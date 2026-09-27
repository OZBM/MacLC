/****************************************************************************
 * NSMenuVLCAdditionsTest.m: menu separator visibility tests
 ****************************************************************************
 * Copyright (C) 2026 Hazen Studio
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by the
 * Free Software Foundation; either version 2 of the License, or (at your
 * option) any later version.
 *****************************************************************************/

#import <XCTest/XCTest.h>

#import "extensions/NSMenu+VLCAdditions.h"

@interface NSMenuVLCAdditionsTest : XCTestCase
@end

@implementation NSMenuVLCAdditionsTest

/* Builds a menu from a layout such as @"About, (Updates), |, Settings": | is a
 * separator and a title in parentheses a hidden item. */
static NSMenu *menuWithLayout(NSString *layout)
{
    NSMenu * const menu = [[NSMenu alloc] initWithTitle:@"Test"];
    for (NSString * const entry in [layout componentsSeparatedByString:@", "]) {
        if ([entry isEqualToString:@"|"]) {
            [menu addItem:[NSMenuItem separatorItem]];
        } else if ([entry hasPrefix:@"("]) {
            NSString * const title = [entry substringWithRange:NSMakeRange(1, entry.length - 2)];
            [menu addItemWithTitle:title action:NULL keyEquivalent:@""].hidden = YES;
        } else {
            [menu addItemWithTitle:entry action:NULL keyEquivalent:@""];
        }
    }
    return menu;
}

/* The menu as it is drawn, in the same notation: hidden items left out. */
static NSString *drawnLayout(NSMenu *menu)
{
    NSMutableArray<NSString *> * const entries = [NSMutableArray array];
    for (NSMenuItem * const item in menu.itemArray) {
        if (!item.isHidden) {
            [entries addObject:item.isSeparatorItem ? @"|" : item.title];
        }
    }
    return [entries componentsJoinedByString:@", "];
}

static NSString *updatedLayout(NSString *layout)
{
    NSMenu * const menu = menuWithLayout(layout);
    [menu updateSeparatorVisibility];
    return drawnLayout(menu);
}

- (void)testAMenuWithoutHiddenItemsKeepsItsSeparators
{
    XCTAssertEqualObjects(updatedLayout(@"Cut, Copy, |, Find, |, Emoji & Symbols"),
                          @"Cut, Copy, |, Find, |, Emoji & Symbols");
}

/* The application menu of MainMenu.xib, with the items MacLC hides when it
 * has no updater and no extension. */
- (void)testTheApplicationMenuShowsOneSeparatorBetweenGroups
{
    XCTAssertEqualObjects(updatedLayout(@"About MacLC, (Check for Updates…), |, Settings…, |, (Extensions), "
                                        @"(Add-ons), |, (Add Interface), |, Services, |, Hide MacLC, "
                                        @"Hide Others, Show All, |, Quit MacLC"),
                          @"About MacLC, |, Settings…, |, Services, |, Hide MacLC, Hide Others, Show All, |, "
                          @"Quit MacLC");
}

- (void)testTheHelpMenuShowsOneSeparatorBetweenGroups
{
    XCTAssertEqualObjects(updatedLayout(@"MacLC Help, License, |, (Online Documentation…), (Online Forum…), "
                                        @"(Make a Donation…), |, Hazen Studio Website"),
                          @"MacLC Help, License, |, Hazen Studio Website");
}

- (void)testLeadingAndTrailingSeparatorsAreHidden
{
    XCTAssertEqualObjects(updatedLayout(@"|, Play, |"), @"Play");
    XCTAssertEqualObjects(updatedLayout(@"(Record), |, |, Play, |, (Stop), |"), @"Play");
}

- (void)testAMenuOfHiddenItemsShowsNoSeparator
{
    XCTAssertEqualObjects(updatedLayout(@"(Play), |, (Stop), |"), @"");
    XCTAssertEqualObjects(updatedLayout(@"|, |"), @"");
}

/* A separator hidden while its group was empty comes back with the group. */
- (void)testSeparatorsComeBackWithTheItemsTheyDivide
{
    NSMenu * const menu = menuWithLayout(@"About MacLC, |, (Extensions), |, Services");
    [menu updateSeparatorVisibility];
    XCTAssertEqualObjects(drawnLayout(menu), @"About MacLC, |, Services");

    [menu itemWithTitle:@"Extensions"].hidden = NO;
    [menu updateSeparatorVisibility];
    XCTAssertEqualObjects(drawnLayout(menu), @"About MacLC, |, Extensions, |, Services");
}

@end
