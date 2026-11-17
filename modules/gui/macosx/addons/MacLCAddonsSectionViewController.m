/*****************************************************************************
 * MacLCAddonsSectionViewController.m: the Add-ons section of the library window
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

#import "addons/MacLCAddonsSectionViewController.h"
#import "addons/MacLCAddons.h"
#import "library/VLCLibrarySegment.h"
#import "theme/MacLCDesign.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnullability-completeness"
#import "extensions/NSString+Helpers.h"
#pragma clang diagnostic pop

#pragma mark - Metrics

static const CGFloat kColumnMaxWidth = 920.0;
static const CGFloat kColumnSideMargin = 32.0;
static const CGFloat kColumnTopMargin = 20.0;
/* The Now Playing bar floats over the bottom of the library window. */
static const CGFloat kColumnBottomMargin = 96.0;
static const CGFloat kCardPadding = 14.0;
static const CGFloat kInstalledLogoSide = 44.0;
static const CGFloat kDiscoverLogoSide = 40.0;
static const CGFloat kLogoCornerRadius = 10.0;
static const CGFloat kGridCardMinWidth = 300.0;
static const CGFloat kGridGap = 16.0;
static const CGFloat kChipPaddingX = 7.0;
static const CGFloat kChipPaddingY = 2.0;
static const CGFloat kChipGap = 6.0;
static const NSTimeInterval kUpdatedBadgeDuration = 2.0;
static const NSTimeInterval kFlashDuration = 0.6;

typedef NS_ENUM(NSInteger, MacLCAddonsInstallPhase) {
    MacLCAddonsInstallPhaseIdle,
    MacLCAddonsInstallPhaseInstalling,
    MacLCAddonsInstallPhaseInstalled,
    MacLCAddonsInstallPhaseFailed,
};

typedef void (^MacLCAddonsLogoLoader)(NSURL *url, void (^done)(NSImage * _Nullable image));

#pragma mark - Helpers

static NSString *MacLCAddonsTrimmed(NSString *string)
{
    return [string stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static NSTextField *MacLCAddonsLabel(NSString *text, NSFont *font, NSColor *color, BOOL wraps)
{
    NSTextField *label = wraps ? [NSTextField wrappingLabelWithString:text]
                               : [NSTextField labelWithString:text];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.font = font;
    label.textColor = color;
    label.selectable = NO;
    return label;
}

static NSFont *MacLCAddonsSemiboldFont(NSFont *base)
{
    return [NSFont systemFontOfSize:base.pointSize weight:NSFontWeightSemibold];
}

static NSStackView *MacLCAddonsStack(NSUserInterfaceLayoutOrientation orientation,
                                     CGFloat spacing, NSLayoutAttribute alignment)
{
    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.orientation = orientation;
    stack.spacing = spacing;
    stack.alignment = alignment;
    stack.detachesHiddenViews = YES;
    return stack;
}

static void MacLCAddonsAddFullWidth(NSStackView *stack, NSView *view)
{
    view.translatesAutoresizingMaskIntoConstraints = NO;
    [stack addArrangedSubview:view];
    [view.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
}

/* Keeps the views alive when the list did not change, so a card being edited
 * is not torn out of the window by an unrelated notification. */
static void MacLCAddonsSetViews(NSStackView *stack, NSArray<NSView *> *views)
{
    if ([stack.arrangedSubviews isEqualToArray:views]) {
        return;
    }
    for (NSView *view in [stack.arrangedSubviews copy]) {
        [stack removeArrangedSubview:view];
        [view removeFromSuperview];
    }
    for (NSView *view in views) {
        MacLCAddonsAddFullWidth(stack, view);
    }
}

static BOOL MacLCAddonMatchesSearch(MacLCAddon *addon, NSString *query)
{
    if (query.length == 0) {
        return YES;
    }
    const NSStringCompareOptions options = NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch;
    if ([addon.name rangeOfString:query options:options].location != NSNotFound) {
        return YES;
    }
    NSString *description = addon.addonDescription;
    return description.length > 0 && [description rangeOfString:query options:options].location != NSNotFound;
}

static NSArray<NSString *> *MacLCAddonChipTitles(MacLCAddon *addon)
{
    NSMutableArray<NSString *> *titles = [NSMutableArray arrayWithCapacity:4];
    if ([addon.resourceNames containsObject:@"catalog"]) {
        [titles addObject:_NS("Catalogs")];
    }
    if (addon.providesStreams) {
        [titles addObject:_NS("Streams")];
    }
    if ([addon.resourceNames containsObject:@"subtitles"]) {
        [titles addObject:_NS("Subtitles")];
    }
    if (addon.providesSearch) {
        [titles addObject:_NS("Search")];
    }
    return titles;
}

static NSString *MacLCAddonCatalogKey(MacLCAddonCatalog *catalog)
{
    return [NSString stringWithFormat:@"%@/%@/%@", catalog.addon.identifier, catalog.type, catalog.identifier];
}

/* What the Discover list says when a catalog cannot be listed. */
static void MacLCAddonsCatalogErrorWording(NSError * _Nullable error, NSString *serviceName,
                                           NSString * __strong *outTitle, NSString * __strong *outMessage)
{
    NSString *title = nil;
    NSString *message = nil;

    NSString * const unresolvedHost = MacLCAddonsUnresolvedHost(error);
    if (unresolvedHost) {
        title = [NSString stringWithFormat:_NS("Can't Reach %@"), serviceName];
        message = [NSString stringWithFormat:_NS("MacLC can't find the server “%@”. Check your network settings, then try again."), unresolvedHost];
    } else if (error && [error.domain isEqualToString:NSURLErrorDomain]) {
        title = [NSString stringWithFormat:_NS("Can't Reach %@"), serviceName];
        message = _NS("Check your internet connection, then try again.");
    } else if (error && [error.domain isEqualToString:MacLCAddonsErrorDomain]) {
        if (error.code == MacLCAddonsErrorHTTPStatus) {
            title = [NSString stringWithFormat:_NS("%@ Isn't Responding"), serviceName];
            NSNumber *status = error.userInfo[@"status"];
            message = [NSString stringWithFormat:_NS("The add-on answered with error %ld. Try again in a moment."),
                       status ? status.longValue : 0L];
        } else if (error.code == MacLCAddonsErrorBadResponse || error.code == MacLCAddonsErrorNotAnAddon) {
            title = [NSString stringWithFormat:_NS("Unexpected Answer from %@"), serviceName];
            message = _NS("The add-on answered with invalid data.");
        }
    }

    if (!title) {
        title = [NSString stringWithFormat:_NS("Can't Reach %@"), serviceName];
        message = _NS("Check your internet connection, then try again.");
    }
    *outTitle = title;
    *outMessage = message;
}

/* What an install from an address says when it fails. */
static NSString *MacLCAddonsInstallErrorWording(NSError *error)
{
    NSString *message = nil;
    if ([error.domain isEqualToString:MacLCAddonsErrorDomain]) {
        if (error.code == MacLCAddonsErrorBadAddress) {
            message = _NS("This is not an add-on address.");
        } else if (error.code == MacLCAddonsErrorNotAnAddon || error.code == MacLCAddonsErrorBadResponse) {
            message = _NS("This address doesn't lead to an add-on.");
        } else if (error.code == MacLCAddonsErrorHTTPStatus) {
            NSNumber *status = error.userInfo[@"status"];
            message = [NSString stringWithFormat:_NS("The add-on answered with error %ld."),
                       status ? status.longValue : 0L];
        }
    } else if (MacLCAddonsUnresolvedHost(error)) {
        message = [NSString stringWithFormat:_NS("Can't find the server “%@”. Check your network settings."),
                   MacLCAddonsUnresolvedHost(error)];
    } else if ([error.domain isEqualToString:NSURLErrorDomain]) {
        message = _NS("Can't reach this address. Check your internet connection.");
    }
    return message ?: (error.localizedDescription ?: _NS("This address doesn't lead to an add-on."));
}

#pragma mark - Plain views

/* The scroll view's document: flipped so the column starts at the top. */
@interface MacLCAddonsSectionFlippedView : NSView
@end

@implementation MacLCAddonsSectionFlippedView

- (BOOL)isFlipped
{
    return YES;
}

@end

/* Tells its controller when it enters or leaves a window: the view
 * controller callbacks do not reach a child the section only added as a subview. */
@interface MacLCAddonsSectionRootView : NSView
@property (nonatomic, copy, nullable) void (^onWindowChange)(NSWindow * _Nullable window);
/* The width the Discover grid is cut for can change with any layout pass. */
@property (nonatomic, copy, nullable) void (^onLayout)(void);
@end

@implementation MacLCAddonsSectionRootView

- (void)viewDidMoveToWindow
{
    [super viewDidMoveToWindow];
    if (_onWindowChange) {
        _onWindowChange(self.window);
    }
}

- (void)layout
{
    [super layout];
    if (_onLayout) {
        _onLayout();
    }
}

@end

#pragma mark - Logo

@interface MacLCAddonsSectionLogoView : NSView
- (instancetype)initWithSide:(CGFloat)side;
/// Shows the placeholder, then the logo once loaded. Results for another URL are ignored.
- (void)showLogoFromURL:(nullable NSURL *)url loader:(nullable MacLCAddonsLogoLoader)loader;
@end

@implementation MacLCAddonsSectionLogoView
{
    NSImageView *_imageView;
    CGFloat _side;
    BOOL _hasImage;
    NSString *_token;
}

- (instancetype)initWithSide:(CGFloat)side
{
    self = [super initWithFrame:NSZeroRect];
    if (self) {
        _side = side;
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.wantsLayer = YES;
        self.layer.cornerRadius = kLogoCornerRadius;
        self.layer.masksToBounds = YES;

        _imageView = [[NSImageView alloc] initWithFrame:NSZeroRect];
        _imageView.translatesAutoresizingMaskIntoConstraints = NO;
        _imageView.accessibilityElement = NO;
        [self addSubview:_imageView];

        [NSLayoutConstraint activateConstraints:@[
            [self.widthAnchor constraintEqualToConstant:side],
            [self.heightAnchor constraintEqualToConstant:side],
            [_imageView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_imageView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_imageView.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_imageView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        ]];
        [self showPlaceholder];
    }
    return self;
}

- (BOOL)wantsUpdateLayer
{
    return YES;
}

- (void)updateLayer
{
    [self.effectiveAppearance performAsCurrentDrawingAppearance:^{
        self.layer.backgroundColor = self->_hasImage ? NSColor.clearColor.CGColor
                                                     : MacLCDesign.quaternaryLabel.CGColor;
    }];
}

- (void)viewDidChangeEffectiveAppearance
{
    [super viewDidChangeEffectiveAppearance];
    self.needsDisplay = YES;
}

- (void)showPlaceholder
{
    _hasImage = NO;
    _imageView.imageScaling = NSImageScaleNone;
    _imageView.image = [MacLCDesign symbolNamed:@"puzzlepiece.extension"
                                      pointSize:_side * 0.5
                                         weight:NSFontWeightRegular
                             accessibilityLabel:nil];
    _imageView.contentTintColor = MacLCDesign.tertiaryLabel;
    self.needsDisplay = YES;
}

- (void)showLogoFromURL:(NSURL *)url loader:(MacLCAddonsLogoLoader)loader
{
    NSString *token = url.absoluteString;
    if (token && [_token isEqualToString:token] && _hasImage) {
        return;
    }
    _token = token;
    [self showPlaceholder];
    if (!url || !loader) {
        return;
    }
    __weak typeof(self) weakSelf = self;
    loader(url, ^(NSImage * _Nullable image) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || !image || ![strongSelf->_token isEqualToString:token]) {
            return;
        }
        strongSelf->_hasImage = YES;
        strongSelf->_imageView.imageScaling = NSImageScaleProportionallyUpOrDown;
        strongSelf->_imageView.contentTintColor = nil;
        strongSelf->_imageView.image = image;
        strongSelf.needsDisplay = YES;
    });
}

@end

#pragma mark - Chips

@interface MacLCAddonsSectionChipView : NSView
- (instancetype)initWithTitle:(NSString *)title;
@end

@implementation MacLCAddonsSectionChipView

- (instancetype)initWithTitle:(NSString *)title
{
    self = [super initWithFrame:NSZeroRect];
    if (self) {
        self.wantsLayer = YES;
        NSTextField *label = [NSTextField labelWithString:title];
        label.translatesAutoresizingMaskIntoConstraints = YES;
        label.font = MacLCDesign.footnote;
        label.textColor = MacLCDesign.secondaryLabel;
        [label sizeToFit];
        const NSSize labelSize = NSMakeSize(ceil(NSWidth(label.frame)), ceil(NSHeight(label.frame)));
        label.frame = NSMakeRect(kChipPaddingX, kChipPaddingY, labelSize.width, labelSize.height);
        [self addSubview:label];
        [self setFrameSize:NSMakeSize(labelSize.width + 2 * kChipPaddingX,
                                      labelSize.height + 2 * kChipPaddingY)];
    }
    return self;
}

- (BOOL)wantsUpdateLayer
{
    return YES;
}

- (void)updateLayer
{
    [self.effectiveAppearance performAsCurrentDrawingAppearance:^{
        self.layer.backgroundColor = [MacLCDesign.quaternaryLabel colorWithAlphaComponent:0.12].CGColor;
    }];
}

- (void)viewDidChangeEffectiveAppearance
{
    [super viewDidChangeEffectiveAppearance];
    self.needsDisplay = YES;
}

- (void)layout
{
    [super layout];
    self.layer.cornerRadius = NSHeight(self.bounds) / 2.0;
}

@end

/* A row of chips that wraps onto more lines when the card is narrow. */
@interface MacLCAddonsSectionChipsView : NSView
- (void)setTitles:(NSArray<NSString *> *)titles;
@end

@implementation MacLCAddonsSectionChipsView
{
    NSArray<NSView *> *_chips;
    CGFloat _knownWidth;
}

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        _chips = @[];
        [self setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationVertical];
        [self setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationVertical];
    }
    return self;
}

