/*****************************************************************************
 * VLCSampleBufferDisplay.m: video output display using
 * AVSampleBufferDisplayLayer on all Apple platforms
 *****************************************************************************
 * Copyright (C) 2023-2026 VLC authors and VideoLAN
 *
 * Authors: Maxime Chapelet <umxprime at videolabs dot io>
 *
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

#include <vlc_common.h>
#include <vlc_filter.h>
#include <vlc_plugin.h>
#include <vlc_vout_display.h>
#include <vlc_atomic.h>
#include <vlc_modules.h>

#import "VLCDrawable.h"

#import <AVFoundation/AVFoundation.h>
#import <AVKit/AVKit.h>
#import <QuartzCore/QuartzCore.h>

#include "../../codec/vt_utils.h"
#include "vlc_pip_controller.h"

#import <VideoToolbox/VideoToolbox.h>

/*
 * ITU-R Report BT.2408 specifies 203 cd/m^2 (nits) as the reference level for
 * diffuse white in HDR production (e.g. PQ/HLG subtitles and graphics).
 * Standard SDR nominal peak white is 100 cd/m^2.
 * When EDR headroom H > 1.0, the display allows highlights up to H * SDR white.
 * To keep subtitle white comfortable and aligned with SDR reference white rather
 * than glaring at peak display brightness, we adapt subtitle layer opacity/luminance
 * by scaling with (ITU_BT2408_REFERENCE_WHITE_NITS / (SDR_NOMINAL_WHITE_NITS * headroom)).
 */
#define ITU_BT2408_REFERENCE_WHITE_NITS 203.0f
#define SDR_NOMINAL_WHITE_NITS          100.0f

#if __is_target_os(ios)
#define IS_VT_ROTATION_API_AVAILABLE __IPHONE_OS_VERSION_MAX_ALLOWED >= 160000
#elif __is_target_os(macos)
#define IS_VT_ROTATION_API_AVAILABLE __MAC_OS_X_VERSION_MAX_ALLOWED >= 130000
#elif __is_target_os(tvos)
#define IS_VT_ROTATION_API_AVAILABLE __TV_OS_VERSION_MAX_ALLOWED >= 160000
#elif __is_target_os(visionos)
#define IS_VT_ROTATION_API_AVAILABLE __VISION_OS_VERSION_MAX_ALLOWED >= 10000
#endif

typedef NS_ENUM(NSUInteger, VLCSampleBufferPixelRotation) {
    kVLCSampleBufferPixelRotation_0 = 0,
    kVLCSampleBufferPixelRotation_90CW,
    kVLCSampleBufferPixelRotation_180,
    kVLCSampleBufferPixelRotation_90CCW,
};

typedef NS_ENUM(NSUInteger, VLCSampleBufferPixelFlip) {
    kVLCSampleBufferPixelFlip_None = 0,
    kVLCSampleBufferPixelFlip_H = 1 << 0,
    kVLCSampleBufferPixelFlip_V = 1 << 1,
};

#pragma mark - VLCRotatedPixelBufferProvider

@interface VLCRotatedPixelBufferProvider : NSObject
- (CVPixelBufferRef)provideFromBuffer:(CVPixelBufferRef)pixelBuffer
                             rotation:(VLCSampleBufferPixelRotation)rotation;
@end

@implementation VLCRotatedPixelBufferProvider
{
    CVPixelBufferPoolRef _rotationPool;
}

- (BOOL)_validateRotationPoolWithBuffer:(CVPixelBufferRef)pixelBuffer
                               rotation:(VLCSampleBufferPixelRotation)rotation
{
    if (!_rotationPool)
        return NO;

    uint32_t poolWidth, poolHeigth, bufferWidth, bufferHeight;

    bufferWidth = (uint32_t)CVPixelBufferGetWidth(pixelBuffer);
    bufferHeight = (uint32_t)CVPixelBufferGetHeight(pixelBuffer);
    if (rotation == kVLCSampleBufferPixelRotation_90CW || rotation == kVLCSampleBufferPixelRotation_90CCW)
    {
        uint32_t swap = bufferWidth;
        bufferWidth = bufferHeight;
        bufferHeight = swap;
    }

    CFDictionaryRef poolAttr = CVPixelBufferPoolGetPixelBufferAttributes(_rotationPool);
    if (!poolAttr) {
        return NO;
    }
    CFTypeRef value;
    value = CFDictionaryGetValue(poolAttr, kCVPixelBufferWidthKey);
    if (!value || CFGetTypeID(value) != CFNumberGetTypeID()
        || !CFNumberGetValue(value, kCFNumberIntType, &poolWidth)
        || poolWidth != bufferWidth)
    {
        return NO;
    }

    value = CFDictionaryGetValue(poolAttr, kCVPixelBufferHeightKey);
    if (!value || CFGetTypeID(value) != CFNumberGetTypeID()
        || !CFNumberGetValue(value, kCFNumberIntType, &poolHeigth)
        || poolHeigth != bufferHeight)
    {
        return NO;
    }

    return YES;
}

- (CVPixelBufferRef)provideFromBuffer:(CVPixelBufferRef)pixelBuffer
                             rotation:(VLCSampleBufferPixelRotation)rotation
{
    if (![self _validateRotationPoolWithBuffer:pixelBuffer rotation:rotation])
        CVPixelBufferPoolRelease(_rotationPool);

    if (!_rotationPool) {
        bool rotated = rotation == kVLCSampleBufferPixelRotation_90CW || rotation == kVLCSampleBufferPixelRotation_90CCW;
        uint32_t srcWidth = CVPixelBufferGetWidth(pixelBuffer);
        uint32_t srcHeight = CVPixelBufferGetHeight(pixelBuffer);
        uint32_t dstWidth = rotated ? srcHeight : srcWidth;
        uint32_t dstHeight = rotated ? srcWidth : srcHeight;

        CFTypeRef keys[] = {
            kCVPixelBufferPixelFormatTypeKey,
            kCVPixelBufferWidthKey,
            kCVPixelBufferHeightKey,
            kCVPixelBufferIOSurfacePropertiesKey,
            kCVPixelBufferMetalCompatibilityKey,
#if TARGET_OS_OSX
            kCVPixelBufferOpenGLCompatibilityKey,
#elif !defined(TARGET_OS_VISION) || !TARGET_OS_VISION
            kCVPixelBufferOpenGLESCompatibilityKey,
#endif
        };

        CFTypeRef values[] = {
            (__bridge CFNumberRef)(@(CVPixelBufferGetPixelFormatType(pixelBuffer))),
            (__bridge CFNumberRef)(@(dstWidth)),
            (__bridge CFNumberRef)(@(dstHeight)),
            (__bridge CFDictionaryRef)@{},
            kCFBooleanTrue,
#if !defined(TARGET_OS_VISION) || !TARGET_OS_VISION
            kCFBooleanTrue
#endif
        };
        _Static_assert(ARRAY_SIZE(keys) == ARRAY_SIZE(values),
            "Mismatch between keys and values array sizes");

        CFDictionaryRef poolAttr = CFDictionaryCreate(NULL, keys, values, ARRAY_SIZE(keys), &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);

        OSStatus status = CVPixelBufferPoolCreate(NULL, NULL, poolAttr, &_rotationPool);
        CFRelease(poolAttr);
        if (status != noErr)
            return NULL;
    }

    CVPixelBufferRef rotated;
    OSStatus status = CVPixelBufferPoolCreatePixelBuffer(NULL, _rotationPool, &rotated);
    if (status != noErr) {
        return NULL;
    }
    CFDictionaryRef attachments;
    if (@available(iOS 15.0, tvOS 15.0, macOS 12.0, *)) {
        attachments = CVBufferCopyAttachments(pixelBuffer, kCVAttachmentMode_ShouldPropagate);
    } else {
        attachments = CVBufferGetAttachments(pixelBuffer, kCVAttachmentMode_ShouldPropagate);
    }
    CVBufferSetAttachments(rotated, attachments, kCVAttachmentMode_ShouldPropagate);
    if (@available(iOS 15.0, tvOS 15.0, macOS 12.0, *)) {
        CFRelease(attachments);
    }
    return rotated;
}

