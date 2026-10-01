/*****************************************************************************
 * MacLCMetalDisplay.m: native Metal video output display module for MacLC
 *****************************************************************************
 * Copyright (C) 2026 Hazen Studio
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

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#import "MacLCMetalDisplay.h"
#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>
#import <Metal/Metal.h>

#include <vlc_common.h>
#include <vlc_plugin.h>
#include <vlc_vout_display.h>
#include <vlc_picture.h>
#include <vlc_filter.h>
#include <vlc_codec.h>
#include <vlc_ancillary.h>

#include "codec/vt_utils.h"
#include "maclc_hdr_vars.h"
#include "maclc_tonemap.h"
#include "MacLCHDRToneMapper.h"
#include "MacLCSDR2HDRSession.h"
#include "MacLCMetalRenderer.h"
#import "MacLCMetalScaler.h"
#import "MacLCMetal360.h"
#import "MacLCMetalLUT.h"
#import "MacLCMetalDovi.h"
#import "MacLCMetalColorPass.h"

#pragma mark - Embedding Protocol

@protocol VLCOpenGLVideoViewEmbedding <NSObject>
- (void)addVoutSubview:(NSView *)view;
- (void)removeVoutSubview:(NSView *)view;
@end

#pragma mark - View Interface

@interface MacLCMetalVideoView : NSView

@property (nonatomic) float userHeadroom;
@property (nonatomic) int hdrMode;
@property (nonatomic) vout_display_t *vd;

- (nullable instancetype)initWithContainer:(id)container display:(vout_display_t *)vd;
- (void)vlcClose;
- (CGSize)currentDrawableSize;
- (float)effectiveHeadroom;
- (void)updateDynamicRangeProperties;

@end

#pragma mark - Display sys struct

typedef struct vout_display_sys_t {
    MacLCMetalVideoView *view;
    MacLCMetalRenderer *renderer;
    MacLCSDR2HDRSession *sdr2hdrSession;
    MacLCHDRToneMapper *toneMapper;
    MacLCMetalDovi *dovi;            /* created with the first RPU */
    MacLCMetalColorPass *colorPass;  /* tone maps linear light (Dolby Vision, curves) */
    filter_t *converter;

    bool doviProfile5;   /* no usable base layer: RPUs are always applied */
    int toneCurve;       /* gl-tone-mapping-function, 0 = MacLC's picture modes */
    float toneParam;     /* gl-tone-mapping-param */

    int user_hdr_mode;
    float user_headroom;
    enum maclc_hdr_presentation maclcPresentation;
    enum maclc_hdr_picture maclcPicture;
    enum maclc_hdr_hlg maclcHLG;

    int64_t seenCaps;
    int64_t publishedCaps;
    const char *publishedActive;

    vout_display_place_t place;
    id<MTLTexture> stageATexture;
    /* The processed picture stage A made, kept until the next one replaces it:
     * the texture above reads its IOSurface, which its pool must not recycle
     * before Display has drawn it. */
    CVPixelBufferRef stageABuffer;

    /* Change tracking for debug logging */
    BOOL hasLoggedOutputMode;
    BOOL lastLoggedEDR;
    float lastLoggedHeadroom;
    const char *lastLoggedStageAPath;
    bool hasLoggedDoviFailure;
    bool doviDumped;
    CGSize lastLoggedDrawableSize;
    CGRect lastLoggedPlacement;
} vout_display_sys_t;

#pragma mark - View Implementation

@implementation MacLCMetalVideoView {
    id _container;
    CGSize _currentDrawableSize;
    float _effectiveHeadroom;
}

+ (Class)layerClass
{
    return [CAMetalLayer class];
}

- (CALayer *)makeBackingLayer
{
    CAMetalLayer *layer = [CAMetalLayer layer];
    layer.device = MTLCreateSystemDefaultDevice();
    layer.pixelFormat = MTLPixelFormatRGBA16Float;
    layer.framebufferOnly = YES;
    layer.maximumDrawableCount = 3;
    layer.displaySyncEnabled = YES;
    layer.opaque = YES;

    /* The layer always receives linear light in Display P3 primaries with SDR white at 1.0 */
    CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceExtendedLinearDisplayP3);
    if (cs != NULL) {
        layer.colorspace = cs;
        CGColorSpaceRelease(cs);
    }
    return layer;
}

- (nullable instancetype)initWithContainer:(id)container display:(vout_display_t *)vd
{
    self = [super initWithFrame:NSZeroRect];
    if (self == nil || container == nil)
        return nil;

    _container = container;
    _vd = vd;
    _hdrMode = 0;
    _userHeadroom = 0.0f;
    _effectiveHeadroom = 1.0f;
    _currentDrawableSize = CGSizeMake(1, 1);

    self.wantsLayer = YES;
    self.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    /* Embed into container exactly like VLCVideoLayerView */
    if ([_container respondsToSelector:@selector(addVoutSubview:)]) {
        [_container addVoutSubview:self];
    } else if ([_container isKindOfClass:[NSView class]]) {
        NSView *containerView = (NSView *)_container;
        [containerView addSubview:self];
        [self setFrame:containerView.bounds];
    } else {
        return nil;
    }

    [self updateDrawableSize];

    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self
           selector:@selector(screenParametersDidChange:)
               name:NSApplicationDidChangeScreenParametersNotification
             object:nil];
    [nc addObserver:self
           selector:@selector(windowDidChangeScreen:)
               name:NSWindowDidChangeScreenNotification
             object:nil];
    [nc addObserver:self
           selector:@selector(windowDidChangeScreenProfile:)
               name:NSWindowDidChangeScreenProfileNotification
             object:nil];

    [self updateDynamicRangeProperties];
    return self;
}

- (void)updateDrawableSize
{
    CAMetalLayer *metalLayer = (CAMetalLayer *)self.layer;
    if (metalLayer == nil || ![metalLayer isKindOfClass:[CAMetalLayer class]])
        return;

    CGFloat scale = self.window ? self.window.backingScaleFactor : [NSScreen mainScreen].backingScaleFactor;
    if (scale <= 0.0)
        scale = 1.0;
    metalLayer.contentsScale = scale;

    CGSize boundsSize = self.bounds.size;
    CGSize newSize = CGSizeMake(ceil(boundsSize.width * scale), ceil(boundsSize.height * scale));
    if (newSize.width < 1.0) newSize.width = 1.0;
    if (newSize.height < 1.0) newSize.height = 1.0;

    metalLayer.drawableSize = newSize;

    @synchronized (self) {
        _currentDrawableSize = newSize;
    }
}

- (CGSize)currentDrawableSize
{
    @synchronized (self) {
        return _currentDrawableSize;
    }
}

- (float)effectiveHeadroom
{
    @synchronized (self) {
        return _effectiveHeadroom;
    }
}

- (void)setFrameSize:(NSSize)newSize
{
    [super setFrameSize:newSize];
    [self updateDrawableSize];
}

- (void)layout
{
    [super layout];
    [self updateDrawableSize];
}

- (void)viewDidChangeBackingProperties
{
    [super viewDidChangeBackingProperties];
    [self updateDrawableSize];
    [self updateDynamicRangeProperties];
}

