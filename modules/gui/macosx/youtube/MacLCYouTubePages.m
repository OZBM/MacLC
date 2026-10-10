/*****************************************************************************
 * MacLCYouTubePages.m: channel, playlist, and video view controllers
 *****************************************************************************
 * Copyright (C) 2026 Hazen Studio
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation; either version 2.1 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/

#import "youtube/MacLCYouTubeSections.h"
#import "youtube/MacLCYouTubeViews.h"
#import "youtube/MacLCYouTubeModel.h"
#import "youtube/MacLCYouTubeService.h"
#import "youtube/MacLCYouTubeAccount.h"

#import "addons/watch/MacLCWatchComponents.h"
#import "medialib/components/MacLCSectionHeaderView.h"
#import "medialib/components/MacLCEmptyStateView.h"
#import "medialib/components/MacLCCollectionLayout.h"
#import "theme/MacLCDesign.h"

#import <QuartzCore/QuartzCore.h>

#ifndef _NS
#define _NS(s) @(s)
#endif
#ifndef _NPS
#define _NPS(s, p, n) ((n) == 1 ? [NSString stringWithFormat:@(s), (n)] : [NSString stringWithFormat:@(p), (n)])
#endif

static const CGFloat kMacLCYouTubeVideoMaxThumbnailWidth = 960.0;
static const CGFloat kMacLCYouTubeChannelAvatarSize = 88.0;
static const CGFloat kMacLCYouTubePlaylistThumbnailWidth = 360.0;
static const CGFloat kMacLCYouTubePlaylistRowHeight = 98.0;

#pragma mark - Aspect-Fill Image View

/* NSImageView only scales to fit; heroes and banners fill their box and let
 * the overflow fall outside (the layer clips). */
@interface MacLCYouTubeFillImageView : NSView
@property (nonatomic, strong, nullable) NSImage *image;
@end

@implementation MacLCYouTubeFillImageView

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        self.layer.contentsGravity = kCAGravityResizeAspectFill;
        self.layer.masksToBounds = YES;
    }
    return self;
}

- (void)setImage:(NSImage *)image
{
    _image = image;
    self.layer.contents = image != nil ? [image layerContentsForContentsScale:self.window.backingScaleFactor ?: 2.0] : nil;
}

- (BOOL)isFlipped
{
    return NO;
}

@end

#pragma mark - Duration Badge View

@interface MacLCYouTubeDurationBadgeView : NSView
@property (nonatomic, strong, readonly) NSTextField *label;
@property (nonatomic, strong, readonly) NSView *dotView;
- (void)configureWithVideo:(nullable MacLCYouTubeVideo *)video;
@end

@implementation MacLCYouTubeDurationBadgeView

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        self.layer.masksToBounds = YES;
        self.layer.cornerRadius = 4.0;
        self.layer.backgroundColor = [NSColor colorWithWhite:0.0 alpha:0.78].CGColor;

        _dotView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 6.0, 6.0)];
        _dotView.translatesAutoresizingMaskIntoConstraints = NO;
        _dotView.wantsLayer = YES;
        _dotView.layer.cornerRadius = 3.0;
        _dotView.layer.backgroundColor = NSColor.whiteColor.CGColor;
        _dotView.hidden = YES;
        [self addSubview:_dotView];

        _label = [NSTextField labelWithString:@""];
        _label.translatesAutoresizingMaskIntoConstraints = NO;
        _label.font = [NSFont monospacedDigitSystemFontOfSize:12.0 weight:NSFontWeightSemibold];
        _label.textColor = NSColor.whiteColor;
        _label.alignment = NSTextAlignmentCenter;
        [self addSubview:_label];

        [NSLayoutConstraint activateConstraints:@[
            [_dotView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:6.0],
            [_dotView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_dotView.widthAnchor constraintEqualToConstant:6.0],
            [_dotView.heightAnchor constraintEqualToConstant:6.0],

            [_label.leadingAnchor constraintEqualToAnchor:_dotView.trailingAnchor constant:4.0],
            [_label.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-6.0],
            [_label.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_label.topAnchor constraintGreaterThanOrEqualToAnchor:self.topAnchor constant:2.0],
            [_label.bottomAnchor constraintLessThanOrEqualToAnchor:self.bottomAnchor constant:-2.0],
        ]];
    }
    return self;
}

- (void)configureWithVideo:(nullable MacLCYouTubeVideo *)video
{
    if (!video) {
        self.hidden = YES;
        return;
    }

    if (video.isLive) {
        self.hidden = NO;
        self.layer.backgroundColor = NSColor.systemRedColor.CGColor;
        _dotView.hidden = NO;
        _label.stringValue = _NS("LIVE");
    } else if (video.isUpcoming) {
        self.hidden = NO;
        self.layer.backgroundColor = [NSColor colorWithWhite:0.0 alpha:0.78].CGColor;
        _dotView.hidden = YES;
        _label.stringValue = _NS("UPCOMING");
    } else if (video.duration > 0) {
        self.hidden = NO;
        self.layer.backgroundColor = [NSColor colorWithWhite:0.0 alpha:0.78].CGColor;
        _dotView.hidden = YES;
        _label.stringValue = [MacLCYouTubeFormat durationString:video.duration];
    } else {
        self.hidden = YES;
    }
}

@end

#pragma mark - Centered Glass Play Button

@interface MacLCYouTubeCentredGlassPlayButton : NSControl
@property (nonatomic, copy, nullable) void (^clickHandler)(void);
@end

@implementation MacLCYouTubeCentredGlassPlayButton {
    NSView *_materialView;
    NSImageView *_playImageView;
    NSTrackingArea *_trackingArea;
}

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        self.layer.cornerRadius = 32.0;
        self.layer.masksToBounds = YES;
        self.accessibilityRole = NSAccessibilityButtonRole;
        self.accessibilityLabel = _NS("Play");
        self.toolTip = _NS("Play");

        if (@available(macOS 26.0, *)) {
            NSGlassEffectView *glass = [[NSGlassEffectView alloc] initWithFrame:self.bounds];
            glass.style = NSGlassEffectViewStyleRegular;
            glass.translatesAutoresizingMaskIntoConstraints = NO;
            glass.wantsLayer = YES;
            glass.layer.cornerRadius = 32.0;
            glass.layer.masksToBounds = YES;
            [self addSubview:glass];
            _materialView = glass;
        } else {
            NSVisualEffectView *vev = [MacLCDesign floatingHUDMaterialView];
            vev.translatesAutoresizingMaskIntoConstraints = NO;
            vev.wantsLayer = YES;
            vev.layer.cornerRadius = 32.0;
            vev.layer.masksToBounds = YES;
            [self addSubview:vev];
            _materialView = vev;
        }

        NSImage *playSymbol = [MacLCDesign symbolNamed:@"play.fill" pointSize:28.0 weight:NSFontWeightSemibold accessibilityLabel:_NS("Play")];
        _playImageView = [[NSImageView alloc] initWithFrame:NSMakeRect(0, 0, 32.0, 32.0)];
        _playImageView.translatesAutoresizingMaskIntoConstraints = NO;
        _playImageView.image = playSymbol;
        _playImageView.contentTintColor = NSColor.whiteColor;
        [self addSubview:_playImageView];

        [NSLayoutConstraint activateConstraints:@[
            [_materialView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_materialView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_materialView.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_materialView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],

            [_playImageView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor constant:2.0],
            [_playImageView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_playImageView.widthAnchor constraintEqualToConstant:32.0],
            [_playImageView.heightAnchor constraintEqualToConstant:32.0],
        ]];
    }
    return self;
}

- (void)updateTrackingAreas
{
    [super updateTrackingAreas];
    if (_trackingArea) {
        [self removeTrackingArea:_trackingArea];
    }
    _trackingArea = [[NSTrackingArea alloc] initWithRect:self.bounds
                                                 options:NSTrackingMouseEnteredAndExited | NSTrackingActiveInActiveApp
                                                   owner:self
                                                userInfo:nil];
    [self addTrackingArea:_trackingArea];
}

- (void)mouseEntered:(NSEvent *)event
{
    [super mouseEntered:event];
    if (NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion) {
        self.alphaValue = 0.85;
    } else {
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = MacLCDesign.motionQuickDuration;
            self.animator.layer.affineTransform = CGAffineTransformMakeScale(1.06, 1.06);
        }];
    }
}

- (void)mouseExited:(NSEvent *)event
{
    [super mouseExited:event];
    if (NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion) {
        self.alphaValue = 1.0;
    } else {
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = MacLCDesign.motionQuickDuration;
            self.animator.layer.affineTransform = CGAffineTransformIdentity;
        }];
    }
}

- (void)mouseUp:(NSEvent *)event
{
    NSPoint loc = [self convertPoint:event.locationInWindow fromView:nil];
    if (NSPointInRect(loc, self.bounds)) {
        if (self.clickHandler) {
            self.clickHandler();
        }
    }
}

- (void)resetCursorRects
{
    [self addCursorRect:self.bounds cursor:NSCursor.pointingHandCursor];
}

@end

#pragma mark - Clickable Text View (Link Detector)

@interface MacLCYouTubeClickableTextView : NSTextView <NSTextViewDelegate>
@property (nonatomic, copy, nullable) void (^linkHandler)(NSURL *url);
@end

@implementation MacLCYouTubeClickableTextView

- (instancetype)initWithFrame:(NSRect)frameRect textContainer:(nullable NSTextContainer *)container
{
    self = [super initWithFrame:frameRect textContainer:container];
    if (self) {
        self.editable = NO;
        self.selectable = YES;
        self.drawsBackground = NO;
        self.delegate = self;
        if (self.textContainer) {
            self.textContainer.lineFragmentPadding = 0.0;
        }
        self.textContainerInset = NSZeroSize;
        self.linkTextAttributes = @{
            NSForegroundColorAttributeName: MacLCDesign.accent,
            NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle)
        };
    }
    return self;
}

- (BOOL)textView:(NSTextView *)textView clickedOnLink:(id)link atIndex:(NSUInteger)charIndex
{
    NSURL *url = nil;
    if ([link isKindOfClass:[NSURL class]]) {
        url = (NSURL *)link;
    } else if ([link isKindOfClass:[NSString class]]) {
        url = [NSURL URLWithString:(NSString *)link];
    }

    if (url) {
        if (self.linkHandler) {
            self.linkHandler(url);
        } else {
            [NSWorkspace.sharedWorkspace openURL:url];
        }
        return YES;
    }
    return NO;
}

@end

#pragma mark - Attributed Text Helpers

static NSAttributedString *MacLCClickableAttributedDescription(NSString * _Nullable text)
{
    if (!text || text.length == 0) {
        return [[NSAttributedString alloc] initWithString:@""];
    }

    NSMutableAttributedString *mas = [[NSMutableAttributedString alloc] initWithString:text attributes:@{
        NSFontAttributeName: MacLCDesign.body,
        NSForegroundColorAttributeName: MacLCDesign.primaryLabel
    }];

    NSError *error = nil;
    NSDataDetector *detector = [NSDataDetector dataDetectorWithTypes:NSTextCheckingTypeLink error:&error];
    if (detector) {
        NSArray<NSTextCheckingResult *> *matches = [detector matchesInString:text options:0 range:NSMakeRange(0, text.length)];
        for (NSTextCheckingResult *match in matches) {
            if (match.URL) {
                [mas addAttributes:@{
                    NSLinkAttributeName: match.URL,
                    NSForegroundColorAttributeName: MacLCDesign.accent,
                    NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle)
                } range:match.range];
            }
        }
    }
    return mas;
}

#pragma mark - Channel Header Item

static NSString * const MacLCYouTubeChannelHeaderItemIdentifier = @"MacLCYouTubeChannelHeaderItemIdentifier";

@interface MacLCYouTubeChannelHeaderItem : NSCollectionViewItem
@property (nonatomic, strong) MacLCYouTubeFillImageView *bannerImageView;
@property (nonatomic, strong) NSImageView *avatarImageView;
@property (nonatomic, strong) NSTextField *nameLabel;
@property (nonatomic, strong) NSImageView *sealImageView;
@property (nonatomic, strong) NSTextField *handleAndSubsLabel;
@property (nonatomic, strong) NSTextField *descLabel;
@property (nonatomic, strong) NSButton *moreButton;
@property (nonatomic, strong) NSSegmentedControl *segmentedControl;
@property (nonatomic, strong) NSLayoutConstraint *bannerHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *bannerAspectConstraint;
@property (nonatomic, strong) NSLayoutConstraint *bannerTopConstraint;
@property (nonatomic, strong) NSLayoutConstraint *avatarTopConstraint;

