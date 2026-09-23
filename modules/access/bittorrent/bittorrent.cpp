/*****************************************************************************
 * bittorrent.cpp: play the files of a torrent while they download
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

/*
 * Three pieces fit together like VLC's archive support:
 *
 * - a stream directory lists the media files of a torrent (a .torrent file,
 *   local or on the web) as sub-items, as if it were a folder;
 * - a stream extractor plays one of those files, "x.torrent#!/path", reading
 *   pieces as libtorrent verifies them and asking for the ones ahead of the
 *   reading position first;
 * - an access for magnet links gets the torrent's metadata from peers and
 *   hands it out as the bytes of a .torrent file, so that the two above work
 *   on "magnet:?xt=...#!/path" too.
 */

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <vlc_common.h>
#include <vlc_plugin.h>
#include <vlc_access.h>
#include <vlc_dialog.h>
#include <vlc_fs.h>
#include <vlc_input_item.h>
#include <vlc_interface.h>
#include <vlc_interrupt.h>
#include <vlc_stream.h>
#include <vlc_stream_extractor.h>

#include <algorithm>
#include <cerrno>
#include <cstring>
#include <functional>
#include <set>


#include <libtorrent/announce_entry.hpp>
#include <libtorrent/load_torrent.hpp>
#include <libtorrent/magnet_uri.hpp>
#include <libtorrent/version.hpp>
#include <libtorrent/write_resume_data.hpp>

#include "bittorrent.h"

using namespace maclc_bt;

static int AccessOpen(vlc_object_t *);
static void AccessClose(vlc_object_t *);
static int DirectoryOpen(vlc_object_t *);
static void DirectoryClose(vlc_object_t *);
static int ExtractorOpen(vlc_object_t *);
static void ExtractorClose(vlc_object_t *);

#define DIR_TEXT N_("Download folder")
#define DIR_LONGTEXT N_("Where torrents are written while they play. Empty: " \
    "a folder in the application's caches.")
#define KEEP_TEXT N_("Keep downloaded files")
#define KEEP_LONGTEXT N_("Keep what was downloaded once a torrent is no " \
    "longer played. Otherwise it is deleted a minute after playback stops.")
#define UPLOAD_TEXT N_("Upload limit (KiB/s)")
#define UPLOAD_LONGTEXT N_("0 for no limit. Peers share more with those who " \
    "share with them.")
#define PORT_TEXT N_("Listening port")
#define PORT_LONGTEXT N_("0 picks a free port each time.")
#define CACHING_TEXT N_("Caching (ms)")
#define CACHING_LONGTEXT N_("How much of a torrent to buffer before playing.")

vlc_module_begin()
    set_shortname(N_("BitTorrent"))
    set_description(N_("BitTorrent magnet links"))
    set_subcategory(SUBCAT_INPUT_ACCESS)
    set_capability("access", 10)
    add_shortcut("magnet")
    set_callbacks(AccessOpen, AccessClose)

    add_directory("bittorrent-dir", NULL, DIR_TEXT, DIR_LONGTEXT)
    add_bool("bittorrent-keep-files", false, KEEP_TEXT, KEEP_LONGTEXT)
    add_integer_with_range("bittorrent-upload-rate", 0, 0, 1000000,
                           UPLOAD_TEXT, UPLOAD_LONGTEXT)
    add_integer_with_range("bittorrent-port", 0, 0, 65535, PORT_TEXT, PORT_LONGTEXT)
    add_integer_with_range("bittorrent-caching", 3000, 0, 60000,
                           CACHING_TEXT, CACHING_LONGTEXT)

    /* The session thread lives past the last stream, and an atexit handler
     * stops it: the code must stay mapped. */
    cannot_unload_broken_library()

    add_submodule()
        set_description(N_("BitTorrent file listing"))
        set_capability("stream_directory", 90)
        set_callbacks(DirectoryOpen, DirectoryClose)

    add_submodule()
        set_description(N_("BitTorrent file streaming"))
        set_capability("stream_extractor", 90)
        set_callbacks(ExtractorOpen, ExtractorClose)
vlc_module_end()

/*****************************************************************************
 * Helpers shared by the three parts
 *****************************************************************************/

