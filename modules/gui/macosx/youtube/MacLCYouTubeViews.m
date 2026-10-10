/*****************************************************************************
 * MacLCYouTubeViews.m: the building blocks of the YouTube section: video
 * cards, result rows, channel and playlist tiles, topic chips, the account
 * button, layouts
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

#import "youtube/MacLCYouTubeViews.h"

#import "youtube/MacLCYouTubeAccount.h"
#import "youtube/MacLCYouTubeService.h"
#import "addons/watch/MacLCWatchComponents.h"
#import "theme/MacLCDesign.h"
#import "medialib/components/MacLCEmptyStateView.h"
#import "extensions/NSString+Helpers.h"

#pragma mark - Identifiers

NSUserInterfaceItemIdentifier const MacLCYouTubeVideoItemIdentifier = @"MacLCYouTubeVideoItemIdentifier";
NSUserInterfaceItemIdentifier const MacLCYouTubeResultRowItemIdentifier = @"MacLCYouTubeResultRowItemIdentifier";
NSUserInterfaceItemIdentifier const MacLCYouTubeChannelItemIdentifier = @"MacLCYouTubeChannelItemIdentifier";
NSUserInterfaceItemIdentifier const MacLCYouTubePlaylistItemIdentifier = @"MacLCYouTubePlaylistItemIdentifier";

#pragma mark - Forward Declarations

@class MacLCYouTubeVideoCardView;
@class MacLCYouTubeResultRowView;
@class MacLCYouTubeChannelTileView;
@class MacLCYouTubePlaylistTileView;

#pragma mark - Shared Helper Functions

static CGFloat BackingScaleForView(NSView *view)
{
    if (view.window != nil && view.window.backingScaleFactor > 0.0) {
        return view.window.backingScaleFactor;
    }
    if (NSScreen.mainScreen != nil && NSScreen.mainScreen.backingScaleFactor > 0.0) {
        return NSScreen.mainScreen.backingScaleFactor;
    }
    return 2.0;
}

static void StyleGlassCircleButton(NSButton *button, CGFloat size)
{
    button.bordered = YES;
    button.imagePosition = NSImageOnly;
    button.imageScaling = NSImageScaleProportionallyUpOrDown;
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [button.widthAnchor constraintEqualToConstant:size],
        [button.heightAnchor constraintEqualToConstant:size],
    ]];

    if (@available(macOS 26.0, *)) {
        button.bezelStyle = NSBezelStyleGlass;
        button.borderShape = NSControlBorderShapeCircle;
        button.contentTintColor = NSColor.whiteColor;
    } else {
        button.wantsLayer = YES;
        button.layer.cornerRadius = size / 2.0;
        button.layer.masksToBounds = YES;
        button.layer.backgroundColor = [NSColor colorWithCalibratedWhite:0.0 alpha:0.65].CGColor;
        button.layer.borderColor = [NSColor colorWithCalibratedWhite:1.0 alpha:0.2].CGColor;
        button.layer.borderWidth = 0.5;
        button.bezelStyle = NSBezelStyleCircular;
        button.contentTintColor = NSColor.whiteColor;
    }
}

#pragma mark - Video Card View

@interface MacLCYouTubeVideoCardView : NSView

@property (nonatomic, weak, nullable) MacLCYouTubeVideoItem *item;
@property (nonatomic, strong) NSView *thumbnailWrapperView;
@property (nonatomic, strong) NSView *thumbnailContainerView;
@property (nonatomic, strong) NSImageView *placeholderImageView;
@property (nonatomic, strong) NSView *thumbnailImageView;
@property (nonatomic, strong) NSView *durationBadgeView;
@property (nonatomic, strong) NSTextField *durationBadgeLabel;
@property (nonatomic, strong) NSButton *addToQueueButton;
@property (nonatomic, strong) NSProgressIndicator *openingSpinner;

@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSView *channelContainerView;
@property (nonatomic, strong) NSTextField *channelLabel;
@property (nonatomic, strong) NSImageView *verifiedSealImageView;
@property (nonatomic, strong) NSTextField *metadataLabel;

/* Placeholder skeleton bars */
@property (nonatomic, strong) NSView *placeholderTitleBar1;
@property (nonatomic, strong) NSView *placeholderTitleBar2;
@property (nonatomic, strong) NSView *placeholderMetaBar;

@property (nonatomic) BOOL isHovered;
@property (nonatomic) BOOL isOpening;
@property (nonatomic, strong, nullable) NSTrackingArea *trackingArea;

- (void)configureWithVideo:(nullable MacLCYouTubeVideo *)video showsChannel:(BOOL)showsChannel;
- (void)setOpening:(BOOL)opening;
- (void)updateHoverState:(BOOL)hovered animated:(BOOL)animated;

@end

@implementation MacLCYouTubeVideoCardView

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;

        /* Thumbnail wrapper: scales up 1.03 on hover */
        _thumbnailWrapperView = [[NSView alloc] initWithFrame:NSZeroRect];
        _thumbnailWrapperView.translatesAutoresizingMaskIntoConstraints = NO;
        _thumbnailWrapperView.wantsLayer = YES;
        _thumbnailWrapperView.layer.masksToBounds = NO;
        [self addSubview:_thumbnailWrapperView];

        /* Thumbnail container: 16:9, rounded 12 pt, aspect fill */
        _thumbnailContainerView = [[NSView alloc] initWithFrame:NSZeroRect];
        _thumbnailContainerView.translatesAutoresizingMaskIntoConstraints = NO;
        _thumbnailContainerView.wantsLayer = YES;
        _thumbnailContainerView.layer.masksToBounds = YES;
        _thumbnailContainerView.layer.cornerRadius = 12.0;
        _thumbnailContainerView.layer.cornerCurve = kCACornerCurveContinuous;
        _thumbnailContainerView.layer.backgroundColor = NSColor.quaternarySystemFillColor.CGColor;
        [_thumbnailWrapperView addSubview:_thumbnailContainerView];

        /* Placeholder image inside thumbnail */
        _placeholderImageView = [[NSImageView alloc] initWithFrame:NSZeroRect];
        _placeholderImageView.translatesAutoresizingMaskIntoConstraints = NO;
        _placeholderImageView.imageScaling = NSImageScaleProportionallyUpOrDown;
        _placeholderImageView.contentTintColor = NSColor.tertiaryLabelColor;
        NSImageSymbolConfiguration *placeholderConfig =
            [NSImageSymbolConfiguration configurationWithPointSize:36.0 weight:NSFontWeightLight];
        NSImage *placeholder = [NSImage imageWithSystemSymbolName:@"play.rectangle" accessibilityDescription:nil];
        if (placeholder != nil) {
            placeholder = [placeholder imageWithSymbolConfiguration:placeholderConfig];
        }
        _placeholderImageView.image = placeholder;
        [_thumbnailContainerView addSubview:_placeholderImageView];

        /* Real thumbnail image layer view */
        _thumbnailImageView = [[NSView alloc] initWithFrame:NSZeroRect];
        _thumbnailImageView.translatesAutoresizingMaskIntoConstraints = NO;
        _thumbnailImageView.wantsLayer = YES;
        _thumbnailImageView.layer.contentsGravity = kCAGravityResizeAspectFill;
        _thumbnailImageView.layer.masksToBounds = YES;
        _thumbnailImageView.hidden = YES;
        [_thumbnailContainerView addSubview:_thumbnailImageView];

        /* Duration badge: bottom-trailing, 6 pt in */
        _durationBadgeView = [[NSView alloc] initWithFrame:NSZeroRect];
        _durationBadgeView.translatesAutoresizingMaskIntoConstraints = NO;
        _durationBadgeView.wantsLayer = YES;
        _durationBadgeView.layer.masksToBounds = YES;
        _durationBadgeView.layer.backgroundColor = [NSColor colorWithCalibratedWhite:0.0 alpha:0.78].CGColor;
        [_thumbnailContainerView addSubview:_durationBadgeView];

        _durationBadgeLabel = [NSTextField labelWithString:@""];
        _durationBadgeLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _durationBadgeLabel.textColor = NSColor.whiteColor;
        _durationBadgeLabel.font = [NSFont monospacedDigitSystemFontOfSize:12.0 weight:NSFontWeightSemibold];
        _durationBadgeLabel.alignment = NSTextAlignmentCenter;
        _durationBadgeLabel.selectable = NO;
        [_durationBadgeView addSubview:_durationBadgeLabel];

        /* Add to Queue button: top-trailing, 6 pt in, 28 pt glass circle */
        _addToQueueButton = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"text.badge.plus"
                                                                accessibilityDescription:_NS("Add to Queue")]
                                               target:self
                                               action:@selector(addToQueueClicked:)];
        _addToQueueButton.toolTip = _NS("Add to Queue");
        _addToQueueButton.accessibilityLabel = _NS("Add to Queue");
        _addToQueueButton.alphaValue = 0.0;
        StyleGlassCircleButton(_addToQueueButton, 28.0);
        [_thumbnailWrapperView addSubview:_addToQueueButton];

        /* Spinner for opening */
        _openingSpinner = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
        _openingSpinner.translatesAutoresizingMaskIntoConstraints = NO;
        _openingSpinner.style = NSProgressIndicatorStyleSpinning;
        _openingSpinner.controlSize = NSControlSizeSmall;
        _openingSpinner.displayedWhenStopped = NO;
        _openingSpinner.hidden = YES;
        [_thumbnailContainerView addSubview:_openingSpinner];

        /* Title: 15 pt semibold, labelColor, 2 lines, word wrap, truncates last line */
        _titleLabel = [NSTextField labelWithString:@""];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _titleLabel.font = [NSFont systemFontOfSize:15.0 weight:NSFontWeightSemibold];
        _titleLabel.textColor = NSColor.labelColor;
        _titleLabel.lineBreakMode = NSLineBreakByWordWrapping;
        _titleLabel.cell.truncatesLastVisibleLine = YES;
        _titleLabel.maximumNumberOfLines = 2;
        _titleLabel.selectable = NO;
        [self addSubview:_titleLabel];

        /* Channel row: 13 pt secondaryLabel + checkmark.seal.fill (11 pt) */
        _channelContainerView = [[NSView alloc] initWithFrame:NSZeroRect];
        _channelContainerView.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_channelContainerView];

        _channelLabel = [NSTextField labelWithString:@""];
        _channelLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _channelLabel.font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightRegular];
        _channelLabel.textColor = NSColor.secondaryLabelColor;
        _channelLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _channelLabel.maximumNumberOfLines = 1;
        _channelLabel.selectable = NO;
        [_channelContainerView addSubview:_channelLabel];

        _verifiedSealImageView = [[NSImageView alloc] initWithFrame:NSZeroRect];
        _verifiedSealImageView.translatesAutoresizingMaskIntoConstraints = NO;
        _verifiedSealImageView.imageScaling = NSImageScaleProportionallyUpOrDown;
        _verifiedSealImageView.contentTintColor = NSColor.secondaryLabelColor;
        NSImageSymbolConfiguration *sealConfig =
            [NSImageSymbolConfiguration configurationWithPointSize:11.0 weight:NSFontWeightMedium];
        NSImage *sealImage = [NSImage imageWithSystemSymbolName:@"checkmark.seal.fill" accessibilityDescription:_NS("Verified")];
        if (sealImage != nil) {
            sealImage = [sealImage imageWithSymbolConfiguration:sealConfig];
        }
        _verifiedSealImageView.image = sealImage;
        _verifiedSealImageView.hidden = YES;
        [_channelContainerView addSubview:_verifiedSealImageView];

        /* Metadata label: 13 pt secondaryLabel */
        _metadataLabel = [NSTextField labelWithString:@""];
        _metadataLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _metadataLabel.font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightRegular];
        _metadataLabel.textColor = NSColor.secondaryLabelColor;
        _metadataLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _metadataLabel.maximumNumberOfLines = 1;
        _metadataLabel.selectable = NO;
        [self addSubview:_metadataLabel];

        /* Skeletons for loading state */
        _placeholderTitleBar1 = [[NSView alloc] initWithFrame:NSZeroRect];
        _placeholderTitleBar1.translatesAutoresizingMaskIntoConstraints = NO;
        _placeholderTitleBar1.wantsLayer = YES;
        _placeholderTitleBar1.layer.cornerRadius = 4.0;
        _placeholderTitleBar1.layer.backgroundColor = NSColor.quaternarySystemFillColor.CGColor;
        _placeholderTitleBar1.hidden = YES;
        [self addSubview:_placeholderTitleBar1];

        _placeholderTitleBar2 = [[NSView alloc] initWithFrame:NSZeroRect];
        _placeholderTitleBar2.translatesAutoresizingMaskIntoConstraints = NO;
        _placeholderTitleBar2.wantsLayer = YES;
        _placeholderTitleBar2.layer.cornerRadius = 4.0;
        _placeholderTitleBar2.layer.backgroundColor = NSColor.quaternarySystemFillColor.CGColor;
        _placeholderTitleBar2.hidden = YES;
        [self addSubview:_placeholderTitleBar2];

        _placeholderMetaBar = [[NSView alloc] initWithFrame:NSZeroRect];
        _placeholderMetaBar.translatesAutoresizingMaskIntoConstraints = NO;
        _placeholderMetaBar.wantsLayer = YES;
        _placeholderMetaBar.layer.cornerRadius = 4.0;
        _placeholderMetaBar.layer.backgroundColor = NSColor.quaternarySystemFillColor.CGColor;
        _placeholderMetaBar.hidden = YES;
        [self addSubview:_placeholderMetaBar];

        /* Layout constraints */
        [NSLayoutConstraint activateConstraints:@[
            [_thumbnailWrapperView.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_thumbnailWrapperView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_thumbnailWrapperView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_thumbnailWrapperView.heightAnchor constraintEqualToAnchor:_thumbnailWrapperView.widthAnchor multiplier:9.0 / 16.0],

            [_thumbnailContainerView.topAnchor constraintEqualToAnchor:_thumbnailWrapperView.topAnchor],
            [_thumbnailContainerView.bottomAnchor constraintEqualToAnchor:_thumbnailWrapperView.bottomAnchor],
            [_thumbnailContainerView.leadingAnchor constraintEqualToAnchor:_thumbnailWrapperView.leadingAnchor],
            [_thumbnailContainerView.trailingAnchor constraintEqualToAnchor:_thumbnailWrapperView.trailingAnchor],

            [_placeholderImageView.centerXAnchor constraintEqualToAnchor:_thumbnailContainerView.centerXAnchor],
            [_placeholderImageView.centerYAnchor constraintEqualToAnchor:_thumbnailContainerView.centerYAnchor],
            [_placeholderImageView.widthAnchor constraintEqualToConstant:44.0],
            [_placeholderImageView.heightAnchor constraintEqualToConstant:44.0],

            [_thumbnailImageView.topAnchor constraintEqualToAnchor:_thumbnailContainerView.topAnchor],
            [_thumbnailImageView.bottomAnchor constraintEqualToAnchor:_thumbnailContainerView.bottomAnchor],
            [_thumbnailImageView.leadingAnchor constraintEqualToAnchor:_thumbnailContainerView.leadingAnchor],
            [_thumbnailImageView.trailingAnchor constraintEqualToAnchor:_thumbnailContainerView.trailingAnchor],

            /* Badge: 6 pt from trailing and bottom */
            [_durationBadgeView.trailingAnchor constraintEqualToAnchor:_thumbnailContainerView.trailingAnchor constant:-6.0],
            [_durationBadgeView.bottomAnchor constraintEqualToAnchor:_thumbnailContainerView.bottomAnchor constant:-6.0],
            [_durationBadgeLabel.topAnchor constraintEqualToAnchor:_durationBadgeView.topAnchor constant:2.0],
            [_durationBadgeLabel.bottomAnchor constraintEqualToAnchor:_durationBadgeView.bottomAnchor constant:-2.0],
            [_durationBadgeLabel.leadingAnchor constraintEqualToAnchor:_durationBadgeView.leadingAnchor constant:6.0],
            [_durationBadgeLabel.trailingAnchor constraintEqualToAnchor:_durationBadgeView.trailingAnchor constant:-6.0],

            /* Add to queue button: 6 pt from trailing and top */
            [_addToQueueButton.trailingAnchor constraintEqualToAnchor:_thumbnailWrapperView.trailingAnchor constant:-6.0],
            [_addToQueueButton.topAnchor constraintEqualToAnchor:_thumbnailWrapperView.topAnchor constant:6.0],

            /* Spinner: centered */
            [_openingSpinner.centerXAnchor constraintEqualToAnchor:_thumbnailContainerView.centerXAnchor],
            [_openingSpinner.centerYAnchor constraintEqualToAnchor:_thumbnailContainerView.centerYAnchor],

            /* Title: 10 pt below thumbnail */
            [_titleLabel.topAnchor constraintEqualToAnchor:_thumbnailWrapperView.bottomAnchor constant:10.0],
            [_titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_titleLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],

            /* Channel row: 4 pt below title */
            [_channelContainerView.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:4.0],
            [_channelContainerView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_channelContainerView.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor],

            [_channelLabel.topAnchor constraintEqualToAnchor:_channelContainerView.topAnchor],
            [_channelLabel.bottomAnchor constraintEqualToAnchor:_channelContainerView.bottomAnchor],
            [_channelLabel.leadingAnchor constraintEqualToAnchor:_channelContainerView.leadingAnchor],

            [_verifiedSealImageView.leadingAnchor constraintEqualToAnchor:_channelLabel.trailingAnchor constant:4.0],
            [_verifiedSealImageView.trailingAnchor constraintEqualToAnchor:_channelContainerView.trailingAnchor],
            [_verifiedSealImageView.centerYAnchor constraintEqualToAnchor:_channelLabel.centerYAnchor],
            [_verifiedSealImageView.widthAnchor constraintEqualToConstant:11.0],
            [_verifiedSealImageView.heightAnchor constraintEqualToConstant:11.0],

            /* Metadata: below channel (or title) */
            [_metadataLabel.topAnchor constraintEqualToAnchor:_channelContainerView.bottomAnchor constant:2.0],
            [_metadataLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_metadataLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],

            /* Skeletons */
            [_placeholderTitleBar1.topAnchor constraintEqualToAnchor:_thumbnailWrapperView.bottomAnchor constant:10.0],
            [_placeholderTitleBar1.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_placeholderTitleBar1.widthAnchor constraintEqualToAnchor:self.widthAnchor multiplier:0.9],
            [_placeholderTitleBar1.heightAnchor constraintEqualToConstant:14.0],

            [_placeholderTitleBar2.topAnchor constraintEqualToAnchor:_placeholderTitleBar1.bottomAnchor constant:6.0],
            [_placeholderTitleBar2.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_placeholderTitleBar2.widthAnchor constraintEqualToAnchor:self.widthAnchor multiplier:0.6],
            [_placeholderTitleBar2.heightAnchor constraintEqualToConstant:14.0],

            [_placeholderMetaBar.topAnchor constraintEqualToAnchor:_placeholderTitleBar2.bottomAnchor constant:8.0],
            [_placeholderMetaBar.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_placeholderMetaBar.widthAnchor constraintEqualToAnchor:self.widthAnchor multiplier:0.45],
            [_placeholderMetaBar.heightAnchor constraintEqualToConstant:12.0],
        ]];
    }
    return self;
}

