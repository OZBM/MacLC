/*****************************************************************************
 * MacLCWatchDiscoveryViews.m: The Edit's collection cards, genre tiles, the
 * services bar and sheet, shelf headers that page, and how shelves scroll
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

#import "addons/watch/MacLCWatchDiscoveryViews.h"

#import <QuartzCore/QuartzCore.h>

#import <vlc_common.h>

#import "addons/MacLCAddons.h"
#import "addons/watch/MacLCExplainer.h"
#import "addons/watch/MacLCWatchComponents.h"
#import "addons/watch/MacLCWatchDiscovery.h"
#import "extensions/NSString+Helpers.h"
#import "main/VLCMain.h"
#import "theme/MacLCDesign.h"

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Color Mapping

NSColor *MacLCWatchColorNamed(NSString *name)
{
    if (name.length == 0) {
        return NSColor.systemBlueColor;
    }
    NSString * const lower = name.lowercaseString;
    if ([lower isEqualToString:@"red"]) {
        return NSColor.systemRedColor;
    } else if ([lower isEqualToString:@"orange"]) {
        return NSColor.systemOrangeColor;
    } else if ([lower isEqualToString:@"yellow"]) {
        return NSColor.systemYellowColor;
    } else if ([lower isEqualToString:@"green"]) {
        return NSColor.systemGreenColor;
    } else if ([lower isEqualToString:@"mint"]) {
        return NSColor.systemMintColor;
    } else if ([lower isEqualToString:@"teal"]) {
        return NSColor.systemTealColor;
    } else if ([lower isEqualToString:@"cyan"]) {
        return NSColor.systemCyanColor;
    } else if ([lower isEqualToString:@"blue"]) {
        return NSColor.systemBlueColor;
    } else if ([lower isEqualToString:@"indigo"]) {
        return NSColor.systemIndigoColor;
    } else if ([lower isEqualToString:@"purple"]) {
        return NSColor.systemPurpleColor;
    } else if ([lower isEqualToString:@"pink"]) {
        return NSColor.systemPinkColor;
    } else if ([lower isEqualToString:@"brown"]) {
        return NSColor.systemBrownColor;
    } else if ([lower isEqualToString:@"gray"] || [lower isEqualToString:@"grey"]) {
        return NSColor.systemGrayColor;
    }
    return NSColor.systemBlueColor;
}

#pragma mark - Shelf Scrolling

static NSHashTable<NSScrollView *> *sConfiguredShelfScrollViews = nil;
static dispatch_once_t sScrollerNotificationOnce;

@implementation MacLCWatchShelfScrolling

+ (nullable NSScrollView *)shelfScrollViewForView:(NSView *)view
                                   outerScrollView:(nullable NSScrollView *)outerScrollView
{
    NSView *v = view.superview;
    while (v != nil) {
        if ([v isKindOfClass:[NSScrollView class]]) {
            if (v != outerScrollView) {
                return (NSScrollView *)v;
            } else {
                return nil;
            }
        }
        v = v.superview;
    }
    return nil;
}

+ (void)configureShelfScrollView:(NSScrollView *)scrollView
{
    if (scrollView == nil) {
        return;
    }

    /* Shelves hide their scroll bar even with "Show scroll bars: Always" — justified by scroll-views.md (page controls present: chevrons). */
    scrollView.hasHorizontalScroller = NO;
    scrollView.hasVerticalScroller = NO;
    scrollView.horizontalScrollElasticity = NSScrollElasticityAllowed;
    scrollView.verticalScrollElasticity = NSScrollElasticityNone;
    scrollView.drawsBackground = NO;

    dispatch_once(&sScrollerNotificationOnce, ^{
        sConfiguredShelfScrollViews = [NSHashTable weakObjectsHashTable];
        [NSNotificationCenter.defaultCenter addObserverForName:NSPreferredScrollerStyleDidChangeNotification
                                                        object:nil
                                                         queue:[NSOperationQueue mainQueue]
                                                    usingBlock:^(NSNotification * _Nonnull note) {
            for (NSScrollView *sv in sConfiguredShelfScrollViews.allObjects) {
                sv.hasHorizontalScroller = NO;
                sv.hasVerticalScroller = NO;
            }
        }];
    });

    [sConfiguredShelfScrollViews addObject:scrollView];
}

+ (void)scrollShelf:(NSScrollView *)scrollView
          direction:(NSInteger)direction
          itemPitch:(CGFloat)itemPitch
{
    if (scrollView == nil || direction == 0) {
        return;
    }

    NSClipView * const clipView = scrollView.contentView;
    if (clipView == nil) {
        return;
    }

    const CGFloat currentX = clipView.bounds.origin.x;
    const CGFloat visibleWidth = clipView.bounds.size.width;
    const CGFloat contentWidth = scrollView.documentView ? scrollView.documentView.bounds.size.width : visibleWidth;
    const CGFloat maxX = MAX(0.0, contentWidth - visibleWidth);

    const CGFloat overlap = (itemPitch > 0.0) ? itemPitch : 188.0;
    const CGFloat pageSize = MAX(overlap, visibleWidth - overlap);

    CGFloat targetX = currentX + (direction > 0 ? pageSize : -pageSize);
    if (itemPitch > 0.0) {
        targetX = round(targetX / itemPitch) * itemPitch;
    }
    targetX = MAX(0.0, MIN(maxX, targetX));

    if (MacLCDesign.reducedMotion) {
        clipView.bounds = NSMakeRect(targetX, clipView.bounds.origin.y, clipView.bounds.size.width, clipView.bounds.size.height);
        [scrollView reflectScrolledClipView:clipView];
        return;
    }

    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = 0.45;
        context.timingFunction = [CAMediaTimingFunction functionWithControlPoints:0.2 :1.0 :0.3 :1.0];
        clipView.animator.bounds = NSMakeRect(targetX, clipView.bounds.origin.y, clipView.bounds.size.width, clipView.bounds.size.height);
    } completionHandler:^{
        [scrollView reflectScrolledClipView:clipView];
    }];
}

+ (BOOL)shelf:(NSScrollView *)scrollView canScrollInDirection:(NSInteger)direction
{
    if (scrollView == nil || direction == 0) {
        return NO;
    }
    NSClipView * const clipView = scrollView.contentView;
    if (clipView == nil) {
        return NO;
    }
    const CGFloat currentX = clipView.bounds.origin.x;
    const CGFloat visibleWidth = clipView.bounds.size.width;
    const CGFloat contentWidth = scrollView.documentView ? scrollView.documentView.bounds.size.width : visibleWidth;
    const CGFloat maxX = MAX(0.0, contentWidth - visibleWidth);

    if (direction < 0) {
        return currentX > 1.0;
    } else {
        return currentX < maxX - 1.0;
    }
}

@end

#pragma mark - Shelf Header Components

@interface MacLCWatchCirclePagingButton : NSButton
@property (nonatomic, assign) BOOL isHovered;
@property (nonatomic, strong, nullable) NSTrackingArea *trackingArea;
@end

@implementation MacLCWatchCirclePagingButton

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        self.bordered = NO;
        self.wantsLayer = YES;
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.layer.masksToBounds = YES;
        self.layer.cornerRadius = 13.0; // 26 pt circle
        self.layer.backgroundColor = NSColor.quaternarySystemFillColor.CGColor;
        self.contentTintColor = NSColor.labelColor;
        self.imagePosition = NSImageOnly;
    }
    return self;
}

- (void)viewDidChangeEffectiveAppearance
{
    [super viewDidChangeEffectiveAppearance];
    [self updateBackgroundAnimated:NO];
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
    if (self.isEnabled) {
        [self addCursorRect:self.bounds cursor:NSCursor.pointingHandCursor];
    }
}

- (void)mouseEntered:(NSEvent *)event
{
    _isHovered = YES;
    [self updateBackgroundAnimated:YES];
}

- (void)mouseExited:(NSEvent *)event
{
    _isHovered = NO;
    [self updateBackgroundAnimated:YES];
}

- (void)setEnabled:(BOOL)enabled
{
    [super setEnabled:enabled];
    self.alphaValue = enabled ? 1.0 : 0.35;
    [self updateBackgroundAnimated:NO];
    [self.window invalidateCursorRectsForView:self];
}

- (void)updateBackgroundAnimated:(BOOL)animated
{
    CGColorRef const targetColor = (_isHovered && self.isEnabled)
        ? NSColor.tertiarySystemFillColor.CGColor
        : NSColor.quaternarySystemFillColor.CGColor;

    if (!animated || MacLCDesign.reducedMotion) {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        self.layer.backgroundColor = targetColor;
        [CATransaction commit];
    } else {
        [CATransaction begin];
        [CATransaction setAnimationDuration:MacLCDesign.motionQuickDuration];
        self.layer.backgroundColor = targetColor;
        [CATransaction commit];
    }
}

@end

@interface MacLCWatchShelfActionButton : NSButton
@property (nonatomic, assign) BOOL isHovered;
@property (nonatomic, strong, nullable) NSTrackingArea *trackingArea;
@end

@implementation MacLCWatchShelfActionButton

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        self.bordered = NO;
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.font = MacLCDesign.subheadline;
        self.contentTintColor = MacLCDesign.secondaryLabel;
    }
    return self;
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
    if (self.isEnabled) {
        [self addCursorRect:self.bounds cursor:NSCursor.pointingHandCursor];
    }
}

- (void)mouseEntered:(NSEvent *)event
{
    _isHovered = YES;
    [self updateTintColorAnimated:YES];
}

- (void)mouseExited:(NSEvent *)event
{
    _isHovered = NO;
    [self updateTintColorAnimated:YES];
}

- (void)updateTintColorAnimated:(BOOL)animated
{
    NSColor * const targetColor = _isHovered ? MacLCDesign.accent : MacLCDesign.secondaryLabel;
    if (!animated || MacLCDesign.reducedMotion) {
        self.contentTintColor = targetColor;
    } else {
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = MacLCDesign.motionQuickDuration;
            self.contentTintColor = targetColor;
        }];
    }
}

@end

#pragma mark - Shelf Header View

NSUserInterfaceItemIdentifier const MacLCWatchShelfHeaderIdentifier = @"MacLCWatchShelfHeaderIdentifier";

@interface MacLCWatchShelfHeaderView ()
{
    NSTextField *_titleLabel;
    NSTextField *_subtitleLabel;
    NSButton *_infoButton;
    MacLCWatchShelfActionButton *_actionButton;
    MacLCWatchCirclePagingButton *_prevButton;
    MacLCWatchCirclePagingButton *_nextButton;

    NSLayoutConstraint *_titleCenterYConstraint;
    NSLayoutConstraint *_titleTopConstraint;
    NSLayoutConstraint *_infoLeadingConstraint;
}
@end

@implementation MacLCWatchShelfHeaderView

+ (CGFloat)heightWithSubtitle:(BOOL)hasSubtitle
{
    return hasSubtitle ? 58.0 : 44.0;
}

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        [self setUpHeaderViews];
    }
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (self) {
        [self setUpHeaderViews];
    }
    return self;
}

