/*****************************************************************************
 * MacLCMetalNIS.m: NVIDIA Image Scaling on the Metal output
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
 *****************************************************************************
 * The NVScaler kernel, its configuration and its coefficient tables are
 * ported from NIS_Scaler.h and NIS_Config.h of NVIDIA Image Scaling SDK 1.0.3
 * (github.com/NVIDIAGameWorks/NVIDIAImageScaling), distributed under the
 * following licence:
 *
 * The MIT License(MIT)
 *
 * Copyright(c) 2022 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy of
 * this software and associated documentation files(the "Software"), to deal in
 * the Software without restriction, including without limitation the rights to
 * use, copy, modify, merge, publish, distribute, sublicense, and / or sell copies of
 * the Software, and to permit persons to whom the Software is furnished to do so,
 * subject to the following conditions :
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
 * FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.IN NO EVENT SHALL THE AUTHORS OR
 * COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
 * IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
 * CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 *****************************************************************************/

#import "MacLCMetalNIS.h"

/* NVScaler with NIS_HDR_MODE_LINEAR, full precision, no viewport, no NV12:
 * the picture is linear light that may exceed 1.0, which is what NVIDIA's
 * linear HDR mode is made for (luma is sqrt-compressed, range 0..12.5).
 * Threadgroup arrays live in the kernel, as MSL requires, and are passed to
 * the helpers; otherwise the code follows NIS_Scaler.h line by line. */
static NSString * const kNISSource = @R"(
#include <metal_stdlib>
using namespace metal;

#define NIS_BLOCK_WIDTH 32
#define NIS_BLOCK_HEIGHT 24
#define NIS_THREAD_GROUP_SIZE 256
#define NIS_SCALE_INT 1
#define NIS_SCALE_FLOAT 1.0f
#define kHDRCompressionFactor 0.282842712f
#define kPhaseCount 64
#define kFilterSize 6
#define kSupportSize 6
#define kPadSize kSupportSize
#define kTilePitch (NIS_BLOCK_WIDTH + kPadSize)
#define kTileSize (kTilePitch * (NIS_BLOCK_HEIGHT + kPadSize))
#define kEdgeMapPitch (NIS_BLOCK_WIDTH + 2)
#define kEdgeMapSize (kEdgeMapPitch * (NIS_BLOCK_HEIGHT + 2))

struct NISConfig {
    float kDetectRatio, kDetectThres, kMinContrastRatio, kRatioNorm;
    float kContrastBoost, kEps, kSharpStartY, kSharpScaleY;
    float kSharpStrengthMin, kSharpStrengthScale, kSharpLimitMin, kSharpLimitScale;
    float kScaleX, kScaleY, kSrcNormX, kSrcNormY;
};

