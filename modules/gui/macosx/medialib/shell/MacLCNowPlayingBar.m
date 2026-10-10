/*****************************************************************************
 * MacLCNowPlayingBar.m: floating Liquid Glass mini player of the library
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

#import "medialib/shell/MacLCNowPlayingBar.h"

#import "library/VLCLibraryWindow.h"
#import "theme/MacLCGlassView.h"
#import "theme/MacLCSymbolButton.h"
#import "theme/MacLCDesign.h"
#import "library/VLCInputItem.h"
#import "library/VLCLibraryImageCache.h"
#import "playqueue/VLCPlayQueueController.h"
#import "playqueue/VLCPlayQueueModel.h"
#import "playqueue/VLCPlayQueueItem.h"
#import "playqueue/VLCPlayerController.h"
#import "main/VLCMain.h"
#import "extensions/NSString+Helpers.h"
#import "windows/VLCDetachedAudioWindow.h"
#import "cast/MacLCCastController.h"
#import "torrent/MacLCTorrentBufferViews.h"
#import "torrent/MacLCTorrentMonitor.h"
#import "sound/MacLCSoundMode.h"
#import "sound/MacLCSoundPanelViewController.h"

#import <vlc_common.h>

@interface MacLCNowPlayingBar ()
{
    __weak VLCLibraryWindow *_libraryWindow;
    MacLCGlassView *_glassView;
    NSButton *_artworkButton;
    NSTextField *_titleLabel;
    NSTextField *_subtitleLabel;
    NSStackView *_titleStack;
    MacLCSymbolButton *_backwardButton;
    MacLCSymbolButton *_playPauseButton;
    MacLCSymbolButton *_forwardButton;
    NSTextField *_elapsedLabel;
    NSSlider *_slider;
    /* Downloaded ranges and the download head of a torrent, over the slider. */
    MacLCTorrentTrackOverlay *_downloadOverlay;
    NSTextField *_remainingLabel;
    MacLCSymbolButton *_volumeButton;
    MacLCSymbolButton *_soundButton;
    NSView *_airPlayButton;
    NSButton *_castButton;
    NSStackView *_trailingStack;
    NSPopover *_volumePopover;
    NSSlider *_volumeSlider;
    BOOL _isDraggingSlider;
    BOOL _shown;
    NSArray<NSLayoutConstraint *> *_superviewConstraints;
    BOOL _kvoRegistered;
    NSView *_liveVideoView;
    /* Narrow windows drop the times, then the slider takes what is left. */
    BOOL _compact;
    NSLayoutConstraint *_elapsedCollapsed;
    NSLayoutConstraint *_remainingCollapsed;
}

@end

@implementation MacLCNowPlayingBar

+ (CGFloat)reservedHeight
{
    return 76.0;
}

- (instancetype)initWithLibraryWindow:(VLCLibraryWindow *)libraryWindow
{
    self = [super initWithFrame:NSZeroRect];
    if (self) {
        _libraryWindow = libraryWindow;
        _shown = NO;
        self.wantsLayer = YES;
        self.hidden = YES;

        [self setupViews];
        [self registerNotifications];
        [self updateMetadata];
        [self updatePlaybackState];
        [self updateTimeAndPosition];
        [self updateVolumeState];
        [self updateSoundAndCastState];
        [self updateVisibilityAnimated:NO];
    }
    return self;
}

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
    if (_kvoRegistered && _libraryWindow != nil) {
        [_libraryWindow removeObserver:self
                            forKeyPath:VLCLibraryWindowEmbeddedVideoPlaybackActiveKey];
        _kvoRegistered = NO;
    }
}

- (BOOL)isShown
{
    return _shown;
}

/* Clear glass over a white page has no edge: a soft shadow lifts the capsule
 * off the content, as the system's floating controls do. */
- (void)layout
{
    [super layout];
    const BOOL compact = NSWidth(self.bounds) < 480.0;
    if (compact != _compact) {
        _compact = compact;
        _elapsedLabel.hidden = compact;
        _remainingLabel.hidden = compact;
        _elapsedCollapsed.active = compact;
        _remainingCollapsed.active = compact;
        self.needsLayout = YES;
    }
    const CGFloat radius = NSHeight(self.bounds) / 2.0;
    CGPathRef const path = CGPathCreateWithRoundedRect(NSRectToCGRect(self.bounds), radius, radius, NULL);
    self.layer.shadowPath = path;
    CGPathRelease(path);
    self.layer.shadowColor = NSColor.blackColor.CGColor;
    self.layer.shadowRadius = 12.0;
    self.layer.shadowOffset = CGSizeMake(0.0, -3.0);
    [self updateShadowOpacity];
}

- (void)viewDidChangeEffectiveAppearance
{
    [super viewDidChangeEffectiveAppearance];
    [self updateShadowOpacity];
}

- (void)updateShadowOpacity
{
    const BOOL dark = [self.effectiveAppearance bestMatchFromAppearancesWithNames:
        @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]] == NSAppearanceNameDarkAqua;
    self.layer.shadowOpacity = dark ? 0.45f : 0.16f;
}