- (BOOL)isFlipped
{
    return YES;
}

- (void)setTitles:(NSArray<NSString *> *)titles
{
    for (NSView *chip in _chips) {
        [chip removeFromSuperview];
    }
    NSMutableArray<NSView *> *chips = [NSMutableArray arrayWithCapacity:titles.count];
    for (NSString *title in titles) {
        MacLCAddonsSectionChipView *chip = [[MacLCAddonsSectionChipView alloc] initWithTitle:title];
        [self addSubview:chip];
        [chips addObject:chip];
    }
    _chips = chips;
    self.hidden = (chips.count == 0);
    [self invalidateIntrinsicContentSize];
    self.needsLayout = YES;
}

- (CGFloat)arrangeForWidth:(CGFloat)width apply:(BOOL)apply
{
    CGFloat x = 0.0, y = 0.0, rowHeight = 0.0;
    for (NSView *chip in _chips) {
        const NSSize size = chip.frame.size;
        if (x > 0.0 && x + size.width > width) {
            x = 0.0;
            y += rowHeight + kChipGap;
            rowHeight = 0.0;
        }
        if (apply) {
            [chip setFrameOrigin:NSMakePoint(x, y)];
        }
        x += size.width + kChipGap;
        rowHeight = MAX(rowHeight, size.height);
    }
    return _chips.count > 0 ? y + rowHeight : 0.0;
}

- (NSSize)intrinsicContentSize
{
    /* Before the first layout the width is unknown: one line is the guess. */
    const CGFloat width = _knownWidth > 0.0 ? _knownWidth : 10000.0;
    return NSMakeSize(NSViewNoIntrinsicMetric, [self arrangeForWidth:width apply:NO]);
}

- (void)layout
{
    [super layout];
    const CGFloat width = NSWidth(self.bounds);
    [self arrangeForWidth:width apply:YES];
    if (fabs(width - _knownWidth) > 0.5) {
        _knownWidth = width;
        [self invalidateIntrinsicContentSize];
    }
}

@end

#pragma mark - Card surface

@interface MacLCAddonsSectionCardView : NSView
/// A static accent tint, for the Reduce Motion version of the flash.
@property (nonatomic) BOOL highlighted;
/// One accent flash (0.6 s) over the card background.
- (void)flash;
@end

@implementation MacLCAddonsSectionCardView

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.wantsLayer = YES;
        self.layer.cornerRadius = MacLCDesign.cornerRadiusLarge;
        self.layer.borderWidth = 0.5;
        self.accessibilityElement = YES;
        self.accessibilityRole = NSAccessibilityGroupRole;
    }
    return self;
}

- (BOOL)wantsUpdateLayer
{
    return YES;
}

- (NSColor *)highlightedBackground
{
    NSColor *base = MacLCDesign.cardBackground;
    return [base blendedColorWithFraction:0.15 ofColor:MacLCDesign.accent]
        ?: [MacLCDesign.accent colorWithAlphaComponent:0.15];
}

- (void)updateLayer
{
    [self.effectiveAppearance performAsCurrentDrawingAppearance:^{
        self.layer.backgroundColor = (self->_highlighted ? [self highlightedBackground]
                                                         : MacLCDesign.cardBackground).CGColor;
        self.layer.borderColor = MacLCDesign.separator.CGColor;
    }];
}

- (void)viewDidChangeEffectiveAppearance
{
    [super viewDidChangeEffectiveAppearance];
    self.needsDisplay = YES;
}

- (void)setHighlighted:(BOOL)highlighted
{
    if (_highlighted == highlighted) {
        return;
    }
    _highlighted = highlighted;
    self.needsDisplay = YES;
}

- (void)flash
{
    [self.effectiveAppearance performAsCurrentDrawingAppearance:^{
        CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:@"backgroundColor"];
        animation.fromValue = (__bridge id)[self highlightedBackground].CGColor;
        animation.toValue = (__bridge id)MacLCDesign.cardBackground.CGColor;
        animation.duration = kFlashDuration;
        animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
        [self.layer addAnimation:animation forKey:@"flash"];
    }];
}

@end

#pragma mark - Installed card

@interface MacLCAddonsSectionInstalledCard : MacLCAddonsSectionCardView <NSTextFieldDelegate>
@property (nonatomic, readonly, nullable) MacLCAddon *addon;
@property (nonatomic, copy, nullable) void (^onRemove)(MacLCAddon *addon);
/// Called with the address pasted in the Configure row.
@property (nonatomic, copy, nullable) void (^onUpdate)(MacLCAddon *addon, NSString *address);
@property (nonatomic, copy, nullable) MacLCAddonsLogoLoader logoLoader;
- (void)configureWithAddon:(MacLCAddon *)addon;
- (void)setUpdating:(BOOL)updating;
- (void)showUpdateError:(nullable NSString *)message;
- (void)collapseConfigureRow;
/// Shows "Updated" next to the version for two seconds.
- (void)showUpdatedBadge;
@end

@implementation MacLCAddonsSectionInstalledCard
{
    MacLCAddonsSectionLogoView *_logoView;
    NSTextField *_nameLabel;
    NSTextField *_versionLabel;
    NSStackView *_updatedStack;
    NSTextField *_descriptionLabel;
    MacLCAddonsSectionChipsView *_chipsView;
    NSButton *_configureButton;
    NSButton *_moreButton;
    NSMenuItem *_removeItem;

    NSStackView *_configureRow;
    NSTextField *_addressField;
    NSButton *_updateButton;
    NSProgressIndicator *_updateSpinner;
    NSTextField *_updateErrorLabel;

    BOOL _updating;
    NSInteger _badgeToken;
}

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        [self buildSubviews];
    }
    return self;
}