- (void)viewDidMoveToWindow
{
    [super viewDidMoveToWindow];
    [self updateDrawableSize];
    [self updateDynamicRangeProperties];
}

- (void)screenParametersDidChange:(NSNotification *)notification
{
    VLC_UNUSED(notification);
    [self updateDynamicRangeProperties];
}

- (void)windowDidChangeScreen:(NSNotification *)notification
{
    if (notification.object == nil || notification.object == self.window)
        [self updateDynamicRangeProperties];
}

- (void)windowDidChangeScreenProfile:(NSNotification *)notification
{
    if (notification.object == nil || notification.object == self.window)
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

    CGFloat effectiveHeadroom = 1.0;
    if (_userHeadroom > 0.0f) {
        effectiveHeadroom = (_userHeadroom > 1.0f) ? (CGFloat)_userHeadroom : 1.0;
    } else {
        NSScreen *screen = self.window.screen;
        if (screen == nil)
            screen = [NSScreen mainScreen];

        CGFloat screenHeadroom = 1.0;
        if (screen != nil) {
            if (@available(macOS 10.15, *)) {
                if ([screen respondsToSelector:@selector(maximumExtendedDynamicRangeColorComponentValue)]) {
                    screenHeadroom = screen.maximumExtendedDynamicRangeColorComponentValue;
                    if (screenHeadroom <= 1.0 &&
                        [screen respondsToSelector:@selector(maximumPotentialExtendedDynamicRangeColorComponentValue)] &&
                        screen.maximumPotentialExtendedDynamicRangeColorComponentValue > 1.0) {
                        screenHeadroom = screen.maximumPotentialExtendedDynamicRangeColorComponentValue;
                    }
                }
            }
        }
        effectiveHeadroom = (screenHeadroom > 1.0) ? screenHeadroom : 1.0;
    }

    BOOL effectiveHDR;
    switch (_hdrMode) {
        case 1: /* Force HDR */
            effectiveHDR = YES;
            break;
        case 2: /* Tone-map to SDR */
        case 3: /* Disable HDR */
            effectiveHDR = NO;
            break;
        case 0: /* Auto */
        default:
            effectiveHDR = (effectiveHeadroom > 1.0);
            break;
    }

    CAMetalLayer *layer = (CAMetalLayer *)self.layer;
    if (layer != nil && [layer isKindOfClass:[CAMetalLayer class]]) {
        [CATransaction lock];
        if (@available(macOS 10.15, *)) {
            layer.wantsExtendedDynamicRangeContent = effectiveHDR;
        }
        if (@available(macOS 14.0, *)) {
            layer.preferredDynamicRange = effectiveHDR ? CADynamicRangeHigh : CADynamicRangeStandard;
            layer.contentsHeadroom = effectiveHDR ? effectiveHeadroom : 1.0;
        }
        if (@available(macOS 15.0, *)) {
            layer.toneMapMode = effectiveHDR ? CAToneMapModeIfSupported : CAToneMapModeAutomatic;
        }
        [CATransaction unlock];
    }

    @synchronized (self) {
        _effectiveHeadroom = (float)effectiveHeadroom;
        if (_vd != NULL) {
            var_SetFloat(_vd, "edr-headroom-effective", (float)effectiveHeadroom);
        }
    }
}

- (void)vlcClose
{
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc removeObserver:self name:NSApplicationDidChangeScreenParametersNotification object:nil];
    [nc removeObserver:self name:NSWindowDidChangeScreenNotification object:nil];
    [nc removeObserver:self name:NSWindowDidChangeScreenProfileNotification object:nil];

    @synchronized (self) {
        _vd = NULL;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        if ([_container respondsToSelector:@selector(removeVoutSubview:)]) {
            [_container removeVoutSubview:self];
        }
        [self removeFromSuperview];
    });
}

@end

#pragma mark - CVPX Converter Helpers

static vlc_decoder_device * CVPXHoldDecoderDevice(vlc_object_t *o, void *sys)
{
    VLC_UNUSED(o);
    vout_display_t *vd = sys;
    vlc_decoder_device *device =
        vlc_decoder_device_Create(VLC_OBJECT(vd), vd->cfg->window);
    static const struct vlc_decoder_device_operations ops =
    {
        NULL,
    };
    device->ops = &ops;
    device->type = VLC_DECODER_DEVICE_VIDEOTOOLBOX;
    return device;
}

static filter_t *
CreateCVPXConverter(vout_display_t *vd, const video_format_t *fmt)
{
    filter_t *converter = vlc_object_create(vd, sizeof(filter_t));
    if (!converter)
        return NULL;

    static const struct filter_video_callbacks cbs =
    {
        .buffer_new = NULL,
        .hold_device = CVPXHoldDecoderDevice,
    };
    converter->owner.video = &cbs;
    converter->owner.sys = vd;

    es_format_InitFromVideo(&converter->fmt_in, fmt);
    es_format_InitFromVideo(&converter->fmt_out, fmt);

    const vlc_chroma_description_t *desc =
        vlc_fourcc_GetChromaDescription(fmt->i_chroma);
    bool is_422_10b = desc != NULL &&
                      desc->subtype == VLC_CHROMA_SUBTYPE_YUV422 &&
                      desc->pixel_bits > 10;

    bool is_10bit_hdr = (fmt->i_chroma == VLC_CODEC_I420_10L ||
                         fmt->i_chroma == VLC_CODEC_I420_10B ||
                         fmt->i_chroma == VLC_CODEC_P010 ||
                         fmt->i_chroma == VLC_CODEC_CVPX_P010 ||
                         fmt->i_chroma == VLC_CODEC_CVPX_P216 ||
                         is_422_10b ||
                         fmt->transfer == TRANSFER_FUNC_SMPTE_ST2084 ||
                         fmt->transfer == TRANSFER_FUNC_HLG ||
                         fmt->primaries == COLOR_PRIMARIES_BT2020);

    /* Only buffers the renderer decodes: NV12, P010 and BGRA. 4:2:2
     * (P216, UYVY) would be read with the 4:2:0 layout. */
    if (is_10bit_hdr)
    {
        converter->fmt_out.video.i_chroma =
        converter->fmt_out.i_codec = VLC_CODEC_CVPX_P010;
    }
    else if (fmt->i_chroma == VLC_CODEC_NV12)
    {
        converter->fmt_out.video.i_chroma =
        converter->fmt_out.i_codec = VLC_CODEC_CVPX_NV12;
    }
    else
    {
        converter->fmt_out.video.i_chroma =
        converter->fmt_out.i_codec = VLC_CODEC_CVPX_BGRA;
    }

    converter->p_module = vlc_filter_LoadModule(converter, "video converter", NULL, false);
    if (!converter->p_module)
    {
        es_format_Clean(&converter->fmt_in);
        es_format_Clean(&converter->fmt_out);
        vlc_object_delete(converter);
        return NULL;
    }
    assert( converter->ops != NULL );

    return converter;
}

static void DeleteCVPXConverter(filter_t *p_converter)
{
    if (!p_converter)
        return;

    vlc_filter_UnloadModule(p_converter);
    es_format_Clean(&p_converter->fmt_in);
    es_format_Clean(&p_converter->fmt_out);
    vlc_object_delete(p_converter);
}

#pragma mark - Callbacks

