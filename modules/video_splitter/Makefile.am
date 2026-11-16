splitterdir = $(pluginsdir)/video_splitter
splitter_PLUGINS =
splitter_LTLIBRARIES =
if HAVE_PARTIAL_LINKING
noinst_LTLIBRARIES += $(splitter_PLUGINS)
else
splitter_LTLIBRARIES += $(splitter_PLUGINS)
endif


splitter_PLUGINS += \
	libclone_plugin.la \
	libwall_plugin.la

libclone_plugin_la_SOURCES = video_splitter/clone.c

libwall_plugin_la_SOURCES = video_splitter/wall.c