namespace
{

/* files() became layout() in libtorrent 2.1. */
const lt::file_storage &FilesOf(const lt::torrent_info &info)
{
#if LIBTORRENT_VERSION_NUM >= 20100
    return info.layout();
#else
    return info.files();
#endif
}

/* A torrent file is a bencoded dictionary with an "info" dictionary. The
 * first byte is cheap to check on every file VLC opens; the rest only when
 * it is a 'd'. */
bool LooksLikeTorrent(stream_t *s)
{
    const uint8_t *peek;
    if (vlc_stream_Peek(s, &peek, 1) < 1 || peek[0] != 'd')
        return false;
    const ssize_t size = vlc_stream_Peek(s, &peek, 1 << 18);
    if (size < 8)
        return false;
    static const char key[] = "4:infod";
    return memmem(peek, size, key, sizeof(key) - 1) != NULL;
}

/* The access at the bottom of a stream chain carries the input's facts. */
stream_t *BottomOf(stream_t *s)
{
    while (s->s != NULL)
        s = s->s;
    return s;
}

bool ReadAll(stream_t *s, std::vector<char> &out)
{
    constexpr size_t kMax = 64u << 20; /* larger than any real .torrent */
    out.clear();
    for (;;)
    {
        const size_t offset = out.size();
        if (offset >= kMax)
            return false;
        out.resize(offset + 65536);
        const ssize_t got = vlc_stream_Read(s, out.data() + offset, 65536);
        if (got <= 0)
        {
            out.resize(offset);
            return got == 0 && !out.empty();
        }
        out.resize(offset + got);
    }
}

bool ParseTorrent(const std::vector<char> &data, lt::add_torrent_params &params,
                  std::string &err)
{
    lt::load_torrent_limits limits;
    limits.max_buffer_size = 64 << 20;
    lt::error_code ec;
    params = lt::load_torrent_buffer(lt::span<char const>(data.data(), data.size()),
                                     ec, limits);
    if (ec)
    {
        err = ec.message();
        return false;
    }
    if (params.ti == nullptr || !params.ti->is_valid())
    {
        err = "no file list";
        return false;
    }
    return true;
}

bool LoadTorrent(stream_t *source, lt::add_torrent_params &params, std::string &err)
{
    std::vector<char> data;
    if (!ReadAll(source, data))
    {
        err = "could not read the torrent";
        return false;
    }
    return ParseTorrent(data, params, err);
}

std::string Lowercase(std::string s)
{
    std::transform(s.begin(), s.end(), s.begin(),
                   [](unsigned char c) { return (char)tolower(c); });
    return s;
}

std::string ExtensionOf(const std::string &path)
{
    const size_t slash = path.rfind('/');
    const size_t dot = path.rfind('.');
    if (dot == std::string::npos || (slash != std::string::npos && dot < slash))
        return std::string();
    return Lowercase(path.substr(dot + 1));
}

std::set<std::string> ExtensionSet(const char *list)
{
    /* "*.avi;*.mkv;..." */
    std::set<std::string> set;
    std::string all(list);
    size_t start = 0;
    while (start < all.size())
    {
        size_t end = all.find(';', start);
        if (end == std::string::npos)
            end = all.size();
        std::string item = all.substr(start, end - start);
        if (item.compare(0, 2, "*.") == 0)
            item.erase(0, 2);
        if (!item.empty())
            set.insert(Lowercase(item));
        start = end + 1;
    }
    return set;
}

bool IsPlayable(const std::string &path)
{
    static const std::set<std::string> media = [] {
        std::set<std::string> set = ExtensionSet(EXTENSIONS_VIDEO ";" EXTENSIONS_AUDIO);
        /* Disc images do not play from a stream. */
        for (const char *ext : { "iso", "bin", "cue", "img" })
            set.erase(ext);
        return set;
    }();
    return media.count(ExtensionOf(path)) > 0;
}

bool IsSubtitle(const std::string &path)
{
    static const std::set<std::string> subtitles = ExtensionSet(EXTENSIONS_SUBTITLE);
    return subtitles.count(ExtensionOf(path)) > 0;
}

/* Containers whose index sits at the end of the file more often than not:
 * the demuxer seeks there right away, so it is fetched early. */
bool WantsTail(const std::string &path)
{
    static const std::set<std::string> tails = {
        "mp4", "m4v", "mov", "3gp", "mkv", "webm", "avi", "wmv", "asf", "flv",
    };
    return tails.count(ExtensionOf(path)) > 0;
}

struct WaitState
{
    bool killed = false;
};

void OnInterrupt(void *data)
{
    WaitState *state = static_cast<WaitState *>(data);
    Lock();
    state->killed = true;
    Unlock();
    Broadcast();
}

enum class Waited { Ready, Stopped, Cancelled, Failed, TimedOut };

/* Waits until ready() holds (called with the session lock held). A progress
 * dialog shows once the wait gets long; *dialog stays up for the caller to
 * release, so that repeated short waits do not make it blink. */
Waited WaitFor(vlc_object_t *obj, const TorrentRef &t,
               const std::function<bool()> &ready,
               const std::function<std::string()> &describe,
               vlc_tick_t timeout, vlc_dialog_id **dialog)
{
    WaitState state;
    vlc_interrupt_register(OnInterrupt, &state);

    const vlc_tick_t start = vlc_tick_now();
    vlc_tick_t next_update = start + VLC_TICK_FROM_MS(1500);
    Waited result = Waited::Ready;

    Lock();
    for (;;)
    {
        if (ready())
            break;
        if (!t->error.empty())
        {
            result = Waited::Failed;
            break;
        }
        if (state.killed || vlc_killed())
        {
            result = Waited::Stopped;
            break;
        }
        vlc_tick_t now = vlc_tick_now();
        if (timeout != VLC_TICK_INVALID && now - start > timeout)
        {
            result = Waited::TimedOut;
            break;
        }
        if (now >= next_update)
        {
            const std::string text = describe();
            Unlock();
            bool cancelled = false;
            if (*dialog == NULL)
                *dialog = vlc_dialog_display_progress(obj, true, 0.f, _("Cancel"),
                                                      _("BitTorrent"), "%s",
                                                      text.c_str());
            else if (vlc_dialog_is_cancelled(obj, *dialog))
                cancelled = true;
            else
                vlc_dialog_update_progress_text(obj, *dialog, 0.f, "%s", text.c_str());
            FlushLog(obj);
            Lock();
            if (cancelled)
            {
                result = Waited::Cancelled;
                break;
            }
            now = vlc_tick_now();
            next_update = now + VLC_TICK_FROM_SEC(1);
        }
        WaitUntil(std::min(next_update, now + VLC_TICK_FROM_MS(250)));
    }
    Unlock();

    vlc_interrupt_unregister();
    return result;
}

std::string Rates(const TorrentRef &t)
{
    /* Lock held. */
    char text[128];
    snprintf(text, sizeof(text), _("%d peers, %.1f MB/s, %d%% downloaded"),
             t->peers, t->download_rate / 1e6, t->progress_ppm / 10000);
    return text;
}

std::string MetadataPath(vlc_object_t *obj, const std::string &key)
{
    const std::string dir = DownloadDir(obj);
    if (dir.empty())
        return std::string();
    const std::string metadata = dir + "/Metadata";
    if (vlc_mkdir(metadata.c_str(), 0700) != 0 && errno != EEXIST)
        return std::string();
    return metadata + "/" + key + ".torrent";
}

bool LoadFile(const std::string &path, std::vector<char> &out)
{
    FILE *f = vlc_fopen(path.c_str(), "rb");
    if (f == NULL)
        return false;
    out.clear();
    char buffer[65536];
    size_t got;
    while ((got = fread(buffer, 1, sizeof(buffer), f)) > 0 && out.size() < (64u << 20))
        out.insert(out.end(), buffer, buffer + got);
    fclose(f);
    return !out.empty();
}

void SaveFile(const std::string &path, const std::vector<char> &data)
{
    const std::string tmp = path + ".part";
    FILE *f = vlc_fopen(tmp.c_str(), "wb");
    if (f == NULL)
        return;
    const bool ok = fwrite(data.data(), 1, data.size(), f) == data.size();
    if (fclose(f) == 0 && ok)
        vlc_rename(tmp.c_str(), path.c_str());
    else
        vlc_unlink(tmp.c_str());
}

/* The torrent as a .torrent file: its metadata plus the trackers and web
 * seeds libtorrent knows now (those of a magnet link included). */
bool SerializeTorrent(const TorrentRef &t, std::vector<char> &out)
{
    lt::add_torrent_params params;
    Lock();
    std::shared_ptr<const lt::torrent_info> info = t->info;
    Unlock();
    if (info == nullptr)
        return false;
    return Try([&] {
        params.ti = std::make_shared<lt::torrent_info>(*info);
        for (const lt::announce_entry &tracker : t->handle.trackers())
        {
            params.trackers.push_back(tracker.url);
            params.tracker_tiers.push_back(tracker.tier);
        }
        for (const std::string &seed : t->handle.url_seeds())
            params.url_seeds.push_back(seed);
        out = lt::write_torrent_file_buf(params, lt::write_flags::allow_missing_piece_layer);
    }) && !out.empty();
}

} /* namespace */