- (void)layout
{
    [super layout];
    _durationBadgeView.layer.cornerRadius = _durationBadgeView.bounds.size.height / 2.0;
}

- (void)viewDidChangeEffectiveAppearance
{
    [super viewDidChangeEffectiveAppearance];
    _thumbnailContainerView.layer.backgroundColor = NSColor.quaternarySystemFillColor.CGColor;
    _placeholderTitleBar1.layer.backgroundColor = NSColor.quaternarySystemFillColor.CGColor;
    _placeholderTitleBar2.layer.backgroundColor = NSColor.quaternarySystemFillColor.CGColor;
    _placeholderMetaBar.layer.backgroundColor = NSColor.quaternarySystemFillColor.CGColor;
}

- (void)configureWithVideo:(nullable MacLCYouTubeVideo *)video showsChannel:(BOOL)showsChannel
{
    if (video == nil) {
        /* Skeleton placeholder card */
        _placeholderTitleBar1.hidden = NO;
        _placeholderTitleBar2.hidden = NO;
        _placeholderMetaBar.hidden = NO;

        _titleLabel.hidden = YES;
        _channelContainerView.hidden = YES;
        _metadataLabel.hidden = YES;
        _durationBadgeView.hidden = YES;
        _addToQueueButton.hidden = YES;
        _placeholderImageView.hidden = NO;
        _thumbnailImageView.hidden = YES;
        _thumbnailImageView.layer.contents = nil;
        return;
    }

    _placeholderTitleBar1.hidden = YES;
    _placeholderTitleBar2.hidden = YES;
    _placeholderMetaBar.hidden = YES;

    _titleLabel.hidden = NO;
    _titleLabel.stringValue = video.title ?: @"";

    _channelContainerView.hidden = !showsChannel;
    _channelLabel.stringValue = video.channelName ?: @"";
    _verifiedSealImageView.hidden = !video.isChannelVerified;

    _metadataLabel.hidden = NO;
    _metadataLabel.stringValue = [MacLCYouTubeFormat metadataLineForVideo:video now:[NSDate date]] ?: @"";

    _addToQueueButton.hidden = NO;

    /* Duration badge */
    if (video.isLive) {
        _durationBadgeView.hidden = NO;
        _durationBadgeView.layer.backgroundColor = NSColor.systemRedColor.CGColor;
        _durationBadgeLabel.font = [NSFont systemFontOfSize:11.0 weight:NSFontWeightBold];
        _durationBadgeLabel.stringValue = @"● LIVE";
    } else if (video.isUpcoming) {
        _durationBadgeView.hidden = NO;
        _durationBadgeView.layer.backgroundColor = [NSColor colorWithCalibratedWhite:0.0 alpha:0.78].CGColor;
        _durationBadgeLabel.font = [NSFont systemFontOfSize:11.0 weight:NSFontWeightBold];
        _durationBadgeLabel.stringValue = _NS("UPCOMING");
    } else if (video.duration > 0.0) {
        _durationBadgeView.hidden = NO;
        _durationBadgeView.layer.backgroundColor = [NSColor colorWithCalibratedWhite:0.0 alpha:0.78].CGColor;
        _durationBadgeLabel.font = [NSFont monospacedDigitSystemFontOfSize:12.0 weight:NSFontWeightSemibold];
        _durationBadgeLabel.stringValue = [MacLCYouTubeFormat durationString:video.duration] ?: @"";
    } else {
        _durationBadgeView.hidden = YES;
    }
}

- (void)setOpening:(BOOL)opening
{
    _isOpening = opening;
    if (opening) {
        _openingSpinner.hidden = NO;
        [_openingSpinner startAnimation:nil];
    } else {
        [_openingSpinner stopAnimation:nil];
        _openingSpinner.hidden = YES;
    }
}

- (void)addToQueueClicked:(id)sender
{
    if (self.item != nil && self.item.video != nil && self.item.enqueueHandler != nil) {
        self.item.enqueueHandler(self.item.video);
    }
}

- (void)updateTrackingAreas
{
    [super updateTrackingAreas];
    if (_trackingArea != nil) {
        [self removeTrackingArea:_trackingArea];
    }
    _trackingArea = [[NSTrackingArea alloc] initWithRect:self.bounds
                                                 options:(NSTrackingActiveInKeyWindow |
                                                          NSTrackingMouseEnteredAndExited |
                                                          NSTrackingInVisibleRect)
                                                   owner:self
                                                userInfo:nil];
    [self addTrackingArea:_trackingArea];
}

- (void)resetCursorRects
{
    [super resetCursorRects];
    if (_isHovered && !_isOpening && self.item.video != nil) {
        [self addCursorRect:self.bounds cursor:NSCursor.pointingHandCursor];
    }
}

- (void)mouseEntered:(NSEvent *)event
{
    _isHovered = YES;
    [self updateHoverState:YES animated:YES];
    [self.window invalidateCursorRectsForView:self];
}

- (void)mouseExited:(NSEvent *)event
{
    _isHovered = NO;
    [self updateHoverState:NO animated:YES];
    [self.window invalidateCursorRectsForView:self];
}

- (void)updateHoverState:(BOOL)hovered animated:(BOOL)animated
{
    if (self.item.video == nil) {
        _addToQueueButton.alphaValue = 0.0;
        _thumbnailWrapperView.layer.transform = CATransform3DIdentity;
        return;
    }

    const CATransform3D targetTransform = (hovered && !MacLCDesign.reducedMotion)
        ? CATransform3DMakeScale(1.03, 1.03, 1.0)
        : CATransform3DIdentity;
    const CGFloat targetAlpha = hovered ? 1.0 : 0.0;

    CALayer * const layer = _thumbnailWrapperView.layer;
    if (layer == nil) {
        return;
    }

    if (!animated || MacLCDesign.reducedMotion) {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        [layer removeAnimationForKey:@"hoverTransform"];
        layer.transform = targetTransform;
        _addToQueueButton.alphaValue = targetAlpha;
        [CATransaction commit];
        return;
    }

    /* Spring motion */
    CALayer * const presentation = layer.presentationLayer ?: layer;
    CATransform3D const fromTransform = presentation.transform;
    layer.transform = targetTransform;

    CASpringAnimation *anim = [MacLCDesign emphasizedSpringForKeyPath:@"transform"];
    anim.fromValue = [NSValue valueWithCATransform3D:fromTransform];
    anim.toValue = [NSValue valueWithCATransform3D:targetTransform];
    [layer addAnimation:anim forKey:@"hoverTransform"];

    [NSAnimationContext runAnimationGroup:^(NSAnimationContext * _Nonnull context) {
        context.duration = MacLCDesign.motionQuickDuration;
        self->_addToQueueButton.animator.alphaValue = targetAlpha;
    }];
}

- (void)mouseUp:(NSEvent *)event
{
    if (_isOpening || self.item.video == nil) {
        return;
    }
    const NSPoint location = [self convertPoint:event.locationInWindow fromView:nil];
    if (NSPointInRect(location, self.bounds)) {
        if (self.item.activationHandler != nil) {
            self.item.activationHandler(self.item.video);
        }
    }
}

- (void)keyDown:(NSEvent *)event
{
    if (self.item.video != nil && !_isOpening) {
        if (event.keyCode == 36 || event.keyCode == 76 || event.keyCode == 49) { // Return / Enter / Space
            if (self.item.activationHandler != nil) {
                self.item.activationHandler(self.item.video);
                return;
            }
        }
    }
    [super keyDown:event];
}

- (NSMenu *)menuForEvent:(NSEvent *)event
{
    MacLCYouTubeVideo * const video = self.item.video;
    if (video == nil) {
        return nil;
    }

    NSMenu * const menu = [[NSMenu alloc] initWithTitle:@"YouTube Video"];
    NSMenuItem *playItem = [[NSMenuItem alloc] initWithTitle:_NS("Play") action:@selector(contextPlay:) keyEquivalent:@""];
    playItem.target = self;
    [menu addItem:playItem];

    NSMenuItem *enqueueItem = [[NSMenuItem alloc] initWithTitle:_NS("Add to Queue") action:@selector(contextEnqueue:) keyEquivalent:@""];
    enqueueItem.target = self;
    [menu addItem:enqueueItem];

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *detailsItem = [[NSMenuItem alloc] initWithTitle:_NS("Show Details") action:@selector(contextDetails:) keyEquivalent:@""];
    detailsItem.target = self;
    [menu addItem:detailsItem];

    if (video.channelURL != nil) {
        NSMenuItem *channelItem = [[NSMenuItem alloc] initWithTitle:_NS("Go to Channel") action:@selector(contextChannel:) keyEquivalent:@""];
        channelItem.target = self;
        [menu addItem:channelItem];
    }

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *copyItem = [[NSMenuItem alloc] initWithTitle:_NS("Copy Link") action:@selector(contextCopyLink:) keyEquivalent:@""];
    copyItem.target = self;
    [menu addItem:copyItem];

    NSMenuItem *browserItem = [[NSMenuItem alloc] initWithTitle:_NS("Open in Browser") action:@selector(contextOpenInBrowser:) keyEquivalent:@""];
    browserItem.target = self;
    [menu addItem:browserItem];

    return menu;
}

- (void)contextPlay:(id)sender
{
    if (self.item.video != nil && self.item.activationHandler != nil) {
        self.item.activationHandler(self.item.video);
    }
}

- (void)contextEnqueue:(id)sender
{
    if (self.item.video != nil && self.item.enqueueHandler != nil) {
        self.item.enqueueHandler(self.item.video);
    }
}

- (void)contextDetails:(id)sender
{
    if (self.item.video != nil && self.item.detailsHandler != nil) {
        self.item.detailsHandler(self.item.video);
    }
}

- (void)contextChannel:(id)sender
{
    if (self.item.video != nil && self.item.channelHandler != nil) {
        self.item.channelHandler(self.item.video);
    }
}

- (void)contextCopyLink:(id)sender
{
    if (self.item.video != nil) {
        [MacLCYouTubeActions copyLinkOfVideo:self.item.video];
    }
}

- (void)contextOpenInBrowser:(id)sender
{
    if (self.item.video != nil && self.item.video.watchURL != nil) {
        [MacLCYouTubeActions openInBrowser:self.item.video.watchURL];
    }
}

#pragma mark - Accessibility

- (BOOL)isAccessibilityElement
{
    return YES;
}

- (NSAccessibilityRole)accessibilityRole
{
    return NSAccessibilityButtonRole;
}

- (nullable NSString *)accessibilityLabel
{
    MacLCYouTubeVideo * const video = self.item.video;
    if (video == nil) {
        return _NS("Loading Video");
    }
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    if (video.title.length > 0) {
        [parts addObject:video.title];
    }
    if (video.channelName.length > 0) {
        [parts addObject:video.channelName];
    }
    if (video.isLive) {
        [parts addObject:_NS("Live")];
    } else if (video.duration > 0.0) {
        NSString *dur = [MacLCYouTubeFormat durationString:video.duration];
        if (dur.length > 0) [parts addObject:dur];
    }
    NSString *meta = [MacLCYouTubeFormat metadataLineForVideo:video now:[NSDate date]];
    if (meta.length > 0) {
        [parts addObject:meta];
    }
    return [parts componentsJoinedByString:@", "];
}

- (BOOL)accessibilityPerformPress
{
    if (self.item.video != nil && !_isOpening && self.item.activationHandler != nil) {
        self.item.activationHandler(self.item.video);
        return YES;
    }
    return NO;
}

- (nullable NSArray<NSAccessibilityCustomAction *> *)accessibilityCustomActions
{
    MacLCYouTubeVideo * const video = self.item.video;
    if (video == nil) {
        return @[];
    }
    NSMutableArray<NSAccessibilityCustomAction *> *actions = [NSMutableArray array];
    __weak typeof(self) weakSelf = self;

    [actions addObject:[[NSAccessibilityCustomAction alloc] initWithName:_NS("Play")
                                                                 handler:^BOOL{
        [weakSelf contextPlay:nil];
        return YES;
    }]];
    [actions addObject:[[NSAccessibilityCustomAction alloc] initWithName:_NS("Add to Queue")
                                                                 handler:^BOOL{
        [weakSelf contextEnqueue:nil];
        return YES;
    }]];
    [actions addObject:[[NSAccessibilityCustomAction alloc] initWithName:_NS("Show Details")
                                                                 handler:^BOOL{
        [weakSelf contextDetails:nil];
        return YES;
    }]];
    if (video.channelURL != nil) {
        [actions addObject:[[NSAccessibilityCustomAction alloc] initWithName:_NS("Go to Channel")
                                                                     handler:^BOOL{
            [weakSelf contextChannel:nil];
            return YES;
        }]];
    }
    [actions addObject:[[NSAccessibilityCustomAction alloc] initWithName:_NS("Copy Link")
                                                                 handler:^BOOL{
        [weakSelf contextCopyLink:nil];
        return YES;
    }]];
    [actions addObject:[[NSAccessibilityCustomAction alloc] initWithName:_NS("Open in Browser")
                                                                 handler:^BOOL{
        [weakSelf contextOpenInBrowser:nil];
        return YES;
    }]];

    return actions;
}

@end

#pragma mark - MacLCYouTubeVideoItem Implementation

@implementation MacLCYouTubeVideoItem
{
    MacLCWatchImageRequest *_imageRequest;
}

