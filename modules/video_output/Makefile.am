voutdir = $(pluginsdir)/video_output
vout_PLUGINS =
vout_LTLIBRARIES =
vout_RPATH =
if HAVE_PARTIAL_LINKING
noinst_LTLIBRARIES += $(vout_PLUGINS)
else
vout_LTLIBRARIES += $(vout_PLUGINS)
vout_RPATH += -rpath '$(voutdir)'
endif

# Install the pkglib/pkglibexec first before relinking the modules.
# This ensures libtool re-linking is not racy.
installvoutLTLIBRARIES = install-voutLTLIBRARIES
$(installvoutLTLIBRARIES): install-pkglibLTLIBRARIES

EXTRA_DIST += video_output/README

### libplacebo ###
if HAVE_LIBPLACEBO
include video_output/libplacebo/Makefile.am
endif

### OpenGL ###
include video_output/opengl/Makefile.am

if HAVE_DECKLINK
libdecklinkoutput_plugin_la_SOURCES = video_output/decklink.cpp \
                                      stream_out/sdi/Ancillary.cpp \
                                      stream_out/sdi/Ancillary.hpp \
                                      stream_out/sdi/DBMHelper.cpp \
                                      stream_out/sdi/DBMHelper.hpp \
                                      stream_out/sdi/SDIGenerator.cpp \
                                      stream_out/sdi/SDIGenerator.hpp \
                                      stream_out/sdi/V210.cpp \
                                      stream_out/sdi/V210.hpp
libdecklinkoutput_plugin_la_CXXFLAGS = $(AM_CXXFLAGS) $(CPPFLAGS_decklinkoutput)
libdecklinkoutput_plugin_la_LIBADD = $(LIBS_decklinkoutput)
if HAVE_WIN32
libdecklinkoutput_plugin_la_LIBADD += $(LIBCOM)
libdecklinkoutput_plugin_la_CXXFLAGS += $(LIBCOMCXXFLAGS)
endif
if HAVE_LINUX
libdecklinkoutput_plugin_la_LIBADD += $(LIBDL)
endif
vout_PLUGINS += libdecklinkoutput_plugin.la
endif

libglinterop_cvpx_plugin_la_SOURCES = video_output/opengl/interop_cvpx.m \
	video_output/opengl/interop.h
libglinterop_cvpx_plugin_la_LIBADD = libvlc_vtutils.la
libglinterop_cvpx_plugin_la_LDFLAGS = $(AM_LDFLAGS) $(vout_RPATH) \
	-Wl,-framework,Foundation,-framework,CoreVideo,-framework,IOSurface,-framework,Metal
libglinterop_cvpx_plugin_la_CPPFLAGS = $(AM_CPPFLAGS)
if HAVE_OSX
vout_PLUGINS += libglinterop_cvpx_plugin.la
libglinterop_cvpx_plugin_la_LDFLAGS += -Wl,-framework,OpenGL
endif
if HAVE_IOS_OR_TVOS
vout_PLUGINS += libglinterop_cvpx_plugin.la
libglinterop_cvpx_plugin_la_CPPFLAGS += -DUSE_OPENGL_ES2
libglinterop_cvpx_plugin_la_LDFLAGS += -Wl,-framework,OpenGLES
endif

if HAVE_OSX
libwindow_macosx_plugin_la_SOURCES = video_output/window_macosx.m
libwindow_macosx_plugin_la_LDFLAGS = $(AM_LDFLAGS) \
	-Wl,-framework,Cocoa
libwindow_macosx_plugin_la_OBJCFLAGS = $(AM_OBJCFLAGS) \
	-fobjc-arc -fobjc-exceptions

libvout_macosx_plugin_la_SOURCES = video_output/macosx.m \
	$(OPENGL_VOUT_COMMONSOURCES)
libvout_macosx_plugin_la_OBJCFLAGS = $(AM_OBJCFLAGS) -fobjc-arc
libvout_macosx_plugin_la_CPPFLAGS = $(AM_CPPFLAGS) -DHAVE_GL_CORE_SYMBOLS -DGL_SILENCE_DEPRECATION
libvout_macosx_plugin_la_LIBADD = libvlc_opengl.la
libvout_macosx_plugin_la_LDFLAGS = $(AM_LDFLAGS) $(vout_RPATH) \
	-Wl,-framework,OpenGL,-framework,Cocoa

libcaopengllayer_plugin_la_SOURCES = video_output/caopengllayer.m \
	$(OPENGL_VOUT_COMMONSOURCES)
libcaopengllayer_plugin_la_OBJCFLAGS = $(AM_OBJCFLAGS) -fobjc-arc
libcaopengllayer_plugin_la_CPPFLAGS = $(AM_CPPFLAGS)  -DHAVE_GL_CORE_SYMBOLS -DGL_SILENCE_DEPRECATION
libcaopengllayer_plugin_la_LIBADD = libvlc_opengl.la
libcaopengllayer_plugin_la_LDFLAGS = $(AM_LDFLAGS) $(vout_RPATH) \
	-Wl,-framework,OpenGL,-framework,Cocoa,-framework,QuartzCore

