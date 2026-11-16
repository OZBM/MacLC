accessdir = $(pluginsdir)/access
access_PLUGINS =
access_LTLIBRARIES =
access_RPATH =

if HAVE_PARTIAL_LINKING
noinst_LTLIBRARIES += $(access_PLUGINS)
else
access_LTLIBRARIES += $(access_PLUGINS)
access_RPATH += -rpath '$(accessdir)'
endif

AM_CPPFLAGS += -I$(srcdir)/access

### Files ###

libdata_plugin_la_SOURCES = access/data.c
access_PLUGINS += libdata_plugin.la

libdcp_plugin_la_SOURCES = access/dcp/dcpparser.h access/dcp/dcp.cpp access/dcp/dcpparser.cpp access/dcp/dcpdecrypt.cpp
if HAVE_ASDCP
libdcp_plugin_la_CPPFLAGS = $(AM_CPPFLAGS) $(ASDCP_CFLAGS) -DASDCPLIB_FACTORY=@ASDCPLIB_FACTORY@
libdcp_plugin_la_LIBADD = $(AM_LIBADD) $(ASDCP_LIBS)
if HAVE_GCRYPT
libdcp_plugin_la_CPPFLAGS += $(GCRYPT_CFLAGS)
libdcp_plugin_la_LIBADD += $(GCRYPT_LIBS)
access_PLUGINS += libdcp_plugin.la
endif
endif

libfilesystem_plugin_la_SOURCES = access/fs.h access/file.c access/directory.c access/fs.c
libfilesystem_plugin_la_CPPFLAGS = $(AM_CPPFLAGS)
access_PLUGINS += libfilesystem_plugin.la

libidummy_plugin_la_SOURCES = access/idummy.c
access_PLUGINS += libidummy_plugin.la

libimem_plugin_la_SOURCES = access/imem-access.c
libimem_plugin_la_LIBADD = $(LIBM)
access_PLUGINS += libimem_plugin.la

libaccess_imem_plugin_la_SOURCES = access/imem.c
access_PLUGINS += libaccess_imem_plugin.la

libsdp_plugin_la_SOURCES = access/sdp.c
access_PLUGINS += libsdp_plugin.la

libtimecode_plugin_la_SOURCES = access/timecode.c
access_PLUGINS += libtimecode_plugin.la

libvdr_plugin_la_SOURCES = access/vdr.c
access_PLUGINS += libvdr_plugin.la

### Audio capture ###

libaccess_jack_plugin_la_SOURCES = access/jack.c
libaccess_jack_plugin_la_CFLAGS = $(AM_CFLAGS) $(JACK_CFLAGS)
libaccess_jack_plugin_la_LIBADD = $(JACK_LIBS)
if HAVE_JACK
access_PLUGINS += libaccess_jack_plugin.la
endif

libavaudiocapture_plugin_la_SOURCES = access/avaudiocapture.m
libavaudiocapture_plugin_la_OBJCFLAGS = $(AM_OBJCFLAGS) -fobjc-arc
libavaudiocapture_plugin_la_LDFLAGS = $(AM_LDFLAGS) $(access_RPATH) -Wl,-framework,Foundation -Wl,-framework,AVFoundation -Wl,-framework,CoreMedia
if HAVE_AVFOUNDATION
access_PLUGINS += libavaudiocapture_plugin.la
endif


### Video capture ###

libavcapture_plugin_la_SOURCES = access/avcapture.m
libavcapture_plugin_la_OBJCFLAGS = $(AM_OBJCFLAGS) -fobjc-arc
libavcapture_plugin_la_LDFLAGS = $(AM_LDFLAGS) $(access_RPATH) -Wl,-framework,Foundation -Wl,-framework,AVFoundation -Wl,-framework,CoreMedia,  -Wl,-framework,CoreVideo
if HAVE_AVFOUNDATION
access_PLUGINS += libavcapture_plugin.la
endif