- (instancetype)initWithNibName:(nullable NSNibName)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _showsChannel = YES;
    }
    return self;
}

- (void)loadView
{
    MacLCYouTubeVideoCardView *cardView = [[MacLCYouTubeVideoCardView alloc] initWithFrame:NSMakeRect(0, 0, 320, 260)];
    cardView.item = self;
    self.view = cardView;
}

- (MacLCYouTubeVideoCardView *)cardView
{
    return (MacLCYouTubeVideoCardView *)self.view;
}

- (void)dealloc
{
    [_imageRequest cancel];
}

- (void)configureAsPlaceholder
{
    [_imageRequest cancel];
    _imageRequest = nil;
    _video = nil;
    [self.cardView configureWithVideo:nil showsChannel:_showsChannel];
    [self.cardView updateHoverState:NO animated:NO];
    [self.cardView setOpening:NO];
}

- (void)prepareForReuse
{
    [super prepareForReuse];
    [self configureAsPlaceholder];
}

- (void)configureWithVideo:(MacLCYouTubeVideo *)video
{
    _video = video;
    [_imageRequest cancel];
    _imageRequest = nil;

    MacLCYouTubeVideoCardView * const cv = self.cardView;
    [cv configureWithVideo:video showsChannel:_showsChannel];

    if (video == nil || video.thumbnailURL == nil) {
        cv.thumbnailImageView.layer.contents = nil;
        cv.thumbnailImageView.hidden = YES;
        cv.placeholderImageView.hidden = NO;
        return;
    }

    const CGFloat width = cv.bounds.size.width > 0.0 ? cv.bounds.size.width : 320.0;
    const NSSize pointSize = NSMakeSize(width, width * 9.0 / 16.0);
    const CGFloat scale = BackingScaleForView(self.view);

    __weak typeof(cv) weakCv = cv;
    MacLCWatchImageRequest *req = nil;
    NSImage * const cached = [[MacLCWatchImageCache sharedCache] imageForURL:video.thumbnailURL
                                                                  pointSize:pointSize
                                                                      scale:scale
                                                                    request:&req
                                                                 completion:^(NSImage * _Nullable image) {
        if (image != nil && weakCv != nil) {
            weakCv.thumbnailImageView.layer.contents = image;
            weakCv.thumbnailImageView.hidden = NO;
            weakCv.placeholderImageView.hidden = YES;
        }
    }];
    _imageRequest = req;

    if (cached != nil) {
        cv.thumbnailImageView.layer.contents = cached;
        cv.thumbnailImageView.hidden = NO;
        cv.placeholderImageView.hidden = YES;
    } else {
        cv.thumbnailImageView.layer.contents = nil;
        cv.thumbnailImageView.hidden = YES;
        cv.placeholderImageView.hidden = NO;
    }
}

- (void)setShowsChannel:(BOOL)showsChannel
{
    _showsChannel = showsChannel;
    [self.cardView configureWithVideo:_video showsChannel:showsChannel];
}

- (void)setOpening:(BOOL)opening
{
    [self.cardView setOpening:opening];
}

+ (CGFloat)heightForWidth:(CGFloat)width
{
    /* thumbnail 16:9 + 10 + two title lines (38) + 4 + two metadata/channel lines (32) */
    return ceil(width * 9.0 / 16.0 + 84.0);
}

@end

#pragma mark - Search Result Row View

@interface MacLCYouTubeResultRowView : NSView

@property (nonatomic, weak, nullable) MacLCYouTubeResultRowItem *item;
@property (nonatomic, strong) NSView *leadingWrapperView;
@property (nonatomic, strong) NSView *leadingContainerView;
@property (nonatomic, strong) NSImageView *placeholderImageView;
@property (nonatomic, strong) NSView *thumbnailImageView;
@property (nonatomic, strong) NSView *durationBadgeView;
@property (nonatomic, strong) NSTextField *durationBadgeLabel;
@property (nonatomic, strong) NSButton *addToQueueButton;
@property (nonatomic, strong) NSProgressIndicator *openingSpinner;

/* Channel avatar circular view */
@property (nonatomic, strong) NSImageView *channelAvatarView;

/* Playlist trailing overlay bar */
@property (nonatomic, strong) NSView *playlistOverlayBar;
@property (nonatomic, strong) NSImageView *playlistOverlayIcon;
@property (nonatomic, strong) NSTextField *playlistOverlayCountLabel;

/* Trailing content */
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSTextField *metadataLabel;
@property (nonatomic, strong) NSView *channelContainerView;
@property (nonatomic, strong) NSTextField *channelLabel;
@property (nonatomic, strong) NSImageView *verifiedSealImageView;
@property (nonatomic, strong) NSTextField *descriptionLabel;

/* Loading skeletons */
@property (nonatomic, strong) NSView *skeletonLeadingBox;
@property (nonatomic, strong) NSView *skeletonTitleBar;
@property (nonatomic, strong) NSView *skeletonMetaBar;

@property (nonatomic) BOOL isHovered;
@property (nonatomic) BOOL isOpening;
@property (nonatomic, strong, nullable) NSTrackingArea *trackingArea;

- (void)configureWithResult:(nullable MacLCYouTubeResult *)result;
- (void)setOpening:(BOOL)opening;
- (void)updateHoverState:(BOOL)hovered animated:(BOOL)animated;

@end