/*****************************************************************************
 * Magnet links: the metadata, as a .torrent file
 *****************************************************************************/

namespace
{

/* Links made by some indexers (Torrentio for Stremio) prefix trackers with
 * "tracker:" and list the info hash itself as a "tracker": libtorrent would
 * reject every one of them and be left with the DHT alone. */
void NormalizeMagnet(lt::add_torrent_params &params)
{
    std::vector<std::string> trackers;
    for (std::string url : params.trackers)
    {
        if (url.compare(0, 8, "tracker:") == 0)
            url.erase(0, 8);
        if (url.find("://") == std::string::npos)
            continue; /* a bare hash, "dht:..." */
        if (std::find(trackers.begin(), trackers.end(), url) == trackers.end())
            trackers.push_back(url);
    }
    params.trackers = std::move(trackers);
    params.tracker_tiers.clear();

    /* A display name is one line. */
    for (char &c : params.name)
        if ((unsigned char)c < 0x20)
            c = ' ';
}

struct MagnetAccess
{
    std::vector<char> metadata;
    uint64_t offset = 0;
    TorrentRef torrent; /* keeps the peers while the input lives */
};

ssize_t MagnetRead(stream_t *access, void *buf, size_t len)
{
    MagnetAccess *sys = static_cast<MagnetAccess *>(access->p_sys);
    if (sys->offset >= sys->metadata.size())
        return 0;
    const size_t n = std::min<size_t>(len, sys->metadata.size() - sys->offset);
    memcpy(buf, sys->metadata.data() + sys->offset, n);
    sys->offset += n;
    return n;
}

int MagnetSeek(stream_t *access, uint64_t offset)
{
    MagnetAccess *sys = static_cast<MagnetAccess *>(access->p_sys);
    sys->offset = offset;
    return VLC_SUCCESS;
}

int MagnetControl(stream_t *access, int query, va_list args)
{
    MagnetAccess *sys = static_cast<MagnetAccess *>(access->p_sys);
    switch (query)
    {
        case STREAM_CAN_SEEK:
        case STREAM_CAN_FASTSEEK:
        case STREAM_CAN_PAUSE:
        case STREAM_CAN_CONTROL_PACE:
            *va_arg(args, bool *) = true;
            return VLC_SUCCESS;
        case STREAM_GET_SIZE:
            *va_arg(args, uint64_t *) = sys->metadata.size();
            return VLC_SUCCESS;
        case STREAM_GET_PTS_DELAY:
            *va_arg(args, vlc_tick_t *) =
                VLC_TICK_FROM_MS(var_InheritInteger(access, "network-caching"));
            return VLC_SUCCESS;
        case STREAM_GET_CONTENT_TYPE:
            *va_arg(args, char **) = strdup("application/x-bittorrent");
            return VLC_SUCCESS;
        case STREAM_SET_PAUSE_STATE:
            return VLC_SUCCESS;
        default:
            return VLC_EGENERIC;
    }
}

} /* namespace */