@property (nonatomic, copy, nullable) void (^tabChangeHandler)(MacLCYouTubeChannelTab tab);
@property (nonatomic, copy, nullable) void (^moreDescriptionHandler)(NSButton *button);
- (void)configureWithChannel:(nullable MacLCYouTubeChannel *)channel currentTab:(MacLCYouTubeChannelTab)tab width:(CGFloat)width;
@end

@implementation MacLCYouTubeChannelHeaderItem {
    MacLCWatchImageRequest *_bannerRequest;
    MacLCWatchImageRequest *_avatarRequest;
    MacLCYouTubeChannel *_channel;
}

- (void)loadView
{
    NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 800.0, 360.0)];
    root.wantsLayer = YES;
    self.view = root;

    _bannerImageView = [[MacLCYouTubeFillImageView alloc] initWithFrame:NSZeroRect];
    _bannerImageView.translatesAutoresizingMaskIntoConstraints = NO;
    _bannerImageView.layer.cornerRadius = 16.0;
    _bannerImageView.layer.backgroundColor = NSColor.quaternarySystemFillColor.CGColor;
    [root addSubview:_bannerImageView];

    _avatarImageView = [[NSImageView alloc] initWithFrame:NSZeroRect];
    _avatarImageView.translatesAutoresizingMaskIntoConstraints = NO;
    _avatarImageView.wantsLayer = YES;
    _avatarImageView.layer.cornerRadius = kMacLCYouTubeChannelAvatarSize / 2.0;
    _avatarImageView.layer.masksToBounds = YES;
    _avatarImageView.imageScaling = NSImageScaleProportionallyUpOrDown;
    _avatarImageView.layer.backgroundColor = NSColor.quaternarySystemFillColor.CGColor;
    [root addSubview:_avatarImageView];

    _nameLabel = [NSTextField labelWithString:@""];
    _nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _nameLabel.font = [NSFont systemFontOfSize:MacLCDesign.title1.pointSize weight:NSFontWeightBold];
    _nameLabel.textColor = MacLCDesign.primaryLabel;

    _sealImageView = [[NSImageView alloc] initWithFrame:NSZeroRect];
    _sealImageView.translatesAutoresizingMaskIntoConstraints = NO;
    _sealImageView.image = [MacLCDesign symbolNamed:@"checkmark.seal.fill" pointSize:14.0 weight:NSFontWeightSemibold accessibilityLabel:_NS("Verified")];
    _sealImageView.contentTintColor = MacLCDesign.secondaryLabel;
    _sealImageView.hidden = YES;

    NSStackView *nameStack = [NSStackView stackViewWithViews:@[_nameLabel, _sealImageView]];
    nameStack.translatesAutoresizingMaskIntoConstraints = NO;
    nameStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    nameStack.alignment = NSLayoutAttributeCenterY;
    nameStack.spacing = 6.0;
    [root addSubview:nameStack];

    _handleAndSubsLabel = [NSTextField labelWithString:@""];
    _handleAndSubsLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _handleAndSubsLabel.font = MacLCDesign.subheadline;
    _handleAndSubsLabel.textColor = MacLCDesign.secondaryLabel;
    [root addSubview:_handleAndSubsLabel];

    _descLabel = [NSTextField wrappingLabelWithString:@""];
    _descLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _descLabel.font = MacLCDesign.body;
    _descLabel.textColor = MacLCDesign.secondaryLabel;
    _descLabel.maximumNumberOfLines = 2;
    _descLabel.lineBreakMode = NSLineBreakByWordWrapping;
    _descLabel.cell.truncatesLastVisibleLine = YES;
    [root addSubview:_descLabel];

    _moreButton = [NSButton buttonWithTitle:_NS("more") target:self action:@selector(moreClicked:)];
    _moreButton.translatesAutoresizingMaskIntoConstraints = NO;
    _moreButton.bordered = NO;
    _moreButton.font = MacLCDesign.subheadline;
    _moreButton.contentTintColor = MacLCDesign.secondaryLabel;
    _moreButton.accessibilityLabel = _NS("More description");
    _moreButton.toolTip = _NS("Show Full Description");
    [root addSubview:_moreButton];

    _segmentedControl = [NSSegmentedControl segmentedControlWithLabels:@[_NS("Videos"), _NS("Live"), _NS("Playlists")]
                                                          trackingMode:NSSegmentSwitchTrackingSelectOne
                                                                target:self
                                                                action:@selector(segmentChanged:)];
    _segmentedControl.translatesAutoresizingMaskIntoConstraints = NO;
    _segmentedControl.segmentStyle = NSSegmentStyleTexturedRounded;
    [root addSubview:_segmentedControl];

    _bannerHeightConstraint = [_bannerImageView.heightAnchor constraintEqualToConstant:0.0];
    /* The banner is as tall as the cell is wide, never from a width read
     * before the layout settled (the section reserves the same 6:1). */
    _bannerAspectConstraint = [_bannerImageView.heightAnchor constraintEqualToAnchor:_bannerImageView.widthAnchor multiplier:1.0 / 6.0];
    _bannerTopConstraint = [_bannerImageView.topAnchor constraintEqualToAnchor:root.topAnchor constant:0.0];
    _avatarTopConstraint = [_avatarImageView.topAnchor constraintEqualToAnchor:_bannerImageView.bottomAnchor constant:16.0];

    _bannerHeightConstraint.active = YES;
    [NSLayoutConstraint activateConstraints:@[
        _bannerTopConstraint,
        [_bannerImageView.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:24.0],
        [_bannerImageView.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-24.0],

        _avatarTopConstraint,
        [_avatarImageView.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:24.0],
        [_avatarImageView.widthAnchor constraintEqualToConstant:kMacLCYouTubeChannelAvatarSize],
        [_avatarImageView.heightAnchor constraintEqualToConstant:kMacLCYouTubeChannelAvatarSize],

        [nameStack.topAnchor constraintEqualToAnchor:_avatarImageView.topAnchor constant:2.0],
        [nameStack.leadingAnchor constraintEqualToAnchor:_avatarImageView.trailingAnchor constant:20.0],
        [nameStack.trailingAnchor constraintLessThanOrEqualToAnchor:root.trailingAnchor constant:-24.0],

        [_handleAndSubsLabel.topAnchor constraintEqualToAnchor:nameStack.bottomAnchor constant:4.0],
        [_handleAndSubsLabel.leadingAnchor constraintEqualToAnchor:nameStack.leadingAnchor],
        [_handleAndSubsLabel.trailingAnchor constraintLessThanOrEqualToAnchor:root.trailingAnchor constant:-24.0],

        [_descLabel.topAnchor constraintEqualToAnchor:_handleAndSubsLabel.bottomAnchor constant:6.0],
        [_descLabel.leadingAnchor constraintEqualToAnchor:nameStack.leadingAnchor],
        [_descLabel.trailingAnchor constraintLessThanOrEqualToAnchor:root.trailingAnchor constant:-80.0],

        [_moreButton.leadingAnchor constraintEqualToAnchor:_descLabel.trailingAnchor constant:4.0],
        [_moreButton.lastBaselineAnchor constraintEqualToAnchor:_descLabel.lastBaselineAnchor],

        [_segmentedControl.topAnchor constraintEqualToAnchor:_avatarImageView.bottomAnchor constant:20.0],
        [_segmentedControl.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:24.0],
        [_segmentedControl.heightAnchor constraintEqualToConstant:30.0],
    ]];
}

- (void)configureWithChannel:(nullable MacLCYouTubeChannel *)channel currentTab:(MacLCYouTubeChannelTab)tab width:(CGFloat)width
{
    _channel = channel;
    _segmentedControl.selectedSegment = (NSInteger)tab;

    _nameLabel.stringValue = channel.name ?: @"";
    _sealImageView.hidden = !channel.isVerified;

    NSMutableArray<NSString *> *infoParts = [NSMutableArray array];
    if (channel.handle.length > 0) {
        [infoParts addObject:channel.handle];
    }
    if (channel.subscriberCount >= 0) {
        NSString *subs = [MacLCYouTubeFormat subscriberCountString:channel.subscriberCount];
        if (subs.length > 0) {
            [infoParts addObject:subs];
        }
    }
    _handleAndSubsLabel.stringValue = [infoParts componentsJoinedByString:@" · "];

    NSString *desc = channel.descriptionText ?: @"";
    _descLabel.stringValue = desc;
    _moreButton.hidden = (desc.length == 0);

    // Banner sizing and loading
    [_bannerRequest cancel];
    _bannerRequest = nil;

    if (channel.bannerURL) {
        CGFloat bannerWidth = MAX(width - 48.0, 200.0);
        CGFloat bannerHeight = bannerWidth / 6.0;
        (void)bannerHeight;
        _bannerHeightConstraint.active = NO;
        _bannerAspectConstraint.active = YES;
        _bannerTopConstraint.constant = 16.0;
        _avatarTopConstraint.constant = 16.0;
        _bannerImageView.hidden = NO;

        CGFloat scale = self.view.window.backingScaleFactor ?: 2.0;
        MacLCWatchImageRequest *req = nil;
        __weak typeof(self) weakSelf = self;
        NSImage *cached = [MacLCWatchImageCache.sharedCache imageForURL:channel.bannerURL
                                                             pointSize:NSMakeSize(bannerWidth, bannerHeight)
                                                                 scale:scale
                                                               request:&req
                                                            completion:^(NSImage *image) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf) {
                strongSelf->_bannerImageView.image = image;
            }
        }];
        _bannerRequest = req;
        _bannerImageView.image = cached;
    } else {
        _bannerAspectConstraint.active = NO;
        _bannerHeightConstraint.active = YES;
        _bannerTopConstraint.constant = 0.0;
        _avatarTopConstraint.constant = 16.0;
        _bannerImageView.hidden = YES;
        _bannerImageView.image = nil;
    }

    // Avatar loading
    [_avatarRequest cancel];
    _avatarRequest = nil;

    if (channel.avatarURL) {
        CGFloat scale = self.view.window.backingScaleFactor ?: 2.0;
        MacLCWatchImageRequest *req = nil;
        __weak typeof(self) weakSelf = self;
        NSImage *cached = [MacLCWatchImageCache.sharedCache imageForURL:channel.avatarURL
                                                             pointSize:NSMakeSize(kMacLCYouTubeChannelAvatarSize, kMacLCYouTubeChannelAvatarSize)
                                                                 scale:scale
                                                               request:&req
                                                            completion:^(NSImage *image) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf) {
                strongSelf->_avatarImageView.image = image ?: [MacLCDesign symbolNamed:@"person.crop.circle.fill" accessibilityLabel:nil];
            }
        }];
        _avatarRequest = req;
        _avatarImageView.image = cached ?: [MacLCDesign symbolNamed:@"person.crop.circle.fill" accessibilityLabel:nil];
    } else {
        _avatarImageView.image = [MacLCDesign symbolNamed:@"person.crop.circle.fill" accessibilityLabel:nil];
    }
}

- (void)segmentChanged:(NSSegmentedControl *)sender
{
    if (self.tabChangeHandler) {
        self.tabChangeHandler((MacLCYouTubeChannelTab)sender.selectedSegment);
    }
}

- (void)moreClicked:(NSButton *)sender
{
    if (self.moreDescriptionHandler) {
        self.moreDescriptionHandler(sender);
    }
}

- (void)prepareForReuse
{
    [super prepareForReuse];
    [_bannerRequest cancel];
    _bannerRequest = nil;
    [_avatarRequest cancel];
    _avatarRequest = nil;
    _bannerImageView.image = nil;
    _avatarImageView.image = nil;
}

@end

#pragma mark - Playlist Header Item

static NSString * const MacLCYouTubePlaylistHeaderItemIdentifier = @"MacLCYouTubePlaylistHeaderItemIdentifier";

@interface MacLCYouTubePlaylistHeaderItem : NSCollectionViewItem
@property (nonatomic, strong) NSImageView *thumbnailImageView;
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSTextField *channelLabel;
@property (nonatomic, strong) NSTextField *countLabel;
@property (nonatomic, strong) NSButton *playAllButton;
@property (nonatomic, strong) NSButton *shuffleButton;

@property (nonatomic, copy, nullable) void (^playAllHandler)(void);
@property (nonatomic, copy, nullable) void (^shuffleHandler)(void);
@property (nonatomic, copy, nullable) void (^channelClickHandler)(void);
- (void)configureWithPlaylist:(nullable MacLCYouTubePlaylist *)playlist videoCount:(NSInteger)videoCount;
@end

@implementation MacLCYouTubePlaylistHeaderItem {
    MacLCWatchImageRequest *_thumbRequest;
}

