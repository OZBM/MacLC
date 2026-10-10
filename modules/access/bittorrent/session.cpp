/*****************************************************************************
 * session.cpp: the libtorrent session shared by every BitTorrent stream
 *****************************************************************************
 * Copyright (C) 2026 Hazen Studio
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation; either version 2.1 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <vlc_common.h>
#include <vlc_configuration.h>
#include <vlc_fs.h>
#include <vlc_variables.h>

#include <algorithm>
#include <chrono>
#include <cerrno>
#include <condition_variable>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <deque>
#include <map>
#include <mutex>
#include <thread>

#include <ctime>
#include <dirent.h>
#include <unistd.h>
#include <sys/stat.h>

#include <libtorrent/alert_types.hpp>
#include <libtorrent/announce_entry.hpp>
#include <libtorrent/bdecode.hpp>
#include <libtorrent/fingerprint.hpp>
#include <libtorrent/peer_info.hpp>
#include <libtorrent/session.hpp>
#include <libtorrent/session_params.hpp>
#include <libtorrent/session_stats.hpp>
#include <libtorrent/settings_pack.hpp>
#include <libtorrent/torrent_status.hpp>
#include <libtorrent/version.hpp>

#include "bittorrent.h"

namespace maclc_bt
{

namespace
{

/* How long a torrent nobody reads stays in the session, and how long the
 * session outlives its last torrent. */
constexpr vlc_tick_t kTorrentLinger = VLC_TICK_FROM_SEC(60);
constexpr vlc_tick_t kSessionLinger = VLC_TICK_FROM_SEC(30);
constexpr size_t kMaxLogLines = 256;
/* Pieces kept in memory once read back, all torrents' readers included. */
constexpr size_t kMaxReadBytes = 64u << 20;

struct Session
{
    std::unique_ptr<lt::session> ses;
    std::thread thread;
    std::map<std::string, TorrentRef> torrents;
    std::deque<std::string> log;
    std::string download_dir;
    bool keep_files = false;
    vlc_tick_t empty_since = VLC_TICK_INVALID;
    int adding = 0;         /* Acquire() calls adding a torrent right now */
    bool quit = false;      /* the process is exiting */
    bool stopping = false;  /* the thread decided to end the session */
    bool dead = false;      /* ... and has: join it and start over */
    int dht_nodes = -1;     /* DHT routing table size, -1 unknown */
};

/* Constant-initialised: usable from the atexit handler, which runs before
 * these are destroyed since it is registered after they were built. */
std::mutex g_mutex;
std::condition_variable g_cond;
Session *g_session = nullptr;
bool g_atexit_registered = false;
bool g_exiting = false; /* no new session once the process is quitting */

std::chrono::steady_clock::time_point SteadyFromTick(vlc_tick_t deadline)
{
    const vlc_tick_t delay = deadline - vlc_tick_now();
    return std::chrono::steady_clock::now()
         + std::chrono::microseconds(delay > 0 ? US_FROM_VLC_TICK(delay) : 0);
}

void QueueLog(Session *s, std::string line)
{
    if (s->log.size() >= kMaxLogLines)
        s->log.pop_front();
    s->log.push_back(std::move(line));
}

TorrentRef FindByHandle(Session *s, const lt::torrent_handle &handle)
{
    for (auto &entry : s->torrents)
        if (entry.second->handle == handle)
            return entry.second;
    return nullptr;
}

/* Publishes the metadata of a torrent and the pieces it already has. Called
 * without the lock: status() is a round trip to the network thread. */
void PublishMetadata(const TorrentRef &t)
{
    std::shared_ptr<const lt::torrent_info> info;
    lt::torrent_status status;
    if (!Try([&] {
            info = t->handle.torrent_file();
            status = t->handle.status(lt::torrent_handle::query_pieces);
        }) || info == nullptr)
        return;

    std::lock_guard<std::mutex> lock(g_mutex);
    const int pieces = info->num_pieces();
    if (t->name.empty())
        t->name = info->name();
    if (!t->has_metadata)
    {
        t->info = info;
        t->have.assign(pieces, 0);
        t->readers.assign(info->num_files(), 0);
        t->has_metadata = true;
    }
    for (int i = 0; i < pieces && i < status.pieces.size(); i++)
        if (status.pieces[lt::piece_index_t(i)])
            t->have[i] = 1;
    for (int piece : t->pending)
        if (piece >= 0 && piece < pieces)
            t->have[piece] = 1;
    t->pending.clear();
    if (t->first_data_at == VLC_TICK_INVALID
     && std::find(t->have.begin(), t->have.end(), 1) != t->have.end())
        t->first_data_at = vlc_tick_now();
    g_cond.notify_all();
}

void StorePiece(const TorrentRef &t, int piece, PieceData &&data)
{
    /* Lock held. */
    t->read_requested.erase(piece);
    auto old = t->read_pieces.find(piece);
    if (old != t->read_pieces.end())
    {
        t->read_bytes -= old->second.size;
        t->read_pieces.erase(old);
        t->read_order.erase(std::remove(t->read_order.begin(), t->read_order.end(), piece),
                            t->read_order.end());
    }
    t->read_bytes += data.size;
    t->read_pieces.emplace(piece, std::move(data));
    t->read_order.push_back(piece);
    /* Readers copy what they use: the two newest always stay. */
    while (t->read_bytes > kMaxReadBytes && t->read_order.size() > 2)
    {
        const int oldest = t->read_order.front();
        t->read_order.pop_front();
        auto it = t->read_pieces.find(oldest);
        if (it != t->read_pieces.end())
        {
            t->read_bytes -= it->second.size;
            t->read_pieces.erase(it);
        }
    }
}

