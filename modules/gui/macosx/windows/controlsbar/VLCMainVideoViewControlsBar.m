/*****************************************************************************
 * VLCMainVideoViewControlsBar.m: MacOS X interface module
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

#import "VLCMainVideoViewControlsBar.h"

#import "theme/MacLCDesign.h"

#import "extensions/NSString+Helpers.h"

#import "library/VLCLibraryController.h"
#import "library/VLCLibraryDataTypes.h"

#import "main/VLCMain.h"

#import "menus/VLCMainMenu.h"

#import "panels/VLCBookmarksWindowController.h"

#import "playqueue/VLCPlayQueueController.h"
#import "playqueue/VLCPlayerController.h"

#import "settings/MacLCConfigSafe.h"
#import "settings/panes/MacLCHDRSettingsViewController.h"
#import "hdr/MacLCHDRController.h"
#import "hdr/MacLCHDRPanelViewController.h"

#import <vlc_configuration.h>

#import "windows/video/VLCMainVideoViewController.h"
#import "windows/video/VLCVideoOutputProvider.h"
#import "windows/video/VLCVideoWindowCommon.h"

@interface VLCMainVideoViewControlsBar ()
{
    VLCPlayQueueController *_playQueueController;
    VLCPlayerController *_playerController;
}

@end

@implementation VLCMainVideoViewControlsBar

- (void)awakeFromNib
{
    [super awakeFromNib];

    self.bookmarksButton.toolTip = _NS("Bookmarks");
    self.bookmarksButton.accessibilityLabel = self.bookmarksButton.toolTip;
    self.bookmarksButton.image = [MacLCDesign symbolNamed:@"bookmark.fill" pointSize:14. weight:NSFontWeightMedium accessibilityLabel:_NS("Bookmarks")];

    self.subtitlesButton.toolTip = _NS("Subtitles");
    self.subtitlesButton.accessibilityLabel = self.subtitlesButton.toolTip;
    self.subtitlesButton.image = [MacLCDesign symbolNamed:@"text.bubble" pointSize:14. weight:NSFontWeightMedium accessibilityLabel:_NS("Subtitles")];

    self.audioButton.toolTip = _NS("Audio");
    self.audioButton.accessibilityLabel = self.audioButton.toolTip;
    self.audioButton.image = [MacLCDesign symbolNamed:@"waveform" pointSize:14. weight:NSFontWeightMedium accessibilityLabel:_NS("Audio")];

    self.videoButton.toolTip = _NS("Video");
    self.videoButton.accessibilityLabel = self.videoButton.toolTip;
    self.videoButton.image = [MacLCDesign symbolNamed:@"tv" pointSize:14. weight:NSFontWeightMedium accessibilityLabel:_NS("Video")];

    self.lyricsButton.toolTip = _NS("Lyrics");
    self.lyricsButton.accessibilityLabel = self.lyricsButton.toolTip;
    self.lyricsButton.image = [MacLCDesign symbolNamed:@"music.note.list" pointSize:14. weight:NSFontWeightMedium accessibilityLabel:_NS("Lyrics")];

    self.playbackRateButton.toolTip = _NS("Playback Rate");
    self.playbackRateButton.accessibilityLabel = self.playbackRateButton.toolTip;
    self.playbackRateButton.font = [MacLCDesign monospacedDigitFontForTextStyle:NSFontTextStyleCaption1 weight:NSFontWeightMedium];

    self.floatOnTopButton.toolTip = _NS("Float on Top");
    self.floatOnTopButton.accessibilityLabel = self.floatOnTopButton.toolTip;
    self.floatOnTopButton.image = [MacLCDesign symbolNamed:@"play.rectangle.on.rectangle" pointSize:14. weight:NSFontWeightMedium accessibilityLabel:_NS("Float on Top")];

    self.hdrButton.title = @"HDR";
    self.hdrButton.accessibilityLabel = _NS("Play SDR video in HDR");
    self.hdrButton.font = MacLCDesign.badgeFont;

    self.pipButton.toolTip = _NS("Picture in Picture");
    self.pipButton.accessibilityLabel = self.pipButton.toolTip;
    self.pipButton.image = [MacLCDesign symbolNamed:@"pip" pointSize:14. weight:NSFontWeightMedium accessibilityLabel:_NS("Picture in Picture")];

    NSArray<NSButton *> * const buttons = @[
        self.playButton,
        self.backwardButton,
        self.forwardButton,
        self.jumpBackwardButton,
        self.jumpForwardButton,
        self.bookmarksButton,
        self.subtitlesButton,
        self.audioButton,
        self.videoButton,
        self.lyricsButton,
        self.fullscreenButton,
        self.floatOnTopButton,
        self.playbackRateButton,
        self.pipButton,
        self.muteVolumeButton
    ];

    for (NSButton * const button in buttons) {
        if (!button) continue;
        button.contentTintColor = MacLCDesign.primaryLabel;
    }

    _playQueueController = VLCMain.sharedInstance.playQueueController;
    _playerController = _playQueueController.playerController;

    VLCLibraryController * const libraryController = VLCMain.sharedInstance.libraryController;
    self.bookmarksButton.hidden = !libraryController.shouldUseMediaLibrary;
    self.bookmarksButton.enabled = libraryController.libraryModel != nil;

    NSNotificationCenter * const notificationCenter = NSNotificationCenter.defaultCenter;
    [notificationCenter addObserver:self
                           selector:@selector(floatOnTopChanged:)
                               name:VLCWindowFloatOnTopChangedNotificationName
                             object:nil];
    [notificationCenter addObserver:self
                           selector:@selector(playbackRateChanged:)
                               name:VLCPlayerRateChanged
                             object:nil];
    [notificationCenter addObserver:self
                           selector:@selector(playbackRateChanged:)
                               name:VLCPlayerCapabilitiesChanged
                             object:nil];
    [notificationCenter addObserver:self
                           selector:@selector(updateAvailableButtons:)
                               name:VLCPlayerCurrentMediaItemChanged
                             object:nil];
    [notificationCenter addObserver:self
                           selector:@selector(updateLyricsButton:)
                               name:VLCPlayerShowLyricsChanged
                             object:nil];
    [notificationCenter addObserver:self
                           selector:@selector(updateLyricsButton:)
                               name:VLCPlayerLyricsAvailableChanged
                             object:nil];
    [notificationCenter addObserver:self
                           selector:@selector(fullscreenChanged:)
                               name:VLCPlayerFullscreenChanged
                             object:nil];
    [notificationCenter addObserver:self
                           selector:@selector(hdrExpansionChanged:)
                               name:MacLCHDRExpansionChangedNotification
                             object:nil];
    [notificationCenter addObserver:self
                           selector:@selector(hdrExpansionChanged:)
                               name:VLCPlayerTrackListChanged
                             object:nil];
    [notificationCenter addObserver:self
                           selector:@selector(hdrExpansionChanged:)
                               name:VLCPlayerTrackSelectionChanged
                             object:nil];
    [notificationCenter addObserver:self
                           selector:@selector(hdrExpansionChanged:)
                               name:NSApplicationDidChangeScreenParametersNotification
                             object:nil];
    [notificationCenter addObserver:self
                           selector:@selector(hdrExpansionChanged:)
                               name:NSWindowDidChangeScreenNotification
                             object:nil];
    [notificationCenter addObserver:self
                           selector:@selector(hdrExpansionChanged:)
                               name:MacLCHDRStateDidChangeNotification
                             object:nil];

    [self update];
}

- (void)update
{
    [super update];
    [self updateFloatOnTopButton];
    [self updatePlaybackRateButton];
    [self updateLyricsButton:nil];
    [self updateHdrButton];
}

- (void)floatOnTopChanged:(NSNotification *)notification
{
    [self updateFloatOnTopButton];
}

- (void)fullscreenChanged:(NSNotification *)notification
{
    [self updateFloatOnTopButton];
}

- (void)updateLyricsButton:(NSNotification *)notification
{
    const BOOL lyricsAvailable = _playerController.lyricsAvailable;
    self.lyricsButton.enabled = lyricsAvailable;
    self.lyricsButton.hidden = !_playerController.currentMediaIsAudioOnly && !lyricsAvailable;
    self.lyricsButton.state = _playerController.showLyrics ? NSControlStateValueOn : NSControlStateValueOff;
    self.lyricsButton.contentTintColor =
        _playerController.showLyrics ? MacLCDesign.accent : MacLCDesign.primaryLabel;
}

- (vout_thread_t *)windowVoutThread
{
    NSWindow * const window = self.floatOnTopButton.window;
    if ([window isKindOfClass:VLCVideoWindowCommon.class]) {
        vout_thread_t * const p_vout =
            ((VLCVideoWindowCommon *)window).videoViewController.voutView.voutThread;
        if (p_vout) return p_vout;
    }
    return _playerController.mainVideoOutputThread;
}

- (void)updateFloatOnTopButton
{
    vout_thread_t * const voutThread = [self windowVoutThread];
    if (voutThread == NULL) {
        return;
    }

    const bool floatOnTopEnabled = var_GetBool(voutThread, "video-on-top");
    vout_Release(voutThread);

    const BOOL isFullscreen = _playerController.fullscreen;
    self.floatOnTopButton.enabled = !isFullscreen;
    self.floatOnTopButton.contentTintColor =
        (floatOnTopEnabled && !isFullscreen) ? MacLCDesign.accent : MacLCDesign.primaryLabel;
}

/* The expansion only has somewhere to go when the screen the window is on is
 * currently offering extended range. That is not a fixed property of the
 * display: it moves with the brightness slider and with what else is on
 * screen, which is why the button is re-evaluated on screen changes. */
