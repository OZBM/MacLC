/*****************************************************************************
 * MacLCArtworkView.m: artwork with placeholder, badges, progress and hover
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

#import "medialib/components/MacLCArtworkView.h"
#import "medialib/data/MacLCArtworkLoader.h"
#import "medialib/data/MacLCLibraryStore.h"
#import "library/VLCLibraryDataTypes.h"
#import "theme/MacLCDesign.h"
#import "extensions/NSString+Helpers.h"

@interface MacLCBadgeCapsuleView : NSView

@property (nonatomic, readonly) NSTextField *label;

- (instancetype)initWithText:(NSString *)text;

@end

@implementation MacLCBadgeCapsuleView

- (instancetype)initWithText:(NSString *)text
{
    self = [super initWithFrame:NSZeroRect];
    if (self) {
        self.wantsLayer = YES;
        self.layer.masksToBounds = YES;
        self.layer.backgroundColor = [NSColor colorWithSRGBRed:0.0 green:0.0 blue:0.0 alpha:0.55].CGColor;
        self.translatesAutoresizingMaskIntoConstraints = NO;

        _label = [NSTextField labelWithString:text];
        _label.translatesAutoresizingMaskIntoConstraints = NO;
        _label.font = MacLCDesign.badgeFont;
        _label.textColor = NSColor.whiteColor;
        _label.alignment = NSTextAlignmentCenter;
        [self addSubview:_label];

        [NSLayoutConstraint activateConstraints:@[
            [_label.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:6.0],
            [_label.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-6.0],
            [_label.topAnchor constraintEqualToAnchor:self.topAnchor constant:2.0],
            [_label.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-2.0],
        ]];
    }
    return self;
}

- (void)layout
{
    [super layout];
    self.layer.cornerRadius = self.bounds.size.height / 2.0;
}

@end

@interface MacLCArtworkView ()

@property (nonatomic, strong) NSView *containerView;
@property (nonatomic, strong) NSImageView *imageView;
@property (nonatomic, strong) NSView *placeholderView;
@property (nonatomic, strong) NSImageView *placeholderImageView;
@property (nonatomic, strong) NSStackView *badgesStackView;
@property (nonatomic, strong) NSView *progressTrackView;
@property (nonatomic, strong) NSView *progressFillView;
@property (nonatomic, strong) NSLayoutConstraint *progressFillWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *badgesBottomConstraint;

@property (nonatomic, strong) NSView *scrimView;
@property (nonatomic, strong) NSButton *playButton;
@property (nonatomic, strong) CAShapeLayer *selectionRingLayer;
@property (nonatomic, strong) NSTrackingArea *trackingArea;

@property (nonatomic, strong) NSLayoutConstraint *aspectConstraint;
@property (nonatomic, weak) id<VLCMediaLibraryItemProtocol> representedItem;
@property (nonatomic, strong, nullable) MacLCArtworkRequest *artworkRequest;
@property (nonatomic, assign) BOOL isHovered;

@end

@implementation MacLCArtworkView

- (instancetype)initWithShape:(MacLCArtworkShape)shape
{
    self = [super initWithFrame:NSZeroRect];
    if (self) {
        _shape = shape;
        _progress = 0.0;
        _showsPlayAffordance = NO;
        _selected = NO;

        self.wantsLayer = YES;
        self.layer.masksToBounds = NO;
        self.translatesAutoresizingMaskIntoConstraints = NO;

        [self setupSubviews];
        [self updateAspectConstraint];

        [NSNotificationCenter.defaultCenter addObserver:self
                                               selector:@selector(artworkLoaderDidChange:)
                                                   name:MacLCArtworkLoaderArtworkDidChangeNotification
                                                 object:nil];
    }
    return self;
}

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [_artworkRequest cancel];
}

- (void)setupSubviews
{
    // Content container view: holds all visuals that clip to the shape
    _containerView = [[NSView alloc] initWithFrame:NSZeroRect];
    _containerView.wantsLayer = YES;
    _containerView.layer.masksToBounds = YES;
    _containerView.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_containerView];

    [NSLayoutConstraint activateConstraints:@[
        [_containerView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_containerView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_containerView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_containerView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
    ]];

    // Placeholder view
    _placeholderView = [[NSView alloc] initWithFrame:NSZeroRect];
    _placeholderView.wantsLayer = YES;
    _placeholderView.layer.backgroundColor = [NSColor quaternarySystemFillColor].CGColor;
    _placeholderView.translatesAutoresizingMaskIntoConstraints = NO;
    [_containerView addSubview:_placeholderView];

    _placeholderImageView = [[NSImageView alloc] initWithFrame:NSZeroRect];
    _placeholderImageView.imageScaling = NSImageScaleProportionallyUpOrDown;
    _placeholderImageView.contentTintColor = MacLCDesign.tertiaryLabel;
    _placeholderImageView.translatesAutoresizingMaskIntoConstraints = NO;
    [_placeholderView addSubview:_placeholderImageView];

    [NSLayoutConstraint activateConstraints:@[
        [_placeholderView.leadingAnchor constraintEqualToAnchor:_containerView.leadingAnchor],
        [_placeholderView.trailingAnchor constraintEqualToAnchor:_containerView.trailingAnchor],
        [_placeholderView.topAnchor constraintEqualToAnchor:_containerView.topAnchor],
        [_placeholderView.bottomAnchor constraintEqualToAnchor:_containerView.bottomAnchor],

        [_placeholderImageView.centerXAnchor constraintEqualToAnchor:_placeholderView.centerXAnchor],
        [_placeholderImageView.centerYAnchor constraintEqualToAnchor:_placeholderView.centerYAnchor],
        [_placeholderImageView.widthAnchor constraintEqualToConstant:40.0],
        [_placeholderImageView.heightAnchor constraintEqualToConstant:40.0],
    ]];

    // Main image view
    _imageView = [[NSImageView alloc] initWithFrame:NSZeroRect];
    _imageView.wantsLayer = YES;
    _imageView.layer.contentsGravity = kCAGravityResizeAspectFill;
    _imageView.imageScaling = NSImageScaleProportionallyUpOrDown;
    _imageView.translatesAutoresizingMaskIntoConstraints = NO;
    _imageView.hidden = YES;
    [_containerView addSubview:_imageView];

    [NSLayoutConstraint activateConstraints:@[
        [_imageView.leadingAnchor constraintEqualToAnchor:_containerView.leadingAnchor],
        [_imageView.trailingAnchor constraintEqualToAnchor:_containerView.trailingAnchor],
        [_imageView.topAnchor constraintEqualToAnchor:_containerView.topAnchor],
        [_imageView.bottomAnchor constraintEqualToAnchor:_containerView.bottomAnchor],
    ]];

    // Progress bar
    _progressTrackView = [[NSView alloc] initWithFrame:NSZeroRect];
    _progressTrackView.wantsLayer = YES;
    _progressTrackView.layer.masksToBounds = YES;
    _progressTrackView.layer.cornerRadius = 1.5;
    _progressTrackView.layer.backgroundColor = [NSColor.whiteColor colorWithAlphaComponent:0.35].CGColor;
    _progressTrackView.translatesAutoresizingMaskIntoConstraints = NO;
    _progressTrackView.hidden = YES;
    [_containerView addSubview:_progressTrackView];

    _progressFillView = [[NSView alloc] initWithFrame:NSZeroRect];
    _progressFillView.wantsLayer = YES;
    _progressFillView.layer.masksToBounds = YES;
    _progressFillView.layer.cornerRadius = 1.5;
    _progressFillView.layer.backgroundColor = MacLCDesign.accent.CGColor;
    _progressFillView.translatesAutoresizingMaskIntoConstraints = NO;
    [_progressTrackView addSubview:_progressFillView];

    _progressFillWidthConstraint = [_progressFillView.widthAnchor constraintEqualToConstant:0.0];

    [NSLayoutConstraint activateConstraints:@[
        [_progressTrackView.leadingAnchor constraintEqualToAnchor:_containerView.leadingAnchor constant:8.0],
        [_progressTrackView.trailingAnchor constraintEqualToAnchor:_containerView.trailingAnchor constant:-8.0],
        [_progressTrackView.bottomAnchor constraintEqualToAnchor:_containerView.bottomAnchor constant:-8.0],
        [_progressTrackView.heightAnchor constraintEqualToConstant:3.0],

        [_progressFillView.leadingAnchor constraintEqualToAnchor:_progressTrackView.leadingAnchor],
        [_progressFillView.topAnchor constraintEqualToAnchor:_progressTrackView.topAnchor],
        [_progressFillView.bottomAnchor constraintEqualToAnchor:_progressTrackView.bottomAnchor],
        _progressFillWidthConstraint,
    ]];

    // Badges stack view
    _badgesStackView = [[NSStackView alloc] initWithFrame:NSZeroRect];
    _badgesStackView.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    _badgesStackView.spacing = 4.0;
    _badgesStackView.alignment = NSLayoutAttributeCenterY;
    _badgesStackView.translatesAutoresizingMaskIntoConstraints = NO;
    _badgesStackView.hidden = YES;
    [_containerView addSubview:_badgesStackView];

    _badgesBottomConstraint = [_badgesStackView.bottomAnchor constraintEqualToAnchor:_containerView.bottomAnchor constant:-8.0];

    [NSLayoutConstraint activateConstraints:@[
        [_badgesStackView.leadingAnchor constraintEqualToAnchor:_containerView.leadingAnchor constant:8.0],
        _badgesBottomConstraint,
    ]];

    // Scrim overlay for hover
    _scrimView = [[NSView alloc] initWithFrame:NSZeroRect];
    _scrimView.wantsLayer = YES;
    _scrimView.layer.backgroundColor = [NSColor colorWithSRGBRed:0.0 green:0.0 blue:0.0 alpha:0.20].CGColor;
    _scrimView.translatesAutoresizingMaskIntoConstraints = NO;
    _scrimView.hidden = YES;
    [_containerView addSubview:_scrimView];

    [NSLayoutConstraint activateConstraints:@[
        [_scrimView.leadingAnchor constraintEqualToAnchor:_containerView.leadingAnchor],
        [_scrimView.trailingAnchor constraintEqualToAnchor:_containerView.trailingAnchor],
        [_scrimView.topAnchor constraintEqualToAnchor:_containerView.topAnchor],
        [_scrimView.bottomAnchor constraintEqualToAnchor:_containerView.bottomAnchor],
    ]];

    // Play affordance button
    _playButton = [[NSButton alloc] initWithFrame:NSZeroRect];
    _playButton.bordered = NO;
    _playButton.title = @"";
    _playButton.translatesAutoresizingMaskIntoConstraints = NO;
    _playButton.target = self;
    _playButton.action = @selector(playButtonClicked:);
    _playButton.hidden = YES;
    _playButton.accessibilityLabel = _NS("Play");
    _playButton.toolTip = _NS("Play");

    NSImageSymbolConfiguration *symConfig = [NSImageSymbolConfiguration configurationWithPointSize:34.0 weight:NSFontWeightRegular];
    NSImage *playImg = [NSImage imageWithSystemSymbolName:@"play.circle.fill" accessibilityDescription:_NS("Play")];
    if (playImg) {
        playImg = [playImg imageWithSymbolConfiguration:symConfig];
    }
    _playButton.image = playImg;
    _playButton.contentTintColor = NSColor.whiteColor;
    _playButton.wantsLayer = YES;
    _playButton.layer.shadowColor = NSColor.blackColor.CGColor;
    _playButton.layer.shadowOpacity = 0.5;
    _playButton.layer.shadowRadius = 4.0;
    _playButton.layer.shadowOffset = CGSizeMake(0, -2.0);

    [_containerView addSubview:_playButton];

    [NSLayoutConstraint activateConstraints:@[
        [_playButton.centerXAnchor constraintEqualToAnchor:_containerView.centerXAnchor],
        [_playButton.centerYAnchor constraintEqualToAnchor:_containerView.centerYAnchor],
        [_playButton.widthAnchor constraintEqualToConstant:44.0],
        [_playButton.heightAnchor constraintEqualToConstant:44.0],
    ]];

    // Selection ring layer (outside containerView so it never covers the picture)
    _selectionRingLayer = [CAShapeLayer layer];
    _selectionRingLayer.fillColor = nil;
    _selectionRingLayer.strokeColor = MacLCDesign.accent.CGColor;
    _selectionRingLayer.lineWidth = 3.0;
    _selectionRingLayer.hidden = YES;
    [self.layer addSublayer:_selectionRingLayer];

    [self updatePlaceholderSymbol];
}

- (void)updateAspectConstraint
{
    if (_aspectConstraint) {
        _aspectConstraint.active = NO;
    }
    if (_shape == MacLCArtworkShapeVideo) {
        _aspectConstraint = [self.heightAnchor constraintEqualToAnchor:self.widthAnchor multiplier:(9.0 / 16.0)];
    } else {
        _aspectConstraint = [self.heightAnchor constraintEqualToAnchor:self.widthAnchor multiplier:1.0];
    }
    _aspectConstraint.active = YES;
    [self updatePlaceholderSymbol];
}

- (void)setShape:(MacLCArtworkShape)shape
{
    if (_shape != shape) {
        _shape = shape;
        [self updateAspectConstraint];
        [self updateBadgesLayout];
        [self setNeedsLayout:YES];
    }
}

- (void)setImage:(nullable NSImage *)image
{
    _image = image;
    if (image) {
        _imageView.image = image;
        _imageView.hidden = NO;
        _placeholderView.hidden = YES;
    } else {
        _imageView.image = nil;
        _imageView.hidden = YES;
        _placeholderView.hidden = NO;
    }
}

- (void)setPlaceholderSymbolName:(nullable NSString *)placeholderSymbolName
{
    _placeholderSymbolName = [placeholderSymbolName copy];
    [self updatePlaceholderSymbol];
}

- (void)updatePlaceholderSymbol
{
    NSString *symbolName = _placeholderSymbolName;
    if (!symbolName) {
        switch (_shape) {
            case MacLCArtworkShapeVideo:
                symbolName = @"film";
                break;
            case MacLCArtworkShapeSquare:
                symbolName = @"music.note";
                break;
            case MacLCArtworkShapeCircle:
                symbolName = @"person.fill";
                break;
        }
    }
    NSImageSymbolConfiguration *config = [NSImageSymbolConfiguration configurationWithPointSize:36.0 weight:NSFontWeightLight];
    NSImage *symbol = [NSImage imageWithSystemSymbolName:symbolName accessibilityDescription:nil];
    if (symbol) {
        symbol = [symbol imageWithSymbolConfiguration:config];
    }
    _placeholderImageView.image = symbol;
}

- (void)setBadges:(NSArray<NSString *> *)badges
{
    _badges = [badges copy];
    [self updateBadgesLayout];
}

- (void)updateBadgesLayout
{
    for (NSView *subview in _badgesStackView.arrangedSubviews) {
        [_badgesStackView removeArrangedSubview:subview];
        [subview removeFromSuperview];
    }

    if (_shape != MacLCArtworkShapeVideo || _badges.count == 0) {
        _badgesStackView.hidden = YES;
        return;
    }

    _badgesStackView.hidden = NO;
    for (NSString *badgeText in _badges) {
        MacLCBadgeCapsuleView *capsule = [[MacLCBadgeCapsuleView alloc] initWithText:badgeText];
        [_badgesStackView addArrangedSubview:capsule];
    }
}

- (void)setProgress:(CGFloat)progress
{
    _progress = progress;
    if (progress > 0.0 && progress < 1.0) {
        _progressTrackView.hidden = NO;
        CGFloat availableWidth = MAX(0.0, self.bounds.size.width - 16.0);
        _progressFillWidthConstraint.constant = availableWidth * progress;

        _badgesBottomConstraint.active = NO;
        _badgesBottomConstraint = [_badgesStackView.bottomAnchor constraintEqualToAnchor:_progressTrackView.topAnchor constant:-6.0];
        _badgesBottomConstraint.active = YES;
    } else {
        _progressTrackView.hidden = YES;
        _progressFillWidthConstraint.constant = 0.0;

        _badgesBottomConstraint.active = NO;
        _badgesBottomConstraint = [_badgesStackView.bottomAnchor constraintEqualToAnchor:_containerView.bottomAnchor constant:-8.0];
        _badgesBottomConstraint.active = YES;
    }
}

- (void)setSelected:(BOOL)selected
{
    _selected = selected;
    _selectionRingLayer.hidden = !selected;
}

- (void)setShowsPlayAffordance:(BOOL)showsPlayAffordance
{
    _showsPlayAffordance = showsPlayAffordance;
    [self updateHoverAffordanceAnimated:NO];
}

- (void)updateHoverAffordanceAnimated:(BOOL)animated
{
    BOOL shouldShow = _isHovered && _showsPlayAffordance;
    _scrimView.hidden = !shouldShow;
    _playButton.hidden = !shouldShow;
    [self.window invalidateCursorRectsForView:self];
}

- (void)playButtonClicked:(id)sender
{
    if (self.playAction) {
        self.playAction();
    }
}

#pragma mark - Tracking and Hover Lift

- (void)updateTrackingAreas
{
    [super updateTrackingAreas];
    if (_trackingArea) {
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
    if (_isHovered && _showsPlayAffordance && !_playButton.hidden) {
        NSRect playRect = [self convertRect:_playButton.bounds fromView:_playButton];
        [self addCursorRect:playRect cursor:[NSCursor pointingHandCursor]];
    }
}

- (void)mouseEntered:(NSEvent *)event
{
    _isHovered = YES;
    [self applyHoverState:YES];
    [self updateHoverAffordanceAnimated:YES];
}

- (void)mouseExited:(NSEvent *)event
{
    _isHovered = NO;
    [self applyHoverState:NO];
    [self updateHoverAffordanceAnimated:YES];
}

- (void)applyHoverState:(BOOL)hovered
{
    NSTimeInterval duration = MacLCDesign.motionQuickDuration;
    BOOL reducedMotion = MacLCDesign.reducedMotion;

    [CATransaction begin];
    [CATransaction setAnimationDuration:duration];

    if (hovered) {
        self.layer.shadowColor = [NSColor colorWithSRGBRed:0.0 green:0.0 blue:0.0 alpha:0.25].CGColor;
        self.layer.shadowOpacity = 1.0;
        self.layer.shadowRadius = 12.0;
        self.layer.shadowOffset = CGSizeMake(0.0, -4.0);

        if (!reducedMotion) {
            self.layer.transform = CATransform3DMakeScale(1.02, 1.02, 1.0);
        }
    } else {
        self.layer.shadowOpacity = 0.0;
        self.layer.transform = CATransform3DIdentity;
    }

    [CATransaction commit];
}

#pragma mark - Layout

- (void)layout
{
    [super layout];

    CGFloat width = self.bounds.size.width;

    if (_shape == MacLCArtworkShapeCircle) {
        CGFloat radius = width / 2.0;
        _containerView.layer.cornerRadius = radius;
        _containerView.layer.cornerCurve = kCACornerCurveCircular;
    } else {
        _containerView.layer.cornerRadius = MacLCDesign.cornerRadiusMedium;
        _containerView.layer.cornerCurve = kCACornerCurveContinuous;
    }

    // Update selection ring path (3 pt stroke centered 4.5 pt outside bounds)
    NSRect ringRect = NSInsetRect(self.bounds, -4.5, -4.5);
    CGPathRef ringPath = NULL;
    if (_shape == MacLCArtworkShapeCircle) {
        ringPath = CGPathCreateWithEllipseInRect(NSRectToCGRect(ringRect), NULL);
    } else {
        CGFloat cornerR = MacLCDesign.cornerRadiusMedium + 3.0;
        ringPath = CGPathCreateWithRoundedRect(NSRectToCGRect(ringRect), cornerR, cornerR, NULL);
    }
    _selectionRingLayer.path = ringPath;
    CGPathRelease(ringPath);

    // Update progress fill width if progress is active
    if (_progress > 0.0 && _progress < 1.0) {
        CGFloat availableWidth = MAX(0.0, width - 16.0);
        _progressFillWidthConstraint.constant = availableWidth * _progress;
    }
}

#pragma mark - Artwork Loading

- (void)setArtworkFromItem:(nullable id<VLCMediaLibraryItemProtocol>)item
{
    if (_representedItem == item && _image != nil) {
        return;
    }

    [_artworkRequest cancel];
    _artworkRequest = nil;
    _representedItem = item;

    if (item == nil) {
        self.image = nil;
        return;
    }

    NSSize size = self.bounds.size;
    if (size.width <= 0.0 || size.height <= 0.0) {
        switch (_shape) {
            case MacLCArtworkShapeVideo:
                size = NSMakeSize(260.0, 146.0);
                break;
            case MacLCArtworkShapeSquare:
                size = NSMakeSize(180.0, 180.0);
                break;
            case MacLCArtworkShapeCircle:
                size = NSMakeSize(150.0, 150.0);
                break;
        }
    }

    CGFloat scale = self.window.backingScaleFactor;
    if (scale <= 0.0) {
        scale = NSScreen.mainScreen.backingScaleFactor ?: 2.0;
    }

    __weak typeof(self) weakSelf = self;
    MacLCArtworkRequest *req = nil;
    NSImage *cachedImage = [[MacLCArtworkLoader sharedLoader] artworkForItem:item
                                                                  pointSize:size
                                                                      scale:scale
                                                                    request:&req
                                                                 completion:^(NSImage * _Nullable image) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.image = image;
    }];

    _artworkRequest = req;
    if (cachedImage) {
        self.image = cachedImage;
    } else {
        self.image = nil;
    }
}

- (void)artworkLoaderDidChange:(NSNotification *)note
{
    if (_representedItem == nil) {
        return;
    }

    NSString *changedID = note.object;
    if ([changedID isKindOfClass:[NSString class]]) {
        NSString *currentID = MacLCLibraryItemIdentifier(_representedItem);
        if ([changedID isEqualToString:currentID]) {
            id<VLCMediaLibraryItemProtocol> item = _representedItem;
            _representedItem = nil;
            [self setArtworkFromItem:item];
        }
    }
}

@end