- (void)dealloc
{
    CVPixelBufferPoolRelease(_rotationPool);
}
@end

#pragma mark - VLCPixelBufferRotationContext

@protocol VLCPixelBufferRotationContext
@property(nonatomic) VLCSampleBufferPixelRotation rotation;
@property(nonatomic) VLCSampleBufferPixelFlip flip;
- (CVPixelBufferRef)rotate:(CVPixelBufferRef)pixelBuffer;
@end

#pragma mark - VLCPixelBufferRotationContextVT

#if IS_VT_ROTATION_API_AVAILABLE
API_AVAILABLE(ios(16.0), tvos(16.0), macosx(13.0))
@interface VLCPixelBufferRotationContextVT : NSObject <VLCPixelBufferRotationContext>

@end

@implementation VLCPixelBufferRotationContextVT
{
    VLCRotatedPixelBufferProvider *_bufferProvider;
    VTPixelRotationSessionRef _rotationSession;
}

@synthesize rotation = _rotation, flip = _flip;

- (instancetype)init
{
    self = [super init];
    if (self) {
        if (@available(iOS 16.0, tvOS 16.0, macOS 13.0, *)) {
            OSStatus status = VTPixelRotationSessionCreate(NULL, &_rotationSession);
            if (status != noErr)
                return nil;
        } else {
            return nil;
        }
    }
    return self;
}

- (void)setRotation:(VLCSampleBufferPixelRotation)rotation {
    if (_rotation == rotation)
        return;
    _rotation = rotation;
    switch (rotation) {
        case kVLCSampleBufferPixelRotation_90CW:
            VTSessionSetProperty(_rotationSession, kVTPixelRotationPropertyKey_Rotation, kVTRotation_CW90);
            break;
        case kVLCSampleBufferPixelRotation_180:
            VTSessionSetProperty(_rotationSession, kVTPixelRotationPropertyKey_Rotation, kVTRotation_180);
            break;
        case kVLCSampleBufferPixelRotation_90CCW:
            VTSessionSetProperty(_rotationSession, kVTPixelRotationPropertyKey_Rotation, kVTRotation_CCW90);
            break;
        case kVLCSampleBufferPixelRotation_0:
        default:
            VTSessionSetProperty(_rotationSession, kVTPixelRotationPropertyKey_Rotation, kVTRotation_0);
            break;
    }
}

- (void)setFlip:(VLCSampleBufferPixelFlip)flip {
    if (_flip == flip)
        return;
    _flip = flip;
    VTSessionSetProperty(_rotationSession, kVTPixelRotationPropertyKey_FlipHorizontalOrientation, flip & kVLCSampleBufferPixelFlip_H ? kCFBooleanTrue : kCFBooleanFalse);
    VTSessionSetProperty(_rotationSession, kVTPixelRotationPropertyKey_FlipVerticalOrientation, flip & kVLCSampleBufferPixelFlip_V ? kCFBooleanTrue : kCFBooleanFalse);
}

- (CVPixelBufferRef)rotate:(CVPixelBufferRef)pixelBuffer {
    if (!_bufferProvider)
        _bufferProvider = [VLCRotatedPixelBufferProvider new];

    CVPixelBufferRef rotated;
    rotated = [_bufferProvider provideFromBuffer:pixelBuffer rotation:_rotation];
    if (!rotated)
        return NULL;

    OSStatus status = VTPixelRotationSessionRotateImage(_rotationSession, pixelBuffer, rotated);
    if (status != noErr) {
        CFRelease(rotated);
        return NULL;
    }

    return rotated;
}

- (void)dealloc
{
    if (_rotationSession) {
        VTPixelRotationSessionInvalidate(_rotationSession);
        CFRelease(_rotationSession);
    }
}

@end

#endif // IS_VT_ROTATION_API_AVAILABLE

#pragma mark - VLCPixelBufferRotationContextCI

@interface VLCPixelBufferRotationContextCI : NSObject <VLCPixelBufferRotationContext>

@end

@implementation VLCPixelBufferRotationContextCI
{
    VLCRotatedPixelBufferProvider *_bufferProvider;
    CIContext *_rotationContext;
    CGImagePropertyOrientation _orientation;
}

@synthesize rotation = _rotation, flip = _flip;

- (instancetype)init
{
    self = [super init];
    if (self) {
        _rotationContext = [[CIContext alloc] initWithOptions:nil];
        if (!_rotationContext)
            return nil;
    }
    return self;
}

- (void)_updateOrientation {
    switch (_rotation) {
        case kVLCSampleBufferPixelRotation_90CW:
        {
            if (_flip == kVLCSampleBufferPixelFlip_None)
                _orientation = kCGImagePropertyOrientationRight;
            if (_flip == kVLCSampleBufferPixelFlip_H)
                _orientation = kCGImagePropertyOrientationLeftMirrored;
            if (_flip == kVLCSampleBufferPixelFlip_V)
                _orientation = kCGImagePropertyOrientationRightMirrored;
            if (_flip == (kVLCSampleBufferPixelFlip_H | kVLCSampleBufferPixelFlip_V))
                _orientation = kCGImagePropertyOrientationLeft;
            break;
        }
        case kVLCSampleBufferPixelRotation_180:
        {
            if (_flip == kVLCSampleBufferPixelFlip_None)
                _orientation = kCGImagePropertyOrientationDown;
            if (_flip == kVLCSampleBufferPixelFlip_H)
                _orientation = kCGImagePropertyOrientationDownMirrored;
            if (_flip == kVLCSampleBufferPixelFlip_V)
                _orientation = kCGImagePropertyOrientationUpMirrored;
            if (_flip == (kVLCSampleBufferPixelFlip_H | kVLCSampleBufferPixelFlip_V))
                _orientation = kCGImagePropertyOrientationUp;
            break;
        }
        case kVLCSampleBufferPixelRotation_90CCW:
        {
            if (_flip == kVLCSampleBufferPixelFlip_None)
                _orientation = kCGImagePropertyOrientationLeft;
            if (_flip == kVLCSampleBufferPixelFlip_H)
                _orientation = kCGImagePropertyOrientationRightMirrored;
            if (_flip == kVLCSampleBufferPixelFlip_V)
                _orientation = kCGImagePropertyOrientationLeftMirrored;
            if (_flip == (kVLCSampleBufferPixelFlip_H | kVLCSampleBufferPixelFlip_V))
                _orientation = kCGImagePropertyOrientationRight;
            break;
        }
        case kVLCSampleBufferPixelRotation_0:
        default:
        {
            if (_flip == kVLCSampleBufferPixelFlip_None)
                _orientation = kCGImagePropertyOrientationUp;
            if (_flip == kVLCSampleBufferPixelFlip_H)
                _orientation = kCGImagePropertyOrientationUpMirrored;
            if (_flip == kVLCSampleBufferPixelFlip_V)
                _orientation = kCGImagePropertyOrientationDownMirrored;
            if (_flip == (kVLCSampleBufferPixelFlip_H | kVLCSampleBufferPixelFlip_V))
                _orientation = kCGImagePropertyOrientationDown;
            break;
        }
    }
}

