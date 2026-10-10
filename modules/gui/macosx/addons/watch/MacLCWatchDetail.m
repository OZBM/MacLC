/*****************************************************************************
 * MacLCWatchDetail.m: the title page (Apple TV-style) and stream picker
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

#import "addons/watch/MacLCWatchSections.h"
#import "addons/watch/MacLCWatchComponents.h"
#import "addons/watch/MacLCWatchLibrary.h"
#import "addons/watch/MacLCWatchPlayback.h"
#import "addons/watch/MacLCWatchLibraryViews.h"
#import "addons/watch/MacLCStreamPicker.h"
#import "addons/MacLCAddons.h"
#import "theme/MacLCDesign.h"
#import "theme/MacLCFormatBadgeView.h"
#import "main/VLCMain.h"
#import "settings/MacLCSettingsWindowController.h"
#import "playqueue/VLCPlayQueueController.h"
#import "windows/VLCOpenInputMetadata.h"
#import "extensions/NSString+Helpers.h"

#import <QuartzCore/QuartzCore.h>

static const CGFloat kMacLCDetailMinHeaderHeight = 420.0;
static const CGFloat kMacLCDetailMaxHeaderHeight = 720.0;
static const CGFloat kMacLCDetailDefaultEpisodeWidth = 300.0;

#pragma mark - Runtime Formatter

static NSString *MacLCFormatRuntime(NSString * _Nullable raw)
{
    if (!raw || raw.length == 0) {
        return raw ?: @"";
    }
    NSString *trimmed = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) {
        return raw;
    }

    static NSRegularExpression *hmRegex;
    static NSRegularExpression *hOnlyRegex;
    static NSRegularExpression *mOnlyRegex;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        hmRegex = [NSRegularExpression regularExpressionWithPattern:@"^(\\d+)\\s*h(?:r|ours?)?\\s*(\\d+)\\s*(?:m|min|mins|minutes?)?$"
                                                            options:NSRegularExpressionCaseInsensitive
                                                              error:nil];
        hOnlyRegex = [NSRegularExpression regularExpressionWithPattern:@"^(\\d+)\\s*h(?:r|ours?)?$"
                                                                options:NSRegularExpressionCaseInsensitive
                                                                  error:nil];
        mOnlyRegex = [NSRegularExpression regularExpressionWithPattern:@"^(\\d+)\\s*(?:m|min|mins|minutes?)?$"
                                                                options:NSRegularExpressionCaseInsensitive
                                                                  error:nil];
    });

    NSTextCheckingResult *hmMatch = [hmRegex firstMatchInString:trimmed options:0 range:NSMakeRange(0, trimmed.length)];
    if (hmMatch && hmMatch.numberOfRanges >= 3) {
        NSInteger h = [[trimmed substringWithRange:[hmMatch rangeAtIndex:1]] integerValue];
        NSInteger m = [[trimmed substringWithRange:[hmMatch rangeAtIndex:2]] integerValue];
        if (h > 0 && m > 0) {
            return [NSString stringWithFormat:@"%ld h %ld min", (long)h, (long)m];
        } else if (h > 0 && m == 0) {
            return [NSString stringWithFormat:@"%ld h", (long)h];
        } else if (h == 0 && m > 0) {
            return [NSString stringWithFormat:@"%ld min", (long)m];
        }
    }

    NSTextCheckingResult *hMatch = [hOnlyRegex firstMatchInString:trimmed options:0 range:NSMakeRange(0, trimmed.length)];
    if (hMatch && hMatch.numberOfRanges >= 2) {
        NSInteger h = [[trimmed substringWithRange:[hMatch rangeAtIndex:1]] integerValue];
        if (h > 0) {
            return [NSString stringWithFormat:@"%ld h", (long)h];
        }
    }

    NSTextCheckingResult *mMatch = [mOnlyRegex firstMatchInString:trimmed options:0 range:NSMakeRange(0, trimmed.length)];
    if (mMatch && mMatch.numberOfRanges >= 2) {
        NSInteger totalMins = [[trimmed substringWithRange:[mMatch rangeAtIndex:1]] integerValue];
        if (totalMins > 0) {
            if (totalMins < 60) {
                return [NSString stringWithFormat:@"%ld min", (long)totalMins];
            } else {
                NSInteger h = totalMins / 60;
                NSInteger m = totalMins % 60;
                if (m > 0) {
                    return [NSString stringWithFormat:@"%ld h %ld min", (long)h, (long)m];
                } else {
                    return [NSString stringWithFormat:@"%ld h", (long)h];
                }
            }
        }
    }

    return raw;
}

#pragma mark - Flipped Document View

@interface MacLCWatchDetailDocumentView : NSView
@end

@implementation MacLCWatchDetailDocumentView

- (BOOL)isFlipped
{
    return YES;
}

@end

#pragma mark - Picture View

@interface MacLCWatchPictureView : NSView
@property (nonatomic, nullable, strong) NSImage *image;
@end

@implementation MacLCWatchPictureView

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

- (BOOL)wantsUpdateLayer
{
    return YES;
}

- (void)updateLayer
{
    self.layer.contents = self.image;
    self.layer.backgroundColor = (self.image == nil) ? NSColor.quaternarySystemFillColor.CGColor : NULL;
}

- (void)setImage:(nullable NSImage *)image
{
    _image = image;
    self.needsDisplay = YES;
}

@end

#pragma mark - Scrim Views

@interface MacLCWatchBottomScrimView : NSView
@end

@implementation MacLCWatchBottomScrimView

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
    }
    return self;
}

- (CALayer *)makeBackingLayer
{
    CAGradientLayer * const gradient = [CAGradientLayer layer];
    /* Bottom black 0 -> 70 % over the lower 60 % */
    gradient.colors = @[
        (__bridge id)[NSColor colorWithWhite:0.0 alpha:0.0].CGColor,
        (__bridge id)[NSColor colorWithWhite:0.0 alpha:0.7].CGColor
    ];
    gradient.startPoint = CGPointMake(0.5, 0.60);
    gradient.endPoint = CGPointMake(0.5, 0.0);
    return gradient;
}

- (nullable NSView *)hitTest:(NSPoint)point
{
    return nil;
}

@end

@interface MacLCWatchLeadingScrimView : NSView
@end

@implementation MacLCWatchLeadingScrimView

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
    }
    return self;
}

- (CALayer *)makeBackingLayer
{
    CAGradientLayer * const gradient = [CAGradientLayer layer];
    /* Leading black 0 -> 45 % over the leading 55 % */
    gradient.colors = @[
        (__bridge id)[NSColor colorWithWhite:0.0 alpha:0.45].CGColor,
        (__bridge id)[NSColor colorWithWhite:0.0 alpha:0.0].CGColor
    ];
    gradient.startPoint = CGPointMake(0.0, 0.5);
    gradient.endPoint = CGPointMake(0.55, 0.5);
    return gradient;
}

- (nullable NSView *)hitTest:(NSPoint)point
{
    return nil;
}

@end

@interface MacLCWatchTopScrimView : NSView
@end

@implementation MacLCWatchTopScrimView

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
    }
    return self;
}

- (CALayer *)makeBackingLayer
{
    return [CAGradientLayer layer];
}

- (BOOL)wantsUpdateLayer
{
    return YES;
}

- (void)updateLayer
{
    __block CGColorRef top = NULL;
    [self.effectiveAppearance performAsCurrentDrawingAppearance:^{
        top = CGColorRetain([NSColor.windowBackgroundColor colorWithAlphaComponent:0.55].CGColor);
    }];
    CAGradientLayer * const gradient = (CAGradientLayer *)self.layer;
    gradient.colors = @[(__bridge id)top, (__bridge_transfer id)CGColorCreateCopyWithAlpha(top, 0.0)];
    gradient.startPoint = CGPointMake(0.5, 1.0);
    gradient.endPoint = CGPointMake(0.5, 0.0);
    CGColorRelease(top);
}

- (nullable NSView *)hitTest:(NSPoint)point
{
    return nil;
}

@end

#pragma mark - Watched Pill View

@interface MacLCWatchedPillView : NSView
@end

@implementation MacLCWatchedPillView
{
    NSImageView *_iconView;
    NSTextField *_label;
}

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;

        _iconView = [[NSImageView alloc] initWithFrame:NSZeroRect];
        _iconView.translatesAutoresizingMaskIntoConstraints = NO;
        _iconView.imageScaling = NSImageScaleProportionallyUpOrDown;
        _iconView.image = [MacLCDesign symbolNamed:@"checkmark.circle.fill" accessibilityLabel:nil];
        _iconView.contentTintColor = NSColor.whiteColor;
        [self addSubview:_iconView];

        _label = [NSTextField labelWithString:_NS("Watched")];
        _label.translatesAutoresizingMaskIntoConstraints = NO;
        _label.font = MacLCDesign.callout;
        _label.textColor = NSColor.whiteColor;
        [self addSubview:_label];

        [NSLayoutConstraint activateConstraints:@[
            [_iconView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:8.0],
            [_iconView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_iconView.widthAnchor constraintEqualToConstant:14.0],
            [_iconView.heightAnchor constraintEqualToConstant:14.0],

            [_label.leadingAnchor constraintEqualToAnchor:_iconView.trailingAnchor constant:4.0],
            [_label.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-8.0],
            [_label.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],

            [self.heightAnchor constraintEqualToConstant:24.0],
        ]];
    }
    return self;
}

- (BOOL)wantsUpdateLayer
{
    return YES;
}

- (void)updateLayer
{
    self.layer.backgroundColor = [NSColor colorWithWhite:0.0 alpha:0.35].CGColor;
    self.layer.cornerRadius = 12.0;
    self.layer.masksToBounds = YES;
}

- (BOOL)isAccessibilityElement
{
    return YES;
}

- (NSAccessibilityRole)accessibilityRole
{
    return NSAccessibilityStaticTextRole;
}

- (NSString *)accessibilityLabel
{
    return _NS("Watched");
}

@end

#pragma mark - Episodes Collection View

@interface MacLCWatchEpisodesCollectionView : NSCollectionView
@property (nonatomic, copy, nullable) NSMenu * _Nullable (^contextMenuProvider)(NSIndexPath *indexPath);
@end

@implementation MacLCWatchEpisodesCollectionView

- (NSMenu *)menuForEvent:(NSEvent *)event
{
    if (event.type == NSEventTypeRightMouseDown ||
        (event.type == NSEventTypeLeftMouseDown && (event.modifierFlags & NSEventModifierFlagControl))) {
        NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
        NSIndexPath *indexPath = [self indexPathForItemAtPoint:point];
        if (indexPath != nil && self.contextMenuProvider != nil) {
            NSMenu *menu = self.contextMenuProvider(indexPath);
            if (menu != nil) {
                return menu;
            }
        }
    }
    return [super menuForEvent:event];
}

