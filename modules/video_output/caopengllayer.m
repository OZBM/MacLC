/*****************************************************************************
 * caopengllayer.m: CAOpenGLLayer (Mac OS X) video output
 *****************************************************************************
 * Copyright (C) 2014-2017 VLC authors and VideoLAN
 *
 * Authors: David Fuhrmann <david dot fuhrmann at googlemail dot com>
 *          Felix Paul Kühne <fkuehne at videolan dot org>
 *          Pierre d'Herbemont <pdherbemont at videolan dot org>
 *          Alexandre Janniaux <ajanni@videolabs.io>
 *
 * Some of the code is based on mpv's video_layer.swift by "der richter"
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation; either version 2.1 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/

/*****************************************************************************
 * Preamble
 *****************************************************************************/

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <vlc_common.h>
#include <vlc_plugin.h>
#include <vlc_vout_display.h>
#include <vlc_opengl.h>
#include <vlc_atomic.h>

#import <QuartzCore/QuartzCore.h>
#import <Cocoa/Cocoa.h>
#import <OpenGL/OpenGL.h>
#import <dlfcn.h>

#ifndef kCGLOGLPVersion_GL4_1_Core
# ifdef kCGLOGLPVersion_GL4_Core
#  define kCGLOGLPVersion_GL4_1_Core kCGLOGLPVersion_GL4_Core
# else
#  define kCGLOGLPVersion_GL4_1_Core ((CGLOpenGLProfile)0x4100)
# endif
#endif

#ifndef kCGLOGLPVersion_GL3_2_Core
# ifdef kCGLOGLPVersion_3_2_Core
#  define kCGLOGLPVersion_GL3_2_Core kCGLOGLPVersion_3_2_Core
# elif defined(kCGLOGLPVersion_GL3_Core)
#  define kCGLOGLPVersion_GL3_2_Core kCGLOGLPVersion_GL3_Core
# else
#  define kCGLOGLPVersion_GL3_2_Core ((CGLOpenGLProfile)0x3200)
# endif
#endif

#include "opengl/renderer.h"
#include "opengl/vout_helper.h"

/**
 * Protocol declaration that drawable-nsobject should follow
 */
@protocol VLCOpenGLVideoViewEmbedding <NSObject>
- (void)addVoutSubview:(NSView *)view;
- (void)removeVoutSubview:(NSView *)view;
@end

/**
 * Layer subclass that handles OpenGL video rendering
 */
@interface VLCCAOpenGLLayer : CAOpenGLLayer
{
    NSLock *_displayLock;
    vlc_gl_t *_gl; // All accesses to this must be @synchronized(self)
                   // unless you can be sure it won't be called in teardown
    CGLContextObj _glContext;
    atomic_bool _is_ready;
}

@property (nonatomic, copy) void (^render)(NSSize displaySize);

- (instancetype)init:(vlc_gl_t *)gl context:(CGLContextObj)context;
- (void)displayFromVout;
- (void)vlcClose;
- (void)markReady;
- (void)updateDynamicRangeWithHeadroom:(CGFloat)headroom isHDR:(BOOL)isHDR;
@end

/**
 * View subclass which is backed by a VLCCAOpenGLLayer
 */
#if __MAC_OS_X_VERSION_MAX_ALLOWED < 101400
// macOS SDKs lower than 10.14 did not have a NSViewLayerContentScaleDelegate
// protocol definition, but its not needed, it will work fine without it as the
// delegate method even existed before, just not the protocol.
@interface VLCVideoLayerView : NSView <CALayerDelegate>
#else
@interface VLCVideoLayerView : NSView <CALayerDelegate, NSViewLayerContentScaleDelegate>
#endif
{
    vlc_gl_t *_gl; // All accesses to this must be @synchronized(self)
    id _container;

    CGLContextObj _context; // The CGL context managed by us
    CGLContextObj _context_previous; // The previously current CGL context, if any
    BOOL _isHDR;
}

- (instancetype)init:(vlc_gl_t *)gl;
- (void)vlcClose;

- (int)lockContext;
- (void)unlockContext;
- (void)swap;
- (void)setHDR:(BOOL)isHDR;
- (void)updateDynamicRangeProperties;
@end

typedef struct vout_display_sys_t {

    vlc_gl_t *gl;
    vout_display_opengl_t *vgl;

    vout_display_place_t place;
    vout_display_cfg_t cfg;

    bool change_projection;
    video_projection_mode_t projection;
    vlc_viewpoint_t viewpoint;
} vout_display_sys_t;

#pragma mark -
#pragma mark OpenGL context helpers

// kCGLRenderer* enum value define card value, but family is enough here.
// However they follow some pattern by familly.
#define kRendererIntelFamilyMask 0x00024000

