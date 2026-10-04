/*****************************************************************************
 * maclc_dialogue.c : dialogue enhancement audio filter
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

#include <math.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <stdatomic.h>
#include <Accelerate/Accelerate.h>

#ifndef MACLC_DIALOGUE_NO_MODULE
# include <vlc_common.h>
# include <vlc_aout.h>
# include <vlc_filter.h>
# include <vlc_plugin.h>
#else
# ifndef AOUT_CHAN_CENTER
#  define AOUT_CHAN_CENTER       0x1
#  define AOUT_CHAN_LEFT         0x2
#  define AOUT_CHAN_RIGHT        0x4
#  define AOUT_CHAN_REARCENTER   0x10
#  define AOUT_CHAN_REARLEFT     0x20
#  define AOUT_CHAN_REARRIGHT    0x40
#  define AOUT_CHAN_MIDDLELEFT   0x100
#  define AOUT_CHAN_MIDDLERIGHT  0x200
#  define AOUT_CHAN_LFE          0x1000
#  define AOUT_CHANS_FRONT       (AOUT_CHAN_LEFT | AOUT_CHAN_RIGHT)
#  define AOUT_CHAN_MAX          9
# endif

# ifndef unlikely
#  define unlikely(x) (x)
# endif

# ifndef VLC_AOUT_H
static const uint32_t pi_vlc_chan_order_wg4[] =
{
    AOUT_CHAN_LEFT, AOUT_CHAN_RIGHT,
    AOUT_CHAN_MIDDLELEFT, AOUT_CHAN_MIDDLERIGHT,
    AOUT_CHAN_REARLEFT, AOUT_CHAN_REARRIGHT, AOUT_CHAN_REARCENTER,
    AOUT_CHAN_CENTER, AOUT_CHAN_LFE, 0
};
# endif
#endif

#ifndef M_PI
# define M_PI 3.14159265358979323846
#endif

#define FIFO_CAPACITY 32768
#define FIFO_MASK     (FIFO_CAPACITY - 1)

enum dialogue_mode
{
    DIALOGUE_MODE_A, /* Multichannel with Center (>= 3 channels) */
    DIALOGUE_MODE_B, /* Stereo L+R present, no Center: STFT centre extraction */
    DIALOGUE_MODE_C  /* Mono / odd layouts */
};

struct biquad_coeffs
{
    bool active;
    double b0, b1, b2;
    double a1, a2;
};

struct biquad_state
{
    double s1;
    double s2;
};

struct maclc_dialogue_sys
{
    _Atomic float new_amount;
    float prev_amount;
    float rate;
    unsigned channels;
    uint32_t physical_channels;
    enum dialogue_mode mode;

    int idx_c;
    int idx_l;
    int idx_r;
    int idx_lfe;

    /* Mode A / Mode C biquad filter state */
    struct biquad_coeffs bq_coeffs;
    struct biquad_state bq_state[AOUT_CHAN_MAX];

    /* Current static gains (interpolated across ramp for Mode A / Mode C) */
    float current_gains[AOUT_CHAN_MAX];
    float current_gain_m;
    float current_gain_s;

    /* Target static gains */
    float target_gains[AOUT_CHAN_MAX];
    float target_gain_m;
    float target_gain_s;

    /* Mode B: STFT centre extraction state */
    unsigned n_fft;
    vDSP_Length log2n;
    unsigned hop;
    unsigned latency;

    FFTSetup fft_setup;
    float *window;
    float *synth_window;
    float *b_k;

    /* Per-bin smoothed power / cross-power spectra */
    float *p_ll;
    float *p_rr;
    float *p_lr_r;
    float *p_lr_i;

    float *raw_mask;
    float *smooth_mask;

    DSPSplitComplex split_l;
    DSPSplitComplex split_r;

    float *time_l;
    float *time_r;
    float *ola_l;
    float *ola_r;

    /* Ring buffers for arbitrary chunk size handling */
    float *fifo_in_l;
    float *fifo_in_r;
    float *fifo_out_l;
    float *fifo_out_r;
    size_t in_read_pos;
    size_t in_write_pos;
    size_t out_read_pos;
    size_t out_write_pos;

    /* Delay lines for extra channels in stereo layouts (e.g. 2.1, 4.0) */
    float *delay_line[AOUT_CHAN_MAX];
    unsigned delay_pos[AOUT_CHAN_MAX];
};

typedef struct maclc_dialogue_sys maclc_dialogue_sys_t;
typedef struct maclc_dialogue_sys filter_sys_t;

/*****************************************************************************
 * DSP arithmetic helpers
 *****************************************************************************/

static inline float db_to_linear( float db )
{
    return powf( 10.0f, db / 20.0f );
}

