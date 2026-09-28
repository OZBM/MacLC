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
#import "hdr/MacLCSDRToHDRPanelViewController.h"
#import "hdr/MacLCSDRToHDRState.h"
#import "coreinteraction/MacLCOSDController.h"

@implementation MacLCHDRMenuController
{
    NSMenu *_hdrMenu;
    NSMenuItem *_hdrItem;
    NSMenu *_sdrToHdrMenu;
    NSMenuItem *_sdrToHdrItem;
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

        _sdrToHdrMenu = [[NSMenu alloc] initWithTitle:_NS("SDR to HDR")];
        _sdrToHdrMenu.delegate = self;
        _sdrToHdrMenu.autoenablesItems = NO;
    }
    return self;
}

- (NSMenu *)hdrMenu
{
    return _hdrMenu;
}

- (NSMenu *)sdrToHdrMenu
{
    return _sdrToHdrMenu;
}

- (void)installInVideoMenu:(NSMenu *)videoMenu
{
    if (_hdrItem != nil || videoMenu == nil)
        return;
    _hdrItem = [[NSMenuItem alloc] initWithTitle:_NS("HDR") action:nil keyEquivalent:@""];
    _hdrItem.image = [NSImage imageWithSystemSymbolName:@"sun.max" accessibilityDescription:nil];
    _hdrItem.submenu = _hdrMenu;

    _sdrToHdrItem = [[NSMenuItem alloc] initWithTitle:_NS("SDR to HDR") action:nil keyEquivalent:@""];
    NSImage *sdrIcon = [NSImage imageWithSystemSymbolName:@"sun.max.circle" accessibilityDescription:nil]
                    ?: [NSImage imageWithSystemSymbolName:@"wand.and.sparkles" accessibilityDescription:nil];
    _sdrToHdrItem.image = sdrIcon;
    _sdrToHdrItem.submenu = _sdrToHdrMenu;

    [videoMenu insertItem:_hdrItem atIndex:0];
    [videoMenu insertItem:_sdrToHdrItem atIndex:1];
    [videoMenu insertItem:[NSMenuItem separatorItem] atIndex:2];

    /* ⌥⌘H must work even before the submenu was ever opened. */
    [self menuNeedsUpdate:_hdrMenu];
    [self menuNeedsUpdate:_sdrToHdrMenu];
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
    if (menu == _hdrMenu) {
        [self rebuildHdrMenu:menu];
    } else if (menu == _sdrToHdrMenu) {
        [self rebuildSdrToHdrMenu:menu];
    }
}

- (void)rebuildHdrMenu:(NSMenu *)menu
{
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

- (void)rebuildSdrToHdrMenu:(NSMenu *)menu
{
    [menu removeAllItems];

    MacLCSDRToHDRState *state = [MacLCSDRToHDRState sharedState];

    /* 1. Toggle item */
    NSMenuItem *toggleItem = [[NSMenuItem alloc] initWithTitle:_NS("Play SDR Video in HDR")
                                                        action:@selector(toggleSdrToHdr:)
                                                 keyEquivalent:@""];
    toggleItem.target = self;
    toggleItem.state = state.enabled ? NSControlStateValueOn : NSControlStateValueOff;
    [menu addItem:toggleItem];

    /* Separator */
    [menu addItem:[NSMenuItem separatorItem]];

    /* Section header: Quality */
    [menu addItem:[self sectionHeader:_NS("Quality")]];

    /* Quality items: Automatic, Fast, Balanced, High, Maximum */
    NSArray<NSNumber *> *qualities = @[
        @(MacLCSDRToHDRQualityAuto),
        @(MacLCSDRToHDRQualityFast),
        @(MacLCSDRToHDRQualityBalanced),
        @(MacLCSDRToHDRQualityHigh),
        @(MacLCSDRToHDRQualityMaximum)
    ];

    BOOL modelMissing = [state.reason isEqualToString:@"model-missing"];

    for (NSNumber *qNum in qualities) {
        MacLCSDRToHDRQuality q = (MacLCSDRToHDRQuality)qNum.integerValue;
        NSString *title = [MacLCSDRToHDRState displayNameForQuality:q];
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title
                                                      action:@selector(chooseQuality:)
                                               keyEquivalent:@""];
        item.target = self;
        item.tag = q;
        item.state = (state.quality == q) ? NSControlStateValueOn : NSControlStateValueOff;

        if (modelMissing && (q == MacLCSDRToHDRQualityHigh || q == MacLCSDRToHDRQualityMaximum)) {
            item.enabled = NO;
            item.toolTip = _NS("The model for High isn't installed.");
        } else {
            item.enabled = YES;
            item.toolTip = [MacLCSDRToHDRState summaryForQuality:q];
        }
        [menu addItem:item];
    }

    /* Separator */
    [menu addItem:[NSMenuItem separatorItem]];

    /* Show Original */
    NSMenuItem *origItem = [[NSMenuItem alloc] initWithTitle:_NS("Show Original")
                                                      action:@selector(toggleShowOriginal:)
                                               keyEquivalent:@""];
    origItem.target = self;
    const BOOL isRunning = state.activeQualityName.length > 0 && ![state.activeQualityName isEqualToString:@"off"];
    origItem.enabled = isRunning;
    origItem.state = state.comparing ? NSControlStateValueOn : NSControlStateValueOff;
    origItem.toolTip = _NS("Or hold M while the video plays.");
    [menu addItem:origItem];

    /* Separator */
    [menu addItem:[NSMenuItem separatorItem]];

    /* SDR to HDR Options... */
    NSMenuItem *optionsItem = [[NSMenuItem alloc] initWithTitle:_NS("SDR to HDR Options…")
                                                         action:@selector(showSdrToHdrOptions:)
                                                  keyEquivalent:@""];
    optionsItem.target = self;
    optionsItem.image = [NSImage imageWithSystemSymbolName:@"slider.horizontal.3" accessibilityDescription:nil];
    [menu addItem:optionsItem];
}

