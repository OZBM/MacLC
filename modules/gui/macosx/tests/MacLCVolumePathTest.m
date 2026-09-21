/****************************************************************************
 * MacLCVolumePathTest.m: local-volume detection tests
 ****************************************************************************
 * Copyright (C) 2026 Hazen Studio
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by the
 * Free Software Foundation; either version 2 of the License, or (at your
 * option) any later version.
 *****************************************************************************/

#import <XCTest/XCTest.h>

#import "extensions/MacLCVolumePath.h"

#include <sys/mount.h>
#include <string.h>

@interface MacLCVolumePathTest : XCTestCase
@end

@implementation MacLCVolumePathTest

- (void)testTheRootVolumeIsLocal
{
    XCTAssertTrue(MacLCPathIsOnLocalVolume(@"/"));
}

- (void)testPathsOnTheRootVolumeAreLocal
{
    XCTAssertTrue(MacLCPathIsOnLocalVolume(NSHomeDirectory()));
    XCTAssertTrue(MacLCPathIsOnLocalVolume(NSTemporaryDirectory()));
    XCTAssertTrue(MacLCPathIsOnLocalVolume(@"/Applications"));
}

/* The answer comes from the mount table, so a file that is not there yet is
 * still on the volume that would hold it. */
- (void)testAMissingFileOnALocalVolumeIsStillLocal
{
    NSString * const path =
        [NSHomeDirectory() stringByAppendingPathComponent:@"maclc-no-such-file-6f1c2a"];
    XCTAssertTrue(MacLCPathIsOnLocalVolume(path));
}

- (void)testNothingIsNotLocal
{
    XCTAssertFalse(MacLCPathIsOnLocalVolume(nil));
    XCTAssertFalse(MacLCPathIsOnLocalVolume(@""));
}

/* Only absolute paths can be matched against mount points. */
- (void)testARelativePathIsNotLocal
{
    XCTAssertFalse(MacLCPathIsOnLocalVolume(@"Movies/clip.mp4"));
    XCTAssertFalse(MacLCPathIsOnLocalVolume(@"clip.mp4"));
}

/* Every mounted volume must answer the same way for its own mount point as
 * the mount table says, including the deepest mount point, which is the one
 * the whole-component match exists for: a shorter mount point must not win
 * over a longer one that also matches. */
- (void)testEveryMountPointAgreesWithTheMountTable
{
    struct statfs *mounts = NULL;
    const int count = getmntinfo(&mounts, MNT_NOWAIT);
    XCTAssertGreaterThan(count, 0);

    for (int i = 0; i < count; i++) {
        NSString * const mountPoint =
            [NSFileManager.defaultManager stringWithFileSystemRepresentation:mounts[i].f_mntonname
                                                                     length:strlen(mounts[i].f_mntonname)];
        const BOOL expected = (mounts[i].f_flags & MNT_LOCAL) != 0;
        XCTAssertEqual(MacLCPathIsOnLocalVolume(mountPoint), expected,
                       @"%@ should be %@", mountPoint, expected ? @"local" : @"remote");
    }
}

/* A name that only extends a mount point's last component belongs to the
 * volume above it, not to that mount point. */
- (void)testAMountPointIsNotAPrefixOfASiblingName
{
    struct statfs *mounts = NULL;
    const int count = getmntinfo(&mounts, MNT_NOWAIT);
    XCTAssertGreaterThan(count, 0);

    for (int i = 0; i < count; i++) {
        NSString * const mountPoint =
            [NSFileManager.defaultManager stringWithFileSystemRepresentation:mounts[i].f_mntonname
                                                                     length:strlen(mounts[i].f_mntonname)];
        if (mountPoint.length <= 1) {
            continue;
        }
        NSString * const sibling = [mountPoint stringByAppendingString:@"-maclc-6f1c2a"];
        /* Whatever the answer is, it must be the one for the parent volume,
         * never the one this mount point would give if it claimed the name. */
        NSString * const parent = mountPoint.stringByDeletingLastPathComponent;
        XCTAssertEqual(MacLCPathIsOnLocalVolume(sibling),
                       MacLCPathIsOnLocalVolume(parent),
                       @"%@ should follow %@", sibling, parent);
    }
}

@end