- (void)setRotation:(VLCSampleBufferPixelRotation)rotation {
    if (_rotation == rotation)
        return;
    _rotation = rotation;
    [self _updateOrientation];
}

- (void)setFlip:(VLCSampleBufferPixelFlip)flip {
    if (_flip == flip)
        return;
    _flip = flip;
    [self _updateOrientation];
}

- (CVPixelBufferRef)rotate:(CVPixelBufferRef)pixelBuffer {
    if (!_bufferProvider)
        _bufferProvider = [VLCRotatedPixelBufferProvider new];

    CVPixelBufferRef rotated;
    rotated = [_bufferProvider provideFromBuffer:pixelBuffer rotation:_rotation];
    if (!rotated)
        return NULL;

    CIImage *image = [[CIImage alloc] initWithCVPixelBuffer:pixelBuffer];
    image = [image imageByApplyingOrientation:_orientation];
    [_rotationContext render:image toCVPixelBuffer:rotated];

    return rotated;
}

@end

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

    bool is_10bit_hdr = (fmt->i_chroma == VLC_CODEC_I420_10L ||
                         fmt->i_chroma == VLC_CODEC_I420_10B ||
                         fmt->i_chroma == VLC_CODEC_P010 ||
                         fmt->i_chroma == VLC_CODEC_CVPX_P010 ||
                         fmt->transfer == TRANSFER_FUNC_SMPTE_ST2084 ||
                         fmt->transfer == TRANSFER_FUNC_HLG ||
                         fmt->primaries == COLOR_PRIMARIES_BT2020);

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
    else if (fmt->i_chroma == VLC_CODEC_UYVY)
    {
        converter->fmt_out.video.i_chroma =
        converter->fmt_out.i_codec = VLC_CODEC_CVPX_UYVY;
    }
    else
    {
        converter->fmt_out.video.i_chroma =
        converter->fmt_out.i_codec = VLC_CODEC_CVPX_BGRA;
    }

    converter->p_module = vlc_filter_LoadModule(converter, "video converter", NULL, false);
    if (!converter->p_module)
    {
        vlc_object_delete(converter);
        return NULL;
    }
    assert( converter->ops != NULL );

    return converter;
}


static void DeleteCVPXConverter( filter_t * p_converter )
{
    if (!p_converter)
        return;

    vlc_filter_UnloadModule( p_converter );

    es_format_Clean( &p_converter->fmt_in );
    es_format_Clean( &p_converter->fmt_out );

    vlc_object_delete(p_converter);
}

static pip_controller_t * CreatePipController( vout_display_t *vd, void *cbs_opaque );
static void DeletePipController( pip_controller_t * pipcontroller );

#pragma mark - Class Interfaces

@class VLCSampleBufferSubpictureRegion;
@class VLCSampleBufferSubpicture;
@class VLCSampleBufferSubpictureView;
@class VLCSampleBufferDisplayView;
@class VLCSampleBufferDisplay;

@interface VLCSampleBufferSubpictureRegion: NSObject
@property (nonatomic, weak) VLCSampleBufferSubpicture *subpicture;
@property (nonatomic) CGRect backingFrame;
@property (nonatomic) CGImageRef image;
@property (nonatomic) CGFloat    alpha;
@end

@interface VLCSampleBufferSubpicture: NSObject
@property (nonatomic, weak) VLCSampleBufferDisplay *sys;
@property (nonatomic) NSArray<VLCSampleBufferSubpictureRegion *> *regions;
@property (nonatomic) int64_t order;
@end

@interface VLCSampleBufferSubpictureView: VLCView
- (void)drawSubpicture:(VLCSampleBufferSubpicture *)subpicture;
@end

@interface VLCSampleBufferDisplayView: VLCView <CALayerDelegate>
@property (nonatomic, weak) VLCSampleBufferDisplay *sys;
- (AVSampleBufferDisplayLayer *)displayLayer;
@end

@interface VLCSampleBufferDisplay: NSObject
{
    @public
    filter_t *converter;
}
    @property (nonatomic, readonly, weak) VLCView *window;
    @property (nonatomic, readonly) vout_display_t *vd;
    @property (nonatomic) VLCSampleBufferDisplayView *displayView;
    @property (nonatomic) AVSampleBufferDisplayLayer *displayLayer;
    @property (nonatomic) VLCSampleBufferSubpictureView *spuView;
    @property (nonatomic) VLCSampleBufferSubpicture *subpicture;
    @property (nonatomic) id<VLCPixelBufferRotationContext> rotationContext;
    @property (nonatomic) float userHeadroom;
    @property (nonatomic) CGFloat currentHeadroom;
    @property (nonatomic) bool warnedToneMapFallback;

    @property (nonatomic, readonly) pip_controller_t *pipcontroller;

    - (instancetype)init NS_UNAVAILABLE;
    + (instancetype)new NS_UNAVAILABLE;
    - (instancetype)initWithVoutDisplay:(vout_display_t *)vd;
    - (void)placeVideo:(vout_display_place_t)newPlace;
    - (void)updateDynamicRangeAndHeadroom;
@end

#pragma mark - Class Implementations

@implementation VLCSampleBufferSubpictureRegion
- (void)dealloc {
    CGImageRelease(_image);
}
@end

@implementation VLCSampleBufferSubpicture

@end

@implementation VLCSampleBufferSubpictureView
{
    VLCSampleBufferSubpicture *_pendingSubpicture;
}

- (instancetype)init {
    self = [super init];
    if (!self)
        return nil;
#if TARGET_OS_OSX
    self.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.wantsLayer = YES;
#if __MAC_OS_X_VERSION_MAX_ALLOWED >= 101500
    if (@available(macOS 10.15, *)) {
        self.layer.wantsExtendedDynamicRangeContent = NO;
    }
#endif
#if __MAC_OS_X_VERSION_MAX_ALLOWED >= 140000
    if (@available(macOS 14.0, *)) {
        self.layer.contentsHeadroom = 1.0;
    }
#endif
#else
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.backgroundColor = [UIColor clearColor];
#endif
    return self;
}

- (void)drawSubpicture:(VLCSampleBufferSubpicture *)subpicture {
    _pendingSubpicture = subpicture;
#if TARGET_OS_OSX
    [self setNeedsDisplay:YES];
#else
    [self setNeedsDisplay];
#endif
}