/* The "SDR" presentation is tone mapping to SDR, as the native output's
 * effectiveHdrMode has it; every other presentation leaves macosx-hdr-mode
 * in charge. */
static int EffectiveHdrMode(const vout_display_sys_t *sys)
{
    return sys->maclcPresentation == MACLC_HDR_PRESENTATION_SDR ? 2 : sys->user_hdr_mode;
}

static int EdrHeadroomCallback(vlc_object_t *obj, char const *name,
                               vlc_value_t prev, vlc_value_t cur, void *data)
{
    VLC_UNUSED(obj); VLC_UNUSED(name); VLC_UNUSED(prev);
    vout_display_t *vd = data;
    vout_display_sys_t *sys = vd->sys;
    float val = cur.f_float;
    if (val > 0.0f && val < 1.0f)
        val = 1.0f;
    sys->user_headroom = val;
    sys->view.userHeadroom = val;
    [sys->view updateDynamicRangeProperties];
    return VLC_SUCCESS;
}

static int HdrModeCallback(vlc_object_t *obj, char const *name,
                           vlc_value_t prev, vlc_value_t cur, void *data)
{
    VLC_UNUSED(obj); VLC_UNUSED(name); VLC_UNUSED(prev);
    vout_display_t *vd = data;
    vout_display_sys_t *sys = vd->sys;
    sys->user_hdr_mode = (int)cur.i_int;
    sys->view.hdrMode = EffectiveHdrMode(sys);
    [sys->view updateDynamicRangeProperties];
    return VLC_SUCCESS;
}

static int MacLCPresentationCallback(vlc_object_t *obj, char const *name,
                                     vlc_value_t prev, vlc_value_t cur, void *data)
{
    VLC_UNUSED(obj); VLC_UNUSED(name); VLC_UNUSED(prev);
    vout_display_t *vd = data;
    vout_display_sys_t *sys = vd->sys;
    sys->maclcPresentation = maclc_hdr_presentation_parse(cur.psz_string);
    msg_Dbg(vd, "HDR presentation requested: %s",
            maclc_hdr_presentation_name(sys->maclcPresentation));
    const int mode = EffectiveHdrMode(sys);
    if (sys->view.hdrMode != mode) {
        sys->view.hdrMode = mode;
        [sys->view updateDynamicRangeProperties];
    }
    return VLC_SUCCESS;
}

static int MacLCPictureCallback(vlc_object_t *obj, char const *name,
                                vlc_value_t prev, vlc_value_t cur, void *data)
{
    VLC_UNUSED(obj); VLC_UNUSED(name); VLC_UNUSED(prev);
    vout_display_t *vd = data;
    vout_display_sys_t *sys = vd->sys;
    sys->maclcPicture = maclc_hdr_picture_parse(cur.psz_string);
    return VLC_SUCCESS;
}

static int MacLCHLGCallback(vlc_object_t *obj, char const *name,
                            vlc_value_t prev, vlc_value_t cur, void *data)
{
    VLC_UNUSED(obj); VLC_UNUSED(name); VLC_UNUSED(prev);
    vout_display_t *vd = data;
    vout_display_sys_t *sys = vd->sys;
    sys->maclcHLG = maclc_hdr_hlg_parse(cur.psz_string);
    return VLC_SUCCESS;
}

static void PublishHdrState(vout_display_t *vd, vout_display_sys_t *sys,
                            int64_t caps, const char *active)
{
    vlc_object_t *vout_obj = vlc_object_parent(vd);
    if (vout_obj == NULL)
        return;
    if (caps != sys->publishedCaps) {
        sys->publishedCaps = caps;
        var_SetInteger(vout_obj, MACLC_HDR_VAR_CAPS, caps);
    }
    if (active != sys->publishedActive) {
        sys->publishedActive = active;
        var_SetString(vout_obj, MACLC_HDR_VAR_ACTIVE, active);
    }
}

#pragma mark - Operations

static int PlacementChanged(vout_display_t *vd, const vout_display_place_t *place)
{
    VLC_UNUSED(place);
    vout_display_sys_t *sys = vd->sys;
    if (!sys)
        return VLC_EGENERIC;

    CGSize dsize = [sys->view currentDrawableSize];
    struct vout_display_placement cfg_display = vd->cfg->display;
    cfg_display.width = (unsigned)dsize.width;
    cfg_display.height = (unsigned)dsize.height;

    @synchronized (sys->view) {
        vout_display_PlacePicture(&sys->place, vd->source, &cfg_display);
    }
    return VLC_SUCCESS;
}

static int AspectChanged(vout_display_t *vd, const video_format_t *source)
{
    VLC_UNUSED(source);
    return PlacementChanged(vd, NULL);
}

/* 360-degree video: a projector draws the equirectangular or cubemap
 * picture from the viewpoint; rectangular video has none. */
static void SetUpProjection(vout_display_t *vd, video_projection_mode_t projection,
                            const vlc_viewpoint_t *viewpoint)
{
    vout_display_sys_t *sys = vd->sys;
    if (projection == PROJECTION_MODE_RECTANGULAR) {
        sys->renderer.projector = nil;
        return;
    }
    MacLCMetal360 *projector = sys->renderer.projector;
    if (projector == nil)
        projector = [[MacLCMetal360 alloc] initWithDevice:sys->renderer.device
                                              pixelFormat:MTLPixelFormatRGBA16Float];
    [projector setProjection:projection];
    if (viewpoint != NULL)
        [projector setViewpoint:viewpoint];
    sys->renderer.projector = projector;
    msg_Dbg(vd, "Metal output: %s projection", projector != nil ? "360-degree" : "no");
}

static int SetViewpoint(vout_display_t *vd, const vlc_viewpoint_t *vp)
{
    vout_display_sys_t *sys = vd->sys;
    if (sys == NULL)
        return VLC_EGENERIC;
    /* Flat video has no viewpoint to follow: nothing to do, not a failure. */
    if (sys->renderer.projector != nil)
        [sys->renderer.projector setViewpoint:vp];
    return VLC_SUCCESS;
}

static int ChangeSourceProjection(vout_display_t *vd, video_projection_mode_t projection)
{
    vout_display_sys_t *sys = vd->sys;
    if (sys == NULL)
        return VLC_EGENERIC;
    SetUpProjection(vd, projection, &vd->cfg->viewpoint);
    return VLC_SUCCESS;
}

/* The options the OpenGL engine offers on top of the picture: better scalers
 * (gl-upscaler, gl-downscaler) and a 3D LUT (gl-lut-file). */
static void SetUpOptionalStages(vout_display_t *vd)
{
    vout_display_sys_t *sys = vd->sys;
    const int up = var_InheritInteger(vd, "gl-upscaler");
    const int down = var_InheritInteger(vd, "gl-downscaler");
    if (up != 0 || down != 0) {
        MacLCMetalScaler *scaler = [[MacLCMetalScaler alloc] initWithDevice:sys->renderer.device];
        scaler.upscaler = up;
        scaler.downscaler = down;
        sys->renderer.scaler = scaler;
        msg_Dbg(vd, "Metal output: upscaler %d, downscaler %d", up, down);
    }
    char *lutPath = var_InheritString(vd, "gl-lut-file");
    if (lutPath != NULL && lutPath[0] != '\0') {
        NSError *error = nil;
        sys->renderer.lut = [MacLCMetalLUT lutWithCubeFile:@(lutPath)
                                                    device:sys->renderer.device
                                                     error:&error];
        if (sys->renderer.lut == nil)
            msg_Warn(vd, "Metal output: could not load the LUT %s: %s", lutPath,
                     error.localizedDescription.UTF8String ?: "unknown error");
        else
            msg_Dbg(vd, "Metal output: LUT %s", lutPath);
    }
    free(lutPath);
}

