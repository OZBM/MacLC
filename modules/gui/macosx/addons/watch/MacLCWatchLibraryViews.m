/*****************************************************************************
 * MacLCWatchLibraryViews.m: how history, resume points and favorites show in
 * Watch: watched badges, progress bars, the favorite heart, Continue
 * Watching cards, the shared actions menu
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

#import "addons/watch/MacLCWatchLibraryViews.h"

#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

#import <vlc_common.h>

#import "addons/MacLCAddons.h"
#import "addons/watch/MacLCWatchComponents.h"
#import "addons/watch/MacLCWatchLibrary.h"
#import "extensions/NSString+Helpers.h"
#import "main/VLCMain.h"
#import "theme/MacLCDesign.h"

#pragma mark - Date Formatting Helper

static NSString *MacLCRelativeDateString(NSDate * _Nullable date)
{
    if (date == nil) {
        return @"";
    }

    NSCalendar * const calendar = [NSCalendar currentCalendar];
    if ([calendar isDateInToday:date]) {
        return _NS("Today");
    }
    if ([calendar isDateInYesterday:date]) {
        return _NS("Yesterday");
    }

    static NSDateFormatter *sSameYearFormatter = nil;
    static NSDateFormatter *sOtherYearFormatter = nil;
    static dispatch_once_t sOnceToken;
    dispatch_once(&sOnceToken, ^{
        sSameYearFormatter = [[NSDateFormatter alloc] init];
        sSameYearFormatter.dateFormat = @"MMM d";
        sOtherYearFormatter = [[NSDateFormatter alloc] init];
        sOtherYearFormatter.dateFormat = @"MMM d, yyyy";
    });

    const NSInteger currentYear = [calendar component:NSCalendarUnitYear fromDate:[NSDate date]];
    const NSInteger dateYear = [calendar component:NSCalendarUnitYear fromDate:date];
    if (currentYear == dateYear) {
        return [sSameYearFormatter stringFromDate:date];
    }
    return [sOtherYearFormatter stringFromDate:date];
}

#pragma mark - MacLCWatchProgressBar

@implementation MacLCWatchProgressBar

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        self.hidden = YES;
    }
    return self;
}

- (NSSize)intrinsicContentSize
{
    return NSMakeSize(NSViewNoIntrinsicMetric, 4.0);
}

- (void)setFraction:(double)fraction
{
    const double clamped = fmax(0.0, fmin(1.0, fraction));
    if (fabs(_fraction - clamped) > 0.001 || self.hidden != (clamped <= 0.0 || clamped >= 1.0)) {
        _fraction = clamped;
        self.hidden = (_fraction <= 0.0 || _fraction >= 1.0);
        [self setNeedsDisplay:YES];
    }
}

- (void)drawRect:(NSRect)dirtyRect
{
    const NSRect bounds = self.bounds;
    if (NSIsEmptyRect(bounds) || _fraction <= 0.0 || _fraction >= 1.0) {
        return;
    }

    const CGFloat radius = bounds.size.height / 2.0;
    NSBezierPath * const trackPath = [NSBezierPath bezierPathWithRoundedRect:bounds xRadius:radius yRadius:radius];
    [[NSColor colorWithWhite:1.0 alpha:0.30] setFill];
    [trackPath fill];

    const CGFloat fillWidth = ceil(bounds.size.width * (CGFloat)_fraction);
    if (fillWidth > 0.0) {
        const NSRect fillRect = NSMakeRect(bounds.origin.x, bounds.origin.y, MIN(fillWidth, bounds.size.width), bounds.size.height);
        NSBezierPath * const fillPath = [NSBezierPath bezierPathWithRoundedRect:fillRect xRadius:radius yRadius:radius];
        [[NSColor colorWithWhite:1.0 alpha:1.0] setFill];
        [fillPath fill];
    }
}

- (BOOL)isAccessibilityElement
{
    return YES;
}

- (NSAccessibilityRole)accessibilityRole
{
    return NSAccessibilityProgressIndicatorRole;
}

- (nullable id)accessibilityValue
{
    return @(_fraction);
}

@end

#pragma mark - MacLCWatchedBadge

@implementation MacLCWatchedBadge
{
    NSImageView *_imageView;
}

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        self.layer.cornerRadius = 12.0;
        self.layer.masksToBounds = YES;
        self.layer.backgroundColor = [NSColor colorWithWhite:0.0 alpha:0.45].CGColor;

        _imageView = [[NSImageView alloc] initWithFrame:NSZeroRect];
        _imageView.translatesAutoresizingMaskIntoConstraints = NO;
        _imageView.imageScaling = NSImageScaleProportionallyUpOrDown;
        _imageView.contentTintColor = NSColor.whiteColor;
        NSImageSymbolConfiguration * const config =
            [NSImageSymbolConfiguration configurationWithPointSize:12.0 weight:NSFontWeightBold];
        NSImage *symbol = [NSImage imageWithSystemSymbolName:@"checkmark" accessibilityDescription:nil];
        if (symbol != nil) {
            symbol = [symbol imageWithSymbolConfiguration:config];
        }
        _imageView.image = symbol;
        [self addSubview:_imageView];

        [NSLayoutConstraint activateConstraints:@[
            [_imageView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [_imageView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_imageView.widthAnchor constraintEqualToConstant:14.0],
            [_imageView.heightAnchor constraintEqualToConstant:14.0],
        ]];
    }
    return self;
}

- (void)viewDidChangeEffectiveAppearance
{
    [super viewDidChangeEffectiveAppearance];
    self.layer.backgroundColor = [NSColor colorWithWhite:0.0 alpha:0.45].CGColor;
}

- (NSSize)intrinsicContentSize
{
    return NSMakeSize(24.0, 24.0);
}

- (BOOL)isAccessibilityElement
{
    return YES;
}

- (NSAccessibilityRole)accessibilityRole
{
    return NSAccessibilityImageRole;
}

- (nullable NSString *)accessibilityLabel
{
    return _NS("Watched");
}

@end

#pragma mark - MacLCWatchFavoriteButton

@implementation MacLCWatchFavoriteButton
{
    MacLCAddonItem *_item;
}

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        _onPicture = YES;
        self.wantsLayer = YES;
        self.title = @"";
        self.bordered = NO;
        self.buttonType = NSButtonTypeMomentaryChange;
        self.imagePosition = NSImageOnly;
        self.imageScaling = NSImageScaleProportionallyUpOrDown;
        self.target = self;
        self.action = @selector(toggleFavorite:);

        [self updateVisuals];

        [NSNotificationCenter.defaultCenter addObserver:self
                                               selector:@selector(libraryDidChange:)
                                                   name:MacLCWatchLibraryDidChangeNotification
                                                 object:nil];
    }
    return self;
}

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self name:MacLCWatchLibraryDidChangeNotification object:nil];
}

- (NSSize)intrinsicContentSize
{
    return NSMakeSize(28.0, 28.0);
}

- (void)setOnPicture:(BOOL)onPicture
{
    if (_onPicture != onPicture) {
        _onPicture = onPicture;
        [self updateVisuals];
    }
}

- (void)configureWithItem:(nullable MacLCAddonItem *)item
{
    _item = item;
    [self updateVisuals];
}

- (void)updateVisuals
{
    if (_item == nil || _item.identifier.length == 0) {
        self.image = nil;
        self.hidden = YES;
        return;
    }

    const BOOL isFav = [MacLCWatchLibrary.sharedLibrary isFavorite:_item.identifier];
    NSString * const symbolName = isFav ? @"heart.fill" : @"heart";
    NSString * const label = isFav ? _NS("Remove from Favorites") : _NS("Add to Favorites");
    self.accessibilityLabel = label;
    self.toolTip = label;

    NSImageSymbolConfiguration * const config =
        [NSImageSymbolConfiguration configurationWithPointSize:14.0 weight:NSFontWeightMedium];
    NSImage *img = [NSImage imageWithSystemSymbolName:symbolName accessibilityDescription:nil];
    if (img != nil) {
        img = [img imageWithSymbolConfiguration:config];
    }
    self.image = img;

    if (_onPicture) {
        self.layer.cornerRadius = 14.0;
        self.layer.masksToBounds = YES;
        self.layer.backgroundColor = [NSColor colorWithWhite:0.0 alpha:0.45].CGColor;
        self.contentTintColor = isFav ? NSColor.systemPinkColor : NSColor.whiteColor;
    } else {
        self.layer.cornerRadius = 0.0;
        self.layer.backgroundColor = nil;
        self.contentTintColor = isFav ? NSColor.controlAccentColor : NSColor.secondaryLabelColor;
    }
}

- (void)toggleFavorite:(id)sender
{
    if (_item == nil || _item.identifier.length == 0) {
        return;
    }
    const BOOL isFav = [MacLCWatchLibrary.sharedLibrary isFavorite:_item.identifier];
    [MacLCWatchLibrary.sharedLibrary setFavorite:!isFav forItem:_item];
    [self updateVisuals];
}

- (void)libraryDidChange:(NSNotification *)note
{
    if (_item == nil || _item.identifier.length == 0) {
        return;
    }
    NSSet<NSString *> * const changed = note.userInfo[MacLCWatchLibraryChangedTitlesKey];
    if (changed == nil || [changed containsObject:_item.identifier]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self updateVisuals];
        });
    }
}

- (void)viewDidChangeEffectiveAppearance
{
    [super viewDidChangeEffectiveAppearance];
    if (_onPicture) {
        self.layer.backgroundColor = [NSColor colorWithWhite:0.0 alpha:0.45].CGColor;
    }
}

- (BOOL)isAccessibilityElement
{
    return YES;
}

- (NSAccessibilityRole)accessibilityRole
{
    return NSAccessibilityButtonRole;
}

- (nullable id)accessibilityValue
{
    if (_item == nil) {
        return nil;
    }
    return [MacLCWatchLibrary.sharedLibrary isFavorite:_item.identifier] ? _NS("Favorite") : nil;
}

@end

#pragma mark - Continue Watching Cards

NSUserInterfaceItemIdentifier const MacLCWatchContinueItemIdentifier = @"MacLCWatchContinueItemIdentifier";

@interface MacLCWatchContinueCardView : NSView

@property (nonatomic, weak) MacLCWatchContinueItem *item;
@property (nonatomic, readonly) NSView *cardWrapperView;
@property (nonatomic, readonly) NSView *cardContainerView;
@property (nonatomic, readonly) NSImageView *placeholderImageView;
@property (nonatomic, readonly) NSView *pictureImageView;
@property (nonatomic, readonly) CAGradientLayer *scrimLayer;
@property (nonatomic, readonly) MacLCWatchProgressBar *progressBar;
@property (nonatomic, readonly) NSView *playGlyphView;
@property (nonatomic, readonly) NSButton *optionsButton;
@property (nonatomic, readonly) CAShapeLayer *selectionRingLayer;
@property (nonatomic, readonly) NSTextField *titleLabel;
@property (nonatomic, readonly) NSTextField *resumeLabel;
@property (nonatomic, readonly) NSTextField *lastPlayedLabel;

@property (nonatomic, nullable) NSImage *image;
@property (nonatomic, assign) BOOL isHovered;

- (void)updateHoverState:(BOOL)hovered animated:(BOOL)animated;

@end

@implementation MacLCWatchContinueCardView
{
    NSTrackingArea *_trackingArea;
}

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;

        _cardWrapperView = [[NSView alloc] initWithFrame:NSZeroRect];
        _cardWrapperView.translatesAutoresizingMaskIntoConstraints = NO;
        _cardWrapperView.wantsLayer = YES;
        _cardWrapperView.layer.masksToBounds = NO;
        [self addSubview:_cardWrapperView];

        _cardContainerView = [[NSView alloc] initWithFrame:NSZeroRect];
        _cardContainerView.translatesAutoresizingMaskIntoConstraints = NO;
        _cardContainerView.wantsLayer = YES;
        _cardContainerView.layer.masksToBounds = YES;
        _cardContainerView.layer.cornerRadius = MacLCDesign.cornerRadiusMedium;
        _cardContainerView.layer.cornerCurve = kCACornerCurveContinuous;
        _cardContainerView.layer.borderWidth = 1.0;
        _cardContainerView.layer.borderColor = NSColor.separatorColor.CGColor;
        _cardContainerView.layer.backgroundColor = NSColor.quaternarySystemFillColor.CGColor;
        [_cardWrapperView addSubview:_cardContainerView];

        _placeholderImageView = [[NSImageView alloc] initWithFrame:NSZeroRect];
        _placeholderImageView.translatesAutoresizingMaskIntoConstraints = NO;
        _placeholderImageView.imageScaling = NSImageScaleProportionallyUpOrDown;
        _placeholderImageView.contentTintColor = NSColor.tertiaryLabelColor;
        NSImageSymbolConfiguration * const config =
            [NSImageSymbolConfiguration configurationWithPointSize:36.0 weight:NSFontWeightLight];
        NSImage *placeholder = [NSImage imageWithSystemSymbolName:@"play.tv" accessibilityDescription:nil];
        if (placeholder == nil) {
            placeholder = [NSImage imageWithSystemSymbolName:@"film" accessibilityDescription:nil];
        }
        if (placeholder != nil) {
            placeholder = [placeholder imageWithSymbolConfiguration:config];
        }
        _placeholderImageView.image = placeholder;
        [_cardContainerView addSubview:_placeholderImageView];

        _pictureImageView = [[NSView alloc] initWithFrame:NSZeroRect];
        _pictureImageView.translatesAutoresizingMaskIntoConstraints = NO;
        _pictureImageView.wantsLayer = YES;
        _pictureImageView.layer.contentsGravity = kCAGravityResizeAspectFill;
        _pictureImageView.layer.masksToBounds = YES;
        _pictureImageView.hidden = YES;
        [_cardContainerView addSubview:_pictureImageView];

        _scrimLayer = [CAGradientLayer layer];
        _scrimLayer.colors = @[
            (__bridge id)[NSColor colorWithWhite:0.0 alpha:0.0].CGColor,
            (__bridge id)[NSColor colorWithWhite:0.0 alpha:0.55].CGColor
        ];
        _scrimLayer.startPoint = CGPointMake(0.5, 0.0);
        _scrimLayer.endPoint = CGPointMake(0.5, 1.0);
        [_cardContainerView.layer addSublayer:_scrimLayer];

        _progressBar = [[MacLCWatchProgressBar alloc] initWithFrame:NSZeroRect];
        _progressBar.translatesAutoresizingMaskIntoConstraints = NO;
        [_cardContainerView addSubview:_progressBar];

        // Centered glass play glyph on hover
        NSView *playView = nil;
        if (@available(macOS 26.0, *)) {
            NSGlassEffectView * const glass = [[NSGlassEffectView alloc] initWithFrame:NSZeroRect];
            glass.style = NSGlassEffectViewStyleRegular;
            playView = glass;
        } else {
            NSVisualEffectView * const hud = [[NSVisualEffectView alloc] initWithFrame:NSZeroRect];
            hud.material = NSVisualEffectMaterialHUDWindow;
            hud.blendingMode = NSVisualEffectBlendingModeWithinWindow;
            hud.state = NSVisualEffectStateActive;
            playView = hud;
        }
        playView.translatesAutoresizingMaskIntoConstraints = NO;
        playView.wantsLayer = YES;
        playView.layer.cornerRadius = 22.0;
        playView.layer.masksToBounds = YES;
        playView.alphaValue = 0.0;
        _playGlyphView = playView;
        [_cardContainerView addSubview:_playGlyphView];

        NSImageView * const playIcon = [[NSImageView alloc] initWithFrame:NSZeroRect];
        playIcon.translatesAutoresizingMaskIntoConstraints = NO;
        playIcon.imageScaling = NSImageScaleProportionallyUpOrDown;
        playIcon.contentTintColor = NSColor.whiteColor;
        NSImageSymbolConfiguration * const playCfg =
            [NSImageSymbolConfiguration configurationWithPointSize:20.0 weight:NSFontWeightBold];
        NSImage *playImg = [NSImage imageWithSystemSymbolName:@"play.fill" accessibilityDescription:nil];
        if (playImg != nil) {
            playImg = [playImg imageWithSymbolConfiguration:playCfg];
        }
        playIcon.image = playImg;
        [_playGlyphView addSubview:playIcon];

        // "…" options button at top-trailing on hover
        _optionsButton = [[NSButton alloc] initWithFrame:NSZeroRect];
        _optionsButton.translatesAutoresizingMaskIntoConstraints = NO;
        _optionsButton.wantsLayer = YES;
        _optionsButton.title = @"";
        _optionsButton.bordered = NO;
        _optionsButton.buttonType = NSButtonTypeMomentaryChange;
        _optionsButton.imagePosition = NSImageOnly;
        _optionsButton.imageScaling = NSImageScaleProportionallyUpOrDown;
        _optionsButton.layer.cornerRadius = 14.0;
        _optionsButton.layer.masksToBounds = YES;
        _optionsButton.layer.backgroundColor = [NSColor colorWithWhite:0.0 alpha:0.45].CGColor;
        _optionsButton.contentTintColor = NSColor.whiteColor;
        NSImageSymbolConfiguration * const optCfg =
            [NSImageSymbolConfiguration configurationWithPointSize:14.0 weight:NSFontWeightMedium];
        NSImage *optImg = [NSImage imageWithSystemSymbolName:@"ellipsis" accessibilityDescription:nil];
        if (optImg != nil) {
            optImg = [optImg imageWithSymbolConfiguration:optCfg];
        }
        _optionsButton.image = optImg;
        _optionsButton.target = self;
        _optionsButton.action = @selector(showOptionsMenu:);
        _optionsButton.accessibilityLabel = _NS("More Options");
        _optionsButton.toolTip = _NS("More Options");
        _optionsButton.alphaValue = 0.0;
        [_cardContainerView addSubview:_optionsButton];

        _selectionRingLayer = [CAShapeLayer layer];
        _selectionRingLayer.fillColor = nil;
        _selectionRingLayer.strokeColor = MacLCDesign.accent.CGColor;
        _selectionRingLayer.lineWidth = 3.0;
        _selectionRingLayer.hidden = YES;
        [_cardWrapperView.layer addSublayer:_selectionRingLayer];

        _titleLabel = [NSTextField labelWithString:@""];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _titleLabel.font = [NSFont systemFontOfSize:MacLCDesign.body.pointSize weight:NSFontWeightMedium];
        _titleLabel.textColor = MacLCDesign.primaryLabel;
        _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _titleLabel.maximumNumberOfLines = 1;
        _titleLabel.selectable = NO;
        [self addSubview:_titleLabel];

        _resumeLabel = [NSTextField labelWithString:@""];
        _resumeLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _resumeLabel.font = MacLCDesign.subheadline;
        _resumeLabel.textColor = MacLCDesign.secondaryLabel;
        _resumeLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _resumeLabel.maximumNumberOfLines = 1;
        _resumeLabel.selectable = NO;
        [self addSubview:_resumeLabel];

        _lastPlayedLabel = [NSTextField labelWithString:@""];
        _lastPlayedLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _lastPlayedLabel.font = MacLCDesign.footnote;
        _lastPlayedLabel.textColor = MacLCDesign.tertiaryLabel;
        _lastPlayedLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _lastPlayedLabel.maximumNumberOfLines = 1;
        _lastPlayedLabel.selectable = NO;
        _lastPlayedLabel.hidden = YES;
        [self addSubview:_lastPlayedLabel];

        [NSLayoutConstraint activateConstraints:@[
            [_cardWrapperView.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_cardWrapperView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_cardWrapperView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_cardWrapperView.heightAnchor constraintEqualToAnchor:_cardWrapperView.widthAnchor multiplier:(9.0 / 16.0)],

            [_cardContainerView.topAnchor constraintEqualToAnchor:_cardWrapperView.topAnchor],
            [_cardContainerView.bottomAnchor constraintEqualToAnchor:_cardWrapperView.bottomAnchor],
            [_cardContainerView.leadingAnchor constraintEqualToAnchor:_cardWrapperView.leadingAnchor],
            [_cardContainerView.trailingAnchor constraintEqualToAnchor:_cardWrapperView.trailingAnchor],

            [_placeholderImageView.centerXAnchor constraintEqualToAnchor:_cardContainerView.centerXAnchor],
            [_placeholderImageView.centerYAnchor constraintEqualToAnchor:_cardContainerView.centerYAnchor],
            [_placeholderImageView.widthAnchor constraintEqualToConstant:40.0],
            [_placeholderImageView.heightAnchor constraintEqualToConstant:40.0],

            [_pictureImageView.topAnchor constraintEqualToAnchor:_cardContainerView.topAnchor],
            [_pictureImageView.bottomAnchor constraintEqualToAnchor:_cardContainerView.bottomAnchor],
            [_pictureImageView.leadingAnchor constraintEqualToAnchor:_cardContainerView.leadingAnchor],
            [_pictureImageView.trailingAnchor constraintEqualToAnchor:_cardContainerView.trailingAnchor],

            [_progressBar.leadingAnchor constraintEqualToAnchor:_cardContainerView.leadingAnchor],
            [_progressBar.trailingAnchor constraintEqualToAnchor:_cardContainerView.trailingAnchor],
            [_progressBar.bottomAnchor constraintEqualToAnchor:_cardContainerView.bottomAnchor],
            [_progressBar.heightAnchor constraintEqualToConstant:4.0],

            [_playGlyphView.centerXAnchor constraintEqualToAnchor:_cardContainerView.centerXAnchor],
            [_playGlyphView.centerYAnchor constraintEqualToAnchor:_cardContainerView.centerYAnchor],
            [_playGlyphView.widthAnchor constraintEqualToConstant:44.0],
            [_playGlyphView.heightAnchor constraintEqualToConstant:44.0],

            [playIcon.centerXAnchor constraintEqualToAnchor:_playGlyphView.centerXAnchor constant:1.0],
            [playIcon.centerYAnchor constraintEqualToAnchor:_playGlyphView.centerYAnchor],
            [playIcon.widthAnchor constraintEqualToConstant:20.0],
            [playIcon.heightAnchor constraintEqualToConstant:20.0],

            [_optionsButton.topAnchor constraintEqualToAnchor:_cardContainerView.topAnchor constant:8.0],
            [_optionsButton.trailingAnchor constraintEqualToAnchor:_cardContainerView.trailingAnchor constant:-8.0],
            [_optionsButton.widthAnchor constraintEqualToConstant:28.0],
            [_optionsButton.heightAnchor constraintEqualToConstant:28.0],

            [_titleLabel.topAnchor constraintEqualToAnchor:_cardWrapperView.bottomAnchor constant:8.0],
            [_titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_titleLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],

            [_resumeLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:2.0],
            [_resumeLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_resumeLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],

            [_lastPlayedLabel.topAnchor constraintEqualToAnchor:_resumeLabel.bottomAnchor constant:2.0],
            [_lastPlayedLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_lastPlayedLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        ]];
    }
    return self;
}

- (void)viewDidChangeEffectiveAppearance
{
    [super viewDidChangeEffectiveAppearance];
    _cardContainerView.layer.borderColor = NSColor.separatorColor.CGColor;
    _cardContainerView.layer.backgroundColor = NSColor.quaternarySystemFillColor.CGColor;
    _selectionRingLayer.strokeColor = MacLCDesign.accent.CGColor;
    _optionsButton.layer.backgroundColor = [NSColor colorWithWhite:0.0 alpha:0.45].CGColor;
}

- (void)layout
{
    [super layout];

    const NSRect bounds = _cardContainerView.bounds;
    const CGFloat scrimHeight = ceil(bounds.size.height * 0.45);
    _scrimLayer.frame = CGRectMake(0.0, 0.0, bounds.size.width, scrimHeight);

    const NSRect ringRect = NSInsetRect(bounds, -4.5, -4.5);
    const CGFloat cornerR = MacLCDesign.cornerRadiusMedium + 3.0;
    CGPathRef const path = CGPathCreateWithRoundedRect(NSRectToCGRect(ringRect), cornerR, cornerR, NULL);
    _selectionRingLayer.path = path;
    CGPathRelease(path);
}

- (void)setImage:(nullable NSImage *)image
{
    _image = image;
    if (image != nil) {
        _pictureImageView.layer.contents = image;
        _pictureImageView.hidden = NO;
        _placeholderImageView.hidden = YES;
    } else {
        _pictureImageView.layer.contents = nil;
        _pictureImageView.hidden = YES;
        _placeholderImageView.hidden = NO;
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
    if (_isHovered) {
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
    const CATransform3D targetTransform = (hovered && !MacLCDesign.reducedMotion)
        ? CATransform3DMakeScale(1.04, 1.04, 1.0)
        : CATransform3DIdentity;
    const float targetOpacity = hovered ? 0.30f : 0.0f;
    const CGFloat controlsAlpha = hovered ? 1.0 : 0.0;

    CALayer * const layer = _cardWrapperView.layer;
    if (layer == nil) {
        return;
    }

    if (!animated || MacLCDesign.reducedMotion) {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        [layer removeAnimationForKey:@"hoverTransform"];
        [layer removeAnimationForKey:@"hoverShadow"];
        layer.transform = targetTransform;
        layer.shadowColor = NSColor.blackColor.CGColor;
        layer.shadowRadius = 14.0;
        layer.shadowOffset = CGSizeMake(0.0, -6.0);
        layer.shadowOpacity = targetOpacity;
        _playGlyphView.alphaValue = controlsAlpha;
        _optionsButton.alphaValue = controlsAlpha;
        [CATransaction commit];
        return;
    }

    CALayer * const presentation = layer.presentationLayer ?: layer;
    CATransform3D const fromTransform = presentation.transform;
    const float fromOpacity = presentation.shadowOpacity;

    layer.transform = targetTransform;
    layer.shadowColor = NSColor.blackColor.CGColor;
    layer.shadowRadius = 14.0;
    layer.shadowOffset = CGSizeMake(0.0, -6.0);
    layer.shadowOpacity = targetOpacity;

    CASpringAnimation * const transformAnim = [CASpringAnimation animationWithKeyPath:@"transform"];
    transformAnim.damping = 15.0;
    transformAnim.stiffness = 260.0;
    transformAnim.mass = 1.0;
    transformAnim.duration = transformAnim.settlingDuration;
    transformAnim.fromValue = [NSValue valueWithCATransform3D:fromTransform];
    transformAnim.toValue = [NSValue valueWithCATransform3D:targetTransform];

    CASpringAnimation * const shadowAnim = [CASpringAnimation animationWithKeyPath:@"shadowOpacity"];
    shadowAnim.damping = 15.0;
    shadowAnim.stiffness = 260.0;
    shadowAnim.mass = 1.0;
    shadowAnim.duration = shadowAnim.settlingDuration;
    shadowAnim.fromValue = @(fromOpacity);
    shadowAnim.toValue = @(targetOpacity);

    [layer addAnimation:transformAnim forKey:@"hoverTransform"];
    [layer addAnimation:shadowAnim forKey:@"hoverShadow"];

    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx) {
        ctx.duration = MacLCDesign.motionQuickDuration;
        ctx.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
        self->_playGlyphView.animator.alphaValue = controlsAlpha;
        self->_optionsButton.animator.alphaValue = controlsAlpha;
    }];
}

/* The picture, the glass play glyph and the labels are decoration: the card
 * takes every click except the "…" button's, or the glyph swallows them. */