- (void)viewDidMoveToSuperview
{
    [super viewDidMoveToSuperview];

    if (_superviewConstraints.count > 0) {
        [NSLayoutConstraint deactivateConstraints:_superviewConstraints];
        _superviewConstraints = nil;
    }

    NSView *superview = self.superview;
    if (superview == nil) {
        return;
    }

    self.translatesAutoresizingMaskIntoConstraints = NO;

    /* Below NSLayoutPriorityWindowSizeStayPut: the bar follows the window,
     * it must never size it (at DefaultHigh it pinned the window to 808 pt). */
    /* Centred between the floating sidebar and inspector, not under them. */
    NSLayoutGuide * const safeArea = superview.safeAreaLayoutGuide;
    NSLayoutConstraint *widthFit = [self.widthAnchor constraintEqualToAnchor:safeArea.widthAnchor constant:-48.0];
    widthFit.priority = NSLayoutPriorityDragThatCannotResizeWindow - 1;

    /* The margins give way before the window would: a narrow window squeezes
     * the bar (title, then slider) instead of refusing to shrink. */
    NSLayoutConstraint * const leadingMargin =
        [self.leadingAnchor constraintGreaterThanOrEqualToAnchor:safeArea.leadingAnchor constant:24.0];
    NSLayoutConstraint * const trailingMargin =
        [self.trailingAnchor constraintLessThanOrEqualToAnchor:safeArea.trailingAnchor constant:-24.0];
    leadingMargin.priority = NSLayoutPriorityDragThatCannotResizeWindow;
    trailingMargin.priority = NSLayoutPriorityDragThatCannotResizeWindow;
    _superviewConstraints = @[
        [self.bottomAnchor constraintEqualToAnchor:superview.bottomAnchor constant:-16.0],
        [self.centerXAnchor constraintEqualToAnchor:safeArea.centerXAnchor],
        [self.heightAnchor constraintEqualToConstant:60.0],
        [self.widthAnchor constraintLessThanOrEqualToConstant:760.0],
        widthFit,
        leadingMargin,
        trailingMargin,
    ];

    [NSLayoutConstraint activateConstraints:_superviewConstraints];
}

