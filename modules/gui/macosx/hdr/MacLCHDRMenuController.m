/*****************************************************************************
 * MacLCHDRMenuController.m: the Video ▸ HDR submenu
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

#import "MacLCHDRMenuController.h"

#import "extensions/NSString+Helpers.h"
#import "hdr/MacLCHDRController.h"
#import "hdr/MacLCHDRPanelViewController.h"

@implementation MacLCHDRMenuController
{
    NSMenu *_hdrMenu;
    NSMenuItem *_hdrItem;
}

+ (instancetype)sharedMenuController
{
    static MacLCHDRMenuController *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        shared = [[MacLCHDRMenuController alloc] init];
    });
    return shared;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _hdrMenu = [[NSMenu alloc] initWithTitle:_NS("HDR")];
        _hdrMenu.delegate = self;
        _hdrMenu.autoenablesItems = NO;
    }
    return self;
}

- (NSMenu *)hdrMenu
{
    return _hdrMenu;
}

- (void)installInVideoMenu:(NSMenu *)videoMenu
{
    if (_hdrItem != nil || videoMenu == nil)
        return;
    _hdrItem = [[NSMenuItem alloc] initWithTitle:_NS("HDR") action:nil keyEquivalent:@""];
    _hdrItem.image = [NSImage imageWithSystemSymbolName:@"sun.max" accessibilityDescription:nil];
    _hdrItem.submenu = _hdrMenu;
    [videoMenu insertItem:_hdrItem atIndex:0];
    [videoMenu insertItem:[NSMenuItem separatorItem] atIndex:1];

    /* ⌥⌘H must work even before the submenu was ever opened. */
    [self menuNeedsUpdate:_hdrMenu];
}

- (NSMenuItem *)sectionHeader:(NSString *)title
{
    if (@available(macOS 14.0, *))
        return [NSMenuItem sectionHeaderWithTitle:title];
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:nil keyEquivalent:@""];
    item.enabled = NO;
    return item;
}

- (void)menuNeedsUpdate:(NSMenu *)menu
{
    if (menu != _hdrMenu)
        return;
    [menu removeAllItems];

    MacLCHDRController *controller = [MacLCHDRController sharedController];
    MacLCHDRStreamInfo *stream = controller.stream;
    const BOOL hdr = stream.isHDR;

    NSMenuItem *options = [[NSMenuItem alloc] initWithTitle:_NS("HDR Options…")
                                                     action:@selector(showOptions:)
                                              keyEquivalent:@"h"];
    options.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagOption;
    options.target = self;
    options.image = [NSImage imageWithSystemSymbolName:@"slider.horizontal.3" accessibilityDescription:nil];
    [menu addItem:options];

    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItem:[self sectionHeader:_NS("Format")]];
    const MacLCHDRPresentation active = controller.activePresentation;
    const MacLCHDRPresentation recommended = controller.recommendation.presentation;
    NSArray<NSNumber *> *all = @[@(MacLCHDRPresentationDolbyVision), @(MacLCHDRPresentationHDR10Plus),
                                 @(MacLCHDRPresentationHDR10), @(MacLCHDRPresentationHLG),
                                 @(MacLCHDRPresentationSDR)];
    for (NSNumber *number in all) {
        const MacLCHDRPresentation p = number.integerValue;
        NSString *title = MacLCHDRPresentationDisplayName(p);
        if (hdr && p == recommended)
            title = [NSString stringWithFormat:_NS("%@ (Recommended)"), title];
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title
                                                      action:@selector(choosePresentation:)
                                               keyEquivalent:@""];
        item.target = self;
        item.tag = p;
        item.enabled = hdr && [stream.availablePresentations containsObject:number];
        item.state = (hdr && p == active) ? NSControlStateValueOn : NSControlStateValueOff;
        item.toolTip = MacLCHDRPresentationSummary(p);
        [menu addItem:item];
    }

    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItem:[self sectionHeader:_NS("Picture")]];
    const BOOL pq = hdr && stream.transfer == TRANSFER_FUNC_SMPTE_ST2084
                 && active != MacLCHDRPresentationSDR;
    MacLCHDRPictureMode mode = controller.activePictureMode;
    for (NSNumber *number in @[@(MacLCHDRPictureModeAccurate), @(MacLCHDRPictureModeBalanced),
                               @(MacLCHDRPictureModeBright)]) {
        const MacLCHDRPictureMode m = number.integerValue;
        NSString *title = m == MacLCHDRPictureModeAccurate ? _NS("Accurate")
                        : m == MacLCHDRPictureModeBalanced ? _NS("Balanced") : _NS("Bright");
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title
                                                      action:@selector(choosePicture:)
                                               keyEquivalent:@""];
        item.target = self;
        item.tag = m;
        item.enabled = pq;
        item.state = (pq && m == mode) ? NSControlStateValueOn : NSControlStateValueOff;
        item.toolTip = MacLCHDRPictureModeSummary(m);
        [menu addItem:item];
    }
}

- (void)showOptions:(id)sender
{
    [MacLCHDRPanelViewController showForKeyWindow];
}

- (void)choosePresentation:(NSMenuItem *)sender
{
    [[MacLCHDRController sharedController] applyPresentation:(MacLCHDRPresentation)sender.tag];
}

- (void)choosePicture:(NSMenuItem *)sender
{
    [[MacLCHDRController sharedController] applyPictureMode:(MacLCHDRPictureMode)sender.tag];
}

@end