- (NSView *)hitTest:(NSPoint)point
{
    NSView * const hit = [super hitTest:point];
    if (hit == nil)
        return nil;
    if (!_optionsButton.hidden && [hit isDescendantOf:_optionsButton])
        return hit;
    return self;
}

- (void)mouseDown:(NSEvent *)event
{
    /* Handled here so that the matching mouseUp comes back to this view. */
}

- (void)mouseUp:(NSEvent *)event
{
    const NSPoint location = [self convertPoint:event.locationInWindow fromView:nil];
    if (NSPointInRect(location, _optionsButton.frame)) {
        return;
    }
    if (NSPointInRect(location, self.bounds)) {
        if (self.item.activationHandler != nil && self.item.entry != nil) {
            self.item.activationHandler(self.item.entry);
        }
    }
}

- (void)keyDown:(NSEvent *)event
{
    if (event.keyCode == 36 || event.keyCode == 76) {
        if (self.item.activationHandler != nil && self.item.entry != nil) {
            self.item.activationHandler(self.item.entry);
            return;
        }
    }
    [super keyDown:event];
}

- (NSMenu *)menuForEvent:(NSEvent *)event
{
    if (self.item.entry == nil) {
        return [super menuForEvent:event];
    }
    return [self buildActionsMenu];
}