- (void)setUpHeaderViews
{
    self.wantsLayer = YES;
    _showsPaging = YES;
    _canPageBack = NO;
    _canPageForward = NO;

    _titleLabel = [NSTextField labelWithString:@""];
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _titleLabel.font = [NSFont systemFontOfSize:MacLCDesign.title2.pointSize weight:NSFontWeightBold];
    _titleLabel.textColor = NSColor.labelColor;
    _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    _titleLabel.selectable = NO;
    _titleLabel.accessibilityRole = NSAccessibilityHeadingRole;
    [self addSubview:_titleLabel];

    _subtitleLabel = [NSTextField labelWithString:@""];
    _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _subtitleLabel.font = MacLCDesign.subheadline;
    _subtitleLabel.textColor = MacLCDesign.secondaryLabel;
    _subtitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    _subtitleLabel.selectable = NO;
    _subtitleLabel.hidden = YES;
    [self addSubview:_subtitleLabel];

    _actionButton = [[MacLCWatchShelfActionButton alloc] initWithFrame:NSZeroRect];
    _actionButton.target = self;
    _actionButton.action = @selector(actionButtonClicked:);
    _actionButton.hidden = YES;
    [self addSubview:_actionButton];

    NSImageSymbolConfiguration * const symConfig =
        [NSImageSymbolConfiguration configurationWithPointSize:13.0 weight:NSFontWeightSemibold];

    _prevButton = [[MacLCWatchCirclePagingButton alloc] initWithFrame:NSMakeRect(0, 0, 26, 26)];
    NSImage *prevImg = [NSImage imageWithSystemSymbolName:@"chevron.left" accessibilityDescription:_NS("Previous")];
    if (prevImg != nil) {
        prevImg = [prevImg imageWithSymbolConfiguration:symConfig];
    }
    _prevButton.image = prevImg;
    _prevButton.target = self;
    _prevButton.action = @selector(prevButtonClicked:);
    _prevButton.enabled = NO;
    [self addSubview:_prevButton];

    _nextButton = [[MacLCWatchCirclePagingButton alloc] initWithFrame:NSMakeRect(0, 0, 26, 26)];
    NSImage *nextImg = [NSImage imageWithSystemSymbolName:@"chevron.right" accessibilityDescription:_NS("Next")];
    if (nextImg != nil) {
        nextImg = [nextImg imageWithSymbolConfiguration:symConfig];
    }
    _nextButton.image = nextImg;
    _nextButton.target = self;
    _nextButton.action = @selector(nextButtonClicked:);
    _nextButton.enabled = NO;
    [self addSubview:_nextButton];

    _titleCenterYConstraint = [_titleLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor];
    _titleTopConstraint = [_titleLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:6.0];

    [NSLayoutConstraint activateConstraints:@[
        [_titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        _titleCenterYConstraint,

        [_subtitleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_subtitleLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:2.0],

        [_nextButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_nextButton.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_nextButton.widthAnchor constraintEqualToConstant:26.0],
        [_nextButton.heightAnchor constraintEqualToConstant:26.0],

        [_prevButton.trailingAnchor constraintEqualToAnchor:_nextButton.leadingAnchor constant:-6.0],
        [_prevButton.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_prevButton.widthAnchor constraintEqualToConstant:26.0],
        [_prevButton.heightAnchor constraintEqualToConstant:26.0],

        [_actionButton.trailingAnchor constraintEqualToAnchor:_prevButton.leadingAnchor constant:-12.0],
        [_actionButton.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
    ]];
}

- (void)setTitle:(NSString *)title
{
    _title = [title copy];
    _titleLabel.stringValue = title ?: @"";
    [self updatePagingAccessibility];
}

- (void)setSubtitle:(nullable NSString *)subtitle
{
    _subtitle = [subtitle copy];
    const BOOL hasSubtitle = (subtitle.length > 0);
    _subtitleLabel.stringValue = subtitle ?: @"";
    _subtitleLabel.hidden = !hasSubtitle;

    if (hasSubtitle) {
        _titleCenterYConstraint.active = NO;
        _titleTopConstraint.active = YES;
    } else {
        _titleTopConstraint.active = NO;
        _titleCenterYConstraint.active = YES;
    }
}

- (void)setExplainerTopic:(nullable NSString *)explainerTopic
{
    _explainerTopic = [explainerTopic copy];
    if (_infoButton != nil) {
        [_infoButton removeFromSuperview];
        _infoButton = nil;
    }
    if (explainerTopic.length > 0) {
        _infoButton = [MacLCExplainer infoButtonForTopic:(MacLCExplainerTopic)explainerTopic];
        _infoButton.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_infoButton];
        [NSLayoutConstraint activateConstraints:@[
            [_infoButton.leadingAnchor constraintEqualToAnchor:_titleLabel.trailingAnchor constant:6.0],
            [_infoButton.centerYAnchor constraintEqualToAnchor:_titleLabel.centerYAnchor],
            [_infoButton.widthAnchor constraintEqualToConstant:22.0],
            [_infoButton.heightAnchor constraintEqualToConstant:22.0],
        ]];
    }
}

- (void)setActionTitle:(nullable NSString *)actionTitle
{
    _actionTitle = [actionTitle copy];
    const BOOL hasAction = (actionTitle.length > 0);
    _actionButton.title = actionTitle ?: @"";
    _actionButton.hidden = !hasAction;
}

/* Chevrons only where there is somewhere to go: a shelf that fits shows none. */
- (void)updatePagingVisibility
{
    const BOOL hidden = !_showsPaging || (!_canPageBack && !_canPageForward);
    _prevButton.hidden = hidden;
    _nextButton.hidden = hidden;
}

- (void)setShowsPaging:(BOOL)showsPaging
{
    _showsPaging = showsPaging;
    [self updatePagingVisibility];
}

- (void)setCanPageBack:(BOOL)canPageBack
{
    _canPageBack = canPageBack;
    _prevButton.enabled = canPageBack;
    [self updatePagingVisibility];
}

- (void)setCanPageForward:(BOOL)canPageForward
{
    _canPageForward = canPageForward;
    _nextButton.enabled = canPageForward;
    [self updatePagingVisibility];
}

- (void)updatePagingAccessibility
{
    NSString * const t = self.title ?: @"";
    _prevButton.accessibilityLabel = [NSString stringWithFormat:_NS("Previous %@"), t];
    _nextButton.accessibilityLabel = [NSString stringWithFormat:_NS("Next %@"), t];
}

- (void)actionButtonClicked:(id)sender
{
    if (self.action != nil) {
        self.action();
    }
}

- (void)prevButtonClicked:(id)sender
{
    if (self.pageHandler != nil) {
        self.pageHandler(-1);
    }
}

- (void)nextButtonClicked:(id)sender
{
    if (self.pageHandler != nil) {
        self.pageHandler(+1);
    }
}

- (void)prepareForReuse
{
    self.title = @"";
    self.subtitle = nil;
    self.explainerTopic = nil;
    self.actionTitle = nil;
    self.action = nil;
    self.pageHandler = nil;
    self.showsPaging = YES;
    self.canPageBack = NO;
    self.canPageForward = NO;
}

@end

#pragma mark - Collection Card (The Edit)

NSUserInterfaceItemIdentifier const MacLCWatchCollectionCardIdentifier = @"MacLCWatchCollectionCardIdentifier";

@interface MacLCWatchCollectionCardView : NSView
@property (nonatomic, weak) MacLCWatchCollectionCard *item;
@property (nonatomic, strong) CAGradientLayer *gradientLayer;
@property (nonatomic, strong) NSImageView *symbolImageView;
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSTextField *subtitleLabel;
@property (nonatomic, strong) NSTextField *countLabel;
@property (nonatomic, strong) CAShapeLayer *focusRingLayer;

@property (nonatomic, strong) NSArray<NSView *> *posterViews;
@property (nonatomic, strong) NSArray<NSImageView *> *posterImageViews;
@property (nonatomic, assign) BOOL isHovered;

- (void)updateHoverState:(BOOL)hovered animated:(BOOL)animated;
- (void)applyCollection:(MacLCWatchCollection *)collection;
@end

/* AppKit anchors a view's layer at its corner: turn about the centre. */
static CATransform3D MacLCRotationAboutCentre(CGFloat radians, NSSize size)
{
    CATransform3D t = CATransform3DMakeTranslation(size.width / 2.0, size.height / 2.0, 0.0);
    t = CATransform3DRotate(t, radians, 0.0, 0.0, 1.0);
    return CATransform3DTranslate(t, -size.width / 2.0, -size.height / 2.0, 0.0);
}

@implementation MacLCWatchCollectionCardView
{
    NSTrackingArea *_trackingArea;
}

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        self.layer.masksToBounds = NO;

        _gradientLayer = [CAGradientLayer layer];
        _gradientLayer.cornerRadius = MacLCDesign.cornerRadiusLarge;
        _gradientLayer.cornerCurve = kCACornerCurveContinuous;
        _gradientLayer.borderWidth = 1.0;
        _gradientLayer.borderColor = NSColor.separatorColor.CGColor;
        _gradientLayer.startPoint = CGPointMake(0.0, 0.0);
        _gradientLayer.endPoint = CGPointMake(1.0, 1.0);
        [self.layer addSublayer:_gradientLayer];

        _focusRingLayer = [CAShapeLayer layer];
        _focusRingLayer.fillColor = nil;
        _focusRingLayer.strokeColor = MacLCDesign.accent.CGColor;
        _focusRingLayer.lineWidth = 3.0;
        _focusRingLayer.hidden = YES;
        [self.layer addSublayer:_focusRingLayer];

        _symbolImageView = [[NSImageView alloc] initWithFrame:NSZeroRect];
        _symbolImageView.translatesAutoresizingMaskIntoConstraints = NO;
        _symbolImageView.imageScaling = NSImageScaleProportionallyUpOrDown;
        [self addSubview:_symbolImageView];

        _titleLabel = [NSTextField wrappingLabelWithString:@""];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _titleLabel.font = [NSFont systemFontOfSize:MacLCDesign.title2.pointSize weight:NSFontWeightBold];
        _titleLabel.textColor = NSColor.labelColor;
        _titleLabel.maximumNumberOfLines = 3;
        _titleLabel.lineBreakMode = NSLineBreakByWordWrapping;
        _titleLabel.cell.truncatesLastVisibleLine = YES;
        _titleLabel.selectable = NO;
        [self addSubview:_titleLabel];

        _subtitleLabel = [NSTextField wrappingLabelWithString:@""];
        _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _subtitleLabel.font = MacLCDesign.subheadline;
        _subtitleLabel.textColor = MacLCDesign.secondaryLabel;
        _subtitleLabel.maximumNumberOfLines = 3;
        _subtitleLabel.lineBreakMode = NSLineBreakByWordWrapping;
        _subtitleLabel.cell.truncatesLastVisibleLine = YES;
        _subtitleLabel.selectable = NO;
        [self addSubview:_subtitleLabel];

        _countLabel = [NSTextField labelWithString:@""];
        _countLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _countLabel.font = [NSFont systemFontOfSize:MacLCDesign.footnote.pointSize weight:NSFontWeightSemibold];
        _countLabel.selectable = NO;
        [self addSubview:_countLabel];

        NSMutableArray<NSView *> *pViews = [NSMutableArray arrayWithCapacity:3];
        NSMutableArray<NSImageView *> *imgViews = [NSMutableArray arrayWithCapacity:3];

        for (NSInteger i = 0; i < 3; i++) {
            NSView *pView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 82, 123)];
            pView.wantsLayer = YES;
            pView.layer.masksToBounds = NO;
            pView.layer.cornerRadius = MacLCDesign.cornerRadiusSmall;
            pView.layer.cornerCurve = kCACornerCurveContinuous;
            pView.layer.shadowColor = NSColor.blackColor.CGColor;
            pView.layer.shadowRadius = 8.0;
            pView.layer.shadowOffset = CGSizeMake(0.0, -3.0);
            pView.layer.shadowOpacity = 0.25;

            NSImageView *iv = [[NSImageView alloc] initWithFrame:NSMakeRect(0, 0, 82, 123)];
            iv.wantsLayer = YES;
            iv.layer.masksToBounds = YES;
            iv.layer.cornerRadius = MacLCDesign.cornerRadiusSmall;
            iv.layer.cornerCurve = kCACornerCurveContinuous;
            iv.layer.backgroundColor = NSColor.quaternarySystemFillColor.CGColor;
            iv.imageScaling = NSImageScaleProportionallyUpOrDown;
            [pView addSubview:iv];

            [pViews addObject:pView];
            [imgViews addObject:iv];
        }

        /* Order: poster 0 at back, poster 2 in middle, poster 1 (middle) in front. */
        [self addSubview:pViews[0]];
        [self addSubview:pViews[2]];
        [self addSubview:pViews[1]];

        _posterViews = [pViews copy];
        _posterImageViews = [imgViews copy];

        [NSLayoutConstraint activateConstraints:@[
            [_symbolImageView.topAnchor constraintEqualToAnchor:self.topAnchor constant:18.0],
            [_symbolImageView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:18.0],
            [_symbolImageView.widthAnchor constraintEqualToConstant:24.0],
            [_symbolImageView.heightAnchor constraintEqualToConstant:24.0],

            [_titleLabel.topAnchor constraintEqualToAnchor:_symbolImageView.bottomAnchor constant:10.0],
            [_titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:18.0],
            [_titleLabel.widthAnchor constraintLessThanOrEqualToConstant:144.0],

            [_subtitleLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:6.0],
            [_subtitleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:18.0],
            [_subtitleLabel.widthAnchor constraintLessThanOrEqualToConstant:144.0],

            [_countLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:18.0],
            [_countLabel.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-18.0],
        ]];
    }
    return self;
}

