/*****************************************************************************
 * pl_scale.c
 *****************************************************************************
 * Copyright (C) 2021 VLC authors and VideoLAN
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

#include <stdatomic.h>

#include "limits.h"

#include <vlc_common.h>
#include <vlc_configuration.h>
#include <vlc_picture.h>
#include <vlc_plugin.h>
#include <vlc_modules.h>
#include <vlc_opengl.h>
#include <vlc_filter.h>
#include <vlc_opengl_filter.h>

#include <libplacebo/log.h>
#include <libplacebo/gpu.h>
#include <libplacebo/opengl.h>
#include <libplacebo/renderer.h>

#include "video_output/opengl/gl_api.h"
#include "video_output/opengl/gl_common.h"
#include "video_output/opengl/gl_scale.h"
#include "video_output/opengl/gl_util.h"
#include "video_output/opengl/sampler.h"
#include "video_output/libplacebo/utils.h"
#include "video_output/apple/maclc_hdr_vars.h"

#include <libplacebo/tone_mapping.h>

#define CFG_PREFIX "plscale-"

/* "Bright" lifts the PQ signal before tone mapping. A 8 % gain in PQ code
 * values raises reference white (203 cd/m2) to about 310 cd/m2 and everything
 * above proportionally, and the BT.2390 roll-off that follows keeps the result
 * under the display's peak: brighter mid-tones and highlights, paid for with
 * compressed or clipped highlight detail. */
#define MACLC_BRIGHT_PQ_GAIN 1.08f

/* Accurate: reproduce everything below 90 % of the target peak unchanged and
 * fold the rest into a Moebius shoulder (same intent as maclc_tonemap.h). */
#define MACLC_ACCURATE_KNEE 0.9f

static const char *const filter_options[] = {
    "upscaler", "downscaler", "target-prim", "target-trc", NULL,
};

struct sys
{
    struct vlc_gl_api api;
    GLuint id;
    GLuint vbo;

    pl_log pl_log;
    pl_opengl pl_opengl;
    pl_renderer pl_renderer;

    /* Cached representation of pl_frame to wrap the raw textures */
    struct pl_frame frame_in;
    struct pl_frame frame_out;
    struct pl_render_params render_params;
    struct pl_dovi_metadata dovi_metadata;
    struct pl_hdr_metadata hdr_static;

    unsigned out_width;
    unsigned out_height;

    vlc_object_t *display;
    _Atomic float headroom;
    float user_headroom;
    bool is_hdr_target;

    /* MacLC presentation / picture mode (maclc_hdr_vars.h) */
    struct pl_color_repr repr_base;
    struct pl_color_space color_base;
    struct pl_color_map_params color_map;
    struct pl_color_adjustment color_adjust;
    bool dovi_profile5;
    vlc_object_t *hdr_vars;          /* object holding the request variables */
    _Atomic int presentation;
    _Atomic int picture;
    int applied_picture;
    int applied_presentation;
    bool applied_fits;
    int64_t seen_caps;
    int64_t published_caps;
    const char *published_active;
};

static void
DestroyTextures(pl_gpu gpu, unsigned count, pl_tex textures[])
{
    for (unsigned i = 0; i < count; ++i)
        pl_tex_destroy(gpu, &textures[i]);
}

static int
WrapTextures(pl_gpu gpu, unsigned count, const GLuint textures[],
             const uint32_t tex_widths[], const uint32_t tex_heights[],
             GLenum tex_target, pl_tex out[])
{
    for (unsigned i = 0; i < count; ++i)
    {
        struct pl_opengl_wrap_params opengl_wrap_params = {
            .texture = textures[i],
            .width = tex_widths[i],
            .height = tex_heights[i],
            .target = tex_target,
            .iformat = GL_RGBA8,
        };

        out[i] = pl_opengl_wrap(gpu, &opengl_wrap_params);
        if (!out[i])
        {
            if (i)
                DestroyTextures(gpu, i - 1, out);
            return VLC_EGENERIC;
        }
    }

    return VLC_SUCCESS;
}

static pl_tex
WrapFramebuffer(pl_gpu gpu, GLuint framebuffer, unsigned width, unsigned height)
{
    struct pl_opengl_wrap_params opengl_wrap_params = {
        .framebuffer = framebuffer,
        .width = width,
        .height = height,
        .iformat = GL_RGBA8,
    };

    return pl_opengl_wrap(gpu, &opengl_wrap_params);
}

