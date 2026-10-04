/*****************************************************************************
 * MacLCNetworkAddress.h: Network address resolution helper
 *****************************************************************************
 * Copyright (C) 2026 Hazen Studio
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Representation of an active network interface for IP selection.
 */
@interface MacLCNetworkInterfaceInfo : NSObject

@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly, copy) NSString *ipv4Address;
@property (nonatomic, readonly, getter=isUp) BOOL up;
@property (nonatomic, readonly, getter=isLoopback) BOOL loopback;

- (instancetype)initWithName:(NSString *)name
                 ipv4Address:(NSString *)ipv4Address
                          up:(BOOL)up
                    loopback:(BOOL)loopback;

@end

/**
 * Resolves the primary LAN IPv4 address for AirPlay and Chromecast streaming.
 */
@interface MacLCNetworkAddress : NSObject

/**
 * Returns the IPv4 address of the primary network interface.
 * Reads the primary interface from SystemConfiguration (State:/Network/Global/IPv4 -> PrimaryInterface)
 * and retrieves its IP via getifaddrs.
 * Falls back to the first non-loopback, non-link-local IPv4 of an active "en*" interface.
 */
+ (nullable NSString *)primaryIPv4Address;

/**
 * Pure selection logic that chooses the primary IPv4 address from a provided interface list.
 * Exposed for unit testing.
 */
+ (nullable NSString *)selectPrimaryIPv4AddressWithPrimaryName:(nullable NSString *)primaryName
                                                   interfaces:(NSArray<MacLCNetworkInterfaceInfo *> *)interfaces;

/**
 * Validates whether an IPv4 address string is non-loopback, non-link-local (not 169.254/16), and non-zero.
 */
+ (BOOL)isValidNonLocalIPv4:(NSString *)address;

@end

NS_ASSUME_NONNULL_END
