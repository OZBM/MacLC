/*****************************************************************************
 * videotoolbox.c: Video Toolbox decoder
 *****************************************************************************
 * Copyright © 2014-2015 VideoLabs SAS
 *
 * Authors: Felix Paul Kühne <fkuehne # videolan.org>
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

#pragma mark preamble

#ifdef HAVE_CONFIG_H
# import "config.h"
#endif

#import <vlc_common.h>
#import <vlc_plugin.h>
#import <vlc_codec.h>
#import <vlc_ancillary.h>
#import "../hxxx_helper.h"
#import <vlc_bits.h>
#import <vlc_boxes.h>
#import "../vt_utils.h"
#import "../../packetizer/h264_nal.h"
#import "../../packetizer/h264_slice.h"
#import "../../packetizer/hxxx_nal.h"
#import "../../packetizer/hxxx_sei.h"
#import "pacer.h"
#import "dpb.h"

#import <VideoToolbox/VideoToolbox.h>
#import <VideoToolbox/VTErrors.h>

#import <CoreFoundation/CoreFoundation.h>
#import <TargetConditionals.h>

#import <sys/types.h>
#import <sys/sysctl.h>
#import <mach/machine.h>

#ifndef kCMVideoCodecType_AV1
#define kCMVideoCodecType_AV1 'av01'
#endif

#define VT_ALIGNMENT 16
#define VT_RESTART_MAX 1

#pragma mark - local prototypes

enum vtsession_status
{
    VTSESSION_STATUS_OK,
    VTSESSION_STATUS_RESTART,
    VTSESSION_STATUS_RESTART_CHROMA,
    VTSESSION_STATUS_ABORT,
    VTSESSION_STATUS_VOUT_FAILURE,
};

static int ConfigureVout(decoder_t *);
static CFDictionaryRef ESDSExtradataInfoCreate(decoder_t *, uint8_t *, uint32_t);
static CFDictionaryRef ExtradataInfoCreate(CFStringRef, void *, size_t);
static CFMutableDictionaryRef CreateSessionDescriptionFormat(decoder_t *, unsigned, unsigned);
static int HandleVTStatus(decoder_t *, OSStatus, enum vtsession_status *);
static int DecodeBlock(decoder_t *, block_t *);
static void RequestFlush(decoder_t *);
static void Drain(decoder_t *p_dec, bool flush);
static void DecoderCallback(void *, void *, OSStatus, VTDecodeInfoFlags,
                            CVPixelBufferRef, CMTime, CMTime);
static Boolean deviceSupportsHEVC();
#if defined(__aarch64__)
static Boolean deviceSupportsAV1();
#endif
static bool deviceSupports42010bitRendering();
static Boolean deviceSupportsAdvancedProfiles();
static Boolean deviceSupportsAdvancedLevels();

#pragma mark - decoder structure

#define VT_MAX_SEI_COUNT 16

#define DEFAULT_FRAME_RATE_NUM 30000
#define DEFAULT_FRAME_RATE_DEN 1001

typedef struct decoder_sys_t
{
    CMVideoCodecType            codec;

    /* Codec specific callbacks and contexts */
    bool                        (*pf_codec_init)(decoder_t *);
    void                        (*pf_codec_clean)(void *);
    bool                        (*pf_codec_supported)(decoder_t *);
    void                        (*pf_codec_flush)(decoder_t *);
    bool                        (*pf_late_start)(decoder_t *);
    block_t*                    (*pf_process_block)(decoder_t *,
                                                    block_t *, bool *);
    bool                        (*pf_need_restart)(decoder_t *,
                                                   VTDecompressionSessionRef);
    bool                        (*pf_configure_vout)(decoder_t *);
    CFDictionaryRef             (*pf_copy_extradata)(decoder_t *);
    bool                        (*pf_fill_reorder_info)(decoder_t *, const block_t *,
                                                        frame_info_t *);
    void                         *p_codec_context;
    /* !Codec specific callbacks and contexts */

    enum
    {
        STATE_BITSTREAM_WAITING_RAP = -2,
        STATE_BITSTREAM_DISCARD_LEADING = -1,
        STATE_BITSTREAM_SYNCED = 0,
    } sync_state, start_sync_state;
    enum
    {
        STATE_DECODER_WAITING_RAP = 0,
        STATE_DECODER_STARTED,
    } decoder_state;
    VTDecompressionSessionRef   session;
    CMVideoFormatDescriptionRef videoFormatDescription;

    /* Decoder Callback Synchronization */
    vlc_mutex_t                 lock;
    bool                        b_discard_decoder_output;

    struct dpb_s                dpb;

    bool                        b_format_propagated;

    enum vtsession_status       vtsession_status;

    OSType                      i_cvpx_format;
    bool                        b_cvpx_format_forced;

    date_t                      pts;

    vlc_video_context          *vctx;
    /* Picture pacer to work-around the VT session allocating too many CVPX buffers
     * that can lead to a OOM. */
    struct pic_pacer           *pic_pacer;
} decoder_sys_t;

#pragma mark - start & stop

static OSType GetBestChroma(uint8_t i_chroma_format, uint8_t i_depth_luma,
                            uint8_t i_depth_chroma)
{
    if (i_chroma_format == 1 /* YUV 4:2:0 */)
    {
        if (i_depth_luma == 8 && i_depth_chroma == 8)
            return kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange;
        if (i_depth_luma == 10 && i_depth_chroma == 10)
        {
            if (deviceSupportsHEVC() && deviceSupports42010bitRendering())
                return kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange;

           /* Force BGRA output (and let VT handle the tone mapping) since legacy
            * OpenGL (caopengllayer at priority 300) cannot handle 10/16-bit textures.
            * This is the case for iOS and older macOS devices not supporting HEVC/Metal. */
            return kCVPixelFormatType_32BGRA;
        }
        else if (i_depth_luma > 10 && i_depth_chroma > 10)
        {
            /* Apple CoreVideo defines no 4:2:0 16-bit biplanar format (there is no
             * kCVPixelFormatType_420YpCbCr16BiPlanar... in the SDK). The only 16-bit
             * biplanar YCbCr formats defined by Apple are 4:2:2
             * (kCVPixelFormatType_422YpCbCr16BiPlanarVideoRange = 'sv22') and 4:4:4
             * (kCVPixelFormatType_444YpCbCr16BiPlanarVideoRange = 'sv44').
             *
             * For >10-bit HEVC content on macOS, select the 4:2:2 16-bit biplanar
             * format ('sv22'), letting VideoToolbox perform chroma upsampling.
             * Where 16-bit 4:2:2 cannot be used, fall back to the 10-bit P010
             * format (kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange) where
             * supported, preserving HDR precision far better than crushing to
             * 8-bit 32BGRA. */
#if TARGET_OS_OSX
            if (deviceSupportsHEVC() && deviceSupports42010bitRendering())
                return kCVPixelFormatType_422YpCbCr16BiPlanarVideoRange;
#endif
            if (deviceSupportsHEVC() && deviceSupports42010bitRendering())
                return kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange;

            return kCVPixelFormatType_32BGRA;
        }
    }
    return 0;
}

/* Codec Specific */

/** H26x Specific */
static OSType GetBestChromaFromHxxx(struct hxxx_helper *hh)
{
    uint8_t a, b, c;
    if (hxxx_helper_get_chroma_chroma(hh, &a, &b, &c) != VLC_SUCCESS)
        return 0;
    return GetBestChroma(a, b, c);
}

/** H264 Specific */

struct vt_h264_context
{
    struct hxxx_helper hh;
    h264_poc_context_t poc;
};

static void GetxPSH264(uint8_t i_pps_id, void *priv,
                      const h264_sequence_parameter_set_t **pp_sps,
                      const h264_picture_parameter_set_t **pp_pps)
{
    struct vt_h264_context *h264ctx = priv;

    *pp_pps = h264ctx->hh.h264.pps_list[i_pps_id].h264_pps;
    if (*pp_pps == NULL)
        *pp_sps = NULL;
    else
        *pp_sps = h264ctx->hh.h264.sps_list[h264_get_pps_sps_id(*pp_pps)].h264_sps;
}

struct sei_callback_h264_s
{
    uint8_t i_pic_struct;
    const h264_sequence_parameter_set_t *p_sps;
};

static bool ParseH264SEI(const hxxx_sei_data_t *p_sei_data, void *priv)
{
    if (p_sei_data->i_type == HXXX_SEI_PIC_TIMING)
    {
        struct sei_callback_h264_s *s = priv;
        if (s->p_sps)
        {
            uint8_t i_dpb_output_delay;
            h264_decode_sei_pic_timing( p_sei_data->p_bs, s->p_sps,
                                       &s->i_pic_struct,
                                       &i_dpb_output_delay );
            VLC_UNUSED(i_dpb_output_delay);
        }
        return false;
    }

    return true;
}

static bool FillReorderInfoH264(decoder_t *p_dec, const block_t *p_block,
                                frame_info_t *p_info)
{
    decoder_sys_t *p_sys = p_dec->p_sys;
    struct vt_h264_context *h264ctx = p_sys->p_codec_context;
    hxxx_iterator_ctx_t itctx;
    hxxx_iterator_init(&itctx, p_block->p_buffer, p_block->i_buffer,
                       h264ctx->hh.i_output_nal_length_size);

    const uint8_t *p_nal; size_t i_nal;
    struct
    {
        const uint8_t *p_nal;
        size_t i_nal;
    } sei_array[VT_MAX_SEI_COUNT];
    size_t i_sei_count = 0;
    while (hxxx_iterate_next(&itctx, &p_nal, &i_nal))
    {
        if (i_nal < 2)
            continue;

        const enum h264_nal_unit_type_e i_nal_type = p_nal[0] & 0x1F;

        if (i_nal_type <= H264_NAL_SLICE_IDR && i_nal_type != H264_NAL_UNKNOWN)
        {
            h264_slice_t *slice = h264_decode_slice(p_nal, i_nal, GetxPSH264, h264ctx);
            if (!slice)
                return false;

            const h264_sequence_parameter_set_t *p_sps;
            const h264_picture_parameter_set_t *p_pps;
            GetxPSH264(h264_get_slice_pps_id(slice), h264ctx, &p_sps, &p_pps);
            if (p_sps)
            {
                int bFOC;
                h264_compute_poc(p_sps, slice, &h264ctx->poc,
                                 &p_info->i_poc, &p_info->i_foc, &bFOC);

                enum h264_slice_type_e slicetype = h264_get_slice_type(slice);
                p_info->b_keyframe = slicetype == H264_SLICE_TYPE_I;
                p_info->b_flush = p_info->b_keyframe || h264_has_mmco5(slice);
                p_info->b_field = h264_is_field_pic(slice);
                p_info->b_progressive = !h264_using_adaptive_frames(p_sps) &&
                                        !p_info->b_field;

                struct sei_callback_h264_s sei;
                sei.p_sps = p_sps;
                sei.i_pic_struct = UINT8_MAX;

                for (size_t i = 0; i < i_sei_count; i++)
                    HxxxParseSEI(sei_array[i].p_nal, sei_array[i].i_nal, 1,
                                 ParseH264SEI, &sei);

                p_info->i_num_ts = h264_get_num_ts(p_sps, slice, sei.i_pic_struct,
                                                   p_info->i_foc, bFOC);

                h264_get_dpb_values(p_sps, &p_info->i_max_num_reorder, &p_info->i_max_pics_buffering);

                if (!p_info->b_progressive)
                    p_info->b_top_field_first = (sei.i_pic_struct % 2 == 1);

                /* Set frame rate for timings in case of missing rate */
                unsigned fr[2];
                if(h264_get_frame_rate(p_sps, fr, &fr[1]))
                {
                    p_info->field_rate_num = fr[0];
                    p_info->field_rate_den = fr[1];
                }
            }
            h264_slice_release(slice);

            return true; /* No need to parse further NAL */
        }
        else if (i_nal_type == H264_NAL_SEI)
        {
            if (i_sei_count < VT_MAX_SEI_COUNT)
            {
                sei_array[i_sei_count].p_nal = p_nal;
                sei_array[i_sei_count++].i_nal = i_nal;
            }
        }
    }

    return false;
}


static block_t *ProcessBlockH264(decoder_t *p_dec, block_t *p_block, bool *pb_config_changed)
{
    decoder_sys_t *p_sys = p_dec->p_sys;
    struct vt_h264_context *h264ctx = p_sys->p_codec_context;
    p_block = hxxx_helper_process_block(&h264ctx->hh, p_block);
    *pb_config_changed = hxxx_helper_has_new_config(&h264ctx->hh);
    return p_block;
}

static void CleanH264(void *p_codec_context)
{
    struct vt_h264_context *h264ctx = p_codec_context;
    hxxx_helper_clean(&h264ctx->hh);
    free(h264ctx);
}

static bool InitH264(decoder_t *p_dec)
{
    decoder_sys_t *p_sys = p_dec->p_sys;
    struct vt_h264_context *ctx = malloc(sizeof(*ctx));
    if(!ctx)
        return false;
    h264_poc_context_init(&ctx->poc);
    hxxx_helper_init(&ctx->hh, VLC_OBJECT(p_dec),
                     p_dec->fmt_in->i_codec, 0, 4);
    if(hxxx_helper_set_extra(&ctx->hh, p_dec->fmt_in->p_extra,
                                       p_dec->fmt_in->i_extra) != VLC_SUCCESS)
    {
        CleanH264(ctx);
        return false;
    }
    p_sys->p_codec_context = ctx;
    p_sys->dpb.i_fields_per_buffer = 2;
    return true;
}

static CFDictionaryRef CopyDecoderExtradataH264(decoder_t *p_dec)
{
    decoder_sys_t *p_sys = p_dec->p_sys;
    struct vt_h264_context *h264ctx = p_sys->p_codec_context;

    CFDictionaryRef extradata = NULL;
    if (p_dec->fmt_in->i_extra && h264ctx->hh.i_input_nal_length_size)
    {
        /* copy DecoderConfiguration */
        extradata = ExtradataInfoCreate(CFSTR("avcC"),
                                        p_dec->fmt_in->p_extra,
                                        p_dec->fmt_in->i_extra);
    }
    else if (hxxx_helper_has_config(&h264ctx->hh))
    {
        /* build DecoderConfiguration from gathered */
        block_t *p_avcC = hxxx_helper_get_extradata_block(&h264ctx->hh);
        if (p_avcC)
        {
            extradata = ExtradataInfoCreate(CFSTR("avcC"),
                                            p_avcC->p_buffer,
                                            p_avcC->i_buffer);
            block_Release(p_avcC);
        }
    }
    return extradata;
}

