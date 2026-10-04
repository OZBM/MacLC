/*****************************************************************************
 * MacLCNetworkAddress.m: Network address resolution helper
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

#import "MacLCNetworkAddress.h"

#import <SystemConfiguration/SystemConfiguration.h>
#include <ifaddrs.h>
#include <arpa/inet.h>
#include <net/if.h>

@implementation MacLCNetworkInterfaceInfo

- (instancetype)initWithName:(NSString *)name
                 ipv4Address:(NSString *)ipv4Address
                          up:(BOOL)up
                    loopback:(BOOL)loopback
{
    self = [super init];
    if (self) {
        _name = [name copy];
        _ipv4Address = [ipv4Address copy];
        _up = up;
        _loopback = loopback;
    }
    return self;
}

@end

@implementation MacLCNetworkAddress

+ (BOOL)isValidNonLocalIPv4:(NSString *)address
{
    if (address.length == 0) {
        return NO;
    }

    struct in_addr addr;
    if (inet_pton(AF_INET, address.UTF8String, &addr) != 1) {
        return NO;
    }

    const uint32_t ip = ntohl(addr.s_addr);
    if (ip == 0 || ip == 0xFFFFFFFF) {
        return NO;
    }

    // 127.0.0.0/8 (Loopback)
    if ((ip & 0xFF000000) == 0x7F000000) {
        return NO;
    }

    // 169.254.0.0/16 (Link-local)
    if ((ip & 0xFFFF0000) == 0xA9FE0000) {
        return NO;
    }

    return YES;
}

+ (nullable NSString *)selectPrimaryIPv4AddressWithPrimaryName:(nullable NSString *)primaryName
                                                   interfaces:(NSArray<MacLCNetworkInterfaceInfo *> *)interfaces
{
    if (primaryName.length > 0) {
        for (MacLCNetworkInterfaceInfo *iface in interfaces) {
            if ([iface.name isEqualToString:primaryName]) {
                if (iface.isUp && !iface.isLoopback && [self isValidNonLocalIPv4:iface.ipv4Address]) {
                    return iface.ipv4Address;
                }
            }
        }
    }

    // Fallback: first non-loopback, non-link-local IPv4 of an en* interface that is up
    for (MacLCNetworkInterfaceInfo *iface in interfaces) {
        if (iface.isUp && !iface.isLoopback && [iface.name hasPrefix:@"en"] && [self isValidNonLocalIPv4:iface.ipv4Address]) {
            return iface.ipv4Address;
        }
    }

    return nil;
}

+ (nullable NSString *)primaryIPv4Address
{
    NSString *primaryName = nil;

    SCDynamicStoreRef store = SCDynamicStoreCreate(NULL, CFSTR("MacLCNetworkAddress"), NULL, NULL);
    if (store != NULL) {
        CFDictionaryRef globalIPv4 = SCDynamicStoreCopyValue(store, CFSTR("State:/Network/Global/IPv4"));
        if (globalIPv4 != NULL) {
            if (CFGetTypeID(globalIPv4) == CFDictionaryGetTypeID()) {
                CFStringRef primaryIface = CFDictionaryGetValue(globalIPv4, CFSTR("PrimaryInterface"));
                if (primaryIface != NULL && CFGetTypeID(primaryIface) == CFStringGetTypeID()) {
                    primaryName = [(__bridge NSString *)primaryIface copy];
                }
            }
            CFRelease(globalIPv4);
        }
        CFRelease(store);
    }

    NSMutableArray<MacLCNetworkInterfaceInfo *> *interfaceList = [NSMutableArray array];

    struct ifaddrs *ifap = NULL;
    if (getifaddrs(&ifap) == 0 && ifap != NULL) {
        for (struct ifaddrs *cur = ifap; cur != NULL; cur = cur->ifa_next) {
            if (cur->ifa_addr == NULL || cur->ifa_addr->sa_family != AF_INET) {
                continue;
            }

            char ipStr[INET_ADDRSTRLEN];
            struct sockaddr_in *addrIn = (struct sockaddr_in *)cur->ifa_addr;
            if (inet_ntop(AF_INET, &(addrIn->sin_addr), ipStr, sizeof(ipStr)) != NULL) {
                NSString *name = [NSString stringWithUTF8String:cur->ifa_name];
                NSString *ip = [NSString stringWithUTF8String:ipStr];
                const BOOL isUp = (cur->ifa_flags & IFF_UP) != 0;
                const BOOL isLoopback = (cur->ifa_flags & IFF_LOOPBACK) != 0;

                MacLCNetworkInterfaceInfo *info =
                    [[MacLCNetworkInterfaceInfo alloc] initWithName:name
                                                        ipv4Address:ip
                                                                 up:isUp
                                                           loopback:isLoopback];
                [interfaceList addObject:info];
            }
        }
        freeifaddrs(ifap);
    }

    return [self selectPrimaryIPv4AddressWithPrimaryName:primaryName interfaces:interfaceList];
}

@end