/* Picks the libplacebo tone mapping for the requested picture mode. Cheap
 * enough to call per frame: it only rewrites the parameters when the mode,
 * the presentation or the "does the master fit the display" answer changes. */
static void
UpdateToneMapping(struct sys *sys, int presentation, float src_peak,
                  float dst_peak)
{
    int picture = atomic_load_explicit(&sys->picture, memory_order_relaxed);
    const bool fits = src_peak > 0.0f && dst_peak > 0.0f && src_peak <= dst_peak;
    if (picture == sys->applied_picture &&
        presentation == sys->applied_presentation &&
        fits == sys->applied_fits)
        return;

    sys->applied_picture = picture;
    sys->applied_presentation = presentation;
    sys->applied_fits = fits;

    /* Same rule as the native output and the interface's advice. */
    if (picture == MACLC_HDR_PICTURE_AUTO)
        picture = fits ? MACLC_HDR_PICTURE_ACCURATE : MACLC_HDR_PICTURE_BALANCED;

    sys->color_map = pl_color_map_default_params;
    sys->color_adjust = pl_color_adjustment_neutral;

    switch (picture)
    {
        case MACLC_HDR_PICTURE_ACCURATE:
            sys->color_map.tone_mapping_function = &pl_tone_map_mobius;
            sys->color_map.tone_constants.linear_knee = MACLC_ACCURATE_KNEE;
            break;
        case MACLC_HDR_PICTURE_BRIGHT:
            sys->color_map.tone_mapping_function = &pl_tone_map_bt2390;
            sys->color_adjust.contrast = MACLC_BRIGHT_PQ_GAIN;
            break;
        case MACLC_HDR_PICTURE_BALANCED:
        default:
            sys->color_map.tone_mapping_function = &pl_tone_map_bt2390;
            break;
    }

    /* Which metadata the tone mapper may use: HDR10 means the static values
     * only, HDR10+ prefers its dynamic ST 2094-40 values. */
    if (presentation == MACLC_HDR_PRESENTATION_HDR10)
        sys->color_map.metadata = PL_HDR_METADATA_HDR10;
    else if (presentation == MACLC_HDR_PRESENTATION_HDR10PLUS)
        sys->color_map.metadata = PL_HDR_METADATA_HDR10PLUS;
    else
        sys->color_map.metadata = PL_HDR_METADATA_ANY;

    sys->render_params.color_map_params = &sys->color_map;
    sys->render_params.color_adjustment = &sys->color_adjust;
}

static void
PublishHdrState(struct sys *sys, int64_t caps, const char *active)
{
    if (sys->hdr_vars == NULL)
        return;
    if (caps != sys->published_caps)
    {
        sys->published_caps = caps;
        var_SetInteger(sys->hdr_vars, MACLC_HDR_VAR_CAPS, caps);
    }
    if (active != sys->published_active)
    {
        sys->published_active = active;
        var_SetString(sys->hdr_vars, MACLC_HDR_VAR_ACTIVE, active);
    }
}

