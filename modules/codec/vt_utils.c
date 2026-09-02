/*****************************************************************************
 * vt_utils.c: videotoolbox/cvpx utility functions
 *****************************************************************************
 * Copyright (C) 2017 VLC authors, VideoLAN and VideoLabs
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

#include <vlc_atomic.h>

#include "vt_utils.h"
#include "../packetizer/iso_color_tables.h"

CFMutableDictionaryRef
cfdict_create(CFIndex capacity)
{
    return CFDictionaryCreateMutable(kCFAllocatorDefault, capacity,
                                     &kCFTypeDictionaryKeyCallBacks,
                                     &kCFTypeDictionaryValueCallBacks);
}

void
cfdict_set_int32(CFMutableDictionaryRef dict, CFStringRef key, int value)
{
    CFNumberRef number = CFNumberCreate(NULL, kCFNumberSInt32Type, &value);
    CFDictionarySetValue(dict, key, number);
    CFRelease(number);
}

struct cvpxpic_ctx
{
    picture_context_t s;
    CVPixelBufferRef cvpx;
    unsigned nb_fields;

    vlc_atomic_rc_t rc;
    void (*on_released_cb)(vlc_video_context *vctx, unsigned);
};

static void
cvpxpic_destroy_cb(picture_context_t *opaque)
{
    struct cvpxpic_ctx *ctx = (struct cvpxpic_ctx *)opaque;

    if (vlc_atomic_rc_dec(&ctx->rc))
    {
        CFRelease(ctx->cvpx);
        if (ctx->on_released_cb)
            ctx->on_released_cb(opaque->vctx, ctx->nb_fields);
        free(opaque);
    }
}

static picture_context_t *
cvpxpic_copy_cb(struct picture_context_t *opaque)
{
    struct cvpxpic_ctx *ctx = (struct cvpxpic_ctx *)opaque;
    vlc_atomic_rc_inc(&ctx->rc);
    vlc_video_context_Hold(opaque->vctx);
    return opaque;
}

static int
cvpxpic_attach_common(picture_t *p_pic, CVPixelBufferRef cvpx,
                      void (*pf_destroy)(picture_context_t *),
                      vlc_video_context *vctx,
                      void (*on_released_cb)(vlc_video_context *vctx, unsigned))
{
    struct cvpxpic_ctx *ctx = malloc(sizeof(struct cvpxpic_ctx));
    if (ctx == NULL)
    {
        picture_Release(p_pic);
        return VLC_ENOMEM;
    }
    ctx->s = (picture_context_t) {
        pf_destroy, cvpxpic_copy_cb, vctx,
    };
    ctx->cvpx = CVPixelBufferRetain(cvpx);
    ctx->nb_fields = p_pic->i_nb_fields;
    vlc_atomic_rc_init(&ctx->rc);

    assert(vctx);
    vlc_video_context_Hold(vctx);
    ctx->on_released_cb = on_released_cb;

    p_pic->context = &ctx->s;

    return VLC_SUCCESS;
}

int
cvpxpic_attach(picture_t *p_pic, CVPixelBufferRef cvpx, vlc_video_context *vctx,
               void (*on_released_cb)(vlc_video_context *vctx, unsigned))
{
    return cvpxpic_attach_common(p_pic, cvpx, cvpxpic_destroy_cb, vctx, on_released_cb);
}

CVPixelBufferRef
cvpxpic_get_ref(picture_t *pic)
{
    assert(pic->context != NULL);
    return ((struct cvpxpic_ctx *)pic->context)->cvpx;
}

static void
cvpxpic_destroy_mapped_ro_cb(picture_context_t *opaque)
{
    struct cvpxpic_ctx *ctx = (struct cvpxpic_ctx *)opaque;

    CVPixelBufferUnlockBaseAddress(ctx->cvpx, kCVPixelBufferLock_ReadOnly);
    cvpxpic_destroy_cb(opaque);
}

static void
cvpxpic_destroy_mapped_rw_cb(picture_context_t *opaque)
{
    struct cvpxpic_ctx *ctx = (struct cvpxpic_ctx *)opaque;

    CVPixelBufferUnlockBaseAddress(ctx->cvpx, 0);
    cvpxpic_destroy_cb(opaque);
}

picture_t *
cvpxpic_create_mapped(const video_format_t *fmt, CVPixelBufferRef cvpx,
                      vlc_video_context *vctx, bool readonly)

{
    unsigned planes_count;
    switch (fmt->i_chroma)
    {
        case VLC_CODEC_BGRA:
        case VLC_CODEC_UYVY: planes_count = 0; break;
        case VLC_CODEC_NV12:
        case VLC_CODEC_P010: planes_count = 2; break;
        case VLC_CODEC_I420: planes_count = 3; break;
        default: return NULL;
    }

    CVPixelBufferLockFlags lock = readonly ? kCVPixelBufferLock_ReadOnly : 0;
    CVPixelBufferLockBaseAddress(cvpx, lock);
    picture_resource_t rsc = { };

#ifndef NDEBUG
    assert(CVPixelBufferGetPlaneCount(cvpx) == planes_count);
#endif

    void (*pf_destroy)(picture_context_t *) = readonly ?
        cvpxpic_destroy_mapped_ro_cb : cvpxpic_destroy_mapped_rw_cb;

    picture_t *pic = picture_NewFromResource(fmt, &rsc);
    if (pic == NULL
     || cvpxpic_attach_common(pic, cvpx, pf_destroy, vctx, NULL) != VLC_SUCCESS)
    {
        CVPixelBufferUnlockBaseAddress(cvpx, lock);
        return NULL;
    }

    if (planes_count == 0)
    {
        pic->p[0].p_pixels = CVPixelBufferGetBaseAddress(cvpx);
        pic->p[0].i_lines = CVPixelBufferGetHeight(cvpx);
        pic->p[0].i_pitch = CVPixelBufferGetBytesPerRow(cvpx);
    }
    else
    {
        for (unsigned i = 0; i < planes_count; ++i)
        {
            pic->p[i].p_pixels = CVPixelBufferGetBaseAddressOfPlane(cvpx, i);
            pic->p[i].i_lines = CVPixelBufferGetHeightOfPlane(cvpx, i);
            pic->p[i].i_pitch = CVPixelBufferGetBytesPerRowOfPlane(cvpx, i);
        }
    }

    return pic;
}

picture_t *
cvpxpic_unmap(picture_t *mapped_pic)
{
    video_format_t fmt = mapped_pic->format;
    switch (fmt.i_chroma)
    {
        case VLC_CODEC_UYVY: fmt.i_chroma = VLC_CODEC_CVPX_UYVY; break;
        case VLC_CODEC_NV12: fmt.i_chroma = VLC_CODEC_CVPX_NV12; break;
        case VLC_CODEC_P010: fmt.i_chroma = VLC_CODEC_CVPX_P010; break;
        case VLC_CODEC_I420: fmt.i_chroma = VLC_CODEC_CVPX_I420; break;
        case VLC_CODEC_BGRA: fmt.i_chroma = VLC_CODEC_CVPX_BGRA; break;
        default:
            assert(!"invalid mapped_pic fmt");
            picture_Release(mapped_pic);
            return NULL;
    }
    assert(mapped_pic->context != NULL);

    picture_t *hw_pic = picture_NewFromFormat(&fmt);
    if (hw_pic == NULL)
    {
        picture_Release(mapped_pic);
        return NULL;
    }

    cvpxpic_attach(hw_pic, cvpxpic_get_ref(mapped_pic), NULL, NULL);
    picture_CopyProperties(hw_pic, mapped_pic);
    picture_Release(mapped_pic);
    return hw_pic;
}

CVPixelBufferPoolRef
cvpxpool_create(const video_format_t *fmt, unsigned count)
{
    int cvpx_format;
    switch (fmt->i_chroma)
    {
        case VLC_CODEC_CVPX_UYVY:
            cvpx_format = kCVPixelFormatType_422YpCbCr8;
            break;
        case VLC_CODEC_CVPX_NV12:
            cvpx_format = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange;
            break;
        case VLC_CODEC_CVPX_I420:
            cvpx_format = kCVPixelFormatType_420YpCbCr8Planar;
            break;
        case VLC_CODEC_CVPX_BGRA:
            cvpx_format = kCVPixelFormatType_32BGRA;
            break;
        case VLC_CODEC_CVPX_P010:
            cvpx_format = 'x420'; /* kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange */
            break;
        default:
            return NULL;
    }

    /* destination pixel buffer attributes */
    CFMutableDictionaryRef cvpx_attrs_dict = cfdict_create(5);
    if (unlikely(cvpx_attrs_dict == NULL))
        return NULL;
    CFMutableDictionaryRef pool_dict = cfdict_create(2);
    if (unlikely(pool_dict == NULL))
    {
        CFRelease(cvpx_attrs_dict);
        return NULL;
    }

    CFMutableDictionaryRef io_dict = cfdict_create(0);
    if (unlikely(io_dict == NULL))
    {
        CFRelease(cvpx_attrs_dict);
        CFRelease(pool_dict);
        return NULL;
    }
    CFDictionarySetValue(cvpx_attrs_dict,
                         kCVPixelBufferIOSurfacePropertiesKey, io_dict);
    CFRelease(io_dict);

    cfdict_set_int32(cvpx_attrs_dict, kCVPixelBufferPixelFormatTypeKey,
                     cvpx_format);
    cfdict_set_int32(cvpx_attrs_dict, kCVPixelBufferWidthKey, fmt->i_visible_width);
    cfdict_set_int32(cvpx_attrs_dict, kCVPixelBufferHeightKey, fmt->i_visible_height);
    /* Required by CIFilter to render IOSurface */
    cfdict_set_int32(cvpx_attrs_dict, kCVPixelBufferBytesPerRowAlignmentKey, 16);

    cfdict_set_int32(pool_dict, kCVPixelBufferPoolMinimumBufferCountKey, count);
    cfdict_set_int32(pool_dict, kCVPixelBufferPoolMaximumBufferAgeKey, 0);

    CVPixelBufferPoolRef pool;
    CVReturn err =
        CVPixelBufferPoolCreate(NULL, pool_dict, cvpx_attrs_dict, &pool);
    CFRelease(pool_dict);
    CFRelease(cvpx_attrs_dict);
    if (err != kCVReturnSuccess)
        return NULL;

    CVPixelBufferRef cvpxs[count];
    for (unsigned i = 0; i < count; ++i)
    {
        err = CVPixelBufferPoolCreatePixelBuffer(NULL, pool, &cvpxs[i]);
        if (err != kCVReturnSuccess)
        {
            CVPixelBufferPoolRelease(pool);
            pool = NULL;
            count = i;
            break;
        }
    }
    for (unsigned i = 0; i < count; ++i)
        CFRelease(cvpxs[i]);

    return pool;
}