void HandleAlerts(Session *s, std::vector<lt::alert *> &alerts,
                  std::vector<TorrentRef> &publish)
{
    bool changed = false;
    for (lt::alert *a : alerts)
    {
        if (auto *p = lt::alert_cast<lt::piece_finished_alert>(a))
        {
            TorrentRef t = FindByHandle(s, p->handle);
            if (t == nullptr)
                continue;
            const int piece = static_cast<int>(p->piece_index);
            if (t->has_metadata && piece >= 0 && piece < (int)t->have.size())
                t->have[piece] = 1;
            else
                t->pending.push_back(piece);
            if (t->first_data_at == VLC_TICK_INVALID)
                t->first_data_at = vlc_tick_now();
            changed = true;
        }
        else if (auto *rp = lt::alert_cast<lt::read_piece_alert>(a))
        {
            TorrentRef t = FindByHandle(s, rp->handle);
            if (t == nullptr)
                continue;
            PieceData data;
            data.failed = static_cast<bool>(rp->error);
            if (!data.failed)
            {
                data.data = rp->buffer;
                data.size = rp->size;
            }
            else
                QueueLog(s, rp->message());
            StorePiece(t, static_cast<int>(rp->piece), std::move(data));
            changed = true;
        }
        else if (auto *st = lt::alert_cast<lt::state_update_alert>(a))
        {
            for (const lt::torrent_status &status : st->status)
            {
                TorrentRef t = FindByHandle(s, status.handle);
                if (t == nullptr)
                    continue;
                t->peers = status.num_peers;
                t->seeds = status.num_seeds;
                t->download_rate = status.download_payload_rate;
                t->upload_rate = status.upload_payload_rate;
                t->progress_ppm = status.progress_ppm;
                t->downloaded = status.total_payload_download;
                t->uploaded = status.total_payload_upload;
                t->swarm_seeds = status.num_complete;
                t->swarm_leechers = status.num_incomplete;
            }
            changed = true;
        }
        else if (auto *ss = lt::alert_cast<lt::session_stats_alert>(a))
        {
            static const int dht_nodes = lt::find_metric_idx("dht.dht_nodes");
            if (dht_nodes >= 0)
                s->dht_nodes = static_cast<int>(ss->counters()[dht_nodes]);
        }
        else if (auto *m = lt::alert_cast<lt::metadata_received_alert>(a))
        {
            if (TorrentRef t = FindByHandle(s, m->handle))
                publish.push_back(t);
        }
        else if (auto *c = lt::alert_cast<lt::torrent_checked_alert>(a))
        {
            /* Pieces found on disk by the check are not announced one by
             * one: read them all again. */
            if (TorrentRef t = FindByHandle(s, c->handle))
                publish.push_back(t);
        }
        else if (auto *e = lt::alert_cast<lt::torrent_error_alert>(a))
        {
            if (TorrentRef t = FindByHandle(s, e->handle))
                t->error = e->message();
            QueueLog(s, e->message());
            changed = true;
        }
        else if (auto *fe = lt::alert_cast<lt::file_error_alert>(a))
        {
            if (TorrentRef t = FindByHandle(s, fe->handle))
                t->error = fe->message();
            QueueLog(s, fe->message());
            changed = true;
        }
        else if (lt::alert_cast<lt::metadata_failed_alert>(a)
              || lt::alert_cast<lt::tracker_error_alert>(a)
              || lt::alert_cast<lt::listen_failed_alert>(a)
              || lt::alert_cast<lt::torrent_removed_alert>(a))
        {
            QueueLog(s, a->message());
        }
    }
    if (changed)
        g_cond.notify_all();
}

/* Removes what nobody has read for a while, and says whether the session
 * itself should end. Lock held. */
bool Housekeep(Session *s, vlc_tick_t now)
{
    for (auto it = s->torrents.begin(); it != s->torrents.end();)
    {
        const TorrentRef &t = it->second;
        if (t->users == 0 && t->idle_since != VLC_TICK_INVALID
         && now - t->idle_since > kTorrentLinger)
        {
            const lt::remove_flags_t flags =
                s->keep_files ? lt::remove_flags_t{} : lt::session::delete_files;
            Try([&] { s->ses->remove_torrent(t->handle, flags); });
            QueueLog(s, "removed torrent " + t->key);
            it = s->torrents.erase(it);
        }
        else
            ++it;
    }

    if (!s->torrents.empty() || s->adding > 0)
    {
        s->empty_since = VLC_TICK_INVALID;
        return false;
    }
    if (s->empty_since == VLC_TICK_INVALID)
        s->empty_since = now;
    return now - s->empty_since > kSessionLinger;
}

/* Peers by state and source, and the trackers' state, for the snapshot. Called
 * without the lock: both are round trips to the network thread. */
