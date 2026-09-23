/*****************************************************************************
 * bittorrent.h: BitTorrent streaming through libtorrent (shared declarations)
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

#ifndef MACLC_BITTORRENT_H
#define MACLC_BITTORRENT_H

#include <vlc_common.h>
#include <vlc_tick.h>    /* neither is pulled in by vlc_common.h in C++ */
#include <vlc_threads.h> /* vlc_tick_now() */

#include <cstdint>
#include <deque>
#include <map>
#include <memory>
#include <set>
#include <string>
#include <vector>

#include <boost/shared_array.hpp>

#include <libtorrent/add_torrent_params.hpp>
#include <libtorrent/torrent_handle.hpp>
#include <libtorrent/torrent_info.hpp>

/*
 * One libtorrent session is shared by every torrent the player opens. A
 * torrent stays in it while something reads it, and for a while after, so
 * that the next file of the same torrent (the next episode) starts with its
 * peers already connected. The session itself goes away some time after
 * its last torrent.
 *
 * Everything in Torrent below the handle is guarded by the session lock
 * (Lock()/Unlock()), and every change to it is announced with Broadcast().
 */
namespace maclc_bt
{

/* A piece as libtorrent read it back (read_piece_alert). */
struct PieceData
{
    boost::shared_array<char> data;
    int size = 0;
    bool failed = false;
};

struct Torrent
{
    lt::torrent_handle handle;
    std::string key;                 /* hex of the best info hash */
    std::string save_path;           /* where its files are written */

    int users = 0;                   /* readers and accesses holding it */
    vlc_tick_t idle_since = VLC_TICK_INVALID;

    bool has_metadata = false;
    std::shared_ptr<const lt::torrent_info> info;
    std::vector<char> have;          /* one entry per piece: verified */
    std::vector<int> pending;        /* pieces verified before `have` was known */
    std::vector<int> readers;        /* readers per file */
    std::string error;               /* not empty once the torrent failed */

    int peers = 0;
    int seeds = 0;
    int download_rate = 0;           /* bytes per second, payload */
    int upload_rate = 0;
    int progress_ppm = 0;            /* of what is wanted */

    /* Verified pieces are read through libtorrent, never from the files it
     * writes: a piece is announced once its hash matches, which can be
     * checked from blocks still waiting in memory to be written. */
    std::map<int, PieceData> read_pieces;  /* results, bounded */
    std::deque<int> read_order;            /* oldest result first */
    size_t read_bytes = 0;
    std::set<int> read_requested;          /* read_piece() calls in flight */
};

using TorrentRef = std::shared_ptr<Torrent>;

void Lock();
void Unlock();
/* Waits for a Broadcast() or the deadline, lock held. */
void WaitUntil(vlc_tick_t deadline);
void Broadcast();

/* Returns the torrent in use by the caller (users + 1), adding it to the
 * shared session when it is not there yet. On failure returns nullptr and
 * says why in err. The parameters may come from a .torrent file or a
 * magnet link. */
TorrentRef Acquire(vlc_object_t *obj, lt::add_torrent_params &&params,
                   std::string &err);
void Release(TorrentRef &torrent);

/* The folder the session downloads into (created if needed). */
std::string DownloadDir(vlc_object_t *obj);

/* Log lines the session thread queued; call from a thread that owns obj. */
void FlushLog(vlc_object_t *obj);

std::string KeyFor(const lt::info_hash_t &hashes);

/* Runs a libtorrent call that may throw (an invalid handle does), and says
 * whether it went through. */
template <typename F>
bool Try(F &&call)
{
    try
    {
        call();
        return true;
    }
    catch (...)
    {
        return false;
    }
}

} /* namespace maclc_bt */

#endif