static bool CodecSupportedH264(decoder_t *p_dec)
{
    decoder_sys_t *p_sys = p_dec->p_sys;
    struct vt_h264_context *h264ctx = p_sys->p_codec_context;

    uint8_t i_profile, i_level;
    if (hxxx_helper_get_current_profile_level(&h264ctx->hh, &i_profile, &i_level))
        return true;

    switch (i_profile) {
        case PROFILE_H264_BASELINE:
        case PROFILE_H264_MAIN:
        case PROFILE_H264_HIGH:
            break;

        case PROFILE_H264_HIGH_10:
        {
            if (deviceSupportsAdvancedProfiles())
                break;
            else
            {
                msg_Err(p_dec, "current device doesn't support H264 10bits");
                return false;
            }
        }

        default:
        {
            msg_Warn(p_dec, "unknown H264 profile %" PRIx8, i_profile);
            return false;
        }
    }

    /* A level higher than 5.2 was not tested, so don't dare to try to decode
     * it. On SoC A8, 4.2 is the highest specified profile. on Twister, we can
     * do up to 5.2 */
    if (i_level > 52 || (i_level > 42 && !deviceSupportsAdvancedLevels()))
    {
        msg_Err(p_dec, "current device doesn't support this H264 level: %"
                PRIx8, i_level);
        return false;
    }

    if (p_sys->i_cvpx_format == 0 && !p_sys->b_cvpx_format_forced)
        p_sys->i_cvpx_format = GetBestChromaFromHxxx(&h264ctx->hh);

    return true;
}

static void CodecFlushH264(decoder_t *p_dec)
{
    decoder_sys_t *p_sys = p_dec->p_sys;
    struct vt_h264_context *h264ctx = p_sys->p_codec_context;
    h264_poc_context_init(&h264ctx->poc);
}

static bool LateStartH264(decoder_t *p_dec)
{
    decoder_sys_t *p_sys = p_dec->p_sys;
    struct vt_h264_context *h264ctx = p_sys->p_codec_context;
    return (p_dec->fmt_in->i_extra == 0 && !hxxx_helper_has_config(&h264ctx->hh));
}

static bool ConfigureVoutH264(decoder_t *p_dec)
{
    decoder_sys_t *p_sys = p_dec->p_sys;
    struct vt_h264_context *h264ctx = p_sys->p_codec_context;

    if (p_dec->fmt_in->video.primaries == COLOR_PRIMARIES_UNDEF)
    {
        video_color_primaries_t primaries;
        video_transfer_func_t transfer;
        video_color_space_t colorspace;
        video_color_range_t full_range;
        if (hxxx_helper_get_colorimetry(&h264ctx->hh,
                                        &primaries,
                                        &transfer,
                                        &colorspace,
                                        &full_range) == VLC_SUCCESS)
        {
            p_dec->fmt_out.video.primaries = primaries;
            p_dec->fmt_out.video.transfer = transfer;
            p_dec->fmt_out.video.space = colorspace;
            p_dec->fmt_out.video.color_range = full_range;
        }
    }

    if (!p_dec->fmt_in->video.i_visible_width || !p_dec->fmt_in->video.i_visible_height)
    {
        unsigned i_offset_x, i_offset_y, i_width, i_height, i_vis_width, i_vis_height;
        if (VLC_SUCCESS ==
           hxxx_helper_get_current_picture_size(&h264ctx->hh,
                                                &i_offset_x, &i_offset_y,
                                                &i_width, &i_height,
                                                &i_vis_width, &i_vis_height))
        {
            p_dec->fmt_out.video.i_x_offset = i_offset_x;
            p_dec->fmt_out.video.i_y_offset = i_offset_y;
            p_dec->fmt_out.video.i_visible_width = i_vis_width;
            p_dec->fmt_out.video.i_width = vlc_align(i_width, VT_ALIGNMENT);
            p_dec->fmt_out.video.i_visible_height = i_vis_height;
            p_dec->fmt_out.video.i_height = vlc_align(i_height, VT_ALIGNMENT);
        }
        else return false;
    }

    if (!p_dec->fmt_in->video.i_sar_num || !p_dec->fmt_in->video.i_sar_den)
    {
        int i_sar_num, i_sar_den;
        if (VLC_SUCCESS ==
            hxxx_helper_get_current_sar(&h264ctx->hh, &i_sar_num, &i_sar_den))
        {
            p_dec->fmt_out.video.i_sar_num = i_sar_num;
            p_dec->fmt_out.video.i_sar_den = i_sar_den;
        }
    }

    return true;
}

static bool VideoToolboxNeedsToRestartH264(decoder_t *p_dec,
                                           VTDecompressionSessionRef session)
{
    decoder_sys_t *p_sys = p_dec->p_sys;
    struct vt_h264_context *h264ctx = p_sys->p_codec_context;
    const struct hxxx_helper *hh = &h264ctx->hh;

    unsigned ox, oy, w, h, vw, vh;
    int sarn, sard;

    if (hxxx_helper_get_current_picture_size(hh, &ox, &oy, &w, &h, &vw, &vh) != VLC_SUCCESS)
        return true;

    if (hxxx_helper_get_current_sar(hh, &sarn, &sard) != VLC_SUCCESS)
        return true;

    bool b_ret = true;

    CFMutableDictionaryRef decoderConfiguration =
            CreateSessionDescriptionFormat(p_dec, sarn, sard);
    if (decoderConfiguration != NULL)
    {
        CMFormatDescriptionRef newvideoFormatDesc;
        /* create new video format description */
        OSStatus status = CMVideoFormatDescriptionCreate(kCFAllocatorDefault,
                                                         p_sys->codec,
                                                         vw, vh,
                                                         decoderConfiguration,
                                                         &newvideoFormatDesc);
        if (!status)
        {
            b_ret = !VTDecompressionSessionCanAcceptFormatDescription(session,
                                                                      newvideoFormatDesc);
            CFRelease(newvideoFormatDesc);
        }
        CFRelease(decoderConfiguration);
    }

    return b_ret;
}

/** HEVC Specific */

struct vt_hevc_dovi_state
{
    uint8_t coef_data_type;
    uint8_t coef_log2_denom;
    uint8_t bl_bit_depth;
    uint8_t el_bit_depth;
    uint8_t disable_residual_flag;
    uint8_t dm_compression;
    vlc_video_dovi_metadata_t last_dovi;
    bool b_valid;
};

struct vt_hevc_context
{
    struct hxxx_helper hh;
    hevc_poc_ctx_t poc;
    struct vt_hevc_dovi_state dovi_state;
    bool b_dovi_logged;
    bool b_dovi_warned;
    bool b_hdr10plus_logged;
};

struct vt_frame_info_t
{
    frame_info_t info;
    bool has_hdr10plus;
    vlc_video_hdr_dynamic_metadata_t hdr10plus;
    bool has_dovi;
    vlc_video_dovi_metadata_t dovi;
};

static void CleanHEVC(void *p_codec_context)
{
    struct vt_hevc_context *hevcctx = p_codec_context;
    hxxx_helper_clean(&hevcctx->hh);
    free(hevcctx);
}

static bool InitHEVC(decoder_t *p_dec)
{
    decoder_sys_t *p_sys = p_dec->p_sys;
    struct vt_hevc_context *ctx = malloc(sizeof(*ctx));
    if(!ctx)
        return false;
    hevc_poc_cxt_init(&ctx->poc);
    ctx->b_dovi_logged = false;
    ctx->b_dovi_warned = false;
    ctx->b_hdr10plus_logged = false;
    memset(&ctx->dovi_state, 0, sizeof(ctx->dovi_state));
    hxxx_helper_init(&ctx->hh, VLC_OBJECT(p_dec),
                     p_dec->fmt_in->i_codec, 0, 4);
    if(hxxx_helper_set_extra(&ctx->hh, p_dec->fmt_in->p_extra,
                                       p_dec->fmt_in->i_extra) != VLC_SUCCESS)
    {
        CleanHEVC(ctx);
        return false;
    }
    p_sys->p_codec_context = ctx;
    return true;
}

static void GetxPSHEVC(uint8_t i_id, void *priv,
                       hevc_picture_parameter_set_t **pp_pps,
                       hevc_sequence_parameter_set_t **pp_sps,
                       hevc_video_parameter_set_t **pp_vps)
{
    struct vt_hevc_context *hevcctx = priv;

    *pp_pps = hevcctx->hh.hevc.pps_list[i_id].hevc_pps;
    if (*pp_pps == NULL)
    {
        *pp_vps = NULL;
        *pp_sps = NULL;
    }
    else
    {
        uint8_t i_sps_id = hevc_get_pps_sps_id(*pp_pps);
        *pp_sps = hevcctx->hh.hevc.sps_list[i_sps_id].hevc_sps;
        if (*pp_sps == NULL)
            *pp_vps = NULL;
        else
        {
            uint8_t i_vps_id = hevc_get_sps_vps_id(*pp_sps);
            *pp_vps = hevcctx->hh.hevc.vps_list[i_vps_id].hevc_vps;
        }
    }
}

struct hevc_sei_callback_s
{
    hevc_sei_pic_timing_t *p_timing;
    const hevc_sequence_parameter_set_t *p_sps;
};

static bool ParseHEVCSEI(const hxxx_sei_data_t *p_sei_data, void *priv)
{
    if (p_sei_data->i_type == HXXX_SEI_PIC_TIMING)
    {
        struct hevc_sei_callback_s *s = priv;
        if (likely(s->p_sps))
            s->p_timing = hevc_decode_sei_pic_timing(p_sei_data->p_bs, s->p_sps);
        return false;
    }
    return true;
}

static size_t rpu_unescape_rbsp(const uint8_t *src, size_t src_len, uint8_t *dst, size_t dst_len)
{
    size_t di = 0;
    for (size_t si = 0; si < src_len && di < dst_len; )
    {
        if (si + 2 < src_len && src[si] == 0x00 && src[si + 1] == 0x00 && src[si + 2] == 0x03)
        {
            dst[di++] = 0x00;
            if (di < dst_len)
                dst[di++] = 0x00;
            si += 3;
        }
        else
        {
            dst[di++] = src[si++];
        }
    }
    return di;
}

static inline int64_t rpu_read_se_coef(bs_t *p_bs, uint8_t coef_data_type, uint8_t coef_log2_denom)
{
    if (coef_data_type == 0 /* RPU_COEFF_FIXED */)
    {
        int64_t ipart = bs_read_se(p_bs);
        uint64_t fpart = 0;
        if (coef_log2_denom > 0)
            fpart = bs_read(p_bs, coef_log2_denom);
        return (ipart * (1LL << coef_log2_denom)) + (int64_t)fpart;
    }
    else if (coef_data_type == 1 /* RPU_COEFF_FLOAT */)
    {
        uint32_t u = bs_read(p_bs, 32);
        float f;
        memcpy(&f, &u, sizeof(f));
        return (int64_t)(f * (1LL << coef_log2_denom));
    }
    return 0;
}

static inline uint64_t rpu_read_ue_coef(bs_t *p_bs, uint8_t coef_data_type, uint8_t coef_log2_denom)
{
    if (coef_data_type == 0 /* RPU_COEFF_FIXED */)
    {
        uint64_t ipart = bs_read_ue(p_bs);
        uint64_t fpart = 0;
        if (coef_log2_denom > 0)
            fpart = bs_read(p_bs, coef_log2_denom);
        return (ipart << coef_log2_denom) | fpart;
    }
    else if (coef_data_type == 1 /* RPU_COEFF_FLOAT */)
    {
        uint32_t u = bs_read(p_bs, 32);
        float f;
        memcpy(&f, &u, sizeof(f));
        return (uint64_t)(f * (1LL << coef_log2_denom));
    }
    return 0;
}

static bool ParseHEVCHDR10Plus(decoder_t *p_dec, struct vt_hevc_context *hevcctx,
                               const uint8_t *p_nal, size_t i_nal,
                               vlc_video_hdr_dynamic_metadata_t *out)
{
    VLC_UNUSED(p_dec);
    VLC_UNUSED(hevcctx);

    if (i_nal < 4)
        return false;

    const uint8_t *p_payload = p_nal + 2;
    size_t i_payload = i_nal - 2;

    uint8_t rbsp_buf[2048];
    uint8_t *p_rbsp = rbsp_buf;
    bool b_allocated = false;

    if (i_payload > sizeof(rbsp_buf))
    {
        p_rbsp = malloc(i_payload);
        if (!p_rbsp)
            return false;
        b_allocated = true;
    }

    size_t i_rbsp = rpu_unescape_rbsp(p_payload, i_payload, p_rbsp, i_payload);
    if (i_rbsp < 7)
    {
        if (b_allocated)
            free(p_rbsp);
        return false;
    }

    bs_t bs;
    bs_init(&bs, p_rbsp, i_rbsp);

    bool b_found = false;

    while (bs_aligned(&bs) && !bs_error(&bs) && !bs_eof(&bs))
    {
        size_t cur_pos = bs_pos(&bs);
        if (cur_pos >= i_rbsp * 8 || (i_rbsp * 8 - cur_pos) < 16)
            break;

        /* SEI payloadType */
        unsigned i_type = 0;
        while (!bs_eof(&bs))
        {
            uint8_t b = bs_read(&bs, 8);
            i_type += b;
            if (b != 0xff)
                break;
        }
        if (bs_error(&bs))
            break;

        /* SEI payloadSize */
        unsigned i_size = 0;
        while (!bs_eof(&bs))
        {
            uint8_t b = bs_read(&bs, 8);
            i_size += b;
            if (b != 0xff)
                break;
        }
        if (bs_error(&bs))
            break;

        cur_pos = bs_pos(&bs);
        if (cur_pos + (size_t)i_size * 8 > i_rbsp * 8)
            break;

        size_t end_pos = cur_pos + (size_t)i_size * 8;

        if (i_type == 4 /* user_data_registered_itu_t_t35 */ && i_size >= 7)
        {
            uint8_t country_code = bs_read(&bs, 8);
            if (country_code == 0xB5)
            {
                uint16_t provider_code = bs_read(&bs, 16);
                uint16_t provider_oriented_code = bs_read(&bs, 16);
                uint8_t application_identifier = bs_read(&bs, 8);

                if (provider_code == 0x003C &&
                    provider_oriented_code == 0x0001 &&
                    application_identifier == 0x04)
                {
                    /* SMPTE ST 2094-40 / HDR10+ payload */
                    memset(out, 0, sizeof(*out));
                    out->country_code = 0xB5;
                    out->application_version = bs_read(&bs, 8);
                    uint8_t num_windows = bs_read(&bs, 2);

                    if (num_windows >= 1 && num_windows <= 3)
                    {
                        for (int w = 1; w < num_windows; w++)
                        {
                            bs_skip(&bs, 153);
                        }

                        uint32_t targeted_max_luma = bs_read(&bs, 27);
                        out->targeted_luminance = (float)targeted_max_luma;

                        uint8_t actual_peak_flag = bs_read1(&bs);
                        if (actual_peak_flag)
                        {
                            uint8_t rows = bs_read(&bs, 5);
                            uint8_t cols = bs_read(&bs, 5);
                            if (rows >= 2 && rows <= 25 && cols >= 2 && cols <= 25)
                                bs_skip(&bs, (size_t)rows * cols * 4);
                            else
                                goto skip_msg;
                        }

                        for (int w = 0; w < num_windows; w++)
                        {
                            for (int i = 0; i < 3; i++)
                            {
                                uint32_t maxscl = bs_read(&bs, 17);
                                if (w == 0)
                                    out->maxscl[i] = (float)maxscl / 100000.0f;
                            }
                            uint32_t avg_maxrgb = bs_read(&bs, 17);
                            if (w == 0)
                                out->average_maxrgb = (float)avg_maxrgb / 100000.0f;

                            uint8_t num_hist = bs_read(&bs, 4);
                            if (num_hist > 15)
                                goto skip_msg;
                            if (w == 0)
                                out->num_histogram = num_hist;

                            for (int i = 0; i < num_hist; i++)
                            {
                                uint8_t pct = bs_read(&bs, 7);
                                uint32_t pctl = bs_read(&bs, 17);
                                if (w == 0 && i < 15)
                                {
                                    out->histogram[i].percentage = pct;
                                    out->histogram[i].percentile = (float)pctl / 100000.0f;
                                }
                            }

                            uint32_t frac_bright = bs_read(&bs, 10);
                            if (w == 0)
                                out->fraction_bright_pixels = (float)frac_bright / 1000.0f;
                        }

                        uint8_t mast_actual_peak_flag = bs_read1(&bs);
                        if (mast_actual_peak_flag)
                        {
                            uint8_t rows = bs_read(&bs, 5);
                            uint8_t cols = bs_read(&bs, 5);
                            if (rows >= 2 && rows <= 25 && cols >= 2 && cols <= 25)
                                bs_skip(&bs, (size_t)rows * cols * 4);
                            else
                                goto skip_msg;
                        }

                        for (int w = 0; w < num_windows; w++)
                        {
                            uint8_t tone_mapping_flag = bs_read1(&bs);
                            if (w == 0)
                                out->tone_mapping_flag = tone_mapping_flag;
                            if (tone_mapping_flag)
                            {
                                uint16_t knee_x = bs_read(&bs, 12);
                                uint16_t knee_y = bs_read(&bs, 12);
                                uint8_t num_anchors = bs_read(&bs, 4);
                                if (num_anchors > 15)
                                    goto skip_msg;
                                if (w == 0)
                                {
                                    out->knee_point_x = (float)knee_x / 4095.0f;
                                    out->knee_point_y = (float)knee_y / 4095.0f;
                                    out->num_bezier_anchors = num_anchors;
                                }
                                for (int i = 0; i < num_anchors; i++)
                                {
                                    uint16_t anchor = bs_read(&bs, 10);
                                    if (w == 0 && i < 15)
                                        out->bezier_curve_anchors[i] = (float)anchor / 1023.0f;
                                }
                            }

                            uint8_t color_sat_flag = bs_read1(&bs);
                            if (color_sat_flag)
                                bs_skip(&bs, 6);
                        }

                        if (!bs_error(&bs))
                            b_found = true;
                    }
                }
            }
        }

skip_msg:
        cur_pos = bs_pos(&bs);
        if (cur_pos < end_pos)
            bs_skip(&bs, end_pos - cur_pos);

        if (b_found)
            break;
    }

    if (b_allocated)
        free(p_rbsp);

    return b_found;
}