void RefreshStats(const TorrentRef &t)
{
    std::vector<lt::peer_info> peers;
    std::vector<lt::announce_entry> entries;
    if (!Try([&] {
            t->handle.get_peer_info(peers);
            entries = t->handle.trackers();
        }))
        return;

    int connecting = 0, handshaking = 0, unchoked = 0;
    int tracker = 0, dht = 0, pex = 0, lsd = 0, incoming = 0;
    for (const lt::peer_info &p : peers)
    {
        if (p.flags & lt::peer_info::connecting)
            connecting++;
        else if (p.flags & lt::peer_info::handshake)
            handshaking++;
        else if (!(p.flags & lt::peer_info::remote_choked))
            unchoked++; /* "choked" in libtorrent is the other way round: we choke them */
        /* A peer found by several means counts in each. */
        tracker += (p.source & lt::peer_info::tracker) ? 1 : 0;
        dht += (p.source & lt::peer_info::dht) ? 1 : 0;
        pex += (p.source & lt::peer_info::pex) ? 1 : 0;
        lsd += (p.source & lt::peer_info::lsd) ? 1 : 0;
        incoming += (p.source & lt::peer_info::incoming) ? 1 : 0;
    }

    std::vector<TrackerStat> trackers;
    for (const lt::announce_entry &e : entries)
    {
        if (trackers.size() >= 8)
            break;
        TrackerStat stat;
        stat.url = e.url.substr(0, e.url.find('?')); /* a passkey travels in the query */
        bool updating = false, ok = false, failed = false;
        int seeds = -1, leechers = -1;
        for (const lt::announce_endpoint &ep : e.endpoints)
        {
            if (!ep.enabled)
                continue;
            for (const lt::announce_infohash &ih : ep.info_hashes)
            {
                updating = updating || ih.updating;
                if (ih.start_sent && ih.fails == 0)
                    ok = true;
                if (ih.fails > 0 || ih.last_error)
                {
                    failed = true;
                    stat.message = ih.last_error ? ih.last_error.message() : ih.message;
                }
                else if (stat.message.empty())
                    stat.message = ih.message;
                seeds = std::max(seeds, ih.scrape_complete);
                leechers = std::max(leechers, ih.scrape_incomplete);
            }
        }
        /* One endpoint answering is enough; nothing yet is still "updating". */
        stat.state = ok ? "ok" : updating ? "updating"
                   : (failed || !stat.message.empty()) ? "error" : "updating";
        if (ok && failed)
            stat.message.clear();
        if (seeds >= 0 || leechers >= 0)
            stat.peers = std::max(seeds, 0) + std::max(leechers, 0);
        trackers.push_back(std::move(stat));
    }

    std::lock_guard<std::mutex> lock(g_mutex);
    t->peers_connecting = connecting;
    t->peers_handshaking = handshaking;
    t->peers_unchoked = unchoked;
    t->src_tracker = tracker;
    t->src_dht = dht;
    t->src_pex = pex;
    t->src_lsd = lsd;
    t->src_incoming = incoming;
    t->trackers = std::move(trackers);
}

/* The DHT's routing table, kept for the next launch: a session that starts
 * from it finds peers in seconds instead of bootstrapping from four routers.
 * It lives in the Metadata folder, which ClearLeftovers() spares. */
std::string DhtStatePath(const Session *s)
{
    return s->download_dir + "/Metadata/dht.dat";
}

void SaveDhtState(Session *s)
{
    const std::string path = DhtStatePath(s);
    std::vector<char> buf;
    size_t nodes = 0;
    if (!Try([&] {
            const lt::session_params params =
                s->ses->session_state(lt::session::save_dht_state);
            nodes = params.dht_state.nodes.size() + params.dht_state.nodes6.size();
            buf = lt::write_session_params_buf(params, lt::session::save_dht_state);
        }) || nodes == 0 || buf.empty())
        return; /* an empty table would erase a good file */
    /* A short session knows few nodes: it must not replace a fuller table. */
    if (nodes < 16 && access(path.c_str(), F_OK) == 0)
        return;

    const std::string tmp = path + ".tmp." + std::to_string(getpid());
    if (mkdir((s->download_dir + "/Metadata").c_str(), 0700) != 0 && errno != EEXIST)
        return;
    FILE *f = fopen(tmp.c_str(), "wb");
    if (f == nullptr)
        return;
    fchmod(fileno(f), 0600);
    const bool ok = fwrite(buf.data(), 1, buf.size(), f) == buf.size();
    if (fclose(f) == 0 && ok)
        rename(tmp.c_str(), path.c_str());
    else
        unlink(tmp.c_str());
}

void Run(Session *s)
{
    std::vector<lt::alert *> alerts;
    vlc_tick_t next_housekeeping = vlc_tick_now();
    vlc_tick_t next_refresh = vlc_tick_now();

    for (;;)
    {
        std::vector<TorrentRef> publish, refresh;
        s->ses->wait_for_alert(lt::milliseconds(250));
        s->ses->pop_alerts(&alerts);

        bool end = false;
        {
            std::lock_guard<std::mutex> lock(g_mutex);
            HandleAlerts(s, alerts, publish);

            const vlc_tick_t now = vlc_tick_now();
            if (now >= next_housekeeping)
            {
                next_housekeeping = now + VLC_TICK_FROM_SEC(1);
                s->ses->post_torrent_updates();
                s->ses->post_session_stats(); /* DHT size, for the snapshot */
                end = Housekeep(s, now);
            }
            if (now >= next_refresh)
            {
                next_refresh = now + VLC_TICK_FROM_MS(500);
                for (auto &entry : s->torrents)
                    if (entry.second->users > 0)
                        refresh.push_back(entry.second);
            }
            if (s->quit)
                end = true;
            if (end)
                s->stopping = true;
        }

        /* After the lock is gone: these talk to the network thread. */
        for (const TorrentRef &t : publish)
            PublishMetadata(t);
        if (!end)
            for (const TorrentRef &t : refresh)
                RefreshStats(t);

        if (end)
            break;
    }

    SaveDhtState(s);

    {
        std::lock_guard<std::mutex> lock(g_mutex);
        for (auto &entry : s->torrents)
            if (!s->keep_files)
                Try([&] { s->ses->remove_torrent(entry.second->handle,
                                                  lt::session::delete_files); });
        s->torrents.clear();
    }

    /* Trackers get a second to hear that we leave (stop_tracker_timeout);
     * destroying the proxy waits for the session's threads. */
    {
        lt::session_proxy proxy = s->ses->abort();
        s->ses.reset();
    }

    std::lock_guard<std::mutex> lock(g_mutex);
    s->dead = true;
    g_cond.notify_all();
}

/* The session must be gone before the process tears down the libraries its
 * threads use, and the plugin is never unloaded, so this stays valid. */