CVPixelBufferRef
cvpxpool_new_cvpx(CVPixelBufferPoolRef pool)
{
    CVPixelBufferRef cvpx;
    CVReturn err = CVPixelBufferPoolCreatePixelBuffer(NULL, pool, &cvpx);

    if (err != kCVReturnSuccess)
        return NULL;

    return cvpx;
}

CFStringRef
cvpx_map_YCbCrMatrix_from_vcs(video_color_space_t color_space)
{
    switch (color_space) {
    case COLOR_SPACE_BT601:
        return kCVImageBufferYCbCrMatrix_ITU_R_601_4;
    case COLOR_SPACE_BT2020:
        if (__builtin_available(macOS 10.11, iOS 9, *))
            return kCVImageBufferYCbCrMatrix_ITU_R_2020;
        break;
    case COLOR_SPACE_BT709:
        return kCVImageBufferYCbCrMatrix_ITU_R_709_2;
    case COLOR_SPACE_UNDEF:
        break;
    default:
        if (__builtin_available(macOS 10.13, iOS 11, tvOS 11, watchOS 4, *)) {
            enum iso_23001_8_mc mc_cicp =
                vlc_coeffs_to_iso_23001_8_mc(color_space);
            return CVYCbCrMatrixGetStringForIntegerCodePoint(mc_cicp);
        }
    }
    return NULL;
}

