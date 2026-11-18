aoutdir = $(pluginsdir)/audio_output
aout_PLUGINS =
aout_LTLIBRARIES =
aout_RPATH =

if HAVE_PARTIAL_LINKING
noinst_LTLIBRARIES += $(aout_PLUGINS)
else
aout_LTLIBRARIES += $(aout_PLUGINS)
aout_RPATH += -rpath '$(aoutdir)'
endif


# Install the pkglib/pkglibexec first before relinking the modules.
# This ensures libtool re-linking is not racy.
installaoutLTLIBRARIES = install-aoutLTLIBRARIES
$(installaoutLTLIBRARIES): install-pkglibLTLIBRARIES

libadummy_plugin_la_SOURCES = audio_output/adummy.c

libafile_plugin_la_SOURCES = audio_output/file.c
libafile_plugin_la_CPPFLAGS = $(AM_CPPFLAGS)

libamem_plugin_la_SOURCES = audio_output/amem.c

aout_PLUGINS += \
	libadummy_plugin.la \
	libafile_plugin.la \
	libamem_plugin.la

libjack_plugin_la_SOURCES = audio_output/jack.c audio_output/volume.h
libjack_plugin_la_CFLAGS = $(AM_CFLAGS) $(JACK_CFLAGS)
libjack_plugin_la_LIBADD = $(JACK_LIBS) $(LIBM)
if HAVE_JACK
aout_PLUGINS += libjack_plugin.la
endif

libavsamplebuffer_plugin_la_SOURCES = audio_output/apple/avsamplebuffer.m \
	audio_output/apple/channel_layout.c \
	audio_output/apple/eac3_dec3.c
if HAVE_OSX
libavsamplebuffer_plugin_la_SOURCES += audio_output/apple/atmos_prime.m
endif
if HAVE_IOS
libavsamplebuffer_plugin_la_SOURCES += audio_output/apple/avaudiosession_common.m
endif
if HAVE_TVOS
libavsamplebuffer_plugin_la_SOURCES += audio_output/apple/avaudiosession_common.m
endif
if HAVE_XROS
libavsamplebuffer_plugin_la_SOURCES += audio_output/apple/avaudiosession_common.m
endif
if HAVE_WATCHOS
libavsamplebuffer_plugin_la_SOURCES += audio_output/apple/avaudiosession_common.m
endif
libavsamplebuffer_plugin_la_LDFLAGS = $(AM_LDFLAGS) \
	-Wl,-framework,CoreMedia,-framework,Foundation,-framework,AVFoundation \
	-Wl,-framework,CoreAudio
libavsamplebuffer_plugin_la_OBJCFLAGS = $(AM_OBJCFLAGS) -fobjc-arc

libauhal_plugin_la_SOURCES = audio_output/apple/auhal.c \
	audio_output/apple/coreaudio_common.c audio_output/apple/coreaudio_common.h \
	audio_output/apple/channel_layout.c

libauhal_plugin_la_LDFLAGS = $(AM_LDFLAGS) $(aout_RPATH) \
	-Wl,-framework,CoreAudio,-framework,AudioUnit,-framework,AudioToolbox,-framework,CoreServices
if HAVE_OSX
aout_PLUGINS += libauhal_plugin.la libavsamplebuffer_plugin.la
endif
libaudiounit_ios_plugin_la_SOURCES = audio_output/apple/audiounit_ios.m \
	audio_output/apple/coreaudio_common.c audio_output/apple/coreaudio_common.h \
	audio_output/apple/channel_layout.c audio_output/apple/avaudiosession_common.m
libaudiounit_ios_plugin_la_LDFLAGS = $(AM_LDFLAGS) $(aout_RPATH) \
	-Wl,-framework,Foundation,-framework,CoreAudio,-framework,AudioToolbox,-framework,UIKit,-framework,AVFoundation
if HAVE_IOS_OR_TVOS
aout_PLUGINS += libaudiounit_ios_plugin.la libavsamplebuffer_plugin.la
endif
if HAVE_XROS
aout_PLUGINS += libaudiounit_ios_plugin.la libavsamplebuffer_plugin.la
endif
if HAVE_WATCHOS
aout_PLUGINS += libavsamplebuffer_plugin.la
endif
