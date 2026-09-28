/*****************************************************************************
 * VLCHDRNetwork.h: the trained grid predictors behind SDR to HDR's High and
 *                  Maximum levels, run with MPSGraph
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

#ifndef VLC_HDR_NETWORK_H
#define VLC_HDR_NETWORK_H

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#import "VLCHDRExpander.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * A small convolutional network that looks at a 256 x 256 thumbnail of the
 * SDR picture and predicts, for every cell of a coarse grid and every
 * intensity bin, the gain the pixels there should get (per colour channel,
 * as a share of log(MACLC_SDR2HDR_P_TRAIN)). It was trained on SDR / HDR
 * pairs rendered from public-domain HDR photographs (Poly Haven, CC0),
 * through the same guided filter and slicing the expander runs, so what it
 * learnt is what plays.
 *
 * The weights live in a `.maclcnn` file: a JSON header naming
 * the architecture and every tensor, then the tensors in half floats. The
 * graph is rebuilt from that description with MPSGraph and encoded straight
 * into the expander's command buffer, so High costs no extra round trip.
 *
 * A `VLCHDRNetwork` serves High, Maximum or both: `-networkSet` below loads
 * whichever files exist and presents them to the expander as one producer.
 */
@interface VLCHDRNetwork : NSObject <VLCHDRGridProducer>

/** Loads the network in `path` for `device`, or returns nil (with the reason
 *  in `error`) if the file is missing, malformed or describes an architecture
 *  this build cannot rebuild. */
+ (nullable instancetype)networkWithContentsOfFile:(NSString *)path
                                            device:(id<MTLDevice>)device
                                             error:(NSError **)error;

/** The architecture name from the file ("high-v1", "max-v1"). */
@property (nonatomic, readonly) NSString *name;

/** Where the weights came from. */
@property (nonatomic, readonly) NSString *path;

/** Which level this network is for (from its name): High or Maximum. */
@property (nonatomic, readonly) enum maclc_sdr2hdr_quality quality;

@end

/**
 * High and Maximum behind one producer: the expander tells it which level
 * the picture is for (`currentQuality`) before asking for the geometry and
 * the prediction. supportsQuality: answers for each level's own network;
 * the outputs run High, and say why, when Maximum's is missing.
 */
@interface VLCHDRNetworkSet : NSObject <VLCHDRGridProducer>

/**
 * Looks for `sdr2hdr-high-v1.maclcnn` and `sdr2hdr-max-v1.maclcnn` in, in
 * order: `userDirectory` (if not nil), ~/Library/Application Support/MacLC/
 * models, and the app bundle's Resources/models. Returns nil when neither
 * network could be loaded; `logger` receives one line per file tried.
 */
+ (nullable instancetype)networkSetWithDevice:(id<MTLDevice>)device
                                userDirectory:(nullable NSString *)userDirectory
                                          log:(void (^ _Nullable)(NSString *line))logger;

@property (nonatomic, readonly, nullable) VLCHDRNetwork *high;
@property (nonatomic, readonly, nullable) VLCHDRNetwork *maximum;
@property (nonatomic) enum maclc_sdr2hdr_quality currentQuality;

@end

NS_ASSUME_NONNULL_END

#endif /* VLC_HDR_NETWORK_H */