static int
Draw(struct vlc_gl_filter *filter, const struct vlc_gl_picture *pic,
     const struct vlc_gl_input_meta *meta)
{
    (void) meta;

    struct sys *sys = filter->sys;
    const opengl_vtable_t *vt = &sys->api.vt;
    struct vlc_gl_sampler *sampler = filter->sampler;
    pl_gpu gpu = sys->pl_opengl->gpu;
    struct pl_frame *frame_in = &sys->frame_in;
    struct pl_frame *frame_out = &sys->frame_out;
    struct pl_render_params *render_params = &sys->render_params;

    if (pic->mtx_has_changed)
    {
        const float *mtx = pic->mtx;

        /* The direction is either horizontal or vertical, and the two vectors
         * are orthogonal */
        assert((!mtx[1] && !mtx[2]) || (!mtx[0] && !mtx[3]));

        /* Is the video rotated by 90° (or 270°)? */
        bool rotated90 = !mtx[0];

        /*
         * The same rotation+flip orientation may be encoded in different ways
         * in libplacebo. For example, hflip the crop rectangle and use a 90°
         * rotation is equivalent to vflip the crop rectangle and use a 270°
         * rotation.
         *
         * To get a unique solution, limit the rotation to be either 0 or 90,
         * and encode the remaining in the crop rectangle.
         */
        frame_in->rotation = rotated90 ? PL_ROTATION_90 : PL_ROTATION_0;

        /* Apply 90° to the coords if necessary */
        float coords[] = {
            rotated90 ? 1 : 0, 0,
            rotated90 ? 0 : 1, 1,
        };

        vlc_gl_picture_ToTexCoords(pic, 2, coords, coords);

        unsigned w = sampler->tex_widths[0];
        unsigned h = sampler->tex_heights[0];
        struct pl_rect2df *r = &frame_in->crop;
        r->x0 = coords[0] * w;
        r->y0 = coords[1] * h;
        r->x1 = coords[2] * w;
        r->y1 = coords[3] * h;
    }

    const int presentation =
        atomic_load_explicit(&sys->presentation, memory_order_relaxed);

    /* Which metadata drives this frame. Dolby Vision RPUs are applied per
     * picture whenever they are present - also for files whose container did
     * not announce them - unless another presentation was asked for; profile
     * 5 has no usable base layer, so its RPUs are always applied. */
    const bool want_dovi = sys->dovi_profile5
        || presentation == MACLC_HDR_PRESENTATION_AUTO
        || presentation == MACLC_HDR_PRESENTATION_DOLBYVISION;
    const bool use_rpu = meta->dovi_rpu != NULL && want_dovi;
    const bool use_hdr10plus = meta->hdr10plus != NULL && !use_rpu
        && (presentation == MACLC_HDR_PRESENTATION_AUTO
            || presentation == MACLC_HDR_PRESENTATION_HDR10PLUS);

    frame_in->repr = sys->repr_base;
    frame_in->color = sys->color_base;
    frame_in->color.hdr = sys->hdr_static;

    if (use_rpu) {
        frame_in->color.primaries = PL_COLOR_PRIM_BT_2020;
        frame_in->color.transfer = PL_COLOR_TRC_PQ;
        frame_in->repr.sys = PL_COLOR_SYSTEM_DOLBYVISION;
        frame_in->repr.dovi = &sys->dovi_metadata;
        vlc_placebo_DoviMetadata(meta->dovi_rpu, &sys->dovi_metadata);
        struct pl_hdr_metadata *hdr = &frame_in->color.hdr;
        const float scale = 1.0f / ((1 << 12) - 1);
        hdr->min_luma = pl_hdr_rescale(PL_HDR_PQ, PL_HDR_NITS,
                                       scale * meta->dovi_rpu->source_min_pq);
        hdr->max_luma = pl_hdr_rescale(PL_HDR_PQ, PL_HDR_NITS,
                                       scale * meta->dovi_rpu->source_max_pq);
    } else if (frame_in->repr.sys == PL_COLOR_SYSTEM_DOLBYVISION) {
        /* Announced as Dolby Vision but rendered from the base layer. */
        frame_in->repr.sys = PL_COLOR_SYSTEM_BT_2020_NC;
        frame_in->repr.dovi = NULL;
    }

    if (use_hdr10plus)
        vlc_placebo_HdrMetadata(meta->hdr10plus, &frame_in->color.hdr);

    const bool sdr_target = presentation == MACLC_HDR_PRESENTATION_SDR;
    if (sys->is_hdr_target)
    {
        float headroom = atomic_load_explicit(&sys->headroom, memory_order_relaxed);
        if (headroom <= 0.0f)
            headroom = sys->user_headroom;

        /* On an EDR surface 1.0 is the display's SDR white, which is where
         * libplacebo puts reference white (PL_COLOR_SDR_WHITE, 203 cd/m2, as
         * in ITU-R BT.2408); the headroom multiplies that. */
        if (sdr_target)
            frame_out->color.hdr.max_luma = PL_COLOR_SDR_WHITE;
        else if (headroom > 0.0f)
            frame_out->color.hdr.max_luma = PL_COLOR_SDR_WHITE * headroom;
        else
            frame_out->color.hdr.max_luma = 1000.0f;
    }

    UpdateToneMapping(sys, presentation, frame_in->color.hdr.max_luma,
                      frame_out->color.hdr.max_luma);

    /* Report what reached us and what we render, for the interface. */
    int64_t caps = sys->seen_caps;
    if (meta->dovi_rpu != NULL)
        caps |= MACLC_HDR_CAP_DOVI_SEEN;
    if (meta->hdr10plus != NULL)
        caps |= MACLC_HDR_CAP_HDR10PLUS_SEEN;
    sys->seen_caps = caps;
    const char *active;
    if (sdr_target || !pl_color_space_is_hdr(&frame_in->color))
        active = maclc_hdr_presentation_name(MACLC_HDR_PRESENTATION_SDR);
    else if (use_rpu)
        active = maclc_hdr_presentation_name(MACLC_HDR_PRESENTATION_DOLBYVISION);
    else if (use_hdr10plus)
        active = maclc_hdr_presentation_name(MACLC_HDR_PRESENTATION_HDR10PLUS);
    else if (frame_in->color.transfer == PL_COLOR_TRC_HLG)
        active = maclc_hdr_presentation_name(MACLC_HDR_PRESENTATION_HLG);
    else
        active = maclc_hdr_presentation_name(MACLC_HDR_PRESENTATION_HDR10);
    PublishHdrState(sys, caps | MACLC_HDR_CAP_CAN_DOVI | MACLC_HDR_CAP_CAN_HDR10PLUS,
                    active);

    GLint value;
    vt->GetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &value);
    GLuint final_draw_framebuffer = value; /* as GLuint */

    pl_tex texs_in[PICTURE_PLANE_MAX];
    int ret = WrapTextures(gpu, sampler->tex_count, pic->textures,
                           sampler->tex_widths, sampler->tex_heights,
                           sampler->tex_target, texs_in);
    if (ret != VLC_SUCCESS)
        goto end;

    /* Only changes the plane textures from the cached pl_frame */
    for (unsigned i = 0; i < sampler->tex_count; ++i)
        frame_in->planes[i].texture = texs_in[i];

    pl_tex tex_out = WrapFramebuffer(gpu, final_draw_framebuffer,
                                     sys->out_width, sys->out_height);
    if (!tex_out)
        goto destroy_texs_in;

    frame_out->planes[0].texture = tex_out;

    bool ok = pl_render_image(sys->pl_renderer, frame_in, frame_out,
                              render_params);
    if (!ok)
        ret = VLC_EGENERIC;

    DestroyTextures(gpu, 1, &tex_out);