static void biquad_compute_peaking( struct biquad_coeffs *bq, double f0,
                                    double q, double gain_db, double fs )
{
    if( f0 >= 0.45 * fs || fs <= 0.0 )
    {
        bq->active = false;
        bq->b0 = 1.0;
        bq->b1 = 0.0;
        bq->b2 = 0.0;
        bq->a1 = 0.0;
        bq->a2 = 0.0;
        return;
    }

    bq->active = true;
    double A = pow( 10.0, gain_db / 40.0 );
    double w0 = 2.0 * M_PI * f0 / fs;
    double alpha = sin( w0 ) / ( 2.0 * q );
    double cos_w0 = cos( w0 );

    double b0 = 1.0 + alpha * A;
    double b1 = -2.0 * cos_w0;
    double b2 = 1.0 - alpha * A;
    double a0 = 1.0 + alpha / A;
    double a1 = -2.0 * cos_w0;
    double a2 = 1.0 - alpha / A;

    bq->b0 = b0 / a0;
    bq->b1 = b1 / a0;
    bq->b2 = b2 / a0;
    bq->a1 = a1 / a0;
    bq->a2 = a2 / a0;
}

static inline float biquad_process( const struct biquad_coeffs *bq,
                                    struct biquad_state *s, float in )
{
    if( !bq->active )
        return in;

    double x = (double)in;
    double y = bq->b0 * x + s->s1;
    s->s1 = bq->b1 * x - bq->a1 * y + s->s2;
    s->s2 = bq->b2 * x - bq->a2 * y;
    return (float)y;
}

/*****************************************************************************
 * Mode B: STFT frame processing
 *****************************************************************************/