- (void)showOptions:(id)sender
{
    [MacLCSDRToHDRPanelViewController closePanel];
    [MacLCHDRPanelViewController showForKeyWindow];
}

- (void)showSdrToHdrOptions:(id)sender
{
    [MacLCHDRPanelViewController closePanel];
    [MacLCSDRToHDRPanelViewController showForKeyWindow];
}

- (void)choosePresentation:(NSMenuItem *)sender
{
    const MacLCHDRPresentation presentation = (MacLCHDRPresentation)sender.tag;
    [[MacLCHDRController sharedController] applyPresentation:presentation];
    [[MacLCOSDController sharedController] showMessage:MacLCHDRPresentationDisplayName(presentation)
                                            symbolName:@"sun.max.fill"];
}

- (void)choosePicture:(NSMenuItem *)sender
{
    [[MacLCHDRController sharedController] applyPictureMode:(MacLCHDRPictureMode)sender.tag];
    [[MacLCOSDController sharedController]
        showMessage:[NSString stringWithFormat:_NS("Picture: %@"), sender.title]
         symbolName:@"slider.horizontal.3"];
}

- (void)toggleSdrToHdr:(id)sender
{
    MacLCSDRToHDRState *state = [MacLCSDRToHDRState sharedState];
    const BOOL newEnabled = !state.enabled;
    state.enabled = newEnabled;
    if (newEnabled) {
        NSString *name = [MacLCSDRToHDRState displayNameForQuality:state.activeQuality];
        [[MacLCOSDController sharedController] showMessage:[NSString stringWithFormat:_NS("SDR to HDR: %@"), name]
                                                symbolName:@"sun.max"];
    } else {
        [[MacLCOSDController sharedController] showMessage:_NS("SDR to HDR Off")
                                                symbolName:@"sun.min"];
    }
}

- (void)chooseQuality:(NSMenuItem *)sender
{
    MacLCSDRToHDRQuality q = (MacLCSDRToHDRQuality)sender.tag;
    [MacLCSDRToHDRState sharedState].quality = q;
    NSString *name = [MacLCSDRToHDRState displayNameForQuality:q];
    [[MacLCOSDController sharedController] showMessage:[NSString stringWithFormat:_NS("SDR to HDR: %@"), name]
                                            symbolName:@"sun.max"];
}

- (void)toggleShowOriginal:(id)sender
{
    MacLCSDRToHDRState *state = [MacLCSDRToHDRState sharedState];
    const BOOL comparing = !state.comparing;
    [state setComparing:comparing];
    if (comparing) {
        [[MacLCOSDController sharedController] showMessage:_NS("Original") symbolName:@"square.split.2x1"];
    } else {
        [[MacLCOSDController sharedController] showMessage:_NS("HDR") symbolName:@"sun.max"];
    }
}

@end