- (void)loadView
{
    NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 800.0, 240.0)];
    root.wantsLayer = YES;
    self.view = root;

    _thumbnailImageView = [[NSImageView alloc] initWithFrame:NSZeroRect];
    _thumbnailImageView.translatesAutoresizingMaskIntoConstraints = NO;
    _thumbnailImageView.wantsLayer = YES;
    _thumbnailImageView.layer.cornerRadius = 12.0;
    _thumbnailImageView.layer.masksToBounds = YES;
    _thumbnailImageView.imageScaling = NSImageScaleProportionallyUpOrDown;
    _thumbnailImageView.layer.backgroundColor = NSColor.quaternarySystemFillColor.CGColor;
    [root addSubview:_thumbnailImageView];

    _titleLabel = [NSTextField wrappingLabelWithString:@""];
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _titleLabel.font = [NSFont systemFontOfSize:MacLCDesign.title1.pointSize weight:NSFontWeightBold];
    _titleLabel.textColor = MacLCDesign.primaryLabel;
    _titleLabel.maximumNumberOfLines = 2;
    _titleLabel.lineBreakMode = NSLineBreakByWordWrapping;
    _titleLabel.cell.truncatesLastVisibleLine = YES;
    [root addSubview:_titleLabel];

    _channelLabel = [NSTextField labelWithString:@""];
    _channelLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _channelLabel.font = MacLCDesign.headline;
    _channelLabel.textColor = MacLCDesign.secondaryLabel;
    [root addSubview:_channelLabel];

    _countLabel = [NSTextField labelWithString:@""];
    _countLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _countLabel.font = MacLCDesign.subheadline;
    _countLabel.textColor = MacLCDesign.secondaryLabel;
    [root addSubview:_countLabel];

    _playAllButton = [NSButton buttonWithTitle:_NS("Play All") target:self action:@selector(playAllClicked:)];
    _playAllButton.translatesAutoresizingMaskIntoConstraints = NO;
    _playAllButton.image = [MacLCDesign symbolNamed:@"play.fill" accessibilityLabel:_NS("Play All")];
    _playAllButton.imagePosition = NSImageLeading;
    _playAllButton.controlSize = NSControlSizeLarge;
    if (@available(macOS 26.0, *)) {
        _playAllButton.bezelStyle = NSBezelStyleGlass;
        _playAllButton.tintProminence = NSTintProminencePrimary;
        _playAllButton.bezelColor = MacLCDesign.accent;
    } else {
        _playAllButton.bezelStyle = NSBezelStylePush;
    }
    _playAllButton.accessibilityLabel = _playAllButton.title;
    _playAllButton.toolTip = _playAllButton.title;

    _shuffleButton = [NSButton buttonWithTitle:_NS("Shuffle") target:self action:@selector(shuffleClicked:)];
    _shuffleButton.translatesAutoresizingMaskIntoConstraints = NO;
    _shuffleButton.image = [MacLCDesign symbolNamed:@"shuffle" accessibilityLabel:_NS("Shuffle")];
    _shuffleButton.imagePosition = NSImageLeading;
    _shuffleButton.controlSize = NSControlSizeLarge;
    if (@available(macOS 26.0, *)) {
        _shuffleButton.bezelStyle = NSBezelStyleGlass;
    } else {
        _shuffleButton.bezelStyle = NSBezelStylePush;
    }
    _shuffleButton.accessibilityLabel = _shuffleButton.title;
    _shuffleButton.toolTip = _shuffleButton.title;

    NSStackView *buttonsStack = [NSStackView stackViewWithViews:@[_playAllButton, _shuffleButton]];
    buttonsStack.translatesAutoresizingMaskIntoConstraints = NO;
    buttonsStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    buttonsStack.spacing = 12.0;
    [root addSubview:buttonsStack];

    [NSLayoutConstraint activateConstraints:@[
        [_thumbnailImageView.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:24.0],
        [_thumbnailImageView.topAnchor constraintEqualToAnchor:root.topAnchor constant:16.0],
        [_thumbnailImageView.widthAnchor constraintEqualToConstant:kMacLCYouTubePlaylistThumbnailWidth],
        [_thumbnailImageView.heightAnchor constraintEqualToConstant:kMacLCYouTubePlaylistThumbnailWidth * 9.0 / 16.0],

        [_titleLabel.leadingAnchor constraintEqualToAnchor:_thumbnailImageView.trailingAnchor constant:24.0],
        [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:root.trailingAnchor constant:-24.0],
        [_titleLabel.topAnchor constraintEqualToAnchor:_thumbnailImageView.topAnchor constant:4.0],

        [_channelLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
        [_channelLabel.trailingAnchor constraintLessThanOrEqualToAnchor:root.trailingAnchor constant:-24.0],
        [_channelLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:8.0],

        [_countLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
        [_countLabel.trailingAnchor constraintLessThanOrEqualToAnchor:root.trailingAnchor constant:-24.0],
        [_countLabel.topAnchor constraintEqualToAnchor:_channelLabel.bottomAnchor constant:6.0],

        [buttonsStack.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
        [buttonsStack.bottomAnchor constraintEqualToAnchor:_thumbnailImageView.bottomAnchor],
    ]];
}

- (void)configureWithPlaylist:(nullable MacLCYouTubePlaylist *)playlist videoCount:(NSInteger)videoCount
{
    _titleLabel.stringValue = playlist.title ?: @"";
    _channelLabel.stringValue = playlist.channelName ?: @"";

    NSInteger count = (videoCount > 0) ? videoCount : playlist.videoCount;
    if (count > 0) {
        _countLabel.stringValue = [NSString stringWithFormat:_NPS("%ld video", "%ld videos", count), (long)count];
    } else {
        _countLabel.stringValue = @"";
    }

    [_thumbRequest cancel];
    _thumbRequest = nil;

    if (playlist.thumbnailURL) {
        CGFloat scale = self.view.window.backingScaleFactor ?: 2.0;
        NSSize targetSize = NSMakeSize(kMacLCYouTubePlaylistThumbnailWidth, kMacLCYouTubePlaylistThumbnailWidth * 9.0 / 16.0);
        MacLCWatchImageRequest *req = nil;
        __weak typeof(self) weakSelf = self;
        NSImage *cached = [MacLCWatchImageCache.sharedCache imageForURL:playlist.thumbnailURL
                                                             pointSize:targetSize
                                                                 scale:scale
                                                               request:&req
                                                            completion:^(NSImage *image) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf) {
                strongSelf->_thumbnailImageView.image = image;
            }
        }];
        _thumbRequest = req;
        _thumbnailImageView.image = cached;
    } else {
        _thumbnailImageView.image = nil;
    }
}

- (void)playAllClicked:(id)sender
{
    if (self.playAllHandler) {
        self.playAllHandler();
    }
}

- (void)shuffleClicked:(id)sender
{
    if (self.shuffleHandler) {
        self.shuffleHandler();
    }
}

- (void)prepareForReuse
{
    [super prepareForReuse];
    [_thumbRequest cancel];
    _thumbRequest = nil;
    _thumbnailImageView.image = nil;
}

@end

#pragma mark - Playlist Row View & Item

static NSString * const MacLCYouTubePlaylistRowItemIdentifier = @"MacLCYouTubePlaylistRowItemIdentifier";

@interface MacLCYouTubePlaylistRowItem : NSCollectionViewItem
@property (nonatomic, strong) NSTextField *indexLabel;
@property (nonatomic, strong) NSImageView *thumbnailView;
@property (nonatomic, strong) MacLCYouTubeDurationBadgeView *durationBadge;
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSTextField *channelLabel;
@property (nonatomic, strong) NSTextField *durationLabel;

@property (nonatomic, copy, nullable) void (^activationHandler)(MacLCYouTubeVideo *video, NSUInteger index);
@property (nonatomic, copy, nullable) void (^enqueueHandler)(MacLCYouTubeVideo *video);
@property (nonatomic, copy, nullable) void (^detailsHandler)(MacLCYouTubeVideo *video);
@property (nonatomic, copy, nullable) void (^channelHandler)(MacLCYouTubeVideo *video);

- (void)configureWithVideo:(nullable MacLCYouTubeVideo *)video index:(NSUInteger)index;
- (void)handleRowClickWithEvent:(NSEvent *)event;
- (NSMenu *)contextMenuForEvent:(NSEvent *)event;
@end

@interface MacLCYouTubePlaylistRowView : NSView
@property (nonatomic, weak) MacLCYouTubePlaylistRowItem *rowItem;
@end

@implementation MacLCYouTubePlaylistRowView {
    NSTrackingArea *_trackingArea;
}

- (void)updateTrackingAreas
{
    [super updateTrackingAreas];
    if (_trackingArea) {
        [self removeTrackingArea:_trackingArea];
    }
    _trackingArea = [[NSTrackingArea alloc] initWithRect:self.bounds
                                                 options:NSTrackingMouseEnteredAndExited | NSTrackingActiveInActiveApp
                                                   owner:self
                                                userInfo:nil];
    [self addTrackingArea:_trackingArea];
}

- (void)mouseEntered:(NSEvent *)event
{
    [super mouseEntered:event];
    self.layer.backgroundColor = NSColor.quaternarySystemFillColor.CGColor;
}

- (void)mouseExited:(NSEvent *)event
{
    [super mouseExited:event];
    self.layer.backgroundColor = NULL;
}

- (void)resetCursorRects
{
    [self addCursorRect:self.bounds cursor:NSCursor.pointingHandCursor];
}

- (void)mouseDown:(NSEvent *)event
{
    [super mouseDown:event];
    [self.rowItem handleRowClickWithEvent:event];
}

- (NSMenu *)menuForEvent:(NSEvent *)event
{
    return [self.rowItem contextMenuForEvent:event];
}

@end

@implementation MacLCYouTubePlaylistRowItem {
    MacLCWatchImageRequest *_thumbRequest;
    MacLCYouTubeVideo *_video;
    NSUInteger _index;
}

- (void)loadView
{
    MacLCYouTubePlaylistRowView *root = [[MacLCYouTubePlaylistRowView alloc] initWithFrame:NSMakeRect(0, 0, 800.0, kMacLCYouTubePlaylistRowHeight)];
    root.wantsLayer = YES;
    root.layer.cornerRadius = 8.0;
    root.rowItem = self;
    self.view = root;

    _indexLabel = [NSTextField labelWithString:@""];
    _indexLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _indexLabel.font = [NSFont monospacedDigitSystemFontOfSize:13.0 weight:NSFontWeightMedium];
    _indexLabel.textColor = MacLCDesign.secondaryLabel;
    _indexLabel.alignment = NSTextAlignmentRight;
    [root addSubview:_indexLabel];

    _thumbnailView = [[NSImageView alloc] initWithFrame:NSZeroRect];
    _thumbnailView.translatesAutoresizingMaskIntoConstraints = NO;
    _thumbnailView.wantsLayer = YES;
    _thumbnailView.layer.cornerRadius = 8.0;
    _thumbnailView.layer.masksToBounds = YES;
    _thumbnailView.imageScaling = NSImageScaleProportionallyUpOrDown;
    _thumbnailView.layer.backgroundColor = NSColor.quaternarySystemFillColor.CGColor;
    [root addSubview:_thumbnailView];

    _durationBadge = [[MacLCYouTubeDurationBadgeView alloc] initWithFrame:NSZeroRect];
    _durationBadge.translatesAutoresizingMaskIntoConstraints = NO;
    [_thumbnailView addSubview:_durationBadge];

    _titleLabel = [NSTextField wrappingLabelWithString:@""];
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _titleLabel.font = [NSFont systemFontOfSize:15.0 weight:NSFontWeightSemibold];
    _titleLabel.textColor = MacLCDesign.primaryLabel;
    _titleLabel.maximumNumberOfLines = 2;
    _titleLabel.lineBreakMode = NSLineBreakByWordWrapping;
    _titleLabel.cell.truncatesLastVisibleLine = YES;
    [root addSubview:_titleLabel];

    _channelLabel = [NSTextField labelWithString:@""];
    _channelLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _channelLabel.font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightRegular];
    _channelLabel.textColor = MacLCDesign.secondaryLabel;
    [root addSubview:_channelLabel];

    _durationLabel = [NSTextField labelWithString:@""];
    _durationLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _durationLabel.font = [NSFont monospacedDigitSystemFontOfSize:13.0 weight:NSFontWeightRegular];
    _durationLabel.textColor = MacLCDesign.secondaryLabel;
    _durationLabel.alignment = NSTextAlignmentRight;
    [root addSubview:_durationLabel];

    [NSLayoutConstraint activateConstraints:@[
        [_indexLabel.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:8.0],
        [_indexLabel.centerYAnchor constraintEqualToAnchor:root.centerYAnchor],
        [_indexLabel.widthAnchor constraintEqualToConstant:32.0],

        [_thumbnailView.leadingAnchor constraintEqualToAnchor:_indexLabel.trailingAnchor constant:12.0],
        [_thumbnailView.centerYAnchor constraintEqualToAnchor:root.centerYAnchor],
        [_thumbnailView.widthAnchor constraintEqualToConstant:160.0],
        [_thumbnailView.heightAnchor constraintEqualToConstant:90.0],

        [_durationBadge.trailingAnchor constraintEqualToAnchor:_thumbnailView.trailingAnchor constant:-6.0],
        [_durationBadge.bottomAnchor constraintEqualToAnchor:_thumbnailView.bottomAnchor constant:-6.0],

        [_titleLabel.leadingAnchor constraintEqualToAnchor:_thumbnailView.trailingAnchor constant:16.0],
        [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_durationLabel.leadingAnchor constant:-16.0],
        [_titleLabel.topAnchor constraintEqualToAnchor:_thumbnailView.topAnchor constant:4.0],

        [_channelLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
        [_channelLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_durationLabel.leadingAnchor constant:-16.0],
        [_channelLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:6.0],

        [_durationLabel.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-16.0],
        [_durationLabel.centerYAnchor constraintEqualToAnchor:root.centerYAnchor],
        [_durationLabel.widthAnchor constraintGreaterThanOrEqualToConstant:50.0],
    ]];
}