static void dialogue_process_stft_frame( maclc_dialogue_sys_t *sys )
{
    const unsigned n_fft = sys->n_fft;
    const unsigned half_n = n_fft / 2;
    const unsigned hop = sys->hop;

    /* 1. Read n_fft samples from input FIFO and apply periodic Hann analysis window */
    for( unsigned i = 0; i < n_fft; i++ )
    {
        size_t idx = (sys->in_read_pos + i) & FIFO_MASK;
        sys->time_l[i] = sys->fifo_in_l[idx] * sys->window[i];
        sys->time_r[i] = sys->fifo_in_r[idx] * sys->window[i];
    }

    /* 2. Unpack real samples into even/odd split complex representation */
    for( unsigned i = 0; i < half_n; i++ )
    {
        sys->split_l.realp[i] = sys->time_l[2 * i];
        sys->split_l.imagp[i] = sys->time_l[2 * i + 1];
        sys->split_r.realp[i] = sys->time_r[2 * i];
        sys->split_r.imagp[i] = sys->time_r[2 * i + 1];
    }

    /* 3. Forward real FFT via vDSP */
    vDSP_fft_zrip( sys->fft_setup, &sys->split_l, 1, sys->log2n, FFT_FORWARD );
    vDSP_fft_zrip( sys->fft_setup, &sys->split_r, 1, sys->log2n, FFT_FORWARD );

    /* vDSP forward real FFT has an intrinsic factor of 2: scale by 0.5 to obtain true spectra */
    const float fwd_scale = 0.5f;
    vDSP_vsmul( sys->split_l.realp, 1, &fwd_scale, sys->split_l.realp, 1, half_n );
    vDSP_vsmul( sys->split_l.imagp, 1, &fwd_scale, sys->split_l.imagp, 1, half_n );
    vDSP_vsmul( sys->split_r.realp, 1, &fwd_scale, sys->split_r.realp, 1, half_n );
    vDSP_vsmul( sys->split_r.imagp, 1, &fwd_scale, sys->split_r.imagp, 1, half_n );

    /* 4. Recursive smoothing across frames (beta = 0.7) and raw centre similarity mask */
    /* In vDSP packing: DC is realp[0] (imag = 0), Nyquist is imagp[0] (imag = 0). */
    for( unsigned k = 0; k <= half_n; k++ )
    {
        float lr, li, rr, ri;
        if( k == 0 )
        {
            lr = sys->split_l.realp[0];
            li = 0.0f;
            rr = sys->split_r.realp[0];
            ri = 0.0f;
        }
        else if( k == half_n )
        {
            lr = sys->split_l.imagp[0];
            li = 0.0f;
            rr = sys->split_r.imagp[0];
            ri = 0.0f;
        }
        else
        {
            lr = sys->split_l.realp[k];
            li = sys->split_l.imagp[k];
            rr = sys->split_r.realp[k];
            ri = sys->split_r.imagp[k];
        }

        float mag_l_sq = lr * lr + li * li;
        float mag_r_sq = rr * rr + ri * ri;
        float cross_r  = lr * rr + li * ri;
        float cross_i  = li * rr - lr * ri;

        sys->p_ll[k]   = 0.7f * sys->p_ll[k]   + 0.3f * mag_l_sq;
        sys->p_rr[k]   = 0.7f * sys->p_rr[k]   + 0.3f * mag_r_sq;
        sys->p_lr_r[k] = 0.7f * sys->p_lr_r[k] + 0.3f * cross_r;
        sys->p_lr_i[k] = 0.7f * sys->p_lr_i[k] + 0.3f * cross_i;

        float abs_plr = sqrtf( sys->p_lr_r[k] * sys->p_lr_r[k] + sys->p_lr_i[k] * sys->p_lr_i[k] );
        float psi = (2.0f * abs_plr) / (sys->p_ll[k] + sys->p_rr[k] + 1e-12f);
        if( psi > 1.0f )
            psi = 1.0f;

        sys->raw_mask[k] = psi * psi;
    }

    /* 5. 3-bin moving average frequency smoothing */
    sys->smooth_mask[0] = 0.5f * (sys->raw_mask[0] + sys->raw_mask[1]);
    for( unsigned k = 1; k < half_n; k++ )
    {
        sys->smooth_mask[k] = (sys->raw_mask[k - 1] + sys->raw_mask[k] + sys->raw_mask[k + 1]) * (1.0f / 3.0f);
    }
    sys->smooth_mask[half_n] = 0.5f * (sys->raw_mask[half_n - 1] + sys->raw_mask[half_n]);

    /* 6. Amount & gains: read amount at start of frame */
    float a = atomic_load_explicit( &sys->new_amount, memory_order_relaxed );
    if( a < 0.0f ) a = 0.0f;
    else if( a > 1.0f ) a = 1.0f;

    float gc = db_to_linear( 6.0f * a );
    float g_headroom = db_to_linear( -1.5f * a );
    float gc_eff = gc * g_headroom; /* db_to_linear( 4.5f * a ) */

    /* 7. Centre estimate, residuals, and output spectra per bin */
    for( unsigned k = 0; k <= half_n; k++ )
    {
        float lr, li, rr, ri;
        if( k == 0 )
        {
            lr = sys->split_l.realp[0];
            li = 0.0f;
            rr = sys->split_r.realp[0];
            ri = 0.0f;
        }
        else if( k == half_n )
        {
            lr = sys->split_l.imagp[0];
            li = 0.0f;
            rr = sys->split_r.imagp[0];
            ri = 0.0f;
        }
        else
        {
            lr = sys->split_l.realp[k];
            li = sys->split_l.imagp[k];
            rr = sys->split_r.realp[k];
            ri = sys->split_r.imagp[k];
        }

        float mk = sys->smooth_mask[k];
        float bk = sys->b_k[k];

        /* Ck = mk * bk * (Lk + Rk) / 2 */
        float wk = mk * bk * 0.5f;
        float cr = wk * (lr + rr);
        float ci = wk * (li + ri);

        /* Residuals */
        float lres_r = lr - cr;
        float lres_i = li - ci;
        float rres_r = rr - cr;
        float rres_i = ri - ci;

        /* gr(k) = dB(-4a * bk) * dB(-1.5a) */
        float gr_eff = (bk > 0.0f) ? db_to_linear( -4.0f * a * bk - 1.5f * a ) : g_headroom;

        /* Output spectra */
        float l_out_r = gc_eff * cr + gr_eff * lres_r;
        float l_out_i = gc_eff * ci + gr_eff * lres_i;
        float r_out_r = gc_eff * cr + gr_eff * rres_r;
        float r_out_i = gc_eff * ci + gr_eff * rres_i;

        if( k == 0 )
        {
            sys->split_l.realp[0] = l_out_r;
            sys->split_r.realp[0] = r_out_r;
        }
        else if( k == half_n )
        {
            sys->split_l.imagp[0] = l_out_r;
            sys->split_r.imagp[0] = r_out_r;
        }
        else
        {
            sys->split_l.realp[k] = l_out_r;
            sys->split_l.imagp[k] = l_out_i;
            sys->split_r.realp[k] = r_out_r;
            sys->split_r.imagp[k] = r_out_i;
        }
    }

    /* 8. Inverse FFT via vDSP */
    vDSP_fft_zrip( sys->fft_setup, &sys->split_l, 1, sys->log2n, FFT_INVERSE );
    vDSP_fft_zrip( sys->fft_setup, &sys->split_r, 1, sys->log2n, FFT_INVERSE );

    /* Pack split complex back into time domain */
    for( unsigned i = 0; i < half_n; i++ )
    {
        sys->time_l[2 * i]     = sys->split_l.realp[i];
        sys->time_l[2 * i + 1] = sys->split_l.imagp[i];
        sys->time_r[2 * i]     = sys->split_r.realp[i];
        sys->time_r[2 * i + 1] = sys->split_r.imagp[i];
    }

    /* 9. Synthesis window and scale: synth_window[i] = window[i] / (1.5 * n_fft) */
    vDSP_vmul( sys->time_l, 1, sys->synth_window, 1, sys->time_l, 1, n_fft );
    vDSP_vmul( sys->time_r, 1, sys->synth_window, 1, sys->time_r, 1, n_fft );

    /* 10. Overlap-add into accumulation buffer */
    vDSP_vadd( sys->ola_l, 1, sys->time_l, 1, sys->ola_l, 1, n_fft );
    vDSP_vadd( sys->ola_r, 1, sys->time_r, 1, sys->ola_r, 1, n_fft );

    /* 11. Push hop completed samples to output FIFO */
    for( unsigned i = 0; i < hop; i++ )
    {
        sys->fifo_out_l[sys->out_write_pos & FIFO_MASK] = sys->ola_l[i];
        sys->fifo_out_r[sys->out_write_pos & FIFO_MASK] = sys->ola_r[i];
        sys->out_write_pos++;
    }

    /* 12. Shift overlap-add buffer left by hop, zeroing the new tail */
    memmove( sys->ola_l, sys->ola_l + hop, (n_fft - hop) * sizeof(float) );
    memset( sys->ola_l + n_fft - hop, 0, hop * sizeof(float) );
    memmove( sys->ola_r, sys->ola_r + hop, (n_fft - hop) * sizeof(float) );
    memset( sys->ola_r + n_fft - hop, 0, hop * sizeof(float) );

    /* 13. Advance input FIFO read pointer by hop */
    sys->in_read_pos += hop;
}