libdc1394_plugin_la_SOURCES = access/dc1394.c
libdc1394_plugin_la_CFLAGS = $(AM_CFLAGS) $(DC1394_CFLAGS)
libdc1394_plugin_la_LIBADD = $(DC1394_LIBS)
libdc1394_plugin_la_LDFLAGS = $(AM_LDFLAGS) $(access_RPATH)
access_PLUGINS += $(LTLIBdc1394)
EXTRA_LTLIBRARIES += libdc1394_plugin.la

libdecklink_plugin_la_SOURCES = access/decklink.cpp access/sdi.c access/sdi.h access/vlc_decklink.h
libdecklink_plugin_la_CXXFLAGS = $(AM_CXXFLAGS) $(CPPFLAGS_decklink)
libdecklink_plugin_la_LIBADD = $(LIBS_decklink)
if HAVE_WIN32
libdecklink_plugin_la_LIBADD += $(LIBCOM)
libdecklink_plugin_la_CXXFLAGS += $(LIBCOMCXXFLAGS)
endif
if HAVE_LINUX
libdecklink_plugin_la_LIBADD += $(LIBDL)
endif
if HAVE_DECKLINK
access_PLUGINS += libdecklink_plugin.la
endif

libshm_plugin_la_SOURCES = access/shm.c
libshm_plugin_la_LIBADD = $(LIBM)
access_PLUGINS += libshm_plugin.la


### Screen grab ###

if HAVE_MAC_SCREEN
libscreen_plugin_la_SOURCES = access/screen/screen.c access/screen/screen.h \
	access/screen/mac.c
libscreen_plugin_la_LDFLAGS = $(AM_LDFLAGS) "-Wl,-framework,OpenGL,-framework,ApplicationServices"
access_PLUGINS += libscreen_plugin.la
endif

librdp_plugin_la_SOURCES = access/rdp.c
librdp_plugin_la_CFLAGS = $(AM_CFLAGS) $(FREERDP_CFLAGS)
librdp_plugin_la_LIBADD = $(FREERDP_LIBS)
librdp_plugin_la_LDFLAGS = $(AM_LDFLAGS) $(access_RPATH)
access_PLUGINS += $(LTLIBrdp)
EXTRA_LTLIBRARIES += librdp_plugin.la

libvnc_plugin_la_SOURCES = access/vnc.c
libvnc_plugin_la_CFLAGS = $(AM_CFLAGS) $(VNC_CFLAGS)
libvnc_plugin_la_LIBADD = $(VNC_LIBS)
libvnc_plugin_la_LDFLAGS = $(AM_LDFLAGS) $(access_RPATH)
access_PLUGINS += $(LTLIBvnc)
EXTRA_LTLIBRARIES += libvnc_plugin.la


### Optical media ###

libcdda_plugin_la_SOURCES = access/cdda.c access/disc_helper.h access/vcd/cdrom.c access/vcd/cdrom.h \
                            access/vcd/cdrom_internals.h \
                            misc/webservices/json_helper.h misc/webservices/musicbrainz.c \
                            misc/webservices/musicbrainz.h

libcdda_plugin_la_CFLAGS = $(AM_CFLAGS)
libcdda_plugin_la_LIBADD = libvlc_json.la $(LIBM)
libcdda_plugin_la_LDFLAGS = $(AM_LDFLAGS) $(access_RPATH)
if HAVE_DARWIN
libcdda_plugin_la_LIBADD += -liconv
libcdda_plugin_la_LDFLAGS += -Wl,-framework,IOKit,-framework,CoreFoundation
endif
if HAVE_GCRYPT
libcdda_plugin_la_CFLAGS += $(GCRYPT_CFLAGS)
libcdda_plugin_la_LIBADD += $(GCRYPT_LIBS)
endif
EXTRA_LTLIBRARIES += libcdda_plugin.la
access_PLUGINS += $(LTLIBcdda)