/*
 * GL API does not provide a way to know if a device is a lowpower one.
 * We could make some guess here:
 * On a MacBookPro (intel):
 *   - GeForce and Radeon card could be discrete or external.
 *   - Intel could be integrated or external.
 * To be check MacPro or MacMini or ARM ones.
 */
static bool vlc_IsLowPowerDevice(GLint renderer_id) {
    int renderer_vendor = renderer_id & kCGLRendererIDMatchingMask;
    // Consider Intel familly card as low power devices.
    return renderer_vendor == kCGLRendererIntel900ID ||
           renderer_vendor == kCGLRendererIntelX3100ID ||
           renderer_vendor == kCGLRendererIntelHDID ||
           renderer_vendor == kCGLRendererIntelHD4000ID ||
           renderer_vendor == kCGLRendererIntelHD5000ID;
}

/*
 * Search for a low power device.
 * Without proper API (like Metal), here we try to look on all the available
 * renderer and filter them.
 * We are looking for the one attached to the main display, accelerated, and
 * with low power consumption.
 * Without any match, we let CGLChoosePixelFormat/CGLCreateContext do as before.
 */
static GLint vlc_SearchGLRendererId() {
    CGLRendererInfoObj renderer_info = NULL;
    GLint renderer_count = 0;
    if (CGLQueryRendererInfo((GLuint)-1, &renderer_info, &renderer_count) !=
        kCGLNoError)
      return -1;

    GLint best_match = -1;
    for (GLint i = 0; i < renderer_count && best_match == -1; ++i) {
      GLint renderer_id = -1;
      if (CGLDescribeRenderer(renderer_info, i, kCGLRPRendererID,
                              &renderer_id) != kCGLNoError)
        break;
      GLint accelerated = 0;
      if (CGLDescribeRenderer(renderer_info, i, kCGLRPAccelerated,
                              &accelerated) != kCGLNoError)
        break;
      if (!accelerated)
        continue; // avoid not accelerated device
      GLint display = -1;
      if (CGLDescribeRenderer(renderer_info, i, kCGLRPDisplayMask, &display) !=
          kCGLNoError)
        break;
      CGDirectDisplayID display_id = CGOpenGLDisplayMaskToDisplayID(display);
      if (display_id != CGMainDisplayID())
        continue;
      if (vlc_IsLowPowerDevice(renderer_id))
        best_match = renderer_id;
    }
    CGLDestroyRendererInfo(renderer_info);
    return best_match;
}

/**
 * Create a new CGLContextObj for use by VLC
 * This function may try various pixel formats until it finds a suitable/compatible
 * one that works on the given hardware.
 * \return CGLContextObj or NULL in case of error
 */
static CGLContextObj vlc_CreateCGLContext(vlc_gl_t *gl)
{
    CGLError err;
    GLint npix = 0;
    CGLPixelFormatObj pix = NULL;
    CGLContextObj ctx;

    GLint renderer_id = vlc_SearchGLRendererId();

    static const struct {
        CGLOpenGLProfile profile;
        const char *name;
        bool has_profile;
    } profiles[] = {
        { (CGLOpenGLProfile)kCGLOGLPVersion_GL4_1_Core, "OpenGL 4.1 Core", true },
        { (CGLOpenGLProfile)kCGLOGLPVersion_GL3_2_Core, "OpenGL 3.2 Core", true },
        { (CGLOpenGLProfile)0, "Legacy OpenGL", false },
    };

    static const struct {
        int color_size;
        int alpha_size;
    } color_depths[] = {
        { 64, 16 },
        { 24, 8 },
    };

    const char *success_profile = NULL;
    int success_color = 0;
    int success_alpha = 0;

    for (size_t p = 0; p < ARRAY_SIZE(profiles); p++) {
        for (size_t c = 0; c < ARRAY_SIZE(color_depths); c++) {
            CGLPixelFormatAttribute attribs[20];
            size_t i = 0;

            if (profiles[p].has_profile) {
                attribs[i++] = kCGLPFAOpenGLProfile;
                attribs[i++] = (CGLPixelFormatAttribute)profiles[p].profile;
            }

            attribs[i++] = kCGLPFAAllRenderers;
            attribs[i++] = kCGLPFAAllowOfflineRenderers;
            attribs[i++] = kCGLPFADoubleBuffer;
            attribs[i++] = kCGLPFAAccelerated;
            attribs[i++] = kCGLPFANoRecovery;
            attribs[i++] = kCGLPFAColorSize;
            attribs[i++] = (CGLPixelFormatAttribute)color_depths[c].color_size;
            attribs[i++] = kCGLPFAAlphaSize;
            attribs[i++] = (CGLPixelFormatAttribute)color_depths[c].alpha_size;
            attribs[i++] = kCGLPFADepthSize;
            attribs[i++] = 24;

            // Enable automatic graphics switching support, important on Macs
            // with dedicated GPUs, as it allows to not always use the dedicated
            // GPU which has more power consumption
            attribs[i++] = kCGLPFASupportsAutomaticGraphicsSwitching;

            // A low power renderer was found, ask to use it.
            if (renderer_id != -1) {
                attribs[i++] = kCGLPFARendererID;
                attribs[i++] = (CGLPixelFormatAttribute)renderer_id;
            }

            attribs[i++] = 0;

            err = CGLChoosePixelFormat(attribs, &pix, &npix);
            if (err == kCGLNoError && pix != NULL) {
                success_profile = profiles[p].name;
                success_color = color_depths[c].color_size;
                success_alpha = color_depths[c].alpha_size;
                goto found;
            }
        }
    }

    return NULL;

found:
    err = CGLCreateContext(pix, NULL, &ctx);
    if (err != kCGLNoError || ctx == NULL) {
        CGLDestroyPixelFormat(pix);
        return NULL;
    }

    CGLDestroyPixelFormat(pix);

    if (gl != NULL) {
        msg_Dbg(gl, "Created CGL context with %s profile, %d-bit color (%d-bit alpha)",
                success_profile, success_color, success_alpha);
    }

    return ctx;
}