- (void)layout
{
    [super layout];
    _gradientLayer.frame = self.bounds;

    const NSRect ringRect = NSInsetRect(self.bounds, -4.5, -4.5);
    const CGFloat cornerR = MacLCDesign.cornerRadiusLarge + 3.0;
    CGPathRef const path = CGPathCreateWithRoundedRect(NSRectToCGRect(ringRect), cornerR, cornerR, NULL);
    _focusRingLayer.path = path;
    CGPathRelease(path);

    /* Poster positions: bottoms 18 pt from card bottom.
     * Card height 216: bottom at 18 pt means Y = 18 in unflipped coordinates (or 216 - 18 - 123 in flipped). */
    const CGFloat posterY = self.isFlipped ? (self.bounds.size.height - 18.0 - 123.0) : 18.0;
    /* The fan lives right of the 144 pt text column (16 + 144) and inside
     * the 340 pt card, open or closed. */
    const CGFloat midX = 246.0;
    const CGFloat spread = 36.0;

    _posterViews[0].frame = NSMakeRect(midX - spread - 41.0, posterY, 82.0, 123.0);
    _posterViews[1].frame = NSMakeRect(midX - 41.0, posterY, 82.0, 123.0);
    _posterViews[2].frame = NSMakeRect(midX + spread - 41.0, posterY, 82.0, 123.0);

    for (NSImageView *iv in _posterImageViews) {
        iv.frame = NSMakeRect(0, 0, 82.0, 123.0);
    }

    [self updateHoverState:_isHovered animated:NO];
}

- (void)applyCollection:(MacLCWatchCollection *)collection
{
    NSColor * const tint = MacLCWatchColorNamed(collection.tintName);
    _gradientLayer.colors = @[
        (__bridge id)[tint colorWithAlphaComponent:0.32].CGColor,
        (__bridge id)[tint colorWithAlphaComponent:0.12].CGColor,
    ];
    _gradientLayer.backgroundColor = NSColor.windowBackgroundColor.CGColor;

    NSImageSymbolConfiguration * const symConfig =
        [NSImageSymbolConfiguration configurationWithPointSize:22.0 weight:NSFontWeightSemibold];
    NSImage *sym = [NSImage imageWithSystemSymbolName:collection.symbolName accessibilityDescription:nil];
    if (sym != nil) {
        sym = [sym imageWithSymbolConfiguration:symConfig];
    }
    _symbolImageView.image = sym;
    _symbolImageView.contentTintColor = tint;

    _titleLabel.stringValue = collection.title ?: @"";
    _subtitleLabel.stringValue = collection.subtitle ?: @"";

    const NSUInteger count = collection.entries.count;
    NSString *countStr = @"";
    if ([collection.mediaType isEqualToString:@"movie"]) {
        countStr = [NSString stringWithFormat:_NS("%lu Films"), (unsigned long)count];
    } else if ([collection.mediaType isEqualToString:@"series"]) {
        countStr = [NSString stringWithFormat:_NS("%lu Shows"), (unsigned long)count];
    } else {
        countStr = [NSString stringWithFormat:_NS("%lu Titles"), (unsigned long)count];
    }
    _countLabel.stringValue = countStr;
    _countLabel.textColor = tint;
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
    [self addCursorRect:self.bounds cursor:NSCursor.pointingHandCursor];
}

- (void)mouseEntered:(NSEvent *)event
{
    _isHovered = YES;
    [self updateHoverState:YES animated:YES];
}

- (void)mouseExited:(NSEvent *)event
{
    _isHovered = NO;
    [self updateHoverState:NO animated:YES];
}

- (void)updateHoverState:(BOOL)hovered animated:(BOOL)animated
{
    if (_posterViews.count < 3) {
        return;
    }

    const CGFloat rot0 = hovered ? (-14.0 * M_PI / 180.0) : (-8.0 * M_PI / 180.0);
    const CGFloat rot2 = hovered ? (+14.0 * M_PI / 180.0) : (+8.0 * M_PI / 180.0);

    const CGFloat spreadX0 = hovered ? -8.0 : 0.0;
    const CGFloat spreadX2 = hovered ? +8.0 : 0.0;
    const CGFloat riseY1 = hovered ? (self.isFlipped ? -6.0 : 6.0) : 0.0;

    CATransform3D t0 = CATransform3DConcat(MacLCRotationAboutCentre(rot0, _posterViews[0].bounds.size),
                                           CATransform3DMakeTranslation(spreadX0, 0, 0));
    CATransform3D t1 = CATransform3DMakeTranslation(0, riseY1, 0);
    CATransform3D t2 = CATransform3DConcat(MacLCRotationAboutCentre(rot2, _posterViews[2].bounds.size),
                                           CATransform3DMakeTranslation(spreadX2, 0, 0));

    if (MacLCDesign.reducedMotion) {
        t0 = MacLCRotationAboutCentre(-8.0 * M_PI / 180.0, _posterViews[0].bounds.size);
        t1 = CATransform3DIdentity;
        t2 = MacLCRotationAboutCentre(+8.0 * M_PI / 180.0, _posterViews[2].bounds.size);
    }

    NSArray<NSValue *> *targets = @[
        [NSValue valueWithCATransform3D:t0],
        [NSValue valueWithCATransform3D:t1],
        [NSValue valueWithCATransform3D:t2],
    ];

    for (NSInteger i = 0; i < 3; i++) {
        CALayer * const layer = _posterViews[i].layer;
        CATransform3D const targetT = [targets[i] CATransform3DValue];

        if (!animated || MacLCDesign.reducedMotion) {
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            [layer removeAnimationForKey:@"fanSpring"];
            layer.transform = targetT;
            [CATransaction commit];
        } else {
            CALayer * const pres = layer.presentationLayer ?: layer;
            CATransform3D const fromT = pres.transform;
            layer.transform = targetT;

            CASpringAnimation *anim = [CASpringAnimation animationWithKeyPath:@"transform"];
            anim.damping = 14.0;
            anim.stiffness = 220.0;
            anim.mass = 1.0;
            anim.duration = anim.settlingDuration;
            anim.fromValue = [NSValue valueWithCATransform3D:fromT];
            anim.toValue = [NSValue valueWithCATransform3D:targetT];
            [layer addAnimation:anim forKey:@"fanSpring"];
        }
    }
}

- (void)mouseUp:(NSEvent *)event
{
    const NSPoint loc = [self convertPoint:event.locationInWindow fromView:nil];
    if (NSPointInRect(loc, self.bounds)) {
        if (self.item.activationHandler != nil && self.item.collection != nil) {
            self.item.activationHandler(self.item.collection);
        }
    }
}

- (void)keyDown:(NSEvent *)event
{
    if (event.keyCode == 36 || event.keyCode == 76) { // Return / Enter
        if (self.item.activationHandler != nil && self.item.collection != nil) {
            self.item.activationHandler(self.item.collection);
            return;
        }
    }
    [super keyDown:event];
}

- (BOOL)acceptsFirstResponder
{
    return YES;
}

- (BOOL)isAccessibilityElement
{
    return YES;
}

- (nullable NSAccessibilityRole)accessibilityRole
{
    return NSAccessibilityButtonRole;
}

- (nullable NSString *)accessibilityLabel
{
    return [NSString stringWithFormat:@"%@, %@, %@",
            _titleLabel.stringValue ?: @"",
            _subtitleLabel.stringValue ?: @"",
            _countLabel.stringValue ?: @""];
}

- (BOOL)accessibilityPerformPress
{
    if (self.item.activationHandler != nil && self.item.collection != nil) {
        self.item.activationHandler(self.item.collection);
        return YES;
    }
    return NO;
}

@end

@implementation MacLCWatchCollectionCard
{
    NSMutableArray<MacLCWatchImageRequest *> *_imageRequests;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _imageRequests = [NSMutableArray array];
    }
    return self;
}

- (void)loadView
{
    MacLCWatchCollectionCardView *v = [[MacLCWatchCollectionCardView alloc] initWithFrame:NSMakeRect(0, 0, 340, 216)];
    v.item = self;
    self.view = v;
}

- (MacLCWatchCollectionCardView *)cardView
{
    return (MacLCWatchCollectionCardView *)self.view;
}

- (void)dealloc
{
    for (MacLCWatchImageRequest *req in _imageRequests) {
        [req cancel];
    }
}

- (void)prepareForReuse
{
    [super prepareForReuse];
    for (MacLCWatchImageRequest *req in _imageRequests) {
        [req cancel];
    }
    [_imageRequests removeAllObjects];
    _collection = nil;
    self.selected = NO;
    self.cardView.focusRingLayer.hidden = YES;
    for (NSImageView *iv in self.cardView.posterImageViews) {
        iv.image = nil;
    }
    [self.cardView updateHoverState:NO animated:NO];
}