constant float coef_scale[kPhaseCount][8] = {
        {0.0f,     0.0f,    1.0000f, 0.0f,     0.0f,    0.0f, 0.0f, 0.0f},
        {0.0029f, -0.0127f, 1.0000f, 0.0132f, -0.0034f, 0.0f, 0.0f, 0.0f},
        {0.0063f, -0.0249f, 0.9985f, 0.0269f, -0.0068f, 0.0f, 0.0f, 0.0f},
        {0.0088f, -0.0361f, 0.9956f, 0.0415f, -0.0103f, 0.0005f, 0.0f, 0.0f},
        {0.0117f, -0.0474f, 0.9932f, 0.0562f, -0.0142f, 0.0005f, 0.0f, 0.0f},
        {0.0142f, -0.0576f, 0.9897f, 0.0713f, -0.0181f, 0.0005f, 0.0f, 0.0f},
        {0.0166f, -0.0674f, 0.9844f, 0.0874f, -0.0220f, 0.0010f, 0.0f, 0.0f},
        {0.0186f, -0.0762f, 0.9785f, 0.1040f, -0.0264f, 0.0015f, 0.0f, 0.0f},
        {0.0205f, -0.0850f, 0.9727f, 0.1206f, -0.0308f, 0.0020f, 0.0f, 0.0f},
        {0.0225f, -0.0928f, 0.9648f, 0.1382f, -0.0352f, 0.0024f, 0.0f, 0.0f},
        {0.0239f, -0.1006f, 0.9575f, 0.1558f, -0.0396f, 0.0029f, 0.0f, 0.0f},
        {0.0254f, -0.1074f, 0.9487f, 0.1738f, -0.0439f, 0.0034f, 0.0f, 0.0f},
        {0.0264f, -0.1138f, 0.9390f, 0.1929f, -0.0488f, 0.0044f, 0.0f, 0.0f},
        {0.0278f, -0.1191f, 0.9282f, 0.2119f, -0.0537f, 0.0049f, 0.0f, 0.0f},
        {0.0288f, -0.1245f, 0.9170f, 0.2310f, -0.0581f, 0.0059f, 0.0f, 0.0f},
        {0.0293f, -0.1294f, 0.9058f, 0.2510f, -0.0630f, 0.0063f, 0.0f, 0.0f},
        {0.0303f, -0.1333f, 0.8926f, 0.2710f, -0.0679f, 0.0073f, 0.0f, 0.0f},
        {0.0308f, -0.1367f, 0.8789f, 0.2915f, -0.0728f, 0.0083f, 0.0f, 0.0f},
        {0.0308f, -0.1401f, 0.8657f, 0.3120f, -0.0776f, 0.0093f, 0.0f, 0.0f},
        {0.0313f, -0.1426f, 0.8506f, 0.3330f, -0.0825f, 0.0103f, 0.0f, 0.0f},
        {0.0313f, -0.1445f, 0.8354f, 0.3540f, -0.0874f, 0.0112f, 0.0f, 0.0f},
        {0.0313f, -0.1460f, 0.8193f, 0.3755f, -0.0923f, 0.0122f, 0.0f, 0.0f},
        {0.0313f, -0.1470f, 0.8022f, 0.3965f, -0.0967f, 0.0137f, 0.0f, 0.0f},
        {0.0308f, -0.1479f, 0.7856f, 0.4185f, -0.1016f, 0.0146f, 0.0f, 0.0f},
        {0.0303f, -0.1479f, 0.7681f, 0.4399f, -0.1060f, 0.0156f, 0.0f, 0.0f},
        {0.0298f, -0.1479f, 0.7505f, 0.4614f, -0.1104f, 0.0166f, 0.0f, 0.0f},
        {0.0293f, -0.1470f, 0.7314f, 0.4829f, -0.1147f, 0.0181f, 0.0f, 0.0f},
        {0.0288f, -0.1460f, 0.7119f, 0.5049f, -0.1187f, 0.0190f, 0.0f, 0.0f},
        {0.0278f, -0.1445f, 0.6929f, 0.5264f, -0.1226f, 0.0200f, 0.0f, 0.0f},
        {0.0273f, -0.1431f, 0.6724f, 0.5479f, -0.1260f, 0.0215f, 0.0f, 0.0f},
        {0.0264f, -0.1411f, 0.6528f, 0.5693f, -0.1299f, 0.0225f, 0.0f, 0.0f},
        {0.0254f, -0.1387f, 0.6323f, 0.5903f, -0.1328f, 0.0234f, 0.0f, 0.0f},
        {0.0244f, -0.1357f, 0.6113f, 0.6113f, -0.1357f, 0.0244f, 0.0f, 0.0f},
        {0.0234f, -0.1328f, 0.5903f, 0.6323f, -0.1387f, 0.0254f, 0.0f, 0.0f},
        {0.0225f, -0.1299f, 0.5693f, 0.6528f, -0.1411f, 0.0264f, 0.0f, 0.0f},
        {0.0215f, -0.1260f, 0.5479f, 0.6724f, -0.1431f, 0.0273f, 0.0f, 0.0f},
        {0.0200f, -0.1226f, 0.5264f, 0.6929f, -0.1445f, 0.0278f, 0.0f, 0.0f},
        {0.0190f, -0.1187f, 0.5049f, 0.7119f, -0.1460f, 0.0288f, 0.0f, 0.0f},
        {0.0181f, -0.1147f, 0.4829f, 0.7314f, -0.1470f, 0.0293f, 0.0f, 0.0f},
        {0.0166f, -0.1104f, 0.4614f, 0.7505f, -0.1479f, 0.0298f, 0.0f, 0.0f},
        {0.0156f, -0.1060f, 0.4399f, 0.7681f, -0.1479f, 0.0303f, 0.0f, 0.0f},
        {0.0146f, -0.1016f, 0.4185f, 0.7856f, -0.1479f, 0.0308f, 0.0f, 0.0f},
        {0.0137f, -0.0967f, 0.3965f, 0.8022f, -0.1470f, 0.0313f, 0.0f, 0.0f},
        {0.0122f, -0.0923f, 0.3755f, 0.8193f, -0.1460f, 0.0313f, 0.0f, 0.0f},
        {0.0112f, -0.0874f, 0.3540f, 0.8354f, -0.1445f, 0.0313f, 0.0f, 0.0f},
        {0.0103f, -0.0825f, 0.3330f, 0.8506f, -0.1426f, 0.0313f, 0.0f, 0.0f},
        {0.0093f, -0.0776f, 0.3120f, 0.8657f, -0.1401f, 0.0308f, 0.0f, 0.0f},
        {0.0083f, -0.0728f, 0.2915f, 0.8789f, -0.1367f, 0.0308f, 0.0f, 0.0f},
        {0.0073f, -0.0679f, 0.2710f, 0.8926f, -0.1333f, 0.0303f, 0.0f, 0.0f},
        {0.0063f, -0.0630f, 0.2510f, 0.9058f, -0.1294f, 0.0293f, 0.0f, 0.0f},
        {0.0059f, -0.0581f, 0.2310f, 0.9170f, -0.1245f, 0.0288f, 0.0f, 0.0f},
        {0.0049f, -0.0537f, 0.2119f, 0.9282f, -0.1191f, 0.0278f, 0.0f, 0.0f},
        {0.0044f, -0.0488f, 0.1929f, 0.9390f, -0.1138f, 0.0264f, 0.0f, 0.0f},
        {0.0034f, -0.0439f, 0.1738f, 0.9487f, -0.1074f, 0.0254f, 0.0f, 0.0f},
        {0.0029f, -0.0396f, 0.1558f, 0.9575f, -0.1006f, 0.0239f, 0.0f, 0.0f},
        {0.0024f, -0.0352f, 0.1382f, 0.9648f, -0.0928f, 0.0225f, 0.0f, 0.0f},
        {0.0020f, -0.0308f, 0.1206f, 0.9727f, -0.0850f, 0.0205f, 0.0f, 0.0f},
        {0.0015f, -0.0264f, 0.1040f, 0.9785f, -0.0762f, 0.0186f, 0.0f, 0.0f},
        {0.0010f, -0.0220f, 0.0874f, 0.9844f, -0.0674f, 0.0166f, 0.0f, 0.0f},
        {0.0005f, -0.0181f, 0.0713f, 0.9897f, -0.0576f, 0.0142f, 0.0f, 0.0f},
        {0.0005f, -0.0142f, 0.0562f, 0.9932f, -0.0474f, 0.0117f, 0.0f, 0.0f},
        {0.0005f, -0.0103f, 0.0415f, 0.9956f, -0.0361f, 0.0088f, 0.0f, 0.0f},
        {0.0f, -0.0068f, 0.0269f, 0.9985f, -0.0249f, 0.0063f, 0.0f, 0.0f},
        {0.0f, -0.0034f, 0.0132f, 1.0000f, -0.0127f, 0.0029f, 0.0f, 0.0f}
};