- (BOOL)hdrExpansionAvailable
{
    NSWindow * const window = self.hdrButton.window;
    NSScreen * const screen = window.screen ?: NSScreen.mainScreen;
    return screen.maximumExtendedDynamicRangeColorComponentValue > 1.0;
}

/* The expansion only ever runs on standard range video: a picture that is
 * already PQ or HLG is passed to the display layer untouched, so the switch
 * would have nothing to act on and is taken off the bar entirely. Read from the
 * elementary stream rather than from the video output, which is not up yet at
 * the point the bar first draws itself. */
- (BOOL)currentVideoIsAlreadyHDR
{
    const video_transfer_func_t transfer =
        _playerController.selectedVideoTrack.videoTransferFunction;
    return transfer == TRANSFER_FUNC_SMPTE_ST2084
        || transfer == TRANSFER_FUNC_HLG;
}

- (void)hdrExpansionChanged:(NSNotification *)notification
{
    [self updateHdrButton];
}

/* The HDR control is a format badge. For HDR video it names what is being
 * shown (DOLBY VISION, HDR10+, HDR10, HLG) and opens the HDR panel; for SDR
 * video on a display with extended range it switches SDR-to-HDR expansion. */
- (void)styleHdrBadgeWithTitle:(NSString *)title filled:(BOOL)filled dimmed:(BOOL)dimmed
{
    NSColor * const color = dimmed ? MacLCDesign.tertiaryLabel : MacLCDesign.primaryLabel;
    self.hdrButton.attributedTitle =
        [[NSAttributedString alloc] initWithString:title
                                        attributes:[MacLCDesign badgeTextAttributesWithColor:color]];
    self.hdrButton.wantsLayer = YES;
    self.hdrButton.layer.cornerRadius = 4.0;
    self.hdrButton.layer.borderWidth = 1.0;
    [self.hdrButton.effectiveAppearance performAsCurrentDrawingAppearance:^{
        self.hdrButton.layer.borderColor = color.CGColor;
        self.hdrButton.layer.backgroundColor =
            filled ? [MacLCDesign.primaryLabel colorWithAlphaComponent:0.14].CGColor
                   : NSColor.clearColor.CGColor;
    }];
}