@end

#pragma mark - Detail View Controller Implementation

@interface MacLCWatchDetailViewController () <NSCollectionViewDataSource, NSCollectionViewDelegate>
{
    BOOL _initialShowStreams;
    BOOL _appeared;
    BOOL _metaLoaded;

    MacLCAddonRequest *_metaRequest;
    MacLCWatchImageRequest *_pictureRequest;
    MacLCWatchImageRequest *_logoRequest;

    MacLCStreamPickerController *_streamPickerController;
    NSPopover *_descriptionPopover;

    NSScrollView *_scrollView;
    MacLCWatchDetailDocumentView *_documentView;

    // Header components
    NSView *_headerView;
    NSLayoutConstraint *_headerHeightConstraint;
    MacLCWatchPictureView *_pictureView;
    NSView *_extensionView;
    MacLCWatchBottomScrimView *_bottomScrim;
    MacLCWatchLeadingScrimView *_leadingScrim;
    MacLCWatchTopScrimView *_topScrim;

    NSStackView *_headerLeadingStack;
    NSImageView *_logoImageView;
    NSTextField *_titleLabel;
    NSStackView *_factsStack;
    NSStackView *_factsRowStack;
    NSTextField *_factsLabel;
    MacLCWatchedPillView *_watchedPill;
    NSTextField *_factsSubtitleLabel;
    NSStackView *_descStack;
    NSTextField *_descLabel;
    NSButton *_moreButton;
    NSTextField *_detailsLabel;
    MacLCWatchProgressBar *_progressBar;
    NSStackView *_buttonsStack;
    NSButton *_playButton;
    NSButton *_startOverButton;
    NSButton *_trailerButton;
    NSButton *_favoriteButton;
    NSButton *_actionsButton;

    NSStackView *_creditsStack;
    NSTextField *_starringLabel;
    NSLayoutConstraint *_documentWidthConstraint;
    NSTextField *_directorLabel;

    // Episodes components (for shows)
    NSView *_episodesContainerView;
    NSView *_seasonShelfView;
    NSPopUpButton *_seasonPopUp;
    NSScrollView *_episodesScrollView;
    NSLayoutConstraint *_episodesScrollViewHeightConstraint;
    NSCollectionView *_episodesCollectionView;
    NSView *_episodesErrorView;
    NSTextField *_episodesErrorLabel;
    NSButton *_episodesTryAgainButton;
    NSArray<MacLCAddonVideo *> *_episodesForCurrentSeason;

    // About components
    NSView *_aboutContainerView;
    NSTextField *_aboutTitleLabel;
    NSTextField *_aboutDescLabel;
    NSTextField *_aboutGenresKeyLabel;
    NSTextField *_aboutGenresValueLabel;
    NSTextField *_aboutReleasedKeyLabel;
    NSTextField *_aboutReleasedValueLabel;
    NSTextField *_aboutRuntimeKeyLabel;
    NSTextField *_aboutRuntimeValueLabel;
    NSTextField *_aboutRatingKeyLabel;
    NSTextField *_aboutRatingValueLabel;
}

@property (nonatomic, nullable, strong) MacLCAddonMeta *meta;

@end

@implementation MacLCWatchDetailViewController

- (instancetype)initWithItem:(MacLCAddonItem *)item showStreams:(BOOL)showStreams
{
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _item = item;
        _initialShowStreams = showStreams;
        _episodesForCurrentSeason = @[];
    }
    return self;
}

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self name:NSPreferredScrollerStyleDidChangeNotification object:nil];
    [NSNotificationCenter.defaultCenter removeObserver:self name:MacLCWatchLibraryDidChangeNotification object:nil];
    [_metaRequest cancel];
    [_pictureRequest cancel];
    [_logoRequest cancel];
    if (_descriptionPopover) {
        [_descriptionPopover performClose:nil];
    }
}

- (BOOL)isSeries
{
    if ([_item.type isEqualToString:@"series"] || [_item.type isEqualToString:@"tv"]) {
        return YES;
    }
    if (_meta && _meta.videos.count > 0) {
        return YES;
    }
    return NO;
}

- (void)loadView
{
    NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 960.0, 720.0)];
    root.wantsLayer = YES;

    _scrollView = [[NSScrollView alloc] initWithFrame:root.bounds];
    _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _scrollView.drawsBackground = NO;
    _scrollView.hasVerticalScroller = YES;
    _scrollView.autohidesScrollers = YES;
    _scrollView.hasHorizontalScroller = NO;
    /* The picture goes under the toolbar (as on the Apple TV app);
     * -viewDidLayout keeps the other safe-area insets. */
    _scrollView.automaticallyAdjustsContentInsets = NO;
    [root addSubview:_scrollView];

    _documentView = [[MacLCWatchDetailDocumentView alloc] initWithFrame:NSMakeRect(0, 0, 960.0, 1200.0)];
    _documentView.translatesAutoresizingMaskIntoConstraints = NO;
    _scrollView.documentView = _documentView;

    /* The clip view is as wide as the window; the content is narrower by the
     * side insets (the sidebar's safe area), see -viewDidLayout. */
    _documentWidthConstraint = [_documentView.widthAnchor constraintEqualToAnchor:_scrollView.contentView.widthAnchor];
    [NSLayoutConstraint activateConstraints:@[
        [_scrollView.topAnchor constraintEqualToAnchor:root.topAnchor],
        [_scrollView.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],
        [_scrollView.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [_scrollView.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],

        [_documentView.topAnchor constraintEqualToAnchor:_scrollView.contentView.topAnchor],
        [_documentView.leadingAnchor constraintEqualToAnchor:_scrollView.contentView.leadingAnchor],
        [_documentView.trailingAnchor constraintEqualToAnchor:_scrollView.contentView.trailingAnchor],
        _documentWidthConstraint,
    ]];

    /* Set first: the header pins to self.view's safe area, and reading
     * self.view before it is set would call -loadView again, forever. */
    self.view = root;

    [self setUpHeaderView];
    if ([self isSeries]) {
        [self setUpEpisodesView];
    }
    [self setUpAboutView];
    [self installMainConstraints];
}