constant float coef_usm[kPhaseCount][8] = {
        {0.0f,      -0.6001f, 1.2002f, -0.6001f,  0.0f,  0.0f, 0.0f, 0.0f},
        {0.0029f, -0.6084f, 1.1987f, -0.5903f, -0.0029f, 0.0f, 0.0f, 0.0f},
        {0.0049f, -0.6147f, 1.1958f, -0.5791f, -0.0068f, 0.0005f, 0.0f, 0.0f},
        {0.0073f, -0.6196f, 1.1890f, -0.5659f, -0.0103f, 0.0f, 0.0f, 0.0f},
        {0.0093f, -0.6235f, 1.1802f, -0.5513f, -0.0151f, 0.0f, 0.0f, 0.0f},
        {0.0112f, -0.6265f, 1.1699f, -0.5352f, -0.0195f, 0.0005f, 0.0f, 0.0f},
        {0.0122f, -0.6270f, 1.1582f, -0.5181f, -0.0259f, 0.0005f, 0.0f, 0.0f},
        {0.0142f, -0.6284f, 1.1455f, -0.5005f, -0.0317f, 0.0005f, 0.0f, 0.0f},
        {0.0156f, -0.6265f, 1.1274f, -0.4790f, -0.0386f, 0.0005f, 0.0f, 0.0f},
        {0.0166f, -0.6235f, 1.1089f, -0.4570f, -0.0454f, 0.0010f, 0.0f, 0.0f},
        {0.0176f, -0.6187f, 1.0879f, -0.4346f, -0.0532f, 0.0010f, 0.0f, 0.0f},
        {0.0181f, -0.6138f, 1.0659f, -0.4102f, -0.0615f, 0.0015f, 0.0f, 0.0f},
        {0.0190f, -0.6069f, 1.0405f, -0.3843f, -0.0698f, 0.0015f, 0.0f, 0.0f},
        {0.0195f, -0.6006f, 1.0161f, -0.3574f, -0.0796f, 0.0020f, 0.0f, 0.0f},
        {0.0200f, -0.5928f, 0.9893f, -0.3286f, -0.0898f, 0.0024f, 0.0f, 0.0f},
        {0.0200f, -0.5820f, 0.9580f, -0.2988f, -0.1001f, 0.0029f, 0.0f, 0.0f},
        {0.0200f, -0.5728f, 0.9292f, -0.2690f, -0.1104f, 0.0034f, 0.0f, 0.0f},
        {0.0200f, -0.5620f, 0.8975f, -0.2368f, -0.1226f, 0.0039f, 0.0f, 0.0f},
        {0.0205f, -0.5498f, 0.8643f, -0.2046f, -0.1343f, 0.0044f, 0.0f, 0.0f},
        {0.0200f, -0.5371f, 0.8301f, -0.1709f, -0.1465f, 0.0049f, 0.0f, 0.0f},
        {0.0195f, -0.5239f, 0.7944f, -0.1367f, -0.1587f, 0.0054f, 0.0f, 0.0f},
        {0.0195f, -0.5107f, 0.7598f, -0.1021f, -0.1724f, 0.0059f, 0.0f, 0.0f},
        {0.0190f, -0.4966f, 0.7231f, -0.0649f, -0.1865f, 0.0063f, 0.0f, 0.0f},
        {0.0186f, -0.4819f, 0.6846f, -0.0288f, -0.1997f, 0.0068f, 0.0f, 0.0f},
        {0.0186f, -0.4668f, 0.6460f, 0.0093f, -0.2144f, 0.0073f, 0.0f, 0.0f},
        {0.0176f, -0.4507f, 0.6055f, 0.0479f, -0.2290f, 0.0083f, 0.0f, 0.0f},
        {0.0171f, -0.4370f, 0.5693f, 0.0859f, -0.2446f, 0.0088f, 0.0f, 0.0f},
        {0.0161f, -0.4199f, 0.5283f, 0.1255f, -0.2598f, 0.0098f, 0.0f, 0.0f},
        {0.0161f, -0.4048f, 0.4883f, 0.1655f, -0.2754f, 0.0103f, 0.0f, 0.0f},
        {0.0151f, -0.3887f, 0.4497f, 0.2041f, -0.2910f, 0.0107f, 0.0f, 0.0f},
        {0.0142f, -0.3711f, 0.4072f, 0.2446f, -0.3066f, 0.0117f, 0.0f, 0.0f},
        {0.0137f, -0.3555f, 0.3672f, 0.2852f, -0.3228f, 0.0122f, 0.0f, 0.0f},
        {0.0132f, -0.3394f, 0.3262f, 0.3262f, -0.3394f, 0.0132f, 0.0f, 0.0f},
        {0.0122f, -0.3228f, 0.2852f, 0.3672f, -0.3555f, 0.0137f, 0.0f, 0.0f},
        {0.0117f, -0.3066f, 0.2446f, 0.4072f, -0.3711f, 0.0142f, 0.0f, 0.0f},
        {0.0107f, -0.2910f, 0.2041f, 0.4497f, -0.3887f, 0.0151f, 0.0f, 0.0f},
        {0.0103f, -0.2754f, 0.1655f, 0.4883f, -0.4048f, 0.0161f, 0.0f, 0.0f},
        {0.0098f, -0.2598f, 0.1255f, 0.5283f, -0.4199f, 0.0161f, 0.0f, 0.0f},
        {0.0088f, -0.2446f, 0.0859f, 0.5693f, -0.4370f, 0.0171f, 0.0f, 0.0f},
        {0.0083f, -0.2290f, 0.0479f, 0.6055f, -0.4507f, 0.0176f, 0.0f, 0.0f},
        {0.0073f, -0.2144f, 0.0093f, 0.6460f, -0.4668f, 0.0186f, 0.0f, 0.0f},
        {0.0068f, -0.1997f, -0.0288f, 0.6846f, -0.4819f, 0.0186f, 0.0f, 0.0f},
        {0.0063f, -0.1865f, -0.0649f, 0.7231f, -0.4966f, 0.0190f, 0.0f, 0.0f},
        {0.0059f, -0.1724f, -0.1021f, 0.7598f, -0.5107f, 0.0195f, 0.0f, 0.0f},
        {0.0054f, -0.1587f, -0.1367f, 0.7944f, -0.5239f, 0.0195f, 0.0f, 0.0f},
        {0.0049f, -0.1465f, -0.1709f, 0.8301f, -0.5371f, 0.0200f, 0.0f, 0.0f},
        {0.0044f, -0.1343f, -0.2046f, 0.8643f, -0.5498f, 0.0205f, 0.0f, 0.0f},
        {0.0039f, -0.1226f, -0.2368f, 0.8975f, -0.5620f, 0.0200f, 0.0f, 0.0f},
        {0.0034f, -0.1104f, -0.2690f, 0.9292f, -0.5728f, 0.0200f, 0.0f, 0.0f},
        {0.0029f, -0.1001f, -0.2988f, 0.9580f, -0.5820f, 0.0200f, 0.0f, 0.0f},
        {0.0024f, -0.0898f, -0.3286f, 0.9893f, -0.5928f, 0.0200f, 0.0f, 0.0f},
        {0.0020f, -0.0796f, -0.3574f, 1.0161f, -0.6006f, 0.0195f, 0.0f, 0.0f},
        {0.0015f, -0.0698f, -0.3843f, 1.0405f, -0.6069f, 0.0190f, 0.0f, 0.0f},
        {0.0015f, -0.0615f, -0.4102f, 1.0659f, -0.6138f, 0.0181f, 0.0f, 0.0f},
        {0.0010f, -0.0532f, -0.4346f, 1.0879f, -0.6187f, 0.0176f, 0.0f, 0.0f},
        {0.0010f, -0.0454f, -0.4570f, 1.1089f, -0.6235f, 0.0166f, 0.0f, 0.0f},
        {0.0005f, -0.0386f, -0.4790f, 1.1274f, -0.6265f, 0.0156f, 0.0f, 0.0f},
        {0.0005f, -0.0317f, -0.5005f, 1.1455f, -0.6284f, 0.0142f, 0.0f, 0.0f},
        {0.0005f, -0.0259f, -0.5181f, 1.1582f, -0.6270f, 0.0122f, 0.0f, 0.0f},
        {0.0005f, -0.0195f, -0.5352f, 1.1699f, -0.6265f, 0.0112f, 0.0f, 0.0f},
        {0.0f, -0.0151f, -0.5513f, 1.1802f, -0.6235f, 0.0093f, 0.0f, 0.0f},
        {0.0f, -0.0103f, -0.5659f, 1.1890f, -0.6196f, 0.0073f, 0.0f, 0.0f},
        {0.0005f, -0.0068f, -0.5791f, 1.1958f, -0.6147f, 0.0049f, 0.0f, 0.0f},
        {0.0f, -0.0029f, -0.5903f, 1.1987f, -0.6084f, 0.0029f, 0.0f, 0.0f}
};