@implementation MacLCYouTubeResultRowView

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;

        /* Leading wrapper (320 × 180) */
        _leadingWrapperView = [[NSView alloc] initWithFrame:NSZeroRect];
        _leadingWrapperView.translatesAutoresizingMaskIntoConstraints = NO;
        _leadingWrapperView.wantsLayer = YES;
        _leadingWrapperView.layer.masksToBounds = NO;
        [self addSubview:_leadingWrapperView];

        _leadingContainerView = [[NSView alloc] initWithFrame:NSZeroRect];
        _leadingContainerView.translatesAutoresizingMaskIntoConstraints = NO;
        _leadingContainerView.wantsLayer = YES;
        _leadingContainerView.layer.masksToBounds = YES;
        _leadingContainerView.layer.cornerRadius = 12.0;
        _leadingContainerView.layer.cornerCurve = kCACornerCurveContinuous;
        _leadingContainerView.layer.backgroundColor = NSColor.quaternarySystemFillColor.CGColor;
        [_leadingWrapperView addSubview:_leadingContainerView];

        _placeholderImageView = [[NSImageView alloc] initWithFrame:NSZeroRect];
        _placeholderImageView.translatesAutoresizingMaskIntoConstraints = NO;
        _placeholderImageView.imageScaling = NSImageScaleProportionallyUpOrDown;
        _placeholderImageView.contentTintColor = NSColor.tertiaryLabelColor;
        NSImageSymbolConfiguration *placeholderConfig =
            [NSImageSymbolConfiguration configurationWithPointSize:40.0 weight:NSFontWeightLight];
        NSImage *placeholder = [NSImage imageWithSystemSymbolName:@"play.rectangle" accessibilityDescription:nil];
        if (placeholder != nil) {
            placeholder = [placeholder imageWithSymbolConfiguration:placeholderConfig];
        }
        _placeholderImageView.image = placeholder;
        [_leadingContainerView addSubview:_placeholderImageView];

        _thumbnailImageView = [[NSView alloc] initWithFrame:NSZeroRect];
        _thumbnailImageView.translatesAutoresizingMaskIntoConstraints = NO;
        _thumbnailImageView.wantsLayer = YES;
        _thumbnailImageView.layer.contentsGravity = kCAGravityResizeAspectFill;
        _thumbnailImageView.layer.masksToBounds = YES;
        _thumbnailImageView.hidden = YES;
        [_leadingContainerView addSubview:_thumbnailImageView];

        /* Duration badge */
        _durationBadgeView = [[NSView alloc] initWithFrame:NSZeroRect];
        _durationBadgeView.translatesAutoresizingMaskIntoConstraints = NO;
        _durationBadgeView.wantsLayer = YES;
        _durationBadgeView.layer.masksToBounds = YES;
        _durationBadgeView.layer.backgroundColor = [NSColor colorWithCalibratedWhite:0.0 alpha:0.78].CGColor;
        [_leadingContainerView addSubview:_durationBadgeView];

        _durationBadgeLabel = [NSTextField labelWithString:@""];
        _durationBadgeLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _durationBadgeLabel.textColor = NSColor.whiteColor;
        _durationBadgeLabel.font = [NSFont monospacedDigitSystemFontOfSize:12.0 weight:NSFontWeightSemibold];
        _durationBadgeLabel.alignment = NSTextAlignmentCenter;
        _durationBadgeLabel.selectable = NO;
        [_durationBadgeView addSubview:_durationBadgeLabel];

        /* Add to queue glass button */
        _addToQueueButton = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"text.badge.plus"
                                                                accessibilityDescription:_NS("Add to Queue")]
                                               target:self
                                               action:@selector(addToQueueClicked:)];
        _addToQueueButton.toolTip = _NS("Add to Queue");
        _addToQueueButton.accessibilityLabel = _NS("Add to Queue");
        _addToQueueButton.alphaValue = 0.0;
        StyleGlassCircleButton(_addToQueueButton, 28.0);
        [_leadingWrapperView addSubview:_addToQueueButton];

        /* Opening spinner */
        _openingSpinner = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
        _openingSpinner.translatesAutoresizingMaskIntoConstraints = NO;
        _openingSpinner.style = NSProgressIndicatorStyleSpinning;
        _openingSpinner.controlSize = NSControlSizeSmall;
        _openingSpinner.displayedWhenStopped = NO;
        _openingSpinner.hidden = YES;
        [_leadingContainerView addSubview:_openingSpinner];

        /* Channel 136 pt avatar circle */
        _channelAvatarView = [[NSImageView alloc] initWithFrame:NSZeroRect];
        _channelAvatarView.translatesAutoresizingMaskIntoConstraints = NO;
        _channelAvatarView.wantsLayer = YES;
        _channelAvatarView.layer.masksToBounds = YES;
        _channelAvatarView.layer.cornerRadius = 68.0;
        _channelAvatarView.layer.backgroundColor = NSColor.quaternarySystemFillColor.CGColor;
        _channelAvatarView.imageScaling = NSImageScaleProportionallyUpOrDown;
        _channelAvatarView.hidden = YES;
        [_leadingWrapperView addSubview:_channelAvatarView];

        /* Playlist trailing third overlay */
        _playlistOverlayBar = [[NSView alloc] initWithFrame:NSZeroRect];
        _playlistOverlayBar.translatesAutoresizingMaskIntoConstraints = NO;
        _playlistOverlayBar.wantsLayer = YES;
        _playlistOverlayBar.layer.backgroundColor = [NSColor colorWithCalibratedWhite:0.0 alpha:0.70].CGColor;
        _playlistOverlayBar.hidden = YES;
        [_leadingContainerView addSubview:_playlistOverlayBar];

        _playlistOverlayIcon = [[NSImageView alloc] initWithFrame:NSZeroRect];
        _playlistOverlayIcon.translatesAutoresizingMaskIntoConstraints = NO;
        _playlistOverlayIcon.imageScaling = NSImageScaleProportionallyUpOrDown;
        _playlistOverlayIcon.contentTintColor = NSColor.whiteColor;
        NSImageSymbolConfiguration *listConfig =
            [NSImageSymbolConfiguration configurationWithPointSize:20.0 weight:NSFontWeightMedium];
        NSImage *listImg = [NSImage imageWithSystemSymbolName:@"list.and.film" accessibilityDescription:nil];
        if (listImg != nil) {
            listImg = [listImg imageWithSymbolConfiguration:listConfig];
        }
        _playlistOverlayIcon.image = listImg;
        [_playlistOverlayBar addSubview:_playlistOverlayIcon];

        _playlistOverlayCountLabel = [NSTextField labelWithString:@""];
        _playlistOverlayCountLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _playlistOverlayCountLabel.font = [NSFont systemFontOfSize:12.0 weight:NSFontWeightSemibold];
        _playlistOverlayCountLabel.textColor = NSColor.whiteColor;
        _playlistOverlayCountLabel.alignment = NSTextAlignmentCenter;
        _playlistOverlayCountLabel.selectable = NO;
        [_playlistOverlayBar addSubview:_playlistOverlayCountLabel];

        /* Trailing texts */
        _titleLabel = [NSTextField labelWithString:@""];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _titleLabel.font = [NSFont systemFontOfSize:17.0 weight:NSFontWeightSemibold];
        _titleLabel.textColor = NSColor.labelColor;
        _titleLabel.lineBreakMode = NSLineBreakByWordWrapping;
        _titleLabel.cell.truncatesLastVisibleLine = YES;
        _titleLabel.maximumNumberOfLines = 2;
        _titleLabel.selectable = NO;
        [self addSubview:_titleLabel];

        _metadataLabel = [NSTextField labelWithString:@""];
        _metadataLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _metadataLabel.font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightRegular];
        _metadataLabel.textColor = NSColor.secondaryLabelColor;
        _metadataLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _metadataLabel.selectable = NO;
        [self addSubview:_metadataLabel];

        _channelContainerView = [[NSView alloc] initWithFrame:NSZeroRect];
        _channelContainerView.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_channelContainerView];

        _channelLabel = [NSTextField labelWithString:@""];
        _channelLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _channelLabel.font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightRegular];
        _channelLabel.textColor = NSColor.secondaryLabelColor;
        _channelLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _channelLabel.selectable = NO;
        [_channelContainerView addSubview:_channelLabel];

        _verifiedSealImageView = [[NSImageView alloc] initWithFrame:NSZeroRect];
        _verifiedSealImageView.translatesAutoresizingMaskIntoConstraints = NO;
        _verifiedSealImageView.imageScaling = NSImageScaleProportionallyUpOrDown;
        _verifiedSealImageView.contentTintColor = NSColor.secondaryLabelColor;
        NSImage *seal = [NSImage imageWithSystemSymbolName:@"checkmark.seal.fill" accessibilityDescription:_NS("Verified")];
        if (seal != nil) {
            seal = [seal imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPointSize:11.0 weight:NSFontWeightMedium]];
        }
        _verifiedSealImageView.image = seal;
        _verifiedSealImageView.hidden = YES;
        [_channelContainerView addSubview:_verifiedSealImageView];

        _descriptionLabel = [NSTextField labelWithString:@""];
        _descriptionLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _descriptionLabel.font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightRegular];
        _descriptionLabel.textColor = NSColor.secondaryLabelColor;
        _descriptionLabel.lineBreakMode = NSLineBreakByWordWrapping;
        _descriptionLabel.cell.truncatesLastVisibleLine = YES;
        _descriptionLabel.maximumNumberOfLines = 2;
        _descriptionLabel.selectable = NO;
        _descriptionLabel.hidden = YES;
        [self addSubview:_descriptionLabel];

        /* Skeletons */
        _skeletonLeadingBox = [[NSView alloc] initWithFrame:NSZeroRect];
        _skeletonLeadingBox.translatesAutoresizingMaskIntoConstraints = NO;
        _skeletonLeadingBox.wantsLayer = YES;
        _skeletonLeadingBox.layer.cornerRadius = 12.0;
        _skeletonLeadingBox.layer.backgroundColor = NSColor.quaternarySystemFillColor.CGColor;
        _skeletonLeadingBox.hidden = YES;
        [self addSubview:_skeletonLeadingBox];

        _skeletonTitleBar = [[NSView alloc] initWithFrame:NSZeroRect];
        _skeletonTitleBar.translatesAutoresizingMaskIntoConstraints = NO;
        _skeletonTitleBar.wantsLayer = YES;
        _skeletonTitleBar.layer.cornerRadius = 4.0;
        _skeletonTitleBar.layer.backgroundColor = NSColor.quaternarySystemFillColor.CGColor;
        _skeletonTitleBar.hidden = YES;
        [self addSubview:_skeletonTitleBar];

        _skeletonMetaBar = [[NSView alloc] initWithFrame:NSZeroRect];
        _skeletonMetaBar.translatesAutoresizingMaskIntoConstraints = NO;
        _skeletonMetaBar.wantsLayer = YES;
        _skeletonMetaBar.layer.cornerRadius = 4.0;
        _skeletonMetaBar.layer.backgroundColor = NSColor.quaternarySystemFillColor.CGColor;
        _skeletonMetaBar.hidden = YES;
        [self addSubview:_skeletonMetaBar];

        /* Constraints */
        [NSLayoutConstraint activateConstraints:@[
            [_leadingWrapperView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_leadingWrapperView.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_leadingWrapperView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            [_leadingWrapperView.widthAnchor constraintEqualToConstant:320.0],

            [_leadingContainerView.topAnchor constraintEqualToAnchor:_leadingWrapperView.topAnchor],
            [_leadingContainerView.bottomAnchor constraintEqualToAnchor:_leadingWrapperView.bottomAnchor],
            [_leadingContainerView.leadingAnchor constraintEqualToAnchor:_leadingWrapperView.leadingAnchor],
            [_leadingContainerView.trailingAnchor constraintEqualToAnchor:_leadingWrapperView.trailingAnchor],

            [_placeholderImageView.centerXAnchor constraintEqualToAnchor:_leadingContainerView.centerXAnchor],
            [_placeholderImageView.centerYAnchor constraintEqualToAnchor:_leadingContainerView.centerYAnchor],
            [_placeholderImageView.widthAnchor constraintEqualToConstant:48.0],
            [_placeholderImageView.heightAnchor constraintEqualToConstant:48.0],

            [_thumbnailImageView.topAnchor constraintEqualToAnchor:_leadingContainerView.topAnchor],
            [_thumbnailImageView.bottomAnchor constraintEqualToAnchor:_leadingContainerView.bottomAnchor],
            [_thumbnailImageView.leadingAnchor constraintEqualToAnchor:_leadingContainerView.leadingAnchor],
            [_thumbnailImageView.trailingAnchor constraintEqualToAnchor:_leadingContainerView.trailingAnchor],

            [_durationBadgeView.trailingAnchor constraintEqualToAnchor:_leadingContainerView.trailingAnchor constant:-6.0],
            [_durationBadgeView.bottomAnchor constraintEqualToAnchor:_leadingContainerView.bottomAnchor constant:-6.0],
            [_durationBadgeLabel.topAnchor constraintEqualToAnchor:_durationBadgeView.topAnchor constant:2.0],
            [_durationBadgeLabel.bottomAnchor constraintEqualToAnchor:_durationBadgeView.bottomAnchor constant:-2.0],
            [_durationBadgeLabel.leadingAnchor constraintEqualToAnchor:_durationBadgeView.leadingAnchor constant:6.0],
            [_durationBadgeLabel.trailingAnchor constraintEqualToAnchor:_durationBadgeView.trailingAnchor constant:-6.0],

            [_addToQueueButton.trailingAnchor constraintEqualToAnchor:_leadingWrapperView.trailingAnchor constant:-6.0],
            [_addToQueueButton.topAnchor constraintEqualToAnchor:_leadingWrapperView.topAnchor constant:6.0],

            [_openingSpinner.centerXAnchor constraintEqualToAnchor:_leadingContainerView.centerXAnchor],
            [_openingSpinner.centerYAnchor constraintEqualToAnchor:_leadingContainerView.centerYAnchor],

            /* Avatar centered in 320 area */
            [_channelAvatarView.centerXAnchor constraintEqualToAnchor:_leadingWrapperView.centerXAnchor],
            [_channelAvatarView.centerYAnchor constraintEqualToAnchor:_leadingWrapperView.centerYAnchor],
            [_channelAvatarView.widthAnchor constraintEqualToConstant:136.0],
            [_channelAvatarView.heightAnchor constraintEqualToConstant:136.0],

            /* Playlist trailing overlay bar (1/3 of width) */
            [_playlistOverlayBar.topAnchor constraintEqualToAnchor:_leadingContainerView.topAnchor],
            [_playlistOverlayBar.bottomAnchor constraintEqualToAnchor:_leadingContainerView.bottomAnchor],
            [_playlistOverlayBar.trailingAnchor constraintEqualToAnchor:_leadingContainerView.trailingAnchor],
            [_playlistOverlayBar.widthAnchor constraintEqualToAnchor:_leadingContainerView.widthAnchor multiplier:0.33],

            [_playlistOverlayIcon.centerXAnchor constraintEqualToAnchor:_playlistOverlayBar.centerXAnchor],
            [_playlistOverlayIcon.centerYAnchor constraintEqualToAnchor:_playlistOverlayBar.centerYAnchor constant:-12.0],
            [_playlistOverlayIcon.widthAnchor constraintEqualToConstant:24.0],
            [_playlistOverlayIcon.heightAnchor constraintEqualToConstant:24.0],

            [_playlistOverlayCountLabel.topAnchor constraintEqualToAnchor:_playlistOverlayIcon.bottomAnchor constant:4.0],
            [_playlistOverlayCountLabel.leadingAnchor constraintEqualToAnchor:_playlistOverlayBar.leadingAnchor constant:4.0],
            [_playlistOverlayCountLabel.trailingAnchor constraintEqualToAnchor:_playlistOverlayBar.trailingAnchor constant:-4.0],

            /* Trailing content: 16 pt from leading wrapper */
            [_titleLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:4.0],
            [_titleLabel.leadingAnchor constraintEqualToAnchor:_leadingWrapperView.trailingAnchor constant:16.0],
            [_titleLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],

            [_metadataLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:6.0],
            [_metadataLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
            [_metadataLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],

            [_channelContainerView.topAnchor constraintEqualToAnchor:_metadataLabel.bottomAnchor constant:6.0],
            [_channelContainerView.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
            [_channelContainerView.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor],

            [_channelLabel.topAnchor constraintEqualToAnchor:_channelContainerView.topAnchor],
            [_channelLabel.bottomAnchor constraintEqualToAnchor:_channelContainerView.bottomAnchor],
            [_channelLabel.leadingAnchor constraintEqualToAnchor:_channelContainerView.leadingAnchor],

            [_verifiedSealImageView.leadingAnchor constraintEqualToAnchor:_channelLabel.trailingAnchor constant:4.0],
            [_verifiedSealImageView.trailingAnchor constraintEqualToAnchor:_channelContainerView.trailingAnchor],
            [_verifiedSealImageView.centerYAnchor constraintEqualToAnchor:_channelLabel.centerYAnchor],
            [_verifiedSealImageView.widthAnchor constraintEqualToConstant:11.0],
            [_verifiedSealImageView.heightAnchor constraintEqualToConstant:11.0],

            [_descriptionLabel.topAnchor constraintEqualToAnchor:_channelContainerView.bottomAnchor constant:8.0],
            [_descriptionLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
            [_descriptionLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],

            /* Skeletons */
            [_skeletonLeadingBox.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_skeletonLeadingBox.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_skeletonLeadingBox.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            [_skeletonLeadingBox.widthAnchor constraintEqualToConstant:320.0],

            [_skeletonTitleBar.topAnchor constraintEqualToAnchor:self.topAnchor constant:8.0],
            [_skeletonTitleBar.leadingAnchor constraintEqualToAnchor:_skeletonLeadingBox.trailingAnchor constant:16.0],
            [_skeletonTitleBar.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-40.0],
            [_skeletonTitleBar.heightAnchor constraintEqualToConstant:18.0],

            [_skeletonMetaBar.topAnchor constraintEqualToAnchor:_skeletonTitleBar.bottomAnchor constant:10.0],
            [_skeletonMetaBar.leadingAnchor constraintEqualToAnchor:_skeletonTitleBar.leadingAnchor],
            [_skeletonMetaBar.widthAnchor constraintEqualToConstant:240.0],
            [_skeletonMetaBar.heightAnchor constraintEqualToConstant:14.0],
        ]];
    }
    return self;
}

- (void)layout
{
    [super layout];
    _durationBadgeView.layer.cornerRadius = _durationBadgeView.bounds.size.height / 2.0;
}

- (void)viewDidChangeEffectiveAppearance
{
    [super viewDidChangeEffectiveAppearance];
    _leadingContainerView.layer.backgroundColor = NSColor.quaternarySystemFillColor.CGColor;
    _channelAvatarView.layer.backgroundColor = NSColor.quaternarySystemFillColor.CGColor;
    _skeletonLeadingBox.layer.backgroundColor = NSColor.quaternarySystemFillColor.CGColor;
    _skeletonTitleBar.layer.backgroundColor = NSColor.quaternarySystemFillColor.CGColor;
    _skeletonMetaBar.layer.backgroundColor = NSColor.quaternarySystemFillColor.CGColor;
}

- (void)configureWithResult:(nullable MacLCYouTubeResult *)result
{
    if (result == nil) {
        _skeletonLeadingBox.hidden = NO;
        _skeletonTitleBar.hidden = NO;
        _skeletonMetaBar.hidden = NO;

        _leadingWrapperView.hidden = YES;
        _titleLabel.hidden = YES;
        _metadataLabel.hidden = YES;
        _channelContainerView.hidden = YES;
        _descriptionLabel.hidden = YES;
        return;
    }

    _skeletonLeadingBox.hidden = YES;
    _skeletonTitleBar.hidden = YES;
    _skeletonMetaBar.hidden = YES;
    _leadingWrapperView.hidden = NO;
    _titleLabel.hidden = NO;

    switch (result.kind) {
        case MacLCYouTubeResultKindVideo: {
            MacLCYouTubeVideo * const v = result.video;
            _leadingContainerView.hidden = NO;
            _channelAvatarView.hidden = YES;
            _playlistOverlayBar.hidden = YES;
            _descriptionLabel.hidden = YES;
            _addToQueueButton.hidden = NO;

            _titleLabel.stringValue = v.title ?: @"";
            _metadataLabel.hidden = NO;
            _metadataLabel.stringValue = [MacLCYouTubeFormat metadataLineForVideo:v now:[NSDate date]] ?: @"";

            _channelContainerView.hidden = NO;
            _channelLabel.stringValue = v.channelName ?: @"";
            _verifiedSealImageView.hidden = !v.isChannelVerified;

            if (v.isLive) {
                _durationBadgeView.hidden = NO;
                _durationBadgeView.layer.backgroundColor = NSColor.systemRedColor.CGColor;
                _durationBadgeLabel.font = [NSFont systemFontOfSize:11.0 weight:NSFontWeightBold];
                _durationBadgeLabel.stringValue = @"● LIVE";
            } else if (v.isUpcoming) {
                _durationBadgeView.hidden = NO;
                _durationBadgeView.layer.backgroundColor = [NSColor colorWithCalibratedWhite:0.0 alpha:0.78].CGColor;
                _durationBadgeLabel.font = [NSFont systemFontOfSize:11.0 weight:NSFontWeightBold];
                _durationBadgeLabel.stringValue = _NS("UPCOMING");
            } else if (v.duration > 0.0) {
                _durationBadgeView.hidden = NO;
                _durationBadgeView.layer.backgroundColor = [NSColor colorWithCalibratedWhite:0.0 alpha:0.78].CGColor;
                _durationBadgeLabel.font = [NSFont monospacedDigitSystemFontOfSize:12.0 weight:NSFontWeightSemibold];
                _durationBadgeLabel.stringValue = [MacLCYouTubeFormat durationString:v.duration] ?: @"";
            } else {
                _durationBadgeView.hidden = YES;
            }
            break;
        }
        case MacLCYouTubeResultKindChannel: {
            MacLCYouTubeChannel * const c = result.channel;
            _leadingContainerView.hidden = YES;
            _channelAvatarView.hidden = NO;
            _playlistOverlayBar.hidden = YES;
            _durationBadgeView.hidden = YES;
            _addToQueueButton.hidden = YES;

            _titleLabel.stringValue = c.name ?: @"";
            _metadataLabel.hidden = NO;
            NSMutableArray *parts = [NSMutableArray array];
            if (c.handle.length > 0) [parts addObject:c.handle];
            if (c.subscriberCount >= 0) [parts addObject:[MacLCYouTubeFormat subscriberCountString:c.subscriberCount]];
            _metadataLabel.stringValue = [parts componentsJoinedByString:@" · "];

            _channelContainerView.hidden = YES;

            _descriptionLabel.hidden = (c.descriptionText.length == 0);
            _descriptionLabel.stringValue = c.descriptionText ?: @"";
            break;
        }
        case MacLCYouTubeResultKindPlaylist: {
            MacLCYouTubePlaylist * const p = result.playlist;
            _leadingContainerView.hidden = NO;
            _channelAvatarView.hidden = YES;
            _playlistOverlayBar.hidden = NO;
            _durationBadgeView.hidden = YES;
            _addToQueueButton.hidden = YES;
            _descriptionLabel.hidden = YES;

            _playlistOverlayCountLabel.stringValue = (p.videoCount >= 0)
                ? [NSString stringWithFormat:_NS("%ld videos"), (long)p.videoCount]
                : @"";

            _titleLabel.stringValue = p.title ?: @"";
            _metadataLabel.hidden = YES;

            _channelContainerView.hidden = (p.channelName.length == 0);
            _channelLabel.stringValue = p.channelName ?: @"";
            _verifiedSealImageView.hidden = YES;
            break;
        }
    }
}

- (void)setOpening:(BOOL)opening
{
    _isOpening = opening;
    if (opening) {
        _openingSpinner.hidden = NO;
        [_openingSpinner startAnimation:nil];
    } else {
        [_openingSpinner stopAnimation:nil];
        _openingSpinner.hidden = YES;
    }
}

- (void)addToQueueClicked:(id)sender
{
    if (self.item != nil && self.item.result != nil && self.item.result.video != nil && self.item.enqueueHandler != nil) {
        self.item.enqueueHandler(self.item.result.video);
    }
}

- (void)updateTrackingAreas
{
    [super updateTrackingAreas];
    if (_trackingArea != nil) {
        [self removeTrackingArea:_trackingArea];
    }
    _trackingArea = [[NSTrackingArea alloc] initWithRect:self.bounds
                                                 options:(NSTrackingActiveInKeyWindow |
                                                          NSTrackingMouseEnteredAndExited |
                                                          NSTrackingInVisibleRect)
                                                   owner:self
                                                userInfo:nil];
    [self addTrackingArea:_trackingArea];
}

- (void)resetCursorRects
{
    [super resetCursorRects];
    if (_isHovered && !_isOpening && self.item.result != nil) {
        [self addCursorRect:self.bounds cursor:NSCursor.pointingHandCursor];
    }
}

- (void)mouseEntered:(NSEvent *)event
{
    _isHovered = YES;
    [self updateHoverState:YES animated:YES];
    [self.window invalidateCursorRectsForView:self];
}

- (void)mouseExited:(NSEvent *)event
{
    _isHovered = NO;
    [self updateHoverState:NO animated:YES];
    [self.window invalidateCursorRectsForView:self];
}

- (void)updateHoverState:(BOOL)hovered animated:(BOOL)animated
{
    if (self.item.result == nil) {
        _addToQueueButton.alphaValue = 0.0;
        _leadingWrapperView.layer.transform = CATransform3DIdentity;
        return;
    }

    const CATransform3D targetTransform = (hovered && !MacLCDesign.reducedMotion)
        ? CATransform3DMakeScale(1.03, 1.03, 1.0)
        : CATransform3DIdentity;
    const CGFloat targetAlpha = (hovered && self.item.result.kind == MacLCYouTubeResultKindVideo) ? 1.0 : 0.0;

    CALayer * const layer = _leadingWrapperView.layer;
    if (layer == nil) {
        return;
    }

    if (!animated || MacLCDesign.reducedMotion) {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        [layer removeAnimationForKey:@"hoverTransform"];
        layer.transform = targetTransform;
        _addToQueueButton.alphaValue = targetAlpha;
        [CATransaction commit];
        return;
    }

    CALayer * const presentation = layer.presentationLayer ?: layer;
    CATransform3D const fromTransform = presentation.transform;
    layer.transform = targetTransform;

    CASpringAnimation *anim = [MacLCDesign emphasizedSpringForKeyPath:@"transform"];
    anim.fromValue = [NSValue valueWithCATransform3D:fromTransform];
    anim.toValue = [NSValue valueWithCATransform3D:targetTransform];
    [layer addAnimation:anim forKey:@"hoverTransform"];

    [NSAnimationContext runAnimationGroup:^(NSAnimationContext * _Nonnull context) {
        context.duration = MacLCDesign.motionQuickDuration;
        self->_addToQueueButton.animator.alphaValue = targetAlpha;
    }];
}

- (void)mouseUp:(NSEvent *)event
{
    if (_isOpening || self.item.result == nil) {
        return;
    }
    const NSPoint location = [self convertPoint:event.locationInWindow fromView:nil];
    if (NSPointInRect(location, self.bounds)) {
        if (self.item.activationHandler != nil) {
            self.item.activationHandler(self.item.result);
        }
    }
}

- (void)keyDown:(NSEvent *)event
{
    if (self.item.result != nil && !_isOpening) {
        if (event.keyCode == 36 || event.keyCode == 76 || event.keyCode == 49) {
            if (self.item.activationHandler != nil) {
                self.item.activationHandler(self.item.result);
                return;
            }
        }
    }
    [super keyDown:event];
}

- (NSMenu *)menuForEvent:(NSEvent *)event
{
    MacLCYouTubeResult * const result = self.item.result;
    if (result == nil) {
        return nil;
    }

    NSMenu * const menu = [[NSMenu alloc] initWithTitle:@"Result"];
    if (result.kind == MacLCYouTubeResultKindVideo && result.video != nil) {
        MacLCYouTubeVideo * const video = result.video;
        NSMenuItem *playItem = [[NSMenuItem alloc] initWithTitle:_NS("Play") action:@selector(contextPlayVideo:) keyEquivalent:@""];
        playItem.target = self;
        [menu addItem:playItem];

        NSMenuItem *enqueueItem = [[NSMenuItem alloc] initWithTitle:_NS("Add to Queue") action:@selector(contextEnqueueVideo:) keyEquivalent:@""];
        enqueueItem.target = self;
        [menu addItem:enqueueItem];

        [menu addItem:[NSMenuItem separatorItem]];

        NSMenuItem *detailsItem = [[NSMenuItem alloc] initWithTitle:_NS("Show Details") action:@selector(contextDetailsVideo:) keyEquivalent:@""];
        detailsItem.target = self;
        [menu addItem:detailsItem];

        if (video.channelURL != nil) {
            NSMenuItem *channelItem = [[NSMenuItem alloc] initWithTitle:_NS("Go to Channel") action:@selector(contextChannelVideo:) keyEquivalent:@""];
            channelItem.target = self;
            [menu addItem:channelItem];
        }

        [menu addItem:[NSMenuItem separatorItem]];

        NSMenuItem *copyItem = [[NSMenuItem alloc] initWithTitle:_NS("Copy Link") action:@selector(contextCopyLinkVideo:) keyEquivalent:@""];
        copyItem.target = self;
        [menu addItem:copyItem];

        NSMenuItem *browserItem = [[NSMenuItem alloc] initWithTitle:_NS("Open in Browser") action:@selector(contextOpenInBrowserVideo:) keyEquivalent:@""];
        browserItem.target = self;
        [menu addItem:browserItem];
    } else if (result.kind == MacLCYouTubeResultKindChannel && result.channel != nil) {
        NSMenuItem *channelItem = [[NSMenuItem alloc] initWithTitle:_NS("Go to Channel") action:@selector(contextActivateResult:) keyEquivalent:@""];
        channelItem.target = self;
        [menu addItem:channelItem];

        [menu addItem:[NSMenuItem separatorItem]];

        NSMenuItem *copyItem = [[NSMenuItem alloc] initWithTitle:_NS("Copy Link") action:@selector(contextCopyLinkChannel:) keyEquivalent:@""];
        copyItem.target = self;
        [menu addItem:copyItem];

        NSMenuItem *browserItem = [[NSMenuItem alloc] initWithTitle:_NS("Open in Browser") action:@selector(contextOpenInBrowserChannel:) keyEquivalent:@""];
        browserItem.target = self;
        [menu addItem:browserItem];
    } else if (result.kind == MacLCYouTubeResultKindPlaylist && result.playlist != nil) {
        NSMenuItem *plItem = [[NSMenuItem alloc] initWithTitle:_NS("Open Playlist") action:@selector(contextActivateResult:) keyEquivalent:@""];
        plItem.target = self;
        [menu addItem:plItem];

        [menu addItem:[NSMenuItem separatorItem]];

        NSMenuItem *copyItem = [[NSMenuItem alloc] initWithTitle:_NS("Copy Link") action:@selector(contextCopyLinkPlaylist:) keyEquivalent:@""];
        copyItem.target = self;
        [menu addItem:copyItem];

        NSMenuItem *browserItem = [[NSMenuItem alloc] initWithTitle:_NS("Open in Browser") action:@selector(contextOpenInBrowserPlaylist:) keyEquivalent:@""];
        browserItem.target = self;
        [menu addItem:browserItem];
    }

    return menu;
}

- (void)contextActivateResult:(id)sender
{
    if (self.item.result != nil && self.item.activationHandler != nil) {
        self.item.activationHandler(self.item.result);
    }
}

- (void)contextPlayVideo:(id)sender
{
    if (self.item.result != nil && self.item.activationHandler != nil) {
        self.item.activationHandler(self.item.result);
    }
}

- (void)contextEnqueueVideo:(id)sender
{
    if (self.item.result != nil && self.item.result.video != nil && self.item.enqueueHandler != nil) {
        self.item.enqueueHandler(self.item.result.video);
    }
}

- (void)contextDetailsVideo:(id)sender
{
    if (self.item.result != nil && self.item.result.video != nil && self.item.detailsHandler != nil) {
        self.item.detailsHandler(self.item.result.video);
    }
}

- (void)contextChannelVideo:(id)sender
{
    if (self.item.result != nil && self.item.result.video != nil && self.item.channelHandler != nil) {
        self.item.channelHandler(self.item.result.video);
    }
}

- (void)contextCopyLinkVideo:(id)sender
{
    if (self.item.result != nil && self.item.result.video != nil) {
        [MacLCYouTubeActions copyLinkOfVideo:self.item.result.video];
    }
}

- (void)contextOpenInBrowserVideo:(id)sender
{
    if (self.item.result != nil && self.item.result.video != nil && self.item.result.video.watchURL != nil) {
        [MacLCYouTubeActions openInBrowser:self.item.result.video.watchURL];
    }
}

- (void)contextCopyLinkChannel:(id)sender
{
    if (self.item.result != nil && self.item.result.channel != nil && self.item.result.channel.URL != nil) {
        [MacLCYouTubeActions openInBrowser:self.item.result.channel.URL];
    }
}

- (void)contextOpenInBrowserChannel:(id)sender
{
    if (self.item.result != nil && self.item.result.channel != nil && self.item.result.channel.URL != nil) {
        [MacLCYouTubeActions openInBrowser:self.item.result.channel.URL];
    }
}

- (void)contextCopyLinkPlaylist:(id)sender
{
    if (self.item.result != nil && self.item.result.playlist != nil && self.item.result.playlist.URL != nil) {
        [MacLCYouTubeActions openInBrowser:self.item.result.playlist.URL];
    }
}

- (void)contextOpenInBrowserPlaylist:(id)sender
{
    if (self.item.result != nil && self.item.result.playlist != nil && self.item.result.playlist.URL != nil) {
        [MacLCYouTubeActions openInBrowser:self.item.result.playlist.URL];
    }
}

#pragma mark - Accessibility

- (BOOL)isAccessibilityElement
{
    return YES;
}

- (NSAccessibilityRole)accessibilityRole
{
    return NSAccessibilityButtonRole;
}

- (nullable NSString *)accessibilityLabel
{
    MacLCYouTubeResult * const result = self.item.result;
    if (result == nil) {
        return _NS("Loading Result");
    }
    switch (result.kind) {
        case MacLCYouTubeResultKindVideo: {
            MacLCYouTubeVideo * const video = result.video;
            return [NSString stringWithFormat:@"%@, %@, %@, %@",
                    video.title ?: @"",
                    video.channelName ?: @"",
                    [MacLCYouTubeFormat durationString:video.duration] ?: @"",
                    [MacLCYouTubeFormat metadataLineForVideo:video now:[NSDate date]] ?: @""];
        }
        case MacLCYouTubeResultKindChannel: {
            MacLCYouTubeChannel * const channel = result.channel;
            return [NSString stringWithFormat:@"%@, %@, %@",
                    channel.name ?: @"",
                    channel.handle ?: @"",
                    [MacLCYouTubeFormat subscriberCountString:channel.subscriberCount] ?: @""];
        }
        case MacLCYouTubeResultKindPlaylist: {
            MacLCYouTubePlaylist * const playlist = result.playlist;
            return [NSString stringWithFormat:_NS("%@, %@, %ld videos"),
                    playlist.title ?: @"",
                    playlist.channelName ?: @"",
                    (long)playlist.videoCount];
        }
    }
}

- (BOOL)accessibilityPerformPress
{
    if (self.item.result != nil && !_isOpening && self.item.activationHandler != nil) {
        self.item.activationHandler(self.item.result);
        return YES;
    }
    return NO;
}

@end

#pragma mark - MacLCYouTubeResultRowItem Implementation

@implementation MacLCYouTubeResultRowItem
{
    MacLCWatchImageRequest *_imageRequest;
}

- (void)loadView
{
    MacLCYouTubeResultRowView *rowView = [[MacLCYouTubeResultRowView alloc] initWithFrame:NSMakeRect(0, 0, 800, [MacLCYouTubeResultRowItem rowHeight])];
    rowView.item = self;
    self.view = rowView;
}

- (MacLCYouTubeResultRowView *)rowView
{
    return (MacLCYouTubeResultRowView *)self.view;
}

- (void)dealloc
{
    [_imageRequest cancel];
}

- (void)configureAsPlaceholder
{
    [_imageRequest cancel];
    _imageRequest = nil;
    _result = nil;
    [self.rowView configureWithResult:nil];
    [self.rowView updateHoverState:NO animated:NO];
    [self.rowView setOpening:NO];
}

- (void)prepareForReuse
{
    [super prepareForReuse];
    [self configureAsPlaceholder];
}

- (void)configureWithResult:(MacLCYouTubeResult *)result
{
    _result = result;
    [_imageRequest cancel];
    _imageRequest = nil;

    MacLCYouTubeResultRowView * const rv = self.rowView;
    [rv configureWithResult:result];

    if (result == nil) {
        rv.thumbnailImageView.layer.contents = nil;
        rv.thumbnailImageView.hidden = YES;
        rv.placeholderImageView.hidden = NO;
        rv.channelAvatarView.image = nil;
        return;
    }

    const CGFloat scale = BackingScaleForView(self.view);
    __weak typeof(rv) weakRv = rv;

    if (result.kind == MacLCYouTubeResultKindChannel) {
        rv.thumbnailImageView.layer.contents = nil;
        rv.thumbnailImageView.hidden = YES;
        rv.placeholderImageView.hidden = YES;

        if (result.channel.avatarURL != nil) {
            MacLCWatchImageRequest *req = nil;
            NSImage * const cached = [[MacLCWatchImageCache sharedCache] imageForURL:result.channel.avatarURL
                                                                          pointSize:NSMakeSize(136.0, 136.0)
                                                                              scale:scale
                                                                            request:&req
                                                                         completion:^(NSImage * _Nullable image) {
                if (image != nil && weakRv != nil) {
                    weakRv.channelAvatarView.image = image;
                }
            }];
            _imageRequest = req;
            rv.channelAvatarView.image = cached ?: [NSImage imageWithSystemSymbolName:@"person.crop.circle" accessibilityDescription:nil];
        } else {
            rv.channelAvatarView.image = [NSImage imageWithSystemSymbolName:@"person.crop.circle" accessibilityDescription:nil];
        }
        return;
    }

    NSURL *imageURL = (result.kind == MacLCYouTubeResultKindVideo)
        ? result.video.thumbnailURL
        : result.playlist.thumbnailURL;

    if (imageURL != nil) {
        MacLCWatchImageRequest *req = nil;
        NSImage * const cached = [[MacLCWatchImageCache sharedCache] imageForURL:imageURL
                                                                      pointSize:NSMakeSize(320.0, 180.0)
                                                                          scale:scale
                                                                        request:&req
                                                                     completion:^(NSImage * _Nullable image) {
            if (image != nil && weakRv != nil) {
                weakRv.thumbnailImageView.layer.contents = image;
                weakRv.thumbnailImageView.hidden = NO;
                weakRv.placeholderImageView.hidden = YES;
            }
        }];
        _imageRequest = req;
        if (cached != nil) {
            rv.thumbnailImageView.layer.contents = cached;
            rv.thumbnailImageView.hidden = NO;
            rv.placeholderImageView.hidden = YES;
        } else {
            rv.thumbnailImageView.layer.contents = nil;
            rv.thumbnailImageView.hidden = YES;
            rv.placeholderImageView.hidden = NO;
        }
    } else {
        rv.thumbnailImageView.layer.contents = nil;
        rv.thumbnailImageView.hidden = YES;
        rv.placeholderImageView.hidden = NO;
    }
}

- (void)setOpening:(BOOL)opening
{
    [self.rowView setOpening:opening];
}

+ (CGFloat)rowHeight
{
    return 180.0;
}

@end

#pragma mark - Channel Shelf Item View

@interface MacLCYouTubeChannelTileView : NSView

@property (nonatomic, weak, nullable) MacLCYouTubeChannelItem *item;
@property (nonatomic, strong) NSImageView *avatarImageView;
@property (nonatomic, strong) NSTextField *nameLabel;
@property (nonatomic, strong) NSTextField *subscribersLabel;
@property (nonatomic) BOOL isHovered;
@property (nonatomic, strong, nullable) NSTrackingArea *trackingArea;

- (void)configureWithChannel:(nullable MacLCYouTubeChannel *)channel;

@end

@implementation MacLCYouTubeChannelTileView

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;

        _avatarImageView = [[NSImageView alloc] initWithFrame:NSZeroRect];
        _avatarImageView.translatesAutoresizingMaskIntoConstraints = NO;
        _avatarImageView.wantsLayer = YES;
        _avatarImageView.layer.masksToBounds = YES;
        _avatarImageView.layer.cornerRadius = 48.0;
        _avatarImageView.layer.backgroundColor = NSColor.quaternarySystemFillColor.CGColor;
        _avatarImageView.imageScaling = NSImageScaleProportionallyUpOrDown;
        [self addSubview:_avatarImageView];

        _nameLabel = [NSTextField labelWithString:@""];
        _nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _nameLabel.font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightSemibold];
        _nameLabel.textColor = NSColor.labelColor;
        _nameLabel.alignment = NSTextAlignmentCenter;
        _nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _nameLabel.maximumNumberOfLines = 2;
        _nameLabel.selectable = NO;
        [self addSubview:_nameLabel];

        _subscribersLabel = [NSTextField labelWithString:@""];
        _subscribersLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _subscribersLabel.font = [NSFont systemFontOfSize:12.0 weight:NSFontWeightRegular];
        _subscribersLabel.textColor = NSColor.secondaryLabelColor;
        _subscribersLabel.alignment = NSTextAlignmentCenter;
        _subscribersLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _subscribersLabel.selectable = NO;
        [self addSubview:_subscribersLabel];

        [NSLayoutConstraint activateConstraints:@[
            [_avatarImageView.topAnchor constraintEqualToAnchor:self.topAnchor constant:4.0],
            [_avatarImageView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [_avatarImageView.widthAnchor constraintEqualToConstant:96.0],
            [_avatarImageView.heightAnchor constraintEqualToConstant:96.0],

            [_nameLabel.topAnchor constraintEqualToAnchor:_avatarImageView.bottomAnchor constant:8.0],
            [_nameLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:4.0],
            [_nameLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-4.0],

            [_subscribersLabel.topAnchor constraintEqualToAnchor:_nameLabel.bottomAnchor constant:2.0],
            [_subscribersLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:4.0],
            [_subscribersLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-4.0],
        ]];
    }
    return self;
}

- (void)configureWithChannel:(nullable MacLCYouTubeChannel *)channel
{
    if (channel == nil) {
        _nameLabel.stringValue = @"";
        _subscribersLabel.stringValue = @"";
        _avatarImageView.image = nil;
        return;
    }
    _nameLabel.stringValue = channel.name ?: @"";
    _subscribersLabel.stringValue = (channel.subscriberCount >= 0)
        ? [MacLCYouTubeFormat subscriberCountString:channel.subscriberCount]
        : @"";
}

- (void)updateTrackingAreas
{
    [super updateTrackingAreas];
    if (_trackingArea != nil) {
        [self removeTrackingArea:_trackingArea];
    }
    _trackingArea = [[NSTrackingArea alloc] initWithRect:self.bounds
                                                 options:(NSTrackingActiveInKeyWindow |
                                                          NSTrackingMouseEnteredAndExited |
                                                          NSTrackingInVisibleRect)
                                                   owner:self
                                                userInfo:nil];
    [self addTrackingArea:_trackingArea];
}

- (void)resetCursorRects
{
    [super resetCursorRects];
    if (_isHovered && self.item.channel != nil) {
        [self addCursorRect:self.bounds cursor:NSCursor.pointingHandCursor];
    }
}

- (void)mouseEntered:(NSEvent *)event
{
    _isHovered = YES;
    [self.window invalidateCursorRectsForView:self];
}

- (void)mouseExited:(NSEvent *)event
{
    _isHovered = NO;
    [self.window invalidateCursorRectsForView:self];
}

- (void)mouseUp:(NSEvent *)event
{
    if (self.item.channel == nil) {
        return;
    }
    const NSPoint location = [self convertPoint:event.locationInWindow fromView:nil];
    if (NSPointInRect(location, self.bounds)) {
        if (self.item.activationHandler != nil) {
            self.item.activationHandler(self.item.channel);
        }
    }
}

- (void)keyDown:(NSEvent *)event
{
    if (self.item.channel != nil) {
        if (event.keyCode == 36 || event.keyCode == 76 || event.keyCode == 49) {
            if (self.item.activationHandler != nil) {
                self.item.activationHandler(self.item.channel);
                return;
            }
        }
    }
    [super keyDown:event];
}

- (BOOL)isAccessibilityElement
{
    return YES;
}

- (NSAccessibilityRole)accessibilityRole
{
    return NSAccessibilityButtonRole;
}

- (nullable NSString *)accessibilityLabel
{
    MacLCYouTubeChannel * const channel = self.item.channel;
    if (channel == nil) return @"";
    return [NSString stringWithFormat:@"%@, %@",
            channel.name ?: @"",
            [MacLCYouTubeFormat subscriberCountString:channel.subscriberCount] ?: @""];
}

- (BOOL)accessibilityPerformPress
{
    if (self.item.channel != nil && self.item.activationHandler != nil) {
        self.item.activationHandler(self.item.channel);
        return YES;
    }
    return NO;
}

@end

#pragma mark - MacLCYouTubeChannelItem Implementation

@implementation MacLCYouTubeChannelItem
{
    MacLCWatchImageRequest *_imageRequest;
}

- (void)loadView
{
    MacLCYouTubeChannelTileView *tileView = [[MacLCYouTubeChannelTileView alloc] initWithFrame:NSMakeRect(0, 0, 120, 160)];
    tileView.item = self;
    self.view = tileView;
}

- (MacLCYouTubeChannelTileView *)tileView
{
    return (MacLCYouTubeChannelTileView *)self.view;
}

- (void)dealloc
{
    [_imageRequest cancel];
}

- (void)prepareForReuse
{
    [super prepareForReuse];
    [_imageRequest cancel];
    _imageRequest = nil;
    _channel = nil;
    [self.tileView configureWithChannel:nil];
}

- (void)configureWithChannel:(MacLCYouTubeChannel *)channel
{
    _channel = channel;
    [_imageRequest cancel];
    _imageRequest = nil;

    MacLCYouTubeChannelTileView * const tv = self.tileView;
    [tv configureWithChannel:channel];

    if (channel != nil && channel.avatarURL != nil) {
        const CGFloat scale = BackingScaleForView(self.view);
        __weak typeof(tv) weakTv = tv;
        MacLCWatchImageRequest *req = nil;
        NSImage * const cached = [[MacLCWatchImageCache sharedCache] imageForURL:channel.avatarURL
                                                                      pointSize:NSMakeSize(96.0, 96.0)
                                                                          scale:scale
                                                                        request:&req
                                                                     completion:^(NSImage * _Nullable image) {
            if (image != nil && weakTv != nil) {
                weakTv.avatarImageView.image = image;
            }
        }];
        _imageRequest = req;
        tv.avatarImageView.image = cached ?: [NSImage imageWithSystemSymbolName:@"person.crop.circle" accessibilityDescription:nil];
    } else {
        tv.avatarImageView.image = [NSImage imageWithSystemSymbolName:@"person.crop.circle" accessibilityDescription:nil];
    }
}

@end

#pragma mark - Playlist Tile View

@interface MacLCYouTubePlaylistTileView : NSView

@property (nonatomic, weak, nullable) MacLCYouTubePlaylistItem *item;
@property (nonatomic, strong) NSView *stackBackEdge;
@property (nonatomic, strong) NSView *stackMiddleEdge;
@property (nonatomic, strong) NSView *thumbnailContainerView;
@property (nonatomic, strong) NSImageView *placeholderImageView;
@property (nonatomic, strong) NSView *thumbnailImageView;
@property (nonatomic, strong) NSView *countBadgeView;
@property (nonatomic, strong) NSImageView *countBadgeIcon;
@property (nonatomic, strong) NSTextField *countBadgeLabel;
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSTextField *channelLabel;

@property (nonatomic) BOOL isHovered;
@property (nonatomic, strong, nullable) NSTrackingArea *trackingArea;

- (void)configureWithPlaylist:(nullable MacLCYouTubePlaylist *)playlist;

@end

@implementation MacLCYouTubePlaylistTileView

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;

        /* Two thin stacked edges above the thumbnail for YouTube playlist look */
        _stackBackEdge = [[NSView alloc] initWithFrame:NSZeroRect];
        _stackBackEdge.translatesAutoresizingMaskIntoConstraints = NO;
        _stackBackEdge.wantsLayer = YES;
        _stackBackEdge.layer.cornerRadius = 4.0;
        _stackBackEdge.layer.backgroundColor = NSColor.quaternarySystemFillColor.CGColor;
        [self addSubview:_stackBackEdge];

        _stackMiddleEdge = [[NSView alloc] initWithFrame:NSZeroRect];
        _stackMiddleEdge.translatesAutoresizingMaskIntoConstraints = NO;
        _stackMiddleEdge.wantsLayer = YES;
        _stackMiddleEdge.layer.cornerRadius = 6.0;
        _stackMiddleEdge.layer.backgroundColor = NSColor.tertiarySystemFillColor.CGColor;
        [self addSubview:_stackMiddleEdge];

        /* Main thumbnail */
        _thumbnailContainerView = [[NSView alloc] initWithFrame:NSZeroRect];
        _thumbnailContainerView.translatesAutoresizingMaskIntoConstraints = NO;
        _thumbnailContainerView.wantsLayer = YES;
        _thumbnailContainerView.layer.masksToBounds = YES;
        _thumbnailContainerView.layer.cornerRadius = 12.0;
        _thumbnailContainerView.layer.cornerCurve = kCACornerCurveContinuous;
        _thumbnailContainerView.layer.backgroundColor = NSColor.quaternarySystemFillColor.CGColor;
        [self addSubview:_thumbnailContainerView];

        _placeholderImageView = [[NSImageView alloc] initWithFrame:NSZeroRect];
        _placeholderImageView.translatesAutoresizingMaskIntoConstraints = NO;
        _placeholderImageView.imageScaling = NSImageScaleProportionallyUpOrDown;
        _placeholderImageView.contentTintColor = NSColor.tertiaryLabelColor;
        NSImageSymbolConfiguration *placeholderConfig =
            [NSImageSymbolConfiguration configurationWithPointSize:36.0 weight:NSFontWeightLight];
        NSImage *placeholder = [NSImage imageWithSystemSymbolName:@"list.and.film" accessibilityDescription:nil];
        if (placeholder != nil) {
            placeholder = [placeholder imageWithSymbolConfiguration:placeholderConfig];
        }
        _placeholderImageView.image = placeholder;
        [_thumbnailContainerView addSubview:_placeholderImageView];

        _thumbnailImageView = [[NSView alloc] initWithFrame:NSZeroRect];
        _thumbnailImageView.translatesAutoresizingMaskIntoConstraints = NO;
        _thumbnailImageView.wantsLayer = YES;
        _thumbnailImageView.layer.contentsGravity = kCAGravityResizeAspectFill;
        _thumbnailImageView.layer.masksToBounds = YES;
        _thumbnailImageView.hidden = YES;
        [_thumbnailContainerView addSubview:_thumbnailImageView];

        /* Count badge */
        _countBadgeView = [[NSView alloc] initWithFrame:NSZeroRect];
        _countBadgeView.translatesAutoresizingMaskIntoConstraints = NO;
        _countBadgeView.wantsLayer = YES;
        _countBadgeView.layer.masksToBounds = YES;
        _countBadgeView.layer.backgroundColor = [NSColor colorWithCalibratedWhite:0.0 alpha:0.78].CGColor;
        [_thumbnailContainerView addSubview:_countBadgeView];

        _countBadgeIcon = [[NSImageView alloc] initWithFrame:NSZeroRect];
        _countBadgeIcon.translatesAutoresizingMaskIntoConstraints = NO;
        _countBadgeIcon.imageScaling = NSImageScaleProportionallyUpOrDown;
        _countBadgeIcon.contentTintColor = NSColor.whiteColor;
        NSImageSymbolConfiguration *badgeConfig =
            [NSImageSymbolConfiguration configurationWithPointSize:11.0 weight:NSFontWeightMedium];
        NSImage *badgeImg = [NSImage imageWithSystemSymbolName:@"list.and.film" accessibilityDescription:nil];
        if (badgeImg != nil) {
            badgeImg = [badgeImg imageWithSymbolConfiguration:badgeConfig];
        }
        _countBadgeIcon.image = badgeImg;
        [_countBadgeView addSubview:_countBadgeIcon];

        _countBadgeLabel = [NSTextField labelWithString:@""];
        _countBadgeLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _countBadgeLabel.textColor = NSColor.whiteColor;
        _countBadgeLabel.font = [NSFont monospacedDigitSystemFontOfSize:12.0 weight:NSFontWeightSemibold];
        _countBadgeLabel.selectable = NO;
        [_countBadgeView addSubview:_countBadgeLabel];

        /* Title */
        _titleLabel = [NSTextField labelWithString:@""];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _titleLabel.font = [NSFont systemFontOfSize:15.0 weight:NSFontWeightSemibold];
        _titleLabel.textColor = NSColor.labelColor;
        _titleLabel.lineBreakMode = NSLineBreakByWordWrapping;
        _titleLabel.cell.truncatesLastVisibleLine = YES;
        _titleLabel.maximumNumberOfLines = 2;
        _titleLabel.selectable = NO;
        [self addSubview:_titleLabel];

        /* Channel */
        _channelLabel = [NSTextField labelWithString:@""];
        _channelLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _channelLabel.font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightRegular];
        _channelLabel.textColor = NSColor.secondaryLabelColor;
        _channelLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _channelLabel.maximumNumberOfLines = 1;
        _channelLabel.selectable = NO;
        [self addSubview:_channelLabel];

        [NSLayoutConstraint activateConstraints:@[
            /* Stacked edges */
            [_stackBackEdge.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_stackBackEdge.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [_stackBackEdge.widthAnchor constraintEqualToAnchor:self.widthAnchor constant:-32.0],
            [_stackBackEdge.heightAnchor constraintEqualToConstant:6.0],

            [_stackMiddleEdge.topAnchor constraintEqualToAnchor:_stackBackEdge.topAnchor constant:3.0],
            [_stackMiddleEdge.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [_stackMiddleEdge.widthAnchor constraintEqualToAnchor:self.widthAnchor constant:-16.0],
            [_stackMiddleEdge.heightAnchor constraintEqualToConstant:6.0],

            /* Thumbnail */
            [_thumbnailContainerView.topAnchor constraintEqualToAnchor:_stackMiddleEdge.topAnchor constant:4.0],
            [_thumbnailContainerView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_thumbnailContainerView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_thumbnailContainerView.heightAnchor constraintEqualToAnchor:_thumbnailContainerView.widthAnchor multiplier:9.0 / 16.0],

            [_placeholderImageView.centerXAnchor constraintEqualToAnchor:_thumbnailContainerView.centerXAnchor],
            [_placeholderImageView.centerYAnchor constraintEqualToAnchor:_thumbnailContainerView.centerYAnchor],
            [_placeholderImageView.widthAnchor constraintEqualToConstant:40.0],
            [_placeholderImageView.heightAnchor constraintEqualToConstant:40.0],

            [_thumbnailImageView.topAnchor constraintEqualToAnchor:_thumbnailContainerView.topAnchor],
            [_thumbnailImageView.bottomAnchor constraintEqualToAnchor:_thumbnailContainerView.bottomAnchor],
            [_thumbnailImageView.leadingAnchor constraintEqualToAnchor:_thumbnailContainerView.leadingAnchor],
            [_thumbnailImageView.trailingAnchor constraintEqualToAnchor:_thumbnailContainerView.trailingAnchor],

            [_countBadgeView.trailingAnchor constraintEqualToAnchor:_thumbnailContainerView.trailingAnchor constant:-6.0],
            [_countBadgeView.bottomAnchor constraintEqualToAnchor:_thumbnailContainerView.bottomAnchor constant:-6.0],

            [_countBadgeIcon.leadingAnchor constraintEqualToAnchor:_countBadgeView.leadingAnchor constant:6.0],
            [_countBadgeIcon.centerYAnchor constraintEqualToAnchor:_countBadgeView.centerYAnchor],
            [_countBadgeIcon.widthAnchor constraintEqualToConstant:14.0],
            [_countBadgeIcon.heightAnchor constraintEqualToConstant:14.0],

            [_countBadgeLabel.leadingAnchor constraintEqualToAnchor:_countBadgeIcon.trailingAnchor constant:4.0],
            [_countBadgeLabel.trailingAnchor constraintEqualToAnchor:_countBadgeView.trailingAnchor constant:-6.0],
            [_countBadgeLabel.topAnchor constraintEqualToAnchor:_countBadgeView.topAnchor constant:2.0],
            [_countBadgeLabel.bottomAnchor constraintEqualToAnchor:_countBadgeView.bottomAnchor constant:-2.0],

            [_titleLabel.topAnchor constraintEqualToAnchor:_thumbnailContainerView.bottomAnchor constant:10.0],
            [_titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_titleLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],

            [_channelLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:4.0],
            [_channelLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_channelLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        ]];
    }
    return self;
}

- (void)layout
{
    [super layout];
    _countBadgeView.layer.cornerRadius = _countBadgeView.bounds.size.height / 2.0;
}

- (void)configureWithPlaylist:(nullable MacLCYouTubePlaylist *)playlist
{
    if (playlist == nil) {
        _titleLabel.stringValue = @"";
        _channelLabel.stringValue = @"";
        _countBadgeView.hidden = YES;
        _thumbnailImageView.hidden = YES;
        _placeholderImageView.hidden = NO;
        return;
    }
    _titleLabel.stringValue = playlist.title ?: @"";
    _channelLabel.stringValue = playlist.channelName ?: @"";

    if (playlist.videoCount >= 0) {
        _countBadgeView.hidden = NO;
        _countBadgeLabel.stringValue = [NSString stringWithFormat:_NS("%ld videos"), (long)playlist.videoCount];
    } else {
        _countBadgeView.hidden = YES;
    }
}

- (void)updateTrackingAreas
{
    [super updateTrackingAreas];
    if (_trackingArea != nil) {
        [self removeTrackingArea:_trackingArea];
    }
    _trackingArea = [[NSTrackingArea alloc] initWithRect:self.bounds
                                                 options:(NSTrackingActiveInKeyWindow |
                                                          NSTrackingMouseEnteredAndExited |
                                                          NSTrackingInVisibleRect)
                                                   owner:self
                                                userInfo:nil];
    [self addTrackingArea:_trackingArea];
}

- (void)resetCursorRects
{
    [super resetCursorRects];
    if (_isHovered && self.item.playlist != nil) {
        [self addCursorRect:self.bounds cursor:NSCursor.pointingHandCursor];
    }
}

- (void)mouseEntered:(NSEvent *)event
{
    _isHovered = YES;
    [self.window invalidateCursorRectsForView:self];
}

- (void)mouseExited:(NSEvent *)event
{
    _isHovered = NO;
    [self.window invalidateCursorRectsForView:self];
}

- (void)mouseUp:(NSEvent *)event
{
    if (self.item.playlist == nil) {
        return;
    }
    const NSPoint location = [self convertPoint:event.locationInWindow fromView:nil];
    if (NSPointInRect(location, self.bounds)) {
        if (self.item.activationHandler != nil) {
            self.item.activationHandler(self.item.playlist);
        }
    }
}

- (void)keyDown:(NSEvent *)event
{
    if (self.item.playlist != nil) {
        if (event.keyCode == 36 || event.keyCode == 76 || event.keyCode == 49) {
            if (self.item.activationHandler != nil) {
                self.item.activationHandler(self.item.playlist);
                return;
            }
        }
    }
    [super keyDown:event];
}

- (BOOL)isAccessibilityElement
{
    return YES;
}

- (NSAccessibilityRole)accessibilityRole
{
    return NSAccessibilityButtonRole;
}

- (nullable NSString *)accessibilityLabel
{
    MacLCYouTubePlaylist * const playlist = self.item.playlist;
    if (playlist == nil) return @"";
    return [NSString stringWithFormat:_NS("%@, %@, %ld videos"),
            playlist.title ?: @"",
            playlist.channelName ?: @"",
            (long)playlist.videoCount];
}

- (BOOL)accessibilityPerformPress
{
    if (self.item.playlist != nil && self.item.activationHandler != nil) {
        self.item.activationHandler(self.item.playlist);
        return YES;
    }
    return NO;
}

@end

#pragma mark - MacLCYouTubePlaylistItem Implementation

@implementation MacLCYouTubePlaylistItem
{
    MacLCWatchImageRequest *_imageRequest;
}

- (void)loadView
{
    MacLCYouTubePlaylistTileView *tileView = [[MacLCYouTubePlaylistTileView alloc] initWithFrame:NSMakeRect(0, 0, 320, 260)];
    tileView.item = self;
    self.view = tileView;
}

- (MacLCYouTubePlaylistTileView *)tileView
{
    return (MacLCYouTubePlaylistTileView *)self.view;
}

- (void)dealloc
{
    [_imageRequest cancel];
}

- (void)configureAsPlaceholder
{
    [_imageRequest cancel];
    _imageRequest = nil;
    _playlist = nil;
    [self.tileView configureWithPlaylist:nil];
}

- (void)prepareForReuse
{
    [super prepareForReuse];
    [self configureAsPlaceholder];
}

- (void)configureWithPlaylist:(MacLCYouTubePlaylist *)playlist
{
    _playlist = playlist;
    [_imageRequest cancel];
    _imageRequest = nil;

    MacLCYouTubePlaylistTileView * const tv = self.tileView;
    [tv configureWithPlaylist:playlist];

    if (playlist != nil && playlist.thumbnailURL != nil) {
        const CGFloat width = tv.bounds.size.width > 0.0 ? tv.bounds.size.width : 320.0;
        const NSSize pointSize = NSMakeSize(width, width * 9.0 / 16.0);
        const CGFloat scale = BackingScaleForView(self.view);
        __weak typeof(tv) weakTv = tv;
        MacLCWatchImageRequest *req = nil;
        NSImage * const cached = [[MacLCWatchImageCache sharedCache] imageForURL:playlist.thumbnailURL
                                                                      pointSize:pointSize
                                                                          scale:scale
                                                                        request:&req
                                                                     completion:^(NSImage * _Nullable image) {
            if (image != nil && weakTv != nil) {
                weakTv.thumbnailImageView.layer.contents = image;
                weakTv.thumbnailImageView.hidden = NO;
                weakTv.placeholderImageView.hidden = YES;
            }
        }];
        _imageRequest = req;
        if (cached != nil) {
            tv.thumbnailImageView.layer.contents = cached;
            tv.thumbnailImageView.hidden = NO;
            tv.placeholderImageView.hidden = YES;
        } else {
            tv.thumbnailImageView.layer.contents = nil;
            tv.thumbnailImageView.hidden = YES;
            tv.placeholderImageView.hidden = NO;
        }
    } else {
        tv.thumbnailImageView.layer.contents = nil;
        tv.thumbnailImageView.hidden = YES;
        tv.placeholderImageView.hidden = NO;
    }
}

@end

#pragma mark - Topic Chips Bar

@interface MacLCYouTubeChipsBar ()

@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, strong) NSView *documentView;
@property (nonatomic, strong) NSMutableArray<NSButton *> *chipButtons;
@property (nonatomic, strong) CAGradientLayer *maskGradientLayer;