static void dialogue_compute_targets( maclc_dialogue_sys_t *sys, float a );

static void dialogue_process_mode_b( maclc_dialogue_sys_t *sys, float *buf, unsigned frames )
{
    const unsigned channels = sys->channels;
    const int idx_l = sys->idx_l;
    const int idx_r = sys->idx_r;

    while( frames > 0 )
    {
        unsigned chunk = (frames > 4096) ? 4096 : frames;

        /* Push chunk samples of L and R into input FIFO */
        for( unsigned k = 0; k < chunk; k++ )
        {
            const float *frame = buf + k * channels;
            sys->fifo_in_l[sys->in_write_pos & FIFO_MASK] = frame[idx_l];
            sys->fifo_in_r[sys->in_write_pos & FIFO_MASK] = frame[idx_r];
            sys->in_write_pos++;
        }

        /* Process STFT frames while at least n_fft samples are available */
        while( (sys->in_write_pos - sys->in_read_pos) >= sys->n_fft )
        {
            dialogue_process_stft_frame( sys );
        }

        /* Pull chunk samples of L and R from output FIFO into buf */
        for( unsigned k = 0; k < chunk; k++ )
        {
            float *frame = buf + k * channels;
            frame[idx_l] = sys->fifo_out_l[sys->out_read_pos & FIFO_MASK];
            frame[idx_r] = sys->fifo_out_r[sys->out_read_pos & FIFO_MASK];
            sys->out_read_pos++;
        }

        /* Delay and scale any other channels (e.g. LFE, rear) */
        float a = atomic_load_explicit( &sys->new_amount, memory_order_relaxed );
        if( a < 0.0f ) a = 0.0f;
        else if( a > 1.0f ) a = 1.0f;
        dialogue_compute_targets( sys, a );

        for( unsigned k = 0; k < chunk; k++ )
        {
            float *frame = buf + k * channels;
            for( unsigned ch = 0; ch < channels; ch++ )
            {
                if( (int)ch == idx_l || (int)ch == idx_r )
                    continue;

                float in_val = frame[ch];
                unsigned pos = sys->delay_pos[ch];
                float out_val = sys->delay_line[ch] ? sys->delay_line[ch][pos] : in_val;
                if( sys->delay_line[ch] )
                    sys->delay_line[ch][pos] = in_val;

                frame[ch] = out_val * sys->target_gains[ch];
                pos++;
                if( pos >= sys->latency )
                    pos = 0;
                sys->delay_pos[ch] = pos;
            }
        }

        buf += chunk * channels;
        frames -= chunk;
    }
}

/*****************************************************************************
 * Lifecycle: flush and destroy
 *****************************************************************************/

/**
 * dialogue_destroy: releases all resources allocated for dialogue filtering,
 * including vDSP FFT setups, STFT analysis/synthesis buffers, FIFO ring buffers,
 * and multi-channel delay lines.
 */
static void dialogue_destroy( maclc_dialogue_sys_t *sys )
{
    if( !sys )
        return;

    if( sys->fft_setup )
    {
        vDSP_destroy_fftsetup( sys->fft_setup );
        sys->fft_setup = NULL;
    }

    free( sys->window );
    sys->window = NULL;
    free( sys->synth_window );
    sys->synth_window = NULL;
    free( sys->b_k );
    sys->b_k = NULL;

    free( sys->p_ll );
    sys->p_ll = NULL;
    free( sys->p_rr );
    sys->p_rr = NULL;
    free( sys->p_lr_r );
    sys->p_lr_r = NULL;
    free( sys->p_lr_i );
    sys->p_lr_i = NULL;

    free( sys->raw_mask );
    sys->raw_mask = NULL;
    free( sys->smooth_mask );
    sys->smooth_mask = NULL;

    free( sys->split_l.realp );
    sys->split_l.realp = NULL;
    free( sys->split_l.imagp );
    sys->split_l.imagp = NULL;
    free( sys->split_r.realp );
    sys->split_r.realp = NULL;
    free( sys->split_r.imagp );
    sys->split_r.imagp = NULL;

    free( sys->time_l );
    sys->time_l = NULL;
    free( sys->time_r );
    sys->time_r = NULL;
    free( sys->ola_l );
    sys->ola_l = NULL;
    free( sys->ola_r );
    sys->ola_r = NULL;

    free( sys->fifo_in_l );
    sys->fifo_in_l = NULL;
    free( sys->fifo_in_r );
    sys->fifo_in_r = NULL;
    free( sys->fifo_out_l );
    sys->fifo_out_l = NULL;
    free( sys->fifo_out_r );
    sys->fifo_out_r = NULL;

    for( unsigned ch = 0; ch < AOUT_CHAN_MAX; ch++ )
    {
        free( sys->delay_line[ch] );
        sys->delay_line[ch] = NULL;
    }
}