- (NSMenu *)buildActionsMenu
{
    if (self.item.entry == nil) {
        return [[NSMenu alloc] initWithTitle:@""];
    }
    NSMenu * const menu = [MacLCWatchActions menuForItem:self.item.entry.item
                                                   video:nil
                                               inHistory:self.item.inHistory];
    if (self.item.detailsHandler != nil) {
        [menu addItem:[NSMenuItem separatorItem]];
        NSMenuItem * const detailsItem = [[NSMenuItem alloc] initWithTitle:_NS("Show Details")
                                                                    action:@selector(handleShowDetailsAction:)
                                                             keyEquivalent:@""];
        detailsItem.target = self;
        NSImageSymbolConfiguration * const config =
            [NSImageSymbolConfiguration configurationWithPointSize:14.0 weight:NSFontWeightRegular];
        NSImage *img = [NSImage imageWithSystemSymbolName:@"info.circle" accessibilityDescription:nil];
        if (img != nil) {
            img = [img imageWithSymbolConfiguration:config];
        }
        detailsItem.image = img;
        [menu addItem:detailsItem];
    }
    return menu;
}

- (void)showOptionsMenu:(id)sender
{
    NSMenu * const menu = [self buildActionsMenu];
    const NSRect buttonBounds = _optionsButton.bounds;
    const NSPoint location = NSMakePoint(0.0, buttonBounds.size.height + 4.0);
    [menu popUpMenuPositioningItem:nil atLocation:location inView:_optionsButton];
}