- (void)setUpHeaderView
{
    _headerView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 960.0, 540.0)];
    _headerView.translatesAutoresizingMaskIntoConstraints = NO;
    _headerView.wantsLayer = YES;
    [_documentView addSubview:_headerView];

    _pictureView = [[MacLCWatchPictureView alloc] initWithFrame:_headerView.bounds];

    if (@available(macOS 26.0, *)) {
        NSBackgroundExtensionView * const extView = [[NSBackgroundExtensionView alloc] initWithFrame:_headerView.bounds];
        extView.automaticallyPlacesContentView = NO;
        _pictureView.translatesAutoresizingMaskIntoConstraints = NO;
        extView.contentView = _pictureView;
        _extensionView = extView;
        _extensionView.translatesAutoresizingMaskIntoConstraints = NO;
        [_headerView addSubview:_extensionView];

        [NSLayoutConstraint activateConstraints:@[
            [_extensionView.topAnchor constraintEqualToAnchor:_headerView.topAnchor],
            [_extensionView.bottomAnchor constraintEqualToAnchor:_headerView.bottomAnchor],
            [_extensionView.leadingAnchor constraintEqualToAnchor:_headerView.leadingAnchor],
            [_extensionView.trailingAnchor constraintEqualToAnchor:_headerView.trailingAnchor],
            [_pictureView.topAnchor constraintEqualToAnchor:_extensionView.topAnchor],
            [_pictureView.bottomAnchor constraintEqualToAnchor:_extensionView.bottomAnchor],
            [_pictureView.leadingAnchor constraintEqualToAnchor:_extensionView.leadingAnchor],
            [_pictureView.trailingAnchor constraintEqualToAnchor:_extensionView.trailingAnchor],
        ]];
    } else {
        _pictureView.translatesAutoresizingMaskIntoConstraints = NO;
        [_headerView addSubview:_pictureView];

        [NSLayoutConstraint activateConstraints:@[
            [_pictureView.topAnchor constraintEqualToAnchor:_headerView.topAnchor],
            [_pictureView.bottomAnchor constraintEqualToAnchor:_headerView.bottomAnchor],
            [_pictureView.leadingAnchor constraintEqualToAnchor:_headerView.leadingAnchor],
            [_pictureView.trailingAnchor constraintEqualToAnchor:_headerView.trailingAnchor],
        ]];
    }

    _bottomScrim = [[MacLCWatchBottomScrimView alloc] initWithFrame:_headerView.bounds];
    _bottomScrim.translatesAutoresizingMaskIntoConstraints = NO;
    [_headerView addSubview:_bottomScrim];

    _leadingScrim = [[MacLCWatchLeadingScrimView alloc] initWithFrame:_headerView.bounds];
    _leadingScrim.translatesAutoresizingMaskIntoConstraints = NO;
    [_headerView addSubview:_leadingScrim];

    _topScrim = [[MacLCWatchTopScrimView alloc] initWithFrame:_headerView.bounds];
    _topScrim.translatesAutoresizingMaskIntoConstraints = NO;

    [_headerView addSubview:_topScrim];

    [NSLayoutConstraint activateConstraints:@[
        [_bottomScrim.topAnchor constraintEqualToAnchor:_headerView.topAnchor],
        [_bottomScrim.bottomAnchor constraintEqualToAnchor:_headerView.bottomAnchor],
        [_bottomScrim.leadingAnchor constraintEqualToAnchor:_headerView.leadingAnchor],
        [_bottomScrim.trailingAnchor constraintEqualToAnchor:_headerView.trailingAnchor],

        [_leadingScrim.topAnchor constraintEqualToAnchor:_headerView.topAnchor],
        [_leadingScrim.bottomAnchor constraintEqualToAnchor:_headerView.bottomAnchor],
        [_leadingScrim.leadingAnchor constraintEqualToAnchor:_headerView.leadingAnchor],
        [_leadingScrim.trailingAnchor constraintEqualToAnchor:_headerView.trailingAnchor],

        [_topScrim.topAnchor constraintEqualToAnchor:_headerView.topAnchor],
        [_topScrim.leadingAnchor constraintEqualToAnchor:_headerView.leadingAnchor],
        [_topScrim.trailingAnchor constraintEqualToAnchor:_headerView.trailingAnchor],
        [_topScrim.heightAnchor constraintEqualToConstant:88.0],
    ]];

    // Header leading content
    _logoImageView = [[NSImageView alloc] initWithFrame:NSZeroRect];
    _logoImageView.translatesAutoresizingMaskIntoConstraints = NO;
    _logoImageView.imageScaling = NSImageScaleProportionallyUpOrDown;
    _logoImageView.imageAlignment = NSImageAlignCenter;
    _logoImageView.hidden = YES;

    _titleLabel = [NSTextField wrappingLabelWithString:_item.name ?: @""];
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _titleLabel.font = [NSFont systemFontOfSize:MacLCDesign.largeTitle.pointSize weight:NSFontWeightBold];
    _titleLabel.textColor = NSColor.whiteColor;
    _titleLabel.maximumNumberOfLines = 2;
    /* Truncating line break modes turn wrapping off: wrap, and cut the last line. */
    _titleLabel.lineBreakMode = NSLineBreakByWordWrapping;
    _titleLabel.cell.truncatesLastVisibleLine = YES;
    _titleLabel.selectable = NO;

    _factsLabel = [NSTextField labelWithString:@""];
    _factsLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _factsLabel.font = MacLCDesign.callout;
    _factsLabel.textColor = [NSColor colorWithWhite:1.0 alpha:0.85];

    _watchedPill = [[MacLCWatchedPillView alloc] initWithFrame:NSZeroRect];
    _watchedPill.translatesAutoresizingMaskIntoConstraints = NO;
    _watchedPill.hidden = YES;
    [_watchedPill setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    [_watchedPill setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];

    _factsRowStack = [NSStackView stackViewWithViews:@[_factsLabel, _watchedPill]];
    _factsRowStack.translatesAutoresizingMaskIntoConstraints = NO;
    _factsRowStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    _factsRowStack.alignment = NSLayoutAttributeCenterY;
    _factsRowStack.spacing = 8.0;

    _factsSubtitleLabel = [NSTextField labelWithString:@""];
    _factsSubtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _factsSubtitleLabel.font = MacLCDesign.callout;
    _factsSubtitleLabel.textColor = [NSColor colorWithWhite:1.0 alpha:0.85];
    _factsSubtitleLabel.hidden = YES;

    _factsStack = [NSStackView stackViewWithViews:@[_factsRowStack, _factsSubtitleLabel]];
    _factsStack.translatesAutoresizingMaskIntoConstraints = NO;
    _factsStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    _factsStack.alignment = NSLayoutAttributeLeading;
    _factsStack.spacing = 4.0;

    _descLabel = [NSTextField wrappingLabelWithString:_item.itemDescription ?: @""];
    _descLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _descLabel.font = MacLCDesign.body;
    _descLabel.textColor = [NSColor colorWithWhite:1.0 alpha:0.90];
    _descLabel.maximumNumberOfLines = 4;
    _descLabel.preferredMaxLayoutWidth = 560.0; /* wraps instead of sizing on one line */
    /* Truncating line break modes turn wrapping off: wrap, and cut the last line. */
    _descLabel.lineBreakMode = NSLineBreakByWordWrapping;
    _descLabel.cell.truncatesLastVisibleLine = YES;
    _descLabel.selectable = NO;

    _moreButton = [NSButton buttonWithTitle:_NS("More") target:self action:@selector(showMoreDescription:)];
    _moreButton.translatesAutoresizingMaskIntoConstraints = NO;
    _moreButton.bordered = NO;
    _moreButton.font = MacLCDesign.subheadline;
    _moreButton.contentTintColor = [NSColor colorWithWhite:1.0 alpha:0.75];
    _moreButton.accessibilityLabel = _NS("More description");
    _moreButton.toolTip = _NS("Show Full Description");
    _moreButton.hidden = YES;

    _descStack = [NSStackView stackViewWithViews:@[_descLabel, _moreButton]];
    _descStack.translatesAutoresizingMaskIntoConstraints = NO;
    _descStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    _descStack.alignment = NSLayoutAttributeLeading;
    _descStack.spacing = 2.0;

    _detailsLabel = [NSTextField labelWithString:@""];
    _detailsLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _detailsLabel.font = MacLCDesign.callout;
    _detailsLabel.textColor = [NSColor colorWithWhite:1.0 alpha:0.75];

    _progressBar = [[MacLCWatchProgressBar alloc] initWithFrame:NSMakeRect(0, 0, 200.0, 4.0)];
    _progressBar.translatesAutoresizingMaskIntoConstraints = NO;
    _progressBar.hidden = YES;

    _playButton = [NSButton buttonWithTitle:_NS("Play") target:self action:@selector(playButtonAction:)];
    _playButton.translatesAutoresizingMaskIntoConstraints = NO;
    _playButton.image = [MacLCDesign symbolNamed:@"play.fill" accessibilityLabel:nil];
    _playButton.imagePosition = NSImageLeading;
    _playButton.controlSize = NSControlSizeLarge;
    if (@available(macOS 26.0, *)) {
        _playButton.bezelStyle = NSBezelStyleGlass;
        _playButton.tintProminence = NSTintProminencePrimary;
        _playButton.bezelColor = MacLCDesign.accent;
    } else {
        _playButton.bezelStyle = NSBezelStylePush;
    }
    _playButton.accessibilityLabel = _playButton.title;
    _playButton.toolTip = _playButton.title;

    _startOverButton = [NSButton buttonWithTitle:_NS("Start Over") target:self action:@selector(startOverButtonAction:)];
    _startOverButton.translatesAutoresizingMaskIntoConstraints = NO;
    _startOverButton.image = [MacLCDesign symbolNamed:@"arrow.counterclockwise" accessibilityLabel:nil];
    _startOverButton.imagePosition = NSImageLeading;
    _startOverButton.controlSize = NSControlSizeLarge;
    if (@available(macOS 26.0, *)) {
        _startOverButton.bezelStyle = NSBezelStyleGlass;
    } else {
        _startOverButton.bezelStyle = NSBezelStylePush;
    }
    _startOverButton.accessibilityLabel = _NS("Start Over");
    _startOverButton.toolTip = _NS("Start Over");
    _startOverButton.hidden = YES;

    _trailerButton = [NSButton buttonWithTitle:_NS("Trailer") target:self action:@selector(trailerButtonAction:)];
    _trailerButton.translatesAutoresizingMaskIntoConstraints = NO;
    _trailerButton.image = [MacLCDesign symbolNamed:@"film" accessibilityLabel:nil];
    _trailerButton.imagePosition = NSImageLeading;
    _trailerButton.controlSize = NSControlSizeLarge;
    if (@available(macOS 26.0, *)) {
        _trailerButton.bezelStyle = NSBezelStyleGlass;
    } else {
        _trailerButton.bezelStyle = NSBezelStylePush;
    }
    _trailerButton.accessibilityLabel = _NS("Play Trailer");
    _trailerButton.toolTip = _NS("Play Trailer");
    _trailerButton.hidden = YES;

    _favoriteButton = [NSButton buttonWithTitle:@"" target:self action:@selector(favoriteButtonAction:)];
    _favoriteButton.translatesAutoresizingMaskIntoConstraints = NO;
    _favoriteButton.imagePosition = NSImageOnly;
    _favoriteButton.controlSize = NSControlSizeLarge;
    if (@available(macOS 26.0, *)) {
        _favoriteButton.bezelStyle = NSBezelStyleGlass;
    } else {
        _favoriteButton.bezelStyle = NSBezelStylePush;
    }
    _favoriteButton.image = [MacLCDesign symbolNamed:@"heart" accessibilityLabel:_NS("Add to Favorites")];
    _favoriteButton.accessibilityLabel = _NS("Add to Favorites");
    _favoriteButton.toolTip = _NS("Add to Favorites");
    [_favoriteButton.widthAnchor constraintEqualToAnchor:_favoriteButton.heightAnchor].active = YES;

    _actionsButton = [NSButton buttonWithTitle:@"" target:self action:@selector(actionsButtonAction:)];
    _actionsButton.translatesAutoresizingMaskIntoConstraints = NO;
    _actionsButton.imagePosition = NSImageOnly;
    _actionsButton.controlSize = NSControlSizeLarge;
    if (@available(macOS 26.0, *)) {
        _actionsButton.bezelStyle = NSBezelStyleGlass;
    } else {
        _actionsButton.bezelStyle = NSBezelStylePush;
    }
    _actionsButton.image = [MacLCDesign symbolNamed:@"ellipsis" accessibilityLabel:_NS("More Options")];
    _actionsButton.accessibilityLabel = _NS("More Options");
    _actionsButton.toolTip = _NS("More Options");
    [_actionsButton.widthAnchor constraintEqualToAnchor:_actionsButton.heightAnchor].active = YES;

    _buttonsStack = [NSStackView stackViewWithViews:@[_playButton, _startOverButton, _trailerButton, _favoriteButton, _actionsButton]];
    _buttonsStack.translatesAutoresizingMaskIntoConstraints = NO;
    _buttonsStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    _buttonsStack.spacing = 12.0;

    _headerLeadingStack = [NSStackView stackViewWithViews:@[_logoImageView, _titleLabel, _factsStack, _descStack, _detailsLabel, _progressBar, _buttonsStack]];
    _headerLeadingStack.translatesAutoresizingMaskIntoConstraints = NO;
    _headerLeadingStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    _headerLeadingStack.alignment = NSLayoutAttributeLeading;
    _headerLeadingStack.spacing = 6.0;
    [_headerLeadingStack setCustomSpacing:12.0 afterView:_factsStack];
    [_headerLeadingStack setCustomSpacing:12.0 afterView:_descStack];
    [_headerLeadingStack setCustomSpacing:16.0 afterView:_detailsLabel];
    [_headerLeadingStack setCustomSpacing:16.0 afterView:_progressBar];
    [_headerView addSubview:_headerLeadingStack];

    // Header trailing credits (Cast & Director)
    _starringLabel = [NSTextField wrappingLabelWithString:@""];
    _starringLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _starringLabel.font = MacLCDesign.subheadline;
    _starringLabel.maximumNumberOfLines = 3;
    /* Truncating line break modes turn wrapping off: wrap, and cut the last line. */
    _starringLabel.lineBreakMode = NSLineBreakByWordWrapping;
    _starringLabel.cell.truncatesLastVisibleLine = YES;
    _starringLabel.selectable = NO;
    _starringLabel.preferredMaxLayoutWidth = 320.0; /* wraps instead of sizing on one line */
    _starringLabel.hidden = YES;

    _directorLabel = [NSTextField wrappingLabelWithString:@""];
    _directorLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _directorLabel.font = MacLCDesign.subheadline;
    _directorLabel.maximumNumberOfLines = 3;
    /* Truncating line break modes turn wrapping off: wrap, and cut the last line. */
    _directorLabel.lineBreakMode = NSLineBreakByWordWrapping;
    _directorLabel.cell.truncatesLastVisibleLine = YES;
    _directorLabel.selectable = NO;
    _directorLabel.preferredMaxLayoutWidth = 320.0; /* wraps instead of sizing on one line */
    _directorLabel.hidden = YES;

    _creditsStack = [NSStackView stackViewWithViews:@[_starringLabel, _directorLabel]];
    _creditsStack.translatesAutoresizingMaskIntoConstraints = NO;
    _creditsStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    _creditsStack.alignment = NSLayoutAttributeLeading;
    _creditsStack.spacing = 8.0;
    _creditsStack.hidden = YES;
    [_headerView addSubview:_creditsStack];

    NSLayoutConstraint *descWidthEqual = [_descLabel.widthAnchor constraintEqualToConstant:560.0];
    descWidthEqual.priority = 700;

    NSLayoutConstraint *creditsTrailingHeader = [_creditsStack.trailingAnchor constraintEqualToAnchor:_headerView.trailingAnchor constant:-40.0];
    creditsTrailingHeader.priority = 900;

    NSLayoutConstraint *creditsTrailingSafe = [_creditsStack.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-40.0];
    creditsTrailingSafe.priority = 850;

    [NSLayoutConstraint activateConstraints:@[
        [_headerLeadingStack.leadingAnchor constraintEqualToAnchor:_headerView.leadingAnchor constant:40.0],
        [_headerLeadingStack.bottomAnchor constraintEqualToAnchor:_headerView.bottomAnchor constant:-40.0],
        [_headerLeadingStack.widthAnchor constraintLessThanOrEqualToConstant:560.0],
        [_logoImageView.widthAnchor constraintLessThanOrEqualToConstant:360.0],
        [_logoImageView.heightAnchor constraintLessThanOrEqualToConstant:120.0],
        [_titleLabel.widthAnchor constraintLessThanOrEqualToAnchor:_headerLeadingStack.widthAnchor],
        [_progressBar.widthAnchor constraintEqualToConstant:200.0],
        [_progressBar.heightAnchor constraintEqualToConstant:4.0],
        [_descLabel.widthAnchor constraintLessThanOrEqualToConstant:560.0],
        descWidthEqual,
        [_descLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_creditsStack.leadingAnchor constant:-24.0],
        [_descLabel.widthAnchor constraintLessThanOrEqualToAnchor:_headerLeadingStack.widthAnchor],

        [_creditsStack.trailingAnchor constraintLessThanOrEqualToAnchor:_headerView.trailingAnchor constant:-40.0],
        [_creditsStack.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-40.0],
        creditsTrailingHeader,
        creditsTrailingSafe,
        [_creditsStack.bottomAnchor constraintEqualToAnchor:_buttonsStack.bottomAnchor],
        [_creditsStack.widthAnchor constraintLessThanOrEqualToConstant:320.0],
        [_starringLabel.widthAnchor constraintLessThanOrEqualToAnchor:_creditsStack.widthAnchor],
        [_directorLabel.widthAnchor constraintLessThanOrEqualToAnchor:_creditsStack.widthAnchor],
        [_headerLeadingStack.trailingAnchor constraintLessThanOrEqualToAnchor:_creditsStack.leadingAnchor constant:-24.0],
    ]];
}