- (void)buildSubviews
{
    _logoView = [[MacLCAddonsSectionLogoView alloc] initWithSide:kInstalledLogoSide];
    [self addSubview:_logoView];

    /* Name, version and the "Updated" badge on one line. */
    _nameLabel = MacLCAddonsLabel(@"", MacLCDesign.headline, MacLCDesign.primaryLabel, NO);
    _nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [_nameLabel setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                         forOrientation:NSLayoutConstraintOrientationHorizontal];
    _versionLabel = MacLCAddonsLabel(@"", MacLCDesign.footnote, MacLCDesign.secondaryLabel, NO);
    _versionLabel.lineBreakMode = NSLineBreakByClipping;
    [_versionLabel setContentCompressionResistancePriority:NSLayoutPriorityRequired
                                            forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSImageView *checkView = [NSImageView imageViewWithImage:
        [MacLCDesign symbolNamed:@"checkmark.circle.fill" accessibilityLabel:nil] ?: [[NSImage alloc] init]];
    checkView.translatesAutoresizingMaskIntoConstraints = NO;
    checkView.contentTintColor = MacLCDesign.success;
    checkView.accessibilityElement = NO;
    NSTextField *updatedLabel = MacLCAddonsLabel(_NS("Updated"), MacLCDesign.footnote, MacLCDesign.secondaryLabel, NO);
    _updatedStack = MacLCAddonsStack(NSUserInterfaceLayoutOrientationHorizontal, MacLCDesign.spacingXS,
                                     NSLayoutAttributeCenterY);
    [_updatedStack addArrangedSubview:checkView];
    [_updatedStack addArrangedSubview:updatedLabel];
    _updatedStack.hidden = YES;
    [_updatedStack setContentCompressionResistancePriority:NSLayoutPriorityRequired
                                            forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSStackView *titleRow = MacLCAddonsStack(NSUserInterfaceLayoutOrientationHorizontal, MacLCDesign.spacingS,
                                             NSLayoutAttributeFirstBaseline);
    [titleRow addArrangedSubview:_nameLabel];
    [titleRow addArrangedSubview:_versionLabel];
    [titleRow addArrangedSubview:_updatedStack];

    _descriptionLabel = MacLCAddonsLabel(@"", MacLCDesign.callout, MacLCDesign.secondaryLabel, YES);
    _descriptionLabel.maximumNumberOfLines = 2;
    _descriptionLabel.lineBreakMode = NSLineBreakByTruncatingTail;

    _chipsView = [[MacLCAddonsSectionChipsView alloc] initWithFrame:NSZeroRect];

    [self buildConfigureRow];

    NSStackView *middle = MacLCAddonsStack(NSUserInterfaceLayoutOrientationVertical, MacLCDesign.spacingXS,
                                           NSLayoutAttributeLeading);
    [middle addArrangedSubview:titleRow];
    MacLCAddonsAddFullWidth(middle, _descriptionLabel);
    MacLCAddonsAddFullWidth(middle, _chipsView);
    MacLCAddonsAddFullWidth(middle, _configureRow);
    [middle setCustomSpacing:MacLCDesign.spacingS afterView:_chipsView];
    /* The text column takes whatever the buttons leave. */
    [middle setHuggingPriority:NSLayoutPriorityDefaultLow - 1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [self addSubview:middle];

    _configureButton = [NSButton buttonWithTitle:_NS("Configure…") target:self action:@selector(configureClicked:)];
    _configureButton.translatesAutoresizingMaskIntoConstraints = NO;
    _configureButton.bezelStyle = NSBezelStyleRounded;
    _configureButton.controlSize = NSControlSizeRegular;
    _configureButton.toolTip = _NS("Opens the add-on's own settings page. To apply them, install the address it gives you.");

    _moreButton = [NSButton buttonWithTitle:@"" target:self action:@selector(moreClicked:)];
    _moreButton.translatesAutoresizingMaskIntoConstraints = NO;
    _moreButton.image = [MacLCDesign symbolNamed:@"ellipsis.circle" accessibilityLabel:_NS("More")];
    _moreButton.imagePosition = NSImageOnly;
    _moreButton.bordered = NO;
    _moreButton.accessibilityLabel = _NS("More");
    _moreButton.toolTip = _NS("More");
    /* A fixed hit target: an image-only button would otherwise take the card's spare width. */
    [NSLayoutConstraint activateConstraints:@[
        [_moreButton.widthAnchor constraintEqualToConstant:MacLCDesign.minimumHitTarget],
        [_moreButton.heightAnchor constraintEqualToConstant:MacLCDesign.minimumHitTarget],
    ]];
    [_configureButton setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSStackView *trailing = MacLCAddonsStack(NSUserInterfaceLayoutOrientationHorizontal, MacLCDesign.spacingXS,
                                             NSLayoutAttributeCenterY);
    [trailing addArrangedSubview:_configureButton];
    [trailing addArrangedSubview:_moreButton];
    /* NSStackView's own hugging: the buttons keep their width, the text takes the rest. */
    [trailing setHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    [trailing setContentCompressionResistancePriority:NSLayoutPriorityRequired
                                       forOrientation:NSLayoutConstraintOrientationHorizontal];
    [self addSubview:trailing];

    NSMenu *menu = [[NSMenu alloc] init];
    menu.autoenablesItems = NO;
    NSMenuItem *copyItem = [[NSMenuItem alloc] initWithTitle:_NS("Copy Address")
                                                      action:@selector(copyAddress:)
                                               keyEquivalent:@""];
    copyItem.target = self;
    [menu addItem:copyItem];
    _removeItem = [[NSMenuItem alloc] initWithTitle:_NS("Remove…")
                                             action:@selector(removeClicked:)
                                      keyEquivalent:@""];
    _removeItem.target = self;
    [menu addItem:_removeItem];
    _moreButton.menu = menu;

    [NSLayoutConstraint activateConstraints:@[
        [_logoView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:kCardPadding],
        [_logoView.topAnchor constraintEqualToAnchor:self.topAnchor constant:kCardPadding],
        [_logoView.bottomAnchor constraintLessThanOrEqualToAnchor:self.bottomAnchor constant:-kCardPadding],

        [trailing.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-kCardPadding],
        [trailing.topAnchor constraintEqualToAnchor:self.topAnchor constant:kCardPadding],

        [middle.leadingAnchor constraintEqualToAnchor:_logoView.trailingAnchor constant:MacLCDesign.spacingM],
        [middle.trailingAnchor constraintEqualToAnchor:trailing.leadingAnchor constant:-MacLCDesign.spacingM],
        [middle.topAnchor constraintEqualToAnchor:self.topAnchor constant:kCardPadding],
        [middle.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-kCardPadding],
    ]];
}

- (void)buildConfigureRow
{
    NSTextField *hint = MacLCAddonsLabel(_NS("Save your settings on the add-on's page, then paste the address it gives you:"),
                                         MacLCDesign.footnote, MacLCDesign.secondaryLabel, YES);

    _addressField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    _addressField.translatesAutoresizingMaskIntoConstraints = NO;
    _addressField.placeholderString = @"https://…/manifest.json";
    _addressField.delegate = self;
    _addressField.target = self;
    _addressField.action = @selector(updateClicked:);
    [_addressField setContentHuggingPriority:NSLayoutPriorityDefaultLow
                              forOrientation:NSLayoutConstraintOrientationHorizontal];

    _updateButton = [NSButton buttonWithTitle:_NS("Update") target:self action:@selector(updateClicked:)];
    _updateButton.translatesAutoresizingMaskIntoConstraints = NO;
    _updateButton.bezelStyle = NSBezelStyleRounded;
    _updateButton.enabled = NO;

    _updateSpinner = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
    _updateSpinner.translatesAutoresizingMaskIntoConstraints = NO;
    _updateSpinner.style = NSProgressIndicatorStyleSpinning;
    _updateSpinner.controlSize = NSControlSizeSmall;
    _updateSpinner.displayedWhenStopped = NO;
    _updateSpinner.hidden = YES;

    NSStackView *fieldRow = MacLCAddonsStack(NSUserInterfaceLayoutOrientationHorizontal, MacLCDesign.spacingS,
                                             NSLayoutAttributeCenterY);
    [fieldRow addArrangedSubview:_addressField];
    [fieldRow addArrangedSubview:_updateButton];
    [fieldRow addArrangedSubview:_updateSpinner];

    _updateErrorLabel = MacLCAddonsLabel(@"", MacLCDesign.footnote, MacLCDesign.destructive, YES);
    _updateErrorLabel.hidden = YES;

    _configureRow = MacLCAddonsStack(NSUserInterfaceLayoutOrientationVertical, MacLCDesign.spacingXS,
                                     NSLayoutAttributeLeading);
    MacLCAddonsAddFullWidth(_configureRow, hint);
    MacLCAddonsAddFullWidth(_configureRow, fieldRow);
    MacLCAddonsAddFullWidth(_configureRow, _updateErrorLabel);
    _configureRow.hidden = YES;
}

- (void)configureWithAddon:(MacLCAddon *)addon
{
    _addon = addon;
    _nameLabel.stringValue = addon.name ?: @"";
    _versionLabel.stringValue = addon.version.length > 0
        ? [NSString stringWithFormat:_NS("Version %@"), addon.version] : @"";
    _versionLabel.hidden = (addon.version.length == 0);

    _descriptionLabel.stringValue = addon.addonDescription ?: @"";
    _descriptionLabel.hidden = (addon.addonDescription.length == 0);

    [_chipsView setTitles:MacLCAddonChipTitles(addon)];

    _configureButton.hidden = (addon.configureURL == nil);
    if (!addon.configureURL) {
        [self collapseConfigureRow];
    }
    _removeItem.enabled = addon.isRemovable;

    [_logoView showLogoFromURL:addon.logoURL loader:self.logoLoader];
    self.accessibilityLabel = [NSString stringWithFormat:_NS("%@, version %@"), addon.name ?: @"", addon.version ?: @""];
}

#pragma mark Actions

- (void)moreClicked:(id)sender
{
    /* Under the button, as a pull-down would open. */
    const CGFloat below = _moreButton.isFlipped ? NSHeight(_moreButton.bounds) + 4.0 : -4.0;
    [_moreButton.menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(0.0, below) inView:_moreButton];
}

- (void)copyAddress:(id)sender
{
    if (!_addon) {
        return;
    }
    NSPasteboard *pasteboard = NSPasteboard.generalPasteboard;
    [pasteboard clearContents];
    [pasteboard setString:_addon.transportURL forType:NSPasteboardTypeString];
}

- (void)removeClicked:(id)sender
{
    if (_addon && _onRemove) {
        _onRemove(_addon);
    }
}

- (void)configureClicked:(id)sender
{
    if (!_addon.configureURL) {
        return;
    }
    if (!_configureRow.hidden) {
        [self collapseConfigureRow];
        return;
    }
    [NSWorkspace.sharedWorkspace openURL:_addon.configureURL];
    _configureRow.hidden = NO;
    [self.window makeFirstResponder:_addressField];
}

- (void)collapseConfigureRow
{
    if (_configureRow.hidden) {
        return;
    }
    _configureRow.hidden = YES;
    _addressField.stringValue = @"";
    _updateButton.enabled = NO;
    [self showUpdateError:nil];
    if (self.window && [self.window.firstResponder isKindOfClass:[NSView class]]
        && [(NSView *)self.window.firstResponder isDescendantOf:self]) {
        [self.window makeFirstResponder:nil];
    }
}

- (void)cancelOperation:(id)sender
{
    [self collapseConfigureRow];
}

- (void)updateClicked:(id)sender
{
    NSString *address = MacLCAddonsTrimmed(_addressField.stringValue);
    if (address.length == 0 || _updating || !_addon) {
        return;
    }
    [self showUpdateError:nil];
    if (_onUpdate) {
        _onUpdate(_addon, address);
    }
}

- (void)setUpdating:(BOOL)updating
{
    _updating = updating;
    _addressField.enabled = !updating;
    _updateButton.enabled = !updating && MacLCAddonsTrimmed(_addressField.stringValue).length > 0;
    _updateSpinner.hidden = !updating;
    if (updating) {
        [_updateSpinner startAnimation:nil];
    } else {
        [_updateSpinner stopAnimation:nil];
    }
}

- (void)showUpdateError:(NSString *)message
{
    _updateErrorLabel.stringValue = message ?: @"";
    _updateErrorLabel.hidden = (message.length == 0);
}

- (void)showUpdatedBadge
{
    const NSInteger token = ++_badgeToken;
    _updatedStack.hidden = NO;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kUpdatedBadgeDuration * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf && strongSelf->_badgeToken == token) {
            strongSelf->_updatedStack.hidden = YES;
        }
    });
}

#pragma mark NSTextFieldDelegate

- (void)controlTextDidChange:(NSNotification *)notification
{
    _updateButton.enabled = !_updating && MacLCAddonsTrimmed(_addressField.stringValue).length > 0;
    [self showUpdateError:nil];
}

- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)commandSelector
{
    if (commandSelector == @selector(cancelOperation:)) {
        [self collapseConfigureRow];
        return YES;
    }
    return NO;
}

@end

#pragma mark - Discover card

@interface MacLCAddonsSectionDiscoverCell : NSStackView
@property (nonatomic, readonly) MacLCAddon *addon;
@property (nonatomic, readonly) MacLCAddonsSectionCardView *surface;
@property (nonatomic, copy, nullable) void (^onInstall)(MacLCAddon *addon);
- (instancetype)initWithAddon:(MacLCAddon *)addon logoLoader:(nullable MacLCAddonsLogoLoader)loader;
- (void)applyPhase:(MacLCAddonsInstallPhase)phase message:(nullable NSString *)message;
@end

@implementation MacLCAddonsSectionDiscoverCell
{
    MacLCAddonsSectionCardView *_surface;
    NSButton *_installButton;
    NSProgressIndicator *_spinner;
    NSTextField *_errorLabel;
}

- (instancetype)initWithAddon:(MacLCAddon *)addon logoLoader:(MacLCAddonsLogoLoader)loader
{
    self = [super initWithFrame:NSZeroRect];
    if (self) {
        _addon = addon;
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.orientation = NSUserInterfaceLayoutOrientationVertical;
        self.spacing = MacLCDesign.spacingXS;
        self.alignment = NSLayoutAttributeLeading;
        self.detachesHiddenViews = YES;

        _surface = [[MacLCAddonsSectionCardView alloc] initWithFrame:NSZeroRect];
        _surface.accessibilityLabel = [NSString stringWithFormat:_NS("%@, version %@"), addon.name ?: @"", addon.version ?: @""];
        [self buildSurfaceWithLogoLoader:loader];
        MacLCAddonsAddFullWidth(self, _surface);

        _errorLabel = MacLCAddonsLabel(@"", MacLCDesign.footnote, MacLCDesign.destructive, YES);
        _errorLabel.hidden = YES;
        MacLCAddonsAddFullWidth(self, _errorLabel);
    }
    return self;
}

- (MacLCAddonsSectionCardView *)surface
{
    return _surface;
}

- (void)buildSurfaceWithLogoLoader:(MacLCAddonsLogoLoader)loader
{
    MacLCAddonsSectionLogoView *logo = [[MacLCAddonsSectionLogoView alloc] initWithSide:kDiscoverLogoSide];
    [logo showLogoFromURL:_addon.logoURL loader:loader];
    [_surface addSubview:logo];

    NSTextField *name = MacLCAddonsLabel(_addon.name ?: @"", MacLCDesign.headline, MacLCDesign.primaryLabel, NO);
    name.lineBreakMode = NSLineBreakByTruncatingTail;

    NSTextField *description = MacLCAddonsLabel(_addon.addonDescription ?: @"", MacLCDesign.callout,
                                                MacLCDesign.secondaryLabel, YES);
    description.maximumNumberOfLines = 3;
    description.lineBreakMode = NSLineBreakByTruncatingTail;
    description.hidden = (_addon.addonDescription.length == 0);

    MacLCAddonsSectionChipsView *chips = [[MacLCAddonsSectionChipsView alloc] initWithFrame:NSZeroRect];
    [chips setTitles:MacLCAddonChipTitles(_addon)];

    NSStackView *text = MacLCAddonsStack(NSUserInterfaceLayoutOrientationVertical, MacLCDesign.spacingXS,
                                         NSLayoutAttributeLeading);
    MacLCAddonsAddFullWidth(text, name);
    MacLCAddonsAddFullWidth(text, description);
    MacLCAddonsAddFullWidth(text, chips);
    [_surface addSubview:text];

    _spinner = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
    _spinner.translatesAutoresizingMaskIntoConstraints = NO;
    _spinner.style = NSProgressIndicatorStyleSpinning;
    _spinner.controlSize = NSControlSizeSmall;
    _spinner.displayedWhenStopped = NO;
    _spinner.hidden = YES;

    _installButton = [NSButton buttonWithTitle:_NS("Install") target:self action:@selector(installClicked:)];
    _installButton.translatesAutoresizingMaskIntoConstraints = NO;
    _installButton.bezelStyle = NSBezelStyleGlass;
    _installButton.controlSize = NSControlSizeSmall;

    NSStackView *installRow = MacLCAddonsStack(NSUserInterfaceLayoutOrientationHorizontal, MacLCDesign.spacingS,
                                               NSLayoutAttributeCenterY);
    [installRow addArrangedSubview:_spinner];
    [installRow addArrangedSubview:_installButton];
    [_surface addSubview:installRow];

    /* Nothing caps the card's height from above: bias it to its content. */
    NSLayoutConstraint *compactHeight = [_surface.heightAnchor constraintEqualToConstant:0.0];
    compactHeight.priority = NSLayoutPriorityDefaultLow - 1;

    [NSLayoutConstraint activateConstraints:@[
        compactHeight,
        [logo.leadingAnchor constraintEqualToAnchor:_surface.leadingAnchor constant:kCardPadding],
        [logo.topAnchor constraintEqualToAnchor:_surface.topAnchor constant:kCardPadding],

        [text.leadingAnchor constraintEqualToAnchor:logo.trailingAnchor constant:MacLCDesign.spacingM],
        [text.trailingAnchor constraintEqualToAnchor:_surface.trailingAnchor constant:-kCardPadding],
        [text.topAnchor constraintEqualToAnchor:_surface.topAnchor constant:kCardPadding],
        [text.bottomAnchor constraintLessThanOrEqualToAnchor:installRow.topAnchor constant:-MacLCDesign.spacingM],

        [installRow.trailingAnchor constraintEqualToAnchor:_surface.trailingAnchor constant:-kCardPadding],
        [installRow.bottomAnchor constraintEqualToAnchor:_surface.bottomAnchor constant:-kCardPadding],
        [installRow.leadingAnchor constraintGreaterThanOrEqualToAnchor:_surface.leadingAnchor constant:kCardPadding],
    ]];
}

- (void)installClicked:(id)sender
{
    if (_onInstall) {
        _onInstall(_addon);
    }
}

- (void)applyPhase:(MacLCAddonsInstallPhase)phase message:(NSString *)message
{
    BOOL installing = (phase == MacLCAddonsInstallPhaseInstalling);
    _spinner.hidden = !installing;
    if (installing) {
        [_spinner startAnimation:nil];
    } else {
        [_spinner stopAnimation:nil];
    }

    switch (phase) {
        case MacLCAddonsInstallPhaseInstalling:
            _installButton.title = _NS("Installing…");
            _installButton.image = nil;
            _installButton.enabled = NO;
            break;
        case MacLCAddonsInstallPhaseInstalled:
            _installButton.title = _NS("Installed");
            _installButton.image = [MacLCDesign symbolNamed:@"checkmark" accessibilityLabel:nil];
            _installButton.imagePosition = NSImageLeading;
            _installButton.enabled = NO;
            break;
        case MacLCAddonsInstallPhaseIdle:
        case MacLCAddonsInstallPhaseFailed:
            _installButton.title = _NS("Install");
            _installButton.image = nil;
            _installButton.enabled = YES;
            break;
    }

    BOOL failed = (phase == MacLCAddonsInstallPhaseFailed && message.length > 0);
    _errorLabel.stringValue = failed ? message : @"";
    _errorLabel.hidden = !failed;
}

@end

#pragma mark - Root view controller

@interface MacLCAddonsSectionRootViewController : NSViewController <NSTextFieldDelegate>
- (void)applySearchString:(NSString *)searchString;
@end

@implementation MacLCAddonsSectionRootViewController
{
    NSScrollView *_scrollView;
    NSStackView *_column;
    NSStackView *_installedStack;
    NSTextField *_installedEmptyLabel;
    NSStackView *_discoverSection;
    NSStackView *_discoverBody;
    NSSegmentedControl *_segmentedControl;

    NSString *_searchString;
    BOOL _inWindow;
    BOOL _didRefreshManifests;
    __weak MacLCAddonsSectionCardView *_highlightedCard;

    NSMutableDictionary<NSString *, MacLCAddonsSectionInstalledCard *> *_installedCards;
    NSMutableDictionary<NSString *, MacLCAddonRequest *> *_updateRequests;

    NSArray<MacLCAddonCatalog *> *_catalogs;
    NSString *_selectedCatalogKey;
    NSMutableDictionary<NSString *, NSArray<MacLCAddon *> *> *_catalogCache;
    NSError *_catalogError;
    BOOL _loadingCatalog;
    MacLCAddonRequest *_catalogRequest;

    NSMutableArray<MacLCAddonsSectionDiscoverCell *> *_discoverCells;
    NSInteger _gridColumns;
    BOOL _gridRebuildPending;
    NSMutableDictionary<NSString *, NSNumber *> *_installPhases;
    NSMutableDictionary<NSString *, NSString *> *_installMessages;
    NSMutableDictionary<NSString *, MacLCAddonRequest *> *_installRequests;

    MacLCAddonsLogoLoader _logoLoader;
    NSCache<NSString *, NSImage *> *_logoCache;
    NSMutableDictionary<NSString *, NSMutableArray *> *_logoWaiters;
    NSMutableDictionary<NSString *, NSURLSessionDataTask *> *_logoTasks;
    NSMutableSet<NSString *> *_logoFailures;

    NSWindow *_sheet;
    NSTextField *_sheetField;
    NSStackView *_sheetProgressRow;
    NSProgressIndicator *_sheetSpinner;
    NSTextField *_sheetErrorLabel;
    NSButton *_sheetInstallButton;
    MacLCAddonRequest *_sheetRequest;
    BOOL _sheetInstalling;
}

- (instancetype)initWithNibName:(NSNibName)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        _searchString = @"";
        _installedCards = [NSMutableDictionary dictionary];
        _updateRequests = [NSMutableDictionary dictionary];
        _catalogs = @[];
        _catalogCache = [NSMutableDictionary dictionary];
        _discoverCells = [NSMutableArray array];
        _installPhases = [NSMutableDictionary dictionary];
        _installMessages = [NSMutableDictionary dictionary];
        _installRequests = [NSMutableDictionary dictionary];
        _logoCache = [[NSCache alloc] init];
        _logoCache.countLimit = 150;
        _logoWaiters = [NSMutableDictionary dictionary];
        _logoTasks = [NSMutableDictionary dictionary];
        _logoFailures = [NSMutableSet set];

        __weak typeof(self) weakSelf = self;
        _logoLoader = ^(NSURL *url, void (^done)(NSImage * _Nullable image)) {
            [weakSelf loadLogoForURL:url completion:done];
        };
        [NSNotificationCenter.defaultCenter addObserver:self
                                               selector:@selector(addonsDidChange:)
                                                   name:MacLCAddonsDidChangeNotification
                                                 object:nil];
    }
    return self;
}

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [_catalogRequest cancel];
    [_sheetRequest cancel];
    for (MacLCAddonRequest *request in _installRequests.allValues) {
        [request cancel];
    }
    for (MacLCAddonRequest *request in _updateRequests.allValues) {
        [request cancel];
    }
    for (NSURLSessionDataTask *task in _logoTasks.allValues) {
        [task cancel];
    }
}