- (void)setSelected:(BOOL)selected
{
    [super setSelected:selected];
    self.cardView.focusRingLayer.hidden = !selected;
}

- (void)configureWithCollection:(MacLCWatchCollection *)collection
                          items:(nullable NSArray<MacLCAddonItem *> *)items
{
    _collection = collection;
    [self.cardView applyCollection:collection];

    for (MacLCWatchImageRequest *req in _imageRequests) {
        [req cancel];
    }
    [_imageRequests removeAllObjects];

    NSArray<NSImageView *> * const imgViews = self.cardView.posterImageViews;
    const CGFloat scale = self.view.window.backingScaleFactor > 0.0 ? self.view.window.backingScaleFactor : 2.0;
    const NSSize pointSize = NSMakeSize(82.0, 123.0);

    for (NSInteger i = 0; i < 3; i++) {
        if (items != nil && i < (NSInteger)items.count && items[i].posterURL != nil) {
            __weak typeof(self) weakSelf = self;
            MacLCWatchImageRequest *req = nil;
            NSImage *cached = [MacLCWatchImageCache.sharedCache imageForURL:items[i].posterURL
                                                                 pointSize:pointSize
                                                                     scale:scale
                                                                   request:&req
                                                                completion:^(NSImage * _Nullable image) {
                MacLCWatchCollectionCard *strongSelf = weakSelf;
                if (strongSelf != nil && strongSelf.collection == collection) {
                    if (i < (NSInteger)strongSelf.cardView.posterImageViews.count) {
                        strongSelf.cardView.posterImageViews[i].image = image;
                    }
                }
            }];
            if (req != nil) {
                [_imageRequests addObject:req];
            }
            imgViews[i].image = cached;
        } else {
            imgViews[i].image = nil;
        }
    }
}

@end

#pragma mark - Genre Tile

NSUserInterfaceItemIdentifier const MacLCWatchGenreTileIdentifier = @"MacLCWatchGenreTileIdentifier";

@interface MacLCWatchGenreTileView : NSView
@property (nonatomic, weak) MacLCWatchGenreTile *item;
@property (nonatomic, strong) CAGradientLayer *gradientLayer;
@property (nonatomic, strong) NSImageView *watermarkImageView;
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSArray<NSView *> *posterWrapperViews;
@property (nonatomic, strong) NSArray<NSImageView *> *posterImageViews;
@property (nonatomic, assign) BOOL isHovered;

- (void)updateHoverState:(BOOL)hovered animated:(BOOL)animated;
- (void)applyGenre:(NSString *)genre;
@end

@implementation MacLCWatchGenreTileView
{
    NSTrackingArea *_trackingArea;
}

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        self.layer.masksToBounds = YES;
        self.layer.cornerRadius = MacLCDesign.cornerRadiusLarge;
        self.layer.cornerCurve = kCACornerCurveContinuous;

        _gradientLayer = [CAGradientLayer layer];
        _gradientLayer.startPoint = CGPointMake(0.0, 0.0);
        _gradientLayer.endPoint = CGPointMake(1.0, 1.0);
        [self.layer addSublayer:_gradientLayer];

        _watermarkImageView = [[NSImageView alloc] initWithFrame:NSMakeRect(0, 0, 110, 110)];
        _watermarkImageView.wantsLayer = YES;
        _watermarkImageView.imageScaling = NSImageScaleProportionallyUpOrDown;
        [self addSubview:_watermarkImageView];

        NSMutableArray<NSView *> *pWrappers = [NSMutableArray arrayWithCapacity:2];
        NSMutableArray<NSImageView *> *pViews = [NSMutableArray arrayWithCapacity:2];

        for (NSInteger i = 0; i < 2; i++) {
            NSView *wrap = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 60, 90)];
            wrap.wantsLayer = YES;
            wrap.layer.masksToBounds = YES;
            wrap.layer.cornerRadius = MacLCDesign.cornerRadiusSmall;
            wrap.layer.cornerCurve = kCACornerCurveContinuous;
            wrap.layer.borderWidth = 1.0;
            wrap.layer.borderColor = NSColor.whiteColor.CGColor;
            wrap.hidden = YES;

            NSImageView *iv = [[NSImageView alloc] initWithFrame:NSMakeRect(0, 0, 60, 90)];
            iv.imageScaling = NSImageScaleProportionallyUpOrDown;
            [wrap addSubview:iv];

            [self addSubview:wrap];
            [pWrappers addObject:wrap];
            [pViews addObject:iv];
        }

        _posterWrapperViews = [pWrappers copy];
        _posterImageViews = [pViews copy];

        _titleLabel = [NSTextField wrappingLabelWithString:@""];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _titleLabel.font = [NSFont systemFontOfSize:MacLCDesign.title3.pointSize weight:NSFontWeightBold];
        _titleLabel.textColor = NSColor.whiteColor;
        _titleLabel.selectable = NO;
        _titleLabel.maximumNumberOfLines = 2;
        [self addSubview:_titleLabel];

        [NSLayoutConstraint activateConstraints:@[
            [_titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:14.0],
            [_titleLabel.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-14.0],
            [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-14.0],
        ]];
    }
    return self;
}

- (void)layout
{
    [super layout];
    _gradientLayer.frame = self.bounds;

    /* Watermark: 88 pt symbol, rotated -12 deg, bottom-trailing. */
    const CGFloat wmSize = 110.0;
    const CGFloat wmX = self.bounds.size.width - wmSize + 16.0;
    const CGFloat wmY = self.isFlipped ? (self.bounds.size.height - wmSize + 16.0) : -16.0;
    _watermarkImageView.frame = NSMakeRect(wmX, wmY, wmSize, wmSize);
    _watermarkImageView.layer.transform = CATransform3DMakeRotation(-12.0 * M_PI / 180.0, 0, 0, 1);

    /* Peeking posters: 60 x 90, rotated 10 deg, peeking from trailing edge. */
    const CGFloat pY = self.isFlipped ? 10.0 : (self.bounds.size.height - 90.0 - 10.0);
    _posterWrapperViews[0].frame = NSMakeRect(self.bounds.size.width - 50.0, pY, 60.0, 90.0);
    _posterWrapperViews[1].frame = NSMakeRect(self.bounds.size.width - 32.0, pY + 8.0, 60.0, 90.0);

    for (NSImageView *iv in _posterImageViews) {
        iv.frame = NSMakeRect(0, 0, 60.0, 90.0);
    }

    [self updateHoverState:_isHovered animated:NO];
}

- (void)applyGenre:(NSString *)genre
{
    _titleLabel.stringValue = genre ?: @"";

    NSString * const tintName = [MacLCWatchDiscovery tintNameForGenre:genre];
    NSColor * const tint = MacLCWatchColorNamed(tintName);

    /* Opaque and darkening toward the bottom, where the white name sits:
     * even systemYellow reaches about 5:1 behind it (typography.md: bold
     * 20 pt text needs 3:1); a transparent bottom faded into the page. */
    NSColor * const top = [tint blendedColorWithFraction:0.10 ofColor:NSColor.blackColor] ?: tint;
    NSColor * const bottom = [tint blendedColorWithFraction:0.50 ofColor:NSColor.blackColor] ?: tint;
    _gradientLayer.startPoint = CGPointMake(0.5, self.isFlipped ? 0.0 : 1.0);
    _gradientLayer.endPoint = CGPointMake(0.5, self.isFlipped ? 1.0 : 0.0);
    _gradientLayer.colors = @[
        (__bridge id)top.CGColor,
        (__bridge id)bottom.CGColor,
    ];

    NSString * const symName = [MacLCWatchDiscovery symbolNameForGenre:genre];
    NSImageSymbolConfiguration * const symConfig =
        [NSImageSymbolConfiguration configurationWithPointSize:88.0 weight:NSFontWeightBold];
    NSImage *sym = [NSImage imageWithSystemSymbolName:symName accessibilityDescription:nil];
    if (sym != nil) {
        sym = [sym imageWithSymbolConfiguration:symConfig];
    }
    _watermarkImageView.image = sym;
    _watermarkImageView.contentTintColor = [NSColor colorWithWhite:1.0 alpha:0.18];
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
    [self addCursorRect:self.bounds cursor:NSCursor.pointingHandCursor];
}

- (void)mouseEntered:(NSEvent *)event
{
    _isHovered = YES;
    [self updateHoverState:YES animated:YES];
}

- (void)mouseExited:(NSEvent *)event
{
    _isHovered = NO;
    [self updateHoverState:NO animated:YES];
}

- (void)updateHoverState:(BOOL)hovered animated:(BOOL)animated
{
    const CATransform3D cardTarget = (hovered && !MacLCDesign.reducedMotion)
        ? CATransform3DMakeScale(1.03, 1.03, 1.0)
        : CATransform3DIdentity;

    const CGFloat posterRot = 10.0 * M_PI / 180.0;
    const CGFloat slideIn = (hovered && !MacLCDesign.reducedMotion) ? -8.0 : 0.0;
    const CATransform3D posterTarget = CATransform3DConcat(CATransform3DMakeRotation(posterRot, 0, 0, 1),
                                                           CATransform3DMakeTranslation(slideIn, 0, 0));

    if (!animated || MacLCDesign.reducedMotion) {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        [self.layer removeAnimationForKey:@"genreCardSpring"];
        self.layer.transform = cardTarget;

        for (NSView *pv in _posterWrapperViews) {
            [pv.layer removeAnimationForKey:@"genrePosterSpring"];
            pv.layer.transform = posterTarget;
        }
        [CATransaction commit];
    } else {
        CALayer * const cardPres = self.layer.presentationLayer ?: self.layer;
        CATransform3D const cardFrom = cardPres.transform;
        self.layer.transform = cardTarget;

        CASpringAnimation *cardAnim = [CASpringAnimation animationWithKeyPath:@"transform"];
        cardAnim.damping = 14.0;
        cardAnim.stiffness = 220.0;
        cardAnim.mass = 1.0;
        cardAnim.duration = cardAnim.settlingDuration;
        cardAnim.fromValue = [NSValue valueWithCATransform3D:cardFrom];
        cardAnim.toValue = [NSValue valueWithCATransform3D:cardTarget];
        [self.layer addAnimation:cardAnim forKey:@"genreCardSpring"];

        for (NSView *pv in _posterWrapperViews) {
            CALayer * const pPres = pv.layer.presentationLayer ?: pv.layer;
            CATransform3D const pFrom = pPres.transform;
            pv.layer.transform = posterTarget;

            CASpringAnimation *pAnim = [CASpringAnimation animationWithKeyPath:@"transform"];
            pAnim.damping = 14.0;
            pAnim.stiffness = 220.0;
            pAnim.mass = 1.0;
            pAnim.duration = pAnim.settlingDuration;
            pAnim.fromValue = [NSValue valueWithCATransform3D:pFrom];
            pAnim.toValue = [NSValue valueWithCATransform3D:posterTarget];
            [pv.layer addAnimation:pAnim forKey:@"genrePosterSpring"];
        }
    }
}

- (void)mouseUp:(NSEvent *)event
{
    const NSPoint loc = [self convertPoint:event.locationInWindow fromView:nil];
    if (NSPointInRect(loc, self.bounds)) {
        if (self.item.activationHandler != nil && self.item.genre != nil) {
            self.item.activationHandler(self.item.genre);
        }
    }
}