- (void)setupViews
{
    _glassView = [[MacLCGlassView alloc] initWithFrame:NSZeroRect];
    _glassView.translatesAutoresizingMaskIntoConstraints = NO;
    _glassView.cornerRadius = 30.0;
    [self addSubview:_glassView];

    [NSLayoutConstraint activateConstraints:@[
        [_glassView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_glassView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [_glassView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_glassView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
    ]];

    NSView *contentView = _glassView.contentView;

    _artworkButton = [[NSButton alloc] initWithFrame:NSZeroRect];
    _artworkButton.translatesAutoresizingMaskIntoConstraints = NO;
    _artworkButton.bordered = NO;
    _artworkButton.imagePosition = NSImageOnly;
    _artworkButton.imageScaling = NSImageScaleProportionallyUpOrDown;
    _artworkButton.wantsLayer = YES;
    _artworkButton.layer.cornerRadius = 6.0;
    _artworkButton.layer.masksToBounds = YES;
    _artworkButton.layer.cornerCurve = kCACornerCurveContinuous;
    _artworkButton.target = self;
    _artworkButton.action = @selector(artworkClicked:);
    _artworkButton.accessibilityLabel = _NS("Show Video");
    _artworkButton.toolTip = _NS("Show Video");
    [contentView addSubview:_artworkButton];

    _titleLabel = [NSTextField labelWithString:@""];
    _titleLabel.font = MacLCDesign.headline;
    _titleLabel.textColor = MacLCDesign.primaryLabel;
    _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    _titleLabel.maximumNumberOfLines = 1;
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_titleLabel setContentHuggingPriority:NSLayoutPriorityDefaultLow
                           forOrientation:NSLayoutConstraintOrientationHorizontal];
    [_titleLabel setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                          forOrientation:NSLayoutConstraintOrientationHorizontal];

    _subtitleLabel = [NSTextField labelWithString:@""];
    _subtitleLabel.font = MacLCDesign.subheadline;
    _subtitleLabel.textColor = MacLCDesign.secondaryLabel;
    _subtitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    _subtitleLabel.maximumNumberOfLines = 1;
    _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_subtitleLabel setContentHuggingPriority:NSLayoutPriorityDefaultLow
                              forOrientation:NSLayoutConstraintOrientationHorizontal];
    [_subtitleLabel setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                             forOrientation:NSLayoutConstraintOrientationHorizontal];

    _titleStack = [NSStackView stackViewWithViews:@[_titleLabel, _subtitleLabel]];
    _titleStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    _titleStack.alignment = NSLayoutAttributeLeading;
    _titleStack.spacing = 2.0;
    _titleStack.translatesAutoresizingMaskIntoConstraints = NO;
    /* Hugs a bit more than the slider, so the slider takes the spare width
     * (both at DefaultLow left the split between them ambiguous). */
    [_titleStack setContentHuggingPriority:NSLayoutPriorityDefaultLow + 1
                           forOrientation:NSLayoutConstraintOrientationHorizontal];
    [_titleStack setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                          forOrientation:NSLayoutConstraintOrientationHorizontal];
    [contentView addSubview:_titleStack];

    _backwardButton = [MacLCSymbolButton buttonWithSymbolName:@"backward.fill"
                                                       label:_NS("Previous")
                                                   pointSize:15.0
                                                      target:self
                                                      action:@selector(previousClicked:)];
    _backwardButton.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:_backwardButton];

    _playPauseButton = [MacLCSymbolButton buttonWithSymbolName:@"play.fill"
                                                         label:_NS("Play")
                                                     pointSize:24.0
                                                        target:self
                                                        action:@selector(playPauseClicked:)];
    _playPauseButton.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:_playPauseButton];

    _forwardButton = [MacLCSymbolButton buttonWithSymbolName:@"forward.fill"
                                                      label:_NS("Next")
                                                  pointSize:15.0
                                                     target:self
                                                     action:@selector(nextClicked:)];
    _forwardButton.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:_forwardButton];

    _elapsedLabel = [NSTextField labelWithString:@"0:00"];
    _elapsedLabel.font = [MacLCDesign monospacedDigitFontForTextStyle:NSFontTextStyleFootnote];
    _elapsedLabel.textColor = MacLCDesign.secondaryLabel;
    _elapsedLabel.alignment = NSTextAlignmentRight;
    _elapsedLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_elapsedLabel setContentHuggingPriority:NSLayoutPriorityRequired
                             forOrientation:NSLayoutConstraintOrientationHorizontal];
    [_elapsedLabel setContentCompressionResistancePriority:NSLayoutPriorityDefaultHigh
                                           forOrientation:NSLayoutConstraintOrientationHorizontal];
    _elapsedCollapsed = [_elapsedLabel.widthAnchor constraintEqualToConstant:0.0];
    _elapsedCollapsed.priority = NSLayoutPriorityRequired - 1;
    [contentView addSubview:_elapsedLabel];

    _slider = [[NSSlider alloc] initWithFrame:NSZeroRect];
    _slider.translatesAutoresizingMaskIntoConstraints = NO;
    _slider.sliderType = NSSliderTypeLinear;
    _slider.controlSize = NSControlSizeSmall;
    _slider.minValue = 0.0;
    _slider.maxValue = 1.0;
    _slider.doubleValue = 0.0;
    _slider.continuous = YES;
    _slider.target = self;
    _slider.action = @selector(sliderAction:);
    _slider.accessibilityLabel = _NS("Playback Position");
    _slider.toolTip = _NS("Playback Position");
    [_slider setContentHuggingPriority:NSLayoutPriorityDefaultLow
                        forOrientation:NSLayoutConstraintOrientationHorizontal];
    [contentView addSubview:_slider];

    _downloadOverlay = [[MacLCTorrentTrackOverlay alloc] initWithFrame:NSZeroRect];
    _downloadOverlay.translatesAutoresizingMaskIntoConstraints = NO;
    _downloadOverlay.slider = _slider;
    [contentView addSubview:_downloadOverlay positioned:NSWindowAbove relativeTo:_slider];
    [NSLayoutConstraint activateConstraints:@[
        [_downloadOverlay.leadingAnchor constraintEqualToAnchor:_slider.leadingAnchor],
        [_downloadOverlay.trailingAnchor constraintEqualToAnchor:_slider.trailingAnchor],
        [_downloadOverlay.topAnchor constraintEqualToAnchor:_slider.topAnchor],
        [_downloadOverlay.bottomAnchor constraintEqualToAnchor:_slider.bottomAnchor],
    ]];

    _remainingLabel = [NSTextField labelWithString:@"--:--"];
    _remainingLabel.font = [MacLCDesign monospacedDigitFontForTextStyle:NSFontTextStyleFootnote];
    _remainingLabel.textColor = MacLCDesign.secondaryLabel;
    _remainingLabel.alignment = NSTextAlignmentLeft;
    _remainingLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_remainingLabel setContentHuggingPriority:NSLayoutPriorityRequired
                               forOrientation:NSLayoutConstraintOrientationHorizontal];
    [_remainingLabel setContentCompressionResistancePriority:NSLayoutPriorityDefaultHigh
                                             forOrientation:NSLayoutConstraintOrientationHorizontal];
    _remainingCollapsed = [_remainingLabel.widthAnchor constraintEqualToConstant:0.0];
    _remainingCollapsed.priority = NSLayoutPriorityRequired - 1;
    [contentView addSubview:_remainingLabel];

    _volumeButton = [MacLCSymbolButton buttonWithSymbolName:@"speaker.wave.2.fill"
                                                      label:_NS("Volume")
                                                  pointSize:15.0
                                                     target:self
                                                     action:@selector(volumeClicked:)];
    _volumeButton.translatesAutoresizingMaskIntoConstraints = NO;

    _soundButton = [MacLCSymbolButton buttonWithSymbolName:@"slider.vertical.3"
                                                     label:_NS("Sound")
                                                 pointSize:15.0
                                                    target:self
                                                    action:@selector(soundClicked:)];
    _soundButton.translatesAutoresizingMaskIntoConstraints = NO;
    [MacLCSoundPanelViewController registerAnchorView:_soundButton];

    MacLCCastController * const cast = MacLCCastController.sharedController;
    _airPlayButton = [cast makeAirPlayButtonWithTint:MacLCDesign.primaryLabel];
    _airPlayButton.translatesAutoresizingMaskIntoConstraints = NO;
    _castButton = [cast makeCastButton];
    _castButton.translatesAutoresizingMaskIntoConstraints = NO;

    /* Sound, then the destinations (AirPlay, Play On), then the volume: the
     * output-related controls stay together at the trailing edge. */
    _trailingStack = [NSStackView stackViewWithViews:@[_soundButton, _airPlayButton, _castButton, _volumeButton]];
    _trailingStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    _trailingStack.alignment = NSLayoutAttributeCenterY;
    _trailingStack.spacing = 4.0;
    _trailingStack.detachesHiddenViews = YES;
    _trailingStack.translatesAutoresizingMaskIntoConstraints = NO;
    [_trailingStack setContentHuggingPriority:NSLayoutPriorityRequired
                               forOrientation:NSLayoutConstraintOrientationHorizontal];
    [contentView addSubview:_trailingStack];

    NSLayoutConstraint * const sliderMinimumWidth = [_slider.widthAnchor constraintGreaterThanOrEqualToConstant:160.0];
    sliderMinimumWidth.priority = NSLayoutPriorityDragThatCannotResizeWindow - 2;
    [NSLayoutConstraint activateConstraints:@[
        [_artworkButton.widthAnchor constraintEqualToConstant:40.0],
        [_artworkButton.heightAnchor constraintEqualToConstant:40.0],
        [_artworkButton.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:12.0],
        [_artworkButton.centerYAnchor constraintEqualToAnchor:contentView.centerYAnchor],

        [_titleStack.leadingAnchor constraintEqualToAnchor:_artworkButton.trailingAnchor constant:10.0],
        [_titleStack.centerYAnchor constraintEqualToAnchor:contentView.centerYAnchor],
        [_titleStack.trailingAnchor constraintLessThanOrEqualToAnchor:_backwardButton.leadingAnchor constant:-8.0],

        [_backwardButton.widthAnchor constraintGreaterThanOrEqualToConstant:28.0],
        [_backwardButton.heightAnchor constraintGreaterThanOrEqualToConstant:28.0],
        [_backwardButton.centerYAnchor constraintEqualToAnchor:contentView.centerYAnchor],

        [_playPauseButton.widthAnchor constraintEqualToConstant:36.0],
        [_playPauseButton.heightAnchor constraintEqualToConstant:36.0],
        [_playPauseButton.leadingAnchor constraintEqualToAnchor:_backwardButton.trailingAnchor constant:4.0],
        [_playPauseButton.centerYAnchor constraintEqualToAnchor:contentView.centerYAnchor],

        [_forwardButton.widthAnchor constraintGreaterThanOrEqualToConstant:28.0],
        [_forwardButton.heightAnchor constraintGreaterThanOrEqualToConstant:28.0],
        [_forwardButton.leadingAnchor constraintEqualToAnchor:_playPauseButton.trailingAnchor constant:4.0],
        [_forwardButton.centerYAnchor constraintEqualToAnchor:contentView.centerYAnchor],

        [_elapsedLabel.leadingAnchor constraintEqualToAnchor:_forwardButton.trailingAnchor constant:12.0],
        [_elapsedLabel.centerYAnchor constraintEqualToAnchor:contentView.centerYAnchor],

        [_slider.leadingAnchor constraintEqualToAnchor:_elapsedLabel.trailingAnchor constant:8.0],
        [_slider.centerYAnchor constraintEqualToAnchor:contentView.centerYAnchor],
        sliderMinimumWidth,

        [_remainingLabel.leadingAnchor constraintEqualToAnchor:_slider.trailingAnchor constant:8.0],
        [_remainingLabel.centerYAnchor constraintEqualToAnchor:contentView.centerYAnchor],

        [_volumeButton.widthAnchor constraintGreaterThanOrEqualToConstant:28.0],
        [_volumeButton.heightAnchor constraintGreaterThanOrEqualToConstant:28.0],
        [_soundButton.widthAnchor constraintGreaterThanOrEqualToConstant:28.0],
        [_soundButton.heightAnchor constraintGreaterThanOrEqualToConstant:28.0],
        [_airPlayButton.widthAnchor constraintEqualToConstant:28.0],
        [_airPlayButton.heightAnchor constraintEqualToConstant:28.0],
        [_castButton.widthAnchor constraintEqualToConstant:28.0],
        [_castButton.heightAnchor constraintEqualToConstant:28.0],
        [_trailingStack.leadingAnchor constraintEqualToAnchor:_remainingLabel.trailingAnchor constant:12.0],
        [_trailingStack.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-12.0],
        [_trailingStack.centerYAnchor constraintEqualToAnchor:contentView.centerYAnchor],
    ]];
}