static int SetViewpoint(vout_display_t *vd, const vlc_viewpoint_t *vp)
{
    vout_display_sys_t *sys = vd->sys;
    if (vlc_gl_MakeCurrent(sys->gl) != VLC_SUCCESS)
        return VLC_EGENERIC;

    sys->viewpoint = *vp;
    int ret = vout_display_opengl_SetViewpoint(sys->vgl, vp);
    vlc_gl_ReleaseCurrent(sys->gl);
    return ret;
}

static int ChangeSourceProjection(vout_display_t *vd, video_projection_mode_t projection)
{
    vout_display_sys_t *sys = vd->sys;
    sys->projection = projection;
    sys->change_projection = true;
    return VLC_SUCCESS;
}

/**
 * Flush the OpenGL context
 * In case of double-buffering swaps the back buffer with the front buffer.
 * \note This function implicitly calls \c glFlush() before it returns.
 */
static void gl_cb_Swap(vlc_gl_t *vlc_gl)
{
    VLCVideoLayerView *view = (__bridge VLCVideoLayerView *)vlc_gl->sys;
    [view swap];
}

/**
 * Make the OpenGL context the current one
 * Makes the CGL context the current context, if it is not already the current one,
 * and locks it.
 */
static int gl_cb_MakeCurrent(vlc_gl_t *vlc_gl)
{
    VLCVideoLayerView *view = (__bridge VLCVideoLayerView *)vlc_gl->sys;
    return [view lockContext];
}

/**
 * Make the OpenGL context no longer current one.
 * Makes the previous context the current one and unlocks the CGL context.
 */
static void gl_cb_ReleaseCurrent(vlc_gl_t *vlc_gl)
{
    VLCVideoLayerView *view = (__bridge VLCVideoLayerView *)vlc_gl->sys;
    [view unlockContext];
}

/**
 * Look up OpenGL symbols by name
 */
static void *gl_cb_GetProcAddress(vlc_gl_t *vlc_gl, const char *name)
{
    VLC_UNUSED(vlc_gl);

    return dlsym(RTLD_DEFAULT, name);
}

static void CloseOpenGL(vlc_gl_t *gl)
{
    VLCVideoLayerView *view = (__bridge_transfer VLCVideoLayerView *)gl->sys;
    [view vlcClose];
    view = nil;

}

static int OpenOpenGL(vlc_gl_t *gl, unsigned width, unsigned height,
                      const struct vlc_gl_cfg *cfg)
{
    id container = (__bridge id)gl->surface->handle.nsobject;
    if (!container) {
        msg_Err(gl, "No drawable-nsobject found!");
        return VLC_ENOTSUP;
    }

    dispatch_sync(dispatch_get_main_queue(), ^{
        @autoreleasepool {
            VLCVideoLayerView *videoView = [[VLCVideoLayerView alloc] init:gl];
            if (videoView == nil)
                return;
            gl->sys = (__bridge_retained void*)videoView;
        }
    });

    if (unlikely(gl->sys == NULL))
        return VLC_ENOMEM;

    static const struct vlc_gl_operations gl_ops =
    {
        .make_current = gl_cb_MakeCurrent,
        .release_current = gl_cb_ReleaseCurrent,
        .swap = gl_cb_Swap,
        .get_proc_address = gl_cb_GetProcAddress,
    };
    gl->ops = &gl_ops;
    gl->api_type = VLC_OPENGL;

    return VLC_SUCCESS;
}