- (void)handleShowDetailsAction:(id)sender
{
    if (self.item.detailsHandler != nil && self.item.entry != nil) {
        self.item.detailsHandler(self.item.entry);
    }
}

- (BOOL)isAccessibilityElement
{
    return YES;
}

- (NSAccessibilityRole)accessibilityRole
{
    return NSAccessibilityButtonRole;
}

- (nullable NSArray *)accessibilityChildren
{
    return @[];
}

- (nullable NSString *)accessibilityLabel
{
    NSMutableArray<NSString *> * const parts = [NSMutableArray array];
    if (self.item.entry.item.name.length > 0) {
        [parts addObject:self.item.entry.item.name];
    }
    if (self.item.entry.resumeTarget.detailText.length > 0) {
        [parts addObject:self.item.entry.resumeTarget.detailText];
    }
    if (self.item.showsLastPlayed && self.lastPlayedLabel.stringValue.length > 0) {
        [parts addObject:self.lastPlayedLabel.stringValue];
    }
    return [parts componentsJoinedByString:@", "];
}

- (nullable id)accessibilityValue
{
    MacLCWatchProgress * const progress = self.item.entry.resumeTarget.progress;
    if (progress != nil && progress.canResume && progress.fraction > 0.0 && progress.fraction < 1.0) {
        return [NSString stringWithFormat:_NS("In progress, %ld %%"), (long)round(progress.fraction * 100)];
    }
    return nil;
}