destroy_texs_in:
    DestroyTextures(gpu, sampler->tex_count, texs_in);

end:
    vt->BindFramebuffer(GL_DRAW_FRAMEBUFFER, final_draw_framebuffer);

    return ret;
}

static int
RequestOutputSize(struct vlc_gl_filter *filter,
                  struct vlc_gl_tex_size *req,
                  struct vlc_gl_tex_size *optimal_in)
{
    struct sys *sys = filter->sys;

    sys->out_width = req->width;
    sys->out_height = req->height;

    /* Do not propagate resizing to previous filters */
    (void) optimal_in;

    return VLC_SUCCESS;
}

static int
EdrHeadroomCallback(vlc_object_t *obj, const char *var,
                    vlc_value_t oldval, vlc_value_t newval, void *data)
{
    (void) obj; (void) var; (void) oldval;
    _Atomic float *headroom = data;
    atomic_store_explicit(headroom, newval.f_float, memory_order_relaxed);
    return VLC_SUCCESS;
}

static vlc_object_t *
FindEdrHeadroomSource(struct vlc_gl_filter *filter)
{
    for (vlc_object_t *obj = VLC_OBJECT(filter); obj != NULL; obj = vlc_object_parent(obj))
    {
        if (var_Type(obj, "edr-headroom-effective") != 0)
            return obj;
    }
    return NULL;
}

static int
PresentationCallback(vlc_object_t *obj, const char *var,
                     vlc_value_t oldval, vlc_value_t newval, void *data)
{
    (void) var; (void) oldval;
    struct sys *sys = data;
    const int presentation = maclc_hdr_presentation_parse(newval.psz_string);
    atomic_store_explicit(&sys->presentation, presentation, memory_order_relaxed);
    msg_Dbg(obj, "HDR presentation requested: %s",
            maclc_hdr_presentation_name(presentation));
    return VLC_SUCCESS;
}