typedef threadgroup float (*Bank)[kFilterSize];

static inline float getY(float3 rgba)
{
    /* max(): NVIDIA assumes non-negative input */
    return sqrt(max(0.2126f * rgba.x + 0.7152f * rgba.y + 0.0722f * rgba.z, 0.0f)) * kHDRCompressionFactor;
}

static inline float getYLinear(float3 rgba)
{
    return 0.2126f * rgba.x + 0.7152f * rgba.y + 0.0722f * rgba.z;
}

static float4 GetEdgeMap(thread const float (&p)[4][4], int i, int j, constant NISConfig &c)
{
    const float g_0 = abs(p[0 + i][0 + j] + p[0 + i][1 + j] + p[0 + i][2 + j] - p[2 + i][0 + j] - p[2 + i][1 + j] - p[2 + i][2 + j]);
    const float g_45 = abs(p[1 + i][0 + j] + p[0 + i][0 + j] + p[0 + i][1 + j] - p[2 + i][1 + j] - p[2 + i][2 + j] - p[1 + i][2 + j]);
    const float g_90 = abs(p[0 + i][0 + j] + p[1 + i][0 + j] + p[2 + i][0 + j] - p[0 + i][2 + j] - p[1 + i][2 + j] - p[2 + i][2 + j]);
    const float g_135 = abs(p[1 + i][0 + j] + p[2 + i][0 + j] + p[2 + i][1 + j] - p[0 + i][1 + j] - p[0 + i][2 + j] - p[1 + i][2 + j]);

    const float g_0_90_max = max(g_0, g_90);
    const float g_0_90_min = min(g_0, g_90);
    const float g_45_135_max = max(g_45, g_135);
    const float g_45_135_min = min(g_45, g_135);

    if (g_0_90_max + g_45_135_max == 0)
        return float4(0, 0, 0, 0);

    const float e_0_90 = min(g_0_90_max / (g_0_90_max + g_45_135_max), 1.0f);
    const float e_45_135 = 1.0f - e_0_90;

    const bool c_0_90 = (g_0_90_max > (g_0_90_min * c.kDetectRatio)) && (g_0_90_max > c.kDetectThres) && (g_0_90_max > g_45_135_min);
    const bool c_45_135 = (g_45_135_max > (g_45_135_min * c.kDetectRatio)) && (g_45_135_max > c.kDetectThres) && (g_45_135_max > g_0_90_min);
    const bool c_g_0_90 = g_0_90_max == g_0;
    const bool c_g_45_135 = g_45_135_max == g_45;

    const float f_e_0_90 = (c_0_90 && c_45_135) ? e_0_90 : 1.0f;
    const float f_e_45_135 = (c_0_90 && c_45_135) ? e_45_135 : 1.0f;

    const float weight_0 = (c_0_90 && c_g_0_90) ? f_e_0_90 : 0.0f;
    const float weight_90 = (c_0_90 && !c_g_0_90) ? f_e_0_90 : 0.0f;
    const float weight_45 = (c_45_135 && c_g_45_135) ? f_e_45_135 : 0.0f;
    const float weight_135 = (c_45_135 && !c_g_45_135) ? f_e_45_135 : 0.0f;

    return float4(weight_0, weight_90, weight_45, weight_135);
}