- (void)setUpEpisodesView
{
    _episodesContainerView = [[NSView alloc] initWithFrame:NSZeroRect];
    _episodesContainerView.translatesAutoresizingMaskIntoConstraints = NO;
    [_documentView addSubview:_episodesContainerView];

    _seasonShelfView = [[NSView alloc] initWithFrame:NSZeroRect];
    _seasonShelfView.translatesAutoresizingMaskIntoConstraints = NO;
    [_episodesContainerView addSubview:_seasonShelfView];

    _seasonPopUp = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    _seasonPopUp.translatesAutoresizingMaskIntoConstraints = NO;
    _seasonPopUp.font = MacLCDesign.headline;
    _seasonPopUp.target = self;
    _seasonPopUp.action = @selector(seasonDidChange:);
    _seasonPopUp.accessibilityLabel = _NS("Season");
    [_seasonShelfView addSubview:_seasonPopUp];

    NSCollectionViewCompositionalLayoutSectionProvider provider = ^NSCollectionLayoutSection * _Nullable(NSInteger sectionIndex, id<NSCollectionLayoutEnvironment> environment) {
        NSCollectionLayoutSection *section = [MacLCWatchLayout episodeShelfSectionWithEnvironment:environment];
        section.boundarySupplementaryItems = @[];
        return section;
    };
    NSCollectionViewCompositionalLayout *layout = [[NSCollectionViewCompositionalLayout alloc] initWithSectionProvider:provider];

    MacLCWatchEpisodesCollectionView * const epCV = [[MacLCWatchEpisodesCollectionView alloc] initWithFrame:NSZeroRect];
    epCV.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    epCV.collectionViewLayout = layout;
    epCV.dataSource = self;
    epCV.delegate = self;
    epCV.selectable = YES;
    epCV.backgroundColors = @[NSColor.clearColor];
    [epCV registerClass:[MacLCWatchEpisodeItem class] forItemWithIdentifier:MacLCWatchEpisodeItemIdentifier];

    __weak typeof(self) weakSelf = self;
    epCV.contextMenuProvider = ^NSMenu * _Nullable(NSIndexPath * _Nonnull indexPath) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return nil;
        if (indexPath.item < (NSInteger)strongSelf->_episodesForCurrentSeason.count) {
            MacLCAddonVideo *video = strongSelf->_episodesForCurrentSeason[indexPath.item];
            return [MacLCWatchActions menuForItem:strongSelf->_item video:video inHistory:NO];
        }
        return nil;
    };
    _episodesCollectionView = epCV;

    _episodesScrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    _episodesScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _episodesScrollView.documentView = _episodesCollectionView;
    _episodesScrollView.drawsBackground = NO;
    _episodesScrollView.hasVerticalScroller = NO;
    _episodesScrollView.hasHorizontalScroller = NO;
    [_seasonShelfView addSubview:_episodesScrollView];

    _episodesScrollViewHeightConstraint = [_episodesScrollView.heightAnchor constraintEqualToConstant:[self episodesScrollViewHeight]];

    [NSLayoutConstraint activateConstraints:@[
        [_seasonShelfView.topAnchor constraintEqualToAnchor:_episodesContainerView.topAnchor],
        [_seasonShelfView.bottomAnchor constraintEqualToAnchor:_episodesContainerView.bottomAnchor],
        [_seasonShelfView.leadingAnchor constraintEqualToAnchor:_episodesContainerView.leadingAnchor],
        [_seasonShelfView.trailingAnchor constraintEqualToAnchor:_episodesContainerView.trailingAnchor],

        [_seasonPopUp.topAnchor constraintEqualToAnchor:_seasonShelfView.topAnchor],
        [_seasonPopUp.leadingAnchor constraintEqualToAnchor:_seasonShelfView.leadingAnchor constant:40.0],

        [_episodesScrollView.topAnchor constraintEqualToAnchor:_seasonPopUp.bottomAnchor constant:MacLCDesign.spacingM],
        [_episodesScrollView.leadingAnchor constraintEqualToAnchor:_seasonShelfView.leadingAnchor],
        [_episodesScrollView.trailingAnchor constraintEqualToAnchor:_seasonShelfView.trailingAnchor],
        _episodesScrollViewHeightConstraint,
        [_episodesScrollView.bottomAnchor constraintEqualToAnchor:_seasonShelfView.bottomAnchor],
    ]];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(preferredScrollerStyleDidChange:)
                                               name:NSPreferredScrollerStyleDidChangeNotification
                                             object:nil];

    // Episode error state
    _episodesErrorView = [[NSView alloc] initWithFrame:NSZeroRect];
    _episodesErrorView.translatesAutoresizingMaskIntoConstraints = NO;
    _episodesErrorView.hidden = YES;
    [_episodesContainerView addSubview:_episodesErrorView];

    _episodesErrorLabel = [NSTextField labelWithString:_NS("Can't load episodes")];
    _episodesErrorLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _episodesErrorLabel.font = MacLCDesign.headline;
    _episodesErrorLabel.textColor = MacLCDesign.secondaryLabel;
    [_episodesErrorView addSubview:_episodesErrorLabel];

    _episodesTryAgainButton = [NSButton buttonWithTitle:_NS("Try Again") target:self action:@selector(loadMeta)];
    _episodesTryAgainButton.translatesAutoresizingMaskIntoConstraints = NO;
    _episodesTryAgainButton.bezelStyle = NSBezelStylePush;
    [_episodesErrorView addSubview:_episodesTryAgainButton];

    [NSLayoutConstraint activateConstraints:@[
        [_episodesErrorView.topAnchor constraintEqualToAnchor:_episodesContainerView.topAnchor],
        [_episodesErrorView.bottomAnchor constraintEqualToAnchor:_episodesContainerView.bottomAnchor],
        [_episodesErrorView.leadingAnchor constraintEqualToAnchor:_episodesContainerView.leadingAnchor constant:40.0],
        [_episodesErrorView.trailingAnchor constraintEqualToAnchor:_episodesContainerView.trailingAnchor constant:-40.0],
        [_episodesErrorView.heightAnchor constraintGreaterThanOrEqualToConstant:60.0],

        [_episodesErrorLabel.leadingAnchor constraintEqualToAnchor:_episodesErrorView.leadingAnchor],
        [_episodesErrorLabel.centerYAnchor constraintEqualToAnchor:_episodesErrorView.centerYAnchor],

        [_episodesTryAgainButton.leadingAnchor constraintEqualToAnchor:_episodesErrorLabel.trailingAnchor constant:MacLCDesign.spacingM],
        [_episodesTryAgainButton.centerYAnchor constraintEqualToAnchor:_episodesErrorView.centerYAnchor],
    ]];
}

- (CGFloat)episodesScrollViewHeight
{
    CGFloat epHeight = [MacLCWatchEpisodeItem heightForWidth:kMacLCDetailDefaultEpisodeWidth];
    if (epHeight <= 0.0) {
        epHeight = 265.0;
    }
    CGFloat scrollerHeight = 0.0;
    if (NSScroller.preferredScrollerStyle == NSScrollerStyleLegacy) {
        scrollerHeight = [NSScroller scrollerWidthForControlSize:NSControlSizeRegular
                                                   scrollerStyle:NSScrollerStyleLegacy];
    }
    return epHeight + 36.0 + scrollerHeight;
}

- (void)preferredScrollerStyleDidChange:(NSNotification *)notification
{
    if (_episodesScrollViewHeightConstraint) {
        _episodesScrollViewHeightConstraint.constant = [self episodesScrollViewHeight];
        [self.view setNeedsLayout:YES];
    }
}