/* MacLC's picture mode for a master of content_peak on a display of
 * display_peak: the rule the native output and the interface share. */
static maclc_tone_mode ToneModeFor(enum maclc_hdr_picture picture,
                                   float content_peak, float display_peak)
{
    switch (picture) {
        case MACLC_HDR_PICTURE_ACCURATE: return MACLC_TONE_ACCURATE;
        case MACLC_HDR_PICTURE_BALANCED: return MACLC_TONE_BALANCED;
        case MACLC_HDR_PICTURE_BRIGHT:   return MACLC_TONE_BRIGHT;
        default:
            return maclc_hdr_needs_tone_mapping(content_peak > 0.0f ? content_peak : 1000.0f,
                                                display_peak)
                 ? MACLC_TONE_BALANCED : MACLC_TONE_ACCURATE;
    }
}

/* Peak of the current scene from HDR10+ metadata, in cd/m2 (0 if absent):
 * VLC carries maxscl linearised to [0, 1] of 10000 cd/m2. */
static float HDR10PlusScenePeak(const vlc_video_hdr_dynamic_metadata_t *h)
{
    if (h == NULL)
        return 0.0f;
    const float m = fmaxf(fmaxf(h->maxscl[0], h->maxscl[1]), h->maxscl[2]);
    return m > 0.0f ? fminf(m * 10000.0f, 10000.0f) : 0.0f;
}

/* Sets the colour pass up for content_peak -> display_peak: one of the OpenGL
 * engine's curves when the user picked one (or the ST 2094-40 curve the
 * HDR10+ presentation asks for), MacLC's picture modes otherwise. */
static void ConfigureColorPass(vout_display_sys_t *sys, float content_peak,
                               float display_peak,
                               const vlc_video_hdr_dynamic_metadata_t *hdr10plus,
                               bool st2094)
{
    if (st2094 || sys->toneCurve != 0) {
        const float input_max = content_peak > 0.0f ? content_peak : 1000.0f;
        const struct maclc_tonecurve_params curve = {
            .curve = st2094 ? MACLC_TC_ST2094_40 : (enum maclc_tonecurve)sys->toneCurve,
            .param = st2094 ? 0.0f : sys->toneParam,
            .input_min = 0.0f,
            .input_max = input_max,
            .output_min = 0.0f,
            /* Never above the content: curves that can run backwards (spline,
             * ST 2094-40) would otherwise stretch a dim master up to the
             * display's peak, which libplacebo only does when inverse tone
             * mapping is asked for. */
            .output_max = fminf(display_peak, input_max),
            .hdr10plus = hdr10plus,
        };
        [sys->colorPass setToneCurve:&curve];
    } else {
        maclc_tone_params params;
        maclc_tone_params_init(&params,
                               ToneModeFor(sys->maclcPicture, content_peak, display_peak),
                               content_peak, display_peak, MACLC_HDR_REFERENCE_WHITE);
        [sys->colorPass setToneParams:&params];
    }
}

/* Developer hook: MACLC_DEBUG_DUMP_DOVI=<prefix> writes the first Dolby
 * Vision picture - its RPU (<prefix>.rpu, the VLC struct as is), its base
 * layer planes (<prefix>.y, <prefix>.uv), the decoder's linear light and the
 * tone mapped result (<prefix>.lin, <prefix>.map, RGBA half floats) and the
 * parameters (<prefix>.json) - so the GPU can be checked against
 * maclc_dovi_decode_pixel() without a screen. */
static void DumpDolbyVision(vout_display_t *vd, const char *prefix,
                            CVPixelBufferRef pixelBuffer,
                            const vlc_video_dovi_metadata_t *rpu,
                            id<MTLBuffer> lin, id<MTLBuffer> map,
                            size_t width, size_t height,
                            float content_peak, float display_peak,
                            enum maclc_hdr_picture picture)
{
    char path[1024];
    FILE *f;
#define DUMP(ext, ptr, size) do { \
        snprintf(path, sizeof(path), "%s.%s", prefix, ext); \
        if ((f = fopen(path, "wb")) != NULL) { fwrite(ptr, 1, size, f); fclose(f); } \
    } while (0)

    DUMP("rpu", rpu, sizeof(*rpu));
    DUMP("lin", lin.contents, lin.length);
    DUMP("map", map.contents, map.length);

    CVPixelBufferLockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
    for (size_t plane = 0; plane < 2; plane++) {
        const uint8_t *base = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, plane);
        const size_t stride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, plane);
        const size_t rows = CVPixelBufferGetHeightOfPlane(pixelBuffer, plane);
        const size_t row_bytes = CVPixelBufferGetWidthOfPlane(pixelBuffer, plane)
                               * (plane == 0 ? 1 : 2)
                               * (CVPixelBufferGetPixelFormatType(pixelBuffer)
                                  == kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange ? 2 : 1);
        snprintf(path, sizeof(path), "%s.%s", prefix, plane == 0 ? "y" : "uv");
        if (base != NULL && (f = fopen(path, "wb")) != NULL) {
            for (size_t r = 0; r < rows; r++)
                fwrite(base + r * stride, 1, row_bytes, f);
            fclose(f);
        }
    }
    const OSType format = CVPixelBufferGetPixelFormatType(pixelBuffer);
    CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);

    snprintf(path, sizeof(path), "%s.json", prefix);
    if ((f = fopen(path, "w")) != NULL) {
        fprintf(f, "{\"width\": %zu, \"height\": %zu, \"format\": \"%c%c%c%c\", "
                   "\"content_peak\": %.3f, \"display_peak\": %.3f, \"picture\": %d, "
                   "\"rpu_size\": %zu}\n",
                width, height, (char)(format >> 24), (char)(format >> 16),
                (char)(format >> 8), (char)format, content_peak, display_peak,
                (int)picture, sizeof(*rpu));
        fclose(f);
    }
#undef DUMP
    msg_Dbg(vd, "Dolby Vision picture dumped to %s.*", prefix);
}

