/****************************************************************************
 * VLCInputNodePathControlTest.m: Browse breadcrumb tests
 ****************************************************************************
 * Copyright (C) 2026 Hazen Studio
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by the
 * Free Software Foundation; either version 2 of the License, or (at your
 * option) any later version.
 *****************************************************************************/

#import <XCTest/XCTest.h>

#import "library/VLCInputNode.h"
#import "library/VLCInputNodePathControl.h"
#import "library/VLCInputNodePathControlItem.h"

#include <vlc_common.h>
#include <vlc_input_item.h>

@interface VLCInputNodePathControlTest : XCTestCase
@end

@implementation VLCInputNodePathControlTest

/* The root of a media source's tree, as vlc_media_tree_New() builds it:
 * no input item. Opening a discovery service that has found nothing yet
 * from the Browse home appends exactly this node to the breadcrumb, which
 * used to fail an assertion (a crash, since assertions are on). */
- (void)testARootNodeWithoutAnInputItemGetsABreadcrumb
{
    input_item_node_t root = { .p_item = NULL, .i_children = 0, .pp_children = NULL };
    VLCInputNode * const node = [[VLCInputNode alloc] initWithInputNode:&root];
    XCTAssertNil(node.inputItem);

    VLCInputNodePathControlItem * const item =
        [[VLCInputNodePathControlItem alloc] initWithInputNode:node fallbackTitle:@"Bonjour"];
    XCTAssertEqualObjects(item.title, @"Bonjour");
    XCTAssertNotNil(item.image);
    XCTAssertGreaterThan(item.image.accessibilityDescription.length, (NSUInteger)0);
    XCTAssertEqual(item.inputNode, node);

    VLCInputNodePathControl * const pathControl =
        [[VLCInputNodePathControl alloc] initWithFrame:NSMakeRect(0., 0., 400., 24.)];
    XCTAssertNoThrow([pathControl appendInputNodePathControlItem:item]);
    XCTAssertEqual(pathControl.pathItems.count, (NSUInteger)1);
    XCTAssertEqual(pathControl.orderedInputNodePathControlItems.firstObject, item);
}

/* Without a fallback title the item still gets an identifier, and two such
 * roots do not collide in the path control's lookup table. */
- (void)testRootNodesWithoutTitlesStayDistinct
{
    input_item_node_t rootOne = { .p_item = NULL, .i_children = 0, .pp_children = NULL };
    input_item_node_t rootTwo = { .p_item = NULL, .i_children = 0, .pp_children = NULL };
    VLCInputNodePathControlItem * const itemOne =
        [[VLCInputNodePathControlItem alloc] initWithInputNode:[[VLCInputNode alloc] initWithInputNode:&rootOne]];
    VLCInputNodePathControlItem * const itemTwo =
        [[VLCInputNodePathControlItem alloc] initWithInputNode:[[VLCInputNode alloc] initWithInputNode:&rootTwo]];

    XCTAssertNotEqualObjects(itemOne.image.accessibilityDescription, itemTwo.image.accessibilityDescription);

    VLCInputNodePathControl * const pathControl =
        [[VLCInputNodePathControl alloc] initWithFrame:NSMakeRect(0., 0., 400., 24.)];
    [pathControl appendInputNodePathControlItem:itemOne];
    [pathControl appendInputNodePathControlItem:itemTwo];
    XCTAssertEqual(pathControl.inputNodePathControlItems.count, (NSUInteger)2);
}

- (void)testANodeWithAnInputItemIsNamedAfterIt
{
    input_item_t * const inputItem = input_item_NewDirectory("file:///tmp/Movies", "Movies", ITEM_LOCAL);
    input_item_node_t * const inputNode = input_item_node_Create(inputItem);
    VLCInputNode * const node = [[VLCInputNode alloc] initWithInputNode:inputNode];

    VLCInputNodePathControlItem * const item =
        [[VLCInputNodePathControlItem alloc] initWithInputNode:node fallbackTitle:@"Not this"];
    XCTAssertEqualObjects(item.title, @"Movies");
    XCTAssertTrue([item.image.accessibilityDescription hasSuffix:@"/tmp/Movies"]);

    input_item_node_Delete(inputNode);
    input_item_Release(inputItem);
}

/* An item that cannot be found again is left out rather than asserted on. */
- (void)testAnItemWithoutAnIdentifierIsLeftOut
{
    VLCInputNodePathControl * const pathControl =
        [[VLCInputNodePathControl alloc] initWithFrame:NSMakeRect(0., 0., 400., 24.)];
    VLCInputNodePathControlItem * const bareItem = [[VLCInputNodePathControlItem alloc] init];
    XCTAssertNoThrow([pathControl appendInputNodePathControlItem:bareItem]);
    XCTAssertEqual(pathControl.pathItems.count, (NSUInteger)0);
}

@end