static void LoadFilterBanksSh(int i0, Bank shCoefScaler, Bank shCoefUSM)
{
    /* kPhaseCount * 2 <= NIS_THREAD_GROUP_SIZE */
    const int i = i0;
    if (i < kPhaseCount * 2) {
        const int phase = i >> 1;
        const int vIdx = i & 1;
        const int filterOffset = vIdx * 4;
        shCoefScaler[phase][filterOffset + 0] = coef_scale[phase][filterOffset + 0];
        shCoefScaler[phase][filterOffset + 1] = coef_scale[phase][filterOffset + 1];
        if (vIdx == 0) {
            shCoefScaler[phase][2] = coef_scale[phase][2];
            shCoefScaler[phase][3] = coef_scale[phase][3];
        }
        shCoefUSM[phase][filterOffset + 0] = coef_usm[phase][filterOffset + 0];
        shCoefUSM[phase][filterOffset + 1] = coef_usm[phase][filterOffset + 1];
        if (vIdx == 0) {
            shCoefUSM[phase][2] = coef_usm[phase][2];
            shCoefUSM[phase][3] = coef_usm[phase][3];
        }
    }
}

static float CalcLTI(float p0, float p1, float p2, float p3, float p4, float p5, int phase_index,
                     constant NISConfig &c)
{
    const bool selector = (phase_index <= kPhaseCount / 2);
    float sel = selector ? p0 : p3;
    const float a_min = min(min(p1, p2), sel);
    const float a_max = max(max(p1, p2), sel);
    sel = selector ? p2 : p5;
    const float b_min = min(min(p3, p4), sel);
    const float b_max = max(max(p3, p4), sel);

    const float a_cont = a_max - a_min;
    const float b_cont = b_max - b_min;

    const float cont_ratio = max(a_cont, b_cont) / (min(a_cont, b_cont) + c.kEps);
    return (1.0f - saturate((cont_ratio - c.kMinContrastRatio) * c.kRatioNorm)) * c.kContrastBoost;
}

static float4 GetInterpEdgeMap(thread const float4 (&edge)[2][2], float phase_frac_x, float phase_frac_y)
{
    const float4 h0 = mix(edge[0][0], edge[0][1], phase_frac_x);
    const float4 h1 = mix(edge[1][0], edge[1][1], phase_frac_x);
    return mix(h0, h1, phase_frac_y);
}

static float EvalPoly6(thread const float (&pxl)[6], int phase_int,
                       Bank shCoefScaler, Bank shCoefUSM, constant NISConfig &c)
{
    float y = 0.f;
    for (int i = 0; i < 6; ++i)
        y += shCoefScaler[phase_int][i] * pxl[i];
    float y_usm = 0.f;
    for (int i = 0; i < 6; ++i)
        y_usm += shCoefUSM[phase_int][i] * pxl[i];

    // let's compute a piece-wise ramp based on luma
    const float y_scale = 1.0f - saturate((y * (1.0f / NIS_SCALE_FLOAT) - c.kSharpStartY) * c.kSharpScaleY);
    // scale the ramp to sharpen as a function of luma
    const float y_sharpness = y_scale * c.kSharpStrengthScale + c.kSharpStrengthMin;
    y_usm *= y_sharpness;
    // scale the ramp to limit USM as a function of luma
    const float y_sharpness_limit = (y_scale * c.kSharpLimitScale + c.kSharpLimitMin) * y;
    y_usm = min(y_sharpness_limit, max(-y_sharpness_limit, y_usm));
    // reduce ringing
    y_usm *= CalcLTI(pxl[0], pxl[1], pxl[2], pxl[3], pxl[4], pxl[5], phase_int, c);

    return y + y_usm;
}

static float FilterNormal(thread const float (&p)[6][6], int phase_x_frac_int, int phase_y_frac_int,
                          Bank shCoefScaler)
{
    float h_acc = 0.0f;
    for (int j = 0; j < 6; ++j) {
        float v_acc = 0.0f;
        for (int i = 0; i < 6; ++i)
            v_acc += p[i][j] * shCoefScaler[phase_y_frac_int][i];
        h_acc += v_acc * shCoefScaler[phase_x_frac_int][j];
    }
    return h_acc;
}

