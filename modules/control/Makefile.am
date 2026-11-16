controldir = $(pluginsdir)/control
control_PLUGINS =
control_LTLIBRARIES =
if HAVE_PARTIAL_LINKING
noinst_LTLIBRARIES += $(control_PLUGINS)
else
control_LTLIBRARIES += $(control_PLUGINS)
endif

libdummy_plugin_la_SOURCES = control/dummy.c control/intromsg.h
libgestures_plugin_la_SOURCES = control/gestures.c
libhotkeys_plugin_la_SOURCES = control/hotkeys.c
libhotkeys_plugin_la_LIBADD = $(LIBM)
# XXX: netsync disabled, move current code to new playlist/player and add a
# way to control the output clock from the player
#libnetsync_plugin_la_SOURCES = control/netsync.c
#libnetsync_plugin_la_LIBADD = $(SOCKET_LIBS)
librc_plugin_la_SOURCES = \
	control/intromsg.h \
	control/cli/player.c control/cli/playlist.c \
	control/cli/cli.c control/cli/cli.h
librc_plugin_la_LIBADD = $(SOCKET_LIBS) $(LIBM)

control_PLUGINS += \
	libdummy_plugin.la \
	libgestures_plugin.la \
	libhotkeys_plugin.la \
	librc_plugin.la

liblirc_plugin_la_SOURCES = control/lirc.c
liblirc_plugin_la_LIBADD = -llirc_client
if HAVE_LIRC
control_PLUGINS += liblirc_plugin.la
endif

libvlc_motion_la_SOURCES = control/motionlib.c control/motionlib.h
libvlc_motion_la_LDFLAGS = -static
noinst_LTLIBRARIES += libvlc_motion.la
