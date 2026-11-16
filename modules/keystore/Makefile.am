keystoredir = $(pluginsdir)/keystore
keystore_PLUGINS =
keystore_LTLIBRARIES =
keystore_RPATH =
if HAVE_PARTIAL_LINKING
noinst_LTLIBRARIES += $(keystore_PLUGINS)
else
keystore_LTLIBRARIES += $(keystore_PLUGINS)
keystore_RPATH += -rpath '$(keystoredir)'
endif

libmemory_keystore_plugin_la_SOURCES = keystore/memory.c \
	keystore/list_util.c keystore/list_util.h
keystore_PLUGINS += libmemory_keystore_plugin.la

libfile_keystore_plugin_la_SOURCES = keystore/file.c \
	keystore/file_crypt.h \
	keystore/list_util.c keystore/list_util.h
keystore_PLUGINS += libfile_keystore_plugin.la

libkeychain_plugin_la_SOURCES = keystore/keychain.m keystore/list_util.c keystore/list_util.h
libkeychain_plugin_la_OBJCFLAGS = $(AM_OBJCFLAGS) -fobjc-arc
libkeychain_plugin_la_LDFLAGS = $(AM_LDFLAGS) $(keystore_RPATH) -Wl,-framework,Foundation -Wl,-framework,Security

if HAVE_DARWIN
keystore_PLUGINS += libkeychain_plugin.la
endif