- (void)configureWithVideo:(nullable MacLCYouTubeVideo *)video index:(NSUInteger)index
{
    _video = video;
    _index = index;

    _indexLabel.stringValue = [NSString stringWithFormat:@"%ld", (long)(index + 1)];
    _titleLabel.stringValue = video.title ?: @"";
    _channelLabel.stringValue = video.channelName ?: @"";
    _durationLabel.stringValue = [MacLCYouTubeFormat durationString:video.duration];

    [_durationBadge configureWithVideo:video];

    [_thumbRequest cancel];
    _thumbRequest = nil;

    if (video.thumbnailURL) {
        CGFloat scale = self.view.window.backingScaleFactor ?: 2.0;
        NSSize targetSize = NSMakeSize(160.0, 90.0);
        MacLCWatchImageRequest *req = nil;
        __weak typeof(self) weakSelf = self;
        NSImage *cached = [MacLCWatchImageCache.sharedCache imageForURL:video.thumbnailURL
                                                             pointSize:targetSize
                                                                 scale:scale
                                                               request:&req
                                                            completion:^(NSImage *image) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf) {
                strongSelf->_thumbnailView.image = image;
            }
        }];
        _thumbRequest = req;
        _thumbnailView.image = cached;
    } else {
        _thumbnailView.image = nil;
    }
}

- (void)handleRowClickWithEvent:(NSEvent *)event
{
    if (event.clickCount == 2 || event.clickCount == 1) {
        if (self.activationHandler && _video) {
            self.activationHandler(_video, _index);
        }
    }
}

- (NSMenu *)contextMenuForEvent:(NSEvent *)event
{
    if (!_video) return nil;

    NSMenu *menu = [[NSMenu alloc] initWithTitle:@""];
    NSMenuItem *playItem = [[NSMenuItem alloc] initWithTitle:_NS("Play") action:@selector(contextPlayAction:) keyEquivalent:@""];
    playItem.target = self;
    [menu addItem:playItem];

    NSMenuItem *queueItem = [[NSMenuItem alloc] initWithTitle:_NS("Add to Queue") action:@selector(contextEnqueueAction:) keyEquivalent:@""];
    queueItem.target = self;
    [menu addItem:queueItem];

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *detailsItem = [[NSMenuItem alloc] initWithTitle:_NS("Show Details") action:@selector(contextDetailsAction:) keyEquivalent:@""];
    detailsItem.target = self;
    [menu addItem:detailsItem];

    if (_video.channelURL || _video.channelName) {
        NSMenuItem *channelItem = [[NSMenuItem alloc] initWithTitle:_NS("Go to Channel") action:@selector(contextChannelAction:) keyEquivalent:@""];
        channelItem.target = self;
        [menu addItem:channelItem];
    }

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *copyItem = [[NSMenuItem alloc] initWithTitle:_NS("Copy Link") action:@selector(contextCopyLinkAction:) keyEquivalent:@""];
    copyItem.target = self;
    [menu addItem:copyItem];

    NSMenuItem *browserItem = [[NSMenuItem alloc] initWithTitle:_NS("Open in Browser") action:@selector(contextOpenInBrowserAction:) keyEquivalent:@""];
    browserItem.target = self;
    [menu addItem:browserItem];

    return menu;
}

- (void)contextPlayAction:(id)sender
{
    if (self.activationHandler && _video) {
        self.activationHandler(_video, _index);
    }
}

- (void)contextEnqueueAction:(id)sender
{
    if (self.enqueueHandler && _video) {
        self.enqueueHandler(_video);
    }
}

- (void)contextDetailsAction:(id)sender
{
    if (self.detailsHandler && _video) {
        self.detailsHandler(_video);
    }
}

- (void)contextChannelAction:(id)sender
{
    if (self.channelHandler && _video) {
        self.channelHandler(_video);
    }
}

- (void)contextCopyLinkAction:(id)sender
{
    if (_video) {
        [MacLCYouTubeActions copyLinkOfVideo:_video];
    }
}

- (void)contextOpenInBrowserAction:(id)sender
{
    if (_video && _video.watchURL) {
        [MacLCYouTubeActions openInBrowser:_video.watchURL];
    }
}

- (void)prepareForReuse
{
    [super prepareForReuse];
    [_thumbRequest cancel];
    _thumbRequest = nil;
    _thumbnailView.image = nil;
    self.view.layer.backgroundColor = NULL;
}

@end

#pragma mark - Video Page Header Item

static NSString * const MacLCYouTubeVideoHeaderItemIdentifier = @"MacLCYouTubeVideoHeaderItemIdentifier";

@interface MacLCYouTubeVideoHeaderItem : NSCollectionViewItem
@property (nonatomic, strong) NSView *thumbContainerView;
@property (nonatomic, strong) MacLCYouTubeFillImageView *thumbImageView;
@property (nonatomic, strong) MacLCYouTubeCentredGlassPlayButton *playButton;
@property (nonatomic, strong) MacLCYouTubeDurationBadgeView *durationBadge;
@property (nonatomic, strong) NSTextField *titleLabel;

@property (nonatomic, strong) NSTextField *channelNameLabel;
@property (nonatomic, strong) NSImageView *sealImageView;
@property (nonatomic, strong) NSTextField *subscriberLabel;

@property (nonatomic, strong) NSButton *queueButton;
@property (nonatomic, strong) NSButton *shareLinkButton;
@property (nonatomic, strong) NSButton *browserButton;

@property (nonatomic, strong) NSView *descBoxView;
@property (nonatomic, strong) NSTextField *statsLabel;
@property (nonatomic, strong) MacLCYouTubeClickableTextView *descTextView;
@property (nonatomic, strong) NSButton *showMoreButton;

@property (nonatomic, strong) NSScrollView *chaptersScrollView;
@property (nonatomic, strong) NSStackView *chaptersStackView;

@property (nonatomic, copy, nullable) void (^playHandler)(void);
@property (nonatomic, copy, nullable) void (^channelClickHandler)(void);
@property (nonatomic, copy, nullable) void (^enqueueHandler)(void);
@property (nonatomic, copy, nullable) void (^onCopyLinkHandler)(void);
@property (nonatomic, copy, nullable) void (^browserHandler)(void);
@property (nonatomic, copy, nullable) void (^toggleDescriptionHandler)(void);
@property (nonatomic, copy, nullable) void (^chapterClickHandler)(MacLCYouTubeChapter *chapter);

- (void)configureWithVideo:(nullable MacLCYouTubeVideo *)video isExpanded:(BOOL)isExpanded width:(CGFloat)width;
@end

@implementation MacLCYouTubeVideoHeaderItem {
    MacLCWatchImageRequest *_thumbRequest;
    MacLCYouTubeVideo *_video;
    BOOL _isExpanded;
    NSLayoutConstraint *_thumbWidthConstraint;
    NSLayoutConstraint *_descTextHeightConstraint;
}