static bool ParseHEVCDoviRPU(decoder_t *p_dec, struct vt_hevc_context *hevcctx,
                             const uint8_t *p_nal, size_t i_nal,
                             vlc_video_dovi_metadata_t *out)
{
    if (i_nal < 4)
        return false;

    /* NAL header is 2 bytes */
    const uint8_t *p_payload = p_nal + 2;
    size_t i_payload = i_nal - 2;

    uint8_t rbsp_buf[2048];
    uint8_t *p_rbsp = rbsp_buf;
    bool b_allocated = false;

    if (i_payload > sizeof(rbsp_buf))
    {
        p_rbsp = malloc(i_payload);
        if (!p_rbsp)
            return false;
        b_allocated = true;
    }

    size_t i_rbsp = rpu_unescape_rbsp(p_payload, i_payload, p_rbsp, i_payload);
    if (i_rbsp < 4)
    {
        if (b_allocated)
            free(p_rbsp);
        return false;
    }

    bs_t bs;
    bs_init(&bs, p_rbsp, i_rbsp);

    uint8_t rpu_nal_prefix = bs_read(&bs, 8);
    if (rpu_nal_prefix != 25)
    {
        if (b_allocated)
            free(p_rbsp);
        return false;
    }

    uint8_t rpu_type = bs_read(&bs, 6);
    if (rpu_type != 2)
    {
        if (b_allocated)
            free(p_rbsp);
        return false;
    }

    uint16_t rpu_format = bs_read(&bs, 11);
    uint8_t vdr_rpu_profile = bs_read(&bs, 4);
    uint8_t vdr_rpu_level = bs_read(&bs, 4);
    VLC_UNUSED(vdr_rpu_profile);
    VLC_UNUSED(vdr_rpu_level);

    memset(out, 0, sizeof(*out));
    /* Defaults for colorspace matrices */
    out->nonlinear_matrix[0] = 1.0f;
    out->nonlinear_matrix[4] = 1.0f;
    out->nonlinear_matrix[8] = 1.0f;
    out->linear_matrix[0] = 1.0f;
    out->linear_matrix[4] = 1.0f;
    out->linear_matrix[8] = 1.0f;
    out->source_min_pq = 0;
    out->source_max_pq = 4095;
    out->nlq_method_idc = VLC_DOVI_NLQ_NONE;

    uint8_t coef_data_type = 0;
    uint8_t coef_log2_denom = 23;
    uint8_t bl_bit_depth = 10;
    uint8_t el_bit_depth = 10;
    uint8_t disable_residual_flag = 0;
    uint8_t dm_compression = 0;

    uint8_t vdr_seq_info_present_flag = bs_read1(&bs);
    if (vdr_seq_info_present_flag)
    {
        uint8_t chroma_resampling_explicit_filter_flag = bs_read1(&bs);
        VLC_UNUSED(chroma_resampling_explicit_filter_flag);
        coef_data_type = bs_read(&bs, 2);
        if (coef_data_type == 0 /* FIXED */)
        {
            coef_log2_denom = bs_read_ue(&bs);
            if (coef_log2_denom < 13 || coef_log2_denom > 32)
                goto fail;
        }
        else if (coef_data_type == 1 /* FLOAT */)
        {
            coef_log2_denom = 32;
        }
        else
        {
            goto fail;
        }

        uint8_t vdr_rpu_normalized_idc = bs_read(&bs, 2);
        VLC_UNUSED(vdr_rpu_normalized_idc);
        uint8_t bl_video_full_range_flag = bs_read1(&bs);
        VLC_UNUSED(bl_video_full_range_flag);

        if ((rpu_format & 0x700) == 0)
        {
            uint32_t bl_bit_depth_minus8 = bs_read_ue(&bs);
            uint32_t el_bit_depth_minus8 = bs_read_ue(&bs);
            uint32_t vdr_bit_depth_minus8 = bs_read_ue(&bs);

            el_bit_depth_minus8 &= 0xFF;
            if (bl_bit_depth_minus8 > 8 || el_bit_depth_minus8 > 8 || vdr_bit_depth_minus8 > 8)
                goto fail;

            bl_bit_depth = bl_bit_depth_minus8 + 8;
            el_bit_depth = el_bit_depth_minus8 + 8;

            uint8_t spatial_resampling_filter_flag = bs_read1(&bs);
            VLC_UNUSED(spatial_resampling_filter_flag);
            dm_compression = bs_read(&bs, 3);
            uint8_t el_spatial_resampling_filter_flag = bs_read1(&bs);
            VLC_UNUSED(el_spatial_resampling_filter_flag);
            disable_residual_flag = bs_read1(&bs);
        }
        else
        {
            goto fail;
        }

        /* Save sequence state */
        hevcctx->dovi_state.coef_data_type = coef_data_type;
        hevcctx->dovi_state.coef_log2_denom = coef_log2_denom;
        hevcctx->dovi_state.bl_bit_depth = bl_bit_depth;
        hevcctx->dovi_state.el_bit_depth = el_bit_depth;
        hevcctx->dovi_state.disable_residual_flag = disable_residual_flag;
        hevcctx->dovi_state.dm_compression = dm_compression;
    }
    else if (hevcctx->dovi_state.b_valid)
    {
        coef_data_type = hevcctx->dovi_state.coef_data_type;
        coef_log2_denom = hevcctx->dovi_state.coef_log2_denom;
        bl_bit_depth = hevcctx->dovi_state.bl_bit_depth;
        el_bit_depth = hevcctx->dovi_state.el_bit_depth;
        disable_residual_flag = hevcctx->dovi_state.disable_residual_flag;
        dm_compression = hevcctx->dovi_state.dm_compression;
    }
    else
    {
        goto fail;
    }

    out->bl_bit_depth = bl_bit_depth;
    out->el_bit_depth = el_bit_depth;
    out->coef_log2_denom = coef_log2_denom;

    uint8_t vdr_dm_metadata_present_flag = bs_read1(&bs);
    uint8_t use_prev_vdr_rpu_flag = bs_read1(&bs);
    bool use_nlq = ((rpu_format & 0x700) == 0) && !disable_residual_flag;

    if (use_prev_vdr_rpu_flag)
    {
        uint32_t prev_vdr_rpu_id = bs_read_ue(&bs);
        VLC_UNUSED(prev_vdr_rpu_id);
        if (hevcctx->dovi_state.b_valid)
        {
            out->nlq_method_idc = hevcctx->dovi_state.last_dovi.nlq_method_idc;
            memcpy(out->curves, hevcctx->dovi_state.last_dovi.curves, sizeof(out->curves));
            memcpy(out->nlq, hevcctx->dovi_state.last_dovi.nlq, sizeof(out->nlq));
        }
        else
        {
            goto fail;
        }
    }
    else
    {
        uint32_t vdr_rpu_id = bs_read_ue(&bs);
        VLC_UNUSED(vdr_rpu_id);
        uint32_t mapping_color_space = bs_read_ue(&bs);
        VLC_UNUSED(mapping_color_space);
        uint32_t mapping_chroma_format_idc = bs_read_ue(&bs);
        VLC_UNUSED(mapping_chroma_format_idc);

        for (int c = 0; c < 3; c++)
        {
            uint32_t num_pivots_minus_2 = bs_read_ue(&bs);
            if (num_pivots_minus_2 > 7)
                goto fail;
            uint32_t num_pivots = num_pivots_minus_2 + 2;
            out->curves[c].num_pivots = num_pivots;

            uint16_t pivot = 0;
            for (uint32_t i = 0; i < num_pivots; i++)
            {
                pivot += bs_read(&bs, bl_bit_depth);
                out->curves[c].pivots[i] = pivot;
            }
        }

        if (use_nlq)
        {
            uint32_t nlq_method_idc = bs_read(&bs, 3);
            out->nlq_method_idc = (enum vlc_dovi_nlq_method_t)nlq_method_idc;
            bs_skip(&bs, (size_t)bl_bit_depth * 2);
        }
        else
        {
            out->nlq_method_idc = VLC_DOVI_NLQ_NONE;
        }

        uint32_t num_x_partitions = bs_read_ue(&bs) + 1;
        uint32_t num_y_partitions = bs_read_ue(&bs) + 1;
        VLC_UNUSED(num_x_partitions);
        VLC_UNUSED(num_y_partitions);

        /* vdr_rpu_data_payload */
        for (int c = 0; c < 3; c++)
        {
            for (uint32_t i = 0; i < out->curves[c].num_pivots - 1; i++)
            {
                uint32_t mapping_idc = bs_read_ue(&bs);
                out->curves[c].mapping_idc[i] = (enum vlc_dovi_reshape_method_t)mapping_idc;
                if (mapping_idc == VLC_DOVI_RESHAPE_POLYNOMIAL)
                {
                    uint32_t poly_order_minus1 = bs_read_ue(&bs);
                    if (poly_order_minus1 > 1)
                        goto fail;
                    uint32_t poly_order = poly_order_minus1 + 1;
                    out->curves[c].poly_order[i] = poly_order;
                    if (poly_order_minus1 == 0)
                    {
                        uint8_t linear_interp_flag = bs_read1(&bs);
                        if (linear_interp_flag)
                            goto fail;
                    }
                    for (uint32_t k = 0; k <= poly_order; k++)
                    {
                        out->curves[c].poly_coef[i][k] = rpu_read_se_coef(&bs, coef_data_type, coef_log2_denom);
                    }
                }
                else if (mapping_idc == VLC_DOVI_RESHAPE_MMR)
                {
                    uint8_t mmr_order_minus1 = bs_read(&bs, 2);
                    if (mmr_order_minus1 > 2)
                        goto fail;
                    uint8_t mmr_order = mmr_order_minus1 + 1;
                    out->curves[c].mmr_order[i] = mmr_order;
                    out->curves[c].mmr_constant[i] = rpu_read_se_coef(&bs, coef_data_type, coef_log2_denom);
                    for (int j = 0; j < mmr_order; j++)
                    {
                        for (int k = 0; k < 7; k++)
                        {
                            out->curves[c].mmr_coef[i][j][k] = rpu_read_se_coef(&bs, coef_data_type, coef_log2_denom);
                        }
                    }
                }
                else
                {
                    goto fail;
                }
            }
        }

        if (use_nlq)
        {
            for (int c = 0; c < 3; c++)
            {
                out->nlq[c].offset = bs_read(&bs, el_bit_depth);
                out->nlq[c].offset_depth = el_bit_depth;
                out->nlq[c].hdr_in_max = rpu_read_ue_coef(&bs, coef_data_type, coef_log2_denom);
                if (out->nlq_method_idc == VLC_DOVI_NLQ_LINEAR_DZ)
                {
                    out->nlq[c].dz_slope = rpu_read_ue_coef(&bs, coef_data_type, coef_log2_denom);
                    out->nlq[c].dz_threshold = rpu_read_ue_coef(&bs, coef_data_type, coef_log2_denom);
                }
            }
        }
    }

    if (vdr_dm_metadata_present_flag)
    {
        uint32_t affected_dm_id = bs_read_ue(&bs);
        uint32_t current_dm_id = bs_read_ue(&bs);
        VLC_UNUSED(affected_dm_id);
        VLC_UNUSED(current_dm_id);
        uint32_t scene_refresh_flag = bs_read_ue(&bs);
        VLC_UNUSED(scene_refresh_flag);

        if (!dm_compression)
        {
            for (int i = 0; i < 9; i++)
            {
                int16_t val = (int16_t)bs_read(&bs, 16);
                out->nonlinear_matrix[i] = (float)val / 8192.0f;
            }
            for (int i = 0; i < 3; i++)
            {
                uint32_t offset = bs_read(&bs, 32);
                out->nonlinear_offset[i] = (float)(int32_t)offset / 268435456.0f;
            }
            for (int i = 0; i < 9; i++)
            {
                int16_t val = (int16_t)bs_read(&bs, 16);
                out->linear_matrix[i] = (float)val / 16384.0f;
            }

            bs_skip(&bs, 16); /* signal_eotf */
            bs_skip(&bs, 16); /* signal_eotf_param0 */
            bs_skip(&bs, 16); /* signal_eotf_param1 */
            bs_skip(&bs, 32); /* signal_eotf_param2 */
            bs_skip(&bs, 5);  /* signal_bit_depth */
            bs_skip(&bs, 2);  /* signal_color_space */
            bs_skip(&bs, 2);  /* signal_chroma_format */
            bs_skip(&bs, 2);  /* signal_full_range_flag */
            out->source_min_pq = bs_read(&bs, 12);
            out->source_max_pq = bs_read(&bs, 12);
            bs_skip(&bs, 10); /* source_diagonal */
        }

        uint32_t num_ext_blocks = bs_read_ue(&bs);
        bs_align(&bs);

        for (uint32_t b = 0; b < num_ext_blocks && !bs_error(&bs); b++)
        {
            uint32_t ext_block_length = bs_read_ue(&bs);
            uint8_t ext_block_level = bs_read(&bs, 8);
            size_t start_pos = bs_pos(&bs);
            size_t block_bits = (size_t)ext_block_length * 8;

            if (ext_block_level == 1)
            {
                out->source_min_pq = bs_read(&bs, 12);
                out->source_max_pq = bs_read(&bs, 12);
                bs_skip(&bs, 12); /* source_mid_pq */
            }

            size_t current_pos = bs_pos(&bs);
            if (current_pos > start_pos && current_pos - start_pos < block_bits)
            {
                bs_skip(&bs, block_bits - (current_pos - start_pos));
            }
            else if (current_pos == start_pos)
            {
                bs_skip(&bs, block_bits);
            }
        }
    }

    if (bs_error(&bs))
        goto fail;

    if (b_allocated)
        free(p_rbsp);

    hevcctx->dovi_state.last_dovi = *out;
    hevcctx->dovi_state.b_valid = true;
    return true;

fail:
    if (b_allocated)
        free(p_rbsp);

    if (!hevcctx->b_dovi_warned)
    {
        msg_Dbg(p_dec, "Dolby Vision RPU bitstream read error or unsupported profile");
        hevcctx->b_dovi_warned = true;
    }
    return false;
}

