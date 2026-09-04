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

    [self update];
}

- (void)update
{
    [super update];
    [self updateFloatOnTopButton];
    [self updatePlaybackRateButton];
    [self updateLyricsButton:nil];
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