libvcd_plugin_la_SOURCES = access/vcd/vcd.c access/vcd/cdrom.c access/vcd/cdrom.h access/vcd/cdrom_internals.h
libvcd_plugin_la_LDFLAGS = $(AM_LDFLAGS) $(access_RPATH)
if HAVE_DARWIN
libvcd_plugin_la_LIBADD = -liconv
libvcd_plugin_la_LDFLAGS += -Wl,-framework,IOKit,-framework,CoreFoundation
endif
EXTRA_LTLIBRARIES += libvcd_plugin.la
access_PLUGINS += $(LTLIBvcd)

libdvdnav_plugin_la_SOURCES = access/disc_helper.h access/dvd_description.h access/dvdnav.c demux/mpeg/ps.h demux/mpeg/pes.h
libdvdnav_plugin_la_CFLAGS = $(AM_CFLAGS) $(DVDNAV_CFLAGS)
libdvdnav_plugin_la_LIBADD = $(DVDNAV_LIBS)
libdvdnav_plugin_la_LDFLAGS = $(AM_LDFLAGS) $(access_RPATH)
if HAVE_DARWIN
libdvdnav_plugin_la_LDFLAGS += -Wl,-framework,IOKit,-framework,CoreFoundation
endif
access_PLUGINS += $(LTLIBdvdnav)
EXTRA_LTLIBRARIES += libdvdnav_plugin.la

libdvdread_plugin_la_SOURCES = access/disc_helper.h access/dvd_description.h access/dvdread.h access/dvdread.c access/dvdread_video.c access/dvdread_audio.c access/dvdread_vr.c demux/mpeg/ps.h demux/mpeg/pes.h \
                               demux/moving_avg.h demux/timestamps_filter.h
libdvdread_plugin_la_CFLAGS = $(AM_CFLAGS) $(DVDREAD_CFLAGS)
libdvdread_plugin_la_LIBADD = $(DVDREAD_LIBS)
libdvdread_plugin_la_LDFLAGS = $(AM_LDFLAGS) $(access_RPATH)
if HAVE_DARWIN
libdvdread_plugin_la_LDFLAGS += -Wl,-framework,IOKit,-framework,CoreFoundation
endif
access_PLUGINS += $(LTLIBdvdread)
EXTRA_LTLIBRARIES += libdvdread_plugin.la

liblibbluray_plugin_la_SOURCES = access/bluray.c demux/mpeg/timestamps.h
liblibbluray_plugin_la_CFLAGS = $(AM_CFLAGS) $(BLURAY_CFLAGS)
liblibbluray_plugin_la_LIBADD = $(BLURAY_LIBS)
liblibbluray_plugin_la_LDFLAGS = $(AM_LDFLAGS) $(access_RPATH)
access_PLUGINS += $(LTLIBlibbluray)
EXTRA_LTLIBRARIES += liblibbluray_plugin.la

### Network streams ###

libftp_plugin_la_SOURCES = access/ftp.c
libftp_plugin_la_LIBADD = $(SOCKET_LIBS)
access_PLUGINS += libftp_plugin.la

libgopher_plugin_la_SOURCES = access/gopher.c
libgopher_plugin_la_LIBADD = $(SOCKET_LIBS)
access_PLUGINS += libgopher_plugin.la

libhttp_plugin_la_SOURCES = access/http.c
libhttp_plugin_la_LIBADD = $(SOCKET_LIBS)
access_PLUGINS += libhttp_plugin.la

libwebdav_plugin_la_SOURCES = access/webdav.c
libwebdav_plugin_la_LIBADD = libvlc_http.la
access_PLUGINS += libwebdav_plugin.la

liblive555_plugin_la_SOURCES = access/live555.cpp access/mms/asf.c access/mms/buffer.c \
                               access/live555_dtsgen.h codec/opus_header.c codec/opus_header.h