#pragma mark View

- (NSView *)makeIntroRow
{
    NSView *row = [[NSView alloc] initWithFrame:NSZeroRect];
    row.translatesAutoresizingMaskIntoConstraints = NO;

    NSImageView *icon = [[NSImageView alloc] initWithFrame:NSZeroRect];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.image = [MacLCDesign symbolNamed:@"info.circle" pointSize:16.0 weight:NSFontWeightRegular accessibilityLabel:nil];
    icon.contentTintColor = MacLCDesign.secondaryLabel;
    icon.accessibilityElement = NO;
    [row addSubview:icon];

    NSTextField *text = MacLCAddonsLabel(
        _NS("Add-ons bring catalogs, streams and subtitles to Watch. They are third-party services: MacLC sends them the titles you look up, and people in a torrent can see your IP address. Install only add-ons you trust."),
        MacLCDesign.callout, MacLCDesign.secondaryLabel, YES);
    [row addSubview:text];

    NSButton *addButton = [NSButton buttonWithTitle:_NS("Add from Address…")
                                             target:self
                                             action:@selector(showAddressSheet:)];
    addButton.translatesAutoresizingMaskIntoConstraints = NO;
    addButton.bezelStyle = NSBezelStyleGlass;
    addButton.controlSize = NSControlSizeLarge;
    [addButton setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    [addButton setContentCompressionResistancePriority:NSLayoutPriorityRequired
                                        forOrientation:NSLayoutConstraintOrientationHorizontal];
    [row addSubview:addButton];

    [NSLayoutConstraint activateConstraints:@[
        [icon.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
        [icon.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [text.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:MacLCDesign.spacingS],
        [text.topAnchor constraintEqualToAnchor:row.topAnchor],
        [text.bottomAnchor constraintEqualToAnchor:row.bottomAnchor],
        [text.trailingAnchor constraintEqualToAnchor:addButton.leadingAnchor constant:-MacLCDesign.spacingL],
        [addButton.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
        [addButton.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [addButton.topAnchor constraintGreaterThanOrEqualToAnchor:row.topAnchor],
        [addButton.bottomAnchor constraintLessThanOrEqualToAnchor:row.bottomAnchor],
    ]];
    return row;
}

- (NSTextField *)makeHeaderWithTitle:(NSString *)title
{
    NSTextField *header = MacLCAddonsLabel(title, MacLCAddonsSemiboldFont(MacLCDesign.title3),
                                           MacLCDesign.primaryLabel, NO);
    header.accessibilityRole = NSAccessibilityHeadingRole;
    return header;
}

- (void)loadView
{
    MacLCAddonsSectionRootView *root = [[MacLCAddonsSectionRootView alloc] initWithFrame:NSMakeRect(0, 0, 800, 600)];
    __weak typeof(self) weakSelf = self;
    root.onWindowChange = ^(NSWindow * _Nullable window) {
        [weakSelf rootViewWindowDidChange:window];
    };
    root.onLayout = ^{
        [weakSelf rootViewDidLayout];
    };
    self.view = root;

    _scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _scrollView.hasVerticalScroller = YES;
    _scrollView.autohidesScrollers = YES;
    _scrollView.drawsBackground = NO;
    _scrollView.borderType = NSNoBorder;
    [root addSubview:_scrollView];

    MacLCAddonsSectionFlippedView *document = [[MacLCAddonsSectionFlippedView alloc] initWithFrame:NSZeroRect];
    document.translatesAutoresizingMaskIntoConstraints = NO;
    _scrollView.documentView = document;
    NSClipView *clip = _scrollView.contentView;

    _column = MacLCAddonsStack(NSUserInterfaceLayoutOrientationVertical, MacLCDesign.spacingXL, NSLayoutAttributeLeading);
    [document addSubview:_column];

    NSLayoutConstraint *preferredWidth = [_column.widthAnchor constraintEqualToConstant:kColumnMaxWidth];
    preferredWidth.priority = NSLayoutPriorityDefaultHigh - 1;
    [NSLayoutConstraint activateConstraints:@[
        /* Beside the floating sidebar, not under it: the document is then as
         * wide as what can be seen. The top still runs under the toolbar. */
        [_scrollView.leadingAnchor constraintEqualToAnchor:root.safeAreaLayoutGuide.leadingAnchor],
        [_scrollView.trailingAnchor constraintEqualToAnchor:root.safeAreaLayoutGuide.trailingAnchor],
        [_scrollView.topAnchor constraintEqualToAnchor:root.topAnchor],
        [_scrollView.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],

        [document.leadingAnchor constraintEqualToAnchor:clip.leadingAnchor],
        [document.trailingAnchor constraintEqualToAnchor:clip.trailingAnchor],
        [document.topAnchor constraintEqualToAnchor:clip.topAnchor],

        [_column.topAnchor constraintEqualToAnchor:document.topAnchor constant:kColumnTopMargin],
        [_column.bottomAnchor constraintEqualToAnchor:document.bottomAnchor constant:-kColumnBottomMargin],
        [_column.centerXAnchor constraintEqualToAnchor:document.centerXAnchor],
        [_column.widthAnchor constraintLessThanOrEqualToConstant:kColumnMaxWidth],
        [_column.leadingAnchor constraintGreaterThanOrEqualToAnchor:document.leadingAnchor constant:kColumnSideMargin],
        [_column.trailingAnchor constraintLessThanOrEqualToAnchor:document.trailingAnchor constant:-kColumnSideMargin],
        preferredWidth,
    ]];

    // Intro
    NSView *intro = [self makeIntroRow];
    MacLCAddonsAddFullWidth(_column, intro);
    [_column setCustomSpacing:MacLCDesign.spacingXXL afterView:intro];

    // Installed
    NSTextField *installedHeader = [self makeHeaderWithTitle:_NS("Installed")];
    MacLCAddonsAddFullWidth(_column, installedHeader);
    [_column setCustomSpacing:MacLCDesign.spacingM afterView:installedHeader];

    _installedEmptyLabel = MacLCAddonsLabel(@"", MacLCDesign.callout, MacLCDesign.secondaryLabel, YES);
    _installedEmptyLabel.hidden = YES;
    MacLCAddonsAddFullWidth(_column, _installedEmptyLabel);
    [_column setCustomSpacing:MacLCDesign.spacingM afterView:_installedEmptyLabel];

    _installedStack = MacLCAddonsStack(NSUserInterfaceLayoutOrientationVertical, MacLCDesign.spacingM, NSLayoutAttributeLeading);
    MacLCAddonsAddFullWidth(_column, _installedStack);

    // Discover
    NSTextField *discoverHeader = [self makeHeaderWithTitle:_NS("Discover")];
    _segmentedControl = [NSSegmentedControl segmentedControlWithLabels:@[@""]
                                                          trackingMode:NSSegmentSwitchTrackingSelectOne
                                                                target:self
                                                                action:@selector(catalogSegmentChanged:)];
    _segmentedControl.translatesAutoresizingMaskIntoConstraints = NO;
    _segmentedControl.accessibilityLabel = _NS("Discover");

    NSStackView *discoverHeaderRow = MacLCAddonsStack(NSUserInterfaceLayoutOrientationHorizontal, MacLCDesign.spacingL,
                                                      NSLayoutAttributeCenterY);
    [discoverHeaderRow addArrangedSubview:discoverHeader];
    [discoverHeaderRow addArrangedSubview:_segmentedControl];

    _discoverBody = MacLCAddonsStack(NSUserInterfaceLayoutOrientationVertical, kGridGap, NSLayoutAttributeLeading);

    _discoverSection = MacLCAddonsStack(NSUserInterfaceLayoutOrientationVertical, MacLCDesign.spacingM, NSLayoutAttributeLeading);
    MacLCAddonsAddFullWidth(_discoverSection, discoverHeaderRow);
    MacLCAddonsAddFullWidth(_discoverSection, _discoverBody);
    _discoverSection.hidden = YES;
    MacLCAddonsAddFullWidth(_column, _discoverSection);

    [self reloadInstalled];
    [self reloadCatalogs];
}

- (void)rootViewDidLayout
{
    if (_discoverCells.count == 0 || _gridRebuildPending
        || [self gridColumnsForWidth:NSWidth(_column.frame)] == _gridColumns) {
        return;
    }
    /* Rebuilding inside the layout pass would feed back into it. */
    _gridRebuildPending = YES;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        strongSelf->_gridRebuildPending = NO;
        if ([strongSelf gridColumnsForWidth:NSWidth(strongSelf->_column.frame)] != strongSelf->_gridColumns) {
            [strongSelf renderDiscoverBody];
        }
    });
}

#pragma mark Appearing and leaving

- (void)rootViewWindowDidChange:(NSWindow *)window
{
    if (window) {
        _inWindow = YES;
        if (!_didRefreshManifests) {
            _didRefreshManifests = YES;
            [MacLCAddonStore.sharedStore refreshManifests];
        }
        [self loadSelectedCatalogIfNeeded];
        [self renderDiscoverBody];
    } else {
        _inWindow = NO;
        [_catalogRequest cancel];
        _catalogRequest = nil;
        _loadingCatalog = NO;
    }
}

#pragma mark Search

- (void)applySearchString:(NSString *)searchString
{
    _searchString = MacLCAddonsTrimmed(searchString ?: @"");
    _highlightedCard.highlighted = NO;
    if (self.isViewLoaded) {
        [self reloadInstalled];
        [self renderDiscoverBody];
    }
}

- (NSArray<MacLCAddon *> *)filteredAddons:(NSArray<MacLCAddon *> *)addons
{
    if (_searchString.length == 0) {
        return addons;
    }
    NSMutableArray<MacLCAddon *> *shown = [NSMutableArray array];
    for (MacLCAddon *addon in addons) {
        if (MacLCAddonMatchesSearch(addon, _searchString)) {
            [shown addObject:addon];
        }
    }
    return shown;
}

- (NSString *)noMatchWording
{
    return [NSString stringWithFormat:_NS("No add-ons match “%@”."), _searchString];
}

#pragma mark Installed

- (void)addonsDidChange:(NSNotification *)notification
{
    /* Posted on the main queue, before an install's completion runs: the
     * cards it looks for exist by then. */
    [self reloadInstalled];
    [self reloadCatalogs];
    [self refreshDiscoverPhases];
}

- (MacLCAddonsSectionInstalledCard *)makeInstalledCard
{
    MacLCAddonsSectionInstalledCard *card = [[MacLCAddonsSectionInstalledCard alloc] initWithFrame:NSZeroRect];
    card.logoLoader = _logoLoader;
    __weak typeof(self) weakSelf = self;
    card.onRemove = ^(MacLCAddon *addon) {
        [weakSelf promptRemoveAddon:addon];
    };
    card.onUpdate = ^(MacLCAddon *addon, NSString *address) {
        [weakSelf updateAddon:addon fromAddress:address];
    };
    return card;
}

- (void)reloadInstalled
{
    NSMutableSet<NSString *> *identifiers = [NSMutableSet set];
    NSMutableArray<NSView *> *shown = [NSMutableArray array];
    for (MacLCAddon *addon in MacLCAddonStore.sharedStore.installedAddons) {
        MacLCAddonsSectionInstalledCard *card = _installedCards[addon.identifier];
        if (!card) {
            card = [self makeInstalledCard];
            _installedCards[addon.identifier] = card;
        }
        [card configureWithAddon:addon];
        [identifiers addObject:addon.identifier];
        if (MacLCAddonMatchesSearch(addon, _searchString)) {
            [shown addObject:card];
        }
    }
    for (NSString *identifier in [_installedCards.allKeys copy]) {
        if (![identifiers containsObject:identifier]) {
            [_installedCards removeObjectForKey:identifier];
        }
    }

    MacLCAddonsSetViews(_installedStack, shown);
    _installedStack.hidden = (shown.count == 0);
    BOOL noMatch = (shown.count == 0 && _searchString.length > 0);
    _installedEmptyLabel.stringValue = noMatch ? [self noMatchWording] : @"";
    _installedEmptyLabel.hidden = !noMatch;
}

- (void)promptRemoveAddon:(MacLCAddon *)addon
{
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = [NSString stringWithFormat:_NS("Remove “%@”?"), addon.name];
    alert.informativeText = _NS("Watch stops showing what it lists. You can install it again from Discover or from its address.");
    NSButton *removeButton = [alert addButtonWithTitle:_NS("Remove")];
    removeButton.hasDestructiveAction = YES;
    [alert addButtonWithTitle:_NS("Cancel")];

    void (^handler)(NSModalResponse) = ^(NSModalResponse response) {
        if (response == NSAlertFirstButtonReturn) {
            [MacLCAddonStore.sharedStore removeAddon:addon];
        }
    };
    NSWindow *window = self.view.window;
    if (window) {
        [alert beginSheetModalForWindow:window completionHandler:handler];
    } else {
        handler([alert runModal]);
    }
}

- (void)updateAddon:(MacLCAddon *)addon fromAddress:(NSString *)address
{
    NSString *identifier = addon.identifier;
    if (_updateRequests[identifier]) {
        return;
    }
    [_installedCards[identifier] setUpdating:YES];

    __block BOOL completed = NO;
    __weak typeof(self) weakSelf = self;
    MacLCAddonRequest *request = [MacLCAddonStore.sharedStore installFromAddress:address
                                                                      completion:^(MacLCAddon * _Nullable updated, BOOL __unused replaced, NSError * _Nullable error) {
        completed = YES;
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        [strongSelf->_updateRequests removeObjectForKey:identifier];
        MacLCAddonsSectionInstalledCard *card = strongSelf->_installedCards[identifier];
        [card setUpdating:NO];
        if (error) {
            [card showUpdateError:MacLCAddonsInstallErrorWording(error)];
            return;
        }
        [card collapseConfigureRow];
        if (updated && [updated.identifier isEqualToString:identifier]) {
            [card showUpdatedBadge];
        } else if (updated) {
            [strongSelf revealAddon:updated];
        }
    }];
    if (!completed) {
        _updateRequests[identifier] = request;
    }
}

- (void)revealAddon:(MacLCAddon *)addon
{
    MacLCAddonsSectionInstalledCard *card = _installedCards[addon.identifier];
    if (!card || !card.window || card.superview == nil) {
        return;
    }
    [self.view layoutSubtreeIfNeeded];
    [card scrollRectToVisible:NSInsetRect(card.bounds, 0.0, -MacLCDesign.spacingL)];
    _highlightedCard.highlighted = NO;
    if (MacLCDesign.reducedMotion) {
        card.highlighted = YES;
        _highlightedCard = card;
    } else {
        [card flash];
    }
}

#pragma mark Discover

- (NSInteger)gridColumnsForWidth:(CGFloat)width
{
    return MAX(1, (NSInteger)floor((width + kGridGap) / (kGridCardMinWidth + kGridGap)));
}

- (nullable MacLCAddonCatalog *)selectedCatalog
{
    for (MacLCAddonCatalog *catalog in _catalogs) {
        if ([MacLCAddonCatalogKey(catalog) isEqualToString:_selectedCatalogKey]) {
            return catalog;
        }
    }
    return nil;
}

- (void)reloadCatalogs
{
    NSArray<MacLCAddonCatalog *> *catalogs = MacLCAddonStore.sharedStore.addonCatalogs;
    _catalogs = catalogs;
    _discoverSection.hidden = (catalogs.count == 0);
    if (catalogs.count == 0) {
        [_catalogRequest cancel];
        _catalogRequest = nil;
        _loadingCatalog = NO;
        _catalogError = nil;
        _selectedCatalogKey = nil;
        return;
    }

    NSCountedSet<NSString *> *nameCounts = [[NSCountedSet alloc] init];
    for (MacLCAddonCatalog *catalog in catalogs) {
        [nameCounts addObject:catalog.name ?: @""];
    }

    _segmentedControl.segmentCount = (NSInteger)catalogs.count;
    NSInteger selectedIndex = -1;
    for (NSUInteger i = 0; i < catalogs.count; i++) {
        MacLCAddonCatalog *catalog = catalogs[i];
        NSString *label = catalog.name ?: @"";
        if ([nameCounts countForObject:label] > 1) {
            label = [NSString stringWithFormat:@"%@ — %@", label, catalog.addon.name];
        }
        [_segmentedControl setLabel:label forSegment:(NSInteger)i];
        if ([MacLCAddonCatalogKey(catalog) isEqualToString:_selectedCatalogKey]) {
            selectedIndex = (NSInteger)i;
        }
    }

    BOOL selectionChanged = (selectedIndex < 0);
    if (selectionChanged) {
        selectedIndex = 0;
    }
    _segmentedControl.selectedSegment = selectedIndex;
    _selectedCatalogKey = MacLCAddonCatalogKey(catalogs[(NSUInteger)selectedIndex]);
    if (selectionChanged) {
        [self catalogSelectionDidChange];
    } else {
        [self loadSelectedCatalogIfNeeded];
    }
}

- (void)catalogSegmentChanged:(id)sender
{
    const NSInteger index = _segmentedControl.selectedSegment;
    if (index < 0 || index >= (NSInteger)_catalogs.count) {
        return;
    }
    _selectedCatalogKey = MacLCAddonCatalogKey(_catalogs[(NSUInteger)index]);
    [self catalogSelectionDidChange];
}

- (void)catalogSelectionDidChange
{
    [_catalogRequest cancel];
    _catalogRequest = nil;
    _loadingCatalog = NO;
    _catalogError = nil;
    [self loadSelectedCatalogIfNeeded];
    [self renderDiscoverBody];
}

- (void)loadSelectedCatalogIfNeeded
{
    MacLCAddonCatalog *catalog = [self selectedCatalog];
    if (!catalog || !_inWindow) {
        return;
    }
    NSString *key = MacLCAddonCatalogKey(catalog);
    if (_catalogCache[key] || _catalogRequest || _catalogError) {
        return;
    }

    _loadingCatalog = YES;
    __block BOOL completed = NO;
    __weak typeof(self) weakSelf = self;
    MacLCAddonRequest *request = [MacLCAddonStore.sharedStore fetchAddonCatalog:catalog
                                                                     completion:^(NSArray<MacLCAddon *> * _Nullable addons, NSError * _Nullable error) {
        completed = YES;
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        strongSelf->_catalogRequest = nil;
        strongSelf->_loadingCatalog = NO;
        if (![strongSelf->_selectedCatalogKey isEqualToString:key]) {
            return;
        }
        if (error) {
            strongSelf->_catalogError = error;
        } else {
            strongSelf->_catalogError = nil;
            strongSelf->_catalogCache[key] = addons ?: @[];
        }
        [strongSelf renderDiscoverBody];
    }];
    if (!completed) {
        _catalogRequest = request;
    }
}

- (void)retryCatalog:(id)sender
{
    if (_selectedCatalogKey) {
        [_catalogCache removeObjectForKey:_selectedCatalogKey];
    }
    _catalogError = nil;
    [self loadSelectedCatalogIfNeeded];
    [self renderDiscoverBody];
}

- (NSView *)centeredView:(NSView *)content
{
    NSView *container = [[NSView alloc] initWithFrame:NSZeroRect];
    container.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:content];
    [NSLayoutConstraint activateConstraints:@[
        [content.centerXAnchor constraintEqualToAnchor:container.centerXAnchor],
        [content.topAnchor constraintEqualToAnchor:container.topAnchor constant:MacLCDesign.spacingXXXL],
        [content.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-MacLCDesign.spacingXXXL],
        [content.leadingAnchor constraintGreaterThanOrEqualToAnchor:container.leadingAnchor],
        [content.trailingAnchor constraintLessThanOrEqualToAnchor:container.trailingAnchor],
    ]];
    return container;
}

- (NSView *)makeLoadingView
{
    NSProgressIndicator *spinner = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
    spinner.translatesAutoresizingMaskIntoConstraints = NO;
    spinner.style = NSProgressIndicatorStyleSpinning;
    spinner.controlSize = NSControlSizeSmall;
    [spinner startAnimation:nil];

    NSTextField *label = MacLCAddonsLabel(_NS("Loading add-ons…"), MacLCDesign.callout, MacLCDesign.secondaryLabel, NO);
    NSStackView *stack = MacLCAddonsStack(NSUserInterfaceLayoutOrientationVertical, MacLCDesign.spacingS, NSLayoutAttributeCenterX);
    [stack addArrangedSubview:spinner];
    [stack addArrangedSubview:label];
    return [self centeredView:stack];
}

- (NSView *)makeErrorViewForError:(NSError *)error service:(NSString *)serviceName
{
    NSString *title = nil;
    NSString *message = nil;
    MacLCAddonsCatalogErrorWording(error, serviceName, &title, &message);

    NSTextField *titleLabel = MacLCAddonsLabel(title, MacLCDesign.title3, MacLCDesign.primaryLabel, YES);
    titleLabel.alignment = NSTextAlignmentCenter;
    titleLabel.preferredMaxLayoutWidth = 420.0;
    NSTextField *messageLabel = MacLCAddonsLabel(message, MacLCDesign.callout, MacLCDesign.secondaryLabel, YES);
    messageLabel.alignment = NSTextAlignmentCenter;
    messageLabel.preferredMaxLayoutWidth = 420.0;
    NSButton *retry = [NSButton buttonWithTitle:_NS("Try Again") target:self action:@selector(retryCatalog:)];
    retry.translatesAutoresizingMaskIntoConstraints = NO;
    retry.bezelStyle = NSBezelStyleRounded;

    NSStackView *stack = MacLCAddonsStack(NSUserInterfaceLayoutOrientationVertical, MacLCDesign.spacingS, NSLayoutAttributeCenterX);
    [stack addArrangedSubview:titleLabel];
    [stack addArrangedSubview:messageLabel];
    [stack addArrangedSubview:retry];
    [stack setCustomSpacing:MacLCDesign.spacingM afterView:messageLabel];
    return [self centeredView:stack];
}

- (NSTextField *)makeNoticeWithText:(NSString *)text
{
    return MacLCAddonsLabel(text, MacLCDesign.callout, MacLCDesign.secondaryLabel, YES);
}

- (void)renderDiscoverBody
{
    [_discoverCells removeAllObjects];
    MacLCAddonCatalog *catalog = [self selectedCatalog];
    if (!catalog) {
        MacLCAddonsSetViews(_discoverBody, @[]);
        return;
    }

    NSArray<NSView *> *views = @[];
    NSArray<MacLCAddon *> *all = _catalogCache[_selectedCatalogKey];
    if (_loadingCatalog) {
        views = @[[self makeLoadingView]];
    } else if (_catalogError) {
        views = @[[self makeErrorViewForError:_catalogError service:catalog.addon.name]];
    } else if (all) {
        NSArray<MacLCAddon *> *shown = [self filteredAddons:all];
        if (shown.count > 0) {
            views = [self gridRowsForAddons:shown];
        } else if (_searchString.length > 0) {
            views = @[[self makeNoticeWithText:[self noMatchWording]]];
        } else {
            views = @[[self makeNoticeWithText:_NS("This catalog has no add-ons.")]];
        }
    }
    MacLCAddonsSetViews(_discoverBody, views);
}

- (NSArray<NSView *> *)gridRowsForAddons:(NSArray<MacLCAddon *> *)addons
{
    _gridColumns = [self gridColumnsForWidth:NSWidth(_column.frame)];
    NSMutableArray<NSView *> *rows = [NSMutableArray array];
    __weak typeof(self) weakSelf = self;

    for (NSUInteger start = 0; start < addons.count; start += (NSUInteger)_gridColumns) {
        NSStackView *row = MacLCAddonsStack(NSUserInterfaceLayoutOrientationHorizontal, kGridGap, NSLayoutAttributeTop);
        row.distribution = NSStackViewDistributionFillEqually;
        MacLCAddonsSectionDiscoverCell *first = nil;
        for (NSUInteger column = 0; column < (NSUInteger)_gridColumns; column++) {
            const NSUInteger index = start + column;
            if (index >= addons.count) {
                /* An empty slot keeps the last row's cards as wide as the others. */
                NSView *spacer = [[NSView alloc] initWithFrame:NSZeroRect];
                spacer.translatesAutoresizingMaskIntoConstraints = NO;
                [row addArrangedSubview:spacer];
                continue;
            }
            MacLCAddonsSectionDiscoverCell *cell =
                [[MacLCAddonsSectionDiscoverCell alloc] initWithAddon:addons[index] logoLoader:_logoLoader];
            cell.onInstall = ^(MacLCAddon *addon) {
                [weakSelf installCatalogAddon:addon];
            };
            [self applyPhaseToCell:cell];
            [row addArrangedSubview:cell];
            [_discoverCells addObject:cell];
            if (first) {
                [cell.surface.heightAnchor constraintEqualToAnchor:first.surface.heightAnchor].active = YES;
            } else {
                first = cell;
            }
        }
        [rows addObject:row];
    }
    return rows;
}

- (void)applyPhaseToCell:(MacLCAddonsSectionDiscoverCell *)cell
{
    NSString *key = cell.addon.transportURL;
    const MacLCAddonsInstallPhase phase = (MacLCAddonsInstallPhase)_installPhases[key].integerValue;
    if (phase == MacLCAddonsInstallPhaseInstalling) {
        [cell applyPhase:MacLCAddonsInstallPhaseInstalling message:nil];
    } else if ([MacLCAddonStore.sharedStore isInstalled:cell.addon.identifier]) {
        [cell applyPhase:MacLCAddonsInstallPhaseInstalled message:nil];
    } else if (phase == MacLCAddonsInstallPhaseFailed) {
        [cell applyPhase:MacLCAddonsInstallPhaseFailed message:_installMessages[key]];
    } else {
        [cell applyPhase:MacLCAddonsInstallPhaseIdle message:nil];
    }
}

- (void)refreshDiscoverPhases
{
    for (MacLCAddonsSectionDiscoverCell *cell in _discoverCells) {
        [self applyPhaseToCell:cell];
    }
}

- (void)installCatalogAddon:(MacLCAddon *)addon
{
    NSString *key = addon.transportURL;
    if (_installRequests[key]) {
        return;
    }
    _installPhases[key] = @(MacLCAddonsInstallPhaseInstalling);
    [_installMessages removeObjectForKey:key];
    [self refreshDiscoverPhases];

    __block BOOL completed = NO;
    __weak typeof(self) weakSelf = self;
    /* The manifest is fetched again: the catalog's copy may be old and its
     * errors would not be real ones. */
    MacLCAddonRequest *request = [MacLCAddonStore.sharedStore installFromAddress:addon.transportURL
                                                                      completion:^(MacLCAddon * _Nullable __unused installed, BOOL __unused replaced, NSError * _Nullable error) {
        completed = YES;
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        [strongSelf->_installRequests removeObjectForKey:key];
        if (error) {
            strongSelf->_installPhases[key] = @(MacLCAddonsInstallPhaseFailed);
            strongSelf->_installMessages[key] = MacLCAddonsInstallErrorWording(error);
        } else {
            [strongSelf->_installPhases removeObjectForKey:key];
            [strongSelf->_installMessages removeObjectForKey:key];
        }
        [strongSelf refreshDiscoverPhases];
    }];
    if (!completed) {
        _installRequests[key] = request;
    }
}

#pragma mark Logos

- (void)loadLogoForURL:(NSURL *)url completion:(void (^)(NSImage * _Nullable image))completion
{
    NSString *key = url.absoluteString;
    NSImage *cached = key ? [_logoCache objectForKey:key] : nil;
    if (cached) {
        completion(cached);
        return;
    }
    if (!key || [_logoFailures containsObject:key]) {
        completion(nil);
        return;
    }
    NSMutableArray *waiters = _logoWaiters[key];
    if (waiters) {
        [waiters addObject:[completion copy]];
        return;
    }
    _logoWaiters[key] = [NSMutableArray arrayWithObject:[completion copy]];

    __weak typeof(self) weakSelf = self;
    NSURLSessionDataTask *task = [NSURLSession.sharedSession dataTaskWithURL:url
                                                           completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable __unused response, NSError * _Nullable __unused error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }
            NSImage *image = data.length > 0 ? [[NSImage alloc] initWithData:data] : nil;
            NSArray *callbacks = [strongSelf->_logoWaiters[key] copy];
            [strongSelf->_logoWaiters removeObjectForKey:key];
            [strongSelf->_logoTasks removeObjectForKey:key];
            if (image) {
                [strongSelf->_logoCache setObject:image forKey:key];
            } else {
                [strongSelf->_logoFailures addObject:key];
            }
            for (void (^callback)(NSImage * _Nullable) in callbacks) {
                callback(image);
            }
        });
    }];
    _logoTasks[key] = task;
    [task resume];
}

