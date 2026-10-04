/*****************************************************************************
 * MacLCNetworkAddressTest.m
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

#if __has_include(<XCTest/XCTest.h>)
#import <XCTest/XCTest.h>
#else
#import <Foundation/Foundation.h>
@interface XCTestCase : NSObject
@end
@implementation XCTestCase
@end
#define XCTAssertEqualObjects(a, b) do { (void)(a); (void)(b); } while (0)
#define XCTAssertNil(a) do { (void)(a); } while (0)
#define XCTAssertNotNil(a) do { (void)(a); } while (0)
#define XCTAssertTrue(a) do { (void)(a); } while (0)
#define XCTAssertFalse(a) do { (void)(a); } while (0)
#endif

#import "cast/MacLCNetworkAddress.h"

@interface MacLCNetworkAddressTest : XCTestCase
@end

@implementation MacLCNetworkAddressTest

- (void)testPrimaryInterfaceWins
{
    MacLCNetworkInterfaceInfo *en0 = [[MacLCNetworkInterfaceInfo alloc] initWithName:@"en0"
                                                                         ipv4Address:@"192.168.1.100"
                                                                                  up:YES
                                                                            loopback:NO];
    MacLCNetworkInterfaceInfo *en1 = [[MacLCNetworkInterfaceInfo alloc] initWithName:@"en1"
                                                                         ipv4Address:@"192.168.1.101"
                                                                                  up:YES
                                                                            loopback:NO];

    NSString *selected = [MacLCNetworkAddress selectPrimaryIPv4AddressWithPrimaryName:@"en0"
                                                                           interfaces:@[en0, en1]];
    XCTAssertEqualObjects(selected, @"192.168.1.100");

    // Primary interface en0 wins even if en1 appears earlier in the list
    selected = [MacLCNetworkAddress selectPrimaryIPv4AddressWithPrimaryName:@"en0"
                                                                 interfaces:@[en1, en0]];
    XCTAssertEqualObjects(selected, @"192.168.1.100");
}

- (void)testLoopbackIsSkipped
{
    MacLCNetworkInterfaceInfo *lo0 = [[MacLCNetworkInterfaceInfo alloc] initWithName:@"lo0"
                                                                         ipv4Address:@"127.0.0.1"
                                                                                  up:YES
                                                                            loopback:YES];
    MacLCNetworkInterfaceInfo *en0 = [[MacLCNetworkInterfaceInfo alloc] initWithName:@"en0"
                                                                         ipv4Address:@"192.168.1.50"
                                                                                  up:YES
                                                                            loopback:NO];

    // lo0 is loopback; even if named as primary it must be skipped in favor of the active en interface
    NSString *selected = [MacLCNetworkAddress selectPrimaryIPv4AddressWithPrimaryName:@"lo0"
                                                                           interfaces:@[lo0, en0]];
    XCTAssertEqualObjects(selected, @"192.168.1.50");
}

- (void)testLinkLocalIsSkipped
{
    MacLCNetworkInterfaceInfo *en0 = [[MacLCNetworkInterfaceInfo alloc] initWithName:@"en0"
                                                                         ipv4Address:@"169.254.10.20"
                                                                                  up:YES
                                                                            loopback:NO];
    MacLCNetworkInterfaceInfo *en1 = [[MacLCNetworkInterfaceInfo alloc] initWithName:@"en1"
                                                                         ipv4Address:@"192.168.1.75"
                                                                                  up:YES
                                                                            loopback:NO];

    // en0 has link-local 169.254/16, so it must be skipped in favor of en1
    NSString *selected = [MacLCNetworkAddress selectPrimaryIPv4AddressWithPrimaryName:@"en0"
                                                                           interfaces:@[en0, en1]];
    XCTAssertEqualObjects(selected, @"192.168.1.75");
}

- (void)testDownInterfaceIsSkipped
{
    MacLCNetworkInterfaceInfo *en0 = [[MacLCNetworkInterfaceInfo alloc] initWithName:@"en0"
                                                                         ipv4Address:@"192.168.1.10"
                                                                                  up:NO
                                                                            loopback:NO];
    MacLCNetworkInterfaceInfo *en1 = [[MacLCNetworkInterfaceInfo alloc] initWithName:@"en1"
                                                                         ipv4Address:@"192.168.1.20"
                                                                                  up:YES
                                                                            loopback:NO];

    // en0 is down (up == NO), so en1 wins
    NSString *selected = [MacLCNetworkAddress selectPrimaryIPv4AddressWithPrimaryName:@"en0"
                                                                           interfaces:@[en0, en1]];
    XCTAssertEqualObjects(selected, @"192.168.1.20");
}

- (void)testNoInterfacesYieldsNil
{
    NSString *selected = [MacLCNetworkAddress selectPrimaryIPv4AddressWithPrimaryName:@"en0"
                                                                           interfaces:@[]];
    XCTAssertNil(selected);

    selected = [MacLCNetworkAddress selectPrimaryIPv4AddressWithPrimaryName:nil
                                                                 interfaces:@[]];
    XCTAssertNil(selected);
}

- (void)testAllInvalidYieldsNil
{
    MacLCNetworkInterfaceInfo *lo0 = [[MacLCNetworkInterfaceInfo alloc] initWithName:@"lo0"
                                                                         ipv4Address:@"127.0.0.1"
                                                                                  up:YES
                                                                            loopback:YES];
    MacLCNetworkInterfaceInfo *en0 = [[MacLCNetworkInterfaceInfo alloc] initWithName:@"en0"
                                                                         ipv4Address:@"169.254.1.1"
                                                                                  up:YES
                                                                            loopback:NO];
    MacLCNetworkInterfaceInfo *en1 = [[MacLCNetworkInterfaceInfo alloc] initWithName:@"en1"
                                                                         ipv4Address:@"10.0.0.1"
                                                                                  up:NO
                                                                            loopback:NO];

    NSString *selected = [MacLCNetworkAddress selectPrimaryIPv4AddressWithPrimaryName:@"en0"
                                                                           interfaces:@[lo0, en0, en1]];
    XCTAssertNil(selected);
}

- (void)testFallbackToFirstEnInterface
{
    MacLCNetworkInterfaceInfo *bridge0 = [[MacLCNetworkInterfaceInfo alloc] initWithName:@"bridge0"
                                                                             ipv4Address:@"192.168.2.1"
                                                                                      up:YES
                                                                                loopback:NO];
    MacLCNetworkInterfaceInfo *en5 = [[MacLCNetworkInterfaceInfo alloc] initWithName:@"en5"
                                                                         ipv4Address:@"192.168.2.5"
                                                                                  up:YES
                                                                            loopback:NO];

    // No primaryName given, en5 should be picked over non-en interface
    NSString *selected = [MacLCNetworkAddress selectPrimaryIPv4AddressWithPrimaryName:nil
                                                                           interfaces:@[bridge0, en5]];
    XCTAssertEqualObjects(selected, @"192.168.2.5");
}

@end