static void Prepare(vout_display_t *vd, picture_t *pic,
                    const struct vlc_render_subpicture *subpic, vlc_tick_t date)
{
    vout_display_sys_t *sys = vd->sys;
    if (!sys || !pic)
        return;

    /* Dynamic metadata travels with the decoded picture. */
    const vlc_video_dovi_metadata_t *rpu = NULL;
    const vlc_video_hdr_dynamic_metadata_t *hdr10plus = NULL;
    struct vlc_ancillary *anc = picture_GetAncillary(pic, VLC_ANCILLARY_ID_DOVI);
    if (anc != NULL)
        rpu = vlc_ancillary_GetData(anc);
    anc = picture_GetAncillary(pic, VLC_ANCILLARY_ID_HDR10PLUS);
    if (anc != NULL)
        hdr10plus = vlc_ancillary_GetData(anc);

    picture_Hold(pic);
    picture_t *dst = pic;
    if (sys->converter) {
        dst = sys->converter->ops->filter_video(sys->converter, pic);
        if (dst == NULL) /* the converter consumed pic */
            return;
    }

    CVPixelBufferRef pixelBuffer = cvpxpic_get_ref(dst);
    if (pixelBuffer != NULL)
        CVPixelBufferRetain(pixelBuffer);
    picture_Release(dst);

    if (pixelBuffer == NULL) {
        msg_Err(vd, "No CVPixelBuffer attached to picture!");
        return;
    }

    video_format_t render_fmt = vd->fmt ? *vd->fmt : pic->format;

    const bool source_is_pq = (render_fmt.transfer == TRANSFER_FUNC_SMPTE_ST2084);
    const bool source_is_hlg = (render_fmt.transfer == TRANSFER_FUNC_HLG);

    /* Which metadata drives this picture, as the OpenGL engine decides
     * (pl_scale.c): Dolby Vision RPUs whenever they are present, unless
     * another presentation was asked for (profile 5 has no usable base
     * layer, so its RPUs always apply); HDR10+ after that. */
    const enum maclc_hdr_presentation presentation = sys->maclcPresentation;
    const bool want_dovi = sys->doviProfile5
        || presentation == MACLC_HDR_PRESENTATION_AUTO
        || presentation == MACLC_HDR_PRESENTATION_DOLBYVISION;
    const bool use_rpu = rpu != NULL && want_dovi;
    const bool use_hdr10plus = hdr10plus != NULL && !use_rpu && source_is_pq
        && (presentation == MACLC_HDR_PRESENTATION_AUTO
            || presentation == MACLC_HDR_PRESENTATION_HDR10PLUS);
    /* The HDR10+ presentation, chosen explicitly, follows the curve the
     * metadata carries (ST 2094-40 Bezier) when it carries one; Automatic
     * only takes each scene's peak from it. */
    const bool use_st2094 = use_hdr10plus && hdr10plus->tone_mapping_flag
        && hdr10plus->num_bezier_anchors > 0
        && presentation == MACLC_HDR_PRESENTATION_HDR10PLUS;
    const bool source_is_hdr = source_is_pq || source_is_hlg || use_rpu;

    int64_t caps = sys->seenCaps;
    if (rpu != NULL)
        caps |= MACLC_HDR_CAP_DOVI_SEEN;
    if (hdr10plus != NULL)
        caps |= MACLC_HDR_CAP_HDR10PLUS_SEEN;
    sys->seenCaps = caps;

    float headroom = [sys->view effectiveHeadroom];
    const int hdr_mode = EffectiveHdrMode(sys);
    const bool is_edr = (hdr_mode == 0 || hdr_mode == 1) && (headroom > 1.0f);

    /* Output mode logging */
    if (!sys->hasLoggedOutputMode || sys->lastLoggedEDR != is_edr || fabsf(sys->lastLoggedHeadroom - headroom) > 0.05f) {
        msg_Dbg(vd, "Metal output mode: %s (headroom %.2f)", is_edr ? "EDR" : "SDR", headroom);
        sys->hasLoggedOutputMode = YES;
        sys->lastLoggedEDR = is_edr;
        sys->lastLoggedHeadroom = headroom;
    }

    id<MTLCommandBuffer> stageACmdBuf = [sys->renderer createCommandBuffer];
    id<MTLTexture> resultingTexture = nil;
    CVPixelBufferRef processed = NULL;
    const char *stageAPath = "plain decode";
    enum maclc_hdr_presentation rendered = MACLC_HDR_PRESENTATION_SDR;

    const float display_peak = is_edr ? maclc_hdr_peak_for_headroom(headroom)
                                      : MACLC_HDR_REFERENCE_WHITE;

    /* Stage A: 1. Dolby Vision: the RPU decodes the base layer to linear
     * light, the colour pass tone maps it for this display. */
    if (use_rpu) {
        if (sys->dovi == nil)
            sys->dovi = [[MacLCMetalDovi alloc] initWithDevice:sys->renderer.device];
        if (sys->colorPass == nil)
            sys->colorPass = [[MacLCMetalColorPass alloc] initWithDevice:sys->renderer.device];
        id<MTLTexture> linear = [sys->dovi decodePixelBuffer:pixelBuffer
                                                    metadata:rpu
                                               commandBuffer:stageACmdBuf
                                                textureCache:sys->renderer.textureCache];
        if (linear != nil && sys->colorPass != nil) {
            ConfigureColorPass(sys, sys->dovi.sourcePeakNits, display_peak, NULL, false);
            resultingTexture = [sys->colorPass encodeFrom:linear commandBuffer:stageACmdBuf];
        }
        const char *dump = getenv("MACLC_DEBUG_DUMP_DOVI");
        if (dump != NULL && !sys->doviDumped && resultingTexture != nil) {
            const NSUInteger w = linear.width, h = linear.height;
            id<MTLBuffer> linBuf = [sys->renderer.device newBufferWithLength:w * h * 8
                                                                     options:MTLResourceStorageModeShared];
            id<MTLBuffer> mapBuf = [sys->renderer.device newBufferWithLength:w * h * 8
                                                                     options:MTLResourceStorageModeShared];
            id<MTLBlitCommandEncoder> blit = [stageACmdBuf blitCommandEncoder];
            [blit copyFromTexture:linear sourceSlice:0 sourceLevel:0
                     sourceOrigin:MTLOriginMake(0, 0, 0) sourceSize:MTLSizeMake(w, h, 1)
                         toBuffer:linBuf destinationOffset:0
            destinationBytesPerRow:w * 8 destinationBytesPerImage:w * h * 8];
            [blit copyFromTexture:resultingTexture sourceSlice:0 sourceLevel:0
                     sourceOrigin:MTLOriginMake(0, 0, 0) sourceSize:MTLSizeMake(w, h, 1)
                         toBuffer:mapBuf destinationOffset:0
            destinationBytesPerRow:w * 8 destinationBytesPerImage:w * h * 8];
            [blit endEncoding];
            const float content_peak = sys->dovi.sourcePeakNits;
            const enum maclc_hdr_picture picture = sys->maclcPicture;
            const vlc_video_dovi_metadata_t rpuCopy = *rpu; /* the picture's may go first */
            CVPixelBufferRetain(pixelBuffer);
            [stageACmdBuf addCompletedHandler:^(id<MTLCommandBuffer> cb) {
                VLC_UNUSED(cb);
                DumpDolbyVision(vd, dump, pixelBuffer, &rpuCopy, linBuf, mapBuf, w, h,
                                content_peak, display_peak, picture);
                CVPixelBufferRelease(pixelBuffer);
            }];
            sys->doviDumped = true;
        }
        if (resultingTexture != nil) {
            stageAPath = "Dolby Vision";
            rendered = MACLC_HDR_PRESENTATION_DOLBYVISION;
        } else if (!sys->hasLoggedDoviFailure) {
            msg_Warn(vd, "Metal output: could not apply the Dolby Vision RPU "
                         "(pixel format %4.4s); showing the base layer",
                     (const char *)&(OSType){ CFSwapInt32HostToBig(
                         CVPixelBufferGetPixelFormatType(pixelBuffer)) });
            sys->hasLoggedDoviFailure = YES;
        }
    }

    /* Stage A: 2. PQ or HLG source */
    if (resultingTexture == nil && (source_is_pq || source_is_hlg) && sys->toneMapper != nil) {
        const enum maclc_hdr_hlg hlg_mode = sys->maclcHLG;
        const float hlg_peak = maclc_hdr_hlg_peak(hlg_mode, display_peak);
        float content_peak = 0.0f;
        if (source_is_hlg)
            content_peak = hlg_peak;
        else if (use_hdr10plus && HDR10PlusScenePeak(hdr10plus) > 0.0f)
            content_peak = HDR10PlusScenePeak(hdr10plus);
        else if (render_fmt.lighting.MaxCLL > 0)
            content_peak = (float)render_fmt.lighting.MaxCLL;
        else if (render_fmt.mastering.max_luminance > 0)
            content_peak = render_fmt.mastering.max_luminance / 10000.0f;

        /* A curve other than MacLC's own (the OpenGL engine's settings, or
         * HDR10+'s): decode to linear light untouched, then map. HLG keeps
         * MacLC's handling, which renders it for the chosen display. */
        const bool use_curve = source_is_pq && (use_st2094 || sys->toneCurve != 0);
        if (use_curve && sys->colorPass == nil)
            sys->colorPass = [[MacLCMetalColorPass alloc] initWithDevice:sys->renderer.device];

        maclc_tone_params params;
        if (use_curve && sys->colorPass != nil)
            /* identity: nothing above 10000 cd/m2 to compress */
            maclc_tone_params_init(&params, MACLC_TONE_ACCURATE, 10000.0f, 10000.0f,
                                   MACLC_HDR_REFERENCE_WHITE);
        else {
            const enum maclc_hdr_picture picture = source_is_hlg ? MACLC_HDR_PICTURE_AUTO
                                                                 : sys->maclcPicture;
            maclc_tone_params_init(&params, ToneModeFor(picture, content_peak, display_peak),
                                   content_peak, display_peak, MACLC_HDR_REFERENCE_WHITE);
        }

        CVPixelBufferRef mapped = [sys->toneMapper toneMapPixelBuffer:pixelBuffer
                                                             transfer:render_fmt.transfer
                                                              hlgPeak:hlg_peak
                                                               params:&params
                                                       referenceWhite:MACLC_HDR_REFERENCE_WHITE];
        if (mapped != NULL) {
            resultingTexture = [sys->renderer textureFromRGBAHalfBuffer:mapped
                                                          commandBuffer:stageACmdBuf];
            if (resultingTexture != nil && use_curve && sys->colorPass != nil) {
                ConfigureColorPass(sys, content_peak, display_peak,
                                   use_hdr10plus ? hdr10plus : NULL, use_st2094);
                resultingTexture = [sys->colorPass encodeFrom:resultingTexture
                                                commandBuffer:stageACmdBuf];
            }
            if (resultingTexture != nil)
                processed = mapped;
            else
                CVPixelBufferRelease(mapped);
            stageAPath = use_curve ? (use_st2094 ? "HDR10+ curve" : "tone curve") : "tone mapper";
            rendered = source_is_hlg ? MACLC_HDR_PRESENTATION_HLG
                     : use_hdr10plus ? MACLC_HDR_PRESENTATION_HDR10PLUS
                                     : MACLC_HDR_PRESENTATION_HDR10;
        }
    }
    /* Stage A: 3. SDR source with SDR to HDR on */
    else if (resultingTexture == nil && !source_is_hdr && is_edr && sys->sdr2hdrSession != nil) {
        CVPixelBufferRef expanded = [sys->sdr2hdrSession expandIfNeeded:pixelBuffer
                                                                 format:&render_fmt
                                                               headroom:headroom
                                                                   date:date
                                                            sourceIsHDR:NO
                                                                    edr:YES];
        if (expanded != NULL) {
            resultingTexture = [sys->renderer textureFromRGBAHalfBuffer:expanded
                                                          commandBuffer:stageACmdBuf];
            if (resultingTexture != nil)
                processed = expanded;
            else
                CVPixelBufferRelease(expanded);
            stageAPath = "expander";
        }
    }

    /* Stage A: 4. Plain SDR decode kernel fallback */
    if (resultingTexture == nil) {
        resultingTexture = [sys->renderer decodeSourceBuffer:pixelBuffer
                                                      format:&render_fmt
                                               commandBuffer:stageACmdBuf];
        stageAPath = "plain decode";
        rendered = MACLC_HDR_PRESENTATION_SDR;
    }

    [stageACmdBuf commit];
    [stageACmdBuf waitUntilCompleted];

    /* Dolby Vision decodes to BT.2020 whatever the base layer says. */
    sys->renderer.sourceGamutIsWide = use_rpu
        || render_fmt.primaries == COLOR_PRIMARIES_BT2020;
    sys->stageATexture = resultingTexture;
    /* The previous picture's buffer goes back to its pool, where another
     * queue may write it: only once its frame has been drawn. */
    [sys->renderer waitUntilCompleted];
    CVPixelBufferRelease(sys->stageABuffer);
    sys->stageABuffer = processed;

    if (sys->lastLoggedStageAPath != stageAPath) {
        msg_Dbg(vd, "Metal stage A: %s", stageAPath);
        sys->lastLoggedStageAPath = stageAPath;
    }

    /* Publish what reached us and what we render, for the interface. */
    if (hdr_mode == 2 || hdr_mode == 3 || !source_is_hdr)
        rendered = MACLC_HDR_PRESENTATION_SDR;
    if (maclc_hdr_presentation_name(rendered) != sys->publishedActive)
        msg_Dbg(vd, "HDR presentation rendered: %s (requested %s; RPU %s, HDR10+ %s)",
                maclc_hdr_presentation_name(rendered),
                maclc_hdr_presentation_name(presentation),
                rpu != NULL ? "present" : "absent",
                hdr10plus != NULL ? "present" : "absent");
    PublishHdrState(vd, sys,
                    caps | MACLC_HDR_CAP_CAN_DOVI | MACLC_HDR_CAP_CAN_HDR10PLUS
                         | MACLC_HDR_CAP_SERVES_ALL,
                    maclc_hdr_presentation_name(rendered));

    /* Update subpictures */
    CGSize dsize = [sys->view currentDrawableSize];
    [sys->renderer updateSubpicture:subpic outputWidth:(unsigned)dsize.width outputHeight:(unsigned)dsize.height];

    /* Recompute placement */
    struct vout_display_placement cfg_display = vd->cfg->display;
    cfg_display.width = (unsigned)dsize.width;
    cfg_display.height = (unsigned)dsize.height;
    @synchronized (sys->view) {
        vout_display_PlacePicture(&sys->place, vd->source, &cfg_display);
    }

    CVPixelBufferRelease(pixelBuffer);
}