CFStringRef
cvpx_map_ColorPrimaries_from_vcp(video_color_primaries_t color_primaries)
{
    switch (color_primaries) {
    case COLOR_PRIMARIES_BT2020:
        return kCVImageBufferColorPrimaries_ITU_R_2020;
    case COLOR_PRIMARIES_BT709:
        return kCVImageBufferColorPrimaries_ITU_R_709_2;
    case COLOR_PRIMARIES_SMTPE_170:
        return kCVImageBufferColorPrimaries_SMPTE_C;
    case COLOR_PRIMARIES_EBU_3213:
        return kCVImageBufferColorPrimaries_EBU_3213;
    case COLOR_PRIMARIES_UNDEF:
        break;
    default:
        if (__builtin_available(macOS 10.13, iOS 11, tvOS 11, watchOS 4, *)) {
            enum iso_23001_8_cp cp_cicp =
                vlc_primaries_to_iso_23001_8_cp(color_primaries);
            return CVColorPrimariesGetStringForIntegerCodePoint(cp_cicp);
        }
    }
    return NULL;
}

CFStringRef
cvpx_map_TransferFunction_from_vtf(video_transfer_func_t transfer_func)
{
    switch (transfer_func) {
    case TRANSFER_FUNC_SMPTE_ST2084:
        if (__builtin_available(macOS 10.13, iOS 11, *))
            return kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ;
        break;
    case TRANSFER_FUNC_BT709:
    /* note: as stated by CVImageBuffer.h,
       kCVImageBufferTransferFunction_ITU_R_709_2 is equivalent to
       kCVImageBufferTransferFunction_ITU_R_2020 and preferred
    */
        return kCVImageBufferTransferFunction_ITU_R_709_2;
    case TRANSFER_FUNC_SMPTE_240:
        return kCVImageBufferTransferFunction_SMPTE_240M_1995;
    case TRANSFER_FUNC_HLG:
        if (__builtin_available(macOS 10.13, iOS 11, *))
            return kCVImageBufferTransferFunction_ITU_R_2100_HLG;
        break;
    case TRANSFER_FUNC_LINEAR:
#if (TARGET_OS_OSX    && defined(__MAC_10_14)   && MAC_OS_X_VERSION_MAX_ALLOWED    >= __MAC_10_14) ||\
    (TARGET_OS_IPHONE && defined(__IPHONE_12_0) && __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_12_0) || \
    (TARGET_OS_TV     && defined(__TVOS_12_0)   && __TV_OS_VERSION_MAX_ALLOWED     >= __TVOS_12_0) || \
    (TARGET_OS_WATCH  && defined(__WATCHOS_5_0) && __WATCH_OS_VERSION_MAX_ALLOWED  >= __WATCHOS_5_0)
        if (__builtin_available(macOS 10.14, iOS 12, tvOS 12, watchOS 5, *))
            return kCVImageBufferTransferFunction_Linear;
#endif
        break;
    case TRANSFER_FUNC_SRGB:
        return kCVImageBufferTransferFunction_UseGamma;
    case TRANSFER_FUNC_UNDEF:
        break;
    default:
        if (__builtin_available(macOS 10.13, iOS 11, tvOS 11, watchOS 4, *)) {
            enum iso_23001_8_tc tc_cicp =
                vlc_xfer_to_iso_23001_8_tc(transfer_func);
            return CVTransferFunctionGetStringForIntegerCodePoint(tc_cicp);
        }
    }
    return NULL;
}