static void dialogue_flush( maclc_dialogue_sys_t *sys )
{
    for( unsigned i = 0; i < AOUT_CHAN_MAX; i++ )
    {
        sys->bq_state[i].s1 = 0.0;
        sys->bq_state[i].s2 = 0.0;
    }

    if( sys->mode == DIALOGUE_MODE_B )
    {
        sys->in_read_pos = 0;
        sys->in_write_pos = 0;
        sys->out_read_pos = 0;
        sys->out_write_pos = 0;

        if( sys->fifo_in_l )
            memset( sys->fifo_in_l, 0, FIFO_CAPACITY * sizeof(float) );
        if( sys->fifo_in_r )
            memset( sys->fifo_in_r, 0, FIFO_CAPACITY * sizeof(float) );
        if( sys->fifo_out_l )
            memset( sys->fifo_out_l, 0, FIFO_CAPACITY * sizeof(float) );
        if( sys->fifo_out_r )
            memset( sys->fifo_out_r, 0, FIFO_CAPACITY * sizeof(float) );
        if( sys->ola_l )
            memset( sys->ola_l, 0, sys->n_fft * sizeof(float) );
        if( sys->ola_r )
            memset( sys->ola_r, 0, sys->n_fft * sizeof(float) );

        const unsigned half_n = sys->n_fft / 2;
        if( sys->p_ll )
            memset( sys->p_ll, 0, (half_n + 1) * sizeof(float) );
        if( sys->p_rr )
            memset( sys->p_rr, 0, (half_n + 1) * sizeof(float) );
        if( sys->p_lr_r )
            memset( sys->p_lr_r, 0, (half_n + 1) * sizeof(float) );
        if( sys->p_lr_i )
            memset( sys->p_lr_i, 0, (half_n + 1) * sizeof(float) );

        for( unsigned ch = 0; ch < AOUT_CHAN_MAX; ch++ )
        {
            if( sys->delay_line[ch] )
                memset( sys->delay_line[ch], 0, sys->latency * sizeof(float) );
            sys->delay_pos[ch] = 0;
        }

        /* Prime output FIFO with latency (N - H) zeros */
        if( sys->fifo_out_l && sys->fifo_out_r )
        {
            for( unsigned i = 0; i < sys->latency; i++ )
            {
                sys->fifo_out_l[sys->out_write_pos & FIFO_MASK] = 0.0f;
                sys->fifo_out_r[sys->out_write_pos & FIFO_MASK] = 0.0f;
                sys->out_write_pos++;
            }
        }
    }
}

static void dialogue_compute_targets( maclc_dialogue_sys_t *sys, float a )
{
    if( a < 0.0f ) a = 0.0f;
    else if( a > 1.0f ) a = 1.0f;

    if( sys->mode == DIALOGUE_MODE_A )
    {
        if( a == 0.0f )
        {
            sys->target_gain_m = 1.0f;
            sys->target_gain_s = 1.0f;
            for( unsigned ch = 0; ch < sys->channels; ch++ )
                sys->target_gains[ch] = 1.0f;

            biquad_compute_peaking( &sys->bq_coeffs, 2500.0, 0.7, 0.0, (double)sys->rate );
            return;
        }

        float gain_c    = db_to_linear( 3.5f * a );   /* +5a - 1.5a */
        float gain_lr   = db_to_linear( -3.5f * a );  /* -2a - 1.5a */
        float gain_surr = db_to_linear( -4.5f * a );  /* -3a - 1.5a */
        float gain_lfe  = db_to_linear( -6.5f * a );  /* -5a - 1.5a */

        for( unsigned ch = 0; ch < sys->channels; ch++ )
        {
            if( (int)ch == sys->idx_c )
                sys->target_gains[ch] = gain_c;
            else if( (int)ch == sys->idx_l || (int)ch == sys->idx_r )
                sys->target_gains[ch] = gain_lr;
            else if( (int)ch == sys->idx_lfe )
                sys->target_gains[ch] = gain_lfe;
            else
                sys->target_gains[ch] = gain_surr;
        }

        biquad_compute_peaking( &sys->bq_coeffs, 2500.0, 0.7, 3.0 * (double)a, (double)sys->rate );
    }
    else if( sys->mode == DIALOGUE_MODE_B )
    {
        float gain_rear = db_to_linear( -5.0f * a );
        float gain_lfe  = db_to_linear( -7.0f * a );

        for( unsigned ch = 0; ch < sys->channels; ch++ )
        {
            if( (int)ch == sys->idx_lfe )
                sys->target_gains[ch] = gain_lfe;
            else if( (int)ch != sys->idx_l && (int)ch != sys->idx_r )
                sys->target_gains[ch] = gain_rear;
            else
                sys->target_gains[ch] = 1.0f;
        }
    }
    else /* DIALOGUE_MODE_C */
    {
        if( a == 0.0f )
        {
            sys->target_gain_m = 1.0f;
            sys->target_gain_s = 1.0f;
            for( unsigned ch = 0; ch < sys->channels; ch++ )
                sys->target_gains[ch] = 1.0f;

            biquad_compute_peaking( &sys->bq_coeffs, 2500.0, 0.7, 0.0, (double)sys->rate );
            return;
        }

        float gain_c = db_to_linear( -2.0f * a );
        for( unsigned ch = 0; ch < sys->channels; ch++ )
            sys->target_gains[ch] = gain_c;

        biquad_compute_peaking( &sys->bq_coeffs, 2500.0, 0.7, 5.0 * (double)a, (double)sys->rate );
    }
}