#pragma mark -
#pragma mark Module functions

static void Close(vout_display_t *vd)
{
    vout_display_sys_t *sys = vd->sys;

    if (sys->vgl && !vlc_gl_MakeCurrent(sys->gl)) {
        vout_display_opengl_Delete(sys->vgl);
        vlc_gl_ReleaseCurrent(sys->gl);
    }


    if (sys->gl) {
        CloseOpenGL(sys->gl);
        vlc_object_delete(sys->gl);
    }
}

static void PictureRender (vout_display_t *vd, picture_t *pic,
                           const vlc_render_subpicture *subpicture,
                           vlc_tick_t date)
{
    VLC_UNUSED(date);
    vout_display_sys_t *sys = vd->sys;

    if (vlc_gl_MakeCurrent(sys->gl) == VLC_SUCCESS)
    {
        if (sys->change_projection)
        {
            vout_display_opengl_ChangeProjection(sys->vgl, sys->projection);
            vout_display_opengl_Viewport(sys->vgl, sys->place.x, sys->place.y,
                                        sys->place.width, sys->place.height);
            vout_display_opengl_SetOutputSize(sys->vgl, sys->cfg.display.width, sys->cfg.display.height);

            sys->change_projection = false;
        }
        vout_display_opengl_Prepare(sys->vgl, pic, subpicture);
        vlc_gl_ReleaseCurrent(sys->gl);

        VLCVideoLayerView *view = (__bridge VLCVideoLayerView *)sys->gl->sys;
        VLCCAOpenGLLayer *layer = (VLCCAOpenGLLayer *)[view layer];
        [layer markReady];
    }
}

static void PictureDisplay (vout_display_t *vd, picture_t *pic)
{
    vout_display_sys_t *sys = vd->sys;
    VLC_UNUSED(pic);

    VLCVideoLayerView *view = (__bridge VLCVideoLayerView *)sys->gl->sys;
    VLCCAOpenGLLayer *layer = (VLCCAOpenGLLayer *)[view layer];
    [layer displayFromVout];
}

static int PlacementChanged(vout_display_t *vd, const vout_display_place_t *place)
{
    vout_display_sys_t *sys = vd->sys;
    VLC_UNUSED(place);

    if (!sys)
        return VLC_EGENERIC;

    VLCVideoLayerView *view = (__bridge VLCVideoLayerView *)sys->gl->sys;
    VLCCAOpenGLLayer *layer = (VLCCAOpenGLLayer *)[view layer];

    @synchronized(layer)
    {
        vout_display_cfg_t cfg = *vd->cfg;
        cfg.display.width = sys->cfg.display.width;
        cfg.display.height = sys->cfg.display.height;

        sys->cfg = cfg;

        vout_display_PlacePicture(&sys->place, vd->source, &cfg.display);
        // Reverse vertical alignment as the GL tex are Y inverted
        sys->place.y = cfg.display.height - (sys->place.y + sys->place.height);
    }

    // Note!
    // No viewport or aspect ratio is set here, as that needs to be set
    // when rendering. The viewport is always set to match the layer
    // size by the OS right before the OpenGL render callback, so
    // setting it here has no effect.
    return VLC_SUCCESS;
}

static int AspectChanged(vout_display_t *vd, const video_format_t *source)
{
    vout_display_sys_t *sys = vd->sys;

    if (!sys)
        return VLC_EGENERIC;

    VLCVideoLayerView *view = (__bridge VLCVideoLayerView *)sys->gl->sys;
    VLCCAOpenGLLayer *layer = (VLCCAOpenGLLayer *)[view layer];

    @synchronized(layer)
    {
        vout_display_cfg_t cfg = *vd->cfg;
        cfg.display.width = sys->cfg.display.width;
        cfg.display.height = sys->cfg.display.height;

        sys->cfg = cfg;

        vout_display_PlacePicture(&sys->place, source, &cfg.display);
        // Reverse vertical alignment as the GL tex are Y inverted
        sys->place.y = cfg.display.height - (sys->place.y + sys->place.height);
    }

    // Note!
    // No viewport or aspect ratio is set here, as that needs to be set
    // when rendering. The viewport is always set to match the layer
    // size by the OS right before the OpenGL render callback, so
    // setting it here has no effect.
    return VLC_SUCCESS;
}

/*****************************************************************************
 * Open: This function allocates and initializes the OpenGL vout method.
 *****************************************************************************/
