/* generate_silent_joc.c - writes a silent E-AC-3 JOC (Atmos) stream to stdout.
 * Shared bitstream construction from modules/audio_output/apple/atmos_prime.m,
 * generated from ETSI TS 102 366 / TS 103 420 (no third-party binary). */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

/* The silent stream is generated here rather than shipped as an asset. Every
 * bit comes from ETSI TS 102 366 (E-AC-3) and TS 103 420 (object audio); the
 * 5.1 core codes no mantissas and turns dither off, so it decodes to digital
 * silence. The frame header carries the Atmos extension flag, which is what
 * registers Apple's Atmos decoder. The construction follows the Apache-2.0
 * SpatialAudioBridge script, which itself emits the bitstream directly. */

#define ATMOS_FRAME_COUNT   63
#define ATMOS_FRAME_BYTES   3072
#define ATMOS_CHANNELS      5   /* 3/2 with LFE, the core used by JOC streams */
#define ATMOS_BANDWIDTH     60  /* endmant 253, the full bandwidth of a channel */
#define ATMOS_OBJECT_COUNT  16  /* complexity_index_type_a of common DD+ Atmos */

typedef struct
{
    uint8_t *bytes;
    size_t count; /* in bits */
} atmos_bw_t;

static void
atmos_bw_write(atmos_bw_t *bw, unsigned value, unsigned bits)
{
    for (int shift = (int) bits - 1; shift >= 0; --shift)
    {
        if (bw->count % 8 == 0)
            bw->bytes[bw->count / 8] = 0;
        bw->bytes[bw->count / 8] |=
            ((value >> shift) & 1u) << (7 - (bw->count % 8));
        ++bw->count;
    }
}

/* AC-3 CRC: polynomial x^16 + x^15 + x^2 + 1, most significant bit first. */
static unsigned
atmos_crc16(const uint8_t *data, size_t len)
{
    unsigned crc = 0;
    for (size_t i = 0; i < len; ++i)
    {
        crc ^= (unsigned) data[i] << 8;
        for (int bit = 0; bit < 8; ++bit)
            crc = (crc & 0x8000) ? ((crc << 1) ^ 0x8005) & 0xFFFF
                                 : (crc << 1) & 0xFFFF;
    }
    return crc;
}

/* D15 exponent groups that climb from the largest absolute exponent, 15, to
 * the smallest level, 24. Each 7-bit group codes three deltas, offset by 2. */
static void
atmos_exponent_groups(unsigned *deltas, unsigned count)
{
    static const unsigned first[5] = { 2, 2, 2, 2, 1 };
    for (unsigned i = 0; i < count * 3; ++i)
        deltas[i] = i < 5 ? first[i] : 0;
}

static unsigned
atmos_exponent_group(const unsigned *deltas, unsigned index)
{
    return 25 * (deltas[index] + 2) + 5 * (deltas[index + 1] + 2)
         + deltas[index + 2] + 2;
}