- (void)drawRect:(CGRect)dirtyRect {
    #if TARGET_OS_OSX
    NSGraphicsContext *graphicsCtx = [NSGraphicsContext currentContext];
    CGContextRef cgCtx = [graphicsCtx CGContext];
    #else
    CGContextRef cgCtx = UIGraphicsGetCurrentContext();
    #endif

    CGContextClearRect(cgCtx, self.bounds);

#if TARGET_OS_IPHONE
    CGContextSaveGState(cgCtx);
    CGAffineTransform translate = CGAffineTransformTranslate(CGAffineTransformIdentity, 0.0, self.frame.size.height);
    CGFloat scale = 1.0f / self.contentScaleFactor;
    CGAffineTransform transform = CGAffineTransformScale(translate, scale, -scale);
    CGContextConcatCTM(cgCtx, transform);
#endif
    VLCSampleBufferSubpictureRegion *region;
    for (region in _pendingSubpicture.regions) {
#if TARGET_OS_OSX
        CGRect regionFrame = [self convertRectFromBacking:region.backingFrame];
#else
        CGRect regionFrame = region.backingFrame;
#endif
        CGContextSetAlpha(cgCtx, region.alpha);
        CGContextDrawImage(cgCtx, regionFrame, region.image);
    }
#if TARGET_OS_IPHONE
    CGContextRestoreGState(cgCtx);
#endif
}

@end

@implementation VLCSampleBufferDisplayView

- (instancetype)init {
    self = [super init];
    if (!self)
        return nil;
#if TARGET_OS_OSX
    self.autoresizingMask = NSViewNotSizable;
    self.wantsLayer = YES;
#else
    self.autoresizingMask = UIViewAutoresizingNone;
#endif
    return self;
}

#if TARGET_OS_OSX
- (CALayer *)makeBackingLayer {
    AVSampleBufferDisplayLayer *layer;
    layer = [AVSampleBufferDisplayLayer new];
    layer.delegate = self;
    layer.videoGravity = AVLayerVideoGravityResizeAspect;
    [CATransaction lock];
    layer.needsDisplayOnBoundsChange = YES;
    layer.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
    layer.opaque = 1.0;
    layer.hidden = NO;
#if __MAC_OS_X_VERSION_MAX_ALLOWED >= 101500
    if (@available(macOS 10.15, *)) {
        layer.wantsExtendedDynamicRangeContent = YES;
    }
#endif
#if __MAC_OS_X_VERSION_MAX_ALLOWED >= 140000
    if (@available(macOS 14.0, *)) {
        layer.preferredDynamicRange = CADynamicRangeHigh;
        NSScreen *screen = self.window.screen ?: [NSScreen mainScreen];
        CGFloat headroom = 1.0;
        if (screen && screen.maximumExtendedDynamicRangeColorComponentValue > 1.0) {
            headroom = screen.maximumExtendedDynamicRangeColorComponentValue;
        } else if (screen && screen.maximumPotentialExtendedDynamicRangeColorComponentValue > 1.0) {
            headroom = screen.maximumPotentialExtendedDynamicRangeColorComponentValue;
        }
        if (headroom > 1.0) {
            layer.contentsHeadroom = headroom;
        }
    }
#endif
#if __MAC_OS_X_VERSION_MAX_ALLOWED >= 150000
    if (@available(macOS 15.0, *)) {
        layer.toneMapMode = CAToneMapModeIfSupported;
    }
#endif
    [CATransaction unlock];
    return layer;
}
#else
+ (Class)layerClass {
    return [AVSampleBufferDisplayLayer class];
}
#endif

- (AVSampleBufferDisplayLayer *)displayLayer {
    return (AVSampleBufferDisplayLayer *)self.layer;
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    if (self.window && _sys) {
        [_sys updateDynamicRangeAndHeadroom];
    }
}

#if TARGET_OS_OSX
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
#endif

/*
 * General properties
 */

- (BOOL)isOpaque
{
    return YES;
}

- (BOOL)acceptsFirstResponder
{
    return YES;
}

@end

@implementation VLCSampleBufferDisplay

- (id<VLCPixelBufferRotationContext>)rotationContext
{
    if (_rotationContext)
        return _rotationContext;
#if IS_VT_ROTATION_API_AVAILABLE
    if (@available(iOS 16.0, tvOS 16.0, macOS 13.0, *))
        _rotationContext = [VLCPixelBufferRotationContextVT new];
#endif
    if (!_rotationContext)
        _rotationContext = [VLCPixelBufferRotationContextCI new];
    return _rotationContext;
}


- (instancetype)initWithVoutDisplay:(vout_display_t *)vd
{
    self = [super init];
    if (!self)
        return nil;

    if (vd->cfg->window->type != VLC_WINDOW_TYPE_NSOBJECT)
        return nil;

    VLCView *window = (__bridge VLCView *)vd->cfg->window->handle.nsobject;
    if (!window) {
        msg_Err(vd, "No window found!");
        return nil;
    }

    _window = window;

    _pipcontroller = CreatePipController(vd, (__bridge void *)self);

    _vd = vd;
    _currentHeadroom = 1.0;
    _warnedToneMapFallback = false;

    return self;
}

- (void)preparePictureInPicture {
    if ( !_pipcontroller)
        return;

    if ( _pipcontroller->ops->set_display_layer ) {
        _pipcontroller->ops->set_display_layer(
            _pipcontroller,
            (__bridge void*)_displayView.displayLayer
        );
    }
}

- (CGRect)frameForPlace:(const vout_display_place_t *)place
{
    VLCView *window = self.window;
    CGRect frame = CGRectMake(place->x, place->y, place->width, place->height);
#if TARGET_OS_OSX
    frame = [window convertRectFromBacking:frame];
    frame.origin.y = window.bounds.size.height - frame.origin.y - frame.size.height;
#else
    CGFloat scale = window.contentScaleFactor;
    frame.origin.x /= scale;
    frame.origin.y /= scale;
    frame.size.width /= scale;
    frame.size.height /= scale;
#endif
    return frame;
}

- (void)prepareDisplay {
    @synchronized(_displayLayer) {
        if (_displayLayer)
            return;
    }

    VLCSampleBufferDisplay *sys = self;
    vout_display_place_t place = *_vd->place;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (sys.displayView)
            return;

        VLCSampleBufferDisplayView *displayView;
        VLCSampleBufferSubpictureView *spuView;
        VLCView *window = sys.window;

        displayView = [[VLCSampleBufferDisplayView alloc] init];
        displayView.sys = sys;
        spuView = [VLCSampleBufferSubpictureView new];
        [window addSubview:displayView];
        [window addSubview:spuView];

        displayView.frame = [sys frameForPlace:&place];
        [spuView setFrame:[window bounds]];

        sys.displayView = displayView;
        sys.spuView = spuView;
        @synchronized(sys.displayLayer) {
            sys.displayLayer = displayView.displayLayer;
        }

        [sys updateDynamicRangeAndHeadroom];
        [sys observeDisplayLayerFailures];
        [sys setupScreenObservers];
        [sys preparePictureInPicture];
    });
}

- (void)setupScreenObservers {
#if TARGET_OS_OSX
    NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];

    [notificationCenter addObserver:self
                           selector:@selector(screenParametersDidChange:)
                               name:NSApplicationDidChangeScreenParametersNotification
                             object:nil];

    [notificationCenter addObserver:self
                           selector:@selector(windowDidChangeScreen:)
                               name:NSWindowDidChangeScreenNotification
                             object:nil];

    [notificationCenter addObserver:self
                           selector:@selector(windowDidChangeScreenProfile:)
                               name:NSWindowDidChangeScreenProfileNotification
                             object:nil];
#endif
}

#if TARGET_OS_OSX
- (void)screenParametersDidChange:(NSNotification *)notification {
    [self updateDynamicRangeAndHeadroom];
}