- (void)setUpAboutView
{
    _aboutContainerView = [[NSView alloc] initWithFrame:NSZeroRect];
    _aboutContainerView.translatesAutoresizingMaskIntoConstraints = NO;
    [_documentView addSubview:_aboutContainerView];

    _aboutTitleLabel = [NSTextField labelWithString:_NS("About")];
    _aboutTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _aboutTitleLabel.font = [NSFont systemFontOfSize:MacLCDesign.title2.pointSize weight:NSFontWeightBold];
    _aboutTitleLabel.textColor = MacLCDesign.primaryLabel;
    [_aboutContainerView addSubview:_aboutTitleLabel];

    _aboutDescLabel = [NSTextField wrappingLabelWithString:_item.itemDescription ?: @""];
    _aboutDescLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _aboutDescLabel.font = MacLCDesign.body;
    _aboutDescLabel.textColor = MacLCDesign.primaryLabel;
    _aboutDescLabel.selectable = YES;
    [_aboutContainerView addSubview:_aboutDescLabel];

    // 2-column grid
    _aboutGenresKeyLabel = [NSTextField labelWithString:_NS("Genres")];
    _aboutGenresKeyLabel.font = MacLCDesign.subheadline;
    _aboutGenresKeyLabel.textColor = MacLCDesign.secondaryLabel;

    _aboutGenresValueLabel = [NSTextField wrappingLabelWithString:@"—"];
    _aboutGenresValueLabel.font = MacLCDesign.subheadline;
    _aboutGenresValueLabel.textColor = MacLCDesign.primaryLabel;

    NSStackView *genresStack = [NSStackView stackViewWithViews:@[_aboutGenresKeyLabel, _aboutGenresValueLabel]];
    genresStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    genresStack.alignment = NSLayoutAttributeLeading;
    genresStack.spacing = 2.0;

    _aboutReleasedKeyLabel = [NSTextField labelWithString:_NS("Released")];
    _aboutReleasedKeyLabel.font = MacLCDesign.subheadline;
    _aboutReleasedKeyLabel.textColor = MacLCDesign.secondaryLabel;

    _aboutReleasedValueLabel = [NSTextField labelWithString:@"—"];
    _aboutReleasedValueLabel.font = MacLCDesign.subheadline;
    _aboutReleasedValueLabel.textColor = MacLCDesign.primaryLabel;

    NSStackView *releasedStack = [NSStackView stackViewWithViews:@[_aboutReleasedKeyLabel, _aboutReleasedValueLabel]];
    releasedStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    releasedStack.alignment = NSLayoutAttributeLeading;
    releasedStack.spacing = 2.0;

    NSStackView *col1 = [NSStackView stackViewWithViews:@[genresStack, releasedStack]];
    col1.orientation = NSUserInterfaceLayoutOrientationVertical;
    col1.alignment = NSLayoutAttributeLeading;
    col1.spacing = MacLCDesign.spacingM;

    _aboutRuntimeKeyLabel = [NSTextField labelWithString:_NS("Runtime")];
    _aboutRuntimeKeyLabel.font = MacLCDesign.subheadline;
    _aboutRuntimeKeyLabel.textColor = MacLCDesign.secondaryLabel;

    _aboutRuntimeValueLabel = [NSTextField labelWithString:@"—"];
    _aboutRuntimeValueLabel.font = MacLCDesign.subheadline;
    _aboutRuntimeValueLabel.textColor = MacLCDesign.primaryLabel;

    NSStackView *runtimeStack = [NSStackView stackViewWithViews:@[_aboutRuntimeKeyLabel, _aboutRuntimeValueLabel]];
    runtimeStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    runtimeStack.alignment = NSLayoutAttributeLeading;
    runtimeStack.spacing = 2.0;

    _aboutRatingKeyLabel = [NSTextField labelWithString:_NS("Rating")];
    _aboutRatingKeyLabel.font = MacLCDesign.subheadline;
    _aboutRatingKeyLabel.textColor = MacLCDesign.secondaryLabel;

    _aboutRatingValueLabel = [NSTextField labelWithString:@"—"];
    _aboutRatingValueLabel.font = MacLCDesign.subheadline;
    _aboutRatingValueLabel.textColor = MacLCDesign.primaryLabel;

    NSStackView *ratingStack = [NSStackView stackViewWithViews:@[_aboutRatingKeyLabel, _aboutRatingValueLabel]];
    ratingStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    ratingStack.alignment = NSLayoutAttributeLeading;
    ratingStack.spacing = 2.0;

    NSStackView *col2 = [NSStackView stackViewWithViews:@[runtimeStack, ratingStack]];
    col2.orientation = NSUserInterfaceLayoutOrientationVertical;
    col2.alignment = NSLayoutAttributeLeading;
    col2.spacing = MacLCDesign.spacingM;

    NSStackView *gridStack = [NSStackView stackViewWithViews:@[col1, col2]];
    gridStack.translatesAutoresizingMaskIntoConstraints = NO;
    gridStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    gridStack.distribution = NSStackViewDistributionFillEqually;
    gridStack.alignment = NSLayoutAttributeTop;
    gridStack.spacing = 40.0;
    [_aboutContainerView addSubview:gridStack];

    [NSLayoutConstraint activateConstraints:@[
        [_aboutTitleLabel.topAnchor constraintEqualToAnchor:_aboutContainerView.topAnchor],
        [_aboutTitleLabel.leadingAnchor constraintEqualToAnchor:_aboutContainerView.leadingAnchor],
        [_aboutTitleLabel.trailingAnchor constraintEqualToAnchor:_aboutContainerView.trailingAnchor],

        [_aboutDescLabel.topAnchor constraintEqualToAnchor:_aboutTitleLabel.bottomAnchor constant:MacLCDesign.spacingM],
        [_aboutDescLabel.leadingAnchor constraintEqualToAnchor:_aboutContainerView.leadingAnchor],
        [_aboutDescLabel.trailingAnchor constraintEqualToAnchor:_aboutContainerView.trailingAnchor],

        [gridStack.topAnchor constraintEqualToAnchor:_aboutDescLabel.bottomAnchor constant:MacLCDesign.spacingL],
        [gridStack.leadingAnchor constraintEqualToAnchor:_aboutContainerView.leadingAnchor],
        [gridStack.trailingAnchor constraintEqualToAnchor:_aboutContainerView.trailingAnchor],
        [gridStack.bottomAnchor constraintEqualToAnchor:_aboutContainerView.bottomAnchor],
    ]];
}

- (void)installMainConstraints
{
    [NSLayoutConstraint activateConstraints:@[
        [_headerView.topAnchor constraintEqualToAnchor:_documentView.topAnchor],
        [_headerView.leadingAnchor constraintEqualToAnchor:_documentView.leadingAnchor],
        [_headerView.trailingAnchor constraintEqualToAnchor:_documentView.trailingAnchor],
    ]];

    _headerHeightConstraint = [_headerView.heightAnchor constraintEqualToConstant:540.0];
    _headerHeightConstraint.active = YES;

    if ([self isSeries] && _episodesContainerView) {
        [NSLayoutConstraint activateConstraints:@[
            [_episodesContainerView.topAnchor constraintEqualToAnchor:_headerView.bottomAnchor constant:36.0],
            [_episodesContainerView.leadingAnchor constraintEqualToAnchor:_documentView.leadingAnchor],
            [_episodesContainerView.trailingAnchor constraintEqualToAnchor:_documentView.trailingAnchor],

            [_aboutContainerView.topAnchor constraintEqualToAnchor:_episodesContainerView.bottomAnchor constant:36.0],
            [_aboutContainerView.leadingAnchor constraintEqualToAnchor:_documentView.leadingAnchor constant:40.0],
            [_aboutContainerView.trailingAnchor constraintEqualToAnchor:_documentView.trailingAnchor constant:-40.0],
            [_aboutContainerView.bottomAnchor constraintEqualToAnchor:_documentView.bottomAnchor constant:-48.0],
        ]];
    } else {
        [NSLayoutConstraint activateConstraints:@[
            [_aboutContainerView.topAnchor constraintEqualToAnchor:_headerView.bottomAnchor constant:36.0],
            [_aboutContainerView.leadingAnchor constraintEqualToAnchor:_documentView.leadingAnchor constant:40.0],
            [_aboutContainerView.trailingAnchor constraintEqualToAnchor:_documentView.trailingAnchor constant:-40.0],
            [_aboutContainerView.bottomAnchor constraintEqualToAnchor:_documentView.bottomAnchor constant:-48.0],
        ]];
    }
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(watchLibraryDidChange:)
                                               name:MacLCWatchLibraryDidChangeNotification
                                             object:nil];
    [self updateViewsWithItem];
    [self loadMeta];
}

- (void)viewDidAppear
{
    [super viewDidAppear];
    _appeared = YES;
    if (_initialShowStreams && _metaLoaded) {
        _initialShowStreams = NO;
        [self playButtonAction:_playButton];
    }
}

- (void)viewDidLayout
{
    [super viewDidLayout];
    CGFloat targetHeight = self.view.bounds.size.height * 0.75;
    if (targetHeight < kMacLCDetailMinHeaderHeight) {
        targetHeight = kMacLCDetailMinHeaderHeight;
    } else if (targetHeight > kMacLCDetailMaxHeaderHeight) {
        targetHeight = kMacLCDetailMaxHeaderHeight;
    }
    if (_headerHeightConstraint && _headerHeightConstraint.constant != targetHeight) {
        _headerHeightConstraint.constant = targetHeight;
    }
    const NSEdgeInsets safe = self.view.safeAreaInsets;
    const NSEdgeInsets insets = NSEdgeInsetsMake(0.0, safe.left, safe.bottom, safe.right);
    const NSEdgeInsets current = _scrollView.contentInsets;
    if (current.top != insets.top || current.left != insets.left ||
        current.bottom != insets.bottom || current.right != insets.right) {
        _scrollView.contentInsets = insets;
        _scrollView.scrollerInsets = NSEdgeInsetsMake(safe.top, 0.0, 0.0, 0.0);
    }
    _documentWidthConstraint.constant = -(insets.left + insets.right);
    [self updateMoreButtonVisibility];
}

#pragma mark - Content Updates

- (void)updateViewsWithItem
{
    // Background picture
    [self loadBackgroundPicture];

    // Logo & title
    [self loadLogoOrTitle];

    // Facts
    _factsLabel.stringValue = MacLCWatchFactsLine(_item.type, _item.genres, nil, nil);
    _factsLabel.hidden = (_factsLabel.stringValue.length == 0);

    // Description & More button
    [self updateDescriptionText];

    // Details line
    [self updateDetailsLine];

    // Play button & watch library states
    [self updatePlayButtonAndStates];

    // Favorite button
    [self updateFavoriteButton];

    // About section
    [self updateAboutSection];
}