static int
PictureCallback(vlc_object_t *obj, const char *var,
                vlc_value_t oldval, vlc_value_t newval, void *data)
{
    (void) var; (void) oldval;
    struct sys *sys = data;
    const int picture = maclc_hdr_picture_parse(newval.psz_string);
    atomic_store_explicit(&sys->picture, picture, memory_order_relaxed);
    msg_Dbg(obj, "HDR picture mode requested: %s",
            maclc_hdr_picture_name(picture));
    return VLC_SUCCESS;
}

/* The display module creates the request and state variables on the video
 * output object; find it by walking up from the filter. */
static vlc_object_t *
FindHdrVarsHolder(struct vlc_gl_filter *filter)
{
    for (vlc_object_t *obj = VLC_OBJECT(filter); obj != NULL; obj = vlc_object_parent(obj))
    {
        if (var_Type(obj, MACLC_HDR_VAR_CAPS) != 0)
            return obj;
    }
    return NULL;
}

static void
Close(struct vlc_gl_filter *filter)
{
    struct sys *sys = filter->sys;

    if (sys->display != NULL)
        var_DelCallback(sys->display, "edr-headroom-effective",
                        EdrHeadroomCallback, &sys->headroom);
    if (sys->hdr_vars != NULL)
    {
        var_DelCallback(sys->hdr_vars, MACLC_HDR_VAR_PRESENTATION,
                        PresentationCallback, sys);
        var_DelCallback(sys->hdr_vars, MACLC_HDR_VAR_PICTURE,
                        PictureCallback, sys);
    }

    pl_renderer_destroy(&sys->pl_renderer);
    pl_opengl_destroy(&sys->pl_opengl);
    pl_log_destroy(&sys->pl_log);

    free(sys);
}

static vlc_gl_filter_open_fn Open;
static int
Open(struct vlc_gl_filter *filter, const config_chain_t *config,
     struct vlc_gl_sampler *sampler, struct vlc_gl_tex_size *size_out)
{
    (void) config;

    /* By default, do not scale. The dimensions will be modified dynamically by
     * request_output_size(). */
    unsigned width = sampler->tex_widths[0];
    unsigned height = sampler->tex_heights[0];

    config_ChainParse(filter, CFG_PREFIX, filter_options, config);
    int upscaler = var_InheritInteger(filter, CFG_PREFIX "upscaler");
    int downscaler = var_InheritInteger(filter, CFG_PREFIX "downscaler");
    int target_prim = var_InheritInteger(filter, CFG_PREFIX "target-prim");
    if (!target_prim)
        target_prim = var_InheritInteger(filter, "pl-target-prim");
    if (target_prim < 0 || target_prim >= PL_COLOR_PRIM_COUNT)
        target_prim = PL_COLOR_PRIM_UNKNOWN;

    int target_trc = var_InheritInteger(filter, CFG_PREFIX "target-trc");
    if (!target_trc)
        target_trc = var_InheritInteger(filter, "pl-target-trc");
    if (target_trc < 0 || target_trc >= PL_COLOR_TRC_COUNT)
        target_trc = PL_COLOR_TRC_UNKNOWN;

    if (upscaler < 0 || (size_t) upscaler >= ARRAY_SIZE(scale_values)
            || upscaler == SCALE_CUSTOM)
    {
        msg_Err(filter, "Unsupported upscaler: %d", upscaler);
        return VLC_EGENERIC;
    }

    if (downscaler < 0 || (size_t) downscaler >= ARRAY_SIZE(scale_values)
            || downscaler == SCALE_CUSTOM)
    {
        msg_Err(filter, "Unsupported downscaler: %d", downscaler);
        return VLC_EGENERIC;
    }

    struct sys *sys = filter->sys = calloc(1, sizeof(*sys));
    if (!sys)
        return VLC_EGENERIC;

    int ret = vlc_gl_api_Init(&sys->api, filter->gl);
    if (ret != VLC_SUCCESS)
    {
        free(sys);
        return VLC_EGENERIC;
    }

    sys->pl_log = vlc_placebo_CreateLog(VLC_OBJECT(filter));

    struct pl_opengl_params opengl_params = {
        .debug = true,
    };
    sys->pl_opengl = pl_opengl_create(sys->pl_log, &opengl_params);

    if (!sys->pl_opengl)
        goto error;

    pl_gpu gpu = sys->pl_opengl->gpu;
    sys->pl_renderer = pl_renderer_create(sys->pl_log, gpu);
    if (!sys->pl_renderer)
        goto error;