- (void)updateHdrButton
{
    if (self.hdrButton == nil) {
        return;
    }

    if (_playerController.currentMediaIsAudioOnly) {
        self.hdrButton.hidden = YES;
        return;
    }
    self.hdrButton.hidden = NO;

    if ([self currentVideoIsAlreadyHDR]) {
        MacLCHDRController * const hdr = [MacLCHDRController sharedController];
        NSString * const name = MacLCHDRPresentationDisplayName(hdr.activePresentation);
        self.hdrButton.enabled = YES;
        self.hdrButton.state = NSControlStateValueOff;
        [self styleHdrBadgeWithTitle:MacLCHDRPresentationBadgeTitle(hdr.activePresentation)
                              filled:YES
                              dimmed:NO];
        self.hdrButton.toolTip =
            [NSString stringWithFormat:_NS("Playing in %@. Click for HDR options."), name];
        self.hdrButton.accessibilityLabel =
            [NSString stringWithFormat:_NS("HDR options, playing in %@"), name];
        return;
    }

    const BOOL enabled = MacLCConfigGetInt("macosx-sdr-to-hdr", 0) != 0;
    const BOOL available = [self hdrExpansionAvailable];

    self.hdrButton.enabled = available;
    self.hdrButton.state =
        enabled ? NSControlStateValueOn : NSControlStateValueOff;
    [self styleHdrBadgeWithTitle:@"HDR" filled:(enabled && available) dimmed:!available];
    self.hdrButton.accessibilityLabel = _NS("Play SDR video in HDR");

    if (!available) {
        self.hdrButton.toolTip =
            _NS("This display has no extended range right now, so there is "
                "nothing to play SDR video into.");
    } else if (enabled) {
        self.hdrButton.toolTip =
            _NS("SDR video is playing through the display's extended range. "
                "Click to go back to standard range.");
    } else {
        self.hdrButton.toolTip =
            _NS("Play SDR video through the display's extended range. "
                "Highlights get brighter; the picture is no longer the original "
                "grade and uses more power.");
    }
}