- (void)updateViewsWithMeta
{
    // Background picture (meta might have a better background)
    [self loadBackgroundPicture];

    // Logo & title
    [self loadLogoOrTitle];

    // Facts
    NSArray *genres = (_meta.genres.count > 0) ? _meta.genres : _item.genres;
    _factsLabel.stringValue = MacLCWatchFactsLine(_item.type, genres, nil, nil);
    _factsLabel.hidden = (_factsLabel.stringValue.length == 0);

    // Description & More button
    [self updateDescriptionText];

    // Details line
    [self updateDetailsLine];

    // Play button & watch library states
    [self updatePlayButtonAndStates];

    // Favorite button
    [self updateFavoriteButton];

    // Trailer
    if (_meta.trailerYouTubeIdentifier.length > 0) {
        _trailerButton.hidden = NO;
    } else {
        _trailerButton.hidden = YES;
    }

    // Credits
    [self updateCredits];

    // Episodes
    if ([self isSeries]) {
        [self populateSeasons];
    }

    // About section
    [self updateAboutSection];
}

- (void)loadBackgroundPicture
{
    NSURL *bgURL = _meta.backgroundURL ?: _item.backgroundURL ?: _meta.posterURL ?: _item.posterURL;
    if (!bgURL) return;

    CGFloat scale = self.view.window.backingScaleFactor ?: 2.0;
    NSSize targetSize = _headerView.bounds.size;
    if (targetSize.width < 100.0 || targetSize.height < 100.0) {
        targetSize = NSMakeSize(1280.0, 720.0);
    }

    [_pictureRequest cancel];
    _pictureRequest = nil;

    MacLCWatchImageRequest *pictureReq = nil;
    __weak typeof(self) weakSelf = self;
    NSImage *cached = [MacLCWatchImageCache.sharedCache imageForURL:bgURL
                                                         pointSize:targetSize
                                                             scale:scale
                                                           request:&pictureReq
                                                        completion:^(NSImage * _Nullable image) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf->_pictureView.image = image;
    }];
    _pictureRequest = pictureReq;
    if (cached) {
        _pictureView.image = cached;
    }
}

- (void)loadLogoOrTitle
{
    NSURL *logoURL = _meta.logoURL ?: _item.logoURL;
    NSString *displayName = _meta.name ?: _item.name ?: @"";
    _titleLabel.stringValue = displayName;

    if (logoURL) {
        CGFloat scale = self.view.window.backingScaleFactor ?: 2.0;
        [_logoRequest cancel];
        _logoRequest = nil;

        MacLCWatchImageRequest *logoReq = nil;
        __weak typeof(self) weakSelf = self;
        NSImage *cached = [MacLCWatchImageCache.sharedCache imageForURL:logoURL
                                                             pointSize:NSMakeSize(360.0, 120.0)
                                                                 scale:scale
                                                               request:&logoReq
                                                            completion:^(NSImage * _Nullable image) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            if (image) {
                strongSelf->_logoImageView.image = image;
                strongSelf->_logoImageView.hidden = NO;
                strongSelf->_titleLabel.hidden = YES;
            } else {
                strongSelf->_logoImageView.hidden = YES;
                strongSelf->_titleLabel.hidden = NO;
            }
        }];
        _logoRequest = logoReq;
        if (cached) {
            _logoImageView.image = cached;
            _logoImageView.hidden = NO;
            _titleLabel.hidden = YES;
        } else {
            _logoImageView.hidden = YES;
            _titleLabel.hidden = NO;
        }
    } else {
        _logoImageView.hidden = YES;
        _titleLabel.hidden = NO;
    }
}

- (void)updateMoreButtonVisibility
{
    NSString *desc = _meta.itemDescription ?: _item.itemDescription ?: @"";
    if (desc.length == 0) {
        _moreButton.hidden = YES;
        return;
    }

    CGFloat labelWidth = _descLabel.bounds.size.width;
    if (labelWidth <= 10.0) {
        labelWidth = 560.0;
    }

    NSFont *font = _descLabel.font ?: MacLCDesign.body;
    NSDictionary *attrs = @{NSFontAttributeName: font};
    NSRect textRect = [desc boundingRectWithSize:NSMakeSize(labelWidth, CGFLOAT_MAX)
                                         options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                                      attributes:attrs];

    NSRect fourLinesRect = [@"A\nB\nC\nD" boundingRectWithSize:NSMakeSize(labelWidth, CGFLOAT_MAX)
                                                      options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                                                   attributes:attrs];
    CGFloat maxHeight = fourLinesRect.size.height;
    if (maxHeight <= 0.0) {
        maxHeight = font.pointSize * 1.35 * 4.2;
    }

    _moreButton.hidden = (textRect.size.height <= maxHeight + 1.0);
}

- (void)updateDescriptionText
{
    NSString *desc = _meta.itemDescription ?: _item.itemDescription ?: @"";
    _descLabel.stringValue = desc;
    [self updateMoreButtonVisibility];
}

- (void)updateDetailsLine
{
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    NSString *rel = _meta.releaseInfo ?: _item.releaseInfo;
    if (rel.length > 0) {
        [parts addObject:rel];
    }
    NSString *rt = _meta.runtime ?: _item.runtime;
    if (rt.length > 0) {
        NSString *formattedRt = MacLCFormatRuntime(rt);
        if (formattedRt.length > 0) {
            [parts addObject:formattedRt];
        }
    }
    NSString *rating = _meta.imdbRating ?: _item.imdbRating;
    if (rating.length > 0) {
        if ([rating containsString:@"IMDb"]) {
            [parts addObject:rating];
        } else {
            [parts addObject:[NSString stringWithFormat:@"★ %@ IMDb", rating]];
        }
    }
    _detailsLabel.stringValue = [parts componentsJoinedByString:@" · "];
}

- (void)updatePlayButtonAndStates
{
    MacLCWatchLibrary * const library = MacLCWatchLibrary.sharedLibrary;
    MacLCWatchEntry * const entry = [library entryForTitle:_item.identifier];
    const BOOL isSeries = [self isSeries];

    if (!isSeries) {
        MacLCWatchProgress * const movieProgress = [library progressForTitle:_item.identifier video:nil];
        const BOOL canResume = (movieProgress != nil && movieProgress.canResume) ||
                               (entry != nil && entry.resumeTarget != nil && entry.resumeTarget.kind == MacLCWatchResumeKindResume);
        const BOOL isWatched = (movieProgress != nil && movieProgress.isWatched) || (entry != nil && entry.isWatched);

        // Watched pill next to facts line (only for watched movie)
        _watchedPill.hidden = !isWatched;

        if (canResume) {
            _playButton.title = _NS("Resume");
            _playButton.image = [MacLCDesign symbolNamed:@"play.fill" accessibilityLabel:nil];
            _startOverButton.hidden = NO;

            // Subtitle in facts area
            NSString *timeText = nil;
            if (entry != nil && entry.resumeTarget != nil && entry.resumeTarget.detailText.length > 0) {
                timeText = entry.resumeTarget.detailText;
            } else {
                NSTimeInterval remaining = (movieProgress != nil) ? movieProgress.remaining : 0.0;
                if (remaining <= 0.0 && movieProgress != nil && movieProgress.duration > 0.0 && movieProgress.position > 0.0) {
                    remaining = movieProgress.duration - movieProgress.position;
                }
                if (remaining > 0.0) {
                    NSInteger const totalMins = (NSInteger)ceil(remaining / 60.0);
                    if (totalMins >= 60) {
                        NSInteger const h = totalMins / 60;
                        NSInteger const m = totalMins % 60;
                        if (m > 0) {
                            timeText = [NSString stringWithFormat:_NS("%ld h %ld min left"), (long)h, (long)m];
                        } else {
                            timeText = [NSString stringWithFormat:_NS("%ld h left"), (long)h];
                        }
                    } else {
                        timeText = [NSString stringWithFormat:_NS("%ld min left"), (long)totalMins];
                    }
                } else {
                    timeText = _NS("Resume");
                }
            }
            _factsSubtitleLabel.stringValue = timeText ?: @"";
            _factsSubtitleLabel.hidden = NO;

            // Progress bar under details line (200 wide, on picture, white)
            double const fraction = (movieProgress != nil) ? movieProgress.fraction : ((entry != nil) ? entry.fraction : 0.0);
            _progressBar.fraction = fraction;
            _progressBar.hidden = NO;
            [_headerLeadingStack setCustomSpacing:8.0 afterView:_detailsLabel];
        } else {
            _startOverButton.hidden = YES;
            _factsSubtitleLabel.stringValue = @"";
            _factsSubtitleLabel.hidden = YES;
            _progressBar.fraction = 0.0;
            _progressBar.hidden = YES;
            [_headerLeadingStack setCustomSpacing:16.0 afterView:_detailsLabel];

            if (isWatched) {
                _playButton.title = _NS("Play Again");
                _playButton.image = [MacLCDesign symbolNamed:@"arrow.counterclockwise" accessibilityLabel:nil];
            } else {
                _playButton.title = _NS("Play");
                _playButton.image = [MacLCDesign symbolNamed:@"play.fill" accessibilityLabel:nil];
            }
        }
    } else {
        // Series
        _watchedPill.hidden = YES;
        _startOverButton.hidden = YES;
        _factsSubtitleLabel.stringValue = @"";
        _factsSubtitleLabel.hidden = YES;
        _progressBar.fraction = 0.0;
        _progressBar.hidden = YES;
        [_headerLeadingStack setCustomSpacing:16.0 afterView:_detailsLabel];

        MacLCAddonVideo *targetVideo = nil;
        MacLCWatchResumeTarget * const target = entry.resumeTarget;
        if (target != nil && _meta.videos.count > 0) {
            for (MacLCAddonVideo *v in _meta.videos) {
                if ([v.identifier isEqualToString:target.videoIdentifier] ||
                    (v.season == target.season && v.episode == target.episode)) {
                    targetVideo = v;
                    break;
                }
            }
        }

        if (targetVideo != nil) {
            if (target.kind == MacLCWatchResumeKindResume) {
                _playButton.title = [NSString stringWithFormat:_NS("Resume S%ld, E%ld"), (long)target.season, (long)target.episode];
            } else {
                _playButton.title = [NSString stringWithFormat:_NS("Play S%ld, E%ld"), (long)target.season, (long)target.episode];
            }
        } else {
            MacLCAddonVideo * const firstEp = [self firstPlayableEpisode];
            if (firstEp != nil && firstEp.season >= 1 && firstEp.episode >= 1) {
                _playButton.title = [NSString stringWithFormat:_NS("Play S%ld, E%ld"), (long)firstEp.season, (long)firstEp.episode];
            } else {
                _playButton.title = _NS("Play S1, E1");
            }
        }
        _playButton.image = [MacLCDesign symbolNamed:@"play.fill" accessibilityLabel:nil];
    }

    _playButton.accessibilityLabel = _playButton.title;
    _playButton.toolTip = _playButton.title;
}

