/* Dump the in-app SDR to HDR curve (maclc_sdr2hdr_curve_point) for the README chart. */
#include <stdio.h>
#include "maclc_sdr2hdr.h"
int main(void)
{
    const float boost = MACLC_SDR2HDR_BOOST_DEFAULT, headroom = 16.0f;
    printf("signal,original,fast,small,large\n");
    for (int i = 0; i <= 200; i++) {
        float s = i / 200.0f;
        float orig = powf(s, 1.961f);
        printf("%.4f,%.5f,%.5f,%.5f,%.5f\n", s, orig,
               maclc_sdr2hdr_curve_point(MACLC_SDR2HDR_FAST, s, boost, 0.0f, headroom, 0.0f),
               maclc_sdr2hdr_curve_point(MACLC_SDR2HDR_BALANCED, s, boost, 0.0f, headroom, 0.0f),
               maclc_sdr2hdr_curve_point(MACLC_SDR2HDR_BALANCED, s, boost, 0.0f, headroom, MACLC_SDR2HDR_AREA_HIGH));
    }
    return 0;
}