static int AccessOpen(vlc_object_t *obj)
{
    stream_t *access = (stream_t *)obj;
    if (access->psz_url == NULL || strncasecmp(access->psz_url, "magnet:", 7) != 0)
        return VLC_EGENERIC;

    try
    {
        /* The input rebuilds MRLs as "scheme://location": give libtorrent
         * back the "magnet:?" form it parses. */
        std::string uri = access->psz_url;
        if (uri.compare(0, 9, "magnet://") == 0 || uri.compare(0, 9, "MAGNET://") == 0)
            uri = "magnet:" + uri.substr(9);
        lt::error_code ec;
        lt::add_torrent_params params = lt::parse_magnet_uri(uri, ec);
        if (ec)
        {
            msg_Err(access, "not a usable magnet link: %s", ec.message().c_str());
            return VLC_EGENERIC;
        }
        NormalizeMagnet(params);
        const std::string key = KeyFor(params.info_hashes);
        const std::string cache = MetadataPath(obj, key);

        auto sys = std::make_unique<MagnetAccess>();

        /* Metadata fetched before is kept: a magnet link opened again, or
         * one of its files played later, starts without asking peers. */
        std::vector<char> cached;
        lt::add_torrent_params from_cache;
        std::string err;
        /* The cached metadata may know both hashes of a hybrid torrent
         * when the link names one: either match will do. */
        const lt::info_hash_t &wanted = params.info_hashes;
        bool have_cache = !cache.empty() && LoadFile(cache, cached)
                       && ParseTorrent(cached, from_cache, err);
        if (have_cache)
        {
            const lt::info_hash_t &got = from_cache.ti->info_hashes();
            have_cache = (wanted.has_v1() && got.has_v1() && wanted.v1 == got.v1)
                      || (wanted.has_v2() && got.has_v2() && wanted.v2 == got.v2);
        }

        if (access->b_preparsing)
        {
            /* Never touch the network to preparse. */
            if (!have_cache)
                return VLC_EGENERIC;
            sys->metadata = std::move(cached);
        }
        else
        {
            if (have_cache)
                params.ti = from_cache.ti;
            if (!params.name.empty() && access->p_input_item != NULL)
                input_item_SetName(access->p_input_item, params.name.c_str());
            const std::string name = params.name.empty() ? key : params.name;

            sys->torrent = Acquire(obj, std::move(params), err);
            if (sys->torrent == nullptr)
            {
                msg_Err(access, "cannot add the torrent: %s", err.c_str());
                return VLC_EGENERIC;
            }

            vlc_dialog_id *dialog = NULL;
            const TorrentRef &t = sys->torrent;
            const Waited waited = WaitFor(obj, t,
                [&] { return t->has_metadata; },
                [&] {
                    char text[256];
                    snprintf(text, sizeof(text),
                             _("Getting the details of \"%s\" from peers\n%d peers"),
                             name.c_str(), t->peers);
                    return std::string(text);
                },
                VLC_TICK_FROM_SEC(300), &dialog);
            if (dialog != NULL)
                vlc_dialog_release(obj, dialog);
            FlushLog(obj);

            if (waited != Waited::Ready)
            {
                if (waited == Waited::TimedOut)
                    vlc_dialog_display_error(obj, _("BitTorrent"),
                        _("No peer sent the details of \"%s\" in five minutes."),
                        name.c_str());
                else if (waited == Waited::Failed)
                {
                    Lock();
                    const std::string error = t->error;
                    Unlock();
                    msg_Err(access, "torrent failed: %s", error.c_str());
                }
                Release(sys->torrent);
                return VLC_EGENERIC;
            }

            if (!SerializeTorrent(t, sys->metadata))
            {
                msg_Err(access, "cannot describe the torrent");
                Release(sys->torrent);
                return VLC_EGENERIC;
            }
            if (!cache.empty())
                SaveFile(cache, sys->metadata);
        }

        access->pf_read = MagnetRead;
        access->pf_seek = MagnetSeek;
        access->pf_control = MagnetControl;
        access->p_sys = sys.release();
        return VLC_SUCCESS;
    }
    catch (const std::exception &e)
    {
        msg_Err(access, "%s", e.what());
        return VLC_EGENERIC;
    }
}

static void AccessClose(vlc_object_t *obj)
{
    stream_t *access = (stream_t *)obj;
    MagnetAccess *sys = static_cast<MagnetAccess *>(access->p_sys);
    try
    {
        Release(sys->torrent);
    }
    catch (...)
    {
    }
    delete sys;
}

/*****************************************************************************
 * Listing: the media files of a torrent, as sub-items
 *****************************************************************************/

namespace
{

struct Directory
{
    lt::add_torrent_params params;
};

int ReadDir(stream_directory_t *directory, input_item_node_t *node)
{
    Directory *sys = static_cast<Directory *>(directory->p_sys);
    const lt::file_storage &files = FilesOf(*sys->params.ti);

    /* A torrent of several files keeps them in one folder: its name is the
     * torrent's, and says nothing on each item. */
    std::string prefix;
    if (files.num_files() > 1)
        prefix = sys->params.ti->name() + "/";

    struct vlc_readdir_helper rdh;
    vlc_readdir_helper_init(&rdh, directory, node);

    unsigned playable = 0;
    int ret = VLC_SUCCESS;
    for (const lt::file_index_t i : files.file_range())
    {
        if (files.pad_file_at(i))
            continue;
        const std::string path = files.file_path(i);
        const bool is_media = IsPlayable(path);
        /* Subtitles are handed over too: the helper does not list them
         * but attaches them to the video they belong to. */
        if (!is_media && !IsSubtitle(path))
            continue;

        char *mrl = vlc_stream_extractor_CreateMRL(directory, path.c_str(), NULL, 0);
        if (mrl == NULL)
        {
            ret = VLC_ENOMEM;
            break;
        }
        std::string name = path;
        if (!prefix.empty() && name.compare(0, prefix.size(), prefix) == 0)
            name.erase(0, prefix.size());

        input_item_t *item;
        ret = vlc_readdir_helper_additem(&rdh, mrl, NULL, name.c_str(),
                                         ITEM_TYPE_FILE, ITEM_NET, &item);
        free(mrl);
        if (ret != VLC_SUCCESS)
            break;
        if (item != NULL)
        {
            input_item_AddStat(item, "size", files.file_size(i));
            if (is_media)
                playable++;
        }
    }
    vlc_readdir_helper_finish(&rdh, ret == VLC_SUCCESS);

    if (ret == VLC_SUCCESS && playable == 0)
    {
        msg_Warn(directory, "no media file in torrent \"%s\"",
                 sys->params.ti->name().c_str());
        vlc_dialog_display_error(directory, _("BitTorrent"),
            _("\"%s\" has no video or audio file to play."),
            sys->params.ti->name().c_str());
    }
    return ret;
}

} /* namespace */

