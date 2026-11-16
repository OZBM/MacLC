notifydir = $(pluginsdir)/notify
notify_PLUGINS =
notify_LTLIBRARIES =
notify_RPATH =
if HAVE_PARTIAL_LINKING
noinst_LTLIBRARIES += $(notify_PLUGINS)
else
notify_LTLIBRARIES += $(notify_PLUGINS)
notify_RPATH += -rpath '$(notifydir)'
endif

libosx_notifications_plugin_la_SOURCES = notify/osx_notifications.m
libosx_notifications_plugin_la_OBJCFLAGS = $(AM_OBJCFLAGS) -fobjc-arc -fobjc-exceptions
libosx_notifications_plugin_la_LDFLAGS = $(AM_LDFLAGS) $(notify_RPATH) -Wl,-framework,AppKit,-framework,Foundation

notify_PLUGINS += $(LTLIBosx_notifications)
EXTRA_LTLIBRARIES += libosx_notifications_plugin.la