- (void)registerNotifications
{
    NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;

    [nc addObserver:self
           selector:@selector(handleTorrentUpdate:)
               name:MacLCTorrentMonitorDidUpdateNotification
             object:nil];
    [MacLCTorrentMonitor.sharedMonitor start];

    [nc addObserver:self
           selector:@selector(handleSoundModeChange:)
               name:MacLCSoundModeDidChangeNotification
             object:nil];
    [nc addObserver:self
           selector:@selector(handleCastStateChange:)
               name:MacLCCastStateDidChangeNotification
             object:nil];

    [nc addObserver:self
           selector:@selector(handlePlayQueueChange:)
               name:VLCPlayQueueCurrentItemIndexChanged
             object:nil];
    [nc addObserver:self
           selector:@selector(handlePlayQueueChange:)
               name:VLCPlayQueueItemsAdded
             object:nil];
    [nc addObserver:self
           selector:@selector(handlePlayQueueChange:)
               name:VLCPlayQueueItemsRemoved
             object:nil];

    [nc addObserver:self
           selector:@selector(handleMediaChange:)
               name:VLCPlayerCurrentMediaItemChanged
             object:nil];
    [nc addObserver:self
           selector:@selector(handleMediaChange:)
               name:VLCPlayerMetadataChangedForCurrentMedia
             object:nil];

    [nc addObserver:self
           selector:@selector(handleStateChange:)
               name:VLCPlayerStateChanged
             object:nil];
    [nc addObserver:self
           selector:@selector(handleTimePositionChange:)
               name:VLCPlayerTimeAndPositionChanged
             object:nil];
    [nc addObserver:self
           selector:@selector(handleTimePositionChange:)
               name:VLCPlayerLengthChanged
             object:nil];

    [nc addObserver:self
           selector:@selector(handleNavigationChange:)
               name:VLCPlaybackHasPreviousChanged
             object:nil];
    [nc addObserver:self
           selector:@selector(handleNavigationChange:)
               name:VLCPlaybackHasNextChanged
             object:nil];

    [nc addObserver:self
           selector:@selector(handleVolumeChange:)
               name:VLCPlayerVolumeChanged
             object:nil];
    [nc addObserver:self
           selector:@selector(handleVolumeChange:)
               name:VLCPlayerMuteChanged
             object:nil];

    if (_libraryWindow != nil) {
        [_libraryWindow addObserver:self
                         forKeyPath:VLCLibraryWindowEmbeddedVideoPlaybackActiveKey
                            options:NSKeyValueObservingOptionNew
                            context:nil];
        _kvoRegistered = YES;
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey,id> *)change
                       context:(void *)context
{
    if ([keyPath isEqualToString:VLCLibraryWindowEmbeddedVideoPlaybackActiveKey]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self updateVisibilityAnimated:YES];
        });
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