static float AddDirFilters(thread const float (&p)[6][6], float phase_x_frac, float phase_y_frac,
                           int phase_x_frac_int, int phase_y_frac_int, float4 w,
                           Bank shCoefScaler, Bank shCoefUSM, constant NISConfig &c)
{
    float f = 0;
    if (w.x > 0.0f) {
        // 0 deg filter
        float interp0Deg[6];
        for (int i = 0; i < 6; ++i)
            interp0Deg[i] = mix(p[i][2], p[i][3], phase_x_frac);
        f += EvalPoly6(interp0Deg, phase_y_frac_int, shCoefScaler, shCoefUSM, c) * w.x;
    }
    if (w.y > 0.0f) {
        // 90 deg filter
        float interp90Deg[6];
        for (int i = 0; i < 6; ++i)
            interp90Deg[i] = mix(p[2][i], p[3][i], phase_y_frac);
        f += EvalPoly6(interp90Deg, phase_x_frac_int, shCoefScaler, shCoefUSM, c) * w.y;
    }
    if (w.z > 0.0f) {
        // 45 deg filter
        float pphase_b45 = 0.5f + 0.5f * (phase_x_frac - phase_y_frac);

        float temp_interp45Deg[7];
        temp_interp45Deg[1] = mix(p[2][1], p[1][2], pphase_b45);
        temp_interp45Deg[3] = mix(p[3][2], p[2][3], pphase_b45);
        temp_interp45Deg[5] = mix(p[4][3], p[3][4], pphase_b45);
        {
            pphase_b45 = pphase_b45 - 0.5f;
            const float a = (pphase_b45 >= 0.f) ? p[0][2] : p[2][0];
            const float b = (pphase_b45 >= 0.f) ? p[1][3] : p[3][1];
            const float cc = (pphase_b45 >= 0.f) ? p[2][4] : p[4][2];
            const float d = (pphase_b45 >= 0.f) ? p[3][5] : p[5][3];
            temp_interp45Deg[0] = mix(p[1][1], a, abs(pphase_b45));
            temp_interp45Deg[2] = mix(p[2][2], b, abs(pphase_b45));
            temp_interp45Deg[4] = mix(p[3][3], cc, abs(pphase_b45));
            temp_interp45Deg[6] = mix(p[4][4], d, abs(pphase_b45));
        }

        float interp45Deg[6];
        float pphase_p45 = phase_x_frac + phase_y_frac;
        if (pphase_p45 >= 1) {
            for (int i = 0; i < 6; i++)
                interp45Deg[i] = temp_interp45Deg[i + 1];
            pphase_p45 = pphase_p45 - 1;
        } else {
            for (int i = 0; i < 6; i++)
                interp45Deg[i] = temp_interp45Deg[i];
        }
        f += EvalPoly6(interp45Deg, int(pphase_p45 * 64), shCoefScaler, shCoefUSM, c) * w.z;
    }
    if (w.w > 0.0f) {
        // 135 deg filter
        float pphase_b135 = 0.5f * (phase_x_frac + phase_y_frac);

        float temp_interp135Deg[7];
        temp_interp135Deg[1] = mix(p[3][1], p[4][2], pphase_b135);
        temp_interp135Deg[3] = mix(p[2][2], p[3][3], pphase_b135);
        temp_interp135Deg[5] = mix(p[1][3], p[2][4], pphase_b135);
        {
            pphase_b135 = pphase_b135 - 0.5f;
            const float a = (pphase_b135 >= 0.f) ? p[5][2] : p[3][0];
            const float b = (pphase_b135 >= 0.f) ? p[4][3] : p[2][1];
            const float cc = (pphase_b135 >= 0.f) ? p[3][4] : p[1][2];
            const float d = (pphase_b135 >= 0.f) ? p[2][5] : p[0][3];
            temp_interp135Deg[0] = mix(p[4][1], a, abs(pphase_b135));
            temp_interp135Deg[2] = mix(p[3][2], b, abs(pphase_b135));
            temp_interp135Deg[4] = mix(p[2][3], cc, abs(pphase_b135));
            temp_interp135Deg[6] = mix(p[1][4], d, abs(pphase_b135));
        }

        float interp135Deg[6];
        float pphase_p135 = 1 + (phase_x_frac - phase_y_frac);
        if (pphase_p135 >= 1) {
            for (int i = 0; i < 6; ++i)
                interp135Deg[i] = temp_interp135Deg[i + 1];
            pphase_p135 = pphase_p135 - 1;
        } else {
            for (int i = 0; i < 6; ++i)
                interp135Deg[i] = temp_interp135Deg[i];
        }
        f += EvalPoly6(interp135Deg, int(pphase_p135 * 64), shCoefScaler, shCoefUSM, c) * w.w;
    }
    return f;
}