bool cvpx_has_attachment(CVPixelBufferRef pixelBuffer, CFStringRef key) {
#if (TARGET_OS_OSX    && defined(__MAC_12_0)    && MAC_OS_X_VERSION_MAX_ALLOWED    >= __MAC_12_0) ||\
    (TARGET_OS_IOS    && defined(__IPHONE_15_0) && __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_15_0) || \
    (TARGET_OS_TV     && defined(__TVOS_15_0)   && __TV_OS_VERSION_MAX_ALLOWED     >= __TVOS_15_0) || \
    (TARGET_OS_WATCH  && defined(__WATCHOS_8_0) && __WATCH_OS_VERSION_MAX_ALLOWED  >= __WATCHOS_8_0)
    if (__builtin_available(macOS 12.0, iOS 15, tvOS 15, watchOS 8, *)) {
        return CVBufferHasAttachment(pixelBuffer, key);
    }
#endif

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return CVBufferGetAttachment(pixelBuffer, key, NULL) != NULL;
#pragma clang diagnostic pop
}



#include <arpa/inet.h>

CFDataRef
cvpx_create_mastering_display_color_volume_data(const video_format_t *fmt)
{
    if (!fmt)
        return NULL;

    bool has_mastering = fmt->mastering.max_luminance != 0 ||
                         fmt->mastering.min_luminance != 0 ||
                         fmt->mastering.white_point[0] != 0 ||
                         fmt->mastering.primaries[0] != 0;

    bool is_hdr = fmt->transfer == TRANSFER_FUNC_SMPTE_ST2084 ||
                  fmt->transfer == TRANSFER_FUNC_HLG ||
                  fmt->primaries == COLOR_PRIMARIES_BT2020;

    if (!has_mastering && !is_hdr)
        return NULL;

    struct {
        uint16_t display_primaries[3][2];
        uint16_t white_point[2];
        uint32_t max_luminance;
        uint32_t min_luminance;
    } __attribute__((packed)) st2086;

    if (has_mastering) {
        st2086.display_primaries[0][0] = htons(fmt->mastering.primaries[0]);
        st2086.display_primaries[0][1] = htons(fmt->mastering.primaries[1]);
        st2086.display_primaries[1][0] = htons(fmt->mastering.primaries[2]);
        st2086.display_primaries[1][1] = htons(fmt->mastering.primaries[3]);
        st2086.display_primaries[2][0] = htons(fmt->mastering.primaries[4]);
        st2086.display_primaries[2][1] = htons(fmt->mastering.primaries[5]);
        st2086.white_point[0] = htons(fmt->mastering.white_point[0]);
        st2086.white_point[1] = htons(fmt->mastering.white_point[1]);
        if (st2086.display_primaries[0][0] == 0) {
            st2086.display_primaries[0][0] = htons(13250); // G.x
            st2086.display_primaries[0][1] = htons(34500); // G.y
            st2086.display_primaries[1][0] = htons(7500);  // B.x
            st2086.display_primaries[1][1] = htons(3000);  // B.y
            st2086.display_primaries[2][0] = htons(34000); // R.x
            st2086.display_primaries[2][1] = htons(16000); // R.y
        }
        if (st2086.white_point[0] == 0) {
            st2086.white_point[0] = htons(15635); // D65.x
            st2086.white_point[1] = htons(16450); // D65.y
        }
        uint32_t max_l = fmt->mastering.max_luminance;
        if (max_l > 0 && max_l < 10000)
            max_l *= 10000;
        st2086.max_luminance = htonl(max_l ? max_l : 10000000);
        st2086.min_luminance = htonl(fmt->mastering.min_luminance ? fmt->mastering.min_luminance : 1);
    } else {
        /* Default HDR10 Mastering Display: BT.2020 primaries, D65 white point, 1000 nits max, 0.0001 nits min */
        /* ST 2086 SEI order: 0=Green, 1=Blue, 2=Red in 0.00002 units */
        st2086.display_primaries[0][0] = htons(13250); // G.x: 0.265
        st2086.display_primaries[0][1] = htons(34500); // G.y: 0.690
        st2086.display_primaries[1][0] = htons(7500);  // B.x: 0.150
        st2086.display_primaries[1][1] = htons(3000);  // B.y: 0.060
        st2086.display_primaries[2][0] = htons(34000); // R.x: 0.680
        st2086.display_primaries[2][1] = htons(16000); // R.y: 0.320
        st2086.white_point[0] = htons(15635);          // D65.x: 0.3127
        st2086.white_point[1] = htons(16450);          // D65.y: 0.3290
        st2086.max_luminance = htonl(10000000);        // 1000 nits in 0.0001 nit units
        st2086.min_luminance = htonl(1);               // 0.0001 nits in 0.0001 nit units
    }

    return CFDataCreate(kCFAllocatorDefault, (const UInt8 *)&st2086, sizeof(st2086));
}

