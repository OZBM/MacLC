OPENGL_COMMONSOURCES = \
       video_output/opengl/filter.c \
       video_output/opengl/filter_priv.h \
       video_output/opengl/filters.c \
       video_output/opengl/filters.h \
       video_output/opengl/gl_api.c \
       video_output/opengl/gl_api.h \
       video_output/opengl/gl_common.h \
       video_output/opengl/gl_util.c \
       video_output/opengl/gl_util.h \
       video_output/opengl/importer.c \
       video_output/opengl/importer.h \
       video_output/opengl/importer_priv.h \
       video_output/opengl/interop.h \
       video_output/opengl/interop.c \
       video_output/opengl/picture.h \
       video_output/opengl/sampler_loader.c \
       video_output/opengl/sampler.h

OPENGL_COMMONCFLAGS =
OPENGL_COMMONLIBS =

OPENGL_VOUT_COMMONSOURCES = \
    video_output/opengl/gl_scale.h \
    video_output/opengl/renderer.c \
    video_output/opengl/renderer.h \
    video_output/opengl/sub_renderer.c \
    video_output/opengl/sub_renderer.h \
    video_output/opengl/vout_helper.c \
    video_output/opengl/vout_helper.h

# Convenience library for OpenGL components -- OpenGL only
libvlc_opengl_la_SOURCES = $(OPENGL_COMMONSOURCES)
libvlc_opengl_la_CFLAGS = $(OPENGL_COMMONCFLAGS) $(GL_CFLAGS)
libvlc_opengl_la_CPPFLAGS =
libvlc_opengl_la_LIBADD = $(OPENGL_COMMONLIBS) $(LIBM)
libvlc_opengl_la_LDFLAGS = -static -no-undefined

if HAVE_GL
noinst_LTLIBRARIES += libvlc_opengl.la
endif

# Convenience library for OpenGL components -- OpenGL ES only
libvlc_opengles_la_SOURCES = $(OPENGL_COMMONSOURCES)
libvlc_opengles_la_CFLAGS = $(OPENGL_COMMONCFLAGS) -DUSE_OPENGL_ES2
libvlc_opengles_la_LIBADD = $(OPENGL_COMMONLIBS) $(LIBM)
libvlc_opengles_la_LDFLAGS = -static -no-undefined

libvlc_opengles_la_CFLAGS += $(GLES2_CFLAGS)
if HAVE_GLES2
noinst_LTLIBRARIES += libvlc_opengles.la
endif

# Plugins that adapt to either backend link against $(GL_PLUGIN_LIBADD)
# and build with $(GL_PLUGIN_CFLAGS), and are registered under
# HAVE_GL_OR_GLES2. These are GL filters/interops that run inside the
# current context and call GL through the provider's function table, so
# they need only the common convenience library, not the GL/GLES2 link
# libraries.
if HAVE_GL
GL_PLUGIN_LIBADD = libvlc_opengl.la
GL_PLUGIN_CFLAGS = $(GL_CFLAGS)
else
if HAVE_GLES2
GL_PLUGIN_LIBADD = libvlc_opengles.la
GL_PLUGIN_CFLAGS = $(GLES2_CFLAGS) -DUSE_OPENGL_ES2=1
endif
endif

# glsampler_builtin
libglsampler_builtin_plugin_la_SOURCES = video_output/opengl/sampler.c
libglsampler_builtin_plugin_la_CPPFLAGS = $(AM_CPPFLAGS) $(LIBPLACEBO_CFLAGS)
libglsampler_builtin_plugin_la_LIBADD = $(GL_PLUGIN_LIBADD)
libglsampler_builtin_plugin_la_CFLAGS = $(AM_CFLAGS) $(GL_PLUGIN_CFLAGS)
if HAVE_LIBPLACEBO_GL
libglsampler_builtin_plugin_la_LIBADD += $(LIBPLACEBO_LIBS) libplacebo_utils.la
endif
if HAVE_GL_OR_GLES2
vout_PLUGINS += libglsampler_builtin_plugin.la
endif

libglinterop_sw_plugin_la_SOURCES = video_output/opengl/interop_sw.c
libglinterop_sw_plugin_la_CPPFLAGS = $(AM_CPPFLAGS) $(GL_PLUGIN_CFLAGS)
libglinterop_sw_plugin_la_LIBADD = $(GL_PLUGIN_LIBADD)
if HAVE_GL_OR_GLES2
vout_PLUGINS += libglinterop_sw_plugin.la
endif

### OpenGL ###
libgles2_plugin_la_SOURCES = video_output/opengl/display.c \
    $(OPENGL_VOUT_COMMONSOURCES)
libgles2_plugin_la_CFLAGS = $(AM_CFLAGS) $(GLES2_CFLAGS) -DUSE_OPENGL_ES2
libgles2_plugin_la_LIBADD = libvlc_opengles.la $(GLES2_LIBS)
libgles2_plugin_la_LDFLAGS = $(AM_LDFLAGS) $(vout_RPATH)
if HAVE_GLES2
vout_PLUGINS += libgles2_plugin.la
endif

libgl_plugin_la_SOURCES = video_output/opengl/display.c \
    $(OPENGL_VOUT_COMMONSOURCES)
libgl_plugin_la_CFLAGS = $(AM_CFLAGS) $(GL_CFLAGS) $(OPENGL_COMMONCFLAGS)
libgl_plugin_la_CPPFLAGS = $(AM_CPPFLAGS)
libgl_plugin_la_LIBADD = libvlc_opengl.la
if HAVE_GL
vout_PLUGINS += libgl_plugin.la
endif # HAVE_GL

libglfilter_draw_plugin_la_SOURCES = video_output/opengl/filter_draw.c
libglfilter_draw_plugin_la_LDFLAGS = $(AM_LDFLAGS)
libglfilter_draw_plugin_la_LIBADD = $(GL_PLUGIN_LIBADD)
libglfilter_draw_plugin_la_CFLAGS = $(AM_CFLAGS) $(GL_PLUGIN_CFLAGS)
if HAVE_GL_OR_GLES2
vout_PLUGINS += libglfilter_draw_plugin.la
endif

libglfilter_mock_plugin_la_SOURCES = video_output/opengl/filter_mock.c
libglfilter_mock_plugin_la_LIBADD = $(LIBM) $(GL_PLUGIN_LIBADD)
libglfilter_mock_plugin_la_CFLAGS = $(AM_CFLAGS) $(GL_PLUGIN_CFLAGS)
# NOTE: we need $(vout_RPATH) here to properly generate a shared object
#       when building dynamic plugins.
libglfilter_mock_plugin_la_LDFLAGS = $(AM_LDFLAGS) $(vout_RPATH)
if HAVE_GL_OR_GLES2
noinst_PLUGINS += libglfilter_mock_plugin.la
endif

if HAVE_LIBPLACEBO
if HAVE_LIBPLACEBO_GL

libpl_scale_plugin_la_SOURCES = video_output/opengl/pl_scale.c
libpl_scale_plugin_la_CPPFLAGS = $(AM_CPPFLAGS) $(LIBPLACEBO_CFLAGS) $(GL_PLUGIN_CFLAGS)
libpl_scale_plugin_la_LIBADD = $(LIBPLACEBO_LIBS) libplacebo_utils.la $(GL_PLUGIN_LIBADD)
if HAVE_GL_OR_GLES2
video_filter_PLUGINS += libpl_scale_plugin.la
endif

endif
endif