- (void)keyDown:(NSEvent *)event
{
    if (event.keyCode == 36 || event.keyCode == 76) { // Return / Enter
        if (self.item.activationHandler != nil && self.item.genre != nil) {
            self.item.activationHandler(self.item.genre);
            return;
        }
    }
    [super keyDown:event];
}

- (BOOL)acceptsFirstResponder
{
    return YES;
}

- (BOOL)isAccessibilityElement
{
    return YES;
}

- (nullable NSAccessibilityRole)accessibilityRole
{
    return NSAccessibilityButtonRole;
}

- (nullable NSString *)accessibilityLabel
{
    return _titleLabel.stringValue ?: @"";
}

- (BOOL)accessibilityPerformPress
{
    if (self.item.activationHandler != nil && self.item.genre != nil) {
        self.item.activationHandler(self.item.genre);
        return YES;
    }
    return NO;
}

@end

@implementation MacLCWatchGenreTile
{
    NSMutableArray<MacLCWatchImageRequest *> *_imageRequests;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _imageRequests = [NSMutableArray array];
    }
    return self;
}

- (void)loadView
{
    MacLCWatchGenreTileView *v = [[MacLCWatchGenreTileView alloc] initWithFrame:NSMakeRect(0, 0, 196, 110)];
    v.item = self;
    self.view = v;
}

- (MacLCWatchGenreTileView *)tileView
{
    return (MacLCWatchGenreTileView *)self.view;
}

- (void)dealloc
{
    for (MacLCWatchImageRequest *req in _imageRequests) {
        [req cancel];
    }
}

- (void)prepareForReuse
{
    [super prepareForReuse];
    for (MacLCWatchImageRequest *req in _imageRequests) {
        [req cancel];
    }
    [_imageRequests removeAllObjects];
    _genre = nil;
    self.selected = NO;
    for (NSView *pv in self.tileView.posterWrapperViews) {
        pv.hidden = YES;
    }
    for (NSImageView *iv in self.tileView.posterImageViews) {
        iv.image = nil;
    }
    [self.tileView updateHoverState:NO animated:NO];
}

- (void)configureWithGenre:(NSString *)genre posters:(NSArray<MacLCAddonItem *> *)posters
{
    _genre = [genre copy];
    [self.tileView applyGenre:genre];

    for (MacLCWatchImageRequest *req in _imageRequests) {
        [req cancel];
    }
    [_imageRequests removeAllObjects];

    NSArray<NSView *> * const wrappers = self.tileView.posterWrapperViews;
    NSArray<NSImageView *> * const imgViews = self.tileView.posterImageViews;
    const CGFloat scale = self.view.window.backingScaleFactor > 0.0 ? self.view.window.backingScaleFactor : 2.0;
    const NSSize pointSize = NSMakeSize(60.0, 90.0);

    for (NSInteger i = 0; i < 2; i++) {
        if (posters != nil && i < (NSInteger)posters.count && posters[i].posterURL != nil) {
            wrappers[i].hidden = NO;
            __weak typeof(self) weakSelf = self;
            MacLCWatchImageRequest *req = nil;
            NSImage *cached = [MacLCWatchImageCache.sharedCache imageForURL:posters[i].posterURL
                                                                 pointSize:pointSize
                                                                     scale:scale
                                                                   request:&req
                                                                completion:^(NSImage * _Nullable image) {
                MacLCWatchGenreTile *strongSelf = weakSelf;
                if (strongSelf != nil && [strongSelf.genre isEqualToString:genre]) {
                    if (i < (NSInteger)strongSelf.tileView.posterImageViews.count) {
                        strongSelf.tileView.posterImageViews[i].image = image;
                    }
                }
            }];
            if (req != nil) {
                [_imageRequests addObject:req];
            }
            imgViews[i].image = cached;
        } else {
            wrappers[i].hidden = YES;
            imgViews[i].image = nil;
        }
    }
}

@end

#pragma mark - Services Bar Components

@interface MacLCWatchServiceCapsuleButton : NSButton
@property (nonatomic, copy, nullable) NSString *serviceCode;
@property (nonatomic, assign) BOOL isSelectedCapsule;
@property (nonatomic, assign) BOOL isHovered;
@property (nonatomic, strong, nullable) NSTrackingArea *trackingArea;

- (void)setSelectedCapsule:(BOOL)selectedCapsule animated:(BOOL)animated;
@end

@implementation MacLCWatchServiceCapsuleButton

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        self.bordered = NO;
        self.wantsLayer = YES;
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.font = [NSFont systemFontOfSize:MacLCDesign.callout.pointSize weight:NSFontWeightMedium];
        self.contentTintColor = NSColor.labelColor;
    }
    return self;
}

/* The fill is drawn here, not set on the layer: a CGColor taken from a
 * dynamic system color is frozen in one appearance. */
- (NSSize)intrinsicContentSize
{
    const NSSize size = [super intrinsicContentSize];
    return NSMakeSize(ceil(size.width) + 28.0, 28.0);
}

- (void)drawRect:(NSRect)dirtyRect
{
    NSColor * const fill = _isSelectedCapsule
        ? MacLCDesign.accent
        : (_isHovered ? NSColor.tertiarySystemFillColor : NSColor.quaternarySystemFillColor);
    [fill setFill];
    const NSRect bounds = self.bounds;
    [[NSBezierPath bezierPathWithRoundedRect:bounds xRadius:NSHeight(bounds) / 2.0 yRadius:NSHeight(bounds) / 2.0] fill];
    [super drawRect:dirtyRect];
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
    [self addCursorRect:self.bounds cursor:NSCursor.pointingHandCursor];
}

- (void)mouseEntered:(NSEvent *)event
{
    _isHovered = YES;
    if (!_isSelectedCapsule) {
        [self updateColorsAnimated:YES];
    }
}

- (void)mouseExited:(NSEvent *)event
{
    _isHovered = NO;
    if (!_isSelectedCapsule) {
        [self updateColorsAnimated:YES];
    }
}

- (void)setSelectedCapsule:(BOOL)selectedCapsule animated:(BOOL)animated
{
    _isSelectedCapsule = selectedCapsule;
    [self updateColorsAnimated:animated];
}

- (void)updateColorsAnimated:(BOOL)animated
{
    NSColor * const text = _isSelectedCapsule ? NSColor.whiteColor : NSColor.labelColor;
    self.contentTintColor = text;
    self.attributedTitle = [[NSAttributedString alloc] initWithString:self.title ?: @""
        attributes:@{ NSFontAttributeName: self.font, NSForegroundColorAttributeName: text }];
    if (animated && !MacLCDesign.reducedMotion) {
        CATransition * const fade = [CATransition animation];
        fade.type = kCATransitionFade;
        fade.duration = 0.25;
        [self.layer addAnimation:fade forKey:@"capsuleFade"];
    }
    self.needsDisplay = YES;
}

- (BOOL)isAccessibilityElement
{
    return YES;
}

- (nullable NSAccessibilityRole)accessibilityRole
{
    return NSAccessibilityRadioButtonRole;
}

- (nullable id)accessibilityValue
{
    return @(_isSelectedCapsule);
}

@end

#pragma mark - Services Bar

@interface MacLCWatchServiceBar ()
{
    NSScrollView *_scrollView;
    NSView *_documentView;
    NSStackView *_stackView;
    NSMutableArray<MacLCWatchServiceCapsuleButton *> *_capsuleButtons;
    NSButton *_chooseButton;
    NSButton *_infoButton;
}
@end

@implementation MacLCWatchServiceBar

+ (CGFloat)height
{
    return 44.0;
}

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        _services = @[];
        _capsuleButtons = [NSMutableArray array];
        [self setUpServiceBar];
    }
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (self) {
        _services = @[];
        _capsuleButtons = [NSMutableArray array];
        [self setUpServiceBar];
    }
    return self;
}

- (void)setUpServiceBar
{
    self.wantsLayer = YES;

    _scrollView = [[NSScrollView alloc] initWithFrame:self.bounds];
    _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [MacLCWatchShelfScrolling configureShelfScrollView:_scrollView];
    [self addSubview:_scrollView];

    _documentView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 800, 44)];
    _documentView.translatesAutoresizingMaskIntoConstraints = NO;
    _scrollView.documentView = _documentView;

    _stackView = [[NSStackView alloc] initWithFrame:NSZeroRect];
    _stackView.translatesAutoresizingMaskIntoConstraints = NO;
    _stackView.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    _stackView.spacing = 8.0;
    _stackView.alignment = NSLayoutAttributeCenterY;
    [_documentView addSubview:_stackView];

    [NSLayoutConstraint activateConstraints:@[
        [_scrollView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_scrollView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [_scrollView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_scrollView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],

        [_documentView.topAnchor constraintEqualToAnchor:_scrollView.topAnchor],
        [_documentView.bottomAnchor constraintEqualToAnchor:_scrollView.bottomAnchor],
        [_documentView.leadingAnchor constraintEqualToAnchor:_scrollView.leadingAnchor],
        [_documentView.trailingAnchor constraintGreaterThanOrEqualToAnchor:_scrollView.trailingAnchor],

        [_stackView.leadingAnchor constraintEqualToAnchor:_documentView.leadingAnchor],
        [_stackView.centerYAnchor constraintEqualToAnchor:_documentView.centerYAnchor],
        [_stackView.trailingAnchor constraintEqualToAnchor:_documentView.trailingAnchor],
        [_stackView.heightAnchor constraintEqualToConstant:28.0],
    ]];

    [self rebuildCapsulesAnimated:NO];
}

- (void)setServices:(NSArray<MacLCWatchService *> *)services
{
    _services = [services copy];
    [self rebuildCapsulesAnimated:NO];
}

- (void)setSelectedCode:(nullable NSString *)selectedCode
{
    _selectedCode = [selectedCode copy];
    for (MacLCWatchServiceCapsuleButton *b in _capsuleButtons) {
        const BOOL isMatch = (_selectedCode == nil && b.serviceCode == nil) ||
                             (_selectedCode != nil && [b.serviceCode isEqualToString:_selectedCode]);
        [b setSelectedCapsule:isMatch animated:!MacLCDesign.reducedMotion];
    }
}