static int DirectoryOpen(vlc_object_t *obj)
{
    stream_directory_t *directory = (stream_directory_t *)obj;
    if (!LooksLikeTorrent(directory->source))
        return VLC_EGENERIC;

    try
    {
        auto sys = std::make_unique<Directory>();
        std::string err;
        if (!LoadTorrent(directory->source, sys->params, err))
        {
            msg_Dbg(directory, "not a torrent: %s", err.c_str());
            return VLC_EGENERIC;
        }
        directory->pf_readdir = ReadDir;
        directory->p_sys = sys.release();
        return VLC_SUCCESS;
    }
    catch (const std::exception &e)
    {
        msg_Err(directory, "%s", e.what());
        return VLC_EGENERIC;
    }
}

static void DirectoryClose(vlc_object_t *obj)
{
    stream_directory_t *directory = (stream_directory_t *)obj;
    delete static_cast<Directory *>(directory->p_sys);
}

/*****************************************************************************
 * Streaming: one file of the torrent
 *****************************************************************************/

namespace
{

struct Reader
{
    TorrentRef torrent;
    lt::file_index_t file{0};
    std::string name;             /* path inside the torrent */
    int64_t size = 0;
    int64_t file_offset = 0;      /* where the file starts in the torrent */
    int piece_length = 0;
    int first_piece = 0;
    int last_piece = 0;

    uint64_t pos = 0;
    bool failed = false;

    int cur_piece = -1;           /* the piece being read, kept */
    boost::shared_array<char> cur_data;
    int cur_size = 0;

    int head = -1;                /* piece the window was last placed on */
    int window_end = -1;          /* first piece past the window */
    int tail_first = 0;           /* first piece of the end of the file */
    int seen = -1;                /* piece of the last read */
    std::vector<int> timed;       /* pieces this reader gave a deadline */