#pragma mark Address sheet

- (void)buildAddressSheet
{
    _sheet = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 440, 200)
                                         styleMask:NSWindowStyleMaskTitled
                                           backing:NSBackingStoreBuffered
                                             defer:NO];
    _sheet.title = _NS("Add an Add-on");
    NSView *content = _sheet.contentView;

    NSStackView *stack = MacLCAddonsStack(NSUserInterfaceLayoutOrientationVertical, MacLCDesign.spacingM, NSLayoutAttributeLeading);
    [content addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:MacLCDesign.windowContentMargin],
        [stack.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-MacLCDesign.windowContentMargin],
        [stack.topAnchor constraintEqualToAnchor:content.topAnchor constant:MacLCDesign.windowContentMargin],
        [stack.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-MacLCDesign.windowContentMargin],
        [stack.widthAnchor constraintEqualToConstant:400.0],
    ]];

    NSTextField *title = MacLCAddonsLabel(_NS("Add an Add-on"), MacLCDesign.headline, MacLCDesign.primaryLabel, NO);
    MacLCAddonsAddFullWidth(stack, title);

    NSTextField *message = MacLCAddonsLabel(_NS("Paste the address of the add-on. It usually ends with manifest.json."),
                                            MacLCDesign.subheadline, MacLCDesign.secondaryLabel, YES);
    message.preferredMaxLayoutWidth = 400.0;
    MacLCAddonsAddFullWidth(stack, message);

    _sheetField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    _sheetField.translatesAutoresizingMaskIntoConstraints = NO;
    _sheetField.placeholderString = @"https://example.com/manifest.json";
    _sheetField.delegate = self;
    _sheetField.target = self;
    _sheetField.action = @selector(sheetFieldSubmitted:);
    MacLCAddonsAddFullWidth(stack, _sheetField);

    _sheetSpinner = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
    _sheetSpinner.translatesAutoresizingMaskIntoConstraints = NO;
    _sheetSpinner.style = NSProgressIndicatorStyleSpinning;
    _sheetSpinner.controlSize = NSControlSizeSmall;
    _sheetSpinner.displayedWhenStopped = NO;
    NSTextField *progress = MacLCAddonsLabel(_NS("Installing…"), MacLCDesign.subheadline, MacLCDesign.secondaryLabel, NO);
    _sheetProgressRow = MacLCAddonsStack(NSUserInterfaceLayoutOrientationHorizontal, MacLCDesign.spacingXS, NSLayoutAttributeCenterY);
    [_sheetProgressRow addArrangedSubview:_sheetSpinner];
    [_sheetProgressRow addArrangedSubview:progress];
    _sheetProgressRow.hidden = YES;
    [stack addArrangedSubview:_sheetProgressRow];

    _sheetErrorLabel = MacLCAddonsLabel(@"", MacLCDesign.footnote, MacLCDesign.destructive, YES);
    _sheetErrorLabel.preferredMaxLayoutWidth = 400.0;
    _sheetErrorLabel.hidden = YES;
    MacLCAddonsAddFullWidth(stack, _sheetErrorLabel);

    NSButton *cancel = [NSButton buttonWithTitle:_NS("Cancel") target:self action:@selector(cancelSheet:)];
    cancel.bezelStyle = NSBezelStyleRounded;
    cancel.keyEquivalent = @"\e";
    _sheetInstallButton = [NSButton buttonWithTitle:_NS("Install") target:self action:@selector(confirmSheet:)];
    _sheetInstallButton.bezelStyle = NSBezelStyleRounded;
    _sheetInstallButton.keyEquivalent = @"\r";
    _sheetInstallButton.enabled = NO;

    NSStackView *buttons = MacLCAddonsStack(NSUserInterfaceLayoutOrientationHorizontal, MacLCDesign.spacingM, NSLayoutAttributeCenterY);
    [buttons addView:cancel inGravity:NSStackViewGravityTrailing];
    [buttons addView:_sheetInstallButton inGravity:NSStackViewGravityTrailing];
    MacLCAddonsAddFullWidth(stack, buttons);

    _sheetField.nextKeyView = _sheetInstallButton;
    _sheetInstallButton.nextKeyView = cancel;
    cancel.nextKeyView = _sheetField;

    [content layoutSubtreeIfNeeded];
    [_sheet setContentSize:content.fittingSize];
}

