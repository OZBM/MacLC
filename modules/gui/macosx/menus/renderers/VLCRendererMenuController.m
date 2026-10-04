/*****************************************************************************
 * VLCRendererMenuController.m: Controller class for the renderer menu
 *****************************************************************************
 * Copyright (C) 2016-2026 VLC authors and VideoLAN
 *
 * Authors: Marvin Scholz <epirat07 at gmail dot com>
 *          Felix Paul Kühne <fkuehne -at- videolan -dot- org>
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

#import "VLCRendererMenuController.h"

#include <vlc_common.h>
#include <vlc_renderer_discovery.h>

#import "cast/MacLCCastController.h"
#import "extensions/NSString+Helpers.h"
#import "main/VLCMain.h"
#import "menus/renderers/VLCRendererItem.h"
#import "playqueue/VLCPlayQueueController.h"
#import "playqueue/VLCPlayerController.h"
#import "theme/MacLCDesign.h"

@interface VLCRendererMenuController ()

- (void)rebuildMenu;

@end

@implementation VLCRendererMenuController

- (instancetype)init
{
    self = [super init];
    if (self) {
        [NSNotificationCenter.defaultCenter addObserver:self
                                               selector:@selector(castStateDidChange:)
                                                   name:MacLCCastStateDidChangeNotification
                                                 object:nil];
    }
    return self;
}

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)setRendererMenu:(NSMenu *)rendererMenu
{
    _rendererMenu = rendererMenu;
    [self rebuildMenu];
}

- (void)setRendererMenuItem:(NSMenuItem *)rendererMenuItem
{
    _rendererMenuItem = rendererMenuItem;
    [self updateRendererMenuItemEnablement];
}

- (void)setRendererNoneItem:(NSMenuItem *)rendererNoneItem
{
    _rendererNoneItem = rendererNoneItem;
    [self rebuildMenu];
}

- (void)castStateDidChange:(NSNotification *)notification
{
    [self rebuildMenu];
}

- (void)rebuildMenu
{
    if (!_rendererMenu) {
        return;
    }

    MacLCCastController * const castController = MacLCCastController.sharedController;
    VLCPlayerController * const pc = VLCMain.sharedInstance.playQueueController.playerController;
    vlc_renderer_item_t * const currentRenderer = pc.rendererItem;
    const BOOL isCasting = castController.isCasting;

    if (_rendererNoneItem) {
        _rendererNoneItem.title = _NS("This Mac");
        _rendererNoneItem.target = self;
        _rendererNoneItem.action = @selector(selectRenderer:);
        _rendererNoneItem.representedObject = nil;
        _rendererNoneItem.image = [MacLCDesign symbolNamed:@"laptopcomputer" accessibilityLabel:_NS("This Mac")];
        _rendererNoneItem.state = isCasting ? NSControlStateValueOff : NSControlStateValueOn;

        if (![_rendererMenu.itemArray containsObject:_rendererNoneItem]) {
            [_rendererMenu insertItem:_rendererNoneItem atIndex:0];
        }

        while (_rendererMenu.numberOfItems > 1) {
            [_rendererMenu removeItemAtIndex:1];
        }
    } else {
        [_rendererMenu removeAllItems];
        NSMenuItem * const noneItem = [[NSMenuItem alloc] initWithTitle:_NS("This Mac")
                                                                 action:@selector(selectRenderer:)
                                                          keyEquivalent:@""];
        noneItem.target = self;
        noneItem.representedObject = nil;
        noneItem.image = [MacLCDesign symbolNamed:@"laptopcomputer" accessibilityLabel:_NS("This Mac")];
        noneItem.state = isCasting ? NSControlStateValueOff : NSControlStateValueOn;
        [_rendererMenu addItem:noneItem];
    }

    for (VLCRendererItem *item in castController.rendererItems) {
        NSMenuItem * const menuItem = [[NSMenuItem alloc] initWithTitle:item.name
                                                                 action:@selector(selectRenderer:)
                                                          keyEquivalent:@""];
        menuItem.target = self;
        menuItem.representedObject = item;
        NSString * const symbolName = (item.capabilityFlags & VLC_RENDERER_CAN_VIDEO) ? @"tv" : @"hifispeaker";
        menuItem.image = [MacLCDesign symbolNamed:symbolName accessibilityLabel:item.name];

        if (currentRenderer != NULL && item.rendererItem == currentRenderer) {
            menuItem.state = NSControlStateValueOn;
        } else {
            menuItem.state = NSControlStateValueOff;
        }
        [_rendererMenu addItem:menuItem];
    }

    [self updateRendererMenuItemEnablement];
}

- (void)updateRendererMenuItemEnablement
{
    MacLCCastController * const castController = MacLCCastController.sharedController;
    _rendererMenuItem.enabled = (castController.hasCastDevices || castController.isCasting);
}

- (IBAction)selectRenderer:(id)sender
{
    VLCRendererItem * const item = [sender representedObject];
    [MacLCCastController.sharedController playOnRendererItem:item];
}

- (void)startRendererDiscoveries
{
    [MacLCCastController.sharedController start];
}

- (void)stopRendererDiscoveries
{
    // Discoveries are managed by MacLCCastController
}

- (IBAction)toggleRendererDiscovery:(id)sender
{
    // No-op: discoveries are managed by MacLCCastController
}

- (NSArray<VLCRendererItem *> *)rendererItems
{
    return MacLCCastController.sharedController.rendererItems;
}

@end