    vlc_dialog_id *dialog = NULL;
    input_item_t *item = NULL;    /* not owned */
    vlc_tick_t next_info = VLC_TICK_INVALID;
};

/* How far ahead of the reading position pieces get deadlines, and how far
 * apart the deadlines are: bytes and time, whatever the piece size. */
int WindowPieces(int piece_length)
{
    const int64_t window = 48ll << 20;
    return (int)std::clamp<int64_t>((window + piece_length - 1) / piece_length, 4, 256);
}

int DeadlineStep(int piece_length)
{
    return std::clamp(piece_length / 2048, 20, 2000); /* ms, ~2 MB/s */
}

int PieceOf(const Reader *r, uint64_t pos)
{
    return (int)((r->file_offset + (int64_t)pos) / r->piece_length);
}

void SetPriority(const lt::torrent_handle &h, const std::vector<int> &pieces,
                 lt::download_priority_t priority)
{
    if (pieces.empty())
        return;
    std::vector<std::pair<lt::piece_index_t, lt::download_priority_t>> list;
    list.reserve(pieces.size());
    for (int k : pieces)
        list.emplace_back(lt::piece_index_t(k), priority);
    h.prioritize_pieces(list);
}

/* Takes back the deadlines this reader gave to pieces still missing, and
 * returns those pieces. Other readers of the torrent keep theirs, which
 * clear_piece_deadlines() would take too: an external audio track would
 * lose its pieces each time the video seeks, and wait for them forever. */
std::vector<int> Untime(Reader *r)
{
    std::vector<int> pending;
    Lock();
    for (int k : r->timed)
        if (!r->torrent->have[k])
            pending.push_back(k);
    Unlock();
    std::sort(pending.begin(), pending.end());
    pending.erase(std::unique(pending.begin(), pending.end()), pending.end());
    r->timed.clear();
    Try([&] {
        for (int k : pending)
            r->torrent->handle.reset_piece_deadline(lt::piece_index_t(k));
    });
    return pending;
}

/* Pieces a reader stops wanting. The first and the last piece of its file
 * can hold the end or the start of another file, which someone else may be
 * reading: those keep their priority. */
void Drop(Reader *r, const std::vector<int> &pieces)
{
    std::vector<int> dropped;
    for (int k : pieces)
        if (k != r->first_piece && k != r->last_piece)
            dropped.push_back(k);
    Try([&] { SetPriority(r->torrent->handle, dropped, lt::dont_download); });
}

/* A read near the end of the file while the window is elsewhere: a demuxer
 * reading an index (the moov of an MP4, the cues of a Matroska file, the
 * idx1 of an AVI). Its pieces come first, and the window stays where it
 * is: the reader comes back to it. */
void Detour(Reader *r, int piece)
{
    const int step = DeadlineStep(r->piece_length);
    std::vector<int> pieces;
    Lock();
    for (int k = piece; k <= r->last_piece && pieces.size() < 4; k++)
        if (!r->torrent->have[k])
            pieces.push_back(k);
    Unlock();
    Try([&] {
        int deadline = 0;
        for (int k : pieces)
        {
            r->torrent->handle.set_piece_deadline(lt::piece_index_t(k), deadline);
            deadline += step;
        }
    });
    r->timed.insert(r->timed.end(), pieces.begin(), pieces.end());
}

/* The priority of a piece `distance` pieces ahead of the reader: 7 for the
 * one being waited for, then one step lower each time the distance doubles
 * (6 for the next 2, 5 for the next 4...), down to 1.
 *
 * libtorrent requests deadline pieces once a second only. In between, its
 * piece picker keeps the peers' queues full on its own, from the highest
 * priority down, in no particular order within a priority. With the whole
 * window at the top priority that set_piece_deadline() gives, it fetched
 * pieces far ahead while the reader waited for the next one. The
 * sequential mode would fix that, but libtorrent 2.1.1 does not extend its
 * range when a piece goes from priority 0 to more (piece_picker.cpp,
 * set_piece_priority(), unlike 2.0), and every piece starts at 0 here. */
lt::download_priority_t PriorityAt(int distance)
{
    int level = 7;
    for (int d = distance + 1; d > 1 && level > 1; d >>= 1)
        level--;
    return lt::download_priority_t(static_cast<std::uint8_t>(level));
}

/* Moves the window of deadlines to `piece`. Reading on moves it forward by
 * one piece; anything else is a seek, which places it again and drops what
 * it left behind. */
void Schedule(Reader *r, int piece)
{
    if (piece == r->head || piece == r->seen)
        return;
    r->seen = piece;

    const int count = WindowPieces(r->piece_length);
    const int step = DeadlineStep(r->piece_length);

    if (r->head >= 0 && piece != r->head + 1)
    {
        /* Where the reader lands may be here already (a demuxer going back
         * to a keyframe, or reading an index again): what counts is the
         * first piece still missing from there. */
        const int last = std::min(r->last_piece, piece + count - 1);
        int missing = -1;
        Lock();
        for (int k = piece; k <= last && missing < 0; k++)
            if (!r->torrent->have[k])
                missing = k;
        Unlock();
        if (missing < 0)
            return;
        if (missing != piece && missing >= r->head && missing < r->window_end)
            return; /* back to the window */
        if (missing >= r->tail_first && r->head < r->tail_first)
        {
            Detour(r, missing);
            return;
        }
        piece = missing;
        if (piece == r->head)
            return;
    }

    const bool jump = r->head < 0 || piece != r->head + 1;
    const int end = std::min(r->last_piece + 1, piece + count);

    /* A seek takes every deadline of this reader back first: when no piece
     * of the torrent has one any more, the next deadline makes libtorrent
     * cancel the requests already sent for pieces without one
     * (torrent::cancel_non_critical()), so the data left behind stops
     * arriving before the data needed now. */
    std::vector<int> dropped;
    if (jump && r->head >= 0)
        for (int k : Untime(r))
            if (k < piece || k >= end)
                dropped.push_back(k);

    std::vector<std::pair<int, int>> deadlines;
    std::vector<std::pair<lt::piece_index_t, lt::download_priority_t>> priorities;
    Lock();
    const int from = jump ? piece : std::max(r->window_end, piece);
    if (!jump && !r->torrent->have[piece])
        deadlines.emplace_back(piece, 0); /* now the most urgent one */
    for (int k = from; k < end; k++)
        if (!r->torrent->have[k])
            deadlines.emplace_back(k, (k - piece) * step);
    for (int k = piece + 1; k < end; k++)
        if (!r->torrent->have[k])
            priorities.emplace_back(lt::piece_index_t(k), PriorityAt(k - piece));
    Unlock();

    r->head = piece;
    r->window_end = jump ? end : std::max(r->window_end, end);

    Drop(r, dropped);
    const lt::torrent_handle &h = r->torrent->handle;
    Try([&] {
        for (const auto &d : deadlines)
            h.set_piece_deadline(lt::piece_index_t(d.first), d.second);
        if (!priorities.empty())
            h.prioritize_pieces(priorities);
    });
    for (const auto &d : deadlines)
        r->timed.push_back(d.first);
    if (r->timed.size() > 1024)
    {
        /* Reading on only adds: forget what arrived. */
        Lock();
        r->timed.erase(std::remove_if(r->timed.begin(), r->timed.end(),
                                      [&](int k) { return r->torrent->have[k] != 0; }),
                       r->timed.end());
        Unlock();
    }
}

/* The end of a file (the index of an MP4 or the cues of a Matroska file)
 * comes right after its start. */
void PrefetchTail(Reader *r)
{
    const int64_t tail = std::min<int64_t>(r->size, std::clamp<int64_t>(r->size / 100, 1ll << 20, 4ll << 20));
    const int from = PieceOf(r, r->size - tail);
    const int step = DeadlineStep(r->piece_length);
    std::vector<int> pieces;
    Lock();
    for (int k = std::max(from, r->first_piece); k <= r->last_piece; k++)
        if (!r->torrent->have[k])
            pieces.push_back(k);
    Unlock();
    Try([&] {
        int deadline = 1000;
        for (int k : pieces)
        {
            r->torrent->handle.set_piece_deadline(lt::piece_index_t(k), deadline);
            deadline += step;
        }
        /* Needed right after the first piece, before the rest of the
         * window. */
        SetPriority(r->torrent->handle, pieces, PriorityAt(1));
    });
    r->timed.insert(r->timed.end(), pieces.begin(), pieces.end());
}

void UpdateInfo(stream_extractor_t *extractor, Reader *r)
{
    if (r->item == NULL)
        return;
    const vlc_tick_t now = vlc_tick_now();
    if (r->next_info != VLC_TICK_INVALID && now < r->next_info)
        return;
    r->next_info = now + VLC_TICK_FROM_SEC(2);

    Lock();
    const int peers = r->torrent->peers, seeds = r->torrent->seeds;
    const int down = r->torrent->download_rate, up = r->torrent->upload_rate;
    const int progress = r->torrent->progress_ppm;
    Unlock();

    const char *category = _("BitTorrent");
    input_item_AddInfo(r->item, category, _("Peers"), "%d (%d seeds)", peers, seeds);
    input_item_AddInfo(r->item, category, _("Download speed"), "%.1f MB/s", down / 1e6);
    input_item_AddInfo(r->item, category, _("Upload speed"), "%.1f MB/s", up / 1e6);
    input_item_AddInfo(r->item, category, _("Downloaded"), "%d%%", progress / 10000);
    FlushLog(VLC_OBJECT(extractor));
}

/* Waits for the piece to be verified, then for libtorrent to read it back,
 * and keeps it in the reader. */
bool FetchPiece(stream_extractor_t *extractor, Reader *r, int piece)
{
    const TorrentRef &t = r->torrent;
    auto buffering = [&] {
        return std::string(_("Buffering")) + " \"" + r->name + "\"\n" + Rates(t);
    };

    const vlc_tick_t start = vlc_tick_now();
    Waited waited = WaitFor(VLC_OBJECT(extractor), t,
                            [&] { return t->have[piece] != 0; }, buffering,
                            VLC_TICK_INVALID, &r->dialog);
    const vlc_tick_t waited_for = vlc_tick_now() - start;
    if (waited == Waited::Ready && waited_for > VLC_TICK_FROM_MS(100))
    {
        Lock();
        const int peers = t->peers, rate = t->download_rate;
        Unlock();
        msg_Dbg(extractor, "waited %" PRId64 " ms for piece %d (%d peers, %d kB/s)",
                MS_FROM_VLC_TICK(waited_for), piece, peers, rate / 1000);
    }

    /* A result can be evicted by other readers before this one copies it:
     * ask again then, a few times. */
    for (int attempt = 0; waited == Waited::Ready && attempt < 4; attempt++)
    {
        bool request = false;
        Lock();
        auto it = t->read_pieces.find(piece);
        if (it != t->read_pieces.end())
        {
            const PieceData data = it->second;
            Unlock();
            if (data.failed)
            {
                msg_Err(extractor, "libtorrent could not read piece %d", piece);
                r->failed = true;
                return false;
            }
            r->cur_piece = piece;
            r->cur_data = data.data;
            r->cur_size = data.size;
            if (r->dialog != NULL)
            {
                vlc_dialog_release(VLC_OBJECT(extractor), r->dialog);
                r->dialog = NULL;
            }
            return true;
        }
        if (t->read_requested.insert(piece).second)
            request = true;
        Unlock();

        if (request && !Try([&] { t->handle.read_piece(lt::piece_index_t(piece)); }))
        {
            Lock();
            t->read_requested.erase(piece);
            Unlock();
            r->failed = true;
            return false;
        }
        waited = WaitFor(VLC_OBJECT(extractor), t,
                         [&] { return t->read_pieces.count(piece) > 0; }, buffering,
                         VLC_TICK_INVALID, &r->dialog);
    }

    if (waited == Waited::Failed)
    {
        Lock();
        const std::string error = t->error;
        Unlock();
        msg_Err(extractor, "torrent failed: %s", error.c_str());
    }
    /* Stopped: the input is going away, or a stream filter above woke us
     * up; neither is a failure of the torrent. */
    if (waited != Waited::Stopped)
        r->failed = true;
    return false;
}

ssize_t ExtractorRead(stream_extractor_t *extractor, void *buf, size_t len)
{
    Reader *r = static_cast<Reader *>(extractor->p_sys);
    if (r->failed)
        return -1;
    if (r->pos >= (uint64_t)r->size || len == 0)
        return 0;

    try
    {
        const int piece = PieceOf(r, r->pos);
        Schedule(r, piece);

        if (piece != r->cur_piece && !FetchPiece(extractor, r, piece))
            return -1;

        /* Where the piece starts, counted in the file: before the file
         * for the first piece when the file does not start on a piece. */
        const int64_t piece_start = (int64_t)piece * r->piece_length - r->file_offset;
        const int64_t in_piece = (int64_t)r->pos - piece_start;
        const int64_t available = std::min<int64_t>(r->cur_size - in_piece,
                                                    r->size - (int64_t)r->pos);
        if (in_piece < 0 || available <= 0)
        {
            msg_Err(extractor, "piece %d does not cover offset %" PRIu64, piece, r->pos);
            r->failed = true;
            return -1;
        }
        const size_t n = (size_t)std::min<int64_t>((int64_t)len, available);
        memcpy(buf, r->cur_data.get() + in_piece, n);
        r->pos += n;
        UpdateInfo(extractor, r);
        return n;
    }
    catch (const std::exception &e)
    {
        msg_Err(extractor, "%s", e.what());
        r->failed = true;
        return -1;
    }
}

int ExtractorSeek(stream_extractor_t *extractor, uint64_t pos)
{
    Reader *r = static_cast<Reader *>(extractor->p_sys);
    r->pos = pos;
    /* The window moves on the next read, when it is known that the data
     * there is really wanted. */
    return VLC_SUCCESS;
}

int ExtractorControl(stream_extractor_t *extractor, int query, va_list args)
{
    Reader *r = static_cast<Reader *>(extractor->p_sys);
    switch (query)
    {
        case STREAM_CAN_SEEK:
        case STREAM_CAN_PAUSE:
        case STREAM_CAN_CONTROL_PACE:
            *va_arg(args, bool *) = true;
            return VLC_SUCCESS;
        case STREAM_CAN_FASTSEEK:
            /* Seeking itself costs nothing; the data is fetched ahead by
             * libtorrent already (the window of deadlines). Saying so keeps
             * the prefetch filter out: its thread would sit in a read at the
             * old position, waiting for a piece, before it saw a seek. It
             * also lets the Matroska demuxer read its index at the end. */
            *va_arg(args, bool *) = true;
            return VLC_SUCCESS;
        case STREAM_GET_SIZE:
            *va_arg(args, uint64_t *) = r->size;
            return VLC_SUCCESS;
        case STREAM_GET_PTS_DELAY:
            *va_arg(args, vlc_tick_t *) =
                VLC_TICK_FROM_MS(var_InheritInteger(extractor, "bittorrent-caching"));
            return VLC_SUCCESS;
        case STREAM_SET_PAUSE_STATE:
            return VLC_SUCCESS;
        default:
            /* Not the source's answers: its content type is the torrent's. */
            return VLC_EGENERIC;
    }
}

int FindFile(const lt::file_storage &files, const char *identifier)
{
    if (identifier == NULL)
        return -1;
    const std::string wanted = identifier[0] == '/' ? identifier + 1 : identifier;
    int by_name = -1, matches = 0;
    for (const lt::file_index_t i : files.file_range())
    {
        if (files.pad_file_at(i))
            continue;
        const std::string path = files.file_path(i);
        if (path == wanted)
            return static_cast<int>(i);
        const size_t slash = path.rfind('/');
        const std::string base = slash == std::string::npos ? path : path.substr(slash + 1);
        if (base == wanted)
        {
            by_name = static_cast<int>(i);
            matches++;
        }
    }
    return matches == 1 ? by_name : -1;
}

} /* namespace */

