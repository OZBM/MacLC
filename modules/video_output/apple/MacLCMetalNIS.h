/*****************************************************************************
 * MacLCMetalNIS.h: NVIDIA Image Scaling on the Metal output
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
 * The scaling and sharpening shader is derived from NVIDIA Image Scaling SDK,
 * distributed under the following licence:
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

#ifndef MACLC_METAL_NIS_H
#define MACLC_METAL_NIS_H

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

NS_ASSUME_NONNULL_BEGIN

/** NVIDIA Image Scaling: 6-tap directional scaler with adaptive sharpening,
 *  on a linear-light RGBA16Float texture that may exceed 1.0. */
@interface MacLCMetalNIS : NSObject

- (nullable instancetype)initWithDevice:(id<MTLDevice>)device;
- (instancetype)init NS_UNAVAILABLE;

/** 0..1, default 0.5 (NVScalerUpdateConfig sharpness). */
@property (nonatomic) float sharpness;

- (nullable id<MTLTexture>)encodeFrom:(id<MTLTexture>)texture
                                width:(NSUInteger)width
                               height:(NSUInteger)height
                        commandBuffer:(id<MTLCommandBuffer>)commandBuffer;

@end

NS_ASSUME_NONNULL_END

#endif