    sys->frame_in = (struct pl_frame) {
        .num_planes = sampler->tex_count,
        .repr = vlc_placebo_ColorRepr(&sampler->fmt_in),
        .color = vlc_placebo_ColorSpace(&sampler->fmt_in),
    };

    sys->hdr_static = sys->frame_in.color.hdr;
    /* What the base layer is on its own; Draw() switches to Dolby Vision per
     * picture when an RPU is there and wanted. */
    sys->repr_base = sys->frame_in.repr;
    sys->color_base = sys->frame_in.color;
    sys->dovi_profile5 = sampler->fmt_in.dovi.profile == 5;

    if (sampler->fmt_in.dovi.rpu_present || sys->dovi_profile5) {
        sys->frame_in.color.primaries = PL_COLOR_PRIM_BT_2020;
        sys->frame_in.color.transfer = PL_COLOR_TRC_PQ;
        sys->frame_in.repr.sys = PL_COLOR_SYSTEM_DOLBYVISION;
        sys->frame_in.repr.dovi = &sys->dovi_metadata; /* to be filled later */
        if (sys->dovi_profile5) {
            /* No standard base layer: never render it without the RPU. */
            sys->repr_base = sys->frame_in.repr;
            sys->color_base = sys->frame_in.color;
        }
    }

    /* MacLC presentation and picture mode, live when the display module
     * provides the variables, read once otherwise. */
    char *request = var_InheritString(filter, MACLC_HDR_VAR_PRESENTATION);
    atomic_init(&sys->presentation, maclc_hdr_presentation_parse(request));
    free(request);
    request = var_InheritString(filter, MACLC_HDR_VAR_PICTURE);
    atomic_init(&sys->picture, maclc_hdr_picture_parse(request));
    free(request);
    sys->applied_picture = -1;
    sys->applied_presentation = -1;
    sys->published_caps = -1;
    sys->hdr_vars = FindHdrVarsHolder(filter);
    if (sys->hdr_vars != NULL)
    {
        var_AddCallback(sys->hdr_vars, MACLC_HDR_VAR_PRESENTATION,
                        PresentationCallback, sys);
        var_AddCallback(sys->hdr_vars, MACLC_HDR_VAR_PICTURE,
                        PictureCallback, sys);
    }

    /* Initialize frame_in.planes */
    int plane_count =
        vlc_placebo_PlaneComponents(&sampler->fmt_in, sys->frame_in.planes);
    if ((unsigned) plane_count != sampler->tex_count) {
        msg_Err(filter, "Unexpected plane count (%d) != tex count (%u)",
                        plane_count, sampler->tex_count);
        goto error;
    }

    /* Target colour space and HDR display metadata for libplacebo tone-mapping.
     * Order of preference:
     * 1. Explicit user configuration via inherited options ("pl-target-prim",
     *    "pl-target-trc", or filter chain "target-prim", "target-trc").
     * 2. Platform display characteristics:
     *    - For HDR content on macOS, the compositor presents an extended-sRGB
     *      / Display-P3 surface (PL_COLOR_PRIM_DISPLAY_P3, PL_COLOR_TRC_SRGB).
     *    - For SDR content, the target matches the input colour space to ensure
     *      8-bit BT.709 playback does not regress and avoids unintended gamut
     *      or transfer curve conversion.
     * 3. Peak luminance and EDR headroom:
     *    - For HDR content, prefer the effective display headroom published
     *      by the vout display module via "edr-headroom-effective". Target
     *      peak luminance is PL_COLOR_SDR_WHITE (203 cd/m2) * headroom.
     *    - Fall back to explicit user override from "macosx-edr-headroom" (> 0.0f).
     *    - Fall back last to a fixed 1000.0 cd/m² peak (the sustained capability
     *      of Apple Silicon Liquid Retina XDR displays).
     */
    struct pl_color_space color_out = {0};
    bool is_hdr = pl_color_space_is_hdr(&sys->frame_in.color);

    if (target_prim)
        color_out.primaries = target_prim;
    else if (is_hdr)
        color_out.primaries = PL_COLOR_PRIM_DISPLAY_P3;
    else
        color_out.primaries = sys->frame_in.color.primaries;

    if (target_trc)
        color_out.transfer = target_trc;
    else if (is_hdr)
        color_out.transfer = PL_COLOR_TRC_SRGB;
    else
        color_out.transfer = sys->frame_in.color.transfer;