#pragma mark - State Updaters

- (void)updateVisibilityAnimated:(BOOL)animated
{
    BOOL hasCurrentItem = NO;
    VLCPlayQueueController *playQueue = VLCMain.sharedInstance.playQueueController;
    if (playQueue != nil) {
        size_t idx = playQueue.currentPlayQueueIndex;
        if (idx != (size_t)-1 && idx < playQueue.playQueueModel.numberOfPlayQueueItems) {
            hasCurrentItem = YES;
        }
    }

    BOOL embeddedVideo = NO;
    if (_libraryWindow != nil) {
        embeddedVideo = _libraryWindow.embeddedVideoPlaybackActive;
    }

    BOOL shouldShow = hasCurrentItem && !embeddedVideo;
    [self setShown:shouldShow animated:animated];
}

- (void)setShown:(BOOL)shown animated:(BOOL)animated
{
    if (_shown == shown) {
        return;
    }
    _shown = shown;
    if (self.visibilityHandler != nil) {
        self.visibilityHandler(shown);
    }

    if (animated) {
        if (shown) {
            self.hidden = NO;
            [MacLCDesign animateEntranceOfView:self];
        } else {
            [MacLCDesign animateExitOfView:self completion:nil];
        }
    } else {
        self.hidden = !shown;
        self.alphaValue = shown ? 1.0 : 0.0;
    }
}