- (BOOL)accessibilityPerformPress
{
    if (self.item.activationHandler != nil && self.item.entry != nil) {
        self.item.activationHandler(self.item.entry);
        return YES;
    }
    return NO;
}

@end

@implementation MacLCWatchContinueItem
{
    MacLCWatchImageRequest *_imageRequest;
}

+ (CGFloat)heightForWidth:(CGFloat)width
{
    const CGFloat cardHeight = ceil(width * 9.0 / 16.0);

    NSFont * const titleFont = [NSFont systemFontOfSize:MacLCDesign.body.pointSize weight:NSFontWeightMedium];
    const CGFloat titleHeight = ceil(titleFont.ascender - titleFont.descender + titleFont.leading);

    NSFont * const resumeFont = MacLCDesign.subheadline;
    const CGFloat resumeHeight = ceil(resumeFont.ascender - resumeFont.descender + resumeFont.leading);

    NSFont * const dateFont = MacLCDesign.footnote;
    const CGFloat dateHeight = ceil(dateFont.ascender - dateFont.descender + dateFont.leading);

    const CGFloat textHeight = titleHeight + 2.0 + resumeHeight + 2.0 + dateHeight;
    return cardHeight + 8.0 + textHeight;
}

- (void)loadView
{
    MacLCWatchContinueCardView * const view = [[MacLCWatchContinueCardView alloc] initWithFrame:NSZeroRect];
    view.item = self;
    self.view = view;
}