- (void)loadView
{
    NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 960.0, 800.0)];
    root.wantsLayer = YES;
    self.view = root;

    // 1. Thumbnail Container
    _thumbContainerView = [[NSView alloc] initWithFrame:NSZeroRect];
    _thumbContainerView.translatesAutoresizingMaskIntoConstraints = NO;
    _thumbContainerView.wantsLayer = YES;
    _thumbContainerView.layer.cornerRadius = 16.0;
    _thumbContainerView.layer.masksToBounds = YES;
    _thumbContainerView.layer.backgroundColor = NSColor.quaternarySystemFillColor.CGColor;
    [root addSubview:_thumbContainerView];

    _thumbImageView = [[MacLCYouTubeFillImageView alloc] initWithFrame:NSZeroRect];
    _thumbImageView.translatesAutoresizingMaskIntoConstraints = NO;
    [_thumbContainerView addSubview:_thumbImageView];

    _playButton = [[MacLCYouTubeCentredGlassPlayButton alloc] initWithFrame:NSMakeRect(0, 0, 64.0, 64.0)];
    _playButton.translatesAutoresizingMaskIntoConstraints = NO;
    __weak typeof(self) weakSelf = self;
    _playButton.clickHandler = ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf && strongSelf.playHandler) {
            strongSelf.playHandler();
        }
    };
    [_thumbContainerView addSubview:_playButton];

    _durationBadge = [[MacLCYouTubeDurationBadgeView alloc] initWithFrame:NSZeroRect];
    _durationBadge.translatesAutoresizingMaskIntoConstraints = NO;
    [_thumbContainerView addSubview:_durationBadge];

    // 2. Title
    _titleLabel = [NSTextField wrappingLabelWithString:@""];
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _titleLabel.font = [NSFont systemFontOfSize:MacLCDesign.title1.pointSize weight:NSFontWeightBold];
    _titleLabel.textColor = MacLCDesign.primaryLabel;
    _titleLabel.lineBreakMode = NSLineBreakByWordWrapping;
    [root addSubview:_titleLabel];

    // 3. Channel Info & Actions Row
    NSView *channelClickArea = [[NSView alloc] initWithFrame:NSZeroRect];
    channelClickArea.translatesAutoresizingMaskIntoConstraints = NO;
    channelClickArea.wantsLayer = YES;
    NSClickGestureRecognizer *clickRec = [[NSClickGestureRecognizer alloc] initWithTarget:self action:@selector(channelRowClicked:)];
    [channelClickArea addGestureRecognizer:clickRec];
    [root addSubview:channelClickArea];

    _channelNameLabel = [NSTextField labelWithString:@""];
    _channelNameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _channelNameLabel.font = MacLCDesign.headline;
    _channelNameLabel.textColor = MacLCDesign.primaryLabel;
    [channelClickArea addSubview:_channelNameLabel];

    _sealImageView = [[NSImageView alloc] initWithFrame:NSZeroRect];
    _sealImageView.translatesAutoresizingMaskIntoConstraints = NO;
    _sealImageView.image = [MacLCDesign symbolNamed:@"checkmark.seal.fill" pointSize:13.0 weight:NSFontWeightSemibold accessibilityLabel:_NS("Verified")];
    _sealImageView.contentTintColor = MacLCDesign.secondaryLabel;
    _sealImageView.hidden = YES;
    [channelClickArea addSubview:_sealImageView];

    _subscriberLabel = [NSTextField labelWithString:@""];
    _subscriberLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _subscriberLabel.font = MacLCDesign.subheadline;
    _subscriberLabel.textColor = MacLCDesign.secondaryLabel;
    [channelClickArea addSubview:_subscriberLabel];

    // Action buttons
    _queueButton = [NSButton buttonWithTitle:_NS("Add to Queue") target:self action:@selector(queueClicked:)];
    _queueButton.translatesAutoresizingMaskIntoConstraints = NO;
    _queueButton.image = [MacLCDesign symbolNamed:@"text.badge.plus" accessibilityLabel:_NS("Add to Queue")];
    _queueButton.imagePosition = NSImageLeading;
    if (@available(macOS 26.0, *)) {
        _queueButton.bezelStyle = NSBezelStyleGlass;
    } else {
        _queueButton.bezelStyle = NSBezelStylePush;
    }
    _queueButton.accessibilityLabel = _queueButton.title;
    _queueButton.toolTip = _queueButton.title;

    _shareLinkButton = [NSButton buttonWithTitle:_NS("Copy Link") target:self action:@selector(copyLinkClicked:)];
    _shareLinkButton.translatesAutoresizingMaskIntoConstraints = NO;
    _shareLinkButton.image = [MacLCDesign symbolNamed:@"link" accessibilityLabel:_NS("Copy Link")];
    _shareLinkButton.imagePosition = NSImageLeading;
    if (@available(macOS 26.0, *)) {
        _shareLinkButton.bezelStyle = NSBezelStyleGlass;
    } else {
        _shareLinkButton.bezelStyle = NSBezelStylePush;
    }
    _shareLinkButton.accessibilityLabel = _shareLinkButton.title;
    _shareLinkButton.toolTip = _shareLinkButton.title;

    _browserButton = [NSButton buttonWithTitle:_NS("Open in Browser") target:self action:@selector(browserClicked:)];
    _browserButton.translatesAutoresizingMaskIntoConstraints = NO;
    _browserButton.image = [MacLCDesign symbolNamed:@"safari" accessibilityLabel:_NS("Open in Browser")];
    _browserButton.imagePosition = NSImageLeading;
    if (@available(macOS 26.0, *)) {
        _browserButton.bezelStyle = NSBezelStyleGlass;
    } else {
        _browserButton.bezelStyle = NSBezelStylePush;
    }
    _browserButton.accessibilityLabel = _browserButton.title;
    _browserButton.toolTip = _browserButton.title;

    NSStackView *actionButtonsStack = [NSStackView stackViewWithViews:@[_queueButton, _shareLinkButton, _browserButton]];
    actionButtonsStack.translatesAutoresizingMaskIntoConstraints = NO;
    actionButtonsStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    actionButtonsStack.spacing = 10.0;
    [root addSubview:actionButtonsStack];

    // 4. Rounded Description Box
    _descBoxView = [[NSView alloc] initWithFrame:NSZeroRect];
    _descBoxView.translatesAutoresizingMaskIntoConstraints = NO;
    _descBoxView.wantsLayer = YES;
    _descBoxView.layer.cornerRadius = 12.0;
    _descBoxView.layer.masksToBounds = YES;
    _descBoxView.layer.backgroundColor = NSColor.quaternarySystemFillColor.CGColor;
    [root addSubview:_descBoxView];

    _statsLabel = [NSTextField labelWithString:@""];
    _statsLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _statsLabel.font = [NSFont systemFontOfSize:MacLCDesign.subheadline.pointSize weight:NSFontWeightSemibold];
    _statsLabel.textColor = MacLCDesign.primaryLabel;
    [_descBoxView addSubview:_statsLabel];

    _descTextView = [[MacLCYouTubeClickableTextView alloc] initWithFrame:NSZeroRect];
    _descTextView.translatesAutoresizingMaskIntoConstraints = NO;
    [_descBoxView addSubview:_descTextView];

    _showMoreButton = [NSButton buttonWithTitle:_NS("Show More") target:self action:@selector(showMoreClicked:)];
    _showMoreButton.translatesAutoresizingMaskIntoConstraints = NO;
    _showMoreButton.bordered = NO;
    _showMoreButton.font = [NSFont systemFontOfSize:MacLCDesign.subheadline.pointSize weight:NSFontWeightSemibold];
    _showMoreButton.contentTintColor = MacLCDesign.primaryLabel;
    _showMoreButton.accessibilityLabel = _showMoreButton.title;
    _showMoreButton.toolTip = _showMoreButton.title;
    [_descBoxView addSubview:_showMoreButton];

    // 5. Chapters Shelf
    _chaptersStackView = [[NSStackView alloc] initWithFrame:NSZeroRect];
    _chaptersStackView.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    _chaptersStackView.spacing = 8.0;

    _chaptersScrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    _chaptersScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _chaptersScrollView.drawsBackground = NO;
    _chaptersScrollView.hasHorizontalScroller = NO;
    _chaptersScrollView.hasVerticalScroller = NO;
    _chaptersScrollView.documentView = _chaptersStackView;
    _chaptersScrollView.hidden = YES;
    [root addSubview:_chaptersScrollView];

    _thumbWidthConstraint = [_thumbContainerView.widthAnchor constraintEqualToConstant:kMacLCYouTubeVideoMaxThumbnailWidth];
    _descTextHeightConstraint = [_descTextView.heightAnchor constraintEqualToConstant:80.0];

    [NSLayoutConstraint activateConstraints:@[
        [_thumbContainerView.topAnchor constraintEqualToAnchor:root.topAnchor constant:16.0],
        [_thumbContainerView.centerXAnchor constraintEqualToAnchor:root.centerXAnchor],
        _thumbWidthConstraint,
        [_thumbContainerView.heightAnchor constraintEqualToAnchor:_thumbContainerView.widthAnchor multiplier:(9.0 / 16.0)],

        [_thumbImageView.leadingAnchor constraintEqualToAnchor:_thumbContainerView.leadingAnchor],
        [_thumbImageView.trailingAnchor constraintEqualToAnchor:_thumbContainerView.trailingAnchor],
        [_thumbImageView.topAnchor constraintEqualToAnchor:_thumbContainerView.topAnchor],
        [_thumbImageView.bottomAnchor constraintEqualToAnchor:_thumbContainerView.bottomAnchor],

        [_playButton.centerXAnchor constraintEqualToAnchor:_thumbContainerView.centerXAnchor],
        [_playButton.centerYAnchor constraintEqualToAnchor:_thumbContainerView.centerYAnchor],
        [_playButton.widthAnchor constraintEqualToConstant:64.0],
        [_playButton.heightAnchor constraintEqualToConstant:64.0],

        [_durationBadge.trailingAnchor constraintEqualToAnchor:_thumbContainerView.trailingAnchor constant:-8.0],
        [_durationBadge.bottomAnchor constraintEqualToAnchor:_thumbContainerView.bottomAnchor constant:-8.0],

        [_titleLabel.topAnchor constraintEqualToAnchor:_thumbContainerView.bottomAnchor constant:16.0],
        [_titleLabel.leadingAnchor constraintEqualToAnchor:_thumbContainerView.leadingAnchor],
        [_titleLabel.trailingAnchor constraintEqualToAnchor:_thumbContainerView.trailingAnchor],

        [channelClickArea.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:14.0],
        [channelClickArea.leadingAnchor constraintEqualToAnchor:_thumbContainerView.leadingAnchor],
        [channelClickArea.trailingAnchor constraintLessThanOrEqualToAnchor:actionButtonsStack.leadingAnchor constant:-16.0],

        [_channelNameLabel.topAnchor constraintEqualToAnchor:channelClickArea.topAnchor],
        [_channelNameLabel.leadingAnchor constraintEqualToAnchor:channelClickArea.leadingAnchor],

        [_sealImageView.leadingAnchor constraintEqualToAnchor:_channelNameLabel.trailingAnchor constant:4.0],
        [_sealImageView.centerYAnchor constraintEqualToAnchor:_channelNameLabel.centerYAnchor],
        [_sealImageView.trailingAnchor constraintLessThanOrEqualToAnchor:channelClickArea.trailingAnchor],

        [_subscriberLabel.topAnchor constraintEqualToAnchor:_channelNameLabel.bottomAnchor constant:2.0],
        [_subscriberLabel.leadingAnchor constraintEqualToAnchor:channelClickArea.leadingAnchor],
        [_subscriberLabel.bottomAnchor constraintEqualToAnchor:channelClickArea.bottomAnchor],

        [actionButtonsStack.trailingAnchor constraintEqualToAnchor:_thumbContainerView.trailingAnchor],
        [actionButtonsStack.centerYAnchor constraintEqualToAnchor:channelClickArea.centerYAnchor],

        [_descBoxView.topAnchor constraintEqualToAnchor:channelClickArea.bottomAnchor constant:16.0],
        [_descBoxView.leadingAnchor constraintEqualToAnchor:_thumbContainerView.leadingAnchor],
        [_descBoxView.trailingAnchor constraintEqualToAnchor:_thumbContainerView.trailingAnchor],

        [_statsLabel.topAnchor constraintEqualToAnchor:_descBoxView.topAnchor constant:14.0],
        [_statsLabel.leadingAnchor constraintEqualToAnchor:_descBoxView.leadingAnchor constant:16.0],
        [_statsLabel.trailingAnchor constraintEqualToAnchor:_descBoxView.trailingAnchor constant:-16.0],

        [_descTextView.topAnchor constraintEqualToAnchor:_statsLabel.bottomAnchor constant:8.0],
        [_descTextView.leadingAnchor constraintEqualToAnchor:_descBoxView.leadingAnchor constant:16.0],
        [_descTextView.trailingAnchor constraintEqualToAnchor:_descBoxView.trailingAnchor constant:-16.0],
        _descTextHeightConstraint,

        [_showMoreButton.topAnchor constraintEqualToAnchor:_descTextView.bottomAnchor constant:6.0],
        [_showMoreButton.leadingAnchor constraintEqualToAnchor:_descBoxView.leadingAnchor constant:16.0],
        [_showMoreButton.bottomAnchor constraintEqualToAnchor:_descBoxView.bottomAnchor constant:-12.0],

        [_chaptersScrollView.topAnchor constraintEqualToAnchor:_descBoxView.bottomAnchor constant:16.0],
        [_chaptersScrollView.leadingAnchor constraintEqualToAnchor:_thumbContainerView.leadingAnchor],
        [_chaptersScrollView.trailingAnchor constraintEqualToAnchor:_thumbContainerView.trailingAnchor],
        [_chaptersScrollView.heightAnchor constraintEqualToConstant:34.0],
    ]];
}

- (void)configureWithVideo:(nullable MacLCYouTubeVideo *)video isExpanded:(BOOL)isExpanded width:(CGFloat)width
{
    _video = video;
    _isExpanded = isExpanded;

    CGFloat thumbW = MIN(MAX(width - 48.0, 320.0), kMacLCYouTubeVideoMaxThumbnailWidth);
    _thumbWidthConstraint.constant = thumbW;

    _titleLabel.stringValue = video.title ?: @"";
    _channelNameLabel.stringValue = video.channelName ?: @"";
    _sealImageView.hidden = !video.isChannelVerified;
    [_durationBadge configureWithVideo:video];

    if (video.channelFollowerCount >= 0) {
        _subscriberLabel.stringValue = [MacLCYouTubeFormat subscriberCountString:video.channelFollowerCount];
    } else {
        _subscriberLabel.stringValue = @"";
    }

    // Stats line
    NSMutableArray<NSString *> *statsParts = [NSMutableArray array];
    if (video.viewCount >= 0 || video.isLive) {
        NSString *vStr = [MacLCYouTubeFormat viewCountString:video.viewCount live:video.isLive];
        if (vStr.length > 0) [statsParts addObject:vStr];
    }
    if (video.publishedDate) {
        NSString *rStr = [MacLCYouTubeFormat relativeDateString:video.publishedDate now:[NSDate date]];
        if (rStr.length > 0) [statsParts addObject:rStr];
    }
    if (video.likeCount > 0) {
        NSString *likesStr = [MacLCYouTubeFormat viewCountString:video.likeCount live:NO];
        likesStr = [likesStr stringByReplacingOccurrencesOfString:@"views" withString:_NS("likes")];
        likesStr = [likesStr stringByReplacingOccurrencesOfString:@"view" withString:_NS("like")];
        if (likesStr.length > 0) [statsParts addObject:likesStr];
    }
    _statsLabel.stringValue = [statsParts componentsJoinedByString:@" · "];

    // Description text
    NSString *rawDesc = video.descriptionText ?: @"";
    NSAttributedString *attDesc = MacLCClickableAttributedDescription(rawDesc);
    [_descTextView.textStorage setAttributedString:attDesc];

    if (isExpanded) {
        _descTextView.textContainer.maximumNumberOfLines = 0;
        _descTextView.textContainer.lineBreakMode = NSLineBreakByWordWrapping;
        _showMoreButton.title = _NS("Show Less");
        _showMoreButton.accessibilityLabel = _showMoreButton.title;

        NSRect usedRect = [_descTextView.layoutManager usedRectForTextContainer:_descTextView.textContainer];
        _descTextHeightConstraint.constant = MAX(ceil(usedRect.size.height), 80.0);
    } else {
        _descTextView.textContainer.maximumNumberOfLines = 4;
        _descTextView.textContainer.lineBreakMode = NSLineBreakByTruncatingTail;
        _showMoreButton.title = _NS("Show More");
        _showMoreButton.accessibilityLabel = _showMoreButton.title;
        _descTextHeightConstraint.constant = 80.0;
    }
    _showMoreButton.hidden = (rawDesc.length == 0);

    // Chapters shelf
    for (NSView *sub in [_chaptersStackView.views copy]) {
        [_chaptersStackView removeView:sub];
        [sub removeFromSuperview];
    }

    if (video.chapters.count > 0) {
        _chaptersScrollView.hidden = NO;
        for (NSUInteger i = 0; i < video.chapters.count; i++) {
            MacLCYouTubeChapter *chapter = video.chapters[i];
            NSString *chipTitle = [NSString stringWithFormat:@"%@ %@", [MacLCYouTubeFormat durationString:chapter.start], chapter.title ?: @""];
            NSButton *chipButton = [NSButton buttonWithTitle:chipTitle target:self action:@selector(chapterChipClicked:)];
            chipButton.tag = (NSInteger)i;
            chipButton.bordered = YES;
            chipButton.bezelStyle = NSBezelStyleRounded;
            chipButton.font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightMedium];
            chipButton.accessibilityLabel = [NSString stringWithFormat:_NS("Chapter: %@ at %@"), chapter.title, [MacLCYouTubeFormat durationString:chapter.start]];
            chipButton.toolTip = [NSString stringWithFormat:_NS("Play from %@"), [MacLCYouTubeFormat durationString:chapter.start]];
            [_chaptersStackView addView:chipButton inGravity:NSStackViewGravityLeading];
        }
    } else {
        _chaptersScrollView.hidden = YES;
    }

    // Thumbnail picture loading
    [_thumbRequest cancel];
    _thumbRequest = nil;

    if (video.thumbnailURL) {
        CGFloat scale = self.view.window.backingScaleFactor ?: 2.0;
        NSSize targetSize = NSMakeSize(thumbW, thumbW * 9.0 / 16.0);
        MacLCWatchImageRequest *req = nil;
        __weak typeof(self) weakSelf = self;
        NSImage *cached = [MacLCWatchImageCache.sharedCache imageForURL:video.thumbnailURL
                                                             pointSize:targetSize
                                                                 scale:scale
                                                               request:&req
                                                            completion:^(NSImage *image) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf) {
                strongSelf->_thumbImageView.image = image;
            }
        }];
        _thumbRequest = req;
        _thumbImageView.image = cached;
    } else {
        _thumbImageView.image = nil;
    }
}