@end

@implementation MacLCYouTubeChipsBar

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        _chipButtons = [NSMutableArray array];

        _scrollView = [[NSScrollView alloc] initWithFrame:self.bounds];
        _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
        _scrollView.hasHorizontalScroller = NO;
        _scrollView.hasVerticalScroller = NO;
        _scrollView.drawsBackground = NO;
        _scrollView.automaticallyAdjustsContentInsets = NO;
        [self addSubview:_scrollView];

        _documentView = [[NSView alloc] initWithFrame:NSZeroRect];
        _documentView.wantsLayer = YES;
        _scrollView.documentView = _documentView;

        _maskGradientLayer = [CAGradientLayer layer];
        _maskGradientLayer.startPoint = CGPointMake(0.0, 0.5);
        _maskGradientLayer.endPoint = CGPointMake(1.0, 0.5);
        _scrollView.contentView.wantsLayer = YES;
        _scrollView.contentView.layer.mask = _maskGradientLayer;

        [NSLayoutConstraint activateConstraints:@[
            [_scrollView.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_scrollView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            [_scrollView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_scrollView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        ]];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(scrollViewDidScroll:)
                                                     name:NSViewBoundsDidChangeNotification
                                                   object:_scrollView.contentView];
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (BOOL)acceptsFirstResponder
{
    return YES;
}

- (void)setTitles:(NSArray<NSString *> *)titles
{
    _titles = [titles copy];
    _selectedIndex = 0;
    [self rebuildChips];
}

- (void)setSelectedIndex:(NSInteger)selectedIndex
{
    if (selectedIndex < 0) selectedIndex = 0;
    if (_titles.count > 0 && selectedIndex >= (NSInteger)_titles.count) {
        selectedIndex = (NSInteger)_titles.count - 1;
    }
    _selectedIndex = selectedIndex;
    [self updateChipSelectionStyles];
    [self scrollSelectedChipToVisible];
}

- (void)rebuildChips
{
    for (NSButton *btn in _chipButtons) {
        [btn removeFromSuperview];
    }
    [_chipButtons removeAllObjects];

    CGFloat currentX = 0.0;
    const CGFloat chipHeight = 32.0;
    const CGFloat spacing = 8.0;
    const CGFloat paddingH = 12.0;

    for (NSInteger i = 0; i < (NSInteger)_titles.count; i++) {
        NSString *title = _titles[i];
        NSButton *btn = [NSButton buttonWithTitle:title target:self action:@selector(chipClicked:)];
        btn.tag = i;
        btn.bordered = NO;
        btn.wantsLayer = YES;
        btn.layer.cornerRadius = chipHeight / 2.0;
        btn.layer.masksToBounds = YES;
        btn.font = [NSFont systemFontOfSize:14.0 weight:NSFontWeightMedium];

        /* Measure text size */
        NSDictionary *attrs = @{ NSFontAttributeName: btn.font };
        NSSize textSize = [title sizeWithAttributes:attrs];
        CGFloat width = ceil(textSize.width + paddingH * 2.0);

        btn.frame = NSMakeRect(currentX, 0, width, chipHeight);
        [_documentView addSubview:btn];
        [_chipButtons addObject:btn];

        currentX += width + spacing;
    }

    const CGFloat totalWidth = currentX > 0.0 ? (currentX - spacing) : 0.0;
    _documentView.frame = NSMakeRect(0, 0, totalWidth, chipHeight);

    [self updateChipSelectionStyles];
    [self updateMaskGradients];
}

- (void)updateChipSelectionStyles
{
    for (NSInteger i = 0; i < (NSInteger)_chipButtons.count; i++) {
        NSButton *btn = _chipButtons[i];
        BOOL selected = (i == _selectedIndex);
        if (selected) {
            btn.layer.backgroundColor = NSColor.labelColor.CGColor;
            NSMutableAttributedString *attr = [[NSMutableAttributedString alloc] initWithString:btn.title];
            [attr addAttributes:@{
                NSForegroundColorAttributeName: NSColor.windowBackgroundColor,
                NSFontAttributeName: [NSFont systemFontOfSize:14.0 weight:NSFontWeightMedium]
            } range:NSMakeRange(0, attr.length)];
            btn.attributedTitle = attr;
        } else {
            btn.layer.backgroundColor = NSColor.quaternarySystemFillColor.CGColor;
            NSMutableAttributedString *attr = [[NSMutableAttributedString alloc] initWithString:btn.title];
            [attr addAttributes:@{
                NSForegroundColorAttributeName: NSColor.labelColor,
                NSFontAttributeName: [NSFont systemFontOfSize:14.0 weight:NSFontWeightMedium]
            } range:NSMakeRange(0, attr.length)];
            btn.attributedTitle = attr;
        }
    }
}

- (void)layout
{
    [super layout];
    [self updateMaskGradients];
}

- (void)viewDidChangeEffectiveAppearance
{
    [super viewDidChangeEffectiveAppearance];
    [self updateChipSelectionStyles];
}

- (void)scrollViewDidScroll:(NSNotification *)note
{
    [self updateMaskGradients];
}

- (void)updateMaskGradients
{
    const NSRect visibleRect = _scrollView.contentView.bounds;
    const CGFloat maxScrollX = MAX(0.0, _documentView.frame.size.width - visibleRect.size.width);

    _maskGradientLayer.frame = _scrollView.contentView.bounds;

    const CGFloat fadeWidth = 24.0;
    const CGFloat viewWidth = visibleRect.size.width;
    if (viewWidth <= 0.0) return;

    const CGFloat leftFadeFraction = (fadeWidth / viewWidth);
    const CGFloat rightFadeFraction = 1.0 - (fadeWidth / viewWidth);

    const BOOL hasLeft = visibleRect.origin.x > 2.0;
    const BOOL hasRight = visibleRect.origin.x < (maxScrollX - 2.0);

    NSMutableArray *colors = [NSMutableArray array];
    NSMutableArray *locations = [NSMutableArray array];

    if (hasLeft) {
        [colors addObject:(__bridge id)NSColor.clearColor.CGColor];
        [locations addObject:@(0.0)];
        [colors addObject:(__bridge id)NSColor.blackColor.CGColor];
        [locations addObject:@(leftFadeFraction)];
    } else {
        [colors addObject:(__bridge id)NSColor.blackColor.CGColor];
        [locations addObject:@(0.0)];
    }

    if (hasRight) {
        [colors addObject:(__bridge id)NSColor.blackColor.CGColor];
        [locations addObject:@(rightFadeFraction)];
        [colors addObject:(__bridge id)NSColor.clearColor.CGColor];
        [locations addObject:@(1.0)];
    } else {
        [colors addObject:(__bridge id)NSColor.blackColor.CGColor];
        [locations addObject:@(1.0)];
    }

    _maskGradientLayer.colors = colors;
    _maskGradientLayer.locations = locations;
}

- (void)scrollSelectedChipToVisible
{
    if (_selectedIndex >= 0 && _selectedIndex < (NSInteger)_chipButtons.count) {
        NSButton *btn = _chipButtons[_selectedIndex];
        [_documentView scrollRectToVisible:NSInsetRect(btn.frame, -16.0, 0)];
    }
}

- (void)chipClicked:(NSButton *)sender
{
    NSInteger index = sender.tag;
    if (index != _selectedIndex) {
        self.selectedIndex = index;
        if (self.selectionHandler != nil) {
            self.selectionHandler(index);
        }
    }
}

- (void)keyDown:(NSEvent *)event
{
    if (event.keyCode == 123) { // Left arrow
        if (_selectedIndex > 0) {
            self.selectedIndex = _selectedIndex - 1;
            if (self.selectionHandler != nil) {
                self.selectionHandler(_selectedIndex);
            }
        }
        return;
    } else if (event.keyCode == 124) { // Right arrow
        if (_selectedIndex + 1 < (NSInteger)_titles.count) {
            self.selectedIndex = _selectedIndex + 1;
            if (self.selectionHandler != nil) {
                self.selectionHandler(_selectedIndex);
            }
        }
        return;
    }
    [super keyDown:event];
}

#pragma mark - Accessibility

- (BOOL)isAccessibilityElement
{
    return YES;
}

- (NSAccessibilityRole)accessibilityRole
{
    return NSAccessibilityRadioGroupRole;
}

- (nullable NSArray *)accessibilityChildren
{
    return _chipButtons;
}

@end

#pragma mark - Account Button

@interface MacLCYouTubeAccountButton ()
{
    MacLCWatchImageRequest *_avatarRequest;
}
@end

@implementation MacLCYouTubeAccountButton

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        [self setupAccountButton];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (self) {
        [self setupAccountButton];
    }
    return self;
}