void StopAtExit()
{
    Session *s;
    {
        std::unique_lock<std::mutex> lock(g_mutex);
        /* From here on Acquire() neither starts nor deletes a session, so
         * s stays valid for the join below. */
        g_exiting = true;
        s = g_session;
        if (s == nullptr)
            return;
        /* An Acquire() already past that check adds its torrent without the
         * lock: the session must outlive the call. */
        while (s->adding > 0)
            g_cond.wait_for(lock, std::chrono::milliseconds(50));
        s->quit = true;
        /* Leaving a swarm (trackers, port mappings, disk flush) normally
         * takes a second or two; never let it hold the quitting player:
         * past 3 s, end the process here, before libtorrent's own static
         * destructors could run under its still-live threads. libvlc is
         * already released; leftovers are cleared at the next launch. */
        if (!g_cond.wait_for(lock, std::chrono::seconds(3), [s] { return s->dead; }))
        {
            fputs("MacLC: the BitTorrent session did not stop within 3 s, exiting now\n", stderr);
            fflush(stderr); /* not NULL: it would wait for stdin's lock, which a reader may hold forever */
            _exit(EXIT_SUCCESS);
        }
    }
    if (s->thread.joinable())
        s->thread.join();
}

bool MakeDirs(const std::string &path)
{
    std::string partial;
    size_t start = 0;
    while (start <= path.size())
    {
        size_t slash = path.find('/', start);
        if (slash == std::string::npos)
            slash = path.size();
        partial = path.substr(0, slash);
        if (!partial.empty() && vlc_mkdir(partial.c_str(), 0700) != 0 && errno != EEXIST)
            return false;
        start = slash + 1;
    }
    return true;
}

std::string DefaultDownloadDir()
{
    char *cache = config_GetUserDir(VLC_CACHE_DIR);
    if (cache == nullptr)
        return std::string();
    std::string dir = std::string(cache) + "/Torrents";
    free(cache);
    return dir;
}

/* Our own folder only (never a folder the user picked): what a previous run
 * left behind when it did not end cleanly. The metadata cache stays, and so
 * does anything written in the last hour, which another MacLC running at the
 * same time may be playing. */
void ClearLeftovers(const std::string &dir)
{
    const time_t recent = time(NULL) - 3600;
    DIR *d = opendir(dir.c_str());
    if (d == nullptr)
        return;
    std::vector<std::string> names;
    while (struct dirent *e = readdir(d))
    {
        const std::string name = e->d_name;
        if (name == "." || name == ".." || name == "Metadata")
            continue;
        names.push_back(name);
    }
    closedir(d);

    for (const std::string &name : names)
    {
        const std::string path = dir + "/" + name;
        /* Depth-first removal without shelling out. */
        std::vector<std::string> stack{path}, order;
        while (!stack.empty())
        {
            std::string p = stack.back();
            stack.pop_back();
            order.push_back(p);
            struct stat sb;
            if (lstat(p.c_str(), &sb) == 0 && S_ISDIR(sb.st_mode))
                if (DIR *sub = opendir(p.c_str()))
                {
                    while (struct dirent *e = readdir(sub))
                    {
                        const std::string child = e->d_name;
                        if (child != "." && child != "..")
                            stack.push_back(p + "/" + child);
                    }
                    closedir(sub);
                }
        }
        bool in_use = false;
        for (const std::string &p : order)
        {
            struct stat sb;
            if (lstat(p.c_str(), &sb) == 0 && sb.st_mtime > recent)
            {
                in_use = true;
                break;
            }
        }
        if (in_use)
            continue;
        for (auto it = order.rbegin(); it != order.rend(); ++it)
        {
            struct stat sb;
            if (lstat(it->c_str(), &sb) != 0)
                continue;
            if (S_ISDIR(sb.st_mode))
                rmdir(it->c_str());
            else
                unlink(it->c_str());
        }
    }
}

/* The routing table the last session saved, if the file reads back. */
void LoadDhtState(const Session *s, lt::session_params &params)
{
    const std::string path = DhtStatePath(s);
    FILE *f = fopen(path.c_str(), "rb");
    if (f == nullptr)
        return;
    std::vector<char> buf;
    char chunk[4096];
    size_t got;
    while ((got = fread(chunk, 1, sizeof(chunk), f)) > 0 && buf.size() < (1u << 20))
        buf.insert(buf.end(), chunk, chunk + got);
    fclose(f);

    lt::error_code ec;
    const lt::bdecode_node node = lt::bdecode(lt::span<char const>(buf.data(), buf.size()), ec);
    if (ec || node.type() != lt::bdecode_node::dict_t)
    {
        unlink(path.c_str()); /* corrupt: the next session writes a new one */
        return;
    }
    Try([&] {
        params.dht_state = lt::read_session_params(node, lt::session::save_dht_state).dht_state;
    });
}