- (void)setLiveVideoView:(NSView *)videoView
{
    if (_liveVideoView == videoView) {
        return;
    }

    NSView * const artworkContainer = _artworkButton.superview;
    if (_liveVideoView != nil) {
        _liveVideoView.layer.cornerRadius = 0.0;
        _liveVideoView.layer.masksToBounds = NO;
        /* The video view controller may already have taken the view back. */
        if (_liveVideoView.superview == artworkContainer) {
            [_liveVideoView removeFromSuperview];
        }
    }
    _liveVideoView = videoView;

    if (videoView == nil) {
        [self updateMetadata];
        return;
    }

    /* The borderless button stays on top, without an image, so a click on the
     * picture still brings the video back. */
    _artworkButton.image = nil;
    videoView.translatesAutoresizingMaskIntoConstraints = NO;
    videoView.wantsLayer = YES;
    videoView.layer.cornerRadius = 6.0;
    videoView.layer.cornerCurve = kCACornerCurveContinuous;
    videoView.layer.masksToBounds = YES;
    [artworkContainer addSubview:videoView positioned:NSWindowBelow relativeTo:_artworkButton];
    [NSLayoutConstraint activateConstraints:@[
        [videoView.leadingAnchor constraintEqualToAnchor:_artworkButton.leadingAnchor],
        [videoView.trailingAnchor constraintEqualToAnchor:_artworkButton.trailingAnchor],
        [videoView.topAnchor constraintEqualToAnchor:_artworkButton.topAnchor],
        [videoView.bottomAnchor constraintEqualToAnchor:_artworkButton.bottomAnchor],
    ]];
}

- (void)updateMetadata
{
    VLCPlayQueueController *playQueue = VLCMain.sharedInstance.playQueueController;
    VLCPlayerController *player = playQueue.playerController;

    size_t currentIndex = playQueue.currentPlayQueueIndex;
    VLCPlayQueueItem *currentItem = nil;
    if (currentIndex != (size_t)-1 && currentIndex < playQueue.playQueueModel.numberOfPlayQueueItems) {
        currentItem = [playQueue.playQueueModel playQueueItemAtIndex:currentIndex];
    }

    /* The tagged title first: the item's name is often just its file name. */
    NSString *title = player.currentMedia.title;
    if (title.length == 0) {
        title = currentItem.title;
    }
    if (title.length == 0) {
        title = player.nameOfCurrentMediaItem ?: @"";
    }
    _titleLabel.stringValue = title;

    BOOL isAudio = player.currentMediaIsAudioOnly ||
                   (player.videoTracks.count == 0 && player.audioTracks.count > 0);

    if (isAudio) {
        NSString *artist = currentItem.artistName;
        NSString *album = currentItem.albumName;
        if (artist.length > 0 && album.length > 0) {
            _subtitleLabel.stringValue = [NSString stringWithFormat:@"%@ · %@", artist, album];
        } else if (artist.length > 0) {
            _subtitleLabel.stringValue = artist;
        } else if (album.length > 0) {
            _subtitleLabel.stringValue = album;
        } else {
            _subtitleLabel.stringValue = _NS("Audio");
        }
        NSString *label = _NS("Show Player");
        _artworkButton.accessibilityLabel = label;
        _artworkButton.toolTip = label;
    } else {
        _subtitleLabel.stringValue = _NS("Video");
        NSString *label = _NS("Show Video");
        _artworkButton.accessibilityLabel = label;
        _artworkButton.toolTip = label;
    }

    /* While casting, say where the media plays. */
    MacLCCastController * const cast = MacLCCastController.sharedController;
    if (cast.isCasting) {
        _subtitleLabel.stringValue = cast.destinationIsAirPlay
            ? _NS("Playing on AirPlay")
            : [NSString stringWithFormat:_NS("Playing on %@"), cast.destinationName ?: _NS("TV")];
    }

    if (cast.isCasting && _liveVideoView == nil) {
        /* Nothing plays here: show where it plays instead of stale artwork. */
        _artworkButton.image = [MacLCDesign symbolNamed:cast.destinationIsAirPlay ? @"airplay.video" : @"tv"
                                             pointSize:18.0
                                                weight:NSFontWeightMedium
                                    accessibilityLabel:nil];
    } else if (_liveVideoView != nil) {
        /* The live video stands in for the artwork. */
    } else if (currentItem != nil) {
        [VLCLibraryImageCache thumbnailForPlayQueueItem:currentItem
                                         withCompletion:^(const NSImage *thumbnail) {
            dispatch_async(dispatch_get_main_queue(), ^{
                /* Skip artwork that arrives after the track changed. */
                VLCPlayQueueController * const queue = VLCMain.sharedInstance.playQueueController;
                const size_t index = queue.currentPlayQueueIndex;
                VLCPlayQueueItem * const playing =
                    index != (size_t)-1 && index < queue.playQueueModel.numberOfPlayQueueItems
                        ? [queue.playQueueModel playQueueItemAtIndex:index] : nil;
                if (self->_liveVideoView != nil || playing != currentItem) {
                    return;
                }
                if (thumbnail != nil) {
                    self->_artworkButton.image = (NSImage *)thumbnail;
                } else {
                    NSString *placeholder = isAudio ? @"music.note" : @"film";
                    self->_artworkButton.image = [MacLCDesign symbolNamed:placeholder
                                                               pointSize:18.0
                                                                  weight:NSFontWeightMedium
                                                      accessibilityLabel:nil];
                }
            });
        }];
    } else {
        NSString *placeholder = isAudio ? @"music.note" : @"film";
        _artworkButton.image = [MacLCDesign symbolNamed:placeholder
                                             pointSize:18.0
                                                weight:NSFontWeightMedium
                                    accessibilityLabel:nil];
    }

    [self updateNavigationState];
}

