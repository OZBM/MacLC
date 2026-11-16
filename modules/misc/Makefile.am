miscdir = $(pluginsdir)/misc
misc_PLUGINS =
misc_LTLIBRARIES =
misc_RPATH =
if HAVE_PARTIAL_LINKING
noinst_LTLIBRARIES += $(misc_PLUGINS)
else
misc_LTLIBRARIES += $(misc_PLUGINS)
misc_RPATH += -rpath '$(miscdir)'
endif

libstats_plugin_la_SOURCES = misc/stats.c
misc_PLUGINS += libstats_plugin.la

libaudioscrobbler_plugin_la_SOURCES = misc/audioscrobbler.c
libaudioscrobbler_plugin_la_LIBADD = $(SOCKET_LIBS)
misc_PLUGINS += libaudioscrobbler_plugin.la

libexport_plugin_la_SOURCES = \
	misc/playlist/html.c \
	misc/playlist/m3u.c \
	misc/playlist/xspf.c \
	misc/playlist/export.c
misc_PLUGINS += libexport_plugin.la

libfingerprinter_plugin_la_SOURCES =  \
	misc/webservices/acoustid.c misc/webservices/acoustid.h \
        misc/webservices/json_helper.h \
	misc/fingerprinter.c
libfingerprinter_plugin_la_CPPFLAGS = $(AM_CPPFLAGS) -I$(srcdir)/misc
libfingerprinter_plugin_la_LIBADD = libvlc_json.la $(LIBM)
misc_PLUGINS += libfingerprinter_plugin.la

libgnutls_plugin_la_SOURCES = misc/gnutls.c
libgnutls_plugin_la_CFLAGS = $(AM_CFLAGS) $(GNUTLS_CFLAGS)
libgnutls_plugin_la_LIBADD = $(GNUTLS_LIBS)
if HAVE_WIN32
libgnutls_plugin_la_LIBADD += $(SOCKET_LIBS)
endif
libgnutls_plugin_la_LDFLAGS = $(AM_LDFLAGS) $(misc_RPATH)
if HAVE_DARWIN
libgnutls_plugin_la_LDFLAGS += -Wl,-framework,Security,-framework,CoreFoundation
endif
EXTRA_LTLIBRARIES += libgnutls_plugin.la
misc_PLUGINS += $(LTLIBgnutls)

if HAVE_DARWIN
libsecuretransport_plugin_la_SOURCES = misc/securetransport.c
libsecuretransport_plugin_la_CFLAGS = $(AM_CFLAGS) $(SECURETRANSPORT_CFLAGS)
libsecuretransport_plugin_la_LIBADD = $(SECURETRANSPORT_LIBS)
libsecuretransport_plugin_la_LDFLAGS = $(AM_LDFLAGS) $(misc_RPATH) -Wl,-framework,Security,-framework,CoreFoundation
misc_PLUGINS += libsecuretransport_plugin.la
endif

if HAVE_OSX
libiokit_inhibit_plugin_la_SOURCES = misc/inhibit/iokit-inhibit.c
libiokit_inhibit_plugin_la_LDFLAGS = $(AM_LDFLAGS) -Wl,-framework,CoreFoundation,-framework,IOKit
misc_PLUGINS += libiokit_inhibit_plugin.la
endif

libuikit_inhibit_plugin_la_SOURCES = misc/inhibit/uikit-inhibit.m
libuikit_inhibit_plugin_la_LDFLAGS = $(AM_LDFLAGS) -Wl,-framework,UIKit,-framework,Foundation
libuikit_inhibit_plugin_la_OBJCFLAGS = $(AM_OBJCFLAGS) -fobjc-arc
if HAVE_IOS_OR_TVOS
misc_PLUGINS += libuikit_inhibit_plugin.la
endif
if HAVE_XROS
misc_PLUGINS += libuikit_inhibit_plugin.la
endif

libaddonsvorepository_plugin_la_SOURCES = \
	misc/addons/vorepository.c misc/addons/xmlreading.h
libaddonsfsstorage_plugin_la_SOURCES = \
	misc/addons/fsstorage.c misc/addons/xmlreading.h
if ENABLE_ADDONMANAGERMODULES
misc_PLUGINS += \
	libaddonsvorepository_plugin.la \
	libaddonsfsstorage_plugin.la
endif

libxml_plugin_la_SOURCES = misc/xml/libxml.c
libxml_plugin_la_CFLAGS = $(AM_CFLAGS) $(LIBXML2_CFLAGS)
libxml_plugin_la_LIBADD = $(LIBXML2_LIBS)
libxml_plugin_la_LDFLAGS = $(AM_LDFLAGS) $(misc_RPATH) $(LDFLAGS_xml)
EXTRA_LTLIBRARIES += libxml_plugin.la
misc_PLUGINS += $(LTLIBxml)

libmedialibrary_plugin_la_SOURCES = \
	misc/medialibrary/medialibrary.cpp \
	misc/medialibrary/MetadataExtractor.cpp \
	misc/medialibrary/entities.cpp \
	misc/medialibrary/Thumbnailer.cpp \
	misc/medialibrary/medialibrary.h \
	misc/medialibrary/fs/device.h \
	misc/medialibrary/fs/device.cpp \
	misc/medialibrary/fs/directory.h \
	misc/medialibrary/fs/directory.cpp \
	misc/medialibrary/fs/file.h \
	misc/medialibrary/fs/file.cpp \
	misc/medialibrary/fs/fs.h \
	misc/medialibrary/fs/fs.cpp \
	misc/medialibrary/fs/devicelister.cpp \
	misc/medialibrary/fs/devicelister.h \
	misc/medialibrary/fs/util.h \
	misc/medialibrary/fs/util.cpp

libmedialibrary_plugin_la_CXXFLAGS = $(AM_CXXFLAGS) $(MEDIALIBRARY_CFLAGS)
libmedialibrary_plugin_la_LIBADD = $(MEDIALIBRARY_LIBS)
libmedialibrary_plugin_la_LDFLAGS = $(AM_LDFLAGS) $(misc_RPATH)
EXTRA_LTLIBRARIES += libmedialibrary_plugin.la
misc_PLUGINS += $(LTLIBmedialibrary)

include misc/preparser_serializer/Makefile.am