static int Open (vout_display_t *vd,
                 video_format_t *fmt, vlc_video_context *context)
{
    vout_display_sys_t *sys;
    if (vd->cfg->window->type != VLC_WINDOW_TYPE_NSOBJECT)
        return VLC_EGENERIC;

    @autoreleasepool {
        vout_display_sys_t *sys;

        // Only use this video output on macOS 10.14 or higher
        // currently, as it has some issues on at least macOS 10.7
        // and the old NSView based output still works fine on old
        // macOS versions.
        if (@available(macOS 10.14, *)) {
            // This is intentionally left empty, as the check
            // can not be negated or combined with other conditions!
        } else if (!vd->obj.force) {
            return VLC_EGENERIC;
        }

        vd->sys = sys = calloc(1, sizeof(*sys));
        if (sys == NULL)
            return VLC_ENOMEM;
        sys->projection = vd->cfg->projection;
        sys->change_projection = false;

        id container = (__bridge id)vd->cfg->window->handle.nsobject;
        if (!container) {
            msg_Err(vd, "No drawable-nsobject found!");
            Close(vd);
            return VLC_EGENERIC;
        }

        // Create a pseudo-context object which provides needed callbacks
        // for VLC to deal with the CGL context. Usually this should be done
        // by a proper opengl provider module, but we do not have that currently.
        sys->gl = vlc_object_create(vd, sizeof(*sys->gl));
        if (unlikely(!sys->gl))
        {
            Close(vd);
            return VLC_ENOMEM;
        }
        sys->gl->surface = vd->cfg->window;

        const struct vlc_gl_cfg gl_cfg = {
            .need_alpha = false,
        };

        int ret = OpenOpenGL(sys->gl, vd->cfg->display.width, vd->cfg->display.height, &gl_cfg);
        if (ret != VLC_SUCCESS) {
            Close(vd);
            return ret;
        }

        if (fmt->mastering.max_luminance == 0 && vd->source->mastering.max_luminance != 0)
            fmt->mastering = vd->source->mastering;
        if (fmt->lighting.MaxCLL == 0 && vd->source->lighting.MaxCLL != 0)
            fmt->lighting = vd->source->lighting;

        if (fmt->mastering.max_luminance > 0) {
            msg_Dbg(vd, "HDR mastering display: primaries [R: %.4f, %.4f, G: %.4f, %.4f, B: %.4f, %.4f], white point [%.4f, %.4f], min/max luminance [%u, %u]",
                    fmt->mastering.primaries[4] / 50000.0, fmt->mastering.primaries[5] / 50000.0,
                    fmt->mastering.primaries[0] / 50000.0, fmt->mastering.primaries[1] / 50000.0,
                    fmt->mastering.primaries[2] / 50000.0, fmt->mastering.primaries[3] / 50000.0,
                    fmt->mastering.white_point[0] / 50000.0, fmt->mastering.white_point[1] / 50000.0,
                    fmt->mastering.min_luminance, fmt->mastering.max_luminance);
        }
        if (fmt->lighting.MaxCLL > 0 || fmt->lighting.MaxFALL > 0) {
            msg_Dbg(vd, "HDR content light level: MaxCLL %u cd/m², MaxFALL %u cd/m²",
                    fmt->lighting.MaxCLL, fmt->lighting.MaxFALL);
        }

        bool is_hdr = (fmt->transfer == TRANSFER_FUNC_SMPTE_ST2084 ||
                       fmt->transfer == TRANSFER_FUNC_HLG ||
                       vd->source->transfer == TRANSFER_FUNC_SMPTE_ST2084 ||
                       vd->source->transfer == TRANSFER_FUNC_HLG);

        dispatch_sync(dispatch_get_main_queue(), ^{

            __weak VLCVideoLayerView *view = (__bridge VLCVideoLayerView *)sys->gl->sys;
            __weak VLCCAOpenGLLayer *layer = (VLCCAOpenGLLayer *)[view layer];
            [view setHDR:is_hdr];
            sys->cfg = *vd->cfg;

            vout_display_PlacePicture(&sys->place, vd->source, &vd->cfg->display);
            // Reverse vertical alignment as the GL tex are Y inverted
            sys->place.y = vd->cfg->display.height - (sys->place.y + sys->place.height);

            @synchronized(layer) {
                layer.render = ^(NSSize displaySize){
                    @synchronized(layer)
                    {
                        sys->cfg.display.width = displaySize.width;
                        sys->cfg.display.height = displaySize.height;

                        vout_display_PlacePicture(&sys->place, vd->source, &sys->cfg.display);
                    }

                    // Ensure viewport and aspect ratio is correct
                    vout_display_opengl_Viewport(sys->vgl, sys->place.x, sys->place.y,
                                                sys->place.width, sys->place.height);
                    vout_display_opengl_SetOutputSize(sys->vgl, sys->cfg.display.width, sys->cfg.display.height);

                    vout_display_opengl_Display(sys->vgl);

                };
            }
        });


        // Initialize OpenGL video display
        const vlc_fourcc_t *spu_chromas;

        if (vlc_gl_MakeCurrent(sys->gl))
        {
            Close(vd);
            return VLC_EGENERIC;
        }

        sys->viewpoint = vd->cfg->viewpoint;
        sys->vgl = vout_display_opengl_New(fmt, &spu_chromas, sys->gl,
                                           &vd->cfg->viewpoint, context);
        vlc_gl_ReleaseCurrent(sys->gl);

        if (sys->vgl == NULL) {
            msg_Err(vd, "Error while initializing OpenGL display");
            Close(vd);
            return VLC_EGENERIC;
        }

        vd->info.subpicture_chromas = spu_chromas;

        static const struct vlc_display_operations ops = {
            .close = Close,
            .prepare = PictureRender,
            .display = PictureDisplay,
            .set_viewpoint = SetViewpoint,
            .change_source_projection = ChangeSourceProjection,
            .video_place_changed = PlacementChanged,
            .set_source_aspect = AspectChanged,
            .set_source_crop = AspectChanged,
        };
        vd->ops = &ops;

        return VLC_SUCCESS;
    }
}

