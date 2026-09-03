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

#define CFG_PREFIX "plscale-"

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

    frame_in->color.hdr = sys->hdr_static;

    if (frame_in->repr.dovi && meta->dovi_rpu) {
        vlc_placebo_DoviMetadata(meta->dovi_rpu, &sys->dovi_metadata);
        struct pl_hdr_metadata *hdr = &frame_in->color.hdr;
        const float scale = 1.0f / ((1 << 12) - 1);
        hdr->min_luma = pl_hdr_rescale(PL_HDR_PQ, PL_HDR_NITS,
                                       scale * meta->dovi_rpu->source_min_pq);
        hdr->max_luma = pl_hdr_rescale(PL_HDR_PQ, PL_HDR_NITS,
                                       scale * meta->dovi_rpu->source_max_pq);
    }

    if (meta->hdr10plus) {
        vlc_placebo_HdrMetadata(meta->hdr10plus, &frame_in->color.hdr);
    }

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

static void
Close(struct vlc_gl_filter *filter)
{
    struct sys *sys = filter->sys;

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

    if (sampler->fmt_in.dovi.rpu_present && !sampler->fmt_in.dovi.el_present) {
        sys->frame_in.color.primaries = PL_COLOR_PRIM_BT_2020;
        sys->frame_in.color.transfer = PL_COLOR_TRC_PQ;
        sys->frame_in.repr.sys = PL_COLOR_SYSTEM_DOLBYVISION;
        sys->frame_in.repr.dovi = &sys->dovi_metadata; /* to be filled later */
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
     *    - If "macosx-edr-headroom" is explicitly set by the user (> 0.0f),
     *      target peak luminance is calculated as 100.0f * headroom nits.
     *    - Otherwise, dynamic screen headroom query (NSScreen's
     *      maximumExtendedDynamicRangeColorComponentValue) is NOT-REACHED:
     *      in caopengllayer.m, the screen headroom query is retained in
     *      internal Objective-C layer properties (effectiveHeadroom) and is
     *      never published back to the VLC object tree (vd or sys->gl), nor
     *      is display dynamic range passed through vout_display_opengl_New()
     *      or vlc_gl_filters_Append().
     *      To plumb dynamic headroom without inventing an API, caopengllayer.m
     *      would need to set "macosx-edr-headroom" on vd or an "edr-headroom"
     *      float variable on sys->gl whenever the screen or window headroom
     *      changes.
     *      In the absence of a reached dynamic headroom, fall back to a fixed
     *      1000.0 cd/m² peak (the sustained capability of Apple Silicon
     *      Liquid Retina XDR displays).
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

    float headroom = var_InheritFloat(filter, "macosx-edr-headroom");
    if (headroom > 0.0f)
        color_out.hdr.max_luma = 100.0f * headroom;
    else if (is_hdr || (target_trc && pl_color_transfer_is_hdr(target_trc)))
        color_out.hdr.max_luma = 1000.0f;

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