- (void)updatePlaybackState
{
    VLCPlayerController *player = VLCMain.sharedInstance.playQueueController.playerController;
    if (player.playerState == VLC_PLAYER_STATE_PLAYING) {
        [_playPauseButton setSymbolName:@"pause.fill" animated:YES];
        _playPauseButton.label = _NS("Pause");
    } else {
        [_playPauseButton setSymbolName:@"play.fill" animated:YES];
        _playPauseButton.label = _NS("Play");
    }
}

- (void)updateNavigationState
{
    VLCPlayQueueController *playQueue = VLCMain.sharedInstance.playQueueController;
    _backwardButton.enabled = playQueue.hasPreviousPlayQueueItem;
    _forwardButton.enabled = playQueue.hasNextPlayQueueItem;
}

/* A torrent is playing: the part already downloaded shows on the slider and
 * the tooltip says how it goes. No marker here, the bar stays quiet. */
- (void)handleTorrentUpdate:(NSNotification *)notification
{
    MacLCTorrentMonitor * const monitor = MacLCTorrentMonitor.sharedMonitor;
    MacLCTorrentReaderInfo * const reader = monitor.reader;
    MacLCTorrentInfo * const torrent = monitor.torrent;
    NSString * const defaultTip = _NS("Playback Position");

    if (monitor.active && reader != nil && torrent != nil && reader.size > 0) {
        _downloadOverlay.ranges = reader.rangeFractions;
        _downloadOverlay.headFraction = reader.headFraction;
        NSString * const tip = reader.headFraction < 0.999
            ? [MacLCTorrentHeadMarker summaryForTorrent:torrent]
            : defaultTip;
        self.toolTip = tip;
        _slider.toolTip = tip;
    } else {
        _downloadOverlay.ranges = nil;
        _downloadOverlay.headFraction = -1.0;
        self.toolTip = nil;
        _slider.toolTip = defaultTip;
    }
}

- (void)updateTimeAndPosition
{
    if (_isDraggingSlider) {
        return;
    }

    VLCPlayerController *player = VLCMain.sharedInstance.playQueueController.playerController;
    if (!player) {
        return;
    }

    _slider.doubleValue = player.position;
    _downloadOverlay.needsDisplay = YES;

    vlc_tick_t time = player.time;
    vlc_tick_t length = player.length;

    if (time != VLC_TICK_INVALID && time >= 0) {
        _elapsedLabel.stringValue = [NSString stringWithTimeFromTicks:time];
        if (length > 0) {
            _remainingLabel.stringValue = [NSString stringWithDuration:length
                                                           currentTime:time
                                                              negative:YES];
        } else {
            _remainingLabel.stringValue = @"";
        }
    } else {
        _elapsedLabel.stringValue = @"0:00";
        _remainingLabel.stringValue = @"--:--";
    }

    _slider.enabled = player.seekable && length > 0;
}

- (void)updateVolumeState
{
    VLCPlayerController *player = VLCMain.sharedInstance.playQueueController.playerController;
    if (!player) {
        return;
    }

    if (_volumeSlider != nil) {
        _volumeSlider.floatValue = player.volume;
    }

    if (player.mute) {
        [_volumeButton setSymbolName:@"speaker.slash.fill" animated:YES];
    } else if (player.volume <= 0.001) {
        [_volumeButton setSymbolName:@"speaker.fill" animated:YES];
    } else if (player.volume <= 0.5) {
        [_volumeButton setSymbolName:@"speaker.wave.1.fill" animated:YES];
    } else {
        [_volumeButton setSymbolName:@"speaker.wave.2.fill" animated:YES];
    }
}

#pragma mark - Notification Handlers

- (void)handlePlayQueueChange:(NSNotification *)notification
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateMetadata];
        [self updateVisibilityAnimated:YES];
    });
}

- (void)handleMediaChange:(NSNotification *)notification
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateMetadata];
        [self updateTimeAndPosition];
        [self updateVisibilityAnimated:YES];
    });
}

- (void)handleStateChange:(NSNotification *)notification
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updatePlaybackState];
        [self updateVisibilityAnimated:YES];
    });
}

- (void)handleTimePositionChange:(NSNotification *)notification
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateTimeAndPosition];
    });
}

- (void)handleNavigationChange:(NSNotification *)notification
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateNavigationState];
    });
}

- (void)handleVolumeChange:(NSNotification *)notification
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateVolumeState];
    });
}

#pragma mark - Actions