kernel void maclc_nis_scaler(texture2d<float, access::sample> in_texture [[texture(0)]],
                             texture2d<float, access::write> out_texture [[texture(1)]],
                             constant NISConfig &c [[buffer(0)]],
                             uint2 blockIdx [[threadgroup_position_in_grid]],
                             uint threadIdx [[thread_index_in_threadgroup]])
{
    threadgroup float shPixelsY[kTileSize];
    threadgroup float shCoefScaler[kPhaseCount][kFilterSize];
    threadgroup float shCoefUSM[kPhaseCount][kFilterSize];
    threadgroup float4 shEdgeMap[kEdgeMapSize];
    constexpr sampler samplerLinearClamp(coord::normalized, address::clamp_to_edge, filter::linear);

    // Figure out the range of pixels from input image that would be needed to be loaded for this thread-block
    const int dstBlockX = int(NIS_BLOCK_WIDTH * blockIdx.x);
    const int dstBlockY = int(NIS_BLOCK_HEIGHT * blockIdx.y);

    const int srcBlockStartX = int(floor((dstBlockX + 0.5f) * c.kScaleX - 0.5f));
    const int srcBlockStartY = int(floor((dstBlockY + 0.5f) * c.kScaleY - 0.5f));
    const int srcBlockEndX = int(ceil((dstBlockX + NIS_BLOCK_WIDTH + 0.5f) * c.kScaleX - 0.5f));
    const int srcBlockEndY = int(ceil((dstBlockY + NIS_BLOCK_HEIGHT + 0.5f) * c.kScaleY - 0.5f));

    int numTilePixelsX = srcBlockEndX - srcBlockStartX + kSupportSize - 1;
    int numTilePixelsY = srcBlockEndY - srcBlockStartY + kSupportSize - 1;

    // round-up load region to even size since we're loading in 2x2 batches
    numTilePixelsX += numTilePixelsX & 0x1;
    numTilePixelsY += numTilePixelsY & 0x1;
    const int numTilePixels = numTilePixelsX * numTilePixelsY;

    // calculate the equivalent values for the edge map
    const int numEdgeMapPixelsX = numTilePixelsX - kSupportSize + 2;
    const int numEdgeMapPixelsY = numTilePixelsY - kSupportSize + 2;
    const int numEdgeMapPixels = numEdgeMapPixelsX * numEdgeMapPixelsY;

    // fill in input luma tile (shPixelsY) in batches of 2x2 pixels
    for (uint i = threadIdx * 2; i < uint(numTilePixels) >> 1; i += NIS_THREAD_GROUP_SIZE * 2) {
        const uint py = (i / numTilePixelsX) * 2;
        const uint px = i % numTilePixelsX;

        // 0.5 to be in the center of texel
        // - (kSupportSize - 1) / 2 to shift by the kernel support size
        const float kShift = 0.5f - (kSupportSize - 1) / 2;
        const float tx = (srcBlockStartX + int(px) + kShift) * c.kSrcNormX;
        const float ty = (srcBlockStartY + int(py) + kShift) * c.kSrcNormY;
        float p[2][2];
        for (int j = 0; j < 2; j++)
            for (int k = 0; k < 2; k++) {
                const float4 px4 = in_texture.sample(samplerLinearClamp, float2(tx + k * c.kSrcNormX, ty + j * c.kSrcNormY), level(0));
                p[j][k] = getY(px4.xyz);
            }
        const uint idx = py * kTilePitch + px;
        shPixelsY[idx] = p[0][0];
        shPixelsY[idx + 1] = p[0][1];
        shPixelsY[idx + kTilePitch] = p[1][0];
        shPixelsY[idx + kTilePitch + 1] = p[1][1];
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);
    // fill in the edge map of 2x2 pixels
    for (uint i = threadIdx * 2; i < uint(numEdgeMapPixels) >> 1; i += NIS_THREAD_GROUP_SIZE * 2) {
        const uint py = (i / numEdgeMapPixelsX) * 2;
        const uint px = i % numEdgeMapPixelsX;

        const uint edgeMapIdx = py * kEdgeMapPitch + px;

        const uint tileCornerIdx = (py + 1) * kTilePitch + px + 1;
        float p[4][4];
        for (int j = 0; j < 4; j++)
            for (int k = 0; k < 4; k++)
                p[j][k] = shPixelsY[tileCornerIdx + j * kTilePitch + k];

        shEdgeMap[edgeMapIdx] = GetEdgeMap(p, 0, 0, c);
        shEdgeMap[edgeMapIdx + 1] = GetEdgeMap(p, 0, 1, c);
        shEdgeMap[edgeMapIdx + kEdgeMapPitch] = GetEdgeMap(p, 1, 0, c);
        shEdgeMap[edgeMapIdx + kEdgeMapPitch + 1] = GetEdgeMap(p, 1, 1, c);
    }
    LoadFilterBanksSh(int(threadIdx), shCoefScaler, shCoefUSM);
    threadgroup_barrier(mem_flags::mem_threadgroup);

    // output coord within a tile
    const int2 pos = int2(threadIdx % uint(NIS_BLOCK_WIDTH), threadIdx / uint(NIS_BLOCK_WIDTH));
    // x coord inside the output image
    const int dstX = dstBlockX + pos.x;
    // x coord inside the input image
    const float srcX = (0.5f + dstX) * c.kScaleX - 0.5f;
    // nearest integer part
    const int px = int(floor(srcX) - srcBlockStartX);
    // fractional part
    const float fx = srcX - floor(srcX);
    // discretized phase
    const int fx_int = int(fx * kPhaseCount);

    for (int k = 0; k < NIS_BLOCK_WIDTH * NIS_BLOCK_HEIGHT / NIS_THREAD_GROUP_SIZE; ++k) {
        // y coord inside the output image
        const int dstY = dstBlockY + pos.y + k * (NIS_THREAD_GROUP_SIZE / NIS_BLOCK_WIDTH);
        /* the last blocks overhang the picture */
        if (uint(dstX) >= out_texture.get_width() || uint(dstY) >= out_texture.get_height())
            continue;
        // y coord inside the input image
        const float srcY = (0.5f + dstY) * c.kScaleY - 0.5f;
        // nearest integer part
        const int py = int(floor(srcY) - srcBlockStartY);
        // fractional part
        const float fy = srcY - floor(srcY);
        // discretized phase
        const int fy_int = int(fy * kPhaseCount);

        // generate weights for directional filters
        const int startEdgeMapIdx = py * kEdgeMapPitch + px;
        float4 edge[2][2];
        for (int i = 0; i < 2; i++)
            for (int j = 0; j < 2; j++)
                // need to shift edge map sampling since it's a 2x2 centered inside 6x6 grid
                edge[i][j] = shEdgeMap[startEdgeMapIdx + (i * kEdgeMapPitch) + j];
        const float4 w = GetInterpEdgeMap(edge, fx, fy) * NIS_SCALE_INT;

        // load 6x6 support to regs
        const int startTileIdx = py * kTilePitch + px;
        float p[6][6];
        for (int i = 0; i < 6; ++i)
            for (int j = 0; j < 6; ++j)
                p[i][j] = shPixelsY[startTileIdx + i * kTilePitch + j];

        // weigth for luma
        const float baseWeight = NIS_SCALE_FLOAT - w.x - w.y - w.z - w.w;

        // final luma is a weighted product of directional & normal filters
        float opY = 0;
        // get traditional scaler filter output
        opY += FilterNormal(p, fx_int, fy_int, shCoefScaler) * baseWeight;
        // get directional filter bank output
        opY += AddDirFilters(p, fx, fy, fx_int, fy_int, w, shCoefScaler, shCoefUSM, c);

        const float2 coord = float2((srcX + 0.5f) * c.kSrcNormX, (srcY + 0.5f) * c.kSrcNormY);
        // do bilinear tap for chroma upscaling
        float4 op = in_texture.sample(samplerLinearClamp, coord, level(0));

        // NIS_HDR_MODE_LINEAR
        const float kEps = 1e-4f;
        const float kNorm = 1.0f / (NIS_SCALE_FLOAT * kHDRCompressionFactor);
        const float opYN = max(opY, 0.0f) * kNorm;
        const float corr = (opYN * opYN + kEps) / (max(getYLinear(op.xyz), 0.0f) + kEps);
        op.xyz *= corr;
        out_texture.write(float4(max(op.xyz, 0.0f), 1.0f), uint2(dstX, dstY));
    }
}
)";