- (void)channelRowClicked:(id)sender
{
    if (self.channelClickHandler) {
        self.channelClickHandler();
    }
}

- (void)queueClicked:(id)sender
{
    if (self.enqueueHandler) {
        self.enqueueHandler();
    }
}

- (void)copyLinkClicked:(id)sender
{
    if (self.onCopyLinkHandler) {
        self.onCopyLinkHandler();
    }
}

- (void)browserClicked:(id)sender
{
    if (self.browserHandler) {
        self.browserHandler();
    }
}

- (void)showMoreClicked:(id)sender
{
    if (self.toggleDescriptionHandler) {
        self.toggleDescriptionHandler();
    }
}

- (void)chapterChipClicked:(NSButton *)sender
{
    NSInteger idx = sender.tag;
    if (idx >= 0 && idx < (NSInteger)_video.chapters.count) {
        if (self.chapterClickHandler) {
            self.chapterClickHandler(_video.chapters[(NSUInteger)idx]);
        }
    }
}

- (void)prepareForReuse
{
    [super prepareForReuse];
    [_thumbRequest cancel];
    _thumbRequest = nil;
    _thumbImageView.image = nil;
}

@end

#pragma mark - MacLCYouTubeChannelViewController Implementation

@interface MacLCYouTubeChannelViewController () <NSCollectionViewDataSource, NSCollectionViewDelegate>
{
    __weak MacLCYouTubeSectionViewController *_section;
    NSURL *_channelURL;
    NSString *_initialName;
    MacLCYouTubeChannel *_channel;
    MacLCYouTubeChannelTab _currentTab;

    NSMutableArray<MacLCYouTubeVideo *> *_videos;
    NSMutableArray<MacLCYouTubePlaylist *> *_playlists;
    NSUInteger _currentLimit;
    BOOL _mayHaveMore;
    BOOL _isLoading;

    MacLCYouTubeRequest *_currentRequest;
    NSPopover *_descriptionPopover;

    NSScrollView *_scrollView;
    NSCollectionView *_collectionView;
    MacLCEmptyStateView *_emptyStateView;
}
@end

@implementation MacLCYouTubeChannelViewController

- (instancetype)initWithSection:(MacLCYouTubeSectionViewController *)section
                     channelURL:(NSURL *)channelURL
                           name:(nullable NSString *)name
{
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _section = section;
        _channelURL = channelURL;
        _initialName = [name copy];
        _currentTab = MacLCYouTubeChannelTabVideos;
        _currentLimit = 36;
        _videos = [NSMutableArray array];
        _playlists = [NSMutableArray array];
        self.title = name ?: @"";
    }
    return self;
}

- (void)dealloc
{
    [_currentRequest cancel];
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)loadView
{
    NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 960.0, 720.0)];
    root.wantsLayer = YES;
    self.view = root;

    _scrollView = [[NSScrollView alloc] initWithFrame:root.bounds];
    _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _scrollView.drawsBackground = NO;
    _scrollView.hasVerticalScroller = YES;
    _scrollView.autohidesScrollers = YES;
    _scrollView.hasHorizontalScroller = NO;
    [root addSubview:_scrollView];

    _collectionView = [[NSCollectionView alloc] initWithFrame:NSZeroRect];
    _collectionView.translatesAutoresizingMaskIntoConstraints = NO;
    _collectionView.selectable = YES;
    _collectionView.allowsEmptySelection = YES;
    _collectionView.backgroundColors = @[NSColor.clearColor];
    _collectionView.dataSource = self;
    _collectionView.delegate = self;

    __weak typeof(self) weakSelf = self;
    NSCollectionViewCompositionalLayoutSectionProvider provider = ^NSCollectionLayoutSection * _Nullable(NSInteger sectionIndex, id<NSCollectionLayoutEnvironment> environment) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return nil;

        if (sectionIndex == 0) {
            CGFloat w = environment.container.effectiveContentSize.width;
            CGFloat h = [strongSelf channelHeaderHeightForWidth:w];
            return [MacLCCollectionLayout fullWidthSectionWithHeight:h];
        } else {
            if (strongSelf->_currentTab == MacLCYouTubeChannelTabPlaylists) {
                return [MacLCYouTubeLayout playlistGridSectionWithEnvironment:environment hasHeader:NO];
            } else {
                return [MacLCYouTubeLayout videoGridSectionWithEnvironment:environment hasHeader:NO];
            }
        }
    };

    NSCollectionViewCompositionalLayout *layout = [[NSCollectionViewCompositionalLayout alloc] initWithSectionProvider:provider];
    _collectionView.collectionViewLayout = layout;

    [_collectionView registerClass:[MacLCYouTubeChannelHeaderItem class] forItemWithIdentifier:MacLCYouTubeChannelHeaderItemIdentifier];
    [_collectionView registerClass:[MacLCYouTubeVideoItem class] forItemWithIdentifier:MacLCYouTubeVideoItemIdentifier];
    [_collectionView registerClass:[MacLCYouTubePlaylistItem class] forItemWithIdentifier:MacLCYouTubePlaylistItemIdentifier];

    _scrollView.documentView = _collectionView;

    [NSLayoutConstraint activateConstraints:@[
        [_scrollView.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [_scrollView.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [_scrollView.topAnchor constraintEqualToAnchor:root.topAnchor],
        [_scrollView.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],
    ]];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    [self loadChannelData];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(accountDidChange:)
                                               name:MacLCYouTubeAccountDidChangeNotification
                                             object:nil];
}

- (void)accountDidChange:(NSNotification *)notification
{
    _currentLimit = 36;
    [_videos removeAllObjects];
    [_playlists removeAllObjects];
    [self loadChannelData];
}

- (CGFloat)channelHeaderHeightForWidth:(CGFloat)width
{
    /* Mirrors the header's constraints: top 16 (+ banner + 16), avatar, 20,
     * the 30 pt tab control, then 4 (the grid adds its own 16 inset). */
    CGFloat height = 16.0 + kMacLCYouTubeChannelAvatarSize + 20.0 + 30.0 + 4.0;
    if (_channel.bannerURL != nil) {
        height += MAX(width - 48.0, 200.0) / 6.0 + 16.0;
    }
    return height;
}

- (void)loadChannelData
{
    [_currentRequest cancel];
    _isLoading = YES;

    __weak typeof(self) weakSelf = self;
    _currentRequest = [MacLCYouTubeService.sharedService channel:_channelURL
                                                            tab:_currentTab
                                                          limit:_currentLimit
                                                     completion:^(MacLCYouTubePage * _Nullable page, NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        strongSelf->_isLoading = NO;
        strongSelf->_currentRequest = nil;

        if (error) {
            /* The state replaces the list, the channel header stays. */
            [strongSelf->_videos removeAllObjects];
            [strongSelf->_playlists removeAllObjects];
            [strongSelf showEmptyStateWithError:error];
            [strongSelf->_collectionView reloadData];
            return;
        }

        [strongSelf hideEmptyState];

        if (page.channel) {
            strongSelf->_channel = page.channel;
            if (page.channel.name.length > 0) {
                strongSelf.title = page.channel.name;
                [strongSelf->_section chromeDidChange];
            }
        }

        strongSelf->_mayHaveMore = page.mayHaveMore;

        if (strongSelf->_currentTab == MacLCYouTubeChannelTabPlaylists) {
            NSMutableArray<MacLCYouTubePlaylist *> *list = [NSMutableArray array];
            for (MacLCYouTubeResult *res in page.results) {
                if (res.kind == MacLCYouTubeResultKindPlaylist && res.playlist) {
                    [list addObject:res.playlist];
                }
            }
            strongSelf->_playlists = list;
        } else {
            strongSelf->_videos = [page.videos mutableCopy];
        }

        [strongSelf->_collectionView.collectionViewLayout invalidateLayout];
        [strongSelf->_collectionView reloadData];
    }];
}

- (void)showEmptyStateWithError:(NSError *)error
{
    [_emptyStateView removeFromSuperview];
    _emptyStateView = nil;
    {
        __weak typeof(self) weakSelf = self;
        if ([error.domain isEqualToString:MacLCYouTubeErrorDomain] && error.code == MacLCYouTubeErrorBrowserCookies) {
            _emptyStateView = MacLCYouTubeBrowserCookiesStateView(^NSWindow *{ return weakSelf.view.window; }, ^{
                [weakSelf loadChannelData];
            });
        } else {
            _emptyStateView = [MacLCEmptyStateView emptyStateWithSymbolName:@"wifi.exclamationmark"
                                                                     title:_NS("Can't Reach YouTube")
                                                                   message:error.localizedDescription];
            [_emptyStateView addButtonWithTitle:_NS("Try Again") prominent:YES action:^{
                [weakSelf loadChannelData];
            }];
        }
        _emptyStateView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.view addSubview:_emptyStateView];
        [NSLayoutConstraint activateConstraints:@[
            [_emptyStateView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
            [_emptyStateView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:60.0],
            [_emptyStateView.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:24.0],
            [_emptyStateView.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-24.0],
        ]];
    }
    _emptyStateView.hidden = NO;
}

- (void)hideEmptyState
{
    if (_emptyStateView) {
        _emptyStateView.hidden = YES;
    }
}

- (void)showMoreDescriptionFromButton:(NSButton *)button
{
    NSString *desc = _channel.descriptionText;
    if (desc.length == 0) return;

    if (_descriptionPopover) {
        [_descriptionPopover performClose:nil];
        _descriptionPopover = nil;
    }

    NSViewController *popoverVC = [[NSViewController alloc] init];
    NSView *container = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 420.0, 260.0)];

    NSTextField *label = [NSTextField wrappingLabelWithString:desc];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.font = MacLCDesign.body;
    label.textColor = MacLCDesign.primaryLabel;
    label.selectable = YES;

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:container.bounds];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.drawsBackground = NO;
    scroll.hasVerticalScroller = YES;
    scroll.autohidesScrollers = YES;
    scroll.documentView = label;
    [container addSubview:scroll];

    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:container.topAnchor constant:MacLCDesign.spacingL],
        [scroll.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-MacLCDesign.spacingL],
        [scroll.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:MacLCDesign.spacingL],
        [scroll.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-MacLCDesign.spacingL],
        [label.widthAnchor constraintEqualToAnchor:scroll.contentView.widthAnchor],
    ]];

    popoverVC.view = container;
    _descriptionPopover = [[NSPopover alloc] init];
    _descriptionPopover.behavior = NSPopoverBehaviorTransient;
    _descriptionPopover.contentViewController = popoverVC;
    [_descriptionPopover showRelativeToRect:button.bounds ofView:button preferredEdge:NSRectEdgeMaxY];
}