Session *StartSession(vlc_object_t *obj, std::string &err)
{
    auto s = std::make_unique<Session>();
    s->download_dir = DownloadDir(obj);
    if (s->download_dir.empty())
    {
        err = "no folder to download into";
        return nullptr;
    }
    s->keep_files = var_InheritBool(obj, "bittorrent-keep-files");
    if (!s->keep_files && s->download_dir == DefaultDownloadDir())
        ClearLeftovers(s->download_dir);

    const int port = var_InheritInteger(obj, "bittorrent-port");
    const int upload = var_InheritInteger(obj, "bittorrent-upload-rate");

    lt::settings_pack pack;
    pack.set_int(lt::settings_pack::alert_mask,
                 lt::alert_category::error | lt::alert_category::status
               | lt::alert_category::storage | lt::alert_category::piece_progress
               | lt::alert_category::tracker);
    const std::string listen = "0.0.0.0:" + std::to_string(port)
                             + ",[::]:" + std::to_string(port);
    pack.set_str(lt::settings_pack::listen_interfaces, listen);
    pack.set_str(lt::settings_pack::user_agent,
                 std::string("MacLC/" PACKAGE_VERSION " libtorrent/") + lt::version());
    pack.set_str(lt::settings_pack::peer_fingerprint,
                 lt::generate_fingerprint("ML", 1, 0, 0, 0));
    pack.set_str(lt::settings_pack::dht_bootstrap_nodes,
                 "dht.libtorrent.org:25401,router.bittorrent.com:6881,"
                 "router.utorrent.com:6881,dht.transmissionbt.com:6881");
    pack.set_bool(lt::settings_pack::enable_dht, true);
    pack.set_bool(lt::settings_pack::enable_lsd, true);
    pack.set_bool(lt::settings_pack::enable_upnp, true);
    pack.set_bool(lt::settings_pack::enable_natpmp, true);
    pack.set_bool(lt::settings_pack::announce_to_all_tiers, true);
    pack.set_bool(lt::settings_pack::announce_to_all_trackers, true);
    /* Leaving must not hold up quitting the player. */
    pack.set_int(lt::settings_pack::stop_tracker_timeout, 1);
    /* A player waits on the piece it needs now: give up on slow peers
     * sooner than a download manager would. */
    pack.set_int(lt::settings_pack::peer_connect_timeout, 7);
    pack.set_int(lt::settings_pack::request_timeout, 20);
    pack.set_int(lt::settings_pack::piece_timeout, 10);
    /* Between getting a magnet link's metadata and the first file being
     * asked for, nothing is wanted: libtorrent would drop its seeds as
     * redundant and wait a minute before calling them back. */
    pack.set_bool(lt::settings_pack::close_redundant_connections, false);
    pack.set_int(lt::settings_pack::min_reconnect_time, 5);
    pack.set_int(lt::settings_pack::upload_rate_limit, upload > 0 ? upload * 1024 : 0);

    /* Room for a big swarm (default 200; libtorrent also keeps it under
     * what the process's file limit allows). */
    pack.set_int(lt::settings_pack::connections_limit, 400);
    /* New outgoing connections per second (default 30). */
    pack.set_int(lt::settings_pack::connection_speed, 100);
    /* Several peers can sit behind one NAT address. */
    pack.set_bool(lt::settings_pack::allow_multiple_connections_per_ip, true);
    /* A dead tracker must not delay the first round of announces
     * (default 30 s to give up on a reply). */
    pack.set_int(lt::settings_pack::tracker_completion_timeout, 15);
    pack.set_int(lt::settings_pack::tracker_receive_timeout, 10);
    /* Requests a fast peer may have in flight (default 500) ... */
    pack.set_int(lt::settings_pack::max_out_request_queue, 1500);
    /* ... and the time within which a peer should send a whole piece for it
     * to be asked for whole pieces (default 20 s): only the really fast. */
    pack.set_int(lt::settings_pack::whole_pieces_threshold, 5);

    try
    {
        lt::session_params params(std::move(pack));
        LoadDhtState(s.get(), params);
        s->ses = std::make_unique<lt::session>(std::move(params));
    }
    catch (const std::exception &e)
    {
        err = e.what();
        return nullptr;
    }

    Session *raw = s.release();
    try
    {
        raw->thread = std::thread(Run, raw);
    }
    catch (...)
    {
        err = "could not start the session thread";
        raw->ses.reset();
        delete raw;
        return nullptr;
    }
    if (!g_atexit_registered)
        g_atexit_registered = std::atexit(StopAtExit) == 0;
    return raw;
}

} /* namespace */

void Lock()
{
    g_mutex.lock();
}

void Unlock()
{
    g_mutex.unlock();
}

void WaitUntil(vlc_tick_t deadline)
{
    /* The caller holds g_mutex through Lock(). */
    std::unique_lock<std::mutex> lock(g_mutex, std::adopt_lock);
    g_cond.wait_until(lock, SteadyFromTick(deadline));
    lock.release();
}

void Broadcast()
{
    g_cond.notify_all();
}

std::string KeyFor(const lt::info_hash_t &hashes)
{
    static const char digits[] = "0123456789abcdef";
    /* A hybrid torrent reached through a v1 magnet link and through its
     * metadata must get the same key: prefer v1 whenever there is one
     * (get_best() prefers v2). */
    const lt::sha1_hash best = hashes.has_v1() ? hashes.v1 : hashes.get_best();
    std::string key;
    key.reserve(2 * best.size());
    for (size_t i = 0; i < best.size(); i++)
    {
        const unsigned char c = static_cast<unsigned char>(best[i]);
        key.push_back(digits[c >> 4]);
        key.push_back(digits[c & 15]);
    }
    return key;
}

std::string DownloadDir(vlc_object_t *obj)
{
    std::string dir;
    char *custom = var_InheritString(obj, "bittorrent-dir");
    if (custom != nullptr && *custom != '\0')
        dir = custom;
    free(custom);
    if (dir.empty())
        dir = DefaultDownloadDir();
    if (dir.empty() || !MakeDirs(dir))
        return std::string();
    return dir;
}

void FlushLog(vlc_object_t *obj)
{
    std::deque<std::string> lines;
    {
        std::lock_guard<std::mutex> lock(g_mutex);
        if (g_session != nullptr)
            lines.swap(g_session->log);
    }
    for (const std::string &line : lines)
        msg_Dbg(obj, "libtorrent: %s", line.c_str());
}