/* HDR video: open the HDR panel. SDR video: write the same setting the HDR
 * pane writes, and push it to whatever is playing so the picture changes under
 * the click rather than on the next file. */
- (IBAction)toggleHDR:(id)sender
{
    if ([self currentVideoIsAlreadyHDR]) {
        [MacLCHDRPanelViewController showRelativeToView:self.hdrButton
                                          preferredEdge:NSRectEdgeMaxY];
        return;
    }

    const BOOL enabled = MacLCConfigGetInt("macosx-sdr-to-hdr", 0) == 0;

    MacLCConfigPutInt("macosx-sdr-to-hdr", enabled ? 1 : 0);
    config_SaveConfigFile(getIntf());

    vout_thread_t * const p_vout = [self windowVoutThread];
    if (p_vout) {
        var_SetBool(p_vout, "macosx-sdr-to-hdr", enabled);
        vout_Release(p_vout);
    }

    [self updateHdrButton];
    [NSNotificationCenter.defaultCenter
        postNotificationName:MacLCHDRExpansionChangedNotification object:self];
}

- (void)playbackRateChanged:(NSNotification *)notification
{
    [self updatePlaybackRateButton];
}

- (void)updatePlaybackRateButton
{
    self.playbackRateButton.title =
        [NSString stringWithFormat:@"%.1fx", _playerController.playbackRate];
    self.playbackRateButton.enabled = _playerController.rateChangable;
    self.playbackRateButton.font = [MacLCDesign monospacedDigitFontForTextStyle:NSFontTextStyleCaption1 weight:NSFontWeightMedium];
    self.playbackRateButton.contentTintColor = MacLCDesign.primaryLabel;
}