liblive555_plugin_la_CXXFLAGS = $(AM_CXXFLAGS) $(CXXFLAGS_live555)
liblive555_plugin_la_LIBADD = $(LIBS_live555) $(SOCKET_LIBS)
liblive555_plugin_la_LDFLAGS = $(AM_LDFLAGS) $(access_RPATH) \
	$(LDFLAGS_live555)
access_PLUGINS += $(LTLIBlive555)
EXTRA_LTLIBRARIES += liblive555_plugin.la

libaccess_mms_plugin_la_SOURCES = \
	access/mms/mms.c access/mms/mms.h \
	access/mms/mmsh.c access/mms/mmsh.h \
	access/mms/mmstu.c access/mms/mmstu.h \
	access/mms/buffer.c access/mms/buffer.h \
	access/mms/asf.h access/mms/asf.c \
	demux/asf/libasf_guid.h
libaccess_mms_plugin_la_CFLAGS = $(AM_CFLAGS)
libaccess_mms_plugin_la_LIBADD = $(SOCKET_LIBS)
access_PLUGINS += libaccess_mms_plugin.la

libsmbc_plugin_la_SOURCES = access/samba.c access/smb_common.h
libsmbc_plugin_la_CFLAGS = $(AM_CFLAGS) $(SMBCLIENT_CFLAGS)
libsmbc_plugin_la_LIBADD = $(SMBCLIENT_LIBS)
libsmbc_plugin_la_LDFLAGS = $(AM_LDFLAGS) $(access_RPATH)
access_PLUGINS += $(LTLIBsmbc)
EXTRA_LTLIBRARIES += libsmbc_plugin.la

libdsm_plugin_la_SOURCES = access/dsm/access.c access/dsm/sd.c access/smb_common.h
libdsm_plugin_la_CFLAGS = $(AM_CFLAGS) $(DSM_CFLAGS)
libdsm_plugin_la_LIBADD = $(DSM_LIBS) libvlc_access_cache.la
if HAVE_DSM
access_PLUGINS += libdsm_plugin.la
endif

libsmb2_plugin_la_SOURCES = access/smb2.c
libsmb2_plugin_la_CFLAGS = $(AM_CFLAGS) $(SMB2_CFLAGS)
libsmb2_plugin_la_LIBADD = $(SMB2_LIBS) $(SOCKET_LIBS) libvlc_access_cache.la
libsmb2_plugin_la_LDFLAGS = $(AM_LDFLAGS) $(access_RPATH)
if HAVE_DSM
libsmb2_plugin_la_CFLAGS += $(DSM_CFLAGS) -DHAVE_DSM
libsmb2_plugin_la_LIBADD += $(DSM_LIBS)
endif
access_PLUGINS += $(LTLIBsmb2)
EXTRA_LTLIBRARIES += libsmb2_plugin.la

libnoidea_plugin_la_SOURCES = access/ndi.c
libnoidea_plugin_la_CFLAGS = $(AM_CFLAGS) $(CFLAGS_noidea)
libnoidea_plugin_la_LIBADD = $(LIBS_noidea) $(SOCKET_LIBS)
libnoidea_plugin_la_LDFLAGS = $(AM_LDFLAGS) $(access_RPATH)
access_LTLIBRARIES += $(LTLIBnoidea)
EXTRA_LTLIBRARIES += libnoidea_plugin.la

libtcp_plugin_la_SOURCES = access/tcp.c
libtcp_plugin_la_LIBADD = $(SOCKET_LIBS)
access_PLUGINS += libtcp_plugin.la

libudp_plugin_la_SOURCES = access/udp.c
libudp_plugin_la_LIBADD = $(SOCKET_LIBS)
access_PLUGINS += libudp_plugin.la

libamt_plugin_la_SOURCES = access/amt.c
libamt_plugin_la_LIBADD = $(SOCKET_LIBS)
access_PLUGINS += libamt_plugin.la