namespace
{

/* A magnet link or torrent with few trackers (Torrentio's carry none that
 * answer) gets a few well-known public ones, which find peers within
 * seconds where the DHT alone needs a minute. Never on a private torrent:
 * its tracker is the only one allowed to hear about it. */
void AddDefaultTrackers(lt::add_torrent_params &params)
{
    static const char *const defaults[] = {
        "udp://tracker.opentrackr.org:1337/announce",
        "udp://open.demonii.com:1337/announce",
        "udp://tracker.torrent.eu.org:451/announce",
        "udp://open.stealth.si:80/announce",
        "udp://exodus.desync.com:6969/announce",
        "udp://explodie.org:6969/announce",
        "https://tracker.tamersunion.org:443/announce",
    };
    if (params.ti != nullptr && params.ti->priv())
        return;
    /* load_torrent_*() and parse_magnet_uri() both put the trackers here. */
    if (params.trackers.size() >= 3)
        return;
    const std::vector<std::string> known = params.trackers;
    for (const char *url : defaults)
        if (std::find(known.begin(), known.end(), url) == known.end())
            params.trackers.push_back(url);
}

} /* namespace */

TorrentRef Acquire(vlc_object_t *obj, lt::add_torrent_params &&params,
                   std::string &err)
{
    const std::string key = KeyFor(params.info_hashes);
    Session *s;
    std::string download_dir;
    {
        std::unique_lock<std::mutex> lock(g_mutex);
        if (g_exiting)
        {
            err = "the player is quitting";
            return nullptr;
        }
        /* A session that is winding down cannot take new torrents: wait
         * for it to be gone, then start another. */
        while (g_session != nullptr && g_session->stopping && !g_session->dead)
            g_cond.wait(lock);
        if (g_session != nullptr && g_session->dead)
        {
            if (g_session->thread.joinable())
                g_session->thread.join();
            delete g_session;
            g_session = nullptr;
        }
        if (g_session == nullptr)
        {
            g_session = StartSession(obj, err);
            if (g_session == nullptr)
                return nullptr;
            msg_Dbg(obj, "libtorrent %s session started, downloading into %s",
                    lt::version(), g_session->download_dir.c_str());
        }
        s = g_session;

        auto it = s->torrents.find(key);
        if (it != s->torrents.end())
        {
            TorrentRef t = it->second;
            t->users++;
            t->idle_since = VLC_TICK_INVALID;
            t->last_user_at = vlc_tick_now();
            lock.unlock();
            /* A magnet link can bring trackers and peers the first
             * source did not have. */
            Try([&] {
                for (size_t i = 0; i < params.trackers.size(); i++)
                    t->handle.add_tracker(lt::announce_entry(params.trackers[i]));
                for (const lt::tcp::endpoint &peer : params.peers)
                    t->handle.connect_peer(peer);
            });
            return t;
        }
        download_dir = s->download_dir;
        /* The session must not end between here and the insertion below. */
        s->adding++;
    }

    params.save_path = download_dir;
    const std::string name = !params.name.empty() ? params.name
                           : params.ti != nullptr ? params.ti->name() : std::string();
    AddDefaultTrackers(params);
    params.flags &= ~(lt::torrent_flags::auto_managed | lt::torrent_flags::paused
                    | lt::torrent_flags::duplicate_is_error);
    /* Only what is being played is downloaded: readers ask for pieces with
     * deadlines, which libtorrent fetches whatever the file priority, and
     * rank the rest of their window by priority (PriorityAt() in
     * bittorrent.cpp). In sequential mode the piece picker follows those
     * priorities from the first piece on; otherwise it picks at random
     * until it has four pieces (piece_picker::pick_pieces()). */
    params.flags |= lt::torrent_flags::default_dont_download
                  | lt::torrent_flags::sequential_download;
    if (params.ti != nullptr)
        params.file_priorities.assign(params.ti->num_files(), lt::dont_download);

    lt::error_code ec;
    lt::torrent_handle handle;
    const bool added = Try([&] { handle = s->ses->add_torrent(std::move(params), ec); });
    if (!added || ec)
    {
        err = !added ? "libtorrent refused the torrent" : ec.message();
        std::lock_guard<std::mutex> lock(g_mutex);
        s->adding--;
        return nullptr;
    }

    TorrentRef t;
    {
        std::lock_guard<std::mutex> lock(g_mutex);
        s->adding--;
        auto it = s->torrents.find(key);
        if (it != s->torrents.end())
            t = it->second; /* added by another stream meanwhile */
        else if ((t = FindByHandle(s, handle)) != nullptr)
            ; /* libtorrent knew it under another key: one entry per handle */
        else
        {
            t = std::make_shared<Torrent>();
            t->handle = handle;
            t->key = key;
            t->name = name;
            t->save_path = download_dir;
            t->added_at = vlc_tick_now();
            s->torrents.emplace(key, t);
        }
        t->users++;
        t->idle_since = VLC_TICK_INVALID;
        t->last_user_at = vlc_tick_now();
    }
    PublishMetadata(t);
    FlushLog(obj);
    return t;
}

void Release(TorrentRef &torrent)
{
    if (torrent == nullptr)
        return;
    {
        std::lock_guard<std::mutex> lock(g_mutex);
        if (--torrent->users == 0)
            torrent->idle_since = vlc_tick_now();
    }
    torrent.reset();
}

/*****************************************************************************
 * The snapshot the interface polls (variable "maclc-bt-snapshot")
 *****************************************************************************/

int64_t VerifiedAhead(const Torrent &t, const ReaderStats &r, uint64_t pos)
{
    if (r.piece_length <= 0 || (int64_t)pos >= r.size)
        return 0;
    const int64_t pl = r.piece_length;
    const int start = (int)((r.file_offset + (int64_t)pos) / pl);
    int piece = start;
    while (piece <= r.last_piece && piece < (int)t.have.size() && t.have[piece])
        piece++;
    if (piece == start)
        return 0;
    const int64_t end = std::min<int64_t>(r.size, piece * pl - r.file_offset);
    return std::max<int64_t>(0, end - (int64_t)pos);
}