- (void)windowDidChangeScreen:(NSNotification *)notification {
    [self updateDynamicRangeAndHeadroom];
}

- (void)windowDidChangeScreenProfile:(NSNotification *)notification {
    [self updateDynamicRangeAndHeadroom];
}
#endif

- (void)updateDynamicRangeAndHeadroom {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self updateDynamicRangeAndHeadroom];
        });
        return;
    }

    if (!_displayView)
        return;

#if TARGET_OS_OSX
    vout_display_t *vd = _vd;
    int hdr_mode = var_InheritInteger(vd, "macosx-hdr-mode");

    NSWindow *nswindow = self.window.window ?: self.displayView.window;
    NSScreen *screen = nswindow.screen ?: [NSScreen mainScreen];

    CGFloat screenHeadroom = 1.0;
#if __MAC_OS_X_VERSION_MAX_ALLOWED >= 101500
    if (@available(macOS 10.15, *)) {
        if (screen) {
            screenHeadroom = screen.maximumExtendedDynamicRangeColorComponentValue;
            if (screenHeadroom <= 1.0 && screen.maximumPotentialExtendedDynamicRangeColorComponentValue > 1.0) {
                screenHeadroom = screen.maximumPotentialExtendedDynamicRangeColorComponentValue;
            }
        }
    }
#endif

    CGFloat effectiveHeadroom;
    if (_userHeadroom > 0.0f) {
        effectiveHeadroom = (CGFloat)_userHeadroom;
    } else {
        effectiveHeadroom = (screenHeadroom > 1.0) ? screenHeadroom : 1.0;
    }
    _currentHeadroom = effectiveHeadroom;

    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    if (hdr_mode == 2 || hdr_mode == 3) {
        /* Mode 2 (Tone-map to SDR) or Mode 3 (Disable HDR): configure layer for SDR presentation */
#if __MAC_OS_X_VERSION_MAX_ALLOWED >= 101500
        if (@available(macOS 10.15, *)) {
            self.window.layer.wantsExtendedDynamicRangeContent = NO;
            self.displayView.layer.wantsExtendedDynamicRangeContent = NO;
            if (nswindow) {
                nswindow.contentView.layer.wantsExtendedDynamicRangeContent = NO;
            }
        }
#endif
#if __MAC_OS_X_VERSION_MAX_ALLOWED >= 140000
        if (@available(macOS 14.0, *)) {
            self.displayView.layer.preferredDynamicRange = CADynamicRangeStandard;
            self.displayView.layer.contentsHeadroom = 1.0;
        }
#endif
#if __MAC_OS_X_VERSION_MAX_ALLOWED >= 150000
        if (@available(macOS 15.0, *)) {
            self.displayView.layer.toneMapMode = CAToneMapModeAutomatic;
        }
#endif
    } else {
        /* Mode 0 (Auto) or Mode 1 (Force HDR): enable EDR display pipeline */
#if __MAC_OS_X_VERSION_MAX_ALLOWED >= 101500
        if (@available(macOS 10.15, *)) {
            self.window.wantsLayer = YES;
            self.window.layer.wantsExtendedDynamicRangeContent = YES;
            self.displayView.wantsLayer = YES;
            self.displayView.layer.wantsExtendedDynamicRangeContent = YES;
            if (nswindow) {
                nswindow.colorSpace = [NSColorSpace extendedSRGBColorSpace];
                nswindow.contentView.wantsLayer = YES;
                nswindow.contentView.layer.wantsExtendedDynamicRangeContent = YES;
            }
        }
#endif
#if __MAC_OS_X_VERSION_MAX_ALLOWED >= 140000
        if (@available(macOS 14.0, *)) {
            self.displayView.layer.preferredDynamicRange = CADynamicRangeHigh;
            if (effectiveHeadroom > 1.0) {
                self.displayView.layer.contentsHeadroom = effectiveHeadroom;
            } else {
                self.displayView.layer.contentsHeadroom = 1.0;
            }
        }
#endif
#if __MAC_OS_X_VERSION_MAX_ALLOWED >= 150000
        if (@available(macOS 15.0, *)) {
            self.displayView.layer.toneMapMode = CAToneMapModeIfSupported;
        }
#endif
    }

    /* Subtitle layer tagging and luminance adaptation (Defect 4) */
    if (self.spuView) {
#if __MAC_OS_X_VERSION_MAX_ALLOWED >= 101500
        if (@available(macOS 10.15, *)) {
            self.spuView.layer.wantsExtendedDynamicRangeContent = NO;
        }
#endif
#if __MAC_OS_X_VERSION_MAX_ALLOWED >= 140000
        if (@available(macOS 14.0, *)) {
            self.spuView.layer.contentsHeadroom = 1.0;
        }
#endif
        CGFloat factor = 1.0;
        if (hdr_mode != 2 && hdr_mode != 3 && effectiveHeadroom > 1.0) {
            factor = (CGFloat)(ITU_BT2408_REFERENCE_WHITE_NITS / (SDR_NOMINAL_WHITE_NITS * effectiveHeadroom));
            if (factor > 1.0)
                factor = 1.0;
            else if (factor < 0.15)
                factor = 0.15;
        }
        self.spuView.layer.opacity = (float)factor;
    }

    [CATransaction commit];
#endif
}

- (void)observeDisplayLayerFailures {
    NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];

#if !TARGET_OS_OSX
    [notificationCenter addObserver:self
                           selector:@selector(applicationDidBecomeActive:)
                               name:UIApplicationDidBecomeActiveNotification
                             object:nil];
#endif

    if (@available(iOS 14.0, tvOS 14.0, macOS 11.0, *)) {
        [notificationCenter addObserver:self
                               selector:@selector(displayLayerRequiresFlushDidChange:)
                                   name:AVSampleBufferDisplayLayerRequiresFlushToResumeDecodingDidChangeNotification
                                 object:self.displayLayer];
    }
}

- (void)applicationDidBecomeActive:(NSNotification *)notification {
    [self flushToResumeDecoding];
}

- (void)displayLayerRequiresFlushDidChange:(NSNotification *)notification {
    [self flushToResumeDecoding];
}

- (void)flushToResumeDecoding {
    AVSampleBufferDisplayLayer * const displayLayer = self.displayLayer;
    @synchronized(displayLayer) {
        if (displayLayer.status != AVQueuedSampleBufferRenderingStatusFailed)
            return;

        /* only a failure caused by revoked decoder resources is recoverable */
        if (@available(iOS 14.0, tvOS 14.0, macOS 11.0, *)) {
            if (!displayLayer.requiresFlushToResumeDecoding) {
                msg_Err(_vd, "display layer failed permanently: %s",
                        displayLayer.error.localizedDescription.UTF8String);
                return;
            }
        }

        [displayLayer flush];
    }
}

- (void)placeVideo:(vout_display_place_t)newPlace {
    self.displayView.frame = [self frameForPlace:&newPlace];
}

- (void)close {
    [[NSNotificationCenter defaultCenter] removeObserver:self];

    VLCSampleBufferDisplay *sys = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [sys.displayView removeFromSuperview];
        [sys.spuView removeFromSuperview];
    });
    DeletePipController(_pipcontroller);
    _pipcontroller = NULL;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end

#pragma mark -
#pragma mark Module functions