- (void)rebuildCapsulesAnimated:(BOOL)animated
{
    for (NSView *v in _stackView.arrangedSubviews) {
        [_stackView removeArrangedSubview:v];
        [v removeFromSuperview];
    }
    [_capsuleButtons removeAllObjects];

    if (_services.count == 0) {
        /* With no active service: one capsule "Add Your Streaming Services…" (plus.circle) and info button */
        MacLCWatchServiceCapsuleButton *inviteButton = [[MacLCWatchServiceCapsuleButton alloc] initWithFrame:NSZeroRect];
        inviteButton.title = _NS("Add Your Streaming Services…");
        inviteButton.image = [NSImage imageWithSystemSymbolName:@"plus.circle" accessibilityDescription:nil];
        inviteButton.imagePosition = NSImageLeading;
        inviteButton.imageHugsTitle = YES;
        inviteButton.target = self;
        inviteButton.action = @selector(chooseServicesClicked:);
        [inviteButton setSelectedCapsule:NO animated:NO];
        [_stackView addArrangedSubview:inviteButton];

        NSButton *info = [MacLCExplainer infoButtonForTopic:MacLCExplainerTopicServices];
        info.translatesAutoresizingMaskIntoConstraints = NO;
        [_stackView addArrangedSubview:info];
        return;
    }

    /* "All" capsule (serviceCode = nil) */
    MacLCWatchServiceCapsuleButton *allButton = [[MacLCWatchServiceCapsuleButton alloc] initWithFrame:NSZeroRect];
    allButton.title = _NS("All");
    allButton.serviceCode = nil;
    allButton.target = self;
    allButton.action = @selector(capsuleClicked:);
    [allButton setSelectedCapsule:(_selectedCode == nil) animated:NO];
    [_stackView addArrangedSubview:allButton];
    [_capsuleButtons addObject:allButton];

    /* Active services */
    for (MacLCWatchService *s in _services) {
        MacLCWatchServiceCapsuleButton *btn = [[MacLCWatchServiceCapsuleButton alloc] initWithFrame:NSZeroRect];
        btn.title = s.name;
        btn.serviceCode = s.code;
        btn.target = self;
        btn.action = @selector(capsuleClicked:);
        const BOOL isMatch = (_selectedCode != nil && [_selectedCode isEqualToString:s.code]);
        [btn setSelectedCapsule:isMatch animated:NO];
        [_stackView addArrangedSubview:btn];
        [_capsuleButtons addObject:btn];
    }

    /* Trailing: "Choose Services…" and info button */
    MacLCWatchServiceCapsuleButton *chooseBtn = [[MacLCWatchServiceCapsuleButton alloc] initWithFrame:NSZeroRect];
    chooseBtn.title = _NS("Choose Services…");
    chooseBtn.image = [NSImage imageWithSystemSymbolName:@"slider.horizontal.3" accessibilityDescription:nil];
    chooseBtn.imagePosition = NSImageLeading;
    chooseBtn.imageHugsTitle = YES;
    chooseBtn.target = self;
    chooseBtn.action = @selector(chooseServicesClicked:);
    [chooseBtn setSelectedCapsule:NO animated:NO];
    [_stackView addArrangedSubview:chooseBtn];

    NSButton *info = [MacLCExplainer infoButtonForTopic:MacLCExplainerTopicServices];
    info.translatesAutoresizingMaskIntoConstraints = NO;
    [_stackView addArrangedSubview:info];
}

- (void)capsuleClicked:(MacLCWatchServiceCapsuleButton *)sender
{
    self.selectedCode = sender.serviceCode;
    if (self.selectionHandler != nil) {
        self.selectionHandler(sender.serviceCode);
    }
}

- (void)chooseServicesClicked:(id)sender
{
    if (self.chooseServicesHandler != nil) {
        self.chooseServicesHandler();
    }
}

- (BOOL)acceptsFirstResponder
{
    return YES;
}

- (void)keyDown:(NSEvent *)event
{
    if (_capsuleButtons.count == 0) {
        [super keyDown:event];
        return;
    }

    NSInteger currentIndex = -1;
    for (NSInteger i = 0; i < (NSInteger)_capsuleButtons.count; i++) {
        if (_capsuleButtons[i].isSelectedCapsule) {
            currentIndex = i;
            break;
        }
    }

    if (event.keyCode == 123) { // Left arrow
        NSInteger nextIndex = (currentIndex <= 0) ? (NSInteger)(_capsuleButtons.count - 1) : (currentIndex - 1);
        [self capsuleClicked:_capsuleButtons[nextIndex]];
        return;
    } else if (event.keyCode == 124) { // Right arrow
        NSInteger nextIndex = (currentIndex < 0 || currentIndex >= (NSInteger)_capsuleButtons.count - 1) ? 0 : (currentIndex + 1);
        [self capsuleClicked:_capsuleButtons[nextIndex]];
        return;
    }

    [super keyDown:event];
}

- (BOOL)isAccessibilityElement
{
    return YES;
}

- (nullable NSAccessibilityRole)accessibilityRole
{
    return NSAccessibilityRadioGroupRole;
}

- (nullable NSString *)accessibilityLabel
{
    return _NS("Streaming service");
}

@end

#pragma mark - Services Sheet Controller

@interface MacLCWatchServiceToggleTile : NSButton
@property (nonatomic, copy) NSString *serviceCode;
@property (nonatomic, assign) BOOL isOn;
@property (nonatomic, strong) NSImageView *iconImageView;
@property (nonatomic, strong) NSTextField *nameLabel;

- (void)setIsOn:(BOOL)isOn animated:(BOOL)animated;
@end

@implementation MacLCWatchServiceToggleTile

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        self.bordered = NO;
        self.title = @""; /* the name is its own label; NSButton would draw "Button" */
        self.wantsLayer = YES;
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.layer.masksToBounds = YES;
        self.layer.cornerRadius = MacLCDesign.cornerRadiusMedium;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.layer.backgroundColor = NSColor.quaternarySystemFillColor.CGColor;
        self.layer.borderWidth = 1.0;
        self.layer.borderColor = NSColor.separatorColor.CGColor;

        _iconImageView = [[NSImageView alloc] initWithFrame:NSZeroRect];
        _iconImageView.translatesAutoresizingMaskIntoConstraints = NO;
        _iconImageView.imageScaling = NSImageScaleProportionallyUpOrDown;
        [self addSubview:_iconImageView];

        _nameLabel = [NSTextField labelWithString:@""];
        _nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _nameLabel.font = MacLCDesign.headline;
        _nameLabel.textColor = NSColor.labelColor;
        _nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _nameLabel.selectable = NO;
        [self addSubview:_nameLabel];

        [NSLayoutConstraint activateConstraints:@[
            [_iconImageView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12.0],
            [_iconImageView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_iconImageView.widthAnchor constraintEqualToConstant:22.0],
            [_iconImageView.heightAnchor constraintEqualToConstant:22.0],

            [_nameLabel.leadingAnchor constraintEqualToAnchor:_iconImageView.trailingAnchor constant:10.0],
            [_nameLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-10.0],
            [_nameLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        ]];
    }
    return self;
}

- (void)setIsOn:(BOOL)isOn animated:(BOOL)animated
{
    _isOn = isOn;
    NSImageSymbolConfiguration * const symConfig =
        [NSImageSymbolConfiguration configurationWithPointSize:18.0 weight:NSFontWeightMedium];

    if (isOn) {
        NSImage *chk = [NSImage imageWithSystemSymbolName:@"checkmark.circle.fill" accessibilityDescription:nil];
        if (chk != nil) {
            chk = [chk imageWithSymbolConfiguration:symConfig];
        }
        _iconImageView.image = chk;
        _iconImageView.contentTintColor = MacLCDesign.accent;

        self.layer.borderWidth = 2.0;
        self.layer.borderColor = MacLCDesign.accent.CGColor;
    } else {
        NSImage *cir = [NSImage imageWithSystemSymbolName:@"circle" accessibilityDescription:nil];
        if (cir != nil) {
            cir = [cir imageWithSymbolConfiguration:symConfig];
        }
        _iconImageView.image = cir;
        _iconImageView.contentTintColor = MacLCDesign.tertiaryLabel;

        self.layer.borderWidth = 1.0;
        self.layer.borderColor = NSColor.separatorColor.CGColor;
    }
}

- (void)resetCursorRects
{
    [super resetCursorRects];
    [self addCursorRect:self.bounds cursor:NSCursor.pointingHandCursor];
}

- (BOOL)isAccessibilityElement
{
    return YES;
}

- (nullable NSAccessibilityRole)accessibilityRole
{
    return NSAccessibilityCheckBoxRole;
}

- (nullable id)accessibilityValue
{
    return @(_isOn);
}

@end

@interface MacLCWatchServicesSheetController ()
{
    NSMutableSet<NSString *> *_selectedCodes;
    NSMutableArray<MacLCWatchServiceToggleTile *> *_tiles;
    NSPopUpButton *_countryPopUp;
    NSButton *_cancelButton;
    NSButton *_saveButton;
    NSProgressIndicator *_spinner;
    NSTextField *_errorLabel;
    void (^_sheetCompletion)(BOOL saved);
}
@end

/* The grid reads from the top: a flipped document view starts there. */
@interface MacLCWatchFlippedDocumentView : NSView
@end
@implementation MacLCWatchFlippedDocumentView
- (BOOL)isFlipped { return YES; }
@end

@implementation MacLCWatchServicesSheetController

- (instancetype)init
{
    NSWindow *sheetWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 560, 520)
                                                        styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable)
                                                          backing:NSBackingStoreBuffered
                                                            defer:NO];
    sheetWindow.title = _NS("Choose Your Streaming Services");
    self = [super initWithWindow:sheetWindow];
    if (self) {
        _selectedCodes = [NSMutableSet set];
        _tiles = [NSMutableArray array];
        [self buildSheetContent];
    }
    return self;
}