#pragma mark -
#pragma mark VLCVideoLayerView

@implementation VLCVideoLayerView

- (instancetype)init:(vlc_gl_t *)gl
{
    self = [super init];
    if (self == nil)
        return nil;
    _gl = gl;
    _isHDR = NO;

    _context = vlc_CreateCGLContext(gl);
    if (_context == NULL) {
        msg_Err(_gl, "Failure to create CGL context!");
        return nil;
    }

    _container = (__bridge id)gl->surface->handle.nsobject;
    assert(_container != nil);

    // Add video view to container
    if ([_container respondsToSelector:@selector(addVoutSubview:)]) {
        [_container addVoutSubview:self];
    } else if ([_container isKindOfClass:[NSView class]]) {
        NSView *containerView = _container;
        [containerView addSubview:self];
        [self setFrame:containerView.bounds];
    } else {
        CGLReleaseContext(_context);
        _context = NULL;
        return nil;
    }

    self.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.wantsLayer = YES;

    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self
           selector:@selector(screenParametersDidChange:)
               name:NSApplicationDidChangeScreenParametersNotification
             object:nil];
    [nc addObserver:self
           selector:@selector(windowDidChangeScreen:)
               name:NSWindowDidChangeScreenNotification
             object:nil];

    return self;
}

- (void)viewDidMoveToWindow
{
    [super viewDidMoveToWindow];
    [self updateDynamicRangeProperties];
}

- (void)screenParametersDidChange:(NSNotification *)notification
{
    [self updateDynamicRangeProperties];
}

- (void)windowDidChangeScreen:(NSNotification *)notification
{
    if (notification.object == nil || notification.object == self.window) {
        [self updateDynamicRangeProperties];
    }
}

- (void)setHDR:(BOOL)isHDR
{
    _isHDR = isHDR;
    [self updateDynamicRangeProperties];
}

- (void)updateDynamicRangeProperties
{
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self updateDynamicRangeProperties];
        });
        return;
    }

    NSScreen *screen = self.window.screen;
    if (screen == nil) {
        screen = [NSScreen mainScreen];
    }

    CGFloat headroom = 1.0;
    if (screen != nil) {
        if (@available(macOS 10.15, *)) {
            if ([screen respondsToSelector:@selector(maximumExtendedDynamicRangeColorComponentValue)]) {
                headroom = screen.maximumExtendedDynamicRangeColorComponentValue;
            }
        }
    }
    if (headroom < 1.0) {
        headroom = 1.0;
    }

    VLCCAOpenGLLayer *layer = (VLCCAOpenGLLayer *)self.layer;
    if (layer != nil && [layer isKindOfClass:[VLCCAOpenGLLayer class]]) {
        [layer updateDynamicRangeWithHeadroom:headroom isHDR:_isHDR];
    }
}

- (int)lockContext {
    _context_previous = CGLGetCurrentContext();

    CGLError err;
    if (_context_previous != _context) {
        err = CGLSetCurrentContext(_context);
        if (err != kCGLNoError) {
            msg_Err(_gl, "Failure setting current CGLContext: %s", CGLErrorString(err));
            return VLC_EGENERIC;
        }
    }

    err = CGLLockContext(_context);
    if (err != kCGLNoError) {
        msg_Err(_gl, "Failure locking CGLContext: %s", CGLErrorString(err));
        return VLC_EGENERIC;
    }
    return VLC_SUCCESS;
}

