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

#include <algorithm>
#include <chrono>
#include <condition_variable>
#include <cstdlib>
#include <deque>
#include <map>
#include <mutex>
#include <thread>

#include <ctime>
#include <dirent.h>
#include <sys/stat.h>

#include <libtorrent/alert_types.hpp>
#include <libtorrent/fingerprint.hpp>
#include <libtorrent/session.hpp>
#include <libtorrent/session_params.hpp>
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
            }
            changed = true;
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

void Run(Session *s)
{
    std::vector<lt::alert *> alerts;
    vlc_tick_t next_housekeeping = vlc_tick_now();

    for (;;)
    {
        std::vector<TorrentRef> publish;
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
                end = Housekeep(s, now);
            }
            if (s->quit)
                end = true;
            if (end)
                s->stopping = true;
        }

        /* After the lock is gone: these talk to the network thread. */
        for (const TorrentRef &t : publish)
            PublishMetadata(t);

        if (end)
            break;
    }

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
        std::lock_guard<std::mutex> lock(g_mutex);
        /* From here on Acquire() neither starts nor deletes a session, so
         * s stays valid for the join below. */
        g_exiting = true;
        s = g_session;
        if (s == nullptr)
            return;
        s->quit = true;
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

    try
    {
        lt::session_params params(std::move(pack));
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
            t->save_path = download_dir;
            s->torrents.emplace(key, t);
        }
        t->users++;
        t->idle_since = VLC_TICK_INVALID;
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

} /* namespace maclc_bt */