static int EdrHeadroomCallback(vlc_object_t *obj, char const *name,
                               vlc_value_t prev, vlc_value_t cur, void *data)
{
    VLC_UNUSED(obj); VLC_UNUSED(name); VLC_UNUSED(prev);
    VLCSampleBufferDisplay *sys = (__bridge VLCSampleBufferDisplay *)data;
    float val = cur.f_float;
    if (val > 0.0f && val < 1.0f)
        val = 1.0f;
    sys.userHeadroom = val;
    msg_Dbg(sys.vd, "EDR headroom updated via variable callback: %.2f%s",
            val, (val > 0.0f) ? " (user override)" : " (auto screen peak)");
    [sys updateDynamicRangeAndHeadroom];
    return VLC_SUCCESS;
}

static int HdrModeCallback(vlc_object_t *obj, char const *name,
                           vlc_value_t prev, vlc_value_t cur, void *data)
{
    VLC_UNUSED(obj); VLC_UNUSED(name); VLC_UNUSED(prev); VLC_UNUSED(cur);
    VLCSampleBufferDisplay *sys = (__bridge VLCSampleBufferDisplay *)data;
    [sys updateDynamicRangeAndHeadroom];
    return VLC_SUCCESS;
}

static void Close(vout_display_t *vd)
{
    VLCSampleBufferDisplay *sys;
    sys = (__bridge_transfer VLCSampleBufferDisplay*)vd->sys;

    var_DelCallback(vd, "macosx-edr-headroom", EdrHeadroomCallback, (__bridge void*)sys);
    var_DelCallback(vd, "macosx-hdr-mode", HdrModeCallback, (__bridge void*)sys);

    DeleteCVPXConverter(sys->converter);

    [sys close];
}

static void RenderPicture(vout_display_t *vd, picture_t *pic, vlc_tick_t date) {
    VLCSampleBufferDisplay *sys;
    sys = (__bridge VLCSampleBufferDisplay*)vd->sys;

    switch (vd->fmt->orientation) {
    case ORIENT_HFLIPPED:
        sys.rotationContext.flip = kVLCSampleBufferPixelFlip_H;
        sys.rotationContext.rotation = kVLCSampleBufferPixelRotation_0;
        break;
    case ORIENT_VFLIPPED:
        sys.rotationContext.flip = kVLCSampleBufferPixelFlip_V;
        sys.rotationContext.rotation = kVLCSampleBufferPixelRotation_0;
        break;
    case ORIENT_ROTATED_90:
        sys.rotationContext.flip = kVLCSampleBufferPixelFlip_None;
        sys.rotationContext.rotation = kVLCSampleBufferPixelRotation_90CW;
        break;
    case ORIENT_ROTATED_180:
        sys.rotationContext.flip = kVLCSampleBufferPixelFlip_None;
        sys.rotationContext.rotation = kVLCSampleBufferPixelRotation_180;
        break;
    case ORIENT_ROTATED_270:
        sys.rotationContext.flip = kVLCSampleBufferPixelFlip_None;
        sys.rotationContext.rotation = kVLCSampleBufferPixelRotation_90CCW;
        break;
    case ORIENT_TRANSPOSED:
        sys.rotationContext.flip = kVLCSampleBufferPixelFlip_V;
        sys.rotationContext.rotation = kVLCSampleBufferPixelRotation_90CW;
        break;
    case ORIENT_ANTI_TRANSPOSED:
        sys.rotationContext.flip = kVLCSampleBufferPixelFlip_H;
        sys.rotationContext.rotation = kVLCSampleBufferPixelRotation_90CW;
    case ORIENT_NORMAL:
    default:
        sys.rotationContext = nil;
        break;
    }

    @synchronized(sys.displayLayer) {
        if (sys.displayLayer == nil)
            return;
        if (sys.displayLayer.status == AVQueuedSampleBufferRenderingStatusFailed)
            return;
    }

    picture_Hold(pic);

    picture_t *dst = pic;
    if (sys->converter) {
        dst = sys->converter->ops->filter_video(sys->converter, pic);
    }

    CVPixelBufferRef pixelBuffer = cvpxpic_get_ref(dst);
    CVPixelBufferRetain(pixelBuffer);
    picture_Release(dst);

    if (pixelBuffer == NULL) {
        msg_Err(vd, "No pixelBuffer ref attached to pic!");
        return;
    }

    if (vd->fmt->orientation != ORIENT_NORMAL) {
        CVPixelBufferRef rotated = [sys.rotationContext rotate:pixelBuffer];
        if (rotated) {
            CVPixelBufferRelease(pixelBuffer);
            pixelBuffer = rotated;
        }
    }

    /* Merge video format properties from vd->fmt if pic->format is incomplete */
    video_format_t render_fmt = pic->format;
    if (render_fmt.transfer == TRANSFER_FUNC_UNDEF && vd->fmt->transfer != TRANSFER_FUNC_UNDEF)
        render_fmt.transfer = vd->fmt->transfer;
    if (render_fmt.primaries == COLOR_PRIMARIES_UNDEF && vd->fmt->primaries != COLOR_PRIMARIES_UNDEF)
        render_fmt.primaries = vd->fmt->primaries;
    if (render_fmt.space == COLOR_SPACE_UNDEF && vd->fmt->space != COLOR_SPACE_UNDEF)
        render_fmt.space = vd->fmt->space;
    if (render_fmt.mastering.max_luminance == 0 && vd->fmt->mastering.max_luminance != 0)
        render_fmt.mastering = vd->fmt->mastering;
    if (render_fmt.lighting.MaxCLL == 0 && vd->fmt->lighting.MaxCLL != 0)
        render_fmt.lighting = vd->fmt->lighting;

    int hdr_mode = var_InheritInteger(vd, "macosx-hdr-mode");
    switch (hdr_mode) {
    case 1: /* Force Native EDR / HDR */
        if (render_fmt.transfer != TRANSFER_FUNC_HLG)
            render_fmt.transfer = TRANSFER_FUNC_SMPTE_ST2084;
        render_fmt.primaries = COLOR_PRIMARIES_BT2020;
        render_fmt.space = COLOR_SPACE_BT2020;
        break;
    case 2: /* Tone-map to SDR */
#if TARGET_OS_OSX && (__MAC_OS_X_VERSION_MAX_ALLOWED >= 140000)
        if (@available(macOS 14.0, *)) {
            /* On macOS 14+, the compositor handles tone-mapping to SDR via
             * CADynamicRangeStandard and CAToneMapModeAutomatic on the layer.
             * Keep the true PQ/HLG/BT.2020 tagging on the CVPixelBuffer so the
             * compositor has the true dynamic range metadata to compress. */
            break;
        }
#endif
        /* On older macOS where layer dynamic range controls are not available,
         * fall back to retagging as BT.709 so the user gets an SDR presentation. */
        if (!sys.warnedToneMapFallback) {
            msg_Warn(vd, "Hardware tone mapping to SDR is unsupported on this OS version (< macOS 14); falling back to BT.709 retagging");
            sys.warnedToneMapFallback = true;
        }
        render_fmt.transfer = TRANSFER_FUNC_BT709;
        render_fmt.primaries = COLOR_PRIMARIES_BT709;
        render_fmt.space = COLOR_SPACE_BT709;
        break;
    case 3: /* Disable HDR */
        render_fmt.transfer = TRANSFER_FUNC_BT709;
        render_fmt.primaries = COLOR_PRIMARIES_BT709;
        render_fmt.space = COLOR_SPACE_BT709;
        break;
    case 0: /* Auto */
    default:
        /* Auto mode preserves original color space and metadata for native display EDR/tonemapping */
        break;
    }

    /* Ensure color properties and HDR metadata are attached for CoreMedia / ColorSync / EDR pipeline */
    cvpx_attach_mapped_color_properties(pixelBuffer, &render_fmt);
    cvpx_attach_hdr_metadata(pixelBuffer, &render_fmt);

    id aspectRatio = @{
        (__bridge NSString*)kCVImageBufferPixelAspectRatioHorizontalSpacingKey:
            @(vd->source->i_sar_num),
        (__bridge NSString*)kCVImageBufferPixelAspectRatioVerticalSpacingKey:
            @(vd->source->i_sar_den)
    };

    CVBufferSetAttachment(
        pixelBuffer,
        kCVImageBufferPixelAspectRatioKey,
        (__bridge CFDictionaryRef)aspectRatio,
        kCVAttachmentMode_ShouldPropagate
    );

    CMSampleBufferRef sampleBuffer = NULL;
    CMVideoFormatDescriptionRef formatDesc = NULL;
    OSStatus err = CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, pixelBuffer, &formatDesc);
    if (err != noErr) {
        msg_Err(vd, "Image buffer format desciption creation failed!");
        CVPixelBufferRelease(pixelBuffer);
        return;
    }

    vlc_tick_t now = vlc_tick_now();
    CFTimeInterval ca_now = CACurrentMediaTime();
    vlc_tick_t ca_now_ts = vlc_tick_from_sec(ca_now);
    vlc_tick_t diff = date - now;
    CFTimeInterval ca_date = secf_from_vlc_tick(ca_now_ts + diff);
    CMSampleTimingInfo sampleTimingInfo = {
        .decodeTimeStamp = kCMTimeInvalid,
        .duration = kCMTimeInvalid,
        .presentationTimeStamp = CMTimeMakeWithSeconds(ca_date, 1000000)
    };

    err = CMSampleBufferCreateReadyWithImageBuffer(kCFAllocatorDefault, pixelBuffer, formatDesc, &sampleTimingInfo, &sampleBuffer);
    CFRelease(formatDesc);
    CVPixelBufferRelease(pixelBuffer);
    if (err != noErr) {
        msg_Err(vd, "Image buffer creation failed!");
        return;
    }

    @synchronized(sys.displayLayer) {
        [sys.displayLayer enqueueSampleBuffer:sampleBuffer];
    }

    CFRelease(sampleBuffer);
}