static void DisplayFrame(vout_display_t *vd, picture_t *pic)
{
    VLC_UNUSED(pic);
    vout_display_sys_t *sys = vd->sys;
    if (!sys || sys->stageATexture == nil)
        return;

    CAMetalLayer *layer = (CAMetalLayer *)sys->view.layer;
    if (layer == nil || ![layer isKindOfClass:[CAMetalLayer class]])
        return;

    id<CAMetalDrawable> drawable = [layer nextDrawable];
    if (drawable == nil)
        return;

    CGSize dsize = [sys->view currentDrawableSize];
    if (!CGSizeEqualToSize(sys->lastLoggedDrawableSize, dsize)) {
        msg_Dbg(vd, "Metal drawable size: %.0fx%.0f", dsize.width, dsize.height);
        sys->lastLoggedDrawableSize = dsize;
    }

    vout_display_place_t place;
    @synchronized (sys->view) {
        place = sys->place;
    }

    CGRect placeRect = CGRectMake(place.x, place.y, place.width, place.height);
    if (!CGRectEqualToRect(sys->lastLoggedPlacement, placeRect)) {
        msg_Dbg(vd, "Metal picture placement: %.0f,%.0f %.0fx%.0f",
                placeRect.origin.x, placeRect.origin.y, placeRect.size.width, placeRect.size.height);
        sys->lastLoggedPlacement = placeRect;
    }

    CGPoint cropOrigin = CGPointMake(vd->source->i_x_offset, vd->source->i_y_offset);
    CGSize cropSize = CGSizeMake(vd->source->i_visible_width, vd->source->i_visible_height);

    float headroom = [sys->view effectiveHeadroom];
    const int hdr_mode = EffectiveHdrMode(sys);
    const bool is_edr = (hdr_mode == 0 || hdr_mode == 1) && (headroom > 1.0f);

    video_orientation_t orientation = vd->fmt ? vd->fmt->orientation : ORIENT_NORMAL;

    [sys->renderer renderVideoTexture:sys->stageATexture
                           toDrawable:drawable
                            placement:placeRect
                           cropOrigin:cropOrigin
                             cropSize:cropSize
                          orientation:orientation
                             headroom:headroom
                                isEDR:is_edr];
}