static int dialogue_init( maclc_dialogue_sys_t *sys, float rate,
                          unsigned channels, uint32_t physical_channels,
                          float initial_amount )
{
    memset( sys, 0, sizeof(*sys) );
    sys->rate = rate;
    sys->channels = channels;
    sys->physical_channels = physical_channels;

    if( initial_amount < 0.0f ) initial_amount = 0.0f;
    else if( initial_amount > 1.0f ) initial_amount = 1.0f;

    atomic_init( &sys->new_amount, initial_amount );
    sys->prev_amount = initial_amount;

    sys->idx_c = -1;
    sys->idx_l = -1;
    sys->idx_r = -1;
    sys->idx_lfe = -1;

    unsigned current_idx = 0;
    for( int i = 0; pi_vlc_chan_order_wg4[i] != 0; i++ )
    {
        uint32_t chan = pi_vlc_chan_order_wg4[i];
        if( (physical_channels & chan) != 0 )
        {
            if( chan == AOUT_CHAN_CENTER )
                sys->idx_c = (int)current_idx;
            else if( chan == AOUT_CHAN_LEFT )
                sys->idx_l = (int)current_idx;
            else if( chan == AOUT_CHAN_RIGHT )
                sys->idx_r = (int)current_idx;
            else if( chan == AOUT_CHAN_LFE )
                sys->idx_lfe = (int)current_idx;

            current_idx++;
        }
    }

    if( sys->idx_c >= 0 && channels >= 3 )
        sys->mode = DIALOGUE_MODE_A;
    else if( sys->idx_l >= 0 && sys->idx_r >= 0 && sys->idx_c < 0 )
        sys->mode = DIALOGUE_MODE_B;
    else
        sys->mode = DIALOGUE_MODE_C;

    dialogue_compute_targets( sys, initial_amount );

    for( unsigned ch = 0; ch < channels; ch++ )
        sys->current_gains[ch] = sys->target_gains[ch];
    sys->current_gain_m = sys->target_gain_m;
    sys->current_gain_s = sys->target_gain_s;

    if( sys->mode == DIALOGUE_MODE_B )
    {
        sys->n_fft = (rate <= 64000.0f) ? 1024 : 2048;
        sys->log2n = (rate <= 64000.0f) ? 10 : 11;
        sys->hop = sys->n_fft / 4;
        sys->latency = sys->n_fft - sys->hop;

        sys->fft_setup = vDSP_create_fftsetup( sys->log2n, FFT_RADIX2 );
        if( !sys->fft_setup )
        {
            dialogue_destroy( sys );
            return -1;
        }

        const unsigned n_fft = sys->n_fft;
        const unsigned half_n = n_fft / 2;

        sys->window       = malloc( n_fft * sizeof(float) );
        sys->synth_window = malloc( n_fft * sizeof(float) );
        sys->b_k          = malloc( (half_n + 1) * sizeof(float) );
        sys->p_ll         = calloc( half_n + 1, sizeof(float) );
        sys->p_rr         = calloc( half_n + 1, sizeof(float) );
        sys->p_lr_r       = calloc( half_n + 1, sizeof(float) );
        sys->p_lr_i       = calloc( half_n + 1, sizeof(float) );
        sys->raw_mask     = malloc( (half_n + 1) * sizeof(float) );
        sys->smooth_mask  = malloc( (half_n + 1) * sizeof(float) );

        sys->split_l.realp = malloc( half_n * sizeof(float) );
        sys->split_l.imagp = malloc( half_n * sizeof(float) );
        sys->split_r.realp = malloc( half_n * sizeof(float) );
        sys->split_r.imagp = malloc( half_n * sizeof(float) );

        sys->time_l       = malloc( n_fft * sizeof(float) );
        sys->time_r       = malloc( n_fft * sizeof(float) );
        sys->ola_l        = calloc( n_fft, sizeof(float) );
        sys->ola_r        = calloc( n_fft, sizeof(float) );

        sys->fifo_in_l    = calloc( FIFO_CAPACITY, sizeof(float) );
        sys->fifo_in_r    = calloc( FIFO_CAPACITY, sizeof(float) );
        sys->fifo_out_l   = calloc( FIFO_CAPACITY, sizeof(float) );
        sys->fifo_out_r   = calloc( FIFO_CAPACITY, sizeof(float) );

        for( unsigned ch = 0; ch < channels; ch++ )
        {
            if( (int)ch != sys->idx_l && (int)ch != sys->idx_r )
            {
                sys->delay_line[ch] = calloc( sys->latency, sizeof(float) );
                if( !sys->delay_line[ch] )
                {
                    dialogue_destroy( sys );
                    return -1;
                }
            }
        }

        if( !sys->window || !sys->synth_window || !sys->b_k ||
            !sys->p_ll || !sys->p_rr || !sys->p_lr_r || !sys->p_lr_i ||
            !sys->raw_mask || !sys->smooth_mask ||
            !sys->split_l.realp || !sys->split_l.imagp ||
            !sys->split_r.realp || !sys->split_r.imagp ||
            !sys->time_l || !sys->time_r || !sys->ola_l || !sys->ola_r ||
            !sys->fifo_in_l || !sys->fifo_in_r ||
            !sys->fifo_out_l || !sys->fifo_out_r )
        {
            dialogue_destroy( sys );
            return -1;
        }

        /* Compute analysis and scaled synthesis Hann windows (periodic) */
        for( unsigned n = 0; n < n_fft; n++ )
        {
            double w = 0.5 - 0.5 * cos( 2.0 * M_PI * (double)n / (double)n_fft );
            sys->window[n] = (float)w;
            sys->synth_window[n] = (float)(w / (1.5 * (double)n_fft));
        }

        /* Precompute speech band weights bk */
        for( unsigned k = 0; k <= half_n; k++ )
        {
            float f = (float)k * (sys->rate / (float)n_fft);
            if( f < 150.0f )
                sys->b_k[k] = 0.0f;
            else if( f < 250.0f )
            {
                float t = (f - 150.0f) / 100.0f;
                sys->b_k[k] = 0.5f - 0.5f * cosf( (float)M_PI * t );
            }
            else if( f <= 5000.0f )
                sys->b_k[k] = 1.0f;
            else if( f < 8000.0f )
            {
                float t = (f - 5000.0f) / 3000.0f;
                sys->b_k[k] = 0.5f + 0.5f * cosf( (float)M_PI * t );
            }
            else
                sys->b_k[k] = 0.0f;
        }
    }

    dialogue_flush( sys );
    return 0;
}