- (void)unlockContext {
    CGLError err;

    assert(CGLGetCurrentContext() == _context);

    err = CGLUnlockContext(_context);
    if (err != kCGLNoError) {
        msg_Err(_gl, "Failure unlocking CGLContext: %s", CGLErrorString(err));
        abort();
    }

    if (_context_previous != _context) {
        err = CGLSetCurrentContext(_context_previous);
        if (err != kCGLNoError) {
            msg_Err(_gl, "Failure restoring previous CGLContext: %s", CGLErrorString(err));
            abort();
        }
    }

    _context_previous = NULL;
}

- (void)swap {
    // Copies a double-buffered contexts back buffer to front buffer, calling
    // glFlush before this is not needed and discouraged for performance reasons.
    // An implicit glFlush happens before CGLFlushDrawable returns.
    CGLFlushDrawable(_context);
}

/**
 * Invalidates VLC objects (notably _vlc_vd)
 * This method must be called in VLCs module Close (or indirectly by the View)
 * to ensure all critical VLC resources that might be gone when the module is
 * closed are properly NULLed. This is necessary as dealloc is only called later
 * as it has to be done async on the main thread, because NSView must be
 * dealloc'ed on the main thread and the view own the layer, so the layer
 * will stay valid until the view is gone, and might still use _vlc_vd
 * even after the VLC module is gone and the resources would be invalid.
 */
- (void)vlcClose
{
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc removeObserver:self name:NSApplicationDidChangeScreenParametersNotification object:nil];
    [nc removeObserver:self name:NSWindowDidChangeScreenNotification object:nil];

    VLCCAOpenGLLayer *layer = (VLCCAOpenGLLayer *)[self layer];
    [layer vlcClose];

    @synchronized (layer) {
        _gl = NULL;

        // It should never happen that the context is destroyed and we
        // still have a previous context set, as it would mean non-balanced
        // calls to MakeCurrent/ReleaseCurrent.
        assert(_context_previous == NULL);
    }
    if (_context != NULL) {
        CGLReleaseContext(_context);
        _context = NULL;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        // Remove vout subview from container
        if ([_container respondsToSelector:@selector(removeVoutSubview:)]) {
            [_container removeVoutSubview:self];
        }
        [self removeFromSuperview];
    });
}

- (void)dealloc
{
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc removeObserver:self name:NSApplicationDidChangeScreenParametersNotification object:nil];
    [nc removeObserver:self name:NSWindowDidChangeScreenNotification object:nil];

    if (_context != NULL) {
        CGLReleaseContext(_context);
        _context = NULL;
    }
}

- (void)viewWillStartLiveResize
{
    [(VLCCAOpenGLLayer *)self.layer setAsynchronous:YES];
}

- (void)viewDidEndLiveResize
{
    [(VLCCAOpenGLLayer *)self.layer setAsynchronous:NO];
}

- (CALayer *)makeBackingLayer
{
    @synchronized(self) {
        NSAssert(_gl != NULL, @"Cannot create backing layer without vout display!");

        assert(_context != NULL);
        VLCCAOpenGLLayer *layer = [[VLCCAOpenGLLayer alloc] init:_gl context:_context];
        layer.delegate = self;
        return layer;
    }
}

/* Layer delegate method that ensures the layer always get the
 * correct contentScale based on whether the view is on a HiDPI
 * display or not, and when it is moved between displays.
 */
- (BOOL)layer:(CALayer *)layer
shouldInheritContentsScale:(CGFloat)newScale
   fromWindow:(NSWindow *)window
{
    return YES;
}

/*
 * General properties
 */

- (BOOL)isOpaque
{
    return YES;
}

@end

#pragma mark -
#pragma mark VLCCAOpenGLLayer

@implementation VLCCAOpenGLLayer

- (instancetype)init:(vlc_gl_t *)gl context:(CGLContextObj)context
{
    self = [super init];
    if (self) {
        _displayLock = [[NSLock alloc] init];
        _gl = gl;

        _glContext = CGLRetainContext(context);
        assert(_glContext != NULL);

        atomic_init(&_is_ready, false);

        [CATransaction lock];
        self.needsDisplayOnBoundsChange = YES;
        self.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
        self.asynchronous = NO;
        self.opaque = 1.0;
        self.hidden = NO;
#if __MAC_OS_X_VERSION_MAX_ALLOWED >= 101500
        if (@available(macOS 10.15, *)) {
            self.wantsExtendedDynamicRangeContent = YES;
            CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceExtendedLinearDisplayP3);
            if (cs) {
                self.colorspace = cs;
                CGColorSpaceRelease(cs);
            }
        }
#endif
        [CATransaction unlock];

        NSScreen *screen = [NSScreen mainScreen];
        CGFloat headroom = 1.0;
        if (screen != nil) {
            if (@available(macOS 10.15, *)) {
                if ([screen respondsToSelector:@selector(maximumExtendedDynamicRangeColorComponentValue)]) {
                    headroom = screen.maximumExtendedDynamicRangeColorComponentValue;
                }
            }
        }
        if (headroom < 1.0) {
            headroom = 1.0;
        }
        [self updateDynamicRangeWithHeadroom:headroom isHDR:NO];
    }

    return self;
}