CFDataRef
cvpx_create_content_light_level_data(const video_format_t *fmt)
{
    if (!fmt)
        return NULL;

    bool has_lighting = (fmt->lighting.MaxCLL != 0 || fmt->lighting.MaxFALL != 0);
    bool is_hdr = fmt->transfer == TRANSFER_FUNC_SMPTE_ST2084 ||
                  fmt->transfer == TRANSFER_FUNC_HLG ||
                  fmt->primaries == COLOR_PRIMARIES_BT2020;

    if (!has_lighting && !is_hdr)
        return NULL;

    struct {
        uint16_t max_cll;
        uint16_t max_fall;
    } __attribute__((packed)) cta861_3;

    if (has_lighting) {
        cta861_3.max_cll = htons(fmt->lighting.MaxCLL ? fmt->lighting.MaxCLL : 1000);
        cta861_3.max_fall = htons(fmt->lighting.MaxFALL ? fmt->lighting.MaxFALL : (fmt->lighting.MaxCLL ? fmt->lighting.MaxCLL / 2 : 400));
    } else {
        cta861_3.max_cll = htons(1000); // 1000 nits MaxCLL
        cta861_3.max_fall = htons(400);  // 400 nits MaxFALL
    }

    return CFDataCreate(kCFAllocatorDefault, (const UInt8 *)&cta861_3, sizeof(cta861_3));
}

