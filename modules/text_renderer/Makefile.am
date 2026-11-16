textdir = $(pluginsdir)/text_renderer
text_PLUGINS =
text_LTLIBRARIES =
text_RPATH =
if HAVE_PARTIAL_LINKING
noinst_LTLIBRARIES += $(text_PLUGINS)
else
text_LTLIBRARIES += $(text_PLUGINS)
text_RPATH += -rpath '$(textdir)'
endif

libtdummy_plugin_la_SOURCES = text_renderer/tdummy.c
text_PLUGINS += libtdummy_plugin.la

libfreetype_plugin_la_SOURCES = \
	text_renderer/freetype/platform_fonts.c text_renderer/freetype/platform_fonts.h \
	text_renderer/freetype/freetype.c text_renderer/freetype/freetype.h \
	text_renderer/freetype/ftcache.c text_renderer/freetype/ftcache.h \
	text_renderer/freetype/text_layout.c text_renderer/freetype/text_layout.h \
	text_renderer/freetype/lru.c text_renderer/freetype/lru.h \
        text_renderer/freetype/fonts/backends.h \
        text_renderer/freetype/blend/blend.h \
        text_renderer/freetype/blend/rgb.h \
        text_renderer/freetype/blend/yuv.h

libfreetype_plugin_la_CPPFLAGS = $(AM_CPPFLAGS) $(FREETYPE_CFLAGS)
libfreetype_plugin_la_LIBADD = $(AM_LIBADD) $(LIBM)
libfreetype_plugin_la_LDFLAGS = $(FREETYPE_LDFLAGS) $(text_RPATH)

libfreetype_plugin_la_LINK = $(LINK)
if HAVE_DARWIN
libfreetype_plugin_la_SOURCES += text_renderer/freetype/fonts/darwin.c
libfreetype_plugin_la_LDFLAGS += -Wl,-framework,CoreFoundation -Wl,-framework,CoreText
endif
if HAVE_FRIBIDI
libfreetype_plugin_la_CPPFLAGS += $(FRIBIDI_CFLAGS) -DHAVE_FRIBIDI
libfreetype_plugin_la_LIBADD += $(FRIBIDI_LIBS)
endif
if HAVE_HARFBUZZ
libfreetype_plugin_la_CPPFLAGS += $(HARFBUZZ_CFLAGS) -DHAVE_HARFBUZZ
libfreetype_plugin_la_LIBADD += $(HARFBUZZ_LIBS)
endif
libfreetype_plugin_la_LINK += $(libfreetype_plugin_la_LDFLAGS)
libfreetype_plugin_la_LIBADD += $(FREETYPE_LIBS)
if HAVE_FREETYPE
text_PLUGINS += libfreetype_plugin.la
endif

# SVG plugin
libsvg_plugin_la_SOURCES = text_renderer/svg.c
libsvg_plugin_la_CPPFLAGS = $(AM_CPPFLAGS) $(SVG_CFLAGS)
libsvg_plugin_la_LDFLAGS = $(AM_LDFLAGS) $(text_RPATH)
libsvg_plugin_la_LIBADD = $(SVG_LIBS)
EXTRA_LTLIBRARIES += libsvg_plugin.la
text_PLUGINS += $(LTLIBsvg)

# OS X TTS
libnsspeechsynthesizer_plugin_la_SOURCES = text_renderer/nsspeechsynthesizer.m
libnsspeechsynthesizer_plugin_la_LDFLAGS = $(AM_LDFLAGS) -Wl,-framework,Cocoa
if HAVE_OSX
text_PLUGINS += libnsspeechsynthesizer_plugin.la
endif