static void
atmos_silent_frame(uint8_t *frame)
{
    atmos_bw_t w = { .bytes = frame, .count = 0 };

    /* syncinfo and bsi (TS 102 366 E.1.2.1-2) */
    atmos_bw_write(&w, 0x0B77, 16);
    atmos_bw_write(&w, 0, 2);   /* strmtyp: independent */
    atmos_bw_write(&w, 0, 3);   /* substreamid */
    atmos_bw_write(&w, ATMOS_FRAME_BYTES / 2 - 1, 11); /* frmsiz */
    atmos_bw_write(&w, 0, 2);   /* fscod: 48 kHz */
    atmos_bw_write(&w, 3, 2);   /* numblkscod: six blocks */
    atmos_bw_write(&w, 7, 3);   /* acmod: 3/2 */
    atmos_bw_write(&w, 1, 1);   /* lfeon */
    atmos_bw_write(&w, 16, 5);  /* bsid */
    atmos_bw_write(&w, 27, 5);  /* dialnorm: -27 dBFS */
    atmos_bw_write(&w, 0, 1);   /* compre */
    atmos_bw_write(&w, 0, 1);   /* mixmdate */
    atmos_bw_write(&w, 1, 1);   /* infomdate */
    atmos_bw_write(&w, 0, 3);   /* bsmod: complete main */
    atmos_bw_write(&w, 1, 1);   /* copyrightb */
    atmos_bw_write(&w, 1, 1);   /* origbs */
    atmos_bw_write(&w, 0, 2);   /* dsurexmod: not indicated */
    atmos_bw_write(&w, 0, 1);   /* audprodie */
    atmos_bw_write(&w, 0, 1);   /* sourcefscod */
    atmos_bw_write(&w, 1, 1);   /* addbsie */
    atmos_bw_write(&w, 1, 6);   /* addbsil: two bytes follow */
    atmos_bw_write(&w, 1, 8);   /* reserved 7 bits, flag_ec3_extension_type_a */
    atmos_bw_write(&w, ATMOS_OBJECT_COUNT, 8); /* complexity_index_type_a */

    /* audfrm (E.1.2.3), with the strategy flags of common DD+ Atmos encoders */
    atmos_bw_write(&w, 0, 1);   /* expstre: frame-based exponent strategies */
    atmos_bw_write(&w, 0, 1);   /* ahte */
    atmos_bw_write(&w, 0, 2);   /* snroffststr */
    atmos_bw_write(&w, 0, 1);   /* transproce */
    atmos_bw_write(&w, 0, 1);   /* blkswe */
    atmos_bw_write(&w, 1, 1);   /* dithflage */
    atmos_bw_write(&w, 1, 1);   /* bamode */
    atmos_bw_write(&w, 1, 1);   /* frmfgaincode */
    atmos_bw_write(&w, 0, 1);   /* dbaflde */
    atmos_bw_write(&w, 1, 1);   /* skipflde */
    atmos_bw_write(&w, 0, 1);   /* spxattene */
    atmos_bw_write(&w, 0, 1);   /* cplinu[0] */
    for (unsigned i = 1; i < 6; ++i)
        atmos_bw_write(&w, 0, 1); /* cplstre[blk]: coupling stays off */
    for (unsigned i = 0; i < ATMOS_CHANNELS; ++i)
        atmos_bw_write(&w, 0, 5); /* frmchexpstr: D15, then reuse */
    for (unsigned block = 0; block < 6; ++block)
        atmos_bw_write(&w, block == 0, 1); /* lfeexpstr: D15, then reuse */
    for (unsigned i = 0; i < ATMOS_CHANNELS; ++i)
        atmos_bw_write(&w, 0, 5); /* convexpstr, as frmchexpstr */
    atmos_bw_write(&w, 0, 6);   /* frmcsnroffst */
    atmos_bw_write(&w, 0, 4);   /* frmfsnroffst */
    atmos_bw_write(&w, 0, 1);   /* blkstrtinfoe */

    /* audblk (E.1.2.4) */
    const unsigned end_mantissa = (ATMOS_BANDWIDTH + 12) * 3 + 37;
    const unsigned group_count = (end_mantissa - 1) / 3;
    unsigned *groups = calloc(group_count * 3, sizeof(*groups));
    unsigned *lfe_groups = calloc(2 * 3, sizeof(*lfe_groups));
    if (groups != NULL && lfe_groups != NULL)
    {
        atmos_exponent_groups(groups, group_count);
        atmos_exponent_groups(lfe_groups, 2);

        for (unsigned block = 0; block < 6; ++block)
        {
            for (unsigned i = 0; i < ATMOS_CHANNELS; ++i)
                atmos_bw_write(&w, 0, 1); /* dithflag */
            atmos_bw_write(&w, 0, 1); /* dynrnge */
            atmos_bw_write(&w, 0, 1); /* spxinu in block 0, spxstre afterwards */

            if (block == 0)
            {
                for (unsigned i = 0; i < ATMOS_CHANNELS; ++i)
                    atmos_bw_write(&w, ATMOS_BANDWIDTH, 6); /* chbwcod */
                for (unsigned i = 0; i < ATMOS_CHANNELS; ++i)
                {
                    atmos_bw_write(&w, 15, 4); /* exps[ch][0] */
                    for (unsigned g = 0; g < group_count * 3; g += 3)
                        atmos_bw_write(&w, atmos_exponent_group(groups, g), 7);
                    atmos_bw_write(&w, 0, 2); /* gainrng */
                }
                atmos_bw_write(&w, 15, 4); /* lfeexps[0] */
                for (unsigned g = 0; g < 6; g += 3)
                    atmos_bw_write(&w, atmos_exponent_group(lfe_groups, g), 7);
                atmos_bw_write(&w, 1, 1); /* baie, with the default parameters */
                atmos_bw_write(&w, 2, 2); /* sdcycod */
                atmos_bw_write(&w, 1, 2); /* fdcycod */
                atmos_bw_write(&w, 1, 2); /* sgaincod */
                atmos_bw_write(&w, 2, 2); /* dbpbcod */
                atmos_bw_write(&w, 7, 3); /* floorcod */
            }
            else
                atmos_bw_write(&w, 0, 1); /* baie */

            atmos_bw_write(&w, 0, 1); /* fgaincode */
            atmos_bw_write(&w, 0, 1); /* convsnroffste */
            atmos_bw_write(&w, 0, 1); /* skiple */
        }
    }
    free(groups);
    free(lfe_groups);

    /* auxdata (E.1.2.5) and errorcheck (E.1.2.6) */
    while (w.count < ATMOS_FRAME_BYTES * 8 - 18)
        atmos_bw_write(&w, 0, 1);
    atmos_bw_write(&w, 0, 1); /* auxdatae */
    atmos_bw_write(&w, 0, 1); /* encinfo */

    const unsigned crc = atmos_crc16(frame + 2, ATMOS_FRAME_BYTES - 4);
    frame[ATMOS_FRAME_BYTES - 2] = (uint8_t) (crc >> 8);
    frame[ATMOS_FRAME_BYTES - 1] = (uint8_t) (crc & 0xFF);
}


int main(void)
{
    uint8_t frame[ATMOS_FRAME_BYTES];
    memset(frame, 0, sizeof(frame));
    atmos_silent_frame(frame);
    for (unsigned i = 0; i < ATMOS_FRAME_COUNT; ++i)
        fwrite(frame, 1, sizeof(frame), stdout);
    return 0;
}