void
cvpx_attach_hdr_metadata(CVPixelBufferRef cvpx, const video_format_t *fmt)
{
    if (!cvpx || !fmt)
        return;

#if (TARGET_OS_OSX && defined(__MAC_10_13)) || (TARGET_OS_IPHONE && defined(__IPHONE_11_0))
    if (__builtin_available(macOS 10.13, iOS 11, tvOS 11, watchOS 4, *))
    {
        CFDataRef mdcv = cvpx_create_mastering_display_color_volume_data(fmt);
        if (mdcv)
        {
            CVBufferSetAttachment(cvpx, kCVImageBufferMasteringDisplayColorVolumeKey,
                                  mdcv, kCVAttachmentMode_ShouldPropagate);
            CFRelease(mdcv);
        }

        CFDataRef clli = cvpx_create_content_light_level_data(fmt);
        if (clli)
        {
            CVBufferSetAttachment(cvpx, kCVImageBufferContentLightLevelInfoKey,
                                  clli, kCVAttachmentMode_ShouldPropagate);
            CFRelease(clli);
        }
    }
#endif
}

void
cvpx_extract_color_properties(CVPixelBufferRef cvpx, video_format_t *fmt)
{
    if (!cvpx || !fmt)
        return;

    CFDictionaryRef attachmentDict =
        CVBufferGetAttachments(cvpx, kCVAttachmentMode_ShouldPropagate);
    if (!attachmentDict || CFDictionaryGetCount(attachmentDict) == 0)
        return;

    CFStringRef matrix = CFDictionaryGetValue(attachmentDict, kCVImageBufferYCbCrMatrixKey);
    if (matrix)
    {
        if (CFEqual(matrix, kCVImageBufferYCbCrMatrix_ITU_R_709_2))
            fmt->space = COLOR_SPACE_BT709;
        else if (CFEqual(matrix, kCVImageBufferYCbCrMatrix_ITU_R_601_4))
            fmt->space = COLOR_SPACE_BT601;
        else if (__builtin_available(macOS 10.11, iOS 9, *) &&
                 CFEqual(matrix, kCVImageBufferYCbCrMatrix_ITU_R_2020))
            fmt->space = COLOR_SPACE_BT2020;
    }

    CFStringRef primaries = CFDictionaryGetValue(attachmentDict, kCVImageBufferColorPrimariesKey);
    if (primaries)
    {
        if (CFEqual(primaries, kCVImageBufferColorPrimaries_ITU_R_709_2))
            fmt->primaries = COLOR_PRIMARIES_BT709;
        else if (CFEqual(primaries, kCVImageBufferColorPrimaries_EBU_3213))
            fmt->primaries = COLOR_PRIMARIES_EBU_3213;
        else if (CFEqual(primaries, kCVImageBufferColorPrimaries_SMPTE_C))
            fmt->primaries = COLOR_PRIMARIES_SMTPE_170;
        else if (CFEqual(primaries, kCVImageBufferColorPrimaries_ITU_R_2020))
            fmt->primaries = COLOR_PRIMARIES_BT2020;
        else if (__builtin_available(macOS 10.11, iOS 9, *) &&
                 CFEqual(primaries, kCVImageBufferColorPrimaries_P3_D65))
            fmt->primaries = COLOR_PRIMARIES_DCI_P3;
    }

    CFStringRef transfer = CFDictionaryGetValue(attachmentDict, kCVImageBufferTransferFunctionKey);
    if (transfer)
    {
        if (CFEqual(transfer, kCVImageBufferTransferFunction_ITU_R_709_2))
            fmt->transfer = TRANSFER_FUNC_BT709;
        else if (CFEqual(transfer, kCVImageBufferTransferFunction_SMPTE_240M_1995))
            fmt->transfer = TRANSFER_FUNC_SMPTE_240;
        else if (CFEqual(transfer, kCVImageBufferTransferFunction_UseGamma))
            fmt->transfer = TRANSFER_FUNC_SRGB;
        else if (__builtin_available(macOS 10.13, iOS 11, *) &&
                 CFEqual(transfer, kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ))
            fmt->transfer = TRANSFER_FUNC_SMPTE_ST2084;
        else if (__builtin_available(macOS 10.13, iOS 11, *) &&
                 CFEqual(transfer, kCVImageBufferTransferFunction_ITU_R_2100_HLG))
            fmt->transfer = TRANSFER_FUNC_HLG;
        else if (__builtin_available(macOS 10.14, iOS 12, *) &&
                 CFEqual(transfer, kCVImageBufferTransferFunction_Linear))
            fmt->transfer = TRANSFER_FUNC_LINEAR;
    }

#if (TARGET_OS_OSX && defined(__MAC_10_13)) || (TARGET_OS_IPHONE && defined(__IPHONE_11_0))
    if (__builtin_available(macOS 10.13, iOS 11, tvOS 11, watchOS 4, *))
    {
        CFDataRef mdcvData = CFDictionaryGetValue(attachmentDict, kCVImageBufferMasteringDisplayColorVolumeKey);
        if (mdcvData && CFGetTypeID(mdcvData) == CFDataGetTypeID() && CFDataGetLength(mdcvData) >= 24)
        {
            const uint8_t *bytes = CFDataGetBytePtr(mdcvData);
            const uint16_t *u16 = (const uint16_t *)bytes;
            const uint32_t *u32 = (const uint32_t *)(bytes + 16);
            fmt->mastering.primaries[0] = ntohs(u16[0]);
            fmt->mastering.primaries[1] = ntohs(u16[1]);
            fmt->mastering.primaries[2] = ntohs(u16[2]);
            fmt->mastering.primaries[3] = ntohs(u16[3]);
            fmt->mastering.primaries[4] = ntohs(u16[4]);
            fmt->mastering.primaries[5] = ntohs(u16[5]);
            fmt->mastering.white_point[0] = ntohs(u16[6]);
            fmt->mastering.white_point[1] = ntohs(u16[7]);
            fmt->mastering.max_luminance = ntohl(u32[0]);
            fmt->mastering.min_luminance = ntohl(u32[1]);
        }

        CFDataRef clliData = CFDictionaryGetValue(attachmentDict, kCVImageBufferContentLightLevelInfoKey);
        if (clliData && CFGetTypeID(clliData) == CFDataGetTypeID() && CFDataGetLength(clliData) >= 4)
        {
            const uint16_t *u16 = (const uint16_t *)CFDataGetBytePtr(clliData);
            fmt->lighting.MaxCLL = ntohs(u16[0]);
            fmt->lighting.MaxFALL = ntohs(u16[1]);
        }
    }
#endif
}