- (MacLCWatchContinueCardView *)cardView
{
    return (MacLCWatchContinueCardView *)self.view;
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
    _entry = nil;
    self.selected = NO;

    MacLCWatchContinueCardView * const v = self.cardView;
    v.image = nil;
    v.titleLabel.stringValue = @"";
    v.resumeLabel.stringValue = @"";
    v.lastPlayedLabel.stringValue = @"";
    v.lastPlayedLabel.hidden = YES;
    v.progressBar.fraction = 0.0;
    v.progressBar.hidden = YES;
    v.selectionRingLayer.hidden = YES;
    [v updateHoverState:NO animated:NO];
}

- (void)setSelected:(BOOL)selected
{
    [super setSelected:selected];
    self.cardView.selectionRingLayer.hidden = !selected;
}

- (void)setShowsLastPlayed:(BOOL)showsLastPlayed
{
    _showsLastPlayed = showsLastPlayed;
    self.cardView.lastPlayedLabel.hidden = !showsLastPlayed;
}

- (void)configureWithEntry:(MacLCWatchEntry *)entry
{
    _entry = entry;
    [_imageRequest cancel];
    _imageRequest = nil;

    MacLCWatchContinueCardView * const v = self.cardView;
    v.titleLabel.stringValue = entry.item.name ?: @"";
    v.resumeLabel.stringValue = entry.resumeTarget.detailText ?: @"";

    if (_showsLastPlayed && entry.lastPlayed != nil) {
        v.lastPlayedLabel.stringValue = MacLCRelativeDateString(entry.lastPlayed);
        v.lastPlayedLabel.hidden = NO;
    } else {
        v.lastPlayedLabel.stringValue = @"";
        v.lastPlayedLabel.hidden = YES;
    }

    MacLCWatchProgress * const progress = entry.resumeTarget.progress;
    if (progress != nil && progress.canResume && progress.fraction > 0.0 && progress.fraction < 1.0) {
        v.progressBar.fraction = progress.fraction;
        v.progressBar.hidden = NO;
    } else {
        v.progressBar.fraction = 0.0;
        v.progressBar.hidden = YES;
    }

    NSURL * const imageURL = entry.item.backgroundURL ?: entry.item.posterURL;
    if (imageURL != nil) {
        const CGFloat scale = self.view.window.backingScaleFactor > 0.0 ? self.view.window.backingScaleFactor : 2.0;
        const NSSize drawnSize = NSMakeSize(300.0, ceil(300.0 * 9.0 / 16.0));
        __weak typeof(self) weakSelf = self;
        MacLCWatchImageRequest *req = nil;
        NSImage * const cached = [MacLCWatchImageCache.sharedCache imageForURL:imageURL
                                                                    pointSize:drawnSize
                                                                        scale:scale
                                                                      request:&req
                                                                   completion:^(NSImage *image) {
            MacLCWatchContinueItem *strongSelf = weakSelf;
            if (strongSelf != nil && strongSelf.entry == entry) {
                strongSelf.cardView.image = image;
            }
        }];
        _imageRequest = req;
        v.image = cached;
    } else {
        v.image = nil;
    }
}