- (void)buildSheetContent
{
    NSView * const contentView = self.window.contentView;
    contentView.wantsLayer = YES;

    /* 560 x 520 (MacLCWatchDiscoveryViews.h): without these the content's
     * fitting size shrinks the sheet and the grid has to scroll. */
    NSLayoutConstraint * const preferredWidth = [contentView.widthAnchor constraintEqualToConstant:560.0];
    NSLayoutConstraint * const preferredHeight = [contentView.heightAnchor constraintEqualToConstant:520.0];
    preferredWidth.priority = NSLayoutPriorityDragThatCannotResizeWindow;
    preferredHeight.priority = NSLayoutPriorityDragThatCannotResizeWindow;
    [NSLayoutConstraint activateConstraints:@[
        preferredWidth, preferredHeight,
        [contentView.widthAnchor constraintGreaterThanOrEqualToConstant:520.0],
        [contentView.heightAnchor constraintGreaterThanOrEqualToConstant:460.0],
    ]];

    NSTextField * const titleLabel = [NSTextField labelWithString:_NS("Choose Your Streaming Services")];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.font = [NSFont systemFontOfSize:MacLCDesign.title2.pointSize weight:NSFontWeightBold];
    titleLabel.textColor = NSColor.labelColor;
    titleLabel.selectable = NO;
    [contentView addSubview:titleLabel];

    NSTextField * const descLabel = [NSTextField wrappingLabelWithString:
        _NS("Pick the services you subscribe to. Watch then lets you browse what's popular on each one. "
            "Lists come from the community add-on Streaming Catalogs, which you can remove in Settings ▸ Add-ons.")];
    descLabel.translatesAutoresizingMaskIntoConstraints = NO;
    descLabel.font = MacLCDesign.body;
    descLabel.textColor = MacLCDesign.secondaryLabel;
    descLabel.preferredMaxLayoutWidth = 512.0;
    descLabel.selectable = NO;
    [contentView addSubview:descLabel];

    /* Grid of toggle tiles inside a scroll view */
    NSScrollView * const scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.hasVerticalScroller = YES;
    scroll.hasHorizontalScroller = NO;
    scroll.drawsBackground = NO;
    [contentView addSubview:scroll];

    NSArray<MacLCWatchService *> * const services = MacLCWatchDiscovery.knownServices;
    NSArray<NSString *> * const activeCodes = MacLCWatchDiscovery.sharedDiscovery.activeServiceCodes ?: @[];
    [_selectedCodes addObjectsFromArray:activeCodes];

    const NSInteger cols = 3;
    const CGFloat tileW = 160.0;
    const CGFloat tileH = 56.0;
    const CGFloat spacing = 8.0;
    const NSInteger totalRows = (services.count + cols - 1) / cols;
    const CGFloat gridContentH = totalRows * tileH + (totalRows - 1) * spacing;

    NSView * const gridDoc = [[MacLCWatchFlippedDocumentView alloc] initWithFrame:NSMakeRect(0, 0, 500, gridContentH)];
    gridDoc.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.documentView = gridDoc;

    for (NSInteger idx = 0; idx < (NSInteger)services.count; idx++) {
        MacLCWatchService * const s = services[idx];
        const NSInteger row = idx / cols;
        const NSInteger col = idx % cols;

        MacLCWatchServiceToggleTile *tile = [[MacLCWatchServiceToggleTile alloc] initWithFrame:NSZeroRect];
        tile.serviceCode = s.code;
        tile.nameLabel.stringValue = s.name;
        [tile setIsOn:[_selectedCodes containsObject:s.code] animated:NO];
        tile.target = self;
        tile.action = @selector(tileClicked:);
        [gridDoc addSubview:tile];
        [_tiles addObject:tile];

        [NSLayoutConstraint activateConstraints:@[
            [tile.leadingAnchor constraintEqualToAnchor:gridDoc.leadingAnchor constant:col * (tileW + spacing)],
            [tile.topAnchor constraintEqualToAnchor:gridDoc.topAnchor constant:row * (tileH + spacing)],
            [tile.widthAnchor constraintEqualToConstant:tileW],
            [tile.heightAnchor constraintEqualToConstant:tileH],
        ]];
    }

    _errorLabel = [NSTextField wrappingLabelWithString:@""];
    _errorLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _errorLabel.font = MacLCDesign.caption;
    _errorLabel.textColor = NSColor.systemRedColor;
    _errorLabel.selectable = NO;
    _errorLabel.hidden = YES;
    [contentView addSubview:_errorLabel];

    NSTextField * const countryLabel = [NSTextField labelWithString:_NS("Country:")];
    countryLabel.translatesAutoresizingMaskIntoConstraints = NO;
    countryLabel.font = MacLCDesign.body;
    countryLabel.textColor = NSColor.labelColor;
    countryLabel.selectable = NO;
    [contentView addSubview:countryLabel];

    _countryPopUp = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    _countryPopUp.translatesAutoresizingMaskIntoConstraints = NO;
    [self populateCountries];
    [contentView addSubview:_countryPopUp];

    _cancelButton = [NSButton buttonWithTitle:_NS("Cancel") target:self action:@selector(cancelClicked:)];
    _cancelButton.translatesAutoresizingMaskIntoConstraints = NO;
    _cancelButton.keyEquivalent = @"\e"; // Escape
    [contentView addSubview:_cancelButton];

    _saveButton = [NSButton buttonWithTitle:_NS("Save") target:self action:@selector(saveClicked:)];
    _saveButton.translatesAutoresizingMaskIntoConstraints = NO;
    _saveButton.keyEquivalent = @"\r"; // Return
    [contentView addSubview:_saveButton];

    _spinner = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
    _spinner.translatesAutoresizingMaskIntoConstraints = NO;
    _spinner.style = NSProgressIndicatorStyleSpinning;
    _spinner.controlSize = NSControlSizeRegular;
    _spinner.displayedWhenStopped = NO;
    _spinner.hidden = YES;
    [contentView addSubview:_spinner];

    [NSLayoutConstraint activateConstraints:@[
        [titleLabel.topAnchor constraintEqualToAnchor:contentView.topAnchor constant:24.0],
        [titleLabel.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:24.0],

        [descLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:8.0],
        [descLabel.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:24.0],
        [descLabel.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-24.0],

        [scroll.topAnchor constraintEqualToAnchor:descLabel.bottomAnchor constant:16.0],
        [scroll.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:24.0],
        [scroll.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-24.0],
        [scroll.bottomAnchor constraintEqualToAnchor:_errorLabel.topAnchor constant:-10.0],

        [gridDoc.topAnchor constraintEqualToAnchor:scroll.contentView.topAnchor],
        [gridDoc.leadingAnchor constraintEqualToAnchor:scroll.contentView.leadingAnchor],
        [gridDoc.widthAnchor constraintEqualToConstant:cols * tileW + (cols - 1) * spacing],
        [gridDoc.heightAnchor constraintEqualToConstant:gridContentH],

        [_errorLabel.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:24.0],
        [_errorLabel.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-24.0],
        [_errorLabel.bottomAnchor constraintEqualToAnchor:_countryPopUp.topAnchor constant:-12.0],

        [countryLabel.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:24.0],
        [countryLabel.centerYAnchor constraintEqualToAnchor:_countryPopUp.centerYAnchor],

        [_countryPopUp.leadingAnchor constraintEqualToAnchor:countryLabel.trailingAnchor constant:8.0],
        [_countryPopUp.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor constant:-24.0],
        [_countryPopUp.widthAnchor constraintGreaterThanOrEqualToConstant:180.0],

        [_saveButton.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-24.0],
        [_saveButton.centerYAnchor constraintEqualToAnchor:_countryPopUp.centerYAnchor],
        [_saveButton.widthAnchor constraintGreaterThanOrEqualToConstant:72.0],

        [_cancelButton.trailingAnchor constraintEqualToAnchor:_saveButton.leadingAnchor constant:-12.0],
        [_cancelButton.centerYAnchor constraintEqualToAnchor:_countryPopUp.centerYAnchor],
        [_cancelButton.widthAnchor constraintGreaterThanOrEqualToConstant:72.0],

        [_spinner.centerXAnchor constraintEqualToAnchor:_saveButton.centerXAnchor],
        [_spinner.centerYAnchor constraintEqualToAnchor:_saveButton.centerYAnchor],
    ]];
}

- (void)populateCountries
{
    [_countryPopUp removeAllItems];

    NSMutableArray<NSDictionary<NSString *, NSString *> *> *countries = [NSMutableArray array];
    for (NSString *code in [NSLocale ISOCountryCodes]) {
        NSString *name = [NSLocale.currentLocale localizedStringForCountryCode:code];
        if (name.length > 0 && code.length > 0) {
            [countries addObject:@{@"code": code, @"name": name}];
        }
    }

    [countries sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]];
    }];

    NSString *activeCountry = MacLCWatchDiscovery.sharedDiscovery.activeServicesCountry;
    if (activeCountry.length == 0) {
        activeCountry = NSLocale.currentLocale.countryCode ?: @"US";
    }

    NSInteger selectIndex = 0;
    for (NSInteger i = 0; i < (NSInteger)countries.count; i++) {
        NSDictionary *c = countries[i];
        [_countryPopUp addItemWithTitle:c[@"name"]];
        NSMenuItem *item = [_countryPopUp itemAtIndex:i];
        item.representedObject = c[@"code"];
        if ([c[@"code"] isEqualToString:activeCountry]) {
            selectIndex = i;
        }
    }
    [_countryPopUp selectItemAtIndex:selectIndex];
}

- (void)tileClicked:(MacLCWatchServiceToggleTile *)tile
{
    if ([_selectedCodes containsObject:tile.serviceCode]) {
        [_selectedCodes removeObject:tile.serviceCode];
        [tile setIsOn:NO animated:!MacLCDesign.reducedMotion];
    } else {
        [_selectedCodes addObject:tile.serviceCode];
        [tile setIsOn:YES animated:!MacLCDesign.reducedMotion];
    }
    _errorLabel.hidden = YES;
}

- (void)beginSheetModalForWindow:(NSWindow *)window completion:(nullable void (^)(BOOL saved))completion
{
    _sheetCompletion = [completion copy];
    [window beginSheet:self.window completionHandler:^(NSModalResponse returnCode) {
        if (self->_sheetCompletion != nil) {
            self->_sheetCompletion(returnCode == NSModalResponseOK);
            self->_sheetCompletion = nil;
        }
    }];
}

- (void)cancelClicked:(id)sender
{
    NSWindow * const sheet = self.window;
    if (sheet.sheetParent != nil) {
        [sheet.sheetParent endSheet:sheet returnCode:NSModalResponseCancel];
    } else {
        [sheet close];
        if (_sheetCompletion != nil) {
            _sheetCompletion(NO);
            _sheetCompletion = nil;
        }
    }
}

- (void)saveClicked:(id)sender
{
    _errorLabel.hidden = YES;
    _saveButton.hidden = YES;
    _cancelButton.enabled = NO;
    _spinner.hidden = NO;
    [_spinner startAnimation:nil];

    NSString * const selectedCountry = _countryPopUp.selectedItem.representedObject ?: @"US";
    NSArray<NSString *> * const codes = [_selectedCodes allObjects];

    __weak typeof(self) weakSelf = self;
    [MacLCWatchDiscovery.sharedDiscovery setServiceCodes:codes
                                                 country:selectedCountry
                                              completion:^(NSError * _Nullable error) {
        MacLCWatchServicesSheetController *strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        [strongSelf->_spinner stopAnimation:nil];
        strongSelf->_spinner.hidden = YES;
        strongSelf->_saveButton.hidden = NO;
        strongSelf->_cancelButton.enabled = YES;

        if (error != nil) {
            strongSelf->_errorLabel.stringValue = error.localizedDescription ?: _NS("Failed to save streaming services.");
            strongSelf->_errorLabel.hidden = NO;
        } else {
            NSWindow * const sheet = strongSelf.window;
            if (sheet.sheetParent != nil) {
                [sheet.sheetParent endSheet:sheet returnCode:NSModalResponseOK];
            } else {
                [sheet close];
                if (strongSelf->_sheetCompletion != nil) {
                    strongSelf->_sheetCompletion(YES);
                    strongSelf->_sheetCompletion = nil;
                }
            }
        }
    }];
}

@end

#pragma mark - Collection Page Header View

@interface MacLCWatchCollectionHeaderView ()
{
    CAGradientLayer *_gradientLayer;
    NSImageView *_symbolImageView;
    NSTextField *_eyebrowLabel;
    NSTextField *_titleLabel;
    NSTextField *_subtitleLabel;
    NSTextField *_countLabel;
    NSButton *_sourceButton;
    NSURL *_sourceURL;

    NSArray<NSView *> *_posterViews;
    NSArray<NSImageView *> *_posterImageViews;
    NSMutableArray<MacLCWatchImageRequest *> *_imageRequests;
}
@end

@implementation MacLCWatchCollectionHeaderView

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        _imageRequests = [NSMutableArray array];
        [self setUpHeaderViews];
    }
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (self) {
        _imageRequests = [NSMutableArray array];
        [self setUpHeaderViews];
    }
    return self;
}

- (void)dealloc
{
    for (MacLCWatchImageRequest *req in _imageRequests) {
        [req cancel];
    }
}