/* The vout thread has no autorelease pool of its own: without this one the
 * drawable nextDrawable hands out (autoreleased) would only go back to the
 * layer's small pool much later, and a frame that fails to render would
 * keep one until then. */
static void Display(vout_display_t *vd, picture_t *pic)
{
    @autoreleasepool {
        DisplayFrame(vd, pic);
    }
}

static void Close(vout_display_t *vd)
{
    vout_display_sys_t *sys = vd->sys;
    if (!sys)
        return;

    vlc_object_t *vout_obj = vlc_object_parent(vd);

    /* 1. Delete callbacks first */
    var_DelCallback(vd, "macosx-edr-headroom", EdrHeadroomCallback, vd);
    var_DelCallback(vd, "macosx-hdr-mode", HdrModeCallback, vd);

    if (vout_obj != NULL) {
        var_DelCallback(vout_obj, "macosx-hdr-mode", HdrModeCallback, vd);
        var_DelCallback(vout_obj, MACLC_HDR_VAR_PRESENTATION, MacLCPresentationCallback, vd);
        var_DelCallback(vout_obj, MACLC_HDR_VAR_PICTURE, MacLCPictureCallback, vd);
        var_DelCallback(vout_obj, MACLC_HDR_VAR_HLG, MacLCHLGCallback, vd);
    }

    /* 2. Wait for in-flight command buffers */
    if (sys->renderer != nil)
        [sys->renderer waitUntilCompleted];

    /* 3. Remove view on main thread */
    if (sys->view != nil) {
        dispatch_sync(dispatch_get_main_queue(), ^{
            [sys->view vlcClose];
        });
        sys->view = nil;
    }

    sys->stageATexture = nil;
    CVPixelBufferRelease(sys->stageABuffer);
    sys->stageABuffer = NULL;
    sys->dovi = nil;
    sys->colorPass = nil;
    sys->toneMapper = nil;

    /* 4. Release renderer resources */
    if (sys->renderer != nil) {
        [sys->renderer releaseResources];
        sys->renderer = nil;
    }

    /* 5. Close SDR2HDR session */
    if (sys->sdr2hdrSession != nil) {
        [sys->sdr2hdrSession close];
        sys->sdr2hdrSession = nil;
    }

    /* 6. Destroy converter */
    DeleteCVPXConverter(sys->converter);
    sys->converter = NULL;

    /* 7. Destroy variables */
    var_Destroy(vd, "edr-headroom-effective");
    var_Destroy(vd, "macosx-edr-headroom");
    var_Destroy(vd, "macosx-hdr-mode");

    if (vout_obj != NULL) {
        var_Destroy(vout_obj, "macosx-hdr-mode");
        var_Destroy(vout_obj, MACLC_HDR_VAR_PRESENTATION);
        var_Destroy(vout_obj, MACLC_HDR_VAR_PICTURE);
        var_Destroy(vout_obj, MACLC_HDR_VAR_HLG);
        var_Destroy(vout_obj, MACLC_HDR_VAR_CAPS);
        var_Destroy(vout_obj, MACLC_HDR_VAR_ACTIVE);
    }

    free(sys);
    vd->sys = NULL;
}

#pragma mark - Open