void cvpx_attach_mapped_color_properties(CVPixelBufferRef cvpx,
                                         const video_format_t *fmt)
{
    if (!cvpx || !fmt)
        return;

    bool is_hdr = (fmt->transfer == TRANSFER_FUNC_SMPTE_ST2084 ||
                   fmt->transfer == TRANSFER_FUNC_HLG ||
                   fmt->primaries == COLOR_PRIMARIES_BT2020 ||
                   fmt->mastering.max_luminance > 0 ||
                   fmt->lighting.MaxCLL > 0);

    video_color_space_t space = fmt->space;
    video_color_primaries_t primaries = fmt->primaries;
    video_transfer_func_t transfer = fmt->transfer;

    if (is_hdr) {
        if (space == COLOR_SPACE_UNDEF)
            space = COLOR_SPACE_BT2020;
        if (primaries == COLOR_PRIMARIES_UNDEF)
            primaries = COLOR_PRIMARIES_BT2020;
        if (transfer == TRANSFER_FUNC_UNDEF)
            transfer = TRANSFER_FUNC_SMPTE_ST2084;
    }

    CFStringRef color_matrix =
        cvpx_map_YCbCrMatrix_from_vcs(space);
    if (color_matrix) {
        CVBufferSetAttachment(
            cvpx,
            kCVImageBufferYCbCrMatrixKey,
            color_matrix,
            kCVAttachmentMode_ShouldPropagate
        );
    }

    CFStringRef color_primaries =
        cvpx_map_ColorPrimaries_from_vcp(primaries);
    if (color_primaries) {
        CVBufferSetAttachment(
            cvpx,
            kCVImageBufferColorPrimariesKey,
            color_primaries,
            kCVAttachmentMode_ShouldPropagate
        );
    }

    CFStringRef color_transfer_func =
        cvpx_map_TransferFunction_from_vtf(transfer);
    if (color_transfer_func) {
        CVBufferSetAttachment(
            cvpx,
            kCVImageBufferTransferFunctionKey,
            color_transfer_func,
            kCVAttachmentMode_ShouldPropagate
        );
    }

    if (transfer == TRANSFER_FUNC_SRGB)
    {
        Float32 gamma = 2.2;
        CFNumberRef value =
            CFNumberCreate(NULL, kCFNumberFloat32Type, &gamma);
        CVBufferSetAttachment(
            cvpx,
            kCVImageBufferGammaLevelKey,
            value,
            kCVAttachmentMode_ShouldPropagate
        );
        CFRelease(value);
    }

    /* Also attach mastering display and content light level HDR metadata */
    video_format_t hdr_fmt = *fmt;
    hdr_fmt.space = space;
    hdr_fmt.primaries = primaries;
    hdr_fmt.transfer = transfer;
    cvpx_attach_hdr_metadata(cvpx, &hdr_fmt);
}