- (void)setupAccountButton
{
    self.target = self;
    self.action = @selector(buttonClicked:);
    self.imagePosition = NSImageLeading;
    self.imageScaling = NSImageScaleProportionallyUpOrDown;
    self.font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightMedium];
    self.lineBreakMode = NSLineBreakByClipping;
    [self setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    [self setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];

    [self updateState];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(accountDidChange:)
                                                 name:MacLCYouTubeAccountDidChangeNotification
                                               object:nil];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_avatarRequest cancel];
}

- (void)accountDidChange:(NSNotification *)note
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateState];
    });
}

- (void)updateState
{
    [_avatarRequest cancel];
    _avatarRequest = nil;

    MacLCYouTubeAccount * const account = [MacLCYouTubeAccount sharedAccount];
    const BOOL signedIn = account.isSignedIn;

    if (!signedIn) {
        self.bordered = YES;
        self.wantsLayer = YES;
        self.layer.cornerRadius = 14.0;
        self.layer.masksToBounds = YES;
        self.title = _NS("Sign In");
        self.image = [NSImage imageWithSystemSymbolName:@"person.crop.circle"
                                accessibilityDescription:_NS("Sign In")];
        self.toolTip = _NS("Sign In to YouTube");
        self.accessibilityLabel = _NS("Sign In");

        if (@available(macOS 26.0, *)) {
            self.bezelStyle = NSBezelStylePush;
            self.borderShape = NSControlBorderShapeCapsule;
        } else {
            self.bezelStyle = NSBezelStyleRounded;
        }
    } else {
        self.title = @"";
        self.toolTip = _NS("Account");
        self.accessibilityLabel = _NS("Account");
        self.bordered = NO;
        self.wantsLayer = YES;
        self.layer.cornerRadius = 14.0;
        self.layer.masksToBounds = YES;

        NSImageSymbolConfiguration *cfg =
            [NSImageSymbolConfiguration configurationWithPointSize:24.0 weight:NSFontWeightRegular];
        NSImage *placeholder = [NSImage imageWithSystemSymbolName:@"person.crop.circle.fill" accessibilityDescription:_NS("Account")];
        if (placeholder != nil) {
            placeholder = [placeholder imageWithSymbolConfiguration:cfg];
        }
        self.image = placeholder;

        if (account.avatarURL != nil) {
            const CGFloat scale = BackingScaleForView(self);
            __weak typeof(self) weakSelf = self;
            MacLCWatchImageRequest *req = nil;
            NSImage *cached = [[MacLCWatchImageCache sharedCache] imageForURL:account.avatarURL
                                                                   pointSize:NSMakeSize(28.0, 28.0)
                                                                       scale:scale
                                                                     request:&req
                                                                  completion:^(NSImage * _Nullable image) {
                if (image != nil && weakSelf != nil) {
                    weakSelf.image = image;
                }
            }];
            _avatarRequest = req;
            if (cached != nil) {
                self.image = cached;
            }
        }
    }
    [self invalidateIntrinsicContentSize];
}