static int ExtractorOpen(vlc_object_t *obj)
{
    stream_extractor_t *extractor = (stream_extractor_t *)obj;
    if (!LooksLikeTorrent(extractor->source))
        return VLC_EGENERIC;

    stream_t *access = BottomOf(extractor->source);
    if (access->b_preparsing)
    {
        /* Preparsing would start a download to read a duration. */
        msg_Dbg(extractor, "not streaming a torrent to preparse it");
        return VLC_EGENERIC;
    }

    try
    {
        lt::add_torrent_params params;
        std::string err;
        if (!LoadTorrent(extractor->source, params, err))
        {
            msg_Dbg(extractor, "not a torrent: %s", err.c_str());
            return VLC_EGENERIC;
        }
        const lt::file_storage &files = FilesOf(*params.ti);
        const int index = FindFile(files, extractor->identifier);
        if (index < 0)
        {
            msg_Err(extractor, "no file \"%s\" in torrent \"%s\"",
                    extractor->identifier, params.ti->name().c_str());
            return VLC_EGENERIC;
        }

        auto r = std::make_unique<Reader>();
        r->file = lt::file_index_t(index);
        r->name = files.file_path(r->file);
        r->size = files.file_size(r->file);
        r->file_offset = files.file_offset(r->file);
        r->piece_length = params.ti->piece_length();
        r->first_piece = (int)(r->file_offset / r->piece_length);
        r->last_piece = r->size > 0
                      ? (int)((r->file_offset + r->size - 1) / r->piece_length)
                      : r->first_piece;
        /* A read in the last 16 MiB while the window is elsewhere is taken
         * for a demuxer reading an index there, not for a seek. */
        r->tail_first = PieceOf(r.get(), r->size - std::min<int64_t>(r->size, 16ll << 20));
        r->item = access->p_input_item;
        const std::string name = r->name;

        r->torrent = Acquire(obj, std::move(params), err);
        if (r->torrent == nullptr)
        {
            msg_Err(extractor, "cannot add the torrent: %s", err.c_str());
            return VLC_EGENERIC;
        }
        const TorrentRef &t = r->torrent;

        /* Added from its metadata, it has it at once; a magnet added by the
         * access has it too by now. Wait a little in case of a race. */
        vlc_dialog_id *dialog = NULL;
        const Waited waited = WaitFor(obj, t, [&] { return t->has_metadata; },
                                      [&] { return name; },
                                      VLC_TICK_FROM_SEC(30), &dialog);
        if (dialog != NULL)
            vlc_dialog_release(obj, dialog);
        Lock();
        const bool consistent = waited == Waited::Ready
                             && (int)t->have.size() > r->last_piece
                             && (int)t->readers.size() > index;
        if (consistent)
            t->readers[index]++;
        Unlock();
        if (!consistent)
        {
            msg_Err(extractor, "the torrent's metadata is not usable");
            Release(r->torrent);
            return VLC_EGENERIC;
        }

        /* The file stays at priority 0: only pieces with a deadline (the
         * window ahead of the reader and the end of the file) are asked
         * for, so peers serve them in deadline order. A file downloaded at
         * normal priority fills the peers' request queues with pieces the
         * player does not need yet, and the one it waits for comes last
         * (set_piece_deadline raises its piece to the top priority). */
        Schedule(r.get(), r->first_piece);
        if (WantsTail(name))
            PrefetchTail(r.get());

        msg_Dbg(extractor, "streaming \"%s\" (%" PRId64 " bytes, pieces %d-%d of %d KiB)",
                name.c_str(), r->size, r->first_piece, r->last_piece,
                r->piece_length / 1024);

        extractor->pf_read = ExtractorRead;
        extractor->pf_seek = ExtractorSeek;
        extractor->pf_control = ExtractorControl;
        extractor->p_sys = r.release();
        return VLC_SUCCESS;
    }
    catch (const std::exception &e)
    {
        msg_Err(extractor, "%s", e.what());
        return VLC_EGENERIC;
    }
}

static void ExtractorClose(vlc_object_t *obj)
{
    stream_extractor_t *extractor = (stream_extractor_t *)obj;
    Reader *r = static_cast<Reader *>(extractor->p_sys);

    if (r->dialog != NULL)
        vlc_dialog_release(obj, r->dialog);

    try
    {
        const int index = static_cast<int>(r->file);
        Lock();
        bool nobody = false, alone = true;
        if (index < (int)r->torrent->readers.size())
        {
            alone = --r->torrent->readers[index] == 0;
            nobody = std::all_of(r->torrent->readers.begin(), r->torrent->readers.end(),
                                 [](int n) { return n == 0; });
        }
        Unlock();

        /* Stop fetching what nobody plays any more. */
        if (alone)
            Drop(r, Untime(r));
        if (nobody)
            Try([&] { r->torrent->handle.clear_piece_deadlines(); });

        Release(r->torrent);
    }
    catch (...)
    {
    }
    delete r;
}