static bool FillReorderInfoHEVC(decoder_t *p_dec, const block_t *p_block,
                                frame_info_t *p_info)
{
    decoder_sys_t *p_sys = p_dec->p_sys;
    struct vt_hevc_context *hevcctx = p_sys->p_codec_context;
    hxxx_iterator_ctx_t itctx;
    hxxx_iterator_init(&itctx, p_block->p_buffer, p_block->i_buffer,
                       hevcctx->hh.i_output_nal_length_size);

    /* Pre-scan the block for Dolby Vision RPU (NAL unit type 62) which may precede
     * or follow the VCL slice NAL units in the access unit. */
    const uint8_t *p_rpu_nal = NULL;
    size_t i_rpu_nal = 0;
    hxxx_iterator_ctx_t rpu_it;
    hxxx_iterator_init(&rpu_it, p_block->p_buffer, p_block->i_buffer,
                       hevcctx->hh.i_output_nal_length_size);
    const uint8_t *p_scan;
    size_t i_scan;
    while (hxxx_iterate_next(&rpu_it, &p_scan, &i_scan))
    {
        if (i_scan >= 2 && hevc_getNALLayer(p_scan) == 0 && hevc_getNALType(p_scan) == 62)
        {
            p_rpu_nal = p_scan;
            i_rpu_nal = i_scan;
            break;
        }
    }

    const uint8_t *p_nal; size_t i_nal;
    struct
    {
        const uint8_t *p_nal;
        size_t i_nal;
    } sei_array[VT_MAX_SEI_COUNT];
    size_t i_sei_count = 0;

    while(hxxx_iterate_next(&itctx, &p_nal, &i_nal))
    {
        if (i_nal < 2 || hevc_getNALLayer(p_nal) > 0)
            continue;

        const enum hevc_nal_unit_type_e i_nal_type = hevc_getNALType(p_nal);
        if (i_nal_type <= HEVC_NAL_IRAP_VCL23)
        {
            hevc_slice_segment_header_t *p_sli =
                    hevc_decode_slice_header(p_nal, i_nal, true, GetxPSHEVC, hevcctx);
            if (!p_sli)
                return false;

            p_info->b_keyframe = i_nal_type >= HEVC_NAL_BLA_W_LP;
            enum hevc_slice_type_e slice_type;
            if (hevc_get_slice_type(p_sli, &slice_type))
            {
                p_info->b_keyframe |= (slice_type == HEVC_SLICE_TYPE_I);
            }

            if( p_info->b_keyframe )
            {
                p_info->b_no_rasl_output = hevc_get_IRAPNoRaslOutputFlag( i_nal_type, &hevcctx->poc );
                if ( i_nal_type == HEVC_NAL_CRA ) /* C.3.2 */
                    p_info->b_no_output_of_prior_pics = true;
                else
                    p_info->b_no_output_of_prior_pics =
                        hevc_get_slice_no_output_of_prior_pics_flag( p_sli );
            }

            hevc_sequence_parameter_set_t *p_sps;
            hevc_picture_parameter_set_t *p_pps;
            hevc_video_parameter_set_t *p_vps;
            GetxPSHEVC(hevc_get_slice_pps_id(p_sli), hevcctx, &p_pps, &p_sps, &p_vps);
            if (p_sps)
            {
                struct hevc_sei_callback_s sei;
                sei.p_sps = p_sps;
                sei.p_timing = NULL;

                const int POC = hevc_compute_picture_order_count(p_sps, p_sli,
                                                                 &hevcctx->poc);

                for (size_t i=0; i<i_sei_count; i++)
                    HxxxParseSEI(sei_array[i].p_nal, sei_array[i].i_nal,
                                 2, ParseHEVCSEI, &sei);

                p_info->i_poc = POC;
                p_info->i_foc = POC; /* clearly looks wrong :/ */
                p_info->i_num_ts = hevc_get_num_clock_ts(p_sps, sei.p_timing);
                hevc_get_dpb_values(p_sps, &p_info->i_max_num_reorder,
                                    &p_info->i_max_latency_pics, &p_info->i_max_pics_buffering);
                p_info->b_flush = (POC == 0) ||
                                  (i_nal_type >= HEVC_NAL_IDR_N_LP &&
                                   i_nal_type <= HEVC_NAL_IRAP_VCL23);
                p_info->b_field = (p_info->i_num_ts == 1);
                p_info->b_progressive = hevc_frame_is_progressive(p_sps, sei.p_timing);

                /* Set frame rate for timings in case of missing rate */
                if(hevc_get_frame_rate(p_sps, p_vps, &p_info->field_rate_num,
                                                     &p_info->field_rate_den))
                    p_info->field_rate_num *= 2;

                if (sei.p_timing)
                    hevc_release_sei_pic_timing(sei.p_timing);
            }

            /* RASL Open GOP */
            /* XXX: Work-around a VT bug on recent devices (iPhone X, MacBook
             * Pro 2017). The VT session will report a BadDataErr if you send a
             * RASL frame just after a CRA one. Indeed, RASL frames are
             * corrupted if the decoding start at an IRAP frame (IDR/CRA), VT
             * is likely failing to handle this case. */
            p_info->b_leading = ( i_nal_type == HEVC_NAL_RASL_N || i_nal_type == HEVC_NAL_RASL_R );

            if(p_info->b_leading && p_sys->sync_state == STATE_BITSTREAM_DISCARD_LEADING)
                p_info->b_output_needed = false;
            else
                p_info->b_output_needed = hevc_get_slice_pic_output(p_sli);

            hevc_rbsp_release_slice_header(p_sli);

            struct vt_frame_info_t *p_vt_info = (struct vt_frame_info_t *)p_info;
            for (size_t i = 0; i < i_sei_count; i++)
            {
                if (!p_vt_info->has_hdr10plus)
                {
                    if (ParseHEVCHDR10Plus(p_dec, hevcctx,
                                           sei_array[i].p_nal, sei_array[i].i_nal,
                                           &p_vt_info->hdr10plus))
                    {
                        p_vt_info->has_hdr10plus = true;
                        if (!hevcctx->b_hdr10plus_logged)
                        {
                            msg_Dbg(p_dec, "HDR10+ dynamic metadata detected and parsed");
                            hevcctx->b_hdr10plus_logged = true;
                        }
                    }
                }
            }

            if (p_rpu_nal)
            {
                if (ParseHEVCDoviRPU(p_dec, hevcctx, p_rpu_nal, i_rpu_nal, &p_vt_info->dovi))
                {
                    p_vt_info->has_dovi = true;
                    if (!hevcctx->b_dovi_logged)
                    {
                        msg_Dbg(p_dec, "Dolby Vision RPU metadata detected and parsed");
                        hevcctx->b_dovi_logged = true;
                    }
                }
                else
                {
                    p_vt_info->has_dovi = false;
                }
            }

            return true; /* No need to parse further NAL */
        }
        else if (i_nal_type == HEVC_NAL_PREF_SEI)
        {
            if (i_sei_count < VT_MAX_SEI_COUNT)
            {
                sei_array[i_sei_count].p_nal = p_nal;
                sei_array[i_sei_count++].i_nal = i_nal;
            }
        }
    }

    return false;
}

static CFDictionaryRef CopyDecoderExtradataHEVC(decoder_t *p_dec)
{
    decoder_sys_t *p_sys = p_dec->p_sys;
    struct vt_hevc_context *hevcctx = p_sys->p_codec_context;

    CFDictionaryRef extradata = NULL;
    if (p_dec->fmt_in->i_extra && hevcctx->hh.i_input_nal_length_size)
    {
        /* copy DecoderConfiguration */
        extradata = ExtradataInfoCreate(CFSTR("hvcC"),
                                        p_dec->fmt_in->p_extra,
                                        p_dec->fmt_in->i_extra);
    }
    else if (hxxx_helper_has_config(&hevcctx->hh))
    {
        /* build DecoderConfiguration from gathered */
        block_t *p_hvcC = hxxx_helper_get_extradata_block(&hevcctx->hh);
        if (p_hvcC)
        {
            extradata = ExtradataInfoCreate(CFSTR("hvcC"),
                                            p_hvcC->p_buffer,
                                            p_hvcC->i_buffer);
            block_Release(p_hvcC);
        }
    }
    return extradata;
}

static bool LateStartHEVC(decoder_t *p_dec)
{
    decoder_sys_t *p_sys = p_dec->p_sys;
    struct vt_hevc_context *hevcctx = p_sys->p_codec_context;
    return (p_dec->fmt_in->i_extra == 0 && !hxxx_helper_has_config(&hevcctx->hh));
}

static bool CodecSupportedHEVC(decoder_t *p_dec)
{
    decoder_sys_t *p_sys = p_dec->p_sys;
    struct vt_hevc_context *hevcctx = p_sys->p_codec_context;
    if (p_sys->i_cvpx_format == 0 && !p_sys->b_cvpx_format_forced)
        p_sys->i_cvpx_format = GetBestChromaFromHxxx(&hevcctx->hh);
    return true;
}

static void CodecFlushHEVC(decoder_t *p_dec)
{
    decoder_sys_t *p_sys = p_dec->p_sys;
    struct vt_hevc_context *hevcctx = p_sys->p_codec_context;
    hevc_poc_cxt_init(&hevcctx->poc);
}

#define ConfigureVoutHEVC ConfigureVoutH264
#define ProcessBlockHEVC ProcessBlockH264
#define VideoToolboxNeedsToRestartHEVC VideoToolboxNeedsToRestartH264

static CFDictionaryRef CopyDecoderExtradataMPEG4(decoder_t *p_dec)
{
    if (p_dec->fmt_in->i_extra)
        return ESDSExtradataInfoCreate(p_dec, p_dec->fmt_in->p_extra,
                                              p_dec->fmt_in->i_extra);
    else
        return NULL; /* MPEG4 without esds ? */
}

#if defined(__aarch64__)
static CFDictionaryRef CopyDecoderExtradataAV1(decoder_t *p_dec)
{
    if (p_dec->fmt_in->i_extra)
        return ExtradataInfoCreate(CFSTR("av1C"),
                                   p_dec->fmt_in->p_extra,
                                   p_dec->fmt_in->i_extra);
    else
        return NULL;
}
#endif

/* !Codec Specific */

static void DrainDPBLocked(decoder_t *p_dec, bool flush)
{
    decoder_sys_t *p_sys = p_dec->p_sys;
    struct dpb_s *dpb = &p_sys->dpb;
    while (dpb->i_size > 0)
    {
        picture_t *p_output = DPBOutputFrame(dpb, &p_sys->pts,
                                             dpb->p_entries);
        if(p_output)
        {
            if (flush)
                picture_Release(p_output);
            else
                decoder_QueueVideo(p_dec, p_output);
        }
        RemoveDPBSlot(dpb, &dpb->p_entries);
    }
}

static frame_info_t * CreateReorderInfo(decoder_t *p_dec, const block_t *p_block)
{
    decoder_sys_t *p_sys = p_dec->p_sys;
    struct vt_frame_info_t *p_vt_info = calloc(1, sizeof(*p_vt_info));
    if (!p_vt_info)
        return NULL;
    frame_info_t *p_info = &p_vt_info->info;

    /* failsafe defaults */
    p_info->b_output_needed = true;
    p_info->i_max_num_reorder = 0;
    p_info->i_max_latency_pics = 0;
    p_info->i_latency = 0;

    if (p_sys->pf_fill_reorder_info)
    {
        if (!p_sys->pf_fill_reorder_info(p_dec, p_block, p_info))
        {
            free(p_info);
            return NULL;
        }
    }
    else
    {
        p_info->i_num_ts = 2;
        p_info->b_progressive = true;
        p_info->b_field = false;
        p_info->b_keyframe = true;
    }

    p_info->dts = p_block->i_dts;
    p_info->pts = p_block->i_pts;
    p_info->i_length = p_block->i_length;

    if(p_dec->fmt_in->video.i_frame_rate && p_dec->fmt_in->video.i_frame_rate_base) /* demux forced rate */
    {
        p_info->field_rate_num = p_dec->fmt_in->video.i_frame_rate * 2;
        p_info->field_rate_den = p_dec->fmt_in->video.i_frame_rate_base;
    }
    else if(!p_info->field_rate_num || !p_info->field_rate_den) /* full fallback */
    {
        p_info->field_rate_num = DEFAULT_FRAME_RATE_NUM * 2;
        p_info->field_rate_den = DEFAULT_FRAME_RATE_DEN;
    }

    /* required for still pictures/menus */
    p_info->b_eos = (p_block->i_flags & BLOCK_FLAG_END_OF_SEQUENCE);

    return p_info;
}