static inline void dialogue_set_amount( maclc_dialogue_sys_t *sys, float amount )
{
    if( amount < 0.0f ) amount = 0.0f;
    else if( amount > 1.0f ) amount = 1.0f;
    atomic_store_explicit( &sys->new_amount, amount, memory_order_relaxed );
}

static void dialogue_process( maclc_dialogue_sys_t *sys, float *buf, unsigned frames )
{
    if( unlikely( frames == 0 ) )
        return;

    if( sys->mode == DIALOGUE_MODE_B )
    {
        dialogue_process_mode_b( sys, buf, frames );
        return;
    }

    float a = atomic_load_explicit( &sys->new_amount, memory_order_relaxed );
    if( a < 0.0f ) a = 0.0f;
    else if( a > 1.0f ) a = 1.0f;

    if( a == 0.0f && sys->prev_amount == 0.0f )
        return;

    bool ramping = ( a != sys->prev_amount );
    if( ramping )
        dialogue_compute_targets( sys, a );

    const unsigned channels = sys->channels;

    if( sys->mode == DIALOGUE_MODE_A )
    {
        const int idx_c = sys->idx_c;
        if( !ramping )
        {
            for( unsigned k = 0; k < frames; k++ )
            {
                float *frame = buf + k * channels;
                frame[idx_c] = biquad_process( &sys->bq_coeffs, &sys->bq_state[idx_c], frame[idx_c] );
                for( unsigned ch = 0; ch < channels; ch++ )
                    frame[ch] *= sys->target_gains[ch];
            }
        }
        else
        {
            const float inv_frames = 1.0f / (float)frames;
            for( unsigned k = 0; k < frames; k++ )
            {
                float *frame = buf + k * channels;
                float t = (float)(k + 1) * inv_frames;

                frame[idx_c] = biquad_process( &sys->bq_coeffs, &sys->bq_state[idx_c], frame[idx_c] );
                for( unsigned ch = 0; ch < channels; ch++ )
                {
                    float g = sys->current_gains[ch] + t * (sys->target_gains[ch] - sys->current_gains[ch]);
                    frame[ch] *= g;
                }
            }
        }
    }
    else /* DIALOGUE_MODE_C */
    {
        if( !ramping )
        {
            for( unsigned k = 0; k < frames; k++ )
            {
                float *frame = buf + k * channels;
                for( unsigned ch = 0; ch < channels; ch++ )
                {
                    float val = biquad_process( &sys->bq_coeffs, &sys->bq_state[ch], frame[ch] );
                    frame[ch] = val * sys->target_gains[ch];
                }
            }
        }
        else
        {
            const float inv_frames = 1.0f / (float)frames;
            for( unsigned k = 0; k < frames; k++ )
            {
                float *frame = buf + k * channels;
                float t = (float)(k + 1) * inv_frames;
                for( unsigned ch = 0; ch < channels; ch++ )
                {
                    float val = biquad_process( &sys->bq_coeffs, &sys->bq_state[ch], frame[ch] );
                    float g = sys->current_gains[ch] + t * (sys->target_gains[ch] - sys->current_gains[ch]);
                    frame[ch] = val * g;
                }
            }
        }
    }

    if( ramping )
    {
        for( unsigned ch = 0; ch < channels; ch++ )
            sys->current_gains[ch] = sys->target_gains[ch];
        sys->current_gain_m = sys->target_gain_m;
        sys->current_gain_s = sys->target_gain_s;
        sys->prev_amount = a;

        if( a == 0.0f )
            dialogue_flush( sys );
    }
}