int MacLCMetalOpen(vout_display_t *vd,
                video_format_t *fmt, vlc_video_context *context)
{
    if (vd->cfg->window->type != VLC_WINDOW_TYPE_NSOBJECT)
        return VLC_EGENERIC;


    /* Unlike the native output, nothing is declined: Dolby Vision (profile
     * 5 included) and HDR10+ are applied here (MacLCMetalDovi,
     * MacLCMetalColorPass). */

    /* Converter if not already CVPX */
    filter_t *converter = NULL;
    if (!vlc_video_context_GetPrivate(context, VLC_VIDEO_CONTEXT_CVPX)) {
        converter = CreateCVPXConverter(vd, fmt);
        if (!converter)
            return VLC_EGENERIC;
    } else {
        /* The renderer decodes NV12, P010 and BGRA buffers. VideoToolbox
         * also hands out 4:2:2 (UYVY for DV, P216) and planar I420: ask for
         * a buffer the renderer reads, the core inserts the CVPX
         * converter. */
        switch (fmt->i_chroma) {
            case VLC_CODEC_CVPX_P216:
                fmt->i_chroma = VLC_CODEC_CVPX_P010;
                break;
            case VLC_CODEC_CVPX_UYVY:
            case VLC_CODEC_CVPX_I420:
                fmt->i_chroma = VLC_CODEC_CVPX_NV12;
                break;
            default:
                break;
        }
    }

    /* Merge vd->source metadata into fmt as caopengllayer.m Open does */
    if (fmt->mastering.max_luminance == 0 && vd->source->mastering.max_luminance != 0)
        fmt->mastering = vd->source->mastering;
    if (fmt->lighting.MaxCLL == 0 && vd->source->lighting.MaxCLL != 0)
        fmt->lighting = vd->source->lighting;
    if (fmt->primaries == COLOR_PRIMARIES_UNDEF && vd->source->primaries != COLOR_PRIMARIES_UNDEF)
        fmt->primaries = vd->source->primaries;
    if (fmt->transfer == TRANSFER_FUNC_UNDEF && vd->source->transfer != TRANSFER_FUNC_UNDEF)
        fmt->transfer = vd->source->transfer;

    vout_display_sys_t *sys = calloc(1, sizeof(*sys));
    if (sys == NULL) {
        DeleteCVPXConverter(converter);
        return VLC_ENOMEM;
    }

    sys->converter = converter;

    id container = (__bridge id)vd->cfg->window->handle.nsobject;
    if (container == nil) {
        free(sys);
        DeleteCVPXConverter(converter);
        return VLC_EGENERIC;
    }

    /* The view publishes the headroom it measures as soon as it is made. */
    var_Create(vd, "edr-headroom-effective", VLC_VAR_FLOAT);
    var_SetFloat(vd, "edr-headroom-effective", 1.0f);

    __block MacLCMetalVideoView *videoView = nil;
    dispatch_sync(dispatch_get_main_queue(), ^{
        videoView = [[MacLCMetalVideoView alloc] initWithContainer:container display:vd];
    });

    if (videoView == nil) {
        var_Destroy(vd, "edr-headroom-effective");
        free(sys);
        DeleteCVPXConverter(converter);
        return VLC_ENOMEM;
    }

    sys->view = videoView;

    CAMetalLayer *metalLayer = (CAMetalLayer *)videoView.layer;
    sys->renderer = [[MacLCMetalRenderer alloc] initWithDevice:metalLayer.device];
    if (sys->renderer == nil) {
        msg_Err(vd, "Metal output: could not create the renderer");
        dispatch_sync(dispatch_get_main_queue(), ^{
            [videoView vlcClose];
        });
        sys->view = nil; /* ARC does not see free() */
        var_Destroy(vd, "edr-headroom-effective");
        free(sys);
        DeleteCVPXConverter(converter);
        return VLC_EGENERIC;
    }

    sys->toneMapper = [MacLCHDRToneMapper toneMapperForObject:VLC_OBJECT(vd)];
    sys->sdr2hdrSession = [MacLCSDR2HDRSession sessionForDisplay:vd];

    /* Variables and options */
    float user_headroom = var_InheritFloat(vd, "macosx-edr-headroom");
    if (user_headroom > 0.0f && user_headroom < 1.0f)
        user_headroom = 1.0f;
    sys->user_headroom = user_headroom;
    videoView.userHeadroom = user_headroom;

    /* The callbacks below can fire from the interface as soon as they are
     * registered, and they all read vd->sys. */
    vd->sys = sys;

    var_Create(vd, "macosx-edr-headroom", VLC_VAR_FLOAT | VLC_VAR_DOINHERIT);
    var_AddCallback(vd, "macosx-edr-headroom", EdrHeadroomCallback, vd);

    int hdr_mode = var_InheritInteger(vd, "macosx-hdr-mode");
    sys->user_hdr_mode = hdr_mode;
    videoView.hdrMode = hdr_mode;

    var_Create(vd, "macosx-hdr-mode", VLC_VAR_INTEGER | VLC_VAR_DOINHERIT);
    var_AddCallback(vd, "macosx-hdr-mode", HdrModeCallback, vd);

    vlc_object_t *vout_obj = vlc_object_parent(vd);
    if (vout_obj != NULL) {
        var_Create(vout_obj, "macosx-hdr-mode", VLC_VAR_INTEGER | VLC_VAR_DOINHERIT);
        var_AddCallback(vout_obj, "macosx-hdr-mode", HdrModeCallback, vd);
    }

    char *pres = var_InheritString(vd, MACLC_HDR_VAR_PRESENTATION);
    sys->maclcPresentation = maclc_hdr_presentation_parse(pres);
    free(pres);

    videoView.hdrMode = EffectiveHdrMode(sys);
    /* The view measured the screen when it was made; apply the user's
     * headroom and the mode now rather than at the next screen change. */
    [videoView updateDynamicRangeProperties];

    char *pic = var_InheritString(vd, MACLC_HDR_VAR_PICTURE);
    sys->maclcPicture = maclc_hdr_picture_parse(pic);
    free(pic);

    char *hlg = var_InheritString(vd, MACLC_HDR_VAR_HLG);
    sys->maclcHLG = maclc_hdr_hlg_parse(hlg);
    free(hlg);

    sys->seenCaps = 0;
    sys->publishedCaps = -1;
    sys->publishedActive = NULL;

    if (vout_obj != NULL) {
        var_Create(vout_obj, MACLC_HDR_VAR_PRESENTATION, VLC_VAR_STRING | VLC_VAR_DOINHERIT);
        var_AddCallback(vout_obj, MACLC_HDR_VAR_PRESENTATION, MacLCPresentationCallback, vd);

        var_Create(vout_obj, MACLC_HDR_VAR_PICTURE, VLC_VAR_STRING | VLC_VAR_DOINHERIT);
        var_AddCallback(vout_obj, MACLC_HDR_VAR_PICTURE, MacLCPictureCallback, vd);

        var_Create(vout_obj, MACLC_HDR_VAR_HLG, VLC_VAR_STRING | VLC_VAR_DOINHERIT);
        var_AddCallback(vout_obj, MACLC_HDR_VAR_HLG, MacLCHLGCallback, vd);

        var_Create(vout_obj, MACLC_HDR_VAR_CAPS, VLC_VAR_INTEGER);
        var_Create(vout_obj, MACLC_HDR_VAR_ACTIVE, VLC_VAR_STRING);
    }

    /* Say what this output can do before the first picture: the interface
     * knows at once that no track restart is needed for any presentation. */
    PublishHdrState(vd, sys, MACLC_HDR_CAP_CAN_DOVI | MACLC_HDR_CAP_CAN_HDR10PLUS
                             | MACLC_HDR_CAP_SERVES_ALL, NULL);

    SetUpOptionalStages(vd);
    sys->doviProfile5 = fmt->dovi.profile == 5;
    sys->toneCurve = var_InheritInteger(vd, "gl-tone-mapping-function");
    if (sys->toneCurve < 0 || sys->toneCurve > MACLC_TC_SPLINE)
        sys->toneCurve = 0;
    sys->toneParam = var_InheritFloat(vd, "gl-tone-mapping-param");
    sys->renderer.gamutMapping = (int)var_InheritInteger(vd, "gl-gamut-mapping");
    if (sys->toneCurve != 0 || sys->renderer.gamutMapping != 0)
        msg_Dbg(vd, "Metal output: tone curve %d (param %.2f), gamut mapping %d",
                sys->toneCurve, sys->toneParam, sys->renderer.gamutMapping);
    if (vd->source->i_sar_num > 0 && vd->source->i_sar_den > 0)
        sys->renderer.sampleAspectRatio = (float)vd->source->i_sar_num / vd->source->i_sar_den;
    SetUpProjection(vd, fmt->projection_mode, &vd->cfg->viewpoint);

    static const struct vlc_display_operations ops = {
        .close = Close,
        .prepare = Prepare,
        .display = Display,
        .video_place_changed = PlacementChanged,
        .set_source_aspect = AspectChanged,
        .set_source_crop = AspectChanged,
        .set_viewpoint = SetViewpoint,
        .change_source_projection = ChangeSourceProjection,
    };
    vd->ops = &ops;

    static const vlc_fourcc_t subfmts[] = {
        VLC_CODEC_RGBA,
        0
    };
    vd->info.subpicture_chromas = subfmts;

    return VLC_SUCCESS;
}