static void OnDecodedFrame(decoder_t *p_dec, frame_info_t *p_info)
{
    decoder_sys_t *p_sys = p_dec->p_sys;

    if(!p_sys->dpb.b_invalid_pic_reorder_max &&
       p_info->i_max_pics_buffering != p_sys->dpb.i_max_pics)
    {
        p_sys->dpb.i_max_pics = p_info->i_max_pics_buffering;
        pic_pacer_UpdateMaxBuffering(p_sys->pic_pacer, p_sys->dpb.i_max_pics);
    }

    /* First check if DPB sizing was correct before removing one frame */
    if (!p_sys->dpb.b_strict_reorder && !p_info->b_flush &&
        p_sys->dpb.i_size == p_sys->dpb.i_max_pics &&
        p_sys->dpb.i_size && p_sys->dpb.i_max_pics < DPB_MAX_PICS)
    {
        if (p_sys->dpb.b_poc_based_reorder && p_sys->dpb.p_entries->i_foc > p_info->i_foc)
        {
            p_sys->dpb.b_invalid_pic_reorder_max = true;
            p_sys->dpb.i_max_pics++;
            pic_pacer_UpdateMaxBuffering(p_sys->pic_pacer, p_sys->dpb.i_max_pics);
            msg_Dbg(p_dec, "Raising max DPB to %"PRIu8, p_sys->dpb.i_max_pics);
        }
        else if (!p_sys->dpb.b_poc_based_reorder &&
                 p_info->pts > VLC_TICK_INVALID &&
                 p_sys->dpb.p_entries->pts > p_info->pts)
        {
            p_sys->dpb.b_invalid_pic_reorder_max = true;
            p_sys->dpb.i_max_pics++;
            pic_pacer_UpdateMaxBuffering(p_sys->pic_pacer, p_sys->dpb.i_max_pics);
            msg_Dbg(p_dec, "Raising max DPB to %"PRIu8, p_sys->dpb.i_max_pics);
        }
    }

    for(picture_t *p_out = DPBOutputAndRemoval(&p_sys->dpb, &p_sys->pts, p_info);
        p_out != NULL;)
    {
        picture_t *p_pic = p_out;
        p_out = p_out->p_next;
        p_pic->p_next = NULL;
        decoder_QueueVideo(p_dec, p_pic);
    }

    InsertIntoDPB(&p_sys->dpb, p_info);
}

static CMVideoCodecType CodecPrecheck(decoder_t *p_dec)
{
    /* check for the codec we can and want to decode */
    switch (p_dec->fmt_in->i_codec) {
        case VLC_CODEC_H264:
            return kCMVideoCodecType_H264;

        case VLC_CODEC_HEVC:
            if (!deviceSupportsHEVC())
            {
                msg_Warn(p_dec, "device doesn't support HEVC");
                return 0;
            }
            return kCMVideoCodecType_HEVC;

#if defined(__aarch64__)
        case VLC_CODEC_AV1:
            if (!p_dec->fmt_in->i_extra)
            {
                msg_Dbg(p_dec, "Demuxer provided no extradata for AV1 (av1C required)");
                return 0;
            }
            if (!deviceSupportsAV1())
            {
                msg_Dbg(p_dec, "Device does not support hardware AV1 decoding");
                return 0;
            }
            msg_Dbg(p_dec, "Using hardware AV1 decoder");
            return kCMVideoCodecType_AV1;
#endif

        case VLC_CODEC_MP4V:
        {
            msg_Dbg(p_dec, "Will decode MP4V with original FourCC '%4.4s'", (char *)&p_dec->fmt_in->i_original_fourcc);
            return kCMVideoCodecType_MPEG4Video;
        }
#if !TARGET_OS_IPHONE
        case VLC_CODEC_H263:
            return kCMVideoCodecType_H263;

            /* there are no DV or ProRes decoders on iOS, so bailout early */
        case VLC_CODEC_PRORES:
            /* the VT decoder can't differentiate between the ProRes flavors, so we do it */
            switch (p_dec->fmt_in->i_original_fourcc) {
                case VLC_FOURCC( 'a','p','4','c' ):
                case VLC_FOURCC( 'a','p','4','h' ):
                case VLC_FOURCC( 'a','p','4','x' ):
                    return kCMVideoCodecType_AppleProRes4444;

                case VLC_FOURCC( 'a','p','c','h' ):
                    return kCMVideoCodecType_AppleProRes422HQ;

                case VLC_FOURCC( 'a','p','c','s' ):
                    return kCMVideoCodecType_AppleProRes422LT;

                case VLC_FOURCC( 'a','p','c','o' ):
                    return kCMVideoCodecType_AppleProRes422Proxy;

                default:
                    return kCMVideoCodecType_AppleProRes422;
            }

        case VLC_CODEC_DV:
            /* the VT decoder can't differentiate between PAL and NTSC, so we need to do it */
            switch (p_dec->fmt_in->i_original_fourcc) {
                case VLC_FOURCC( 'd', 'v', 'c', ' '):
                case VLC_FOURCC( 'd', 'v', ' ', ' '):
                    msg_Dbg(p_dec, "Decoding DV NTSC");
                    return kCMVideoCodecType_DVCNTSC;

                case VLC_FOURCC( 'd', 'v', 's', 'd'):
                case VLC_FOURCC( 'd', 'v', 'c', 'p'):
                case VLC_FOURCC( 'D', 'V', 'S', 'D'):
                    msg_Dbg(p_dec, "Decoding DV PAL");
                    return kCMVideoCodecType_DVCPAL;
                default:
                    return 0;
            }
#endif
            /* mpgv / mp2v needs fixing, so disable it for now */
#if 0
        case VLC_CODEC_MPGV:
            return kCMVideoCodecType_MPEG1Video;
        case VLC_CODEC_MP2V:
            return kCMVideoCodecType_MPEG2Video;
#endif

        default:
#ifndef NDEBUG
            msg_Err(p_dec, "'%4.4s' is not supported", (char *)&p_dec->fmt_in->i_codec);
#endif
            return -1;
    }

    vlc_assert_unreachable();
}

static void
SetDecoderColorProperties(CFMutableDictionaryRef decoderConfiguration,
                          const video_format_t *video_fmt)
{
    /**
     VideoToolbox decoder doesn't attach all color properties to image buffers.
     Current display modules handle tonemap without them.
     Attaching additional color properties to image buffers is mandatory for
     native image buffer display on macOS in order to have proper colors
     tonemap when AVFoundation APIs are used to render them and prevent
     flickering while using multiple displays with different colorsync profiles.
    */

    CFStringRef color_matrix =
        cvpx_map_YCbCrMatrix_from_vcs(video_fmt->space);
    if (color_matrix) {
        CFDictionarySetValue(
            decoderConfiguration,
            kCVImageBufferYCbCrMatrixKey,
            color_matrix);
    }

    CFStringRef color_primaries =
        cvpx_map_ColorPrimaries_from_vcp(video_fmt->primaries);
    if (color_primaries) {
        CFDictionarySetValue(
            decoderConfiguration,
            kCVImageBufferColorPrimariesKey,
            color_primaries
        );
    }

    CFStringRef color_transfer_func =
        cvpx_map_TransferFunction_from_vtf(video_fmt->transfer);
    if (color_transfer_func) {
        CFDictionarySetValue(
            decoderConfiguration,
            kCVImageBufferTransferFunctionKey,
            color_transfer_func
        );
    }

    Float32 gamma = 0;
    if (video_fmt->transfer == TRANSFER_FUNC_SRGB)
        gamma = 2.2;

    if (gamma != 0) {
        cfdict_set_int32(
            decoderConfiguration,
            kCVImageBufferGammaLevelKey,
            gamma
        );
    }

#if (TARGET_OS_OSX && defined(__MAC_10_13)) || (TARGET_OS_IPHONE && defined(__IPHONE_11_0))
    if (__builtin_available(macOS 10.13, iOS 11, tvOS 11, watchOS 4, *))
    {
        CFDataRef mdcv = cvpx_create_mastering_display_color_volume_data(video_fmt);
        if (mdcv)
        {
            CFDictionarySetValue(decoderConfiguration,
                                 kCVImageBufferMasteringDisplayColorVolumeKey,
                                 mdcv);
            CFRelease(mdcv);
        }

        CFDataRef clli = cvpx_create_content_light_level_data(video_fmt);
        if (clli)
        {
            CFDictionarySetValue(decoderConfiguration,
                                 kCVImageBufferContentLightLevelInfoKey,
                                 clli);
            CFRelease(clli);
        }
    }
#endif
}

static CFMutableDictionaryRef CreateSessionDescriptionFormat(decoder_t *p_dec,
                                                             unsigned i_sar_num,
                                                             unsigned i_sar_den)
{
    decoder_sys_t *p_sys = p_dec->p_sys;

    CFMutableDictionaryRef decoderConfiguration = cfdict_create(0);
    if (decoderConfiguration == NULL)
        return NULL;

    CFDictionaryRef extradata = p_sys->pf_copy_extradata
                                ? p_sys->pf_copy_extradata(p_dec) : NULL;
    if (extradata)
    {
        /* then decoder will also fail if required, no need to handle it */
        CFDictionarySetValue(decoderConfiguration,
                             kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms,
                             extradata);
        CFRelease(extradata);
    }

    CFDictionarySetValue(decoderConfiguration,
                         kCVImageBufferChromaLocationBottomFieldKey,
                         kCVImageBufferChromaLocation_Left);
    CFDictionarySetValue(decoderConfiguration,
                         kCVImageBufferChromaLocationTopFieldKey,
                         kCVImageBufferChromaLocation_Left);

    /* pixel aspect ratio */
    if (i_sar_num && i_sar_den)
    {
        CFMutableDictionaryRef pixelaspectratio = cfdict_create(2);
        if (pixelaspectratio == NULL)
        {
            CFRelease(decoderConfiguration);
            return NULL;
        }

        cfdict_set_int32(pixelaspectratio,
                         kCVImageBufferPixelAspectRatioHorizontalSpacingKey,
                         i_sar_num);
        cfdict_set_int32(pixelaspectratio,
                         kCVImageBufferPixelAspectRatioVerticalSpacingKey,
                         i_sar_den);
        CFDictionarySetValue(decoderConfiguration,
                             kCVImageBufferPixelAspectRatioKey,
                             pixelaspectratio);
        CFRelease(pixelaspectratio);
    }

    video_format_AdjustColorSpace(&p_dec->fmt_out.video);

    SetDecoderColorProperties(decoderConfiguration, &p_dec->fmt_out.video);

#if TARGET_OS_OSX
    /* enable HW accelerated playback, since this is optional on OS X
     * note that the backend may still fallback on software mode if no
     * suitable hardware is available */
    CFDictionarySetValue(decoderConfiguration,
                         kVTVideoDecoderSpecification_EnableHardwareAcceleratedVideoDecoder,
                         kCFBooleanTrue);

    /* on OS X, we can force VT to fail if no suitable HW decoder is available,
     * preventing the aforementioned SW fallback */
    if (var_InheritBool(p_dec, "videotoolbox-hw-decoder-only"))
        CFDictionarySetValue(decoderConfiguration,
                             kVTVideoDecoderSpecification_RequireHardwareAcceleratedVideoDecoder,
                             kCFBooleanTrue);
#endif

    return decoderConfiguration;
}

static int StartVideoToolbox(decoder_t *p_dec)
{
    decoder_sys_t *p_sys = p_dec->p_sys;

    /* Initialized to NULL for error handling */
    CFMutableDictionaryRef destinationPixelBufferAttributes = NULL;
    CFMutableDictionaryRef decoderConfiguration = NULL;

    /* Late starts */
    if (p_sys->pf_late_start && p_sys->pf_late_start(p_dec))
    {
        assert(p_sys->session == NULL);
        return VLC_SUCCESS;
    }

    /* Fills fmt_out (from extradata if any) */
    if (ConfigureVout(p_dec) != VLC_SUCCESS)
        return VLC_EGENERIC;

    /* destination pixel buffer attributes */
    destinationPixelBufferAttributes = cfdict_create(0);
    if (destinationPixelBufferAttributes == NULL)
        return VLC_EGENERIC;

    decoderConfiguration =
        CreateSessionDescriptionFormat(p_dec,
                                       p_dec->fmt_out.video.i_sar_num,
                                       p_dec->fmt_out.video.i_sar_den);
    if (decoderConfiguration == NULL)
        goto error;

    /* create video format description */
    OSStatus status = CMVideoFormatDescriptionCreate(
                                            kCFAllocatorDefault,
                                            p_sys->codec,
                                            p_dec->fmt_out.video.i_visible_width,
                                            p_dec->fmt_out.video.i_visible_height,
                                            decoderConfiguration,
                                            &p_sys->videoFormatDescription);
    if (status)
    {
        msg_Err(p_dec, "video format description creation failed (%i)", (int)status);
        goto error;
    }

    CFDictionarySetValue(destinationPixelBufferAttributes,
                         kCVPixelBufferMetalCompatibilityKey,
                         kCFBooleanTrue);
#if TARGET_OS_OSX
   CFDictionarySetValue(destinationPixelBufferAttributes,
                        kCVPixelBufferIOSurfaceOpenGLTextureCompatibilityKey,
                        kCFBooleanTrue);
#elif !defined(TARGET_OS_VISION) || !TARGET_OS_VISION
    CFDictionarySetValue(destinationPixelBufferAttributes,
                         kCVPixelBufferOpenGLESCompatibilityKey,
                         kCFBooleanTrue);
#endif

    cfdict_set_int32(destinationPixelBufferAttributes,
                     kCVPixelBufferWidthKey, p_dec->fmt_out.video.i_width);
    cfdict_set_int32(destinationPixelBufferAttributes,
                     kCVPixelBufferHeightKey, p_dec->fmt_out.video.i_height);

    /* If input is 10-bit HDR and chroma format was not explicitly forced, prefer 10-bit P010 output */
    if (p_sys->i_cvpx_format == 0 &&
        (p_dec->fmt_in->video.transfer == TRANSFER_FUNC_SMPTE_ST2084 ||
         p_dec->fmt_in->video.transfer == TRANSFER_FUNC_HLG ||
         p_dec->fmt_in->video.primaries == COLOR_PRIMARIES_BT2020 ||
         p_dec->fmt_in->video.i_chroma == VLC_CODEC_I420_10L ||
         p_dec->fmt_in->video.i_chroma == VLC_CODEC_I420_10B ||
         p_dec->fmt_in->video.i_chroma == VLC_CODEC_I420_12L ||
         p_dec->fmt_in->video.i_chroma == VLC_CODEC_I420_12B ||
         p_dec->fmt_in->video.i_chroma == VLC_CODEC_I420_16L ||
         p_dec->fmt_in->video.i_chroma == VLC_CODEC_I420_16B ||
         p_dec->fmt_in->video.i_chroma == VLC_CODEC_P010 ||
         p_dec->fmt_in->video.i_chroma == VLC_CODEC_P012 ||
         p_dec->fmt_in->video.i_chroma == VLC_CODEC_P016 ||
         p_dec->fmt_in->video.i_chroma == VLC_CODEC_P216 ||
         p_dec->fmt_in->video.i_chroma == VLC_CODEC_CVPX_P010 ||
         p_dec->fmt_in->video.i_chroma == VLC_CODEC_CVPX_P216 ||
         (p_dec->fmt_in->i_codec == VLC_CODEC_HEVC && p_dec->fmt_in->i_profile == 2)))
    {
#if TARGET_OS_OSX
        if (p_dec->fmt_in->video.i_chroma == VLC_CODEC_P216 ||
            p_dec->fmt_in->video.i_chroma == VLC_CODEC_CVPX_P216)
            p_sys->i_cvpx_format = kCVPixelFormatType_422YpCbCr16BiPlanarVideoRange;
        else
#endif
            p_sys->i_cvpx_format = kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange;
    }

    if (p_sys->i_cvpx_format != 0)
    {
        OSType chroma = htonl(p_sys->i_cvpx_format);
        if (p_sys->b_cvpx_format_forced)
            msg_Warn(p_dec, "forcing output chroma (kCVPixelFormatType): %4.4s",
                (const char *) &chroma);
        else
            msg_Dbg(p_dec, "chosen output chroma (kCVPixelFormatType): %4.4s",
                (const char *) &chroma);
        cfdict_set_int32(destinationPixelBufferAttributes,
                         kCVPixelBufferPixelFormatTypeKey,
                         p_sys->i_cvpx_format);
    }

    cfdict_set_int32(destinationPixelBufferAttributes,
                     kCVPixelBufferBytesPerRowAlignmentKey, 16);

    /* setup decoder callback record */
    VTDecompressionOutputCallbackRecord decoderCallbackRecord;
    decoderCallbackRecord.decompressionOutputCallback = DecoderCallback;
    decoderCallbackRecord.decompressionOutputRefCon = p_dec;

    /* create decompression session */
    status = VTDecompressionSessionCreate(kCFAllocatorDefault,
                                          p_sys->videoFormatDescription,
                                          decoderConfiguration,
                                          destinationPixelBufferAttributes,
                                          &decoderCallbackRecord, &p_sys->session);
    CFRelease(decoderConfiguration);
    CFRelease(destinationPixelBufferAttributes);

    if (HandleVTStatus(p_dec, status, NULL) != VLC_SUCCESS)
        return VLC_EGENERIC;

    return VLC_SUCCESS;

error:
    if (decoderConfiguration != NULL)
        CFRelease(decoderConfiguration);

    if (destinationPixelBufferAttributes != NULL)
        CFRelease(destinationPixelBufferAttributes);

    return VLC_EGENERIC;
}