- (void)artworkClicked:(id)sender
{
    VLCPlayerController *player = VLCMain.sharedInstance.playQueueController.playerController;
    BOOL isAudio = player.currentMediaIsAudioOnly ||
                   (player.videoTracks.count == 0 && player.audioTracks.count > 0);

    if (isAudio) {
        [VLCMain.sharedInstance.detachedAudioWindow makeKeyAndOrderFront:self];
    } else {
        if (_libraryWindow != nil) {
            [_libraryWindow enableVideoPlaybackAppearance];
        }
    }
}

- (void)previousClicked:(id)sender
{
    [VLCMain.sharedInstance.playQueueController playPreviousItem];
}

- (void)playPauseClicked:(id)sender
{
    [VLCMain.sharedInstance.playQueueController.playerController togglePlayPause];
}

- (void)nextClicked:(id)sender
{
    [VLCMain.sharedInstance.playQueueController playNextItem];
}

- (void)sliderAction:(NSSlider *)sender
{
    VLCPlayerController *player = VLCMain.sharedInstance.playQueueController.playerController;
    if (!player) {
        return;
    }

    NSEvent *event = NSApp.currentEvent;
    NSEventType type = event.type;

    switch (type) {
        case NSEventTypeLeftMouseDown:
        case NSEventTypeLeftMouseDragged:
        case NSEventTypeScrollWheel: {
            _isDraggingSlider = YES;
            float pos = sender.floatValue;
            [player setPositionFast:pos];
            vlc_tick_t length = player.length;
            if (length > 0) {
                vlc_tick_t current = (vlc_tick_t)(pos * length);
                _elapsedLabel.stringValue = [NSString stringWithTimeFromTicks:current];
                _remainingLabel.stringValue = [NSString stringWithDuration:length
                                                               currentTime:current
                                                                  negative:YES];
            }
            break;
        }
        case NSEventTypeLeftMouseUp: {
            _isDraggingSlider = NO;
            float pos = sender.floatValue;
            [player setPositionPrecise:pos];
            break;
        }
        default: {
            float pos = sender.floatValue;
            [player setPositionPrecise:pos];
            break;
        }
    }
}

- (void)soundClicked:(id)sender
{
    /* Option-click turns the current Sound mode on or off. */
    if ((NSApp.currentEvent.modifierFlags & NSEventModifierFlagOption) != 0) {
        MacLCSoundMode.sharedMode.enabled = !MacLCSoundMode.sharedMode.isEnabled;
        return;
    }
    [MacLCSoundPanelViewController showRelativeToView:_soundButton preferredEdge:NSRectEdgeMaxY];
}

- (void)handleSoundModeChange:(NSNotification *)notification
{
    [self updateSoundAndCastState];
}

- (void)handleCastStateChange:(NSNotification *)notification
{
    [self updateSoundAndCastState];
    [self updateMetadata];
}

- (void)updateSoundAndCastState
{
    _soundButton.contentTintColor = MacLCSoundMode.sharedMode.isEnabled ? MacLCDesign.accent : MacLCDesign.primaryLabel;
    MacLCCastController * const cast = MacLCCastController.sharedController;
    _airPlayButton.hidden = !cast.hasAirPlayRoutes && !cast.destinationIsAirPlay;
}

- (void)volumeClicked:(id)sender
{
    if (_volumePopover != nil && _volumePopover.isShown) {
        [_volumePopover close];
        return;
    }

    VLCPlayerController *player = VLCMain.sharedInstance.playQueueController.playerController;

    _volumePopover = [[NSPopover alloc] init];
    _volumePopover.behavior = NSPopoverBehaviorTransient;

    NSViewController *vc = [[NSViewController alloc] init];
    NSView *container = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 160, 36)];

    _volumeSlider = [[NSSlider alloc] initWithFrame:NSMakeRect(14, 6, 132, 24)];
    _volumeSlider.sliderType = NSSliderTypeLinear;
    _volumeSlider.controlSize = NSControlSizeSmall;
    _volumeSlider.minValue = 0.0;
    _volumeSlider.maxValue = VLCVolumeMaximum;
    _volumeSlider.floatValue = player.volume;
    _volumeSlider.continuous = YES;
    _volumeSlider.target = self;
    _volumeSlider.action = @selector(volumeSliderChanged:);
    _volumeSlider.accessibilityLabel = _NS("Volume");
    _volumeSlider.toolTip = _NS("Volume");

    [container addSubview:_volumeSlider];
    vc.view = container;
    _volumePopover.contentViewController = vc;

    [_volumePopover showRelativeToRect:_volumeButton.bounds
                                ofView:_volumeButton
                         preferredEdge:NSRectEdgeMaxY];
}

- (void)volumeSliderChanged:(NSSlider *)sender
{
    VLCPlayerController *player = VLCMain.sharedInstance.playQueueController.playerController;
    if (!player) {
        return;
    }

    player.volume = sender.floatValue;
    if (player.mute && sender.floatValue > 0.001) {
        player.mute = NO;
    }
    [self updateVolumeState];
}

@end