libsftp_plugin_la_SOURCES = access/sftp.c
libsftp_plugin_la_CFLAGS = $(AM_CFLAGS) $(SFTP_CFLAGS)
libsftp_plugin_la_LIBADD = $(SFTP_LIBS)
libsftp_plugin_la_LDFLAGS = $(AM_LDFLAGS) $(access_RPATH)
access_PLUGINS += $(LTLIBsftp)
EXTRA_LTLIBRARIES += libsftp_plugin.la

libnfs_plugin_la_SOURCES = access/nfs.c
libnfs_plugin_la_CFLAGS = $(AM_CFLAGS) $(NFS_CFLAGS)
libnfs_plugin_la_LIBADD = $(NFS_LIBS) $(SOCKET_LIBS)
libnfs_plugin_la_LDFLAGS = $(AM_LDFLAGS) $(access_RPATH)
access_PLUGINS += $(LTLIBnfs)
EXTRA_LTLIBRARIES += libnfs_plugin.la

libavio_plugin_la_SOURCES = access/avio.c access/avio.h
libavio_plugin_la_CFLAGS = $(AM_CFLAGS) $(AVFORMAT_CFLAGS) $(AVUTIL_CFLAGS)
libavio_plugin_la_LDFLAGS = $(AM_LDFLAGS) $(SYMBOLIC_LDFLAGS)
libavio_plugin_la_LIBADD = $(AVFORMAT_LIBS) $(AVUTIL_LIBS) $(LIBM)
if HAVE_AVFORMAT
if !MERGE_FFMPEG
access_PLUGINS += libavio_plugin.la
endif
endif

libsatip_plugin_la_SOURCES = access/satip.c
libsatip_plugin_la_LIBADD = $(SOCKET_LIBS)
access_PLUGINS += libsatip_plugin.la

### Misc ###

libaccess_concat_plugin_la_SOURCES = access/concat.c
access_PLUGINS += libaccess_concat_plugin.la

### SRT ###

libaccess_srt_plugin_la_SOURCES = access/srt.c access/srt_common.c access/srt_common.h
libaccess_srt_plugin_la_CFLAGS = $(AM_CFLAGS) $(SRT_CFLAGS)
libaccess_srt_plugin_la_CPPFLAGS = $(AM_CPPFLAGS) $(SRT_CPPFLAGS)
libaccess_srt_plugin_la_LIBADD = $(SRT_LIBS)
libaccess_srt_plugin_la_LDFLAGS = $(AM_LDFLAGS) $(access_RPATH)
access_PLUGINS += $(LTLIBaccess_srt)
EXTRA_LTLIBRARIES += libaccess_srt_plugin.la

### BitTorrent ###

libbittorrent_plugin_la_SOURCES = access/bittorrent/bittorrent.cpp \
	access/bittorrent/session.cpp access/bittorrent/bittorrent.h
libbittorrent_plugin_la_CPPFLAGS = $(AM_CPPFLAGS) $(BITTORRENT_CFLAGS)
libbittorrent_plugin_la_LIBADD = $(BITTORRENT_LIBS)
libbittorrent_plugin_la_LDFLAGS = $(AM_LDFLAGS) $(access_RPATH)
access_PLUGINS += $(LTLIBbittorrent)
EXTRA_LTLIBRARIES += libbittorrent_plugin.la

### RIST ###

librist_plugin_la_SOURCES = access/rist.c access/rist.h
librist_plugin_la_CFLAGS = $(AM_CFLAGS) $(RIST_CFLAGS)
librist_plugin_la_LIBADD = $(RIST_LIBS) $(SOCKET_LIBS)
librist_plugin_la_LDFLAGS = $(AM_LDFLAGS) $(access_RPATH)
access_PLUGINS += $(LTLIBrist)
EXTRA_LTLIBRARIES += librist_plugin.la

### TOOLS ###

libvlc_access_cache_la_SOURCES = access/cache.c access/cache.h
libvlc_access_cache_la_LIBADD = $(LTLIBVLCCORE)
libvlc_access_cache_la_LDFLAGS = -static
noinst_LTLIBRARIES += libvlc_access_cache.la