vout_PLUGINS += libvout_macosx_plugin.la libcaopengllayer_plugin.la libwindow_macosx_plugin.la
endif

if HAVE_DARWIN
if !HAVE_WATCHOS
libsamplebufferdisplay_plugin_la_SOURCES = video_output/apple/VLCSampleBufferDisplay.m \
	video_output/apple/MacLCSDR2HDRSession.m video_output/apple/MacLCSDR2HDRSession.h \
	video_output/apple/VLCHDRExpander.m video_output/apple/VLCHDRExpander.h \
	video_output/apple/VLCHDRNetwork.m video_output/apple/VLCHDRNetwork.h \
	video_output/apple/maclc_sdr2hdr.h \
	video_output/apple/MacLCHDRToneMapper.m video_output/apple/MacLCHDRToneMapper.h \
	video_output/apple/maclc_tonemap.h video_output/apple/maclc_hdr_vars.h \
	codec/vt_utils.c codec/vt_utils.h
libsamplebufferdisplay_plugin_la_OBJCFLAGS = $(AM_OBJCFLAGS) -fobjc-arc
if HAVE_OSX
# MacLC's Metal output (AppKit view + CAMetalLayer), a submodule of this plugin
libsamplebufferdisplay_plugin_la_SOURCES += \
	video_output/apple/MacLCMetalDisplay.m video_output/apple/MacLCMetalDisplay.h \
	video_output/apple/MacLCMetalRenderer.m video_output/apple/MacLCMetalRenderer.h \
	video_output/apple/MacLCMetalScaler.m video_output/apple/MacLCMetalScaler.h \
	video_output/apple/MacLCMetal360.m video_output/apple/MacLCMetal360.h \
	video_output/apple/MacLCMetalLUT.m video_output/apple/MacLCMetalLUT.h \
	video_output/apple/MacLCMetalDovi.m video_output/apple/MacLCMetalDovi.h \
	video_output/apple/maclc_dovi.h \
	video_output/apple/MacLCMetalColorPass.m video_output/apple/MacLCMetalColorPass.h \
	video_output/apple/maclc_tonecurves.c video_output/apple/maclc_tonecurves.h \
	video_output/apple/MacLCMetalUpscaler.m video_output/apple/MacLCMetalUpscaler.h \
	video_output/apple/MacLCMetalArtCNN.m video_output/apple/MacLCMetalArtCNN.h \
	video_output/apple/maclc_artcnn_c4f16.h \
	video_output/apple/MacLCMetalFSR.m video_output/apple/MacLCMetalFSR.h \
	video_output/apple/MacLCMetalNIS.m video_output/apple/MacLCMetalNIS.h \
	video_output/apple/MacLCMetalHookShader.m video_output/apple/MacLCMetalHookShader.h \
	video_output/apple/maclc_anime4k_cnn_x2_m.h \
	video_output/apple/maclc_upscale_vars.h
libsamplebufferdisplay_plugin_la_LDFLAGS = $(AM_LDFLAGS) $(vout_RPATH) \
	-Wl,-framework,AVFoundation,-framework,AVKit,-framework,Cocoa,-framework,CoreMedia,-framework,QuartzCore,-framework,CoreGraphics,-framework,CoreVideo,-framework,VideoToolbox,-framework,CoreImage,-framework,Metal,-framework,MetalPerformanceShaders,-framework,MetalPerformanceShadersGraph,-framework,IOSurface,-framework,IOKit,-weak_framework,MetalFX
else
libsamplebufferdisplay_plugin_la_LDFLAGS = $(AM_LDFLAGS) $(vout_RPATH) \
	-Wl,-framework,AVFoundation,-framework,Foundation,-framework,AVKit,-framework,UIKit,-framework,CoreMedia,-framework,QuartzCore,-framework,CoreGraphics,-framework,CoreVideo,-framework,VideoToolbox,-framework,CoreImage,-framework,Metal,-framework,MetalPerformanceShaders,-framework,MetalPerformanceShadersGraph,-framework,IOSurface
endif
vout_PLUGINS += libsamplebufferdisplay_plugin.la
endif
endif


if HAVE_IOS_OR_TVOS
libpictureinpicturecontroller_plugin_la_SOURCES = video_output/apple/VLCPictureInPictureController.m
libpictureinpicturecontroller_plugin_la_OBJCFLAGS = $(AM_OBJCFLAGS) -fobjc-arc
libpictureinpicturecontroller_plugin_la_LDFLAGS = $(AM_LDFLAGS) $(vout_RPATH) \
	-Wl,-framework,AVFoundation,-framework,Foundation,-framework,AVKit,-framework,UIKit,-framework,QuartzCore,-framework,CoreMedia
vout_PLUGINS += libpictureinpicturecontroller_plugin.la
endif

libvout_ios_plugin_la_SOURCES = video_output/opengl/display.c $(OPENGL_VOUT_COMMONSOURCES)
libvout_ios_plugin_la_CFLAGS = $(AM_CFLAGS) $(OPENGL_COMMONCFLAGS) -DUSE_OPENGL_ES2
libvout_ios_plugin_la_LIBADD = libvlc_opengles.la $(GLES2_LIBS)