- (NSSize)intrinsicContentSize
{
    if ([MacLCYouTubeAccount sharedAccount].isSignedIn) {
        return NSMakeSize(28.0, 28.0);
    }
    /* Measured from the title, never from the bezel: the symbol (16), a gap
     * (6) and 14 of padding on each side, as the capsule draws them. */
    NSDictionary * const attributes = @{NSFontAttributeName: self.font ?: [NSFont systemFontOfSize:13.0]};
    const CGFloat textWidth = ceil([self.title sizeWithAttributes:attributes].width);
    return NSMakeSize(textWidth + 16.0 + 6.0 + 2 * 14.0 + 4.0, 28.0);
}

- (void)buttonClicked:(id)sender
{
    NSMenu * const menu = [self buildAccountMenu];
    [menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(0, self.bounds.size.height + 4) inView:self];
}

- (NSMenu *)buildAccountMenu
{
    MacLCYouTubeAccount * const account = [MacLCYouTubeAccount sharedAccount];
    NSMenu * const menu = [[NSMenu alloc] initWithTitle:@"YouTube Account"];

    if (!account.isSignedIn) {
        NSMenuItem *signInItem = [[NSMenuItem alloc] initWithTitle:_NS("Sign In with Google…")
                                                            action:@selector(signInClicked:)
                                                     keyEquivalent:@""];
        signInItem.target = self;
        [menu addItem:signInItem];

        NSArray<NSString *> * const browsers = [MacLCYouTubeAccount availableBrowsers];
        for (NSString *browser in browsers) {
            NSString *disp = [MacLCYouTubeAccount displayNameForBrowser:browser];
            NSString *title = [NSString stringWithFormat:_NS("Use %@’s Session"), disp];
            NSMenuItem *browserItem = [[NSMenuItem alloc] initWithTitle:title
                                                                 action:@selector(browserSessionClicked:)
                                                          keyEquivalent:@""];
            browserItem.representedObject = browser;
            browserItem.target = self;
            browserItem.toolTip = [NSString stringWithFormat:_NS("Uses the signed-in YouTube cookies from %@."), disp];
            [menu addItem:browserItem];
        }

        [menu addItem:[NSMenuItem separatorItem]];

        NSMenuItem *aboutItem = [[NSMenuItem alloc] initWithTitle:_NS("About Signing In")
                                                           action:@selector(aboutSigningInClicked:)
                                                    keyEquivalent:@""];
        aboutItem.target = self;
        [menu addItem:aboutItem];
    } else {
        NSString *headerTitle = (account.method == MacLCYouTubeSignInMethodBrowser)
            ? [NSString stringWithFormat:_NS("Using %@’s Session"), account.browserDisplayName ?: _NS("Browser")]
            : _NS("Signed In with Google");
        NSMenuItem *headerItem = [[NSMenuItem alloc] initWithTitle:headerTitle action:nil keyEquivalent:@""];
        headerItem.enabled = NO;
        [menu addItem:headerItem];

        NSMenuItem *openBrowserItem = [[NSMenuItem alloc] initWithTitle:_NS("Open YouTube in Browser")
                                                                 action:@selector(openBrowserClicked:)
                                                          keyEquivalent:@""];
        openBrowserItem.target = self;
        [menu addItem:openBrowserItem];

        [menu addItem:[NSMenuItem separatorItem]];

        NSMenuItem *signOutItem = [[NSMenuItem alloc] initWithTitle:_NS("Sign Out")
                                                             action:@selector(signOutClicked:)
                                                      keyEquivalent:@""];
        signOutItem.target = self;
        [menu addItem:signOutItem];
    }

    return menu;
}