@end

#pragma mark - Layout (Library)

@implementation MacLCWatchLayout (Library)

+ (NSCollectionLayoutSection *)continueShelfSectionWithEnvironment:(id<NSCollectionLayoutEnvironment>)environment
{
    const CGFloat itemWidth = 300.0;
    const CGFloat itemHeight = [MacLCWatchContinueItem heightForWidth:itemWidth];

    NSCollectionLayoutSize * const itemSize =
        [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension absoluteDimension:itemWidth]
                                       heightDimension:[NSCollectionLayoutDimension absoluteDimension:itemHeight]];
    NSCollectionLayoutItem * const item = [NSCollectionLayoutItem itemWithLayoutSize:itemSize];

    NSCollectionLayoutSize * const groupSize =
        [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension absoluteDimension:itemWidth]
                                       heightDimension:[NSCollectionLayoutDimension absoluteDimension:itemHeight]];
    NSCollectionLayoutGroup * const group =
        [NSCollectionLayoutGroup horizontalGroupWithLayoutSize:groupSize subitems:@[item]];

    NSCollectionLayoutSection * const section = [NSCollectionLayoutSection sectionWithGroup:group];
    section.orthogonalScrollingBehavior = NSCollectionLayoutSectionOrthogonalScrollingBehaviorContinuousGroupLeadingBoundary;
    section.interGroupSpacing = 20.0;
    section.contentInsets = NSDirectionalEdgeInsetsMake(0.0, 40.0, 36.0, 40.0);
    section.boundarySupplementaryItems = @[[self headerSupplementaryItem]];
    return section;
}

