/*****************************************************************************
 * VLCInputNodePathControlItem.m: MacOS X interface module
 *****************************************************************************
 * Copyright (C) 2023 VLC authors and VideoLAN
 *
 * Authors: Claudio Cambra <developer@claudiocambra.com>
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

#import "VLCInputNodePathControlItem.h"

#import "VLCInputItem.h"
#import "VLCInputNode.h"
#import "VLCLibraryImageCache.h"

#import "extensions/NSString+Helpers.h"

@implementation VLCInputNodePathControlItem

+ (NSString *)accessibilityDescriptionPrefix
{
    return _NS("Thumbnail for media location");
}

- (instancetype)initWithInputNode:(VLCInputNode *)inputNode
{
    return [self initWithInputNode:inputNode fallbackTitle:nil];
}

- (instancetype)initWithInputNode:(VLCInputNode *)inputNode
                    fallbackTitle:(NSString *)fallbackTitle
{
    self = [super init];
    if (self == nil) {
        return nil;
    }
    if (inputNode == nil) {
        NSLog(@"WARNING: Received nil input node, cannot create VLCInputNodePathControlItem");
        return self;
    }

    _inputNode = inputNode;

    /* A media source's root node has no input item: vlc_media_tree_New()
     * leaves root->p_item NULL. Opening a discovery service that has found
     * nothing yet shows exactly that node, so it needs an item too. */
    VLCInputItem * const inputItem = inputNode.inputItem;
    NSString *identifier = inputItem.MRL;
    if (identifier.length == 0) {
        identifier = inputItem.path;
    }
    if (identifier.length == 0) {
        identifier = fallbackTitle;
    }
    if (identifier.length == 0) {
        identifier = NSUUID.UUID.UUIDString;
    }

    NSString * const name = inputItem.name;
    self.title = name.length > 0 ? name : (fallbackTitle ?: @"");

    NSImage * const folderImage = [NSImage imageNamed:NSImageNameFolder];
    self.image = folderImage != nil ? folderImage.copy : [[NSImage alloc] initWithSize:NSMakeSize(16., 16.)];
    // HACK: We have no way when we get the clicked item from the path control
    // of knowing specifically which input node this path item corresponds to,
    // as the path control returns a copy for clickedPathItem that is not of
    // this class. As a very awkward workaround, lets set the accessibility
    // description of the image and we will use this as an identifier.
    self.image.accessibilityDescription = [NSString stringWithFormat:@"%@: %@",
                                           VLCInputNodePathControlItem.accessibilityDescriptionPrefix,
                                           identifier];
    return self;
}

- (NSString *)description
{
    if (_inputNode != nil && _inputNode.inputItem != nil) {
        return [NSString stringWithFormat:@"path: %@", _inputNode.inputItem.path];
    } else {
        return @"no input node";
    }
}

@end