/* An http(s) or stremio:// address the person may have just copied. */
- (nullable NSString *)addressOnPasteboard
{
    NSString *string = MacLCAddonsTrimmed([NSPasteboard.generalPasteboard stringForType:NSPasteboardTypeString] ?: @"");
    if (string.length == 0 || [string rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].location != NSNotFound) {
        return nil;
    }
    for (NSString *prefix in @[@"http://", @"https://", @"stremio://"]) {
        if ([string rangeOfString:prefix options:NSAnchoredSearch | NSCaseInsensitiveSearch].location != NSNotFound) {
            return string;
        }
    }
    return nil;
}

- (void)showAddressSheet:(id)sender
{
    NSWindow *parent = self.view.window;
    if (!parent) {
        return;
    }
    if (!_sheet) {
        [self buildAddressSheet];
    }
    NSString *prefill = [self addressOnPasteboard];
    _sheetField.stringValue = prefill ?: @"";
    _sheetField.enabled = YES;
    _sheetInstallButton.enabled = (prefill.length > 0);
    _sheetInstalling = NO;
    [_sheetSpinner stopAnimation:nil];
    _sheetProgressRow.hidden = YES;
    _sheetErrorLabel.hidden = YES;

    [parent beginSheet:_sheet completionHandler:nil];
    [_sheet makeFirstResponder:_sheetField];
}