    sys->is_hdr_target = is_hdr || (target_trc && pl_color_transfer_is_hdr(target_trc));
    sys->user_headroom = var_InheritFloat(filter, "macosx-edr-headroom");

    if (sys->is_hdr_target)
    {
        vlc_object_t *display = FindEdrHeadroomSource(filter);
        float headroom = 0.0f;
        if (display != NULL)
        {
            headroom = var_GetFloat(display, "edr-headroom-effective");
            sys->display = display;
        }
        else
            headroom = var_InheritFloat(filter, "edr-headroom-effective");

        atomic_init(&sys->headroom, headroom);

        if (display != NULL)
            var_AddCallback(display, "edr-headroom-effective",
                            EdrHeadroomCallback, &sys->headroom);

        float effective = headroom;
        if (effective <= 0.0f)
            effective = sys->user_headroom;

        if (effective > 0.0f)
            color_out.hdr.max_luma = PL_COLOR_SDR_WHITE * effective;
        else
            color_out.hdr.max_luma = 1000.0f;
    }

    sys->frame_out = (struct pl_frame) {
        .num_planes = 1,
        .planes = {
            {
                .components = 4,
                .component_mapping = {
                    PL_CHANNEL_R,
                    PL_CHANNEL_G,
                    PL_CHANNEL_B,
                    PL_CHANNEL_A,
                },
            },
        },
        .color = color_out,
    };

    sys->render_params = pl_render_default_params;

    int upscaler_idx = libplacebo_scale_map[upscaler];
    sys->render_params.upscaler = scale_config[upscaler_idx];

    int downscaler_idx = libplacebo_scale_map[downscaler];
    sys->render_params.downscaler = scale_config[downscaler_idx];

    static const struct vlc_gl_filter_ops ops = {
        .draw = Draw,
        .close = Close,
        .request_output_size = RequestOutputSize,
    };
    filter->ops = &ops;

    sys->out_width = size_out->width = width;
    sys->out_height = size_out->height = height;

    return VLC_SUCCESS;

error:
    if (sys->display != NULL)
        var_DelCallback(sys->display, "edr-headroom-effective",
                        EdrHeadroomCallback, &sys->headroom);
    if (sys->hdr_vars != NULL)
    {
        var_DelCallback(sys->hdr_vars, MACLC_HDR_VAR_PRESENTATION,
                        PresentationCallback, sys);
        var_DelCallback(sys->hdr_vars, MACLC_HDR_VAR_PICTURE,
                        PictureCallback, sys);
    }
    pl_renderer_destroy(&sys->pl_renderer);
    pl_opengl_destroy(&sys->pl_opengl);
    pl_log_destroy(&sys->pl_log);
    free(sys);

    return VLC_EGENERIC;
}

vlc_module_begin()
    set_shortname("pl_scale")
    set_description("OpenGL scaler")
    set_subcategory(SUBCAT_VIDEO_VFILTER)
    set_capability("opengl filter", 0)
    set_callback(Open)
    add_shortcut("pl_scale")

#define UPSCALER_TEXT "OpenGL upscaler"
#define UPSCALER_LONGTEXT "Upscaler filter to apply during rendering"
    add_integer(CFG_PREFIX "upscaler", SCALE_BUILTIN, UPSCALER_TEXT, \
                UPSCALER_LONGTEXT) \
        change_integer_list(scale_values, scale_text) \

#define DOWNSCALER_TEXT "OpenGL downscaler"
#define DOWNSCALER_LONGTEXT "Downscaler filter to apply during rendering"
    add_integer(CFG_PREFIX "downscaler", SCALE_BUILTIN, DOWNSCALER_TEXT, \
                DOWNSCALER_LONGTEXT) \
        change_integer_list(scale_values, scale_text) \

    add_integer(CFG_PREFIX "target-prim", PL_COLOR_PRIM_UNKNOWN, PRIM_TEXT, \
                PRIM_LONGTEXT) \
        change_integer_list(prim_values, prim_text) \

    add_integer(CFG_PREFIX "target-trc", PL_COLOR_TRC_UNKNOWN, TRC_TEXT, \
                TRC_LONGTEXT) \
        change_integer_list(trc_values, trc_text)
vlc_module_end()