- (void)updateDynamicRangeWithHeadroom:(CGFloat)headroom isHDR:(BOOL)isHDR
{
    [CATransaction lock];
#if __MAC_OS_X_VERSION_MAX_ALLOWED >= 101500
    if (@available(macOS 10.15, *)) {
        if ([self respondsToSelector:@selector(setWantsExtendedDynamicRangeContent:)]) {
            self.wantsExtendedDynamicRangeContent = YES;
        }
    }
#endif
#if __MAC_OS_X_VERSION_MAX_ALLOWED >= 140000
    if (@available(macOS 14.0, *)) {
        if ([self respondsToSelector:@selector(setPreferredDynamicRange:)]) {
            self.preferredDynamicRange = isHDR ? CADynamicRangeHigh : CADynamicRangeStandard;
        }
        if ([self respondsToSelector:@selector(setContentsHeadroom:)]) {
            self.contentsHeadroom = headroom;
        }
    }
#endif
#if __MAC_OS_X_VERSION_MAX_ALLOWED >= 150000
    if (@available(macOS 15.0, *)) {
        if ([self respondsToSelector:@selector(setToneMapMode:)]) {
            self.toneMapMode = isHDR ? CAToneMapModeIfSupported : CAToneMapModeAutomatic;
        }
    }
#endif
    [CATransaction unlock];
}

- (void)markReady {
    atomic_store(&_is_ready, true);
}

/**
 * Invalidates VLC objects (notably _voutDisplay)
 * This method must be called in VLCs module Close (or indirectly by the View).
 */
- (void)vlcClose
{
    @synchronized (self) {
        atomic_store(&_is_ready, false);
        _gl = NULL;
    }
}

- (void)dealloc
{
    CGLReleaseContext(_glContext);
}

- (void)display
{
    [_displayLock lock];

    [super display];
    [CATransaction flush];

    [_displayLock unlock];
}

- (void)displayFromVout
{
    if (self.asynchronous) {
        // During live resizing we do not take updates
        // from the vout, as those would interfere with
        // the rendering currently happening on the main
        // thread for the resize. Rendering anyway happens
        // triggered by the OS every display refresh, so
        // forcing an update here would be useless anyway.
        return;
    }

    [self display];
}

- (BOOL)canDrawInCGLContext:(CGLContextObj)glContext
                pixelFormat:(CGLPixelFormatObj)pixelFormat
               forLayerTime:(CFTimeInterval)timeInterval
                displayTime:(const CVTimeStamp *)timeStamp
{
    @synchronized(self) {
        if (!_gl)
            return NO;
        return _is_ready;
    }
}

- (void)drawInCGLContext:(CGLContextObj)glContext
             pixelFormat:(CGLPixelFormatObj)pixelFormat
            forLayerTime:(CFTimeInterval)timeInterval
             displayTime:(const CVTimeStamp *)timeStamp
{
    @synchronized(self) {
        if (!_gl)
            return;

        if (vlc_gl_MakeCurrent(_gl))
            return;

        GLint dims[4] = { 0, 0, 0, 0 };
        glGetIntegerv(GL_VIEWPORT, dims);
        NSSize newSize = NSMakeSize(dims[2], dims[3]);

        if (NSEqualSizes(newSize, NSZeroSize)) {
            newSize = self.bounds.size;
            CGFloat scale = self.contentsScale;
            newSize.width *= scale;
            newSize.height *= scale;
        }

        if (self.render != nil)
            self.render(newSize);

        vlc_gl_ReleaseCurrent(_gl);
        vlc_gl_Swap(_gl);
    }
}

- (CGLPixelFormatObj)copyCGLPixelFormatForDisplayMask:(uint32_t)mask
{
    CGLPixelFormatObj fmt = CGLGetPixelFormat(_glContext);

    return (fmt) ? CGLRetainPixelFormat(fmt) : NULL;
}

- (CGLContextObj)copyCGLContextForPixelFormat:(CGLPixelFormatObj)pixelFormat
{
    return CGLRetainContext(_glContext);
}

@end

/*
 * Module descriptor
 */
vlc_module_begin()
    set_description(N_("Core Animation OpenGL Layer (Mac OS X)"))
    set_subcategory(SUBCAT_VIDEO_VOUT)
    set_callback_display(Open, 300)

    add_opengl_submodule_renderer()
vlc_module_end()