- (void)endAddressSheet
{
    NSWindow *parent = _sheet.sheetParent ?: self.view.window;
    [parent endSheet:_sheet];
    [_sheet orderOut:nil];
}

- (void)cancelSheet:(id)sender
{
    [_sheetRequest cancel];
    _sheetRequest = nil;
    _sheetInstalling = NO;
    [self endAddressSheet];
}

- (void)sheetFieldSubmitted:(id)sender
{
    if (_sheetInstallButton.isEnabled && !_sheetInstalling) {
        [self confirmSheet:sender];
    }
}

- (void)confirmSheet:(id)sender
{
    NSString *address = MacLCAddonsTrimmed(_sheetField.stringValue);
    if (address.length == 0 || _sheetInstalling) {
        return;
    }
    _sheetInstalling = YES;
    _sheetInstallButton.enabled = NO;
    _sheetField.enabled = NO;
    _sheetErrorLabel.hidden = YES;
    _sheetProgressRow.hidden = NO;
    [_sheetSpinner startAnimation:nil];

    __block BOOL completed = NO;
    __weak typeof(self) weakSelf = self;
    MacLCAddonRequest *request = [MacLCAddonStore.sharedStore installFromAddress:address
                                                                      completion:^(MacLCAddon * _Nullable addon, BOOL __unused replaced, NSError * _Nullable error) {
        completed = YES;
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        strongSelf->_sheetRequest = nil;
        strongSelf->_sheetInstalling = NO;
        strongSelf->_sheetField.enabled = YES;
        [strongSelf->_sheetSpinner stopAnimation:nil];
        strongSelf->_sheetProgressRow.hidden = YES;

        if (error || !addon) {
            strongSelf->_sheetErrorLabel.stringValue = error ? MacLCAddonsInstallErrorWording(error)
                                                             : _NS("This address doesn't lead to an add-on.");
            strongSelf->_sheetErrorLabel.hidden = NO;
            strongSelf->_sheetInstallButton.enabled = YES;
            return;
        }
        [strongSelf endAddressSheet];
        /* Once the sheet is gone, so the scroll and the flash are seen. */
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf revealAddon:addon];
        });
    }];
    if (!completed) {
        _sheetRequest = request;
    }
}