// MARK: - NSCollectionViewDataSource

- (NSInteger)numberOfSectionsInCollectionView:(NSCollectionView *)collectionView
{
    return 2;
}

- (NSInteger)collectionView:(NSCollectionView *)collectionView numberOfItemsInSection:(NSInteger)section
{
    if (section == 0) {
        return 1;
    }

    if (_isLoading && (_videos.count == 0 && _playlists.count == 0)) {
        return 12;
    }

    if (_currentTab == MacLCYouTubeChannelTabPlaylists) {
        return (NSInteger)_playlists.count;
    } else {
        return (NSInteger)_videos.count;
    }
}

- (NSCollectionViewItem *)collectionView:(NSCollectionView *)collectionView itemForRepresentedObjectAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section == 0) {
        MacLCYouTubeChannelHeaderItem *item = [collectionView makeItemWithIdentifier:MacLCYouTubeChannelHeaderItemIdentifier forIndexPath:indexPath];
        CGFloat width = collectionView.bounds.size.width;
        [item configureWithChannel:_channel currentTab:_currentTab width:width];

        __weak typeof(self) weakSelf = self;
        item.tabChangeHandler = ^(MacLCYouTubeChannelTab tab) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf || strongSelf->_currentTab == tab) return;
            strongSelf->_currentTab = tab;
            strongSelf->_currentLimit = 36;
            [strongSelf->_videos removeAllObjects];
            [strongSelf->_playlists removeAllObjects];
            [strongSelf loadChannelData];
        };
        item.moreDescriptionHandler = ^(NSButton *button) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf) {
                [strongSelf showMoreDescriptionFromButton:button];
            }
        };
        return item;
    }

    if (_currentTab == MacLCYouTubeChannelTabPlaylists) {
        MacLCYouTubePlaylistItem *item = [collectionView makeItemWithIdentifier:MacLCYouTubePlaylistItemIdentifier forIndexPath:indexPath];
        if (indexPath.item < (NSInteger)_playlists.count) {
            MacLCYouTubePlaylist *pl = _playlists[(NSUInteger)indexPath.item];
            [item configureWithPlaylist:pl];
            __weak typeof(self) weakSelf = self;
            item.activationHandler = ^(MacLCYouTubePlaylist *playlist) {
                __strong typeof(weakSelf) strongSelf = weakSelf;
                if (strongSelf) {
                    [strongSelf->_section showPlaylist:playlist];
                }
            };
        } else {
            [item configureWithPlaylist:(MacLCYouTubePlaylist * _Nonnull)nil];
        }
        return item;
    } else {
        MacLCYouTubeVideoItem *item = [collectionView makeItemWithIdentifier:MacLCYouTubeVideoItemIdentifier forIndexPath:indexPath];
        item.showsChannel = NO;
        if (indexPath.item < (NSInteger)_videos.count) {
            MacLCYouTubeVideo *v = _videos[(NSUInteger)indexPath.item];
            [item configureWithVideo:v];
            __weak typeof(self) weakSelf = self;
            __weak typeof(item) weakItem = item;
            item.activationHandler = ^(MacLCYouTubeVideo *video) {
                __strong typeof(weakSelf) strongSelf = weakSelf;
                if (strongSelf) {
                    [MacLCYouTubeActions playVideo:video fromItem:weakItem window:strongSelf.view.window];
                }
            };
            item.enqueueHandler = ^(MacLCYouTubeVideo *video) {
                [MacLCYouTubeActions enqueueVideo:video];
            };
            item.detailsHandler = ^(MacLCYouTubeVideo *video) {
                __strong typeof(weakSelf) strongSelf = weakSelf;
                if (strongSelf) {
                    [strongSelf->_section showDetailsForVideo:video];
                }
            };
            item.channelHandler = nil;
        } else {
            [item configureWithVideo:(id _Nonnull)nil];
        }
        return item;
    }
}

// MARK: - NSCollectionViewDelegate

- (void)collectionView:(NSCollectionView *)collectionView willDisplayItem:(NSCollectionViewItem *)item forRepresentedObjectAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section == 1 && _mayHaveMore && !_isLoading) {
        NSInteger totalCount = (_currentTab == MacLCYouTubeChannelTabPlaylists) ? (NSInteger)_playlists.count : (NSInteger)_videos.count;
        if (indexPath.item >= totalCount - 4) {
            _currentLimit += 36;
            [self loadChannelData];
        }
    }
}

@end

#pragma mark - MacLCYouTubePlaylistViewController Implementation

@interface MacLCYouTubePlaylistViewController () <NSCollectionViewDataSource, NSCollectionViewDelegate>
{
    __weak MacLCYouTubeSectionViewController *_section;
    MacLCYouTubePlaylist *_playlist;
    NSMutableArray<MacLCYouTubeVideo *> *_videos;
    BOOL _isLoading;

    MacLCYouTubeRequest *_request;
    NSScrollView *_scrollView;
    NSCollectionView *_collectionView;
    MacLCEmptyStateView *_emptyStateView;
}
@end

@implementation MacLCYouTubePlaylistViewController

- (instancetype)initWithSection:(MacLCYouTubeSectionViewController *)section
                       playlist:(MacLCYouTubePlaylist *)playlist
{
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _section = section;
        _playlist = playlist;
        _videos = [NSMutableArray array];
        self.title = playlist.title ?: @"";
    }
    return self;
}

- (void)dealloc
{
    [_request cancel];
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)loadView
{
    NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 960.0, 720.0)];
    root.wantsLayer = YES;
    self.view = root;

    _scrollView = [[NSScrollView alloc] initWithFrame:root.bounds];
    _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _scrollView.drawsBackground = NO;
    _scrollView.hasVerticalScroller = YES;
    _scrollView.autohidesScrollers = YES;
    _scrollView.hasHorizontalScroller = NO;
    [root addSubview:_scrollView];

    _collectionView = [[NSCollectionView alloc] initWithFrame:NSZeroRect];
    _collectionView.translatesAutoresizingMaskIntoConstraints = NO;
    _collectionView.selectable = YES;
    _collectionView.allowsEmptySelection = YES;
    _collectionView.backgroundColors = @[NSColor.clearColor];
    _collectionView.dataSource = self;
    _collectionView.delegate = self;

    NSCollectionViewCompositionalLayoutSectionProvider provider = ^NSCollectionLayoutSection * _Nullable(NSInteger sectionIndex, id<NSCollectionLayoutEnvironment> environment) {
        if (sectionIndex == 0) {
            return [MacLCCollectionLayout fullWidthSectionWithHeight:240.0];
        } else {
            NSCollectionLayoutSize *rowSize = [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1.0]
                                                                            heightDimension:[NSCollectionLayoutDimension absoluteDimension:kMacLCYouTubePlaylistRowHeight]];
            NSCollectionLayoutItem *rowItem = [NSCollectionLayoutItem itemWithLayoutSize:rowSize];
            NSCollectionLayoutGroup *rowGroup = [NSCollectionLayoutGroup horizontalGroupWithLayoutSize:rowSize subitems:@[rowItem]];
            NSCollectionLayoutSection *rowSection = [NSCollectionLayoutSection sectionWithGroup:rowGroup];
            rowSection.interGroupSpacing = 6.0;
            rowSection.contentInsets = NSDirectionalEdgeInsetsMake(16.0, 24.0, 24.0, 24.0);
            return rowSection;
        }
    };

    NSCollectionViewCompositionalLayout *layout = [[NSCollectionViewCompositionalLayout alloc] initWithSectionProvider:provider];
    _collectionView.collectionViewLayout = layout;

    [_collectionView registerClass:[MacLCYouTubePlaylistHeaderItem class] forItemWithIdentifier:MacLCYouTubePlaylistHeaderItemIdentifier];
    [_collectionView registerClass:[MacLCYouTubePlaylistRowItem class] forItemWithIdentifier:MacLCYouTubePlaylistRowItemIdentifier];

    _scrollView.documentView = _collectionView;

    [NSLayoutConstraint activateConstraints:@[
        [_scrollView.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [_scrollView.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [_scrollView.topAnchor constraintEqualToAnchor:root.topAnchor],
        [_scrollView.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],
    ]];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    [self loadPlaylistData];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(accountDidChange:)
                                               name:MacLCYouTubeAccountDidChangeNotification
                                             object:nil];
}

- (void)accountDidChange:(NSNotification *)notification
{
    [_videos removeAllObjects];
    [self loadPlaylistData];
}

- (void)loadPlaylistData
{
    if (!_playlist.URL) return;

    [_request cancel];
    _isLoading = YES;

    __weak typeof(self) weakSelf = self;
    _request = [MacLCYouTubeService.sharedService playlist:_playlist.URL
                                                     limit:0
                                                completion:^(MacLCYouTubePage * _Nullable page, NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        strongSelf->_isLoading = NO;
        strongSelf->_request = nil;

        if (error) {
            [strongSelf->_videos removeAllObjects];
            [strongSelf showEmptyStateWithError:error];
            [strongSelf->_collectionView reloadData];
            return;
        }

        [strongSelf hideEmptyState];
        strongSelf->_videos = [page.videos mutableCopy];

        if (page.title.length > 0) {
            strongSelf.title = page.title;
            [strongSelf->_section chromeDidChange];
        }

        [strongSelf->_collectionView reloadData];
    }];
}

- (void)showEmptyStateWithError:(NSError *)error
{
    [_emptyStateView removeFromSuperview];
    _emptyStateView = nil;
    {
        __weak typeof(self) weakSelf = self;
        if ([error.domain isEqualToString:MacLCYouTubeErrorDomain] && error.code == MacLCYouTubeErrorBrowserCookies) {
            _emptyStateView = MacLCYouTubeBrowserCookiesStateView(^NSWindow *{ return weakSelf.view.window; }, ^{
                [weakSelf loadPlaylistData];
            });
        } else {
            _emptyStateView = [MacLCEmptyStateView emptyStateWithSymbolName:@"wifi.exclamationmark"
                                                                     title:_NS("Can't Reach YouTube")
                                                                   message:error.localizedDescription];
            [_emptyStateView addButtonWithTitle:_NS("Try Again") prominent:YES action:^{
                [weakSelf loadPlaylistData];
            }];
        }
        _emptyStateView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.view addSubview:_emptyStateView];
        [NSLayoutConstraint activateConstraints:@[
            [_emptyStateView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
            [_emptyStateView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:60.0],
            [_emptyStateView.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:24.0],
            [_emptyStateView.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-24.0],
        ]];
    }
    _emptyStateView.hidden = NO;
}

- (void)hideEmptyState
{
    if (_emptyStateView) {
        _emptyStateView.hidden = YES;
    }
}

- (void)playAll
{
    if (_videos.count == 0) return;
    [MacLCYouTubeService.sharedService playVideos:_videos startingAtIndex:0 completion:nil];
}

- (void)shufflePlay
{
    if (_videos.count == 0) return;
    NSMutableArray<MacLCYouTubeVideo *> *shuffled = [_videos mutableCopy];
    for (NSUInteger i = shuffled.count - 1; i > 0; i--) {
        NSUInteger j = arc4random_uniform((uint32_t)(i + 1));
        [shuffled exchangeObjectAtIndex:i withObjectAtIndex:j];
    }
    [MacLCYouTubeService.sharedService playVideos:shuffled startingAtIndex:0 completion:nil];
}

// MARK: - NSCollectionViewDataSource

- (NSInteger)numberOfSectionsInCollectionView:(NSCollectionView *)collectionView
{
    return 2;
}

- (NSInteger)collectionView:(NSCollectionView *)collectionView numberOfItemsInSection:(NSInteger)section
{
    if (section == 0) {
        return 1;
    }
    return (NSInteger)_videos.count;
}