static CGRect RegionBackingFrame(unsigned display_height,
                                 const struct subpicture_region_rendered *r)
{
    // Invert y coords for CoreGraphics
    const int y = display_height - r->place.height - r->place.y;

    return CGRectMake(
        r->place.x,
        y,
        r->place.width,
        r->place.height
    );
}

static void UpdateSubpictureRegions(vout_display_t *vd,
                                    const vlc_render_subpicture *subpicture)
{
    VLCSampleBufferDisplay *sys;
    sys = (__bridge VLCSampleBufferDisplay*)vd->sys;

    if (sys.subpicture == nil || subpicture == NULL)
        return;

    NSMutableArray *regions = [NSMutableArray new];
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    if (!space) {
        space = CGColorSpaceCreateDeviceRGB();
    }
    const struct subpicture_region_rendered *r;
    vlc_vector_foreach(r, &subpicture->regions) {
        CFIndex length = r->p_picture->format.i_height * r->p_picture->p->i_pitch;
        const size_t pixels_offset =
                r->p_picture->format.i_y_offset * r->p_picture->p->i_pitch +
                r->p_picture->format.i_x_offset * r->p_picture->p->i_pixel_pitch;

        CFDataRef data = CFDataCreate(
            NULL,
            r->p_picture->p->p_pixels + pixels_offset,
            length - pixels_offset);
        CGDataProviderRef provider = CGDataProviderCreateWithCFData(data);
        CGImageRef image = CGImageCreate(
            r->p_picture->format.i_visible_width, r->p_picture->format.i_visible_height,
            8, 32, r->p_picture->p->i_pitch,
            space, kCGBitmapByteOrderDefault | kCGImageAlphaFirst,
            provider, NULL, true, kCGRenderingIntentDefault
            );
        VLCSampleBufferSubpictureRegion *region;
        region = [VLCSampleBufferSubpictureRegion new];
        region.subpicture = sys.subpicture;
        region.image = image;
        region.alpha = r->i_alpha / 255.f;

        region.backingFrame = RegionBackingFrame(vd->cfg->display.height, r);
        [regions addObject:region];
        CGDataProviderRelease(provider);
        CFRelease(data);
    }
    if (space) {
        CGColorSpaceRelease(space);
    }

    sys.subpicture.regions = regions;
}

static bool IsSubpictureDrawNeeded(vout_display_t *vd, const vlc_render_subpicture *subpicture)
{
    VLCSampleBufferDisplay *sys;
    sys = (__bridge VLCSampleBufferDisplay*)vd->sys;

    if (subpicture == NULL)
    {
        if (sys.subpicture == nil)
            return false;
        sys.subpicture = nil;
        /* Need to draw one last time in order to clear the current subpicture */
        return true;
    }

    size_t count = subpicture->regions.size;
    const struct subpicture_region_rendered *r;

    if (!sys.subpicture || subpicture->i_order != sys.subpicture.order)
    {
        /* Subpicture content is different */
        sys.subpicture = [VLCSampleBufferSubpicture new];
        sys.subpicture.sys = sys;
        sys.subpicture.order = subpicture->i_order;
        UpdateSubpictureRegions(vd, subpicture);
        return true;
    }

    bool draw = false;

    if (count == sys.subpicture.regions.count)
    {
        size_t i = 0;
        vlc_vector_foreach(r, &subpicture->regions)
        {
            VLCSampleBufferSubpictureRegion *region =
                sys.subpicture.regions[i++];

            CGRect newRegion = RegionBackingFrame(vd->cfg->display.height, r);

            if ( !CGRectEqualToRect(region.backingFrame, newRegion) )
            {
                /* Subpicture regions are different */
                draw = true;
                break;
            }
        }
    }
    else
    {
        /* Subpicture region count is different */
        draw = true;
    }

    if (!draw)
        return false;

    /* Store the current subpicture regions in order to compare then later.
     */

    UpdateSubpictureRegions(vd, subpicture);
    return true;
}

static void RenderSubpicture(vout_display_t *vd, const vlc_render_subpicture *spu)
{
    if (!IsSubpictureDrawNeeded(vd, spu))
        return;

    VLCSampleBufferDisplay *sys;
    sys = (__bridge VLCSampleBufferDisplay*)vd->sys;

    dispatch_async(dispatch_get_main_queue(), ^{
        [sys.spuView drawSubpicture:sys.subpicture];
    });
}

static void PrepareDisplay (vout_display_t *vd) {
    VLCSampleBufferDisplay *sys;
    sys = (__bridge VLCSampleBufferDisplay*)vd->sys;

    [sys prepareDisplay];
}

static void Prepare (vout_display_t *vd, picture_t *pic,
                     const vlc_render_subpicture *subpicture, vlc_tick_t date)
{
    PrepareDisplay(vd);
    if (pic) {
        RenderPicture(vd, pic, date);
    }

    RenderSubpicture(vd, subpicture);
}