struct cvpx_video_context
{
    const struct vlc_video_context_operations *ops;
    enum cvpx_video_context_type type;
    uint8_t private[];
};

static void
cvpx_video_context_Destroy(void *priv)
{
    struct cvpx_video_context *cvpx_vctx = priv;
    if (cvpx_vctx->ops->destroy)
        cvpx_vctx->ops->destroy(&cvpx_vctx->private);
}

vlc_video_context *
vlc_video_context_CreateCVPX(vlc_decoder_device *device,
                              enum cvpx_video_context_type type, size_t type_size,
                              const struct vlc_video_context_operations *ops)
{
    static const struct vlc_video_context_operations vctx_ops =
    {
        cvpx_video_context_Destroy,
    };
    vlc_video_context *vctx =
        vlc_video_context_Create(device, VLC_VIDEO_CONTEXT_CVPX,
                                 sizeof(struct cvpx_video_context) + type_size,
                                 &vctx_ops);
    if (!vctx)
        return NULL;
    struct cvpx_video_context *cvpx_vctx =
        vlc_video_context_GetPrivate(vctx, VLC_VIDEO_CONTEXT_CVPX);
    assert(cvpx_vctx != NULL);
    cvpx_vctx->type = type;
    cvpx_vctx->ops = ops;

    return vctx;
}

void *
vlc_video_context_GetCVPXPrivate(vlc_video_context *vctx,
                                 enum cvpx_video_context_type type)
{
    struct cvpx_video_context *cvpx_vctx =
        vlc_video_context_GetPrivate(vctx, VLC_VIDEO_CONTEXT_CVPX);

    if (cvpx_vctx && cvpx_vctx->type == type)
        return &cvpx_vctx->private;
    return NULL;
}