namespace
{

void JsonString(std::string &out, const std::string &text)
{
    out.push_back('"');
    for (size_t i = 0; i < text.size();)
    {
        const unsigned char c = text[i];
        if (c == '"' || c == '\\')
        {
            out.push_back('\\');
            out.push_back((char)c);
            i++;
        }
        else if (c < 0x20)
        {
            char escape[8];
            snprintf(escape, sizeof(escape), "\\u%04x", c);
            out += escape;
            i++;
        }
        else if (c < 0x80)
        {
            out.push_back((char)c);
            i++;
        }
        else
        {
            /* Names come from the network: anything that is not well-formed
             * UTF-8 becomes U+FFFD, a JSON parser may refuse the lot. */
            const size_t n = c >= 0xF0 ? 4 : c >= 0xE0 ? 3 : c >= 0xC2 ? 2 : 0;
            bool ok = n > 0 && c <= 0xF4 && i + n <= text.size();
            for (size_t k = 1; ok && k < n; k++)
                ok = ((unsigned char)text[i + k] & 0xC0) == 0x80;
            if (ok && n > 2)
            {
                const unsigned char c1 = text[i + 1];
                ok = !(c == 0xE0 && c1 < 0xA0) && !(c == 0xED && c1 >= 0xA0)
                  && !(c == 0xF0 && c1 < 0x90) && !(c == 0xF4 && c1 >= 0x90);
            }
            if (ok)
            {
                out.append(text, i, n);
                i += n;
            }
            else
            {
                out += "\xEF\xBF\xBD";
                i++;
            }
        }
    }
    out.push_back('"');
}

void JsonKey(std::string &out, const char *key)
{
    out.push_back('"');
    out += key;
    out += "\":";
}

void JsonInt(std::string &out, const char *key, int64_t value)
{
    JsonKey(out, key);
    out += std::to_string(value);
}

void JsonText(std::string &out, const char *key, const std::string &value)
{
    JsonKey(out, key);
    JsonString(out, value);
}

/* The verified byte ranges of the reader's file, at most 128: the smallest
 * gaps are closed first. Lock held. */
void JsonRanges(std::string &out, const Torrent &t, const ReaderStats &r)
{
    std::vector<std::pair<int64_t, int64_t>> ranges;
    const int64_t pl = r.piece_length;
    const int last = std::min(r.last_piece, (int)t.have.size() - 1);
    for (int p = std::max(r.first_piece, 0); p <= last && pl > 0;)
    {
        if (!t.have[p])
        {
            p++;
            continue;
        }
        int q = p;
        while (q + 1 <= last && t.have[q + 1])
            q++;
        const int64_t from = std::max<int64_t>(0, p * pl - r.file_offset);
        const int64_t to = std::min<int64_t>(r.size, (q + 1) * pl - r.file_offset);
        if (to > from)
            ranges.emplace_back(from, to);
        p = q + 1;
    }

    constexpr size_t kMaxRanges = 128;
    if (ranges.size() > kMaxRanges)
    {
        std::vector<int64_t> gaps;
        gaps.reserve(ranges.size() - 1);
        for (size_t i = 1; i < ranges.size(); i++)
            gaps.push_back(ranges[i].first - ranges[i - 1].second);
        const size_t close = ranges.size() - kMaxRanges; /* gaps to close */
        std::nth_element(gaps.begin(), gaps.begin() + (close - 1), gaps.end());
        const int64_t limit = gaps[close - 1];
        std::vector<std::pair<int64_t, int64_t>> merged{ranges[0]};
        for (size_t i = 1; i < ranges.size(); i++)
        {
            if (ranges[i].first - merged.back().second <= limit)
                merged.back().second = ranges[i].second;
            else
                merged.push_back(ranges[i]);
        }
        ranges.swap(merged);
    }

    out += "\"ranges\":[";
    for (size_t i = 0; i < ranges.size(); i++)
    {
        if (i > 0)
            out.push_back(',');
        out += "[" + std::to_string(ranges[i].first) + "," + std::to_string(ranges[i].second) + "]";
    }
    out.push_back(']');
}

const char *ReaderStage(const ReaderStats &r, vlc_tick_t now)
{
    if (r.gating)
        return "buffering";
    if (r.wait_since != VLC_TICK_INVALID && now - r.wait_since > VLC_TICK_FROM_MS(400))
        return "stalled";
    return r.fresh ? "ready" : "playing";
}

const char *TorrentStage(const Torrent &t, vlc_tick_t now)
{
    if (!t.error.empty())
        return "error";
    if (!t.has_metadata)
        return t.peers > 0 ? "metadata" : "trackers";
    if (std::find(t.have.begin(), t.have.end(), 1) == t.have.end())
        return "connecting";
    if (t.streams.empty())
        return "downloading";
    return ReaderStage(*t.streams.back(), now);
}

std::string BuildSnapshot()
{
    std::string out;
    out.reserve(4096);
    const vlc_tick_t now = vlc_tick_now();

    std::lock_guard<std::mutex> lock(g_mutex);
    const Session *s = g_session;
    out += "{\"v\":1,";
    JsonInt(out, "now_ms", MS_FROM_VLC_TICK(now));
    out.push_back(',');
    JsonInt(out, "dht_nodes", s != nullptr ? s->dht_nodes : -1);

    std::string active;
    vlc_tick_t newest = VLC_TICK_INVALID;
    if (s != nullptr)
        for (const auto &entry : s->torrents)
        {
            const Torrent &t = *entry.second;
            if (t.users > 0 && (newest == VLC_TICK_INVALID || t.last_user_at > newest))
            {
                newest = t.last_user_at;
                active = t.key;
            }
        }
    out.push_back(',');
    JsonText(out, "active", active);

    out += ",\"torrents\":[";
    bool first = true;
    if (s != nullptr)
        for (const auto &entry : s->torrents)
        {
            const Torrent &t = *entry.second;
            out += first ? "{" : ",{";
            first = false;
            JsonText(out, "key", t.key);
            out.push_back(',');
            JsonText(out, "name", t.name);
            out.push_back(',');
            JsonText(out, "stage", TorrentStage(t, now));
            out.push_back(',');
            JsonText(out, "error", t.error);
            out.push_back(',');
            JsonInt(out, "size", t.info != nullptr ? t.info->total_size() : 0);
            out.push_back(',');
            JsonInt(out, "pieces", t.info != nullptr ? t.info->num_pieces() : 0);
            out.push_back(',');
            JsonInt(out, "piece_size", t.info != nullptr ? t.info->piece_length() : 0);
            out.push_back(',');
            JsonInt(out, "peers", t.peers);
            out.push_back(',');
            JsonInt(out, "seeds", t.seeds);
            out.push_back(',');
            JsonInt(out, "peers_connecting", t.peers_connecting);
            out.push_back(',');
            JsonInt(out, "peers_handshaking", t.peers_handshaking);
            out.push_back(',');
            JsonInt(out, "peers_unchoked", t.peers_unchoked);
            out.push_back(',');
            JsonInt(out, "swarm_seeds", t.swarm_seeds);
            out.push_back(',');
            JsonInt(out, "swarm_leechers", t.swarm_leechers);
            out += ",\"sources\":{";
            JsonInt(out, "tracker", t.src_tracker);
            out.push_back(',');
            JsonInt(out, "dht", t.src_dht);
            out.push_back(',');
            JsonInt(out, "pex", t.src_pex);
            out.push_back(',');
            JsonInt(out, "lsd", t.src_lsd);
            out.push_back(',');
            JsonInt(out, "incoming", t.src_incoming);
            out += "},\"trackers\":[";
            for (size_t i = 0; i < t.trackers.size(); i++)
            {
                const TrackerStat &tr = t.trackers[i];
                out += i > 0 ? ",{" : "{";
                JsonText(out, "url", tr.url);
                out.push_back(',');
                JsonText(out, "state", tr.state);
                out.push_back(',');
                JsonInt(out, "peers", tr.peers);
                out.push_back(',');
                JsonText(out, "message", tr.message);
                out.push_back('}');
            }
            out += "],";
            JsonInt(out, "down", t.download_rate);
            out.push_back(',');
            JsonInt(out, "up", t.upload_rate);
            out.push_back(',');
            JsonInt(out, "downloaded", t.downloaded);
            out.push_back(',');
            JsonInt(out, "uploaded", t.uploaded);
            out.push_back(',');
            JsonInt(out, "uptime_ms", t.added_at != VLC_TICK_INVALID ? MS_FROM_VLC_TICK(now - t.added_at) : 0);
            out.push_back(',');
            JsonInt(out, "first_data_ms", t.first_data_at != VLC_TICK_INVALID && t.added_at != VLC_TICK_INVALID
                                        ? MS_FROM_VLC_TICK(t.first_data_at - t.added_at) : -1);
            out.push_back('}');
        }

    out += "],\"readers\":[";
    first = true;
    if (s != nullptr)
        for (const auto &entry : s->torrents)
        {
            const Torrent &t = *entry.second;
            for (const ReaderStatsRef &ref : t.streams)
            {
                const ReaderStats &r = *ref;
                out += first ? "{" : ",{";
                first = false;
                JsonText(out, "torrent", t.key);
                out.push_back(',');
                JsonText(out, "file", r.file);
                out.push_back(',');
                JsonInt(out, "size", r.size);
                out.push_back(',');
                JsonInt(out, "pos", (int64_t)r.pos);
                out.push_back(',');
                JsonInt(out, "ahead", VerifiedAhead(t, r, r.pos));
                out.push_back(',');
                JsonRanges(out, t, r);
                out.push_back(',');
                JsonInt(out, "window_end", std::clamp<int64_t>(
                            (int64_t)r.window_end * r.piece_length - r.file_offset, 0, r.size));
                out.push_back(',');
                JsonText(out, "stage", ReaderStage(r, now));
                out.push_back(',');
                JsonInt(out, "need", r.need);
                out.push_back(',');
                JsonInt(out, "rate_in", (int64_t)r.rate_in);
                out.push_back(',');
                JsonInt(out, "stall_ms", r.wait_since != VLC_TICK_INVALID
                                       ? MS_FROM_VLC_TICK(now - r.wait_since) : 0);
                out.push_back('}');
            }
        }
    out += "]}";
    return out;
}

/* Called by the interface from its main thread, a few times a second. The
 * caller frees the result with free(). */
static char *MacLCBtSnapshot(void)
{
    try
    {
        return strdup(BuildSnapshot().c_str());
    }
    catch (...)
    {
        return strdup("{\"v\":1,\"now_ms\":0,\"dht_nodes\":-1,\"active\":\"\","
                      "\"torrents\":[],\"readers\":[]}");
    }
}

} /* namespace */

void PublishSnapshot(vlc_object_t *obj)
{
    vlc_object_t *libvlc = VLC_OBJECT(vlc_object_instance(obj));
    /* A second var_Create() would take a second reference; the lock also
     * keeps two streams opening together from both seeing nothing. */
    std::lock_guard<std::mutex> lock(g_mutex);
    if (var_Type(libvlc, "maclc-bt-snapshot") != 0)
        return;
    if (var_Create(libvlc, "maclc-bt-snapshot", VLC_VAR_ADDRESS) == VLC_SUCCESS)
        var_SetAddress(libvlc, "maclc-bt-snapshot", (void *)MacLCBtSnapshot);
}

} /* namespace maclc_bt */