+ (NSCollectionLayoutSection *)continueGridSectionWithEnvironment:(id<NSCollectionLayoutEnvironment>)environment
                                                        hasHeader:(BOOL)hasHeader
{
    const CGFloat minWidth = 280.0;
    const CGFloat maxWidth = 360.0;
    const CGFloat colSpacing = 20.0;
    const CGFloat rowSpacing = 28.0;
    const CGFloat horizontalInset = 40.0;
    const CGFloat available = MAX(environment.container.effectiveContentSize.width - 2.0 * horizontalInset, minWidth);

    NSInteger columns = MAX(1, (NSInteger)floor((available + colSpacing) / (minWidth + colSpacing)));
    CGFloat itemWidth = (available - (columns - 1) * colSpacing) / columns;
    while (itemWidth > maxWidth) {
        columns += 1;
        itemWidth = (available - (columns - 1) * colSpacing) / columns;
    }
    itemWidth = floor(itemWidth);
    const CGFloat itemHeight = [MacLCWatchContinueItem heightForWidth:itemWidth];

    NSCollectionLayoutSize * const itemSize =
        [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension absoluteDimension:itemWidth]
                                       heightDimension:[NSCollectionLayoutDimension absoluteDimension:itemHeight]];
    NSCollectionLayoutItem * const item = [NSCollectionLayoutItem itemWithLayoutSize:itemSize];

    NSCollectionLayoutSize * const groupSize =
        [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1.0]
                                       heightDimension:[NSCollectionLayoutDimension absoluteDimension:itemHeight]];
    NSCollectionLayoutGroup * const group =
        [NSCollectionLayoutGroup horizontalGroupWithLayoutSize:groupSize subitem:item count:columns];
    group.interItemSpacing = [NSCollectionLayoutSpacing fixedSpacing:colSpacing];

    NSCollectionLayoutSection * const section = [NSCollectionLayoutSection sectionWithGroup:group];
    section.interGroupSpacing = rowSpacing;
    section.contentInsets = NSDirectionalEdgeInsetsMake(16.0, horizontalInset, 36.0, horizontalInset);
    if (hasHeader) {
        section.boundarySupplementaryItems = @[[self headerSupplementaryItem]];
    }
    return section;
}

@end

#pragma mark - Actions Menu

@interface MacLCWatchMenuTarget : NSObject
@property (nonatomic, copy) void (^actionBlock)(void);
- (void)invoke:(id)sender;
@end

@implementation MacLCWatchMenuTarget
- (void)invoke:(id)sender
{
    if (self.actionBlock != nil) {
        self.actionBlock();
    }
}
@end

@implementation MacLCWatchActions

+ (NSMenu *)menuForItem:(MacLCAddonItem *)item
                  video:(nullable MacLCAddonVideo *)video
              inHistory:(BOOL)inHistory
{
    NSMenu * const menu = [[NSMenu alloc] initWithTitle:@""];
    menu.autoenablesItems = NO;
    if (item == nil || item.identifier.length == 0) {
        return menu;
    }

    NSMutableArray<MacLCWatchMenuTarget *> * const targets = [NSMutableArray array];

    void (^addMenuItem)(NSString *, NSString *, void (^)(void)) =
        ^(NSString *title, NSString *symbolName, void (^action)(void)) {
        NSMenuItem * const menuItem = [[NSMenuItem alloc] initWithTitle:title
                                                                 action:@selector(invoke:)
                                                          keyEquivalent:@""];
        MacLCWatchMenuTarget * const target = [[MacLCWatchMenuTarget alloc] init];
        target.actionBlock = action;
        [targets addObject:target];
        menuItem.target = target;

        if (symbolName.length > 0) {
            NSImageSymbolConfiguration * const config =
                [NSImageSymbolConfiguration configurationWithPointSize:14.0 weight:NSFontWeightRegular];
            NSImage *img = [NSImage imageWithSystemSymbolName:symbolName accessibilityDescription:nil];
            if (img != nil) {
                img = [img imageWithSymbolConfiguration:config];
            }
            menuItem.image = img;
        }
        [menu addItem:menuItem];
    };

    MacLCWatchLibrary * const library = MacLCWatchLibrary.sharedLibrary;
    const BOOL isFav = [library isFavorite:item.identifier];

    // 1. "Add to Favorites" / "Remove from Favorites" (heart / heart.slash)
    if (isFav) {
        addMenuItem(_NS("Remove from Favorites"), @"heart.slash", ^{
            [library setFavorite:NO forItem:item];
        });
    } else {
        addMenuItem(_NS("Add to Favorites"), @"heart", ^{
            [library setFavorite:YES forItem:item];
        });
    }

    // 2. "Mark as Watched" / "Mark as Unwatched" (checkmark.circle / arrow.counterclockwise.circle)
    const BOOL isSeries = [item.type.lowercaseString isEqualToString:@"series"] ||
                          [item.type.lowercaseString isEqualToString:@"tv"];
    if (video != nil) {
        MacLCWatchProgress * const progress = [library progressForTitle:item.identifier video:video.identifier];
        const BOOL isWatched = progress.isWatched;
        if (isWatched) {
            addMenuItem(_NS("Mark as Unwatched"), @"arrow.counterclockwise.circle", ^{
                [library markWatched:NO forItem:item video:video];
            });
        } else {
            addMenuItem(_NS("Mark as Watched"), @"checkmark.circle", ^{
                [library markWatched:YES forItem:item video:video];
            });
        }
    } else if (!isSeries) {
        MacLCWatchEntry * const entry = [library entryForTitle:item.identifier];
        const BOOL isWatched = entry.isWatched;
        if (isWatched) {
            addMenuItem(_NS("Mark as Unwatched"), @"arrow.counterclockwise.circle", ^{
                [library markWatched:NO forItem:item video:nil];
            });
        } else {
            addMenuItem(_NS("Mark as Watched"), @"checkmark.circle", ^{
                [library markWatched:YES forItem:item video:nil];
            });
        }
    }

    // 3. "Remove from Continue Watching" (xmark.circle; only for an entry that has a resume target)
    MacLCWatchEntry * const entry = [library entryForTitle:item.identifier];
    if (entry != nil && entry.resumeTarget != nil) {
        addMenuItem(_NS("Remove from Continue Watching"), @"xmark.circle", ^{
            [library removeFromHistory:item.identifier];
        });
    }

    // 4. "Remove from History" (only in the History section: pass inHistory:YES)
    if (inHistory) {
        addMenuItem(_NS("Remove from History"), @"trash", ^{
            [library removeFromHistory:item.identifier];
        });
    }

    objc_setAssociatedObject(menu, "MacLCWatchMenuTargetsKey", targets, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return menu;
}

@end