static void StopVideoToolbox(decoder_t *p_dec)
{
    decoder_sys_t *p_sys = p_dec->p_sys;

    if (p_sys->session != NULL)
    {
        Drain(p_dec, true);

        VTDecompressionSessionInvalidate(p_sys->session);
        CFRelease(p_sys->session);
        p_sys->session = NULL;
        p_sys->b_format_propagated = false;
        p_dec->fmt_out.i_codec = 0;
    }

    if (p_sys->videoFormatDescription != NULL) {
        CFRelease(p_sys->videoFormatDescription);
        p_sys->videoFormatDescription = NULL;
    }
    p_sys->sync_state = p_sys->start_sync_state;
    p_sys->decoder_state = STATE_DECODER_WAITING_RAP;
}

#pragma mark - module open and close

static void pic_pacer_Destroy(void *priv)
{
    pic_pacer_Clean((struct pic_pacer *)priv);
}

static int
CreateVideoContext(decoder_t *p_dec)
{
    decoder_sys_t *p_sys = p_dec->p_sys;

    vlc_decoder_device *dec_dev = decoder_GetDecoderDevice(p_dec);
    if (!dec_dev || dec_dev->type != VLC_DECODER_DEVICE_VIDEOTOOLBOX)
    {
        msg_Warn(p_dec, "Could not find an VIDEOTOOLBOX decoder device");
        return VLC_EGENERIC;
    }

    static const struct vlc_video_context_operations ops =
    {
        pic_pacer_Destroy,
    };
    p_sys->vctx =
        vlc_video_context_CreateCVPX(dec_dev,
                                     CVPX_VIDEO_CONTEXT_VIDEOTOOLBOX,
                                     sizeof(struct pic_pacer), &ops);
    vlc_decoder_device_Release(dec_dev);

    if (!p_sys->vctx)
        return VLC_ENOMEM;

    /* Since pictures can outlive the decoder, the private video context is a
     * good place to place the pic_pacer that need to be valid during the
     * lifetime of all pictures */
    p_sys->pic_pacer =
        vlc_video_context_GetCVPXPrivate(p_sys->vctx,
                                         CVPX_VIDEO_CONTEXT_VIDEOTOOLBOX);
    assert(p_sys->pic_pacer);

    pic_pacer_Init(p_sys->pic_pacer);

    return VLC_SUCCESS;
}

static void CloseDecoder(vlc_object_t *p_this)
{
    decoder_t *p_dec = (decoder_t *)p_this;
    decoder_sys_t *p_sys = p_dec->p_sys;

    StopVideoToolbox(p_dec);

    if (p_sys->pf_codec_clean)
        p_sys->pf_codec_clean(p_sys->p_codec_context);

    vlc_video_context_Release(p_sys->vctx);

    free(p_sys);
}

static int OpenDecoder(vlc_object_t *p_this)
{
    int i_ret;
    decoder_t *p_dec = (decoder_t *)p_this;

    /* Fail if this module already failed to decode this ES */
    if (var_Type(p_dec, "videotoolbox-failed") != 0)
        return VLC_EGENERIC;

    /* check quickly if we can digest the offered data */
    CMVideoCodecType codec;

    codec = CodecPrecheck(p_dec);
    if (codec == 0)
        return VLC_EGENERIC;

    /* now that we see a chance to decode anything, allocate the
     * internals and start the decoding session */
    decoder_sys_t *p_sys;
    p_sys = calloc(1, sizeof(*p_sys));
    if (!p_sys)
        return VLC_ENOMEM;
    p_dec->p_sys = p_sys;
    p_sys->session = NULL;
    p_sys->codec = codec;
    p_sys->videoFormatDescription = NULL;
    p_sys->dpb.i_max_pics = 4;
    p_sys->dpb.i_fields_per_buffer = 1;
    p_sys->dpb.pf_release = picture_Release;
    p_sys->vtsession_status = VTSESSION_STATUS_OK;
    p_sys->b_cvpx_format_forced = false;
    /* will be fixed later */
    date_Init(&p_sys->pts, p_dec->fmt_in->video.i_frame_rate,
                           p_dec->fmt_in->video.i_frame_rate_base);

    char *cvpx_chroma = var_InheritString(p_dec, "videotoolbox-cvpx-chroma");
    if (cvpx_chroma != NULL)
    {
        if (strlen(cvpx_chroma) != 4)
        {
            msg_Err(p_dec, "invalid videotoolbox-cvpx-chroma option");
            free(cvpx_chroma);
            free(p_sys);
            return VLC_EGENERIC;
        }
        memcpy(&p_sys->i_cvpx_format, cvpx_chroma, 4);
        p_sys->i_cvpx_format = ntohl(p_sys->i_cvpx_format);
        p_sys->b_cvpx_format_forced = true;
        free(cvpx_chroma);
    }

    p_dec->fmt_out.video = p_dec->fmt_in->video;
    p_dec->fmt_out.video.p_palette = NULL;

    if (!p_dec->fmt_out.video.i_sar_num || !p_dec->fmt_out.video.i_sar_den)
    {
        p_dec->fmt_out.video.i_sar_num = 1;
        p_dec->fmt_out.video.i_sar_den = 1;
    }

    i_ret = CreateVideoContext(p_dec);
    if (i_ret != VLC_SUCCESS)
    {
        free(p_sys);
        return i_ret;
    }

    vlc_mutex_init(&p_sys->lock);

    p_dec->pf_decode = DecodeBlock;
    p_dec->pf_flush  = RequestFlush;

    switch(codec)
    {
        case kCMVideoCodecType_H264:
            p_sys->pf_codec_init = InitH264;
            p_sys->pf_codec_clean = CleanH264;
            p_sys->pf_codec_supported = CodecSupportedH264;
            p_sys->pf_codec_flush = CodecFlushH264;
            p_sys->pf_late_start = LateStartH264;
            p_sys->pf_process_block = ProcessBlockH264;
            p_sys->pf_need_restart = VideoToolboxNeedsToRestartH264;
            p_sys->pf_configure_vout = ConfigureVoutH264;
            p_sys->pf_copy_extradata = CopyDecoderExtradataH264;
            p_sys->pf_fill_reorder_info = FillReorderInfoH264;
            p_sys->dpb.b_strict_reorder = false;
            p_sys->dpb.b_poc_based_reorder = true;
            p_sys->start_sync_state = STATE_BITSTREAM_WAITING_RAP;
            break;

        case kCMVideoCodecType_HEVC:
            p_sys->pf_codec_init = InitHEVC;
            p_sys->pf_codec_clean = CleanHEVC;
            p_sys->pf_codec_supported = CodecSupportedHEVC;
            p_sys->pf_codec_flush = CodecFlushHEVC;
            p_sys->pf_late_start = LateStartHEVC;
            p_sys->pf_process_block = ProcessBlockHEVC;
            p_sys->pf_need_restart = VideoToolboxNeedsToRestartHEVC;
            p_sys->pf_configure_vout = ConfigureVoutHEVC;
            p_sys->pf_copy_extradata = CopyDecoderExtradataHEVC;
            p_sys->pf_fill_reorder_info = FillReorderInfoHEVC;
            p_sys->dpb.b_strict_reorder = true;
            p_sys->dpb.b_poc_based_reorder = true;
            p_sys->start_sync_state = STATE_BITSTREAM_WAITING_RAP;
            break;

        case kCMVideoCodecType_MPEG4Video:
            p_sys->pf_copy_extradata = CopyDecoderExtradataMPEG4;
            break;

#if defined(__aarch64__)
        case kCMVideoCodecType_AV1:
            p_sys->pf_copy_extradata = CopyDecoderExtradataAV1;
            break;
#endif

        default:
            p_sys->pf_copy_extradata = NULL;
            break;
    }

    p_sys->sync_state = p_sys->start_sync_state;

    if (p_sys->pf_codec_init && !p_sys->pf_codec_init(p_dec))
    {
        p_sys->pf_codec_clean = NULL; /* avoid double free */
        CloseDecoder(p_this);
        return VLC_EGENERIC;
    }
    if (p_sys->pf_codec_supported && !p_sys->pf_codec_supported(p_dec))
    {
        CloseDecoder(p_this);
        return VLC_EGENERIC;
    }

    i_ret = StartVideoToolbox(p_dec);
    if (i_ret == VLC_SUCCESS) {
        date_Set(&p_sys->pts, VLC_TICK_INVALID);
        msg_Info(p_dec, "Using Video Toolbox to decode '%4.4s'",
                        (char *)&p_dec->fmt_in->i_codec);
    } else {
        CloseDecoder(p_this);
    }

    return i_ret;
}

#pragma mark - helpers

static Boolean deviceSupportsHEVC()
{
    if (__builtin_available(macOS 10.13, iOS 11.0, tvOS 11.0, *))
        return VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC);
    else
        return false;
}

#if defined(__aarch64__)
static Boolean deviceSupportsAV1()
{
    if (__builtin_available(macOS 14.0, iOS 17.0, tvOS 17.0, *))
        return VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1);
    else
        return false;
}
#endif

static bool deviceSupports42010bitRendering()
{
#if TARGET_OS_IPHONE
    /* iPhone/iPad/aTV needs metal device to render 420 10bit */
    return cvpx_system_has_metal_device();
#else
    /* macOS can render 420 10bit with OpenGL and Metal */
    return true;
#endif
}

static Boolean deviceSupportsAdvancedProfiles()
{
#if TARGET_OS_IPHONE
    size_t size;
    cpu_type_t type;

    size = sizeof(type);
    sysctlbyname("hw.cputype", &type, &size, NULL, 0);

    /* Support for H264 profile HIGH 10 was introduced with the first 64bit Apple ARM SoC, the A7 */
    if (type == CPU_TYPE_ARM64)
        return true;

#endif
    return false;
}

static Boolean deviceSupportsAdvancedLevels()
{
#if TARGET_OS_IPHONE
    #ifdef __LP64__
        size_t size;
        int32_t cpufamily;
        size = sizeof(cpufamily);
        sysctlbyname("hw.cpufamily", &cpufamily, &size, NULL, 0);

        /* Proper 4K decoding requires a Twister SoC
         * Everything below will kill the decoder daemon */
        if (cpufamily == CPUFAMILY_ARM_CYCLONE || cpufamily == CPUFAMILY_ARM_TYPHOON) {
            return false;
        }

        return true;
    #else
        /* we need a 64bit SoC for advanced levels */
        return false;
    #endif
#else
    return true;
#endif
}

static inline void bo_add_mp4_tag_descr(bo_t *p_bo, uint8_t tag, uint32_t size)
{
    bo_add_8(p_bo, tag);
    for (int i = 3; i > 0; i--)
        bo_add_8(p_bo, (size >> (7 * i)) | 0x80);
    bo_add_8(p_bo, size & 0x7F);
}

static CFDictionaryRef ESDSExtradataInfoCreate(decoder_t *p_dec,
                                               uint8_t *p_buf,
                                               uint32_t i_buf_size)
{
    VLC_UNUSED(p_dec);
    int full_size = 3 + 5 +13 + 5 + i_buf_size + 3;
    int config_size = 13 + 5 + i_buf_size;

    bo_t bo;
    bool status = bo_init(&bo, 1024);
    if (status != true)
        return NULL;

    bo_add_8(&bo, 0);       // Version
    bo_add_24be(&bo, 0);    // Flags

    // elementary stream description tag
    bo_add_mp4_tag_descr(&bo, 0x03, full_size);
    bo_add_16be(&bo, 0);    // esid
    bo_add_8(&bo, 0);       // stream priority (0-3)

    // decoder configuration description tag
    bo_add_mp4_tag_descr(&bo, 0x04, config_size);
    bo_add_8(&bo, 32);      // object type identification (32 == MPEG4)
    bo_add_8(&bo, 0x11);    // stream type
    bo_add_24be(&bo, 0);    // buffer size
    bo_add_32be(&bo, 0);    // max bitrate
    bo_add_32be(&bo, 0);    // avg bitrate

    // decoder specific description tag
    bo_add_mp4_tag_descr(&bo, 0x05, i_buf_size);
    bo_add_mem(&bo, i_buf_size, p_buf);

    // sync layer configuration description tag
    bo_add_8(&bo, 0x06);    // tag
    bo_add_8(&bo, 0x01);    // length
    bo_add_8(&bo, 0x02);    // no SL

    CFDictionaryRef extradataInfo =
        ExtradataInfoCreate(CFSTR("esds"), bo.b->p_buffer, bo.b->i_buffer);
    bo_deinit(&bo);
    return extradataInfo;
}