- (IBAction)openPlaybackRate:(id)sender
{
    NSSlider * const playbackRateSlider = [[NSSlider alloc] init];
    playbackRateSlider.frame = NSMakeRect(0, 0, 272, 17);
    playbackRateSlider.target = self;
    playbackRateSlider.action = @selector(rateSliderAction:);
    playbackRateSlider.minValue = -34.;
    playbackRateSlider.maxValue = 34.;
    playbackRateSlider.sliderType = NSSliderTypeLinear;
    playbackRateSlider.numberOfTickMarks = 17;
    playbackRateSlider.controlSize = NSControlSizeSmall;

    const double value = 17.0 * log(_playerController.playbackRate) / log(2.);
    const int sliderIntValue = (int)((value > 0) ? value + 0.5 : value - 0.5);
    playbackRateSlider.intValue = sliderIntValue;

    const CGFloat inset = 12.;
    const CGFloat verticalInset = inset / 2.;
    const NSSize sliderSize = playbackRateSlider.frame.size;
    NSView * const containerView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, sliderSize.width + inset * 2, sliderSize.height + verticalInset * 2)];
    playbackRateSlider.frame = NSMakeRect(inset, verticalInset, sliderSize.width, sliderSize.height);
    [containerView addSubview:playbackRateSlider];

    NSMenuItem * const menuItem = [[NSMenuItem alloc] init];
    menuItem.title = _NS("Playback rate");
    menuItem.view = containerView;

    NSMenu * const menu = [[NSMenu alloc] initWithTitle:_NS("Playback rate")];
    [menu addItem:menuItem];
    [menu popUpMenuPositioningItem:nil
                        atLocation:self.playbackRateButton.frame.origin
                            inView:((NSView *)sender).superview];
}

- (IBAction)rateSliderAction:(id)sender
{
    NSSlider * const slider = (NSSlider *)sender;
    _playerController.playbackRate = pow(2, (double)slider.intValue / 17);
}

- (IBAction)openBookmarks:(id)sender
{
    [VLCMain.sharedInstance.bookmarks toggleWindow:sender];
}

- (IBAction)openSubtitlesMenu:(id)sender
{
    NSMenu * const menu = VLCMain.sharedInstance.mainMenu.subtitlesMenu;
    [menu popUpMenuPositioningItem:nil
                        atLocation:_subtitlesButton.frame.origin
                            inView:((NSView *)sender).superview];
}

- (IBAction)openAudioMenu:(id)sender
{
    NSMenu * const menu = VLCMain.sharedInstance.mainMenu.audioMenu;
    [menu popUpMenuPositioningItem:nil
                        atLocation:_audioButton.frame.origin
                            inView:((NSView *)sender).superview];
}

- (IBAction)openVideoMenu:(id)sender
{
    NSMenu * const menu = VLCMain.sharedInstance.mainMenu.videoMenu;
    [menu popUpMenuPositioningItem:nil
                        atLocation:self.videoButton.frame.origin
                            inView:((NSView *)sender).superview];
}

- (IBAction)toggleFloatOnTop:(id)sender
{
    vout_thread_t * const p_vout = [self windowVoutThread];
    if (!p_vout) {
        return;
    }
    var_ToggleBool(p_vout, "video-on-top");
    vout_Release(p_vout);
}

- (IBAction)toggleLyrics:(id)sender
{
    _playerController.showLyrics = !_playerController.showLyrics;
}

- (void)updateAvailableButtons:(id)sender
{
    const BOOL currentItemIsAudio = _playerController.currentMediaIsAudioOnly;
    self.videoButton.hidden = currentItemIsAudio;
    self.subtitlesButton.hidden = currentItemIsAudio;

    if (!VLCMain.sharedInstance.libraryController.shouldUseMediaLibrary) {
        self.bookmarksButton.hidden = YES;
    }

    [self updateLyricsButton:nil];
    [self updateHdrButton];
}

- (void)playerStateUpdated:(NSNotification *)notification
{
    [super playerStateUpdated:notification];
    self.playButton.contentTintColor = MacLCDesign.primaryLabel;
}

- (void)updateCurrentItemDisplayControls:(NSNotification *)notification
{
    [super updateCurrentItemDisplayControls:notification];
    self.forwardButton.contentTintColor = MacLCDesign.primaryLabel;
    self.backwardButton.contentTintColor = MacLCDesign.primaryLabel;
    self.jumpForwardButton.contentTintColor = MacLCDesign.primaryLabel;
    self.jumpBackwardButton.contentTintColor = MacLCDesign.primaryLabel;
}

- (void)updateMuteVolumeButtonImage
{
    [super updateMuteVolumeButtonImage];
    self.muteVolumeButton.contentTintColor = MacLCDesign.primaryLabel;
}

@end