static void Display(vout_display_t *vd, picture_t *pic)
{
    // kept as the core is not properly pacing the calls to Prepare without this callback
}

static int PlacementChanged(vout_display_t *vd, const vout_display_place_t *place)
{
    VLCSampleBufferDisplay *sys;
    sys = (__bridge VLCSampleBufferDisplay*)vd->sys;

    vout_display_place_t newPlace = *place;
    dispatch_async(dispatch_get_main_queue(), ^{
        [sys placeVideo:newPlace];
    });

    return VLC_SUCCESS;
}

static pip_controller_t * CreatePipController( vout_display_t *vd, void *cbs_opaque )
{
    pip_controller_t *pip_controller = vlc_object_create(vd, sizeof(pip_controller_t));

    module_t **mods;
    ssize_t total = vlc_module_match("pictureinpicture", NULL, false, &mods, NULL);
    for (ssize_t i = 0; i < total; ++i)
    {
        int (*open)(pip_controller_t *) = vlc_module_map(vd->obj.logger, mods[i]);

        if (open && open(pip_controller) == VLC_SUCCESS)
        {
            free(mods);
            return pip_controller;
        }
    }

    free(mods);
    vlc_object_delete(pip_controller);
    return NULL;
}

static void DeletePipController( pip_controller_t * pip_controller )
{
    if (pip_controller == NULL)
        return;

    if( pip_controller->ops->close )
    {
        pip_controller->ops->close(pip_controller);
    }

    vlc_object_delete(pip_controller);
}

static int UpdateFormat(vout_display_t *vd, const video_format_t *fmt,
                        vlc_video_context *vctx)
{
    VLCSampleBufferDisplay *sys = (__bridge VLCSampleBufferDisplay*)vd->sys;

    // Display will only work with CVPX video context
    filter_t *converter = NULL;
    if (!vlc_video_context_GetPrivate(vctx, VLC_VIDEO_CONTEXT_CVPX)) {
        converter = CreateCVPXConverter(vd, fmt);
        if (!converter)
            return VLC_EGENERIC;
    }

    DeleteCVPXConverter(sys->converter);
    sys->converter = converter;
    return VLC_SUCCESS;
}

static int Open (vout_display_t *vd,
                 video_format_t *fmt, vlc_video_context *context)
{
    if (var_InheritBool(vd, "force-darwin-legacy-display")) {
        return VLC_EGENERIC;
    }
    // Display isn't compatible with 360 content hence opening with this kind
    // of projection should fail if display use isn't forced
    if (!vd->obj.force && fmt->projection_mode != PROJECTION_MODE_RECTANGULAR) {
        return VLC_EGENERIC;
    }

    // Display will only work with CVPX video context
    filter_t *converter = NULL;
    if (!vlc_video_context_GetPrivate(context, VLC_VIDEO_CONTEXT_CVPX)) {
        converter = CreateCVPXConverter(vd, fmt);
        if (!converter)
            return VLC_EGENERIC;
    }

    @autoreleasepool {
        VLCSampleBufferDisplay *sys =
            [[VLCSampleBufferDisplay alloc] initWithVoutDisplay:vd];

        if (sys == nil) {
            DeleteCVPXConverter(converter);
            return VLC_ENOMEM;
        }

        sys->converter = converter;

        float user_headroom = var_InheritFloat(vd, "macosx-edr-headroom");
        if (user_headroom > 0.0f && user_headroom < 1.0f)
            user_headroom = 1.0f;
        sys.userHeadroom = user_headroom;

        if (user_headroom > 0.0f) {
            msg_Dbg(vd, "EDR headroom initialized to user override: %.2f", user_headroom);
        } else {
            msg_Dbg(vd, "EDR headroom initialized to auto (display peak)");
        }

        var_Create(vd, "macosx-edr-headroom", VLC_VAR_FLOAT | VLC_VAR_DOINHERIT);
        var_AddCallback(vd, "macosx-edr-headroom", EdrHeadroomCallback, (__bridge void*)sys);

        var_Create(vd, "macosx-hdr-mode", VLC_VAR_INTEGER | VLC_VAR_DOINHERIT);
        var_AddCallback(vd, "macosx-hdr-mode", HdrModeCallback, (__bridge void*)sys);

        vd->sys = (__bridge_retained void*)sys;

        static const struct vlc_display_operations ops = {
            .close = Close,
            .prepare = Prepare,
            .display = Display,
            .update_format = UpdateFormat,
            .video_place_changed = PlacementChanged,
        };

        vd->ops = &ops;

        static const vlc_fourcc_t subfmts[] = {
            VLC_CODEC_ARGB,
            0
        };

        vd->info.subpicture_chromas = subfmts;

        return VLC_SUCCESS;
    }
}

/*
 * Module descriptor
 */

#define FORCE_LEGACY_DISPLAY_TEXT N_("Force fallback to legacy display")
#define FORCE_LEGACY_DISPLAY_LONGTEXT N_( \
    "Triggers an initialization failure to allow fallback to any other legacy display.")

#define HDR_MODE_TEXT N_("HDR Video Output Mode")
#define HDR_MODE_LONGTEXT N_( \
    "Controls how HDR video content is presented on macOS displays. " \
    "Auto: Uses native EDR on HDR/XDR displays and hardware tonemapping on SDR displays. " \
    "Force Native HDR: Always uses native EDR output. " \
    "Tone-map to SDR: Performs high quality tone mapping to SDR color space. " \
    "Disable HDR: Clamps and renders in standard SDR.")

#define EDR_HEADROOM_TEXT N_("EDR Headroom Scaling")
#define EDR_HEADROOM_LONGTEXT N_( \
    "Controls the extended dynamic range brightness scaling factor (0.0 for auto screen headroom, >= 1.0 to force specific headroom).")

static const int hdr_mode_values[] = { 0, 1, 2, 3 };
static const char *const hdr_mode_names[] = {
    N_("Auto (Native EDR on HDR screens, Tonemap on SDR)"),
    N_("Force Native EDR / HDR"),
    N_("Tone-map to SDR"),
    N_("Disable HDR"),
};

#define HELP_TEXT N_("This display handles hardware decoded pixel buffers "\
                     "and renders them in a view/layer. "\
                     "It can also convert and display software decoded frame buffers. "\
                     "This is the default display for Apple platforms. "\
                     "--force-darwin-legacy-display option can be used to abort the "\
                     "display's initialization and allows fallback to legacy displays like "\
                     "other OpenGL/ES based video outputs.")

vlc_module_begin()
    set_description(N_("CoreMedia sample buffers based video output display"))
    set_subcategory(SUBCAT_VIDEO_VOUT)
    add_bool("force-darwin-legacy-display", false,
             FORCE_LEGACY_DISPLAY_TEXT, FORCE_LEGACY_DISPLAY_LONGTEXT)
        change_volatile()
    add_integer("macosx-hdr-mode", 0, HDR_MODE_TEXT, HDR_MODE_LONGTEXT)
        change_integer_list(hdr_mode_values, hdr_mode_names)
    add_float("macosx-edr-headroom", 0.0f, EDR_HEADROOM_TEXT, EDR_HEADROOM_LONGTEXT)
    set_help(HELP_TEXT)
    set_callback_display(Open, 600)
vlc_module_end()