#ifndef MACLC_DIALOGUE_NO_MODULE

/*****************************************************************************
 * Local prototypes
 *****************************************************************************/
static int  Open ( vlc_object_t * );
static void Close( filter_t * );
static void Flush( filter_t * );
static block_t *DoWork( filter_t *, block_t * );
static int AmountCallback( vlc_object_t *, char const *, vlc_value_t,
                           vlc_value_t, void * );

/*****************************************************************************
 * Module descriptor
 *****************************************************************************/
vlc_module_begin()
    set_shortname(N_("Dialogue"))
    set_description(N_("Dialogue boost"))
    set_capability("audio filter", 0)
    set_subcategory(SUBCAT_AUDIO_AFILTER)
    add_float_with_range("maclc-dialogue-amount", 0.6f, 0.0f, 1.0f,
                         N_("Dialogue boost amount"),
                         N_("How much speech is raised over music and effects (0 = off)."))
    add_shortcut("maclc_dialogue")
    set_callback(Open)
vlc_module_end()

/*****************************************************************************
 * Callback for dialogue amount changes
 *****************************************************************************/
static int AmountCallback( vlc_object_t *p_this, char const *psz_var,
                           vlc_value_t oldval, vlc_value_t newval,
                           void *p_data )
{
    VLC_UNUSED(p_this);
    VLC_UNUSED(psz_var);
    VLC_UNUSED(oldval);
    maclc_dialogue_sys_t *sys = p_data;
    dialogue_set_amount( sys, newval.f_float );
    return VLC_SUCCESS;
}

/*****************************************************************************
 * Flush: zero all states
 *****************************************************************************/
static void Flush( filter_t *p_filter )
{
    filter_sys_t *sys = p_filter->p_sys;
    dialogue_flush( sys );
}

/*****************************************************************************
 * Close: release resources and deregister callbacks
 *****************************************************************************/
static void Close( filter_t *p_filter )
{
    filter_sys_t *sys = p_filter->p_sys;
    if( !sys )
        return;

    vlc_object_t *p_aout = vlc_object_parent( p_filter );
    if( p_aout )
        var_DelCallback( p_aout, "maclc-dialogue-amount", AmountCallback, sys );

    dialogue_destroy( sys );
    free( sys );
}

/*****************************************************************************
 * DoWork: audio processing entry point
 *****************************************************************************/
static block_t *DoWork( filter_t *p_filter, block_t *p_block )
{
    filter_sys_t *sys = p_filter->p_sys;

    if( unlikely( !p_block || p_block->i_nb_samples == 0 ) )
        return p_block;

    dialogue_process( sys, (float *)p_block->p_buffer, p_block->i_nb_samples );
    return p_block;
}

/*****************************************************************************
 * Open: initialize filter
 *****************************************************************************/
static int Open( vlc_object_t *obj )
{
    filter_t *p_filter = (filter_t *)obj;

    if( p_filter->fmt_in.audio.i_physical_channels == 0 )
        return VLC_EGENERIC;

    p_filter->fmt_in.audio.i_format = VLC_CODEC_FL32;
    aout_FormatPrepare( &p_filter->fmt_in.audio );
    p_filter->fmt_out.audio = p_filter->fmt_in.audio;

    unsigned channels = p_filter->fmt_in.audio.i_channels;
    if( channels == 0 || channels > AOUT_CHAN_MAX || p_filter->fmt_in.audio.i_rate == 0 )
        return VLC_EGENERIC;

    vlc_object_t *p_aout = vlc_object_parent( p_filter );
    if( !p_aout )
        return VLC_EGENERIC;

    filter_sys_t *sys = calloc( 1, sizeof(*sys) );
    if( !sys )
        return VLC_ENOMEM;

    var_Create( p_aout, "maclc-dialogue-amount", VLC_VAR_FLOAT | VLC_VAR_DOINHERIT );
    float initial_amount = var_GetFloat( p_aout, "maclc-dialogue-amount" );

    if( dialogue_init( sys, (float)p_filter->fmt_in.audio.i_rate, channels,
                       p_filter->fmt_in.audio.i_physical_channels, initial_amount ) != 0 )
    {
        free( sys );
        return VLC_ENOMEM;
    }

    var_AddCallback( p_aout, "maclc-dialogue-amount", AmountCallback, sys );

    p_filter->p_sys = sys;

    static const struct vlc_filter_operations filter_ops =
    {
        .filter_audio = DoWork,
        .flush = Flush,
        .close = Close,
    };
    p_filter->ops = &filter_ops;

    return VLC_SUCCESS;
}

#endif /* MACLC_DIALOGUE_NO_MODULE */