static int ConfigureVout(decoder_t *p_dec)
{
    decoder_sys_t *p_sys = p_dec->p_sys;

    /* return our proper VLC internal state */
    p_dec->fmt_out.i_codec = 0;

    if (p_sys->pf_configure_vout && !p_sys->pf_configure_vout(p_dec))
        return VLC_EGENERIC;

    if (!p_dec->fmt_out.video.i_visible_width || !p_dec->fmt_out.video.i_visible_height)
    {
        p_dec->fmt_out.video.i_visible_width = p_dec->fmt_out.video.i_width;
        p_dec->fmt_out.video.i_visible_height = p_dec->fmt_out.video.i_height;
    }

    p_dec->fmt_out.video.i_width = vlc_align(p_dec->fmt_out.video.i_width, VT_ALIGNMENT);
    p_dec->fmt_out.video.i_height = vlc_align(p_dec->fmt_out.video.i_height, VT_ALIGNMENT);

    return VLC_SUCCESS;
}

static CFDictionaryRef ExtradataInfoCreate(CFStringRef name,
                                                  void *p_data, size_t i_data)
{
    if (p_data == NULL)
        return NULL;

    CFDataRef extradata = CFDataCreate(kCFAllocatorDefault, p_data, i_data);
    if (extradata == NULL)
        return NULL;

    CFDictionaryRef extradataInfo = CFDictionaryCreate(kCFAllocatorDefault,
        &(CFTypeRef){ name },
        &(CFTypeRef){ extradata },
        1,
        &kCFTypeDictionaryKeyCallBacks,
        &kCFTypeDictionaryValueCallBacks);

    CFRelease(extradata);
    return extradataInfo;
}

static CMSampleBufferRef VTSampleBufferCreate(decoder_t *p_dec,
                                              CMFormatDescriptionRef fmt_desc,
                                              block_t *p_block)
{
    decoder_sys_t *p_sys = p_dec->p_sys;
    OSStatus status;
    CMBlockBufferRef  block_buf = NULL;
    CMSampleBufferRef sample_buf = NULL;
    CMTime pts;
    if (!p_sys->dpb.b_poc_based_reorder && p_block->i_pts == VLC_TICK_INVALID)
        pts = CMTimeMake(p_block->i_dts, CLOCK_FREQ);
    else
        pts = CMTimeMake(p_block->i_pts, CLOCK_FREQ);

    CMSampleTimingInfo timeInfoArray[1] = { {
        .duration = CMTimeMake(p_block->i_length, 1),
        .presentationTimeStamp = pts,
        .decodeTimeStamp = CMTimeMake(p_block->i_dts, CLOCK_FREQ),
    } };

    status = CMBlockBufferCreateWithMemoryBlock(kCFAllocatorDefault,// structureAllocator
                                                p_block->p_buffer,  // memoryBlock
                                                p_block->i_buffer,  // blockLength
                                                kCFAllocatorNull,   // blockAllocator
                                                NULL,               // customBlockSource
                                                0,                  // offsetToData
                                                p_block->i_buffer,  // dataLength
                                                false,              // flags
                                                &block_buf);

    if (!status) {
        status = CMSampleBufferCreate(kCFAllocatorDefault,  // allocator
                                      block_buf,            // dataBuffer
                                      true,                 // dataReady
                                      0,                    // makeDataReadyCallback
                                      0,                    // makeDataReadyRefcon
                                      fmt_desc,             // formatDescription
                                      1,                    // numSamples
                                      1,                    // numSampleTimingEntries
                                      timeInfoArray,        // sampleTimingArray
                                      0,                    // numSampleSizeEntries
                                      NULL,                 // sampleSizeArray
                                      &sample_buf);
        if (status != noErr)
            msg_Warn(p_dec, "sample buffer creation failure %i", (int)status);
    } else
        msg_Warn(p_dec, "cm block buffer creation failure %i", (int)status);

    if (block_buf != NULL)
        CFRelease(block_buf);
    block_buf = NULL;

    return sample_buf;
}

// Error enum values introduced in macOS 12 / iOS 15 SDKs
#if ((TARGET_OS_OSX && __MAC_OS_X_VERSION_MAX_ALLOWED < 120000) || \
     (TARGET_OS_TV && __TV_OS_VERSION_MAX_ALLOWED < 150000) || \
     (TARGET_OS_IOS && __IPHONE_OS_VERSION_MAX_ALLOWED < 150000))
enum {
    kVTVideoDecoderReferenceMissingErr      = -17694
};
#endif