/* NISConfig as the kernel reads it (the viewport fields are unused) */
typedef struct {
    float kDetectRatio, kDetectThres, kMinContrastRatio, kRatioNorm;
    float kContrastBoost, kEps, kSharpStartY, kSharpScaleY;
    float kSharpStrengthMin, kSharpStrengthScale, kSharpLimitMin, kSharpLimitScale;
    float kScaleX, kScaleY, kSrcNormX, kSrcNormY;
} NISConfig;

/* NVScalerUpdateConfig, NISHDRMode::Linear, whole textures as viewports */
static NISConfig UpdateConfig(float sharpness, float inW, float inH, float outW, float outH)
{
    sharpness = fmaxf(fminf(1.f, sharpness), 0.f);
    const float sharpen_slider = sharpness - 0.5f;
    const float MaxScale = (sharpen_slider >= 0.0f) ? 1.25f : 1.75f;
    const float MinScale = (sharpen_slider >= 0.0f) ? 1.25f : 1.0f;
    const float LimitScale = (sharpen_slider >= 0.0f) ? 1.25f : 1.0f;

    const float kMinContrastRatio = 1.5f;
    const float kMaxContrastRatio = 5.0f;
    const float kSharpStartY = 0.3f;
    const float kSharpEndY = 0.5f;
    const float kSharpStrengthMin = fmaxf(0.0f, 0.4f + sharpen_slider * MinScale * 1.1f);
    const float kSharpStrengthMax = 2.2f + sharpen_slider * MaxScale * 1.8f;
    const float kSharpLimitMin = fmaxf(0.06f, 0.10f + sharpen_slider * LimitScale * 0.28f);
    const float kSharpLimitMax = 0.6f + sharpen_slider * LimitScale * 0.6f;

    return (NISConfig) {
        .kDetectRatio = 2 * 1127.f / 1024.f,
        .kDetectThres = 32.0f / 1024.0f,
        .kMinContrastRatio = kMinContrastRatio,
        .kRatioNorm = 1.0f / (kMaxContrastRatio - kMinContrastRatio),
        .kContrastBoost = 1.0f,
        .kEps = 1.0f / 255.0f,
        .kSharpStartY = kSharpStartY,
        .kSharpScaleY = 1.0f / (kSharpEndY - kSharpStartY),
        .kSharpStrengthMin = kSharpStrengthMin,
        .kSharpStrengthScale = kSharpStrengthMax - kSharpStrengthMin,
        .kSharpLimitMin = kSharpLimitMin,
        .kSharpLimitScale = kSharpLimitMax - kSharpLimitMin,
        .kScaleX = inW / outW,
        .kScaleY = inH / outH,
        .kSrcNormX = 1.f / inW,
        .kSrcNormY = 1.f / inH,
    };
}

@implementation MacLCMetalNIS {
    id<MTLDevice> _device;
    id<MTLComputePipelineState> _scaler;
    id<MTLTexture> _out[2];
    NSUInteger _next;
}

- (instancetype)initWithDevice:(id<MTLDevice>)device
{
    self = [super init];
    if (self == nil)
        return nil;
    NSError *error = nil;
    id<MTLLibrary> library = [device newLibraryWithSource:kNISSource options:nil error:&error];
    if (library == nil) {
        NSLog(@"NIS: %@", error);
        return nil;
    }
    _scaler = [device newComputePipelineStateWithFunction:[library newFunctionWithName:@"maclc_nis_scaler"]
                                                    error:&error];
    if (_scaler == nil || _scaler.maxTotalThreadsPerThreadgroup < 256) {
        NSLog(@"NIS: %@", error);
        return nil;
    }
    _device = device;
    _sharpness = 0.5f;
    return self;
}

static id<MTLTexture> Texture(id<MTLDevice> device, NSUInteger w, NSUInteger h)
{
    MTLTextureDescriptor *td =
        [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA16Float
                                                           width:w height:h mipmapped:NO];
    td.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
    td.storageMode = MTLStorageModePrivate;
    return [device newTextureWithDescriptor:td];
}

- (nullable id<MTLTexture>)encodeFrom:(id<MTLTexture>)texture
                                width:(NSUInteger)width
                               height:(NSUInteger)height
                        commandBuffer:(id<MTLCommandBuffer>)commandBuffer
{
    /* NVIDIA refuses ratios above 2; the kernel stays in bounds for any
     * upscale, so larger ratios are allowed and simply softer */
    if (width < texture.width || height < texture.height)
        return nil;
    if (_out[0] == nil || _out[0].width != width || _out[0].height != height) {
        _out[0] = Texture(_device, width, height);
        _out[1] = Texture(_device, width, height);
        if (_out[0] == nil || _out[1] == nil) {
            _out[0] = nil;
            return nil;
        }
    }
    id<MTLTexture> out = _out[_next];
    _next ^= 1;

    const NISConfig config = UpdateConfig(_sharpness, texture.width, texture.height, width, height);
    id<MTLComputeCommandEncoder> enc = [commandBuffer computeCommandEncoder];
    if (enc == nil)
        return nil;
    [enc setComputePipelineState:_scaler];
    [enc setTexture:texture atIndex:0];
    [enc setTexture:out atIndex:1];
    [enc setBytes:&config length:sizeof(config) atIndex:0];
    [enc dispatchThreadgroups:MTLSizeMake((width + 31) / 32, (height + 23) / 24, 1)
        threadsPerThreadgroup:MTLSizeMake(256, 1, 1)];
    [enc endEncoding];
    return out;
}

@end