- (NSCollectionViewItem *)collectionView:(NSCollectionView *)collectionView itemForRepresentedObjectAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section == 0) {
        MacLCYouTubePlaylistHeaderItem *item = [collectionView makeItemWithIdentifier:MacLCYouTubePlaylistHeaderItemIdentifier forIndexPath:indexPath];
        [item configureWithPlaylist:_playlist videoCount:_videos.count];

        __weak typeof(self) weakSelf = self;
        item.playAllHandler = ^{
            [weakSelf playAll];
        };
        item.shuffleHandler = ^{
            [weakSelf shufflePlay];
        };
        item.channelClickHandler = ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf && strongSelf->_playlist.channelName) {
                NSString * const name = strongSelf->_playlist.channelName;
                [strongSelf->_section goBack];
                NSViewController *root = strongSelf->_section.rootViewController;
                if ([root respondsToSelector:@selector(applySearchString:)]) {
                    [(MacLCYouTubeFeedViewController *)root applySearchString:name];
                }
            }
        };
        return item;
    }

    MacLCYouTubePlaylistRowItem *rowItem = [collectionView makeItemWithIdentifier:MacLCYouTubePlaylistRowItemIdentifier forIndexPath:indexPath];
    if (indexPath.item < (NSInteger)_videos.count) {
        MacLCYouTubeVideo *video = _videos[(NSUInteger)indexPath.item];
        [rowItem configureWithVideo:video index:(NSUInteger)indexPath.item];

        __weak typeof(self) weakSelf = self;
        rowItem.activationHandler = ^(MacLCYouTubeVideo *v, NSUInteger idx) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf) {
                [MacLCYouTubeService.sharedService playVideos:strongSelf->_videos startingAtIndex:idx completion:nil];
            }
        };
        rowItem.enqueueHandler = ^(MacLCYouTubeVideo *v) {
            [MacLCYouTubeActions enqueueVideo:v];
        };
        rowItem.detailsHandler = ^(MacLCYouTubeVideo *v) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf) {
                [strongSelf->_section showDetailsForVideo:v];
            }
        };
        rowItem.channelHandler = ^(MacLCYouTubeVideo *v) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf) {
                if (v.channelURL != nil) {
                    [strongSelf->_section showChannelWithURL:v.channelURL name:v.channelName];
                }
            }
        };
    }
    return rowItem;
}

@end

#pragma mark - MacLCYouTubeVideoViewController Implementation

@interface MacLCYouTubeVideoViewController () <NSCollectionViewDataSource, NSCollectionViewDelegate>
{
    __weak MacLCYouTubeSectionViewController *_section;
    MacLCYouTubeVideo *_video;
    NSArray<MacLCYouTubeVideo *> *_channelVideos;
    BOOL _isDescriptionExpanded;

    MacLCYouTubeRequest *_detailsRequest;
    MacLCYouTubeRequest *_moreVideosRequest;

    NSScrollView *_scrollView;
    NSCollectionView *_collectionView;
}
@end

@implementation MacLCYouTubeVideoViewController

- (instancetype)initWithSection:(MacLCYouTubeSectionViewController *)section
                          video:(MacLCYouTubeVideo *)video
{
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _section = section;
        _video = video;
        _channelVideos = @[];
        _isDescriptionExpanded = NO;
        self.title = video.title ?: @"";
    }
    return self;
}

- (void)dealloc
{
    [_detailsRequest cancel];
    [_moreVideosRequest cancel];
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)loadView
{
    NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 960.0, 720.0)];
    root.wantsLayer = YES;
    self.view = root;

    _scrollView = [[NSScrollView alloc] initWithFrame:root.bounds];
    _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _scrollView.drawsBackground = NO;
    _scrollView.hasVerticalScroller = YES;
    _scrollView.autohidesScrollers = YES;
    _scrollView.hasHorizontalScroller = NO;
    [root addSubview:_scrollView];

    _collectionView = [[NSCollectionView alloc] initWithFrame:NSZeroRect];
    _collectionView.translatesAutoresizingMaskIntoConstraints = NO;
    _collectionView.selectable = YES;
    _collectionView.allowsEmptySelection = YES;
    _collectionView.backgroundColors = @[NSColor.clearColor];
    _collectionView.dataSource = self;
    _collectionView.delegate = self;

    __weak typeof(self) weakSelf = self;
    NSCollectionViewCompositionalLayoutSectionProvider provider = ^NSCollectionLayoutSection * _Nullable(NSInteger sectionIndex, id<NSCollectionLayoutEnvironment> environment) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return nil;

        if (sectionIndex == 0) {
            CGFloat w = environment.container.effectiveContentSize.width;
            CGFloat h = [strongSelf videoHeaderHeightForWidth:w];
            return [MacLCCollectionLayout fullWidthSectionWithHeight:h];
        } else {
            return [MacLCYouTubeLayout videoGridSectionWithEnvironment:environment hasHeader:YES];
        }
    };

    NSCollectionViewCompositionalLayout *layout = [[NSCollectionViewCompositionalLayout alloc] initWithSectionProvider:provider];
    _collectionView.collectionViewLayout = layout;

    [_collectionView registerClass:[MacLCYouTubeVideoHeaderItem class] forItemWithIdentifier:MacLCYouTubeVideoHeaderItemIdentifier];
    [_collectionView registerClass:[MacLCYouTubeVideoItem class] forItemWithIdentifier:MacLCYouTubeVideoItemIdentifier];
    [_collectionView registerClass:[MacLCSectionHeaderView class]
        forSupplementaryViewOfKind:NSCollectionElementKindSectionHeader
                    withIdentifier:MacLCSectionHeaderViewIdentifier];

    _scrollView.documentView = _collectionView;

    [NSLayoutConstraint activateConstraints:@[
        [_scrollView.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [_scrollView.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [_scrollView.topAnchor constraintEqualToAnchor:root.topAnchor],
        [_scrollView.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],
    ]];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    [self loadVideoDetails];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(accountDidChange:)
                                               name:MacLCYouTubeAccountDidChangeNotification
                                             object:nil];
}

- (void)accountDidChange:(NSNotification *)notification
{
    [self loadVideoDetails];
}

- (CGFloat)videoHeaderHeightForWidth:(CGFloat)width
{
    CGFloat thumbW = MIN(MAX(width - 48.0, 320.0), kMacLCYouTubeVideoMaxThumbnailWidth);
    CGFloat thumbH = thumbW * 9.0 / 16.0;

    // Title measurement
    NSString *title = _video.title ?: @"";
    NSRect titleBounds = [title boundingRectWithSize:NSMakeSize(thumbW, CGFLOAT_MAX)
                                             options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                                          attributes:@{NSFontAttributeName: [NSFont systemFontOfSize:MacLCDesign.title1.pointSize weight:NSFontWeightBold]}];
    CGFloat titleH = MAX(ceil(titleBounds.size.height), 28.0);

    CGFloat channelRowH = 42.0;

    // Description box measurement
    CGFloat descBoxH = 156.0;
    if (_isDescriptionExpanded && _video.descriptionText.length > 0) {
        NSRect descBounds = [_video.descriptionText boundingRectWithSize:NSMakeSize(thumbW - 32.0, CGFLOAT_MAX)
                                                                 options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                                                              attributes:@{NSFontAttributeName: MacLCDesign.body}];
        descBoxH = 20.0 + 8.0 + ceil(descBounds.size.height) + 6.0 + 24.0 + 26.0;
    }

    CGFloat chaptersH = (_video.chapters.count > 0) ? 50.0 : 0.0;

    return 16.0 + thumbH + 16.0 + titleH + 14.0 + channelRowH + 16.0 + descBoxH + chaptersH + 24.0;
}

- (void)loadVideoDetails
{
    if (!_video) return;

    [_detailsRequest cancel];
    __weak typeof(self) weakSelf = self;
    _detailsRequest = [MacLCYouTubeService.sharedService detailsForVideo:_video
                                                              completion:^(MacLCYouTubeVideo * _Nullable detailedVideo, NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        strongSelf->_detailsRequest = nil;

        if (detailedVideo) {
            strongSelf->_video = detailedVideo;
            if (detailedVideo.title.length > 0) {
                strongSelf.title = detailedVideo.title;
                [strongSelf->_section chromeDidChange];
            }
            [strongSelf->_collectionView.collectionViewLayout invalidateLayout];
            [strongSelf->_collectionView reloadData];

            [strongSelf loadMoreFromChannel];
        }
    }];
}

- (void)loadMoreFromChannel
{
    if (!_video.channelURL) return;

    [_moreVideosRequest cancel];
    __weak typeof(self) weakSelf = self;
    _moreVideosRequest = [MacLCYouTubeService.sharedService channel:_video.channelURL
                                                               tab:MacLCYouTubeChannelTabVideos
                                                             limit:12
                                                        completion:^(MacLCYouTubePage * _Nullable page, NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        strongSelf->_moreVideosRequest = nil;

        if (page && page.videos.count > 0) {
            strongSelf->_channelVideos = page.videos;
            [strongSelf->_collectionView.collectionViewLayout invalidateLayout];
            [strongSelf->_collectionView reloadData];
        }
    }];
}

- (void)toggleDescription
{
    _isDescriptionExpanded = !_isDescriptionExpanded;
    [_collectionView.collectionViewLayout invalidateLayout];
    [_collectionView reloadSections:[NSIndexSet indexSetWithIndex:0]];
}

// MARK: - NSCollectionViewDataSource

- (NSInteger)numberOfSectionsInCollectionView:(NSCollectionView *)collectionView
{
    return (_channelVideos.count > 0) ? 2 : 1;
}

- (NSInteger)collectionView:(NSCollectionView *)collectionView numberOfItemsInSection:(NSInteger)section
{
    if (section == 0) {
        return 1;
    }
    return (NSInteger)_channelVideos.count;
}

- (NSCollectionViewItem *)collectionView:(NSCollectionView *)collectionView itemForRepresentedObjectAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section == 0) {
        MacLCYouTubeVideoHeaderItem *headerItem = [collectionView makeItemWithIdentifier:MacLCYouTubeVideoHeaderItemIdentifier forIndexPath:indexPath];
        CGFloat width = collectionView.bounds.size.width;
        [headerItem configureWithVideo:_video isExpanded:_isDescriptionExpanded width:width];

        __weak typeof(self) weakSelf = self;
        headerItem.playHandler = ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf && strongSelf->_video) {
                [MacLCYouTubeActions playVideo:strongSelf->_video fromItem:nil window:strongSelf.view.window];
            }
        };
        headerItem.channelClickHandler = ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf) {
                if (strongSelf->_video.channelURL != nil) {
                    [strongSelf->_section showChannelWithURL:strongSelf->_video.channelURL name:strongSelf->_video.channelName];
                }
            }
        };
        headerItem.enqueueHandler = ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf && strongSelf->_video) {
                [MacLCYouTubeActions enqueueVideo:strongSelf->_video];
            }
        };
        headerItem.onCopyLinkHandler = ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf && strongSelf->_video) {
                [MacLCYouTubeActions copyLinkOfVideo:strongSelf->_video];
            }
        };
        headerItem.browserHandler = ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf && strongSelf->_video.watchURL) {
                [MacLCYouTubeActions openInBrowser:strongSelf->_video.watchURL];
            }
        };
        headerItem.toggleDescriptionHandler = ^{
            [weakSelf toggleDescription];
        };
        headerItem.chapterClickHandler = ^(MacLCYouTubeChapter *chapter) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf && strongSelf->_video) {
                [MacLCYouTubeService.sharedService playVideo:strongSelf->_video startTime:chapter.start completion:nil];
            }
        };
        return headerItem;
    }

    MacLCYouTubeVideoItem *videoItem = [collectionView makeItemWithIdentifier:MacLCYouTubeVideoItemIdentifier forIndexPath:indexPath];
    videoItem.showsChannel = NO;

    if (indexPath.item < (NSInteger)_channelVideos.count) {
        MacLCYouTubeVideo *v = _channelVideos[(NSUInteger)indexPath.item];
        [videoItem configureWithVideo:v];

        __weak typeof(self) weakSelf = self;
        videoItem.activationHandler = ^(MacLCYouTubeVideo *video) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf) {
                [strongSelf->_section showDetailsForVideo:video];
            }
        };
        videoItem.enqueueHandler = ^(MacLCYouTubeVideo *video) {
            [MacLCYouTubeActions enqueueVideo:video];
        };
        videoItem.detailsHandler = ^(MacLCYouTubeVideo *video) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf) {
                [strongSelf->_section showDetailsForVideo:video];
            }
        };
        videoItem.channelHandler = nil;
    }
    return videoItem;
}

- (NSView *)collectionView:(NSCollectionView *)collectionView viewForSupplementaryElementOfKind:(NSCollectionViewSupplementaryElementKind)kind atIndexPath:(NSIndexPath *)indexPath
{
    if ([kind isEqualToString:NSCollectionElementKindSectionHeader] && indexPath.section == 1) {
        MacLCSectionHeaderView *header = [collectionView makeSupplementaryViewOfKind:kind
                                                                      withIdentifier:MacLCSectionHeaderViewIdentifier
                                                                        forIndexPath:indexPath];
        NSString *channelTitle = _video.channelName ?: _NS("Channel");
        header.title = [NSString stringWithFormat:_NS("More from %@"), channelTitle];
        header.subtitle = nil;
        header.actionTitle = nil;
        header.action = nil;
        return header;
    }
    return [[NSView alloc] initWithFrame:NSZeroRect];
}

@end