- (void)updateFavoriteButton
{
    BOOL const isFav = [MacLCWatchLibrary.sharedLibrary isFavorite:_item.identifier];
    NSString * const symbol = isFav ? @"heart.fill" : @"heart";
    NSString * const label = isFav ? _NS("Remove from Favorites") : _NS("Add to Favorites");
    _favoriteButton.image = [MacLCDesign symbolNamed:symbol accessibilityLabel:label];
    _favoriteButton.accessibilityLabel = label;
    _favoriteButton.toolTip = label;
    _favoriteButton.contentTintColor = isFav ? MacLCDesign.accent : nil;
}

- (void)favoriteButtonAction:(id)sender
{
    BOOL const isFav = [MacLCWatchLibrary.sharedLibrary isFavorite:_item.identifier];
    [MacLCWatchLibrary.sharedLibrary setFavorite:!isFav forItem:_item];
    [self updateFavoriteButton];
}

- (void)updateCredits
{
    if (_meta.cast.count > 0) {
        NSArray *topCast = [_meta.cast subarrayWithRange:NSMakeRange(0, MIN(3, _meta.cast.count))];
        NSString *castStr = [topCast componentsJoinedByString:@", "];
        NSMutableAttributedString *mas = [[NSMutableAttributedString alloc] initWithString:_NS("Starring ")
            attributes:@{
                NSFontAttributeName: MacLCDesign.subheadline,
                NSForegroundColorAttributeName: [NSColor colorWithWhite:1.0 alpha:0.75]
            }];
        [mas appendAttributedString:[[NSAttributedString alloc] initWithString:castStr
            attributes:@{
                NSFontAttributeName: MacLCDesign.subheadline,
                NSForegroundColorAttributeName: NSColor.whiteColor
            }]];
        _starringLabel.attributedStringValue = mas;
        _starringLabel.hidden = NO;
    } else {
        _starringLabel.hidden = YES;
    }

    if (_meta.directors.count > 0) {
        NSString *dirStr = [_meta.directors componentsJoinedByString:@", "];
        NSString *lblStr = (_meta.directors.count > 1) ? _NS("Directors ") : _NS("Director ");
        NSMutableAttributedString *mas = [[NSMutableAttributedString alloc] initWithString:lblStr
            attributes:@{
                NSFontAttributeName: MacLCDesign.subheadline,
                NSForegroundColorAttributeName: [NSColor colorWithWhite:1.0 alpha:0.75]
            }];
        [mas appendAttributedString:[[NSAttributedString alloc] initWithString:dirStr
            attributes:@{
                NSFontAttributeName: MacLCDesign.subheadline,
                NSForegroundColorAttributeName: NSColor.whiteColor
            }]];
        _directorLabel.attributedStringValue = mas;
        _directorLabel.hidden = NO;
    } else {
        _directorLabel.hidden = YES;
    }

    _creditsStack.hidden = (_starringLabel.hidden && _directorLabel.hidden);
}

- (void)updateAboutSection
{
    NSString *fullDesc = _meta.itemDescription ?: _item.itemDescription ?: @"";
    _aboutDescLabel.stringValue = fullDesc;
    _aboutDescLabel.hidden = (fullDesc.length == 0);

    NSArray *genres = (_meta.genres.count > 0) ? _meta.genres : _item.genres;
    _aboutGenresValueLabel.stringValue = (genres.count > 0) ? [genres componentsJoinedByString:@", "] : @"—";

    NSString *rel = _meta.releaseInfo ?: _item.releaseInfo;
    _aboutReleasedValueLabel.stringValue = (rel.length > 0) ? rel : @"—";

    NSString *rt = _meta.runtime ?: _item.runtime;
    _aboutRuntimeValueLabel.stringValue = (rt.length > 0) ? MacLCFormatRuntime(rt) : @"—";

    NSString *rating = _meta.imdbRating ?: _item.imdbRating;
    if (rating.length > 0) {
        if ([rating containsString:@"IMDb"]) {
            _aboutRatingValueLabel.stringValue = rating;
        } else {
            _aboutRatingValueLabel.stringValue = [NSString stringWithFormat:@"★ %@ IMDb", rating];
        }
    } else {
        _aboutRatingValueLabel.stringValue = @"—";
    }
}

#pragma mark - Meta Loading

- (void)loadMeta
{
    [_metaRequest cancel];
    _metaRequest = nil;

    _episodesErrorView.hidden = YES;

    __weak typeof(self) weakSelf = self;
    _metaRequest = [MacLCAddonStore.sharedStore fetchMetaForItem:_item completion:^(MacLCAddonMeta * _Nullable meta, NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf->_metaRequest = nil;
        strongSelf->_metaLoaded = YES;

        if (error && [strongSelf isSeries]) {
            strongSelf->_episodesErrorView.hidden = NO;
            strongSelf->_seasonShelfView.hidden = YES;
        } else {
            strongSelf->_episodesErrorView.hidden = YES;
            if (strongSelf->_seasonShelfView) {
                strongSelf->_seasonShelfView.hidden = NO;
            }
            if (meta) {
                strongSelf.meta = meta;
                if (meta.videos.count > 0) {
                    [MacLCWatchLibrary.sharedLibrary updateEpisodes:meta.videos forItem:strongSelf->_item];
                }
                [strongSelf updateViewsWithMeta];
            }
        }

        if (strongSelf->_initialShowStreams && strongSelf->_appeared) {
            strongSelf->_initialShowStreams = NO;
            [strongSelf playButtonAction:strongSelf->_playButton];
        }
    }];
}

#pragma mark - Episodes / Seasons

- (nullable MacLCAddonVideo *)firstPlayableEpisode
{
    MacLCAddonVideo *candidate = nil;
    NSInteger lowestSeason = NSIntegerMax;
    NSInteger lowestEpisode = NSIntegerMax;

    for (MacLCAddonVideo *v in _meta.videos) {
        if (v.season >= 1) {
            if (v.season < lowestSeason || (v.season == lowestSeason && v.episode < lowestEpisode)) {
                lowestSeason = v.season;
                lowestEpisode = v.episode;
                candidate = v;
            }
        }
    }
    return candidate;
}

- (void)populateSeasons
{
    [_seasonPopUp removeAllItems];
    NSMutableSet<NSNumber *> *seasonSet = [NSMutableSet set];
    for (MacLCAddonVideo *v in _meta.videos) {
        [seasonSet addObject:@(v.season)];
    }

    NSArray<NSNumber *> *sorted = [[seasonSet allObjects] sortedArrayUsingComparator:^NSComparisonResult(NSNumber *a, NSNumber *b) {
        if (a.integerValue == 0) return NSOrderedDescending;
        if (b.integerValue == 0) return NSOrderedAscending;
        return [a compare:b];
    }];

    for (NSNumber *sNum in sorted) {
        NSInteger s = sNum.integerValue;
        NSString *title = (s == 0) ? _NS("Specials") : [NSString stringWithFormat:_NS("Season %ld"), (long)s];
        NSMenuItem *menuItem = [[NSMenuItem alloc] initWithTitle:title action:nil keyEquivalent:@""];
        menuItem.tag = s;
        [_seasonPopUp.menu addItem:menuItem];
    }

    NSInteger selectTag = 1;
    if (sorted.count > 0) {
        selectTag = sorted.firstObject.integerValue;
    }
    [_seasonPopUp selectItemWithTag:selectTag];
    [self updateEpisodesForSelectedSeason];
}

- (void)seasonDidChange:(id)sender
{
    [self updateEpisodesForSelectedSeason];
}

- (void)updateEpisodesForSelectedSeason
{
    NSInteger targetSeason = _seasonPopUp.selectedTag;
    NSMutableArray<MacLCAddonVideo *> *eps = [NSMutableArray array];
    for (MacLCAddonVideo *v in _meta.videos) {
        if (v.season == targetSeason) {
            [eps addObject:v];
        }
    }
    [eps sortUsingComparator:^NSComparisonResult(MacLCAddonVideo *a, MacLCAddonVideo *b) {
        if (a.episode < b.episode) return NSOrderedAscending;
        if (a.episode > b.episode) return NSOrderedDescending;
        return NSOrderedSame;
    }];
    _episodesForCurrentSeason = [eps copy];
    [_episodesCollectionView reloadData];
}

#pragma mark - NSCollectionViewDataSource & Delegate

- (NSInteger)collectionView:(NSCollectionView *)collectionView numberOfItemsInSection:(NSInteger)section
{
    return _episodesForCurrentSeason.count;
}

- (NSCollectionViewItem *)collectionView:(NSCollectionView *)collectionView itemForRepresentedObjectAtIndexPath:(NSIndexPath *)indexPath
{
    MacLCWatchEpisodeItem *item = [collectionView makeItemWithIdentifier:MacLCWatchEpisodeItemIdentifier forIndexPath:indexPath];
    if (indexPath.item < (NSInteger)_episodesForCurrentSeason.count) {
        MacLCAddonVideo *video = _episodesForCurrentSeason[indexPath.item];
        [item configureWithVideo:video titleIdentifier:_item.identifier];
        item.view.menu = [MacLCWatchActions menuForItem:_item video:video inHistory:NO];

        __weak typeof(self) weakSelf = self;
        item.activationHandler = ^(MacLCAddonVideo *v) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf) {
                [strongSelf activateEpisode:v];
            }
        };
    }
    return item;
}

- (void)collectionView:(NSCollectionView *)collectionView didSelectItemsAtIndexPaths:(NSSet<NSIndexPath *> *)indexPaths
{
    [collectionView deselectItemsAtIndexPaths:indexPaths];
    NSIndexPath *indexPath = indexPaths.anyObject;
    if (indexPath && indexPath.item < (NSInteger)_episodesForCurrentSeason.count) {
        MacLCAddonVideo *video = _episodesForCurrentSeason[indexPath.item];
        [self activateEpisode:video];
    }
}

- (void)activateEpisode:(MacLCAddonVideo *)video
{
    MacLCWatchProgress * const progress = [MacLCWatchLibrary.sharedLibrary progressForTitle:_item.identifier video:video.identifier];
    if (progress != nil && progress.canResume) {
        BOOL const resumed = [MacLCWatchPlayback.sharedPlayback resumeProgress:progress item:_item];
        if (resumed) {
            return;
        }
    }
    [self showStreamPickerForVideo:video];
}