- (void)signInClicked:(id)sender
{
    [[MacLCYouTubeAccount sharedAccount] beginSignInFromWindow:self.window completion:nil];
}

- (void)browserSessionClicked:(NSMenuItem *)sender
{
    NSString *browser = sender.representedObject;
    if (browser.length > 0) {
        [[MacLCYouTubeAccount sharedAccount] useBrowserSession:browser];
    }
}

- (void)aboutSigningInClicked:(id)sender
{
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = _NS("About Signing In");
    alert.informativeText = _NS("MacLC stores a session cookie file in your MacLC folder so you can browse your YouTube feed. MacLC never sees, stores, or transmits your password.");
    alert.alertStyle = NSAlertStyleInformational;
    [alert addButtonWithTitle:_NS("OK")];
    if (self.window != nil) {
        [alert beginSheetModalForWindow:self.window completionHandler:nil];
    } else {
        [alert runModal];
    }
}

- (void)openBrowserClicked:(id)sender
{
    [MacLCYouTubeActions openInBrowser:[NSURL URLWithString:@"https://www.youtube.com"]];
}

- (void)signOutClicked:(id)sender
{
    [[MacLCYouTubeAccount sharedAccount] signOut];
}

@end

#pragma mark - Browser-session error

MacLCEmptyStateView *MacLCYouTubeBrowserCookiesStateView(NSWindow * _Nullable (^window)(void), void (^afterSignIn)(void))
{
    MacLCYouTubeAccount * const account = [MacLCYouTubeAccount sharedAccount];
    NSString * const browser = account.browserDisplayName ?: _NS("Your Browser");
    const BOOL safari = [account.browserName isEqualToString:@"safari"];
    NSString * const message = safari
        ? _NS("macOS keeps Safari’s cookies private. Allow MacLC in System Settings › Privacy & Security › Full Disk Access, or sign in with Google instead.")
        : [NSString stringWithFormat:_NS("%@ did not let MacLC read its cookies. Allow it when the Keychain asks, or sign in with Google instead."), browser];
    MacLCEmptyStateView * const view =
        [MacLCEmptyStateView emptyStateWithSymbolName:@"lock.shield"
                                                title:[NSString stringWithFormat:_NS("Can’t Use %@’s Session"), browser]
                                              message:message];
    [view addButtonWithTitle:_NS("Sign In with Google…") prominent:YES action:^{
        [[MacLCYouTubeAccount sharedAccount] beginSignInFromWindow:window ? window() : nil completion:^(BOOL signedIn) {
            if (signedIn && afterSignIn) {
                afterSignIn();
            }
        }];
    }];
    if (safari) {
        [view addButtonWithTitle:_NS("Open Privacy Settings") prominent:NO action:^{
            [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"]];
        }];
    }
    return view;
}

#pragma mark - Layouts

@implementation MacLCYouTubeLayout

+ (NSCollectionLayoutSection *)videoGridSectionWithEnvironment:(id<NSCollectionLayoutEnvironment>)environment
                                                     hasHeader:(BOOL)hasHeader
{
    const CGFloat minWidth = 260.0;
    const CGFloat maxWidth = 380.0;
    const CGFloat colSpacing = 16.0;
    const CGFloat rowSpacing = 36.0;
    const CGFloat horizontalInset = 24.0;
    const CGFloat available = MAX(environment.container.effectiveContentSize.width - 2.0 * horizontalInset, minWidth);

    NSInteger columns = MAX(1, (NSInteger)floor((available + colSpacing) / (minWidth + colSpacing)));
    CGFloat itemWidth = (available - (columns - 1) * colSpacing) / columns;
    while (itemWidth > maxWidth) {
        columns += 1;
        itemWidth = (available - (columns - 1) * colSpacing) / columns;
    }
    itemWidth = floor(itemWidth);
    const CGFloat itemHeight = [MacLCYouTubeVideoItem heightForWidth:itemWidth];

    NSCollectionLayoutSize *itemSize =
        [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension absoluteDimension:itemWidth]
                                       heightDimension:[NSCollectionLayoutDimension absoluteDimension:itemHeight]];
    NSCollectionLayoutItem *item = [NSCollectionLayoutItem itemWithLayoutSize:itemSize];

    NSCollectionLayoutSize *groupSize =
        [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1.0]
                                       heightDimension:[NSCollectionLayoutDimension absoluteDimension:itemHeight]];
    NSCollectionLayoutGroup *group =
        [NSCollectionLayoutGroup horizontalGroupWithLayoutSize:groupSize subitem:item count:columns];
    group.interItemSpacing = [NSCollectionLayoutSpacing fixedSpacing:colSpacing];

    NSCollectionLayoutSection *section = [NSCollectionLayoutSection sectionWithGroup:group];
    section.interGroupSpacing = rowSpacing;
    section.contentInsets = NSDirectionalEdgeInsetsMake(16.0, horizontalInset, 36.0, horizontalInset);

    if (hasHeader) {
        NSCollectionLayoutSize *headerSize =
            [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1.0]
                                           heightDimension:[NSCollectionLayoutDimension estimatedDimension:88.0]];
        NSCollectionLayoutBoundarySupplementaryItem *headerItem =
            [NSCollectionLayoutBoundarySupplementaryItem boundarySupplementaryItemWithLayoutSize:headerSize
                                                                                      elementKind:NSCollectionElementKindSectionHeader
                                                                                        alignment:NSRectAlignmentTop];
        section.boundarySupplementaryItems = @[headerItem];
    }
    return section;
}

+ (NSCollectionLayoutSection *)resultListSectionWithEnvironment:(id<NSCollectionLayoutEnvironment>)environment
                                                      hasHeader:(BOOL)hasHeader
{
    const CGFloat containerWidth = environment.container.effectiveContentSize.width;
    const CGFloat maxContentWidth = 1100.0;
    const CGFloat sideInset = MAX(24.0, (containerWidth - maxContentWidth) / 2.0);
    const CGFloat itemHeight = [MacLCYouTubeResultRowItem rowHeight];

    NSCollectionLayoutSize *itemSize =
        [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1.0]
                                       heightDimension:[NSCollectionLayoutDimension absoluteDimension:itemHeight]];
    NSCollectionLayoutItem *item = [NSCollectionLayoutItem itemWithLayoutSize:itemSize];

    NSCollectionLayoutSize *groupSize =
        [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1.0]
                                       heightDimension:[NSCollectionLayoutDimension absoluteDimension:itemHeight]];
    NSCollectionLayoutGroup *group =
        [NSCollectionLayoutGroup horizontalGroupWithLayoutSize:groupSize subitems:@[item]];

    NSCollectionLayoutSection *section = [NSCollectionLayoutSection sectionWithGroup:group];
    section.interGroupSpacing = 16.0;
    section.contentInsets = NSDirectionalEdgeInsetsMake(16.0, sideInset, 36.0, sideInset);

    if (hasHeader) {
        NSCollectionLayoutSize *headerSize =
            [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1.0]
                                           heightDimension:[NSCollectionLayoutDimension estimatedDimension:88.0]];
        NSCollectionLayoutBoundarySupplementaryItem *headerItem =
            [NSCollectionLayoutBoundarySupplementaryItem boundarySupplementaryItemWithLayoutSize:headerSize
                                                                                      elementKind:NSCollectionElementKindSectionHeader
                                                                                        alignment:NSRectAlignmentTop];
        section.boundarySupplementaryItems = @[headerItem];
    }
    return section;
}

+ (NSCollectionLayoutSection *)channelShelfSectionWithEnvironment:(id<NSCollectionLayoutEnvironment>)environment
{
    const CGFloat itemWidth = 120.0;
    const CGFloat itemHeight = 160.0;

    NSCollectionLayoutSize *itemSize =
        [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension absoluteDimension:itemWidth]
                                       heightDimension:[NSCollectionLayoutDimension absoluteDimension:itemHeight]];
    NSCollectionLayoutItem *item = [NSCollectionLayoutItem itemWithLayoutSize:itemSize];

    NSCollectionLayoutSize *groupSize =
        [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension absoluteDimension:itemWidth]
                                       heightDimension:[NSCollectionLayoutDimension absoluteDimension:itemHeight]];
    NSCollectionLayoutGroup *group =
        [NSCollectionLayoutGroup horizontalGroupWithLayoutSize:groupSize subitems:@[item]];

    NSCollectionLayoutSection *section = [NSCollectionLayoutSection sectionWithGroup:group];
    section.orthogonalScrollingBehavior = NSCollectionLayoutSectionOrthogonalScrollingBehaviorContinuous;
    section.interGroupSpacing = 16.0;
    section.contentInsets = NSDirectionalEdgeInsetsMake(12.0, 24.0, 24.0, 24.0);
    return section;
}

+ (NSCollectionLayoutSection *)playlistGridSectionWithEnvironment:(id<NSCollectionLayoutEnvironment>)environment
                                                        hasHeader:(BOOL)hasHeader
{
    const CGFloat minWidth = 260.0;
    const CGFloat maxWidth = 380.0;
    const CGFloat colSpacing = 16.0;
    const CGFloat rowSpacing = 36.0;
    const CGFloat horizontalInset = 24.0;
    const CGFloat available = MAX(environment.container.effectiveContentSize.width - 2.0 * horizontalInset, minWidth);

    NSInteger columns = MAX(1, (NSInteger)floor((available + colSpacing) / (minWidth + colSpacing)));
    CGFloat itemWidth = (available - (columns - 1) * colSpacing) / columns;
    while (itemWidth > maxWidth) {
        columns += 1;
        itemWidth = (available - (columns - 1) * colSpacing) / columns;
    }
    itemWidth = floor(itemWidth);
    const CGFloat itemHeight = ceil(itemWidth * 9.0 / 16.0 + 76.0);

    NSCollectionLayoutSize *itemSize =
        [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension absoluteDimension:itemWidth]
                                       heightDimension:[NSCollectionLayoutDimension absoluteDimension:itemHeight]];
    NSCollectionLayoutItem *item = [NSCollectionLayoutItem itemWithLayoutSize:itemSize];

    NSCollectionLayoutSize *groupSize =
        [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1.0]
                                       heightDimension:[NSCollectionLayoutDimension absoluteDimension:itemHeight]];
    NSCollectionLayoutGroup *group =
        [NSCollectionLayoutGroup horizontalGroupWithLayoutSize:groupSize subitem:item count:columns];
    group.interItemSpacing = [NSCollectionLayoutSpacing fixedSpacing:colSpacing];

    NSCollectionLayoutSection *section = [NSCollectionLayoutSection sectionWithGroup:group];
    section.interGroupSpacing = rowSpacing;
    section.contentInsets = NSDirectionalEdgeInsetsMake(16.0, horizontalInset, 36.0, horizontalInset);

    if (hasHeader) {
        NSCollectionLayoutSize *headerSize =
            [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1.0]
                                           heightDimension:[NSCollectionLayoutDimension estimatedDimension:88.0]];
        NSCollectionLayoutBoundarySupplementaryItem *headerItem =
            [NSCollectionLayoutBoundarySupplementaryItem boundarySupplementaryItemWithLayoutSize:headerSize
                                                                                      elementKind:NSCollectionElementKindSectionHeader
                                                                                        alignment:NSRectAlignmentTop];
        section.boundarySupplementaryItems = @[headerItem];
    }
    return section;
}

@end

#pragma mark - Shared Actions

@implementation MacLCYouTubeActions

+ (void)playVideo:(MacLCYouTubeVideo *)video fromItem:(nullable NSCollectionViewItem *)cell window:(nullable NSWindow *)window
{
    if (video == nil) {
        return;
    }
    if ([cell respondsToSelector:@selector(setOpening:)]) {
        [(id)cell setOpening:YES];
    }
    NSWindow * const alertWindow = window ?: cell.view.window;

    [[MacLCYouTubeService sharedService] playVideo:video
                                           enqueue:NO
                                        completion:^(NSError * _Nullable error) {
        if ([cell respondsToSelector:@selector(setOpening:)]) {
            [(id)cell setOpening:NO];
        }
        if (error != nil) {
            NSAlert *alert = [[NSAlert alloc] init];
            alert.alertStyle = NSAlertStyleWarning;
            alert.messageText = _NS("Could Not Play Video");
            alert.informativeText = error.localizedDescription ?: _NS("An unknown error occurred while resolving the video.");
            [alert addButtonWithTitle:_NS("OK")];
            if (alertWindow != nil) {
                [alert beginSheetModalForWindow:alertWindow completionHandler:nil];
            } else {
                [alert runModal];
            }
        }
    }];
}

+ (void)enqueueVideo:(MacLCYouTubeVideo *)video
{
    if (video == nil) {
        return;
    }
    [[MacLCYouTubeService sharedService] playVideo:video enqueue:YES completion:nil];
}

+ (void)copyLinkOfVideo:(MacLCYouTubeVideo *)video
{
    if (video.watchURL == nil) {
        return;
    }
    NSPasteboard * const pb = [NSPasteboard generalPasteboard];
    [pb clearContents];
    [pb setString:video.watchURL.absoluteString forType:NSPasteboardTypeString];
}

+ (void)openInBrowser:(NSURL *)URL
{
    if (URL == nil) {
        return;
    }
    [[NSWorkspace sharedWorkspace] openURL:URL];
}

@end