libuiview_window_plugin_la_SOURCES = video_output/apple/VLCVideoUIView.m
libuiview_window_plugin_la_LDFLAGS = $(AM_LDFLAGS) \
	-Wl,-framework,CoreGraphics,-framework,Foundation,-framework,QuartzCore,-framework,UIKit
libuiview_window_plugin_la_OBJCFLAGS = $(AM_OBJCFLAGS) -fobjc-arc

libcaeagl_ios_plugin_la_SOURCES = video_output/apple/VLCOpenGLES2VideoView.m
libcaeagl_ios_plugin_la_LDFLAGS = $(AM_LDFLAGS) \
	-Wl,-framework,Foundation,-framework,OpenGLES,-framework,QuartzCore,-framework,UIKit
libcaeagl_ios_plugin_la_CPPFLAGS = $(AM_CPPFLAGS) -DGL_SILENCE_DEPRECATION
libcaeagl_ios_plugin_la_OBJCFLAGS = $(AM_OBJCFLAGS) -fobjc-arc

libcvpx_gl_plugin_la_SOURCES = video_output/apple/VLCCVOpenGLProvider.m
libcvpx_gl_plugin_la_OBJCFLAGS = $(AM_OBJCFLAGS) -fobjc-arc
libcvpx_gl_plugin_la_CPPFLAGS = $(AM_CPPFLAGS) -DGL_SILENCE_DEPRECATION
libcvpx_gl_plugin_la_LDFLAGS = $(AM_LDFLAGS) \
    -Wl,-framework,Foundation,-framework,CoreFoundation,-framework,CoreVideo,-framework,Metal
libcvpx_gl_plugin_la_LIBADD = libvlc_vtutils.la

if HAVE_OSX
vout_PLUGINS += libcvpx_gl_plugin.la
libcvpx_gl_plugin_la_LDFLAGS += -Wl,-framework,OpenGL
libcvpx_gl_plugin_la_LIBADD += libvlc_opengl.la
endif
if HAVE_IOS_OR_TVOS
vout_PLUGINS += libcvpx_gl_plugin.la
libcvpx_gl_plugin_la_CPPFLAGS += -DUSE_OPENGL_ES2
libcvpx_gl_plugin_la_LDFLAGS += -Wl,-framework,OpenGLES
libcvpx_gl_plugin_la_LIBADD += libvlc_opengles.la
endif

if HAVE_IOS_OR_TVOS
vout_PLUGINS += \
	libvout_ios_plugin.la \
	libuiview_window_plugin.la \
	libcaeagl_ios_plugin.la
endif
if HAVE_XROS
vout_PLUGINS += libuiview_window_plugin.la
endif

libglinterop_gst_mem_plugin_la_SOURCES = video_output/opengl/interop_gst_mem.c \
	video_output/opengl/interop.h codec/gstreamer/gst_mem.h
libglinterop_gst_mem_plugin_la_CFLAGS = $(AM_CFLAGS) $(GL_CFLAGS) $(GST_VIDEO_CFLAGS) \
	$(GST_APP_CFLAGS)
libglinterop_gst_mem_plugin_la_LIBADD = $(GST_VIDEO_LIBS) $(GST_APP_LIBS)

if HAVE_GL
if HAVE_EGL
if HAVE_GST_DECODE
vout_PLUGINS += libglinterop_gst_mem_plugin.la
endif
endif # HAVE_EGL
endif # HAVE_GL


### Coloured ASCII art ###
libcaca_plugin_la_SOURCES = video_output/caca.c
libcaca_plugin_la_CFLAGS = $(AM_CFLAGS) $(CACA_CFLAGS)
libcaca_plugin_la_LIBADD = $(CACA_LIBS)
if !HAVE_WIN32
if !HAVE_DARWIN
libcaca_plugin_la_LIBADD += $(X_LIBS) $(X_PRE_LIBS) -lX11
endif
endif
libcaca_plugin_la_LDFLAGS = $(AM_LDFLAGS) $(vout_RPATH)
EXTRA_LTLIBRARIES += libcaca_plugin.la
vout_PLUGINS += $(LTLIBcaca)

### Common ###

libflaschen_plugin_la_SOURCES = video_output/flaschen.c
libflaschen_plugin_la_LIBADD = $(SOCKET_LIBS)

libvdummy_plugin_la_SOURCES = video_output/vdummy.c
libvideo_splitter_plugin_la_SOURCES = video_output/splitter.c
libvmem_plugin_la_SOURCES = video_output/vmem.c
libwdummy_plugin_la_SOURCES = video_output/wdummy.c
libwextern_plugin_la_SOURCES = video_output/wextern.c
libyuv_plugin_la_SOURCES = video_output/yuv.c
libvgl_plugin_la_SOURCES = video_output/vgl.c

vout_PLUGINS += \
	libflaschen_plugin.la \
	libvdummy_plugin.la \
	libvideo_splitter_plugin.la \
	libvmem_plugin.la \
	libwdummy_plugin.la \
	libwextern_plugin.la \
	libvgl_plugin.la \
	libyuv_plugin.la