#pragma mark NSTextFieldDelegate

- (void)controlTextDidChange:(NSNotification *)notification
{
    if (notification.object != _sheetField) {
        return;
    }
    _sheetInstallButton.enabled = !_sheetInstalling && MacLCAddonsTrimmed(_sheetField.stringValue).length > 0;
    _sheetErrorLabel.hidden = YES;
}

@end

#pragma mark - Section

@implementation MacLCAddonsSectionViewController
{
    NSString *_searchString;
}

- (instancetype)init
{
    self = [super initWithSegmentType:VLCLibraryWatchAddonsSegmentType];
    if (self) {
        _searchString = @"";
        [NSNotificationCenter.defaultCenter addObserver:self
                                               selector:@selector(addonsDidChange:)
                                                   name:MacLCAddonsDidChangeNotification
                                                 object:nil];
    }
    return self;
}

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)addonsDidChange:(NSNotification *)notification
{
    /* The subtitle counts the installed add-ons. */
    [self chromeDidChange];
}

- (NSString *)sectionTitle
{
    return _NS("Add-ons");
}

- (NSString *)makeSearchPlaceholder
{
    return _NS("Search Add-ons");
}

- (BOOL)sectionSupportsViewModes
{
    return NO;
}

- (nullable NSMenu *)makeSortMenu
{
    return nil;
}

- (BOOL)canGoBack
{
    return NO;
}

- (nullable NSString *)currentSubtitle
{
    const NSUInteger count = MacLCAddonStore.sharedStore.installedAddons.count;
    if (count == 1) {
        return _NS("1 add-on installed");
    }
    return [NSString stringWithFormat:_NS("%ld add-ons installed"), (long)count];
}

- (NSViewController *)makeRootViewControllerForViewMode:(MacLCLibraryViewMode)viewMode
{
    MacLCAddonsSectionRootViewController *root = [[MacLCAddonsSectionRootViewController alloc] initWithNibName:nil bundle:nil];
    [root applySearchString:_searchString];
    return root;
}

- (void)searchStringDidChange:(NSString *)searchString
{
    _searchString = searchString ?: @"";
    NSViewController *root = self.rootViewController;
    if ([root isKindOfClass:[MacLCAddonsSectionRootViewController class]]) {
        [(MacLCAddonsSectionRootViewController *)root applySearchString:_searchString];
    }
}

@end