- (void)setUpHeaderViews
{
    self.wantsLayer = YES;

    _gradientLayer = [CAGradientLayer layer];
    _gradientLayer.startPoint = CGPointMake(0.0, 0.0);
    _gradientLayer.endPoint = CGPointMake(1.0, 1.0);
    _gradientLayer.borderWidth = 1.0;
    _gradientLayer.borderColor = NSColor.separatorColor.CGColor;
    [self.layer addSublayer:_gradientLayer];

    _symbolImageView = [[NSImageView alloc] initWithFrame:NSZeroRect];
    _symbolImageView.translatesAutoresizingMaskIntoConstraints = NO;
    _symbolImageView.imageScaling = NSImageScaleProportionallyUpOrDown;
    [self addSubview:_symbolImageView];

    _eyebrowLabel = [NSTextField labelWithString:@""];
    _eyebrowLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _eyebrowLabel.selectable = NO;
    [self addSubview:_eyebrowLabel];

    _titleLabel = [NSTextField wrappingLabelWithString:@""];
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _titleLabel.font = [NSFont systemFontOfSize:MacLCDesign.largeTitle.pointSize weight:NSFontWeightBold];
    _titleLabel.textColor = NSColor.labelColor;
    _titleLabel.maximumNumberOfLines = 2;
    _titleLabel.selectable = NO;
    [self addSubview:_titleLabel];

    _subtitleLabel = [NSTextField wrappingLabelWithString:@""];
    _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _subtitleLabel.font = MacLCDesign.title3;
    _subtitleLabel.textColor = MacLCDesign.secondaryLabel;
    _subtitleLabel.maximumNumberOfLines = 2;
    _subtitleLabel.preferredMaxLayoutWidth = 620.0;
    _subtitleLabel.selectable = NO;
    [self addSubview:_subtitleLabel];

    _countLabel = [NSTextField labelWithString:@""];
    _countLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _countLabel.font = [NSFont systemFontOfSize:MacLCDesign.footnote.pointSize weight:NSFontWeightSemibold];
    _countLabel.selectable = NO;
    [self addSubview:_countLabel];

    _sourceButton = [NSButton buttonWithTitle:@"" target:self action:@selector(sourceClicked:)];
    _sourceButton.bordered = NO;
    _sourceButton.translatesAutoresizingMaskIntoConstraints = NO;
    _sourceButton.font = MacLCDesign.footnote;
    _sourceButton.contentTintColor = NSColor.linkColor;
    _sourceButton.hidden = YES;
    [self addSubview:_sourceButton];

    NSMutableArray<NSView *> *pViews = [NSMutableArray arrayWithCapacity:5];
    NSMutableArray<NSImageView *> *ivs = [NSMutableArray arrayWithCapacity:5];

    for (NSInteger i = 0; i < 5; i++) {
        NSView *wrap = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 110, 165)];
        wrap.wantsLayer = YES;
        wrap.layer.masksToBounds = NO;
        wrap.layer.cornerRadius = MacLCDesign.cornerRadiusSmall;
        wrap.layer.cornerCurve = kCACornerCurveContinuous;
        wrap.layer.shadowColor = NSColor.blackColor.CGColor;
        wrap.layer.shadowRadius = 10.0;
        wrap.layer.shadowOffset = CGSizeMake(0.0, -4.0);
        wrap.layer.shadowOpacity = 0.25;

        NSImageView *iv = [[NSImageView alloc] initWithFrame:NSMakeRect(0, 0, 110, 165)];
        iv.wantsLayer = YES;
        iv.layer.masksToBounds = YES;
        iv.layer.cornerRadius = MacLCDesign.cornerRadiusSmall;
        iv.layer.cornerCurve = kCACornerCurveContinuous;
        iv.layer.backgroundColor = NSColor.quaternarySystemFillColor.CGColor;
        iv.imageScaling = NSImageScaleProportionallyUpOrDown;
        [wrap addSubview:iv];

        [pViews addObject:wrap];
        [ivs addObject:iv];
    }

    /* Subview ordering: index 0 (bottom), index 4, index 1, index 3, index 2 (middle in front) */
    [self addSubview:pViews[0]];
    [self addSubview:pViews[4]];
    [self addSubview:pViews[1]];
    [self addSubview:pViews[3]];
    [self addSubview:pViews[2]];

    _posterViews = [pViews copy];
    _posterImageViews = [ivs copy];

    [NSLayoutConstraint activateConstraints:@[
        [_symbolImageView.topAnchor constraintEqualToAnchor:self.topAnchor constant:40.0],
        [_symbolImageView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:40.0],
        [_symbolImageView.widthAnchor constraintEqualToConstant:34.0],
        [_symbolImageView.heightAnchor constraintEqualToConstant:34.0],

        [_eyebrowLabel.centerYAnchor constraintEqualToAnchor:_symbolImageView.centerYAnchor],
        [_eyebrowLabel.leadingAnchor constraintEqualToAnchor:_symbolImageView.trailingAnchor constant:10.0],

        [_titleLabel.topAnchor constraintEqualToAnchor:_symbolImageView.bottomAnchor constant:12.0],
        [_titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:40.0],
        [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-380.0],

        [_subtitleLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:8.0],
        [_subtitleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:40.0],
        [_subtitleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-380.0],

        [_countLabel.topAnchor constraintEqualToAnchor:_subtitleLabel.bottomAnchor constant:12.0],
        [_countLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:40.0],

        [_sourceButton.leadingAnchor constraintEqualToAnchor:_countLabel.trailingAnchor constant:16.0],
        [_sourceButton.centerYAnchor constraintEqualToAnchor:_countLabel.centerYAnchor],
    ]];
}

- (void)layout
{
    [super layout];
    _gradientLayer.frame = self.bounds;

    /* Fan of 5 posters, 110 x 165, like a hand of cards: -14° ... +14°,
     * rotated about their centres (frameCenterRotation; a layer transform
     * turns about the corner AppKit anchors layers at), outer cards a little
     * lower, the middle one in front. A static tilt is not motion: Reduce
     * Motion keeps it. */
    const CGFloat baseY = self.isFlipped ? (self.bounds.size.height - 28.0 - 165.0) : 28.0;
    const CGFloat midX = self.bounds.size.width - 230.0;
    const CGFloat spread = 62.0;
    const CGFloat degrees[5] = { -14.0, -7.0, 0.0, 7.0, 14.0 };
    const CGFloat drop[5] = { 14.0, 4.0, 0.0, 4.0, 14.0 };
    for (NSInteger i = 0; i < 5; i++) {
        const CGFloat x = midX + (i - 2) * spread - 55.0;
        const CGFloat y = self.isFlipped ? baseY + drop[i] : baseY - drop[i];
        _posterViews[i].frameCenterRotation = 0.0;
        _posterViews[i].frame = NSMakeRect(x, y, 110.0, 165.0);
        _posterViews[i].frameCenterRotation = -degrees[i];
        _posterImageViews[i].frame = NSMakeRect(0, 0, 110.0, 165.0);
    }
    /* Middle on top, then its neighbours (once: reordering re-lays out). */
    if (self.subviews.lastObject != _posterViews[2])
        for (NSNumber *index in @[@0, @4, @1, @3, @2])
            [self addSubview:_posterViews[index.integerValue] positioned:NSWindowAbove relativeTo:nil];
}

- (void)configureWithCollection:(MacLCWatchCollection *)collection
                          items:(NSArray<MacLCAddonItem *> *)items
                        eyebrow:(NSString *)eyebrow
{
    NSColor * const tint = MacLCWatchColorNamed(collection.tintName);

    _gradientLayer.colors = @[
        (__bridge id)[tint colorWithAlphaComponent:0.32].CGColor,
        (__bridge id)[tint colorWithAlphaComponent:0.12].CGColor,
    ];
    _gradientLayer.backgroundColor = NSColor.windowBackgroundColor.CGColor;

    NSImageSymbolConfiguration * const symConfig =
        [NSImageSymbolConfiguration configurationWithPointSize:34.0 weight:NSFontWeightBold];
    NSImage *sym = [NSImage imageWithSystemSymbolName:collection.symbolName accessibilityDescription:nil];
    if (sym != nil) {
        sym = [sym imageWithSymbolConfiguration:symConfig];
    }
    _symbolImageView.image = sym;
    _symbolImageView.contentTintColor = tint;

    if (eyebrow.length > 0) {
        NSFont * const font = [NSFont systemFontOfSize:MacLCDesign.footnote.pointSize weight:NSFontWeightSemibold];
        NSDictionary * const attrs = @{
            NSFontAttributeName: font,
            NSKernAttributeName: @0.6,
            NSForegroundColorAttributeName: tint,
        };
        _eyebrowLabel.attributedStringValue = [[NSAttributedString alloc] initWithString:eyebrow.uppercaseString attributes:attrs];
    } else {
        _eyebrowLabel.attributedStringValue = [[NSAttributedString alloc] initWithString:@""];
    }

    _titleLabel.stringValue = collection.title ?: @"";
    _subtitleLabel.stringValue = collection.subtitle ?: @"";

    const NSUInteger count = collection.entries.count;
    NSString *countStr = @"";
    if ([collection.mediaType isEqualToString:@"movie"]) {
        countStr = [NSString stringWithFormat:_NS("%lu Films"), (unsigned long)count];
    } else if ([collection.mediaType isEqualToString:@"series"]) {
        countStr = [NSString stringWithFormat:_NS("%lu Shows"), (unsigned long)count];
    } else {
        countStr = [NSString stringWithFormat:_NS("%lu Titles"), (unsigned long)count];
    }
    _countLabel.stringValue = countStr;
    _countLabel.textColor = tint;

    _sourceURL = collection.sourceURL;
    if (_sourceURL != nil) {
        _sourceButton.title = [NSString stringWithFormat:_NS("Source: %@"), _sourceURL.host ?: _NS("Web")];
        _sourceButton.hidden = NO;
    } else {
        _sourceButton.hidden = YES;
    }

    for (MacLCWatchImageRequest *req in _imageRequests) {
        [req cancel];
    }
    [_imageRequests removeAllObjects];

    const CGFloat scale = self.window.backingScaleFactor > 0.0 ? self.window.backingScaleFactor : 2.0;
    const NSSize pointSize = NSMakeSize(110.0, 165.0);

    for (NSInteger i = 0; i < 5; i++) {
        if (i < (NSInteger)items.count && items[i].posterURL != nil) {
            __weak typeof(self) weakSelf = self;
            MacLCWatchImageRequest *req = nil;
            NSImage *cached = [MacLCWatchImageCache.sharedCache imageForURL:items[i].posterURL
                                                                 pointSize:pointSize
                                                                     scale:scale
                                                                   request:&req
                                                                completion:^(NSImage * _Nullable image) {
                MacLCWatchCollectionHeaderView *strongSelf = weakSelf;
                if (strongSelf != nil) {
                    if (i < (NSInteger)strongSelf->_posterImageViews.count) {
                        strongSelf->_posterImageViews[i].image = image;
                    }
                }
            }];
            if (req != nil) {
                [_imageRequests addObject:req];
            }
            _posterImageViews[i].image = cached;
        } else {
            _posterImageViews[i].image = nil;
        }
    }
}

- (void)sourceClicked:(id)sender
{
    if (_sourceURL != nil) {
        [NSWorkspace.sharedWorkspace openURL:_sourceURL];
    }
}

@end

NS_ASSUME_NONNULL_END