#pragma mark - User Actions

- (void)playButtonAction:(id)sender
{
    MacLCWatchLibrary * const library = MacLCWatchLibrary.sharedLibrary;
    MacLCWatchEntry * const entry = [library entryForTitle:_item.identifier];

    if (![self isSeries]) {
        MacLCWatchProgress * const movieProgress = [library progressForTitle:_item.identifier video:nil];
        const BOOL canResume = (movieProgress != nil && movieProgress.canResume) ||
                               (entry != nil && entry.resumeTarget != nil && entry.resumeTarget.kind == MacLCWatchResumeKindResume);

        if (canResume) {
            MacLCWatchProgress * const p = movieProgress ?: entry.resumeTarget.progress;
            BOOL resumed = NO;
            if (p != nil) {
                resumed = [MacLCWatchPlayback.sharedPlayback resumeProgress:p item:_item];
            }
            if (!resumed) {
                [self showStreamPickerForVideo:nil];
            }
            return;
        }

        const BOOL isWatched = (movieProgress != nil && movieProgress.isWatched) || (entry != nil && entry.isWatched);
        if (isWatched) {
            // "Play Again" — plays from 0
            if (movieProgress != nil && movieProgress.streamMRL.length > 0) {
                [MacLCWatchPlayback.sharedPlayback playMRL:movieProgress.streamMRL
                                               streamLabel:movieProgress.streamLabel
                                                      item:_item
                                           videoIdentifier:nil
                                                    season:0
                                                   episode:0
                                               episodeName:nil
                                             startPosition:0.0];
            } else {
                [self showStreamPickerForVideo:nil];
            }
            return;
        }

        // Regular unwatched movie
        [self showStreamPickerForVideo:nil];
        return;
    }

    // Series
    MacLCAddonVideo *targetVideo = nil;
    MacLCWatchResumeTarget * const target = entry.resumeTarget;
    if (target != nil && _meta.videos.count > 0) {
        for (MacLCAddonVideo *v in _meta.videos) {
            if ([v.identifier isEqualToString:target.videoIdentifier] ||
                (v.season == target.season && v.episode == target.episode)) {
                targetVideo = v;
                break;
            }
        }
    }

    if (targetVideo != nil) {
        if (target.kind == MacLCWatchResumeKindResume) {
            MacLCWatchProgress * const epProgress = target.progress ?: [library progressForTitle:_item.identifier video:targetVideo.identifier];
            BOOL resumed = NO;
            if (epProgress != nil) {
                resumed = [MacLCWatchPlayback.sharedPlayback resumeProgress:epProgress item:_item];
            }
            if (!resumed) {
                [self showStreamPickerForVideo:targetVideo];
            }
            return;
        } else {
            // Next up
            [self showStreamPickerForVideo:targetVideo];
            return;
        }
    }

    // Fall back to lowest season >= 1
    MacLCAddonVideo * const firstEp = [self firstPlayableEpisode];
    [self showStreamPickerForVideo:firstEp];
}

- (void)startOverButtonAction:(id)sender
{
    MacLCWatchLibrary * const library = MacLCWatchLibrary.sharedLibrary;
    MacLCWatchProgress * const movieProgress = [library progressForTitle:_item.identifier video:nil];
    if (movieProgress != nil && movieProgress.streamMRL.length > 0) {
        [MacLCWatchPlayback.sharedPlayback playMRL:movieProgress.streamMRL
                                       streamLabel:movieProgress.streamLabel
                                              item:_item
                                   videoIdentifier:nil
                                            season:0
                                           episode:0
                                       episodeName:nil
                                     startPosition:0.0];
    } else {
        [self showStreamPickerForVideo:nil];
    }
}

- (NSArray<MacLCAddonVideo *> *)releasedEpisodesForCurrentSeason
{
    NSMutableArray<MacLCAddonVideo *> * const released = [NSMutableArray array];
    NSDate * const now = [NSDate date];
    for (MacLCAddonVideo *v in _episodesForCurrentSeason) {
        if (v.released == nil || [v.released compare:now] != NSOrderedDescending) {
            [released addObject:v];
        }
    }
    return [released copy];
}

- (NSMenu *)buildActionsMenu
{
    NSMenu *menu = [MacLCWatchActions menuForItem:_item video:nil inHistory:NO];
    if (!menu) {
        menu = [[NSMenu alloc] initWithTitle:@""];
    }

    if ([self isSeries] && _episodesForCurrentSeason.count > 0) {
        NSArray<MacLCAddonVideo *> * const released = [self releasedEpisodesForCurrentSeason];
        if (released.count > 0) {
            NSInteger const seasonNum = _seasonPopUp.selectedTag;
            BOOL allWatched = YES;
            MacLCWatchLibrary * const library = MacLCWatchLibrary.sharedLibrary;
            for (MacLCAddonVideo *v in released) {
                MacLCWatchProgress *p = [library progressForTitle:_item.identifier video:v.identifier];
                if (p == nil || !p.isWatched) {
                    allWatched = NO;
                    break;
                }
            }

            if (menu.itemArray.count > 0) {
                [menu addItem:[NSMenuItem separatorItem]];
            }

            NSString *title;
            NSString *symbolName;
            if (allWatched) {
                title = (seasonNum == 0)
                    ? _NS("Mark Specials as Unwatched")
                    : [NSString stringWithFormat:_NS("Mark Season %ld as Unwatched"), (long)seasonNum];
                symbolName = @"arrow.counterclockwise.circle";
            } else {
                title = (seasonNum == 0)
                    ? _NS("Mark Specials as Watched")
                    : [NSString stringWithFormat:_NS("Mark Season %ld as Watched"), (long)seasonNum];
                symbolName = @"checkmark.circle";
            }

            NSMenuItem *seasonItem = [[NSMenuItem alloc] initWithTitle:title
                                                                action:@selector(toggleSeasonWatched:)
                                                         keyEquivalent:@""];
            seasonItem.target = self;
            seasonItem.image = [MacLCDesign symbolNamed:symbolName accessibilityLabel:title];
            seasonItem.representedObject = @(allWatched);
            [menu addItem:seasonItem];
        }
    }

    return menu;
}

- (void)actionsButtonAction:(id)sender
{
    NSMenu * const menu = [self buildActionsMenu];
    if (!menu) return;
    NSPoint const pt = [sender isFlipped] ? NSMakePoint(0.0, NSHeight([sender bounds])) : NSZeroPoint;
    [menu popUpMenuPositioningItem:nil atLocation:pt inView:sender];
}

- (void)toggleSeasonWatched:(NSMenuItem *)sender
{
    BOOL const wasAllWatched = [sender.representedObject boolValue];
    BOOL const newWatched = !wasAllWatched;
    NSArray<MacLCAddonVideo *> * const released = [self releasedEpisodesForCurrentSeason];
    if (released.count > 0) {
        [MacLCWatchLibrary.sharedLibrary markWatched:newWatched forItem:_item videos:released];
    }
}

- (void)watchLibraryDidChange:(NSNotification *)notification
{
    NSSet<NSString *> * const changed = notification.userInfo[MacLCWatchLibraryChangedTitlesKey];
    if (changed == nil || (_item.identifier != nil && [changed containsObject:_item.identifier])) {
        [self updateWatchLibraryState];
    }
}

- (void)updateWatchLibraryState
{
    [self updatePlayButtonAndStates];
    [self updateFavoriteButton];
    if ([self isSeries] && _episodesCollectionView != nil) {
        [_episodesCollectionView reloadData];
    }
}

- (void)trailerButtonAction:(id)sender
{
    if (_meta.trailerYouTubeIdentifier.length == 0) return;
    NSString *mrl = [NSString stringWithFormat:@"https://www.youtube.com/watch?v=%@", _meta.trailerYouTubeIdentifier];
    VLCOpenInputMetadata *metadata = [[VLCOpenInputMetadata alloc] init];
    metadata.MRLString = mrl;
    metadata.itemName = [NSString stringWithFormat:_NS("%@ — Trailer"), _meta.name ?: _item.name];
    [VLCMain.sharedInstance.playQueueController addPlayQueueItems:@[metadata] atPosition:(size_t)-1 startPlayback:YES];
}

- (void)showMoreDescription:(id)sender
{
    NSString *desc = _meta.itemDescription ?: _item.itemDescription;
    if (desc.length == 0) return;

    if (_descriptionPopover) {
        [_descriptionPopover performClose:nil];
        _descriptionPopover = nil;
    }

    NSViewController *vc = [[NSViewController alloc] init];
    NSView *container = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 380.0, 240.0)];

    NSTextField *label = [NSTextField wrappingLabelWithString:desc];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.font = MacLCDesign.body;
    label.textColor = MacLCDesign.primaryLabel;
    label.selectable = YES;

    NSScrollView *popScroll = [[NSScrollView alloc] initWithFrame:container.bounds];
    popScroll.translatesAutoresizingMaskIntoConstraints = NO;
    popScroll.drawsBackground = NO;
    popScroll.hasVerticalScroller = YES;
    popScroll.autohidesScrollers = YES;
    popScroll.documentView = label;
    [container addSubview:popScroll];

    [NSLayoutConstraint activateConstraints:@[
        [popScroll.topAnchor constraintEqualToAnchor:container.topAnchor constant:MacLCDesign.spacingL],
        [popScroll.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-MacLCDesign.spacingL],
        [popScroll.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:MacLCDesign.spacingL],
        [popScroll.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-MacLCDesign.spacingL],
        [label.widthAnchor constraintEqualToAnchor:popScroll.contentView.widthAnchor],
    ]];

    vc.view = container;
    _descriptionPopover = [[NSPopover alloc] init];
    _descriptionPopover.behavior = NSPopoverBehaviorTransient;
    _descriptionPopover.contentViewController = vc;
    [_descriptionPopover showRelativeToRect:_moreButton.bounds ofView:_moreButton preferredEdge:NSRectEdgeMaxY];
}

- (void)showStreamPickerForVideo:(nullable MacLCAddonVideo *)video
{
    NSWindow * const window = self.view.window;
    if (!window) return;

    MacLCStreamPickerController * const picker =
        [[MacLCStreamPickerController alloc] initWithItem:_item video:video];
    _streamPickerController = picker;

    __weak typeof(self) weakSelf = self;
    picker.completionHandler = ^(BOOL played) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf && strongSelf->_streamPickerController == picker) {
            strongSelf->_streamPickerController = nil;
        }
    };

    [picker beginSheetModalForWindow:window];
}

@end