static int HandleVTStatus(decoder_t *p_dec, OSStatus status,
                          enum vtsession_status * p_vtsession_status)
{
#define VTERRCASE(x) \
    case x: msg_Warn(p_dec, "vt session error: '" #x "'"); break;

#define VTERRCASE_LEGACY(code, name) \
    case code: msg_Warn(p_dec, "vt session error: '" name "'"); break;

    switch (status)
    {
        case noErr:
            return VLC_SUCCESS;

        VTERRCASE(kVTPropertyNotSupportedErr)
        VTERRCASE(kVTPropertyReadOnlyErr)
        VTERRCASE(kVTParameterErr)
        VTERRCASE(kVTInvalidSessionErr)
        VTERRCASE(kVTAllocationFailedErr)
        VTERRCASE(kVTPixelTransferNotSupportedErr)
        VTERRCASE(kVTCouldNotFindVideoDecoderErr)
        VTERRCASE(kVTCouldNotCreateInstanceErr)
        VTERRCASE(kVTCouldNotFindVideoEncoderErr)
        VTERRCASE(kVTVideoDecoderBadDataErr)
        VTERRCASE(kVTVideoDecoderUnsupportedDataFormatErr)
        VTERRCASE(kVTVideoDecoderMalfunctionErr)
        VTERRCASE(kVTVideoEncoderMalfunctionErr)
        VTERRCASE(kVTVideoDecoderNotAvailableNowErr)
        VTERRCASE(kVTImageRotationNotSupportedErr)
        VTERRCASE(kVTVideoEncoderNotAvailableNowErr)
        VTERRCASE(kVTFormatDescriptionChangeNotSupportedErr)
        VTERRCASE(kVTInsufficientSourceColorDataErr)
        VTERRCASE(kVTCouldNotCreateColorCorrectionDataErr)
        VTERRCASE(kVTColorSyncTransformConvertFailedErr)
        VTERRCASE(kVTVideoDecoderAuthorizationErr)
        VTERRCASE(kVTVideoEncoderAuthorizationErr)
        VTERRCASE(kVTColorCorrectionPixelTransferFailedErr)
        VTERRCASE(kVTMultiPassStorageIdentifierMismatchErr)
        VTERRCASE(kVTMultiPassStorageInvalidErr)
        VTERRCASE(kVTFrameSiloInvalidTimeStampErr)
        VTERRCASE(kVTFrameSiloInvalidTimeRangeErr)
        VTERRCASE(kVTCouldNotFindTemporalFilterErr)
        VTERRCASE(kVTPixelTransferNotPermittedErr)
        VTERRCASE(kVTColorCorrectionImageRotationFailedErr)
        VTERRCASE(kVTVideoDecoderReferenceMissingErr)

        /* Legacy error codes defined in the old Carbon MacErrors.h */
        VTERRCASE_LEGACY(-8960, "codecErr")
        VTERRCASE_LEGACY(-8961, "noCodecErr")
        VTERRCASE_LEGACY(-8969, "codecBadDataErr")
        VTERRCASE_LEGACY(-8971, "codecExtensionNotFoundErr")
        VTERRCASE_LEGACY(-8973, "codecOpenErr")
        default:
            msg_Warn(p_dec, "unknown vt session error (%i)", (int)status);
    }
#undef VTERRCASE
#undef VTERRCASE_LEGACY

    if (p_vtsession_status)
    {
        switch (status)
        {
            case kVTPixelTransferNotSupportedErr:
            case kVTPixelTransferNotPermittedErr:
                *p_vtsession_status = VTSESSION_STATUS_RESTART_CHROMA;
                break;
            case -8960 /* codecErr */:
            case kVTVideoDecoderMalfunctionErr:
            case kVTInvalidSessionErr:
            case kVTVideoDecoderBadDataErr:
            case -8969 /* codecBadDataErr */:
                *p_vtsession_status = VTSESSION_STATUS_RESTART;
                break;
            case kVTVideoDecoderReferenceMissingErr:
                *p_vtsession_status = VTSESSION_STATUS_OK;
                break;
            default:
                *p_vtsession_status = VTSESSION_STATUS_ABORT;
                break;
        }
    }
    return VLC_EGENERIC;
}

#pragma mark - actual decoding

static void RequestFlush(decoder_t *p_dec)
{
    decoder_sys_t *p_sys = p_dec->p_sys;
    Drain(p_dec, true);
    date_Set(&p_sys->pts, VLC_TICK_INVALID);
    if(p_sys->pf_codec_flush)
        p_sys->pf_codec_flush(p_dec);
}

static void Drain(decoder_t *p_dec, bool flush)
{
    decoder_sys_t *p_sys = p_dec->p_sys;

    /* draining: return last pictures of the reordered queue */
    vlc_mutex_lock(&p_sys->lock);
    p_sys->b_discard_decoder_output = flush;
    vlc_mutex_unlock(&p_sys->lock);

    if (p_sys->session && p_sys->decoder_state == STATE_DECODER_STARTED)
        VTDecompressionSessionWaitForAsynchronousFrames(p_sys->session);

    vlc_mutex_lock(&p_sys->lock);
    DrainDPBLocked(p_dec, flush);
    assert(p_sys->dpb.i_size == 0);
    assert(p_sys->dpb.p_entries == NULL);
    p_sys->b_discard_decoder_output = false;
    p_sys->sync_state = p_sys->start_sync_state;
    vlc_mutex_unlock(&p_sys->lock);
}

static int DecodeBlock(decoder_t *p_dec, block_t *p_block)
{
    decoder_sys_t *p_sys = p_dec->p_sys;

    if (p_block == NULL)
    {
        Drain(p_dec, false);
        return VLCDEC_SUCCESS;
    }

    vlc_mutex_lock(&p_sys->lock);

    if (p_block->i_flags & BLOCK_FLAG_INTERLACED_MASK)
    {
#if TARGET_OS_IPHONE
        msg_Warn(p_dec, "VT decoder doesn't handle deinterlacing on iOS, "
                 "aborting...");
        p_sys->vtsession_status = VTSESSION_STATUS_ABORT;
#else
        if (!p_sys->b_cvpx_format_forced &&
            p_sys->i_cvpx_format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
        {
            /* In case of interlaced content, force VT to output I420 since our
             * SW deinterlacer handle this chroma natively. This avoids having
             * 2 extra conversions (CVPX->I420 then I420->CVPX). */

            p_sys->i_cvpx_format = kCVPixelFormatType_420YpCbCr8Planar;
            msg_Warn(p_dec, "Interlaced content: forcing VT to output I420");
            if (p_sys->session != NULL && p_sys->vtsession_status == VTSESSION_STATUS_OK)
            {
                msg_Warn(p_dec, "restarting vt session (color changed)");
                vlc_mutex_unlock(&p_sys->lock);

                /* Drain before stopping */
                Drain(p_dec, false);
                StopVideoToolbox(p_dec);

                vlc_mutex_lock(&p_sys->lock);
            }
        }
#endif
    }

    if (p_sys->vtsession_status == VTSESSION_STATUS_RESTART ||
        p_sys->vtsession_status == VTSESSION_STATUS_RESTART_CHROMA)
    {
        bool do_restart = true;
        if (p_sys->vtsession_status == VTSESSION_STATUS_RESTART_CHROMA)
        {
            if (p_sys->i_cvpx_format == 0 && p_sys->b_cvpx_format_forced)
            {
                /* Already tried to fallback to the original chroma, aborting... */
                do_restart = false;
            }
            else
            {
                p_sys->i_cvpx_format = 0;
                p_sys->b_cvpx_format_forced = true;
                do_restart = true;
            }
        }

        if (do_restart)
        {
            msg_Warn(p_dec, "restarting vt session (dec callback failed)");
            vlc_mutex_unlock(&p_sys->lock);

            /* Session will be started by Late Start code block */
            StopVideoToolbox(p_dec);

            vlc_mutex_lock(&p_sys->lock);
            p_sys->vtsession_status = VTSESSION_STATUS_OK;
        }
        else
        {
            msg_Warn(p_dec, "too many vt failure...");
            p_sys->vtsession_status = VTSESSION_STATUS_ABORT;
        }
    }

    if (p_sys->vtsession_status == VTSESSION_STATUS_ABORT)
    {
        vlc_mutex_unlock(&p_sys->lock);

        msg_Err(p_dec, "decoder failure, Abort.");
        /* Add an empty variable so that videotoolbox won't be loaded again for
         * this ES */
        var_Create(p_dec, "videotoolbox-failed", VLC_VAR_VOID);
        return VLCDEC_RELOAD;
    }
    else if (p_sys->vtsession_status == VTSESSION_STATUS_VOUT_FAILURE)
    {
        vlc_mutex_unlock(&p_sys->lock);
        return VLCDEC_RELOAD;
    }

    vlc_mutex_unlock(&p_sys->lock);

    if (unlikely(p_block->i_flags&(BLOCK_FLAG_CORRUPTED)))
    {
        if (p_sys->sync_state == STATE_BITSTREAM_SYNCED)
        {
            Drain(p_dec, false);
            date_Set(&p_sys->pts, VLC_TICK_INVALID);
        }
        goto skip;
    }

    bool b_config_changed = false;
    if (p_sys->pf_process_block)
    {
        p_block = p_sys->pf_process_block(p_dec, p_block, &b_config_changed);
        if (!p_block)
            return VLCDEC_SUCCESS;
    }

    frame_info_t *p_info = CreateReorderInfo(p_dec, p_block);
    if (unlikely(!p_info))
        goto skip;

    if (!p_sys->session /* Late Start */||
        (b_config_changed && p_info->b_flush))
    {
        if (p_sys->session &&
            p_sys->pf_need_restart &&
            p_sys->pf_need_restart(p_dec,p_sys->session))
        {
            msg_Dbg(p_dec, "parameters sets changed: draining decoder");
            Drain(p_dec, false);
            msg_Dbg(p_dec, "parameters sets changed: restarting decoder");
            StopVideoToolbox(p_dec);
        }

        if (!p_sys->session)
        {
            if ((p_sys->pf_codec_supported && !p_sys->pf_codec_supported(p_dec))
              || StartVideoToolbox(p_dec) != VLC_SUCCESS)
            {
                /* The current device doesn't handle the profile/level, abort */
                vlc_mutex_lock(&p_sys->lock);
                p_sys->vtsession_status = VTSESSION_STATUS_ABORT;
                vlc_mutex_unlock(&p_sys->lock);
            }
        }

        if (!p_sys->session) /* Start Failed */
        {
            free(p_info);
            goto skip;
        }
    }

    if (p_sys->sync_state == STATE_BITSTREAM_WAITING_RAP)
    {
        if(!p_info->b_keyframe)
        {
            msg_Dbg(p_dec, "discarding non recovery frame %"PRId64, p_info->pts);
            free(p_info);
            goto skip;
        }
        p_sys->sync_state = STATE_BITSTREAM_DISCARD_LEADING;
    }
    else if(p_sys->sync_state == STATE_BITSTREAM_DISCARD_LEADING)
    {
        if(p_info->b_leading)
        {
            msg_Dbg(p_dec, "discarding skipped leading frame %"PRId64, p_info->pts);
            free(p_info);
            goto skip;
        }
        p_sys->sync_state = STATE_BITSTREAM_SYNCED;
    }

    CMSampleBufferRef sampleBuffer =
        VTSampleBufferCreate(p_dec, p_sys->videoFormatDescription, p_block);
    if (unlikely(!sampleBuffer))
    {
        free(p_info);
        goto skip;
    }

    pic_pacer_WaitAllocatableSlot(p_sys->pic_pacer, p_info->b_field);

    VTDecodeInfoFlags flagOut;
    VTDecodeFrameFlags decoderFlags = kVTDecodeFrame_EnableAsynchronousDecompression;

    OSStatus status =
        VTDecompressionSessionDecodeFrame(p_sys->session, sampleBuffer,
                                          decoderFlags, p_info, &flagOut);

    enum vtsession_status vtsession_status;
    if (HandleVTStatus(p_dec, status, &vtsession_status) == VLC_SUCCESS)
    {
        pic_pacer_AccountScheduledDecode(p_sys->pic_pacer, p_info->b_field);

        if(p_sys->decoder_state != STATE_DECODER_STARTED)
        {
            msg_Dbg(p_dec, "session accepted first frame %"PRId64, p_info->pts);
            p_sys->decoder_state = STATE_DECODER_STARTED;
        }
        if (p_block->i_flags & BLOCK_FLAG_END_OF_SEQUENCE)
            Drain( p_dec, false );
    }
    else
    {
        msg_Dbg(p_dec, "session rejected frame %"PRId64" with status %d", p_info->pts, (int)status);
        p_sys->sync_state = p_sys->start_sync_state;
        vlc_mutex_lock(&p_sys->lock);
        p_sys->vtsession_status = vtsession_status;
        /* In case of abort, the decoder module will be reloaded next time
         * since we already modified the input block */
        vlc_mutex_unlock(&p_sys->lock);
    }
    CFRelease(sampleBuffer);

skip:
    block_Release(p_block);
    return VLCDEC_SUCCESS;
}

static int UpdateVideoFormat(decoder_t *p_dec, CVPixelBufferRef imageBuffer)
{
    decoder_sys_t *p_sys = p_dec->p_sys;
    CFDictionaryRef attachmentDict =
        CVBufferGetAttachments(imageBuffer, kCVAttachmentMode_ShouldPropagate);

    if (attachmentDict != NULL && CFDictionaryGetCount(attachmentDict) > 0 &&
        p_dec->fmt_out.video.chroma_location == CHROMA_LOCATION_UNDEF)
    {
        CFStringRef chromaLocation =
            CFDictionaryGetValue(attachmentDict, kCVImageBufferChromaLocationTopFieldKey);
        if (chromaLocation != NULL) {
            if (CFEqual(chromaLocation, kCVImageBufferChromaLocation_Left) ||
                CFEqual(chromaLocation, kCVImageBufferChromaLocation_DV420)) {
                p_dec->fmt_out.video.chroma_location = CHROMA_LOCATION_LEFT;
            } else if (CFEqual(chromaLocation, kCVImageBufferChromaLocation_Center)) {
                p_dec->fmt_out.video.chroma_location = CHROMA_LOCATION_CENTER;
            } else if (CFEqual(chromaLocation, kCVImageBufferChromaLocation_TopLeft)) {
                p_dec->fmt_out.video.chroma_location = CHROMA_LOCATION_TOP_LEFT;
            } else if (CFEqual(chromaLocation, kCVImageBufferChromaLocation_Top)) {
                p_dec->fmt_out.video.chroma_location = CHROMA_LOCATION_TOP_CENTER;
            }
        }

        if (p_dec->fmt_out.video.chroma_location == CHROMA_LOCATION_UNDEF) {
            chromaLocation =
                CFDictionaryGetValue(attachmentDict, kCVImageBufferChromaLocationBottomFieldKey);
            if (chromaLocation != NULL) {
                if (CFEqual(chromaLocation, kCVImageBufferChromaLocation_BottomLeft)) {
                    p_dec->fmt_out.video.chroma_location = CHROMA_LOCATION_BOTTOM_LEFT;
                } else if (CFEqual(chromaLocation, kCVImageBufferChromaLocation_Bottom)) {
                    p_dec->fmt_out.video.chroma_location = CHROMA_LOCATION_BOTTOM_CENTER;
                }
            }
        }
    }

    OSType cvfmt = CVPixelBufferGetPixelFormatType(imageBuffer);
    msg_Dbg(p_dec, "output chroma (kCVPixelFormatType): %4.4s",
        (const char *)&(OSType) { htonl(cvfmt) });
    switch (cvfmt)
    {
        case kCVPixelFormatType_422YpCbCr8:
        case 'yuv2':
            p_dec->fmt_out.i_codec = VLC_CODEC_CVPX_UYVY;
            assert(CVPixelBufferIsPlanar(imageBuffer) == false);
            break;
        case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange:
        case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:
            p_dec->fmt_out.i_codec = VLC_CODEC_CVPX_NV12;
            assert(CVPixelBufferIsPlanar(imageBuffer) == true);
            break;
        case kCVPixelFormatType_420YpCbCr10BiPlanarFullRange:
        case kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange:
            p_dec->fmt_out.i_codec = VLC_CODEC_CVPX_P010;
            assert(CVPixelBufferIsPlanar(imageBuffer) == true);
            break;
        case kCVPixelFormatType_422YpCbCr16BiPlanarVideoRange:
            p_dec->fmt_out.i_codec = VLC_CODEC_CVPX_P216;
            assert(CVPixelBufferIsPlanar(imageBuffer) == true);
            break;
        case kCVPixelFormatType_420YpCbCr8Planar:
            p_dec->fmt_out.i_codec = VLC_CODEC_CVPX_I420;
            assert(CVPixelBufferIsPlanar(imageBuffer) == true);
            break;
        case kCVPixelFormatType_32BGRA:
            p_dec->fmt_out.i_codec = VLC_CODEC_CVPX_BGRA;
            assert(CVPixelBufferIsPlanar(imageBuffer) == false);
            break;
        default:
            p_sys->vtsession_status = VTSESSION_STATUS_ABORT;
            return -1;
    }

    /* Extract color and HDR properties from decoded imageBuffer */
    cvpx_extract_color_properties(imageBuffer, &p_dec->fmt_out.video);

    if (decoder_UpdateVideoOutput(p_dec, p_sys->vctx) != 0)
    {
        p_sys->vtsession_status = VTSESSION_STATUS_VOUT_FAILURE;
        return -1;
    }
    return 0;
}

static void
video_context_OnPicReleased(vlc_video_context *vctx, unsigned nb_fields)
{
    struct pic_pacer *pic_pacer =
        vlc_video_context_GetCVPXPrivate(vctx, CVPX_VIDEO_CONTEXT_VIDEOTOOLBOX);

    pic_pacer_AccountDeallocation(pic_pacer, nb_fields == 1);
}

static void DecoderCallback(void *decompressionOutputRefCon,
                            void *sourceFrameRefCon,
                            OSStatus status,
                            VTDecodeInfoFlags infoFlags,
                            CVPixelBufferRef imageBuffer,
                            CMTime pts,
                            CMTime duration)
{
    VLC_UNUSED(duration);
    decoder_t *p_dec = (decoder_t *)decompressionOutputRefCon;
    decoder_sys_t *p_sys = p_dec->p_sys;
    frame_info_t *p_info = (frame_info_t *) sourceFrameRefCon;
    const bool b_field = p_info->b_field;

    vlc_mutex_lock(&p_sys->lock);
    if (p_sys->b_discard_decoder_output)
        goto end;

    enum vtsession_status vtsession_status;
    if (HandleVTStatus(p_dec, status, &vtsession_status) != VLC_SUCCESS)
    {
        if (p_sys->vtsession_status != VTSESSION_STATUS_ABORT)
            p_sys->vtsession_status = vtsession_status;
        goto end;
    }

    if (!imageBuffer)
    {
        if (unlikely((infoFlags & kVTDecodeInfo_FrameDropped) != kVTDecodeInfo_FrameDropped))
        {
            msg_Err(p_dec, "critical: null imageBuffer for a non-dropped frame with valid status");
            p_sys->vtsession_status = VTSESSION_STATUS_ABORT;
        } else {
            msg_Dbg(p_dec, "decoder dropped frame");
        }
        goto end;
    }

    if (p_sys->vtsession_status == VTSESSION_STATUS_ABORT)
        goto end;

    if (unlikely(!p_sys->b_format_propagated)) {
        p_sys->b_format_propagated =
            UpdateVideoFormat(p_dec, imageBuffer) == VLC_SUCCESS;

        if (!p_sys->b_format_propagated)
            goto end;
        assert(p_dec->fmt_out.i_codec != 0);
    }

    if (infoFlags & kVTDecodeInfo_FrameDropped)
    {
        /* We can't trust VT, some decoded frames can be marked as dropped */
        msg_Dbg(p_dec, "decoder dropped frame");
    }

    if (!CMTIME_IS_VALID(pts))
        goto end;

    if (CVPixelBufferGetDataSize(imageBuffer) == 0)
        goto end;

    if (unlikely(p_info == NULL))
        goto end;

    /* Unlock the mutex because decoder_NewPicture() is blocking. Indeed,
         * it can wait indefinitely when the input is paused. */

    vlc_mutex_unlock(&p_sys->lock);

    picture_t *p_pic = decoder_NewPicture(p_dec);
    if (p_pic)
    {
        p_pic->date = pts.value;
        p_pic->b_force = p_info->b_eos;
        p_pic->b_still = p_info->b_eos;
        p_pic->b_progressive = p_info->b_progressive;
        if (!p_pic->b_progressive)
        {
            p_pic->i_nb_fields = p_info->i_num_ts;
            p_pic->b_top_field_first = p_info->b_top_field_first;
        }

        /* Propagate HDR and color properties to picture */
        p_pic->format.mastering = p_dec->fmt_out.video.mastering;
        p_pic->format.lighting = p_dec->fmt_out.video.lighting;
        p_pic->format.primaries = p_dec->fmt_out.video.primaries;
        p_pic->format.transfer = p_dec->fmt_out.video.transfer;
        p_pic->format.space = p_dec->fmt_out.video.space;
        p_pic->format.color_range = p_dec->fmt_out.video.color_range;

        if (cvpxpic_attach(p_pic, imageBuffer, p_sys->vctx,
                           video_context_OnPicReleased) == VLC_SUCCESS)
        {
            /* VT is not pacing frame allocation. If we are not fast enough to
                 * render (release) the output pictures, the VT session can end up
                 * allocating way too many frames. This can be problematic for 4K
                 * 10bits. To fix this issue, we ensure that we don't have too many
                 * output frames allocated by waiting for the vout to release them. */
            pic_pacer_AccountAllocation(p_sys->pic_pacer, p_info->b_field);
        }

        struct vt_frame_info_t *p_vt_info = (struct vt_frame_info_t *)p_info;
        if (p_vt_info && p_vt_info->has_hdr10plus)
        {
            vlc_video_hdr_dynamic_metadata_t *dst =
                picture_AttachNewAncillary(p_pic, VLC_ANCILLARY_ID_HDR10PLUS, sizeof(*dst));
            if (dst)
                *dst = p_vt_info->hdr10plus;
        }

        if (p_vt_info && p_vt_info->has_dovi)
        {
            vlc_video_dovi_metadata_t *dst =
                picture_AttachNewAncillary(p_pic, VLC_ANCILLARY_ID_DOVI, sizeof(*dst));
            if (dst)
                *dst = p_vt_info->dovi;
        }
    }

    vlc_mutex_lock(&p_sys->lock);

    if (p_sys->b_discard_decoder_output)
        picture_Release(p_pic);
    else
        p_info->p_picture = p_pic;

    OnDecodedFrame( p_dec, p_info );
    p_info = NULL;

end:
    free(p_info);
    vlc_mutex_unlock(&p_sys->lock);
    pic_pacer_AccountFinishedDecode(p_sys->pic_pacer, b_field);
    return;
}

static int
OpenDecDevice(vlc_decoder_device *device, vlc_window_t *window)
{
    VLC_UNUSED(window);
    static const struct vlc_decoder_device_operations ops =
    {
        NULL,
    };
    device->ops = &ops;
    device->type = VLC_DECODER_DEVICE_VIDEOTOOLBOX;

    return VLC_SUCCESS;
}

#pragma mark - Module descriptor

#define VT_REQUIRE_HW_DEC N_("Use Hardware decoders only")
#define VT_FORCE_CVPX_CHROMA "Force the VideoToolbox output chroma"
#define VT_FORCE_CVPX_CHROMA_LONG "Force the VideoToolbox decoder to output \
    CVPixelBuffers in the specified pixel format instead of the default. \
    By default, the best chroma is chosen by the VideoToolbox decoder."

static const char *const chroma_list_values[] =
    {
        "",
        "x420",
        "xf20",
        "BGRA",
        "y420",
        "420f",
        "420v",
        "2vuy",
    };

static const char *const chroma_list_names[] =
    {
        "Auto",
        "Y'CbCr 10-bit 4:2:0 (Bi-Planar, Video Range - HDR)",
        "Y'CbCr 10-bit 4:2:0 (Bi-Planar, Full Range - HDR)",
        "BGRA 8-bit",
        "Y'CbCr 8-bit 4:2:0 (Planar)",
        "Y'CbCr 8-bit 4:2:0 (Bi-Planar, Full Range)",
        "Y'CbCr 8-bit 4:2:0 (Bi-Planar)",
        "Y'CbCr 8-bit 4:2:2",
    };

vlc_module_begin()
    set_subcategory(SUBCAT_INPUT_VCODEC)
    set_description(N_("VideoToolbox video decoder"))
    set_capability("video decoder", 800)
    set_callbacks(OpenDecoder, CloseDecoder)

    add_bool("videotoolbox-hw-decoder-only", true, VT_REQUIRE_HW_DEC, VT_REQUIRE_HW_DEC)
    add_string("videotoolbox-cvpx-chroma", "", VT_FORCE_CVPX_CHROMA, VT_FORCE_CVPX_CHROMA_LONG)
        change_string_list(chroma_list_values, chroma_list_names)

    /* Deprecated options */
    add_obsolete_bool("videotoolbox-temporal-deinterlacing") // Since 4.0.0
    add_obsolete_bool("videotoolbox") // Since 4.0.0

    add_submodule()
        set_callback_dec_device(OpenDecDevice, 1)
vlc_module_end()
