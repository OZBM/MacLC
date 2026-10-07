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

#pragma mark - Stream Table View and Cell

@interface MacLCWatchStreamTableView : NSTableView
@property (nonatomic, copy, nullable) void (^returnKeyHandler)(void);
@property (nonatomic, copy, nullable) void (^escapeKeyHandler)(void);
@end

@implementation MacLCWatchStreamTableView

- (void)keyDown:(NSEvent *)event
{
    if (event.keyCode == 36 && self.returnKeyHandler) {
        self.returnKeyHandler();
        return;
    }
    if (event.keyCode == 53 && self.escapeKeyHandler) {
        self.escapeKeyHandler();
        return;
    }
    [super keyDown:event];
}

@end

@interface MacLCWatchStreamCellView : NSTableCellView
@property (nonatomic, strong) NSTextField *headlineLabel;
@property (nonatomic, strong) NSStackView *badgesStackView;
@property (nonatomic, strong) NSTextField *detailsLabel;
- (void)configureWithBadges:(NSArray<NSString *> *)badges;
@end

@implementation MacLCWatchStreamCellView

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        _headlineLabel = [NSTextField wrappingLabelWithString:@""];
        _headlineLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _headlineLabel.font = MacLCDesign.body;
        _headlineLabel.textColor = MacLCDesign.primaryLabel;
        _headlineLabel.maximumNumberOfLines = 2;
        /* Truncating line break modes turn wrapping off: wrap, and cut the last line. */
        _headlineLabel.lineBreakMode = NSLineBreakByWordWrapping;
        _headlineLabel.cell.truncatesLastVisibleLine = YES;
        [_headlineLabel setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];

        _badgesStackView = [[NSStackView alloc] initWithFrame:NSZeroRect];
        _badgesStackView.translatesAutoresizingMaskIntoConstraints = NO;
        _badgesStackView.orientation = NSUserInterfaceLayoutOrientationHorizontal;
        _badgesStackView.alignment = NSLayoutAttributeCenterY;
        _badgesStackView.spacing = MacLCDesign.spacingXS;
        [_badgesStackView setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];

        _detailsLabel = [NSTextField wrappingLabelWithString:@""];
        _detailsLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _detailsLabel.font = MacLCDesign.subheadline;
        _detailsLabel.textColor = MacLCDesign.secondaryLabel;
        _detailsLabel.maximumNumberOfLines = 2;
        /* Truncating line break modes turn wrapping off: wrap, and cut the last line. */
        _detailsLabel.lineBreakMode = NSLineBreakByWordWrapping;
        _detailsLabel.cell.truncatesLastVisibleLine = YES;
        [_detailsLabel setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];

        NSStackView *detailRow = [NSStackView stackViewWithViews:@[_badgesStackView, _detailsLabel]];
        detailRow.translatesAutoresizingMaskIntoConstraints = NO;
        detailRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
        detailRow.alignment = NSLayoutAttributeCenterY;
        detailRow.spacing = MacLCDesign.spacingS;

        NSStackView *textStack = [NSStackView stackViewWithViews:@[_headlineLabel, detailRow]];
        textStack.translatesAutoresizingMaskIntoConstraints = NO;
        textStack.orientation = NSUserInterfaceLayoutOrientationVertical;
        textStack.alignment = NSLayoutAttributeLeading;
        textStack.spacing = 3.0;
        [self addSubview:textStack];

        [NSLayoutConstraint activateConstraints:@[
            [textStack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:MacLCDesign.spacingM],
            [textStack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-MacLCDesign.spacingM],
            [textStack.topAnchor constraintEqualToAnchor:self.topAnchor constant:8.0],
            [textStack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-8.0],
            [_headlineLabel.widthAnchor constraintLessThanOrEqualToAnchor:textStack.widthAnchor],
            [detailRow.widthAnchor constraintLessThanOrEqualToAnchor:textStack.widthAnchor],
        ]];
    }
    return self;
}

- (void)configureWithBadges:(NSArray<NSString *> *)badges
{
    for (NSView *v in [_badgesStackView.arrangedSubviews copy]) {
        [_badgesStackView removeView:v];
        [v removeFromSuperview];
    }
    for (NSString *title in badges) {
        MacLCFormatBadgeView *badge = [MacLCFormatBadgeView badgeWithTitle:title active:YES];
        [_badgesStackView addArrangedSubview:badge];
    }
    _badgesStackView.hidden = (badges.count == 0);
}

@end

#pragma mark - Stream Spinner Sentinel

@interface MacLCWatchSpinnerSentinel : NSObject
+ (instancetype)sharedSentinel;
@end

@implementation MacLCWatchSpinnerSentinel
+ (instancetype)sharedSentinel
{
    static MacLCWatchSpinnerSentinel *s;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        s = [[MacLCWatchSpinnerSentinel alloc] init];
    });
    return s;
}
@end

#pragma mark - Stream Picker View Controller

@interface MacLCWatchStreamPickerViewController : NSViewController <NSTableViewDataSource, NSTableViewDelegate>

@property (nonatomic, readonly) MacLCAddonItem *item;
@property (nonatomic, readonly, nullable) MacLCAddonVideo *video;
@property (nonatomic, readonly, nullable) MacLCAddonMeta *meta;
@property (nonatomic, weak) NSPopover *popover;

@property (nonatomic, strong) NSMutableArray<MacLCAddonStreamGroup *> *streamGroups;
@property (nonatomic, strong) NSArray *displayItems;
@property (nonatomic, nullable, strong) MacLCAddonStream *selectedStream;
@property (nonatomic, assign) BOOL isPending;
@property (nonatomic, nullable, strong) MacLCAddonRequest *request;

@property (nonatomic, strong) NSTextField *headerTitleLabel;
@property (nonatomic, strong) NSTextField *headerSubtitleLabel;
@property (nonatomic, strong) NSLayoutConstraint *rootHeightConstraint;
@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, strong) MacLCWatchStreamTableView *tableView;

@property (nonatomic, strong) NSView *emptyStateView;
@property (nonatomic, strong) NSImageView *emptyIconView;
@property (nonatomic, strong) NSTextField *emptyTitleLabel;
@property (nonatomic, strong) NSTextField *emptyMessageLabel;
@property (nonatomic, strong) NSButton *emptyActionButton;
@property (nonatomic, strong) NSProgressIndicator *emptySpinner;

@property (nonatomic, strong) NSButton *queueButton;
@property (nonatomic, strong) NSButton *playButton;

- (instancetype)initWithItem:(MacLCAddonItem *)item
                       video:(nullable MacLCAddonVideo *)video
                        meta:(nullable MacLCAddonMeta *)meta;

- (CGFloat)preferredPickerHeight;
- (void)updatePopoverHeight;

@end

@implementation MacLCWatchStreamPickerViewController

- (instancetype)initWithItem:(MacLCAddonItem *)item
                       video:(nullable MacLCAddonVideo *)video
                        meta:(nullable MacLCAddonMeta *)meta
{
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _item = item;
        _video = video;
        _meta = meta;
        _streamGroups = [NSMutableArray array];
        _displayItems = @[];
    }
    return self;
}

- (void)dealloc
{
    [_request cancel];
}

- (void)loadView
{
    NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 420.0, 360.0)];
    root.wantsLayer = YES;
    [root.widthAnchor constraintEqualToConstant:420.0].active = YES;

    _rootHeightConstraint = [root.heightAnchor constraintEqualToConstant:320.0];
    _rootHeightConstraint.priority = 900;
    _rootHeightConstraint.active = YES;

    // Header labels
    _headerTitleLabel = [NSTextField labelWithString:@""];
    _headerTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _headerTitleLabel.font = MacLCDesign.headline;
    _headerTitleLabel.textColor = MacLCDesign.primaryLabel;
    _headerTitleLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;

    _headerSubtitleLabel = [NSTextField labelWithString:@""];
    _headerSubtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _headerSubtitleLabel.font = MacLCDesign.subheadline;
    _headerSubtitleLabel.textColor = MacLCDesign.secondaryLabel;
    _headerSubtitleLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;

    NSStackView *headerStack = [NSStackView stackViewWithViews:@[_headerTitleLabel, _headerSubtitleLabel]];
    headerStack.translatesAutoresizingMaskIntoConstraints = NO;
    headerStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    headerStack.alignment = NSLayoutAttributeLeading;
    headerStack.spacing = 2.0;
    [root addSubview:headerStack];

    _headerTitleLabel.stringValue = _meta.name ?: _item.name ?: @"";

    if (_video != nil && (_video.season > 0 || _video.episode > 0)) {
        NSString *epStr = [NSString stringWithFormat:@"S%ld, E%ld", (long)_video.season, (long)_video.episode];
        if (_video.name.length > 0) {
            _headerSubtitleLabel.stringValue = [NSString stringWithFormat:@"%@ · %@", epStr, _video.name];
        } else {
            _headerSubtitleLabel.stringValue = epStr;
        }
        _headerSubtitleLabel.hidden = NO;
    } else {
        _headerSubtitleLabel.stringValue = @"";
        _headerSubtitleLabel.hidden = YES;
    }

    // Top separator
    NSBox *topSep = [[NSBox alloc] initWithFrame:NSZeroRect];
    topSep.translatesAutoresizingMaskIntoConstraints = NO;
    topSep.boxType = NSBoxSeparator;
    [root addSubview:topSep];

    // Table view
    _tableView = [[MacLCWatchStreamTableView alloc] initWithFrame:NSZeroRect];
    _tableView.autoresizingMask = NSViewWidthSizable;
    _tableView.headerView = nil;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.target = self;
    _tableView.doubleAction = @selector(tableDoubleClicked:);
    _tableView.usesAutomaticRowHeights = YES;
    _tableView.rowHeight = 56.0;

    __weak typeof(self) weakSelf = self;
    _tableView.returnKeyHandler = ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf && strongSelf.selectedStream) {
            [strongSelf playStream:strongSelf.selectedStream];
        }
    };
    _tableView.escapeKeyHandler = ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf && strongSelf.popover) {
            [strongSelf.popover performClose:nil];
        }
    };

    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"StreamColumn"];
    column.resizingMask = NSTableColumnAutoresizingMask;
    [_tableView addTableColumn:column];

    _scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _scrollView.documentView = _tableView;
    _scrollView.drawsBackground = NO;
    _scrollView.hasVerticalScroller = YES;
    _scrollView.autohidesScrollers = YES;
    _scrollView.hasHorizontalScroller = NO;
    [root addSubview:_scrollView];

    // Empty state container
    _emptyStateView = [[NSView alloc] initWithFrame:NSZeroRect];
    _emptyStateView.translatesAutoresizingMaskIntoConstraints = NO;
    _emptyStateView.hidden = YES;
    [root addSubview:_emptyStateView];

    _emptySpinner = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
    _emptySpinner.translatesAutoresizingMaskIntoConstraints = NO;
    _emptySpinner.style = NSProgressIndicatorStyleSpinning;
    _emptySpinner.controlSize = NSControlSizeRegular;
    _emptySpinner.displayedWhenStopped = NO;
    [_emptyStateView addSubview:_emptySpinner];

    _emptyIconView = [[NSImageView alloc] initWithFrame:NSZeroRect];
    _emptyIconView.translatesAutoresizingMaskIntoConstraints = NO;
    _emptyIconView.imageScaling = NSImageScaleProportionallyUpOrDown;
    [_emptyStateView addSubview:_emptyIconView];

    _emptyTitleLabel = [NSTextField labelWithString:@""];
    _emptyTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _emptyTitleLabel.alignment = NSTextAlignmentCenter;
    _emptyTitleLabel.font = MacLCDesign.headline;
    _emptyTitleLabel.textColor = MacLCDesign.primaryLabel;
    _emptyTitleLabel.maximumNumberOfLines = 2;
    [_emptyStateView addSubview:_emptyTitleLabel];

    _emptyMessageLabel = [NSTextField labelWithString:@""];
    _emptyMessageLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _emptyMessageLabel.alignment = NSTextAlignmentCenter;
    _emptyMessageLabel.font = MacLCDesign.subheadline;
    _emptyMessageLabel.textColor = MacLCDesign.secondaryLabel;
    _emptyMessageLabel.maximumNumberOfLines = 3;
    _emptyMessageLabel.lineBreakMode = NSLineBreakByWordWrapping;
    [_emptyStateView addSubview:_emptyMessageLabel];

    _emptyActionButton = [NSButton buttonWithTitle:@"" target:nil action:nil];
    _emptyActionButton.translatesAutoresizingMaskIntoConstraints = NO;
    _emptyActionButton.bezelStyle = NSBezelStylePush;
    _emptyActionButton.hidden = YES;
    [_emptyStateView addSubview:_emptyActionButton];

    [NSLayoutConstraint activateConstraints:@[
        [_emptySpinner.centerXAnchor constraintEqualToAnchor:_emptyStateView.centerXAnchor],
        [_emptySpinner.centerYAnchor constraintEqualToAnchor:_emptyStateView.centerYAnchor],
        [_emptyIconView.centerXAnchor constraintEqualToAnchor:_emptyStateView.centerXAnchor],
        [_emptyIconView.centerYAnchor constraintEqualToAnchor:_emptyStateView.centerYAnchor constant:-32.0],
        [_emptyIconView.widthAnchor constraintEqualToConstant:36.0],
        [_emptyIconView.heightAnchor constraintEqualToConstant:36.0],
        [_emptyTitleLabel.topAnchor constraintEqualToAnchor:_emptyIconView.bottomAnchor constant:MacLCDesign.spacingS],
        [_emptyTitleLabel.leadingAnchor constraintEqualToAnchor:_emptyStateView.leadingAnchor constant:MacLCDesign.spacingL],
        [_emptyTitleLabel.trailingAnchor constraintEqualToAnchor:_emptyStateView.trailingAnchor constant:-MacLCDesign.spacingL],
        [_emptyMessageLabel.topAnchor constraintEqualToAnchor:_emptyTitleLabel.bottomAnchor constant:MacLCDesign.spacingXS],
        [_emptyMessageLabel.leadingAnchor constraintEqualToAnchor:_emptyStateView.leadingAnchor constant:MacLCDesign.spacingL],
        [_emptyMessageLabel.trailingAnchor constraintEqualToAnchor:_emptyStateView.trailingAnchor constant:-MacLCDesign.spacingL],
        [_emptyActionButton.topAnchor constraintEqualToAnchor:_emptyMessageLabel.bottomAnchor constant:MacLCDesign.spacingM],
        [_emptyActionButton.centerXAnchor constraintEqualToAnchor:_emptyStateView.centerXAnchor],
    ]];

    // Bottom separator
    NSBox *bottomSep = [[NSBox alloc] initWithFrame:NSZeroRect];
    bottomSep.translatesAutoresizingMaskIntoConstraints = NO;
    bottomSep.boxType = NSBoxSeparator;
    [root addSubview:bottomSep];

    // Bottom actions
    _queueButton = [NSButton buttonWithTitle:_NS("Add to Queue") target:self action:@selector(queueSelectedStream:)];
    _queueButton.translatesAutoresizingMaskIntoConstraints = NO;
    _queueButton.bezelStyle = NSBezelStylePush;
    _queueButton.enabled = NO;
    _queueButton.accessibilityLabel = _NS("Add to Queue");
    _queueButton.toolTip = _NS("Add to Queue");
    [root addSubview:_queueButton];

    _playButton = [NSButton buttonWithTitle:_NS("Play") target:self action:@selector(playSelectedStream:)];
    _playButton.translatesAutoresizingMaskIntoConstraints = NO;
    _playButton.image = [NSImage imageWithSystemSymbolName:@"play.fill" accessibilityDescription:nil];
    _playButton.imagePosition = NSImageLeading;
    /* Same push style as Add to Queue; Return makes it the default (accent)
     * button. The popover is the glass: no glass inside it (liquid-glass.md). */
    _playButton.bezelStyle = NSBezelStylePush;
    _playButton.keyEquivalent = @"\r";
    _playButton.enabled = NO;
    _playButton.accessibilityLabel = _NS("Play");
    _playButton.toolTip = _NS("Play");
    [root addSubview:_playButton];

    [NSLayoutConstraint activateConstraints:@[
        [headerStack.topAnchor constraintEqualToAnchor:root.topAnchor constant:MacLCDesign.spacingM],
        [headerStack.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:MacLCDesign.spacingM],
        [headerStack.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-MacLCDesign.spacingM],
        [_headerTitleLabel.widthAnchor constraintLessThanOrEqualToAnchor:headerStack.widthAnchor],
        [_headerSubtitleLabel.widthAnchor constraintLessThanOrEqualToAnchor:headerStack.widthAnchor],

        [topSep.topAnchor constraintEqualToAnchor:headerStack.bottomAnchor constant:MacLCDesign.spacingS],
        [topSep.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [topSep.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],

        [_scrollView.topAnchor constraintEqualToAnchor:topSep.bottomAnchor],
        [_scrollView.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [_scrollView.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [_scrollView.bottomAnchor constraintEqualToAnchor:bottomSep.topAnchor],

        [_emptyStateView.topAnchor constraintEqualToAnchor:topSep.bottomAnchor],
        [_emptyStateView.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [_emptyStateView.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [_emptyStateView.bottomAnchor constraintEqualToAnchor:bottomSep.topAnchor],

        [bottomSep.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [bottomSep.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [bottomSep.bottomAnchor constraintEqualToAnchor:root.bottomAnchor constant:-50.0],

        [_queueButton.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:MacLCDesign.spacingM],
        [_queueButton.centerYAnchor constraintEqualToAnchor:root.bottomAnchor constant:-25.0],

        [_playButton.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-MacLCDesign.spacingM],
        [_playButton.centerYAnchor constraintEqualToAnchor:root.bottomAnchor constant:-25.0],
    ]];

    self.view = root;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    [self fetchStreams];
}

- (void)fetchStreams
{
    [_request cancel];
    _request = nil;
    [_streamGroups removeAllObjects];
    _displayItems = @[];
    _selectedStream = nil;
    _playButton.enabled = NO;
    _queueButton.enabled = NO;

    if (!MacLCAddonStore.sharedStore.hasStreamAddon) {
        [self showNoStreamAddonState];
        return;
    }

    _isPending = YES;
    [self updateDisplayItems];
    [self showLoadingState];

    NSString *type = _item.type ?: @"movie";
    NSString *videoID = _video ? _video.identifier : (_meta.defaultVideoIdentifier.length > 0 ? _meta.defaultVideoIdentifier : _item.identifier);

    __weak typeof(self) weakSelf = self;
    _request = [MacLCAddonStore.sharedStore fetchStreamsForType:type
                                                videoIdentifier:videoID
                                                      eachGroup:^(MacLCAddonStreamGroup * _Nonnull group) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf.streamGroups addObject:group];
        [strongSelf updateDisplayItems];
    } completion:^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.isPending = NO;
        strongSelf.request = nil;
        [strongSelf handleFetchCompletion];
    }];
}

- (void)updateDisplayItems
{
    NSMutableArray *items = [NSMutableArray array];
    NSUInteger totalStreams = 0;

    for (MacLCAddonStreamGroup *g in _streamGroups) {
        if (g.streams.count > 0) {
            [items addObject:g.addon.name ?: _NS("Add-on")];
            [items addObjectsFromArray:g.streams];
            totalStreams += g.streams.count;
        } else if (g.error) {
            [items addObject:[NSString stringWithFormat:@"%@ — %@", g.addon.name ?: _NS("Add-on"), _NS("Not Responding")]];
        }
    }

    if (_isPending) {
        [items addObject:[MacLCWatchSpinnerSentinel sharedSentinel]];
    }

    /* Rows shift when a slower add-on answers: keep the stream, not the row. */
    MacLCAddonStream * const keptStream = _selectedStream;
    _displayItems = [items copy];
    [_tableView reloadData];
    _selectedStream = keptStream;

    if (totalStreams > 0) {
        _emptyStateView.hidden = YES;
        _scrollView.hidden = NO;
    }

    if (_selectedStream == nil) {
        for (NSUInteger i = 0; i < _displayItems.count; i++) {
            if ([_displayItems[i] isKindOfClass:[MacLCAddonStream class]]) {
                _selectedStream = (MacLCAddonStream *)_displayItems[i];
                [_tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:i] byExtendingSelection:NO];
                [_tableView scrollRowToVisible:i];
                _playButton.enabled = YES;
                _queueButton.enabled = YES;
                break;
            }
        }
    } else {
        NSUInteger idx = [_displayItems indexOfObject:_selectedStream];
        if (idx != NSNotFound && _tableView.selectedRow != (NSInteger)idx) {
            [_tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:idx] byExtendingSelection:NO];
        }
    }

    [self updatePopoverHeight];
}

- (void)handleFetchCompletion
{
    [self updateDisplayItems];

    NSUInteger totalStreams = 0;
    NSUInteger failedGroups = 0;
    for (MacLCAddonStreamGroup *g in _streamGroups) {
        totalStreams += g.streams.count;
        if (g.error) {
            failedGroups++;
        }
    }

    if (totalStreams == 0) {
        _scrollView.hidden = YES;
        if (_streamGroups.count > 0 && failedGroups == _streamGroups.count) {
            NSError *firstError = _streamGroups.firstObject.error;
            NSString *serviceName = _streamGroups.firstObject.addon.name ?: _NS("Add-on");
            NSString *title = nil;
            NSString *message = nil;
            [self getErrorTitle:&title message:&message forError:firstError service:serviceName];
            [self showErrorStateWithTitle:title message:message buttonTitle:_NS("Try Again") target:self action:@selector(fetchStreams)];
        } else {
            [self showEmptyStateWithTitle:_NS("No Streams Found") message:_NS("No streams available for this title.")];
        }
    } else {
        _scrollView.hidden = NO;
        _emptyStateView.hidden = YES;
    }
    [self updatePopoverHeight];
}

- (void)showLoadingState
{
    _emptyStateView.hidden = NO;
    _scrollView.hidden = YES;
    _emptyIconView.hidden = YES;
    _emptyTitleLabel.hidden = YES;
    _emptyMessageLabel.hidden = YES;
    _emptyActionButton.hidden = YES;
    _emptySpinner.hidden = NO;
    [_emptySpinner startAnimation:nil];
    [self updatePopoverHeight];
}

- (void)showNoStreamAddonState
{
    _emptyStateView.hidden = NO;
    _scrollView.hidden = YES;
    [_emptySpinner stopAnimation:nil];
    _emptySpinner.hidden = YES;

    _emptyIconView.image = [NSImage imageWithSystemSymbolName:@"play.slash" accessibilityDescription:nil];
    _emptyIconView.contentTintColor = MacLCDesign.secondaryLabel;
    _emptyIconView.hidden = NO;

    _emptyTitleLabel.stringValue = _NS("No Streams Add-on");
    _emptyTitleLabel.hidden = NO;

    _emptyMessageLabel.stringValue = _NS("Install an add-on that provides streams to play titles.");
    _emptyMessageLabel.hidden = NO;

    _emptyActionButton.title = _NS("Browse Add-ons…");
    _emptyActionButton.target = self;
    _emptyActionButton.action = @selector(openAddonsSettings:);
    _emptyActionButton.hidden = NO;
    [self updatePopoverHeight];
}

- (void)showEmptyStateWithTitle:(NSString *)title message:(NSString *)message
{
    _emptyStateView.hidden = NO;
    _scrollView.hidden = YES;
    [_emptySpinner stopAnimation:nil];
    _emptySpinner.hidden = YES;

    _emptyIconView.image = [NSImage imageWithSystemSymbolName:@"magnifyingglass" accessibilityDescription:nil];
    _emptyIconView.contentTintColor = MacLCDesign.secondaryLabel;
    _emptyIconView.hidden = NO;

    _emptyTitleLabel.stringValue = title ?: @"";
    _emptyTitleLabel.hidden = NO;

    _emptyMessageLabel.stringValue = message ?: @"";
    _emptyMessageLabel.hidden = NO;

    _emptyActionButton.hidden = YES;
    [self updatePopoverHeight];
}

- (void)showErrorStateWithTitle:(NSString *)title
                        message:(NSString *)message
                    buttonTitle:(NSString *)buttonTitle
                          target:(id)target
                          action:(SEL)action
{
    _emptyStateView.hidden = NO;
    _scrollView.hidden = YES;
    [_emptySpinner stopAnimation:nil];
    _emptySpinner.hidden = YES;

    _emptyIconView.image = [NSImage imageWithSystemSymbolName:@"network.slash" accessibilityDescription:nil];
    _emptyIconView.contentTintColor = MacLCDesign.destructive;
    _emptyIconView.hidden = NO;

    _emptyTitleLabel.stringValue = title ?: @"";
    _emptyTitleLabel.hidden = NO;

    _emptyMessageLabel.stringValue = message ?: @"";
    _emptyMessageLabel.hidden = NO;

    _emptyActionButton.title = buttonTitle;
    _emptyActionButton.target = target;
    _emptyActionButton.action = action;
    _emptyActionButton.hidden = NO;
    [self updatePopoverHeight];
}

- (CGFloat)preferredPickerHeight
{
    CGFloat chrome = 94.0;
    if (_headerSubtitleLabel && !_headerSubtitleLabel.hidden) {
        chrome += 18.0;
    }

    if (_emptyStateView && !_emptyStateView.hidden && _displayItems.count == 0) {
        return 260.0;
    }

    CGFloat tableContentHeight = 0.0;
    for (NSInteger i = 0; i < (NSInteger)_displayItems.count; i++) {
        tableContentHeight += [self tableView:_tableView heightOfRow:i];
    }
    if (tableContentHeight <= 0.0) {
        return 220.0;
    }

    CGFloat total = chrome + tableContentHeight;
    if (total < 220.0) total = 220.0;
    if (total > 480.0) total = 480.0;
    return ceil(total);
}

- (void)updatePopoverHeight
{
    CGFloat h = [self preferredPickerHeight];
    if (_rootHeightConstraint) {
        _rootHeightConstraint.constant = h;
    }
    self.preferredContentSize = NSMakeSize(420.0, h);
    if (self.popover) {
        self.popover.contentSize = NSMakeSize(420.0, h);
    }
}

- (void)openAddonsSettings:(nullable id)sender
{
    [self.popover performClose:nil];
    MacLCSettingsWindowController *swc = VLCMain.sharedInstance.settingsWindowController;
    [swc showSettingsWindowWithLevel:NSNormalWindowLevel];
    [swc selectPaneWithIdentifier:@"addons"];
}

- (void)getErrorTitle:(NSString **)outTitle
              message:(NSString **)outMessage
             forError:(nullable NSError *)error
              service:(NSString *)serviceName
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
            long code = status ? status.longValue : 0;
            message = [NSString stringWithFormat:_NS("The service answered with error %ld. Try again in a moment."), code];
        } else if (error.code == MacLCAddonsErrorBadResponse ||
                   error.code == MacLCAddonsErrorNotAnAddon ||
                   error.code == MacLCAddonsErrorBadAddress) {
            title = [NSString stringWithFormat:_NS("Unexpected Answer from %@"), serviceName];
            message = _NS("If you changed the add-on address in Settings, check it.");
        }
    }

    if (!title) {
        title = [NSString stringWithFormat:_NS("Can't Reach %@"), serviceName];
        message = _NS("Check your internet connection, then try again.");
    }

    if (outTitle) *outTitle = title;
    if (outMessage) *outMessage = message;
}

#pragma mark - Table View Data Source & Delegate

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    return _displayItems.count;
}

- (BOOL)tableView:(NSTableView *)tableView isGroupRow:(NSInteger)row
{
    if (row >= 0 && row < (NSInteger)_displayItems.count) {
        return [_displayItems[row] isKindOfClass:[NSString class]];
    }
    return NO;
}

- (BOOL)tableView:(NSTableView *)tableView shouldSelectRow:(NSInteger)row
{
    if (row >= 0 && row < (NSInteger)_displayItems.count) {
        return [_displayItems[row] isKindOfClass:[MacLCAddonStream class]];
    }
    return NO;
}

- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row
{
    if (row >= 0 && row < (NSInteger)_displayItems.count) {
        id item = _displayItems[row];
        if ([item isKindOfClass:[NSString class]]) {
            return 28.0;
        } else if ([item isKindOfClass:[MacLCWatchSpinnerSentinel class]]) {
            return 32.0;
        } else if ([item isKindOfClass:[MacLCAddonStream class]]) {
            MacLCAddonStream *stream = (MacLCAddonStream *)item;
            const CGFloat textWidth = 420.0 - (MacLCDesign.spacingM * 2.0);

            NSDictionary *headAttrs = @{NSFontAttributeName: MacLCDesign.body};
            NSRect headRect = [stream.headline boundingRectWithSize:NSMakeSize(textWidth, CGFLOAT_MAX)
                                                            options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                                                         attributes:headAttrs];
            CGFloat headLineH = MacLCDesign.body.pointSize * 1.35;
            CGFloat headH = MIN(headRect.size.height, headLineH * 2.2);
            if (headH < headLineH) {
                headH = headLineH;
            }

            CGFloat detH = 0.0;
            if (stream.details.length > 0) {
                CGFloat detWidth = textWidth;
                if (stream.qualityTokens.count > 0) {
                    detWidth = MAX(120.0, textWidth - 80.0);
                }
                NSDictionary *detAttrs = @{NSFontAttributeName: MacLCDesign.subheadline};
                NSRect detRect = [stream.details boundingRectWithSize:NSMakeSize(detWidth, CGFLOAT_MAX)
                                                              options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                                                           attributes:detAttrs];
                CGFloat detLineH = MacLCDesign.subheadline.pointSize * 1.35;
                detH = MIN(detRect.size.height, detLineH * 2.2);
                if (detH < detLineH) {
                    detH = detLineH;
                }
            } else if (stream.qualityTokens.count > 0) {
                detH = 18.0;
            }

            CGFloat total = 8.0 + headH + 3.0 + detH + 8.0;
            if (total < 52.0) {
                total = 52.0;
            }
            return ceil(total);
        }
    }
    return 32.0;
}


- (nullable NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(nullable NSTableColumn *)tableColumn row:(NSInteger)row
{
    if (row < 0 || row >= (NSInteger)_displayItems.count) return nil;

    id item = _displayItems[row];
    if ([item isKindOfClass:[NSString class]]) {
        static NSString * const kGroupCellId = @"MacLCWatchStreamGroupCell";
        NSTableCellView *groupView = [tableView makeViewWithIdentifier:kGroupCellId owner:self];
        if (!groupView) {
            groupView = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, 200, 28)];
            groupView.identifier = kGroupCellId;
            NSTextField *label = [NSTextField labelWithString:@""];
            label.translatesAutoresizingMaskIntoConstraints = NO;
            label.font = MacLCDesign.headline;
            label.textColor = MacLCDesign.secondaryLabel;
            [groupView addSubview:label];
            groupView.textField = label;

            [NSLayoutConstraint activateConstraints:@[
                [label.leadingAnchor constraintEqualToAnchor:groupView.leadingAnchor constant:MacLCDesign.spacingM],
                [label.centerYAnchor constraintEqualToAnchor:groupView.centerYAnchor],
            ]];
        }
        groupView.textField.stringValue = (NSString *)item;
        return groupView;
    }

    if ([item isKindOfClass:[MacLCWatchSpinnerSentinel class]]) {
        static NSString * const kSpinnerCellId = @"MacLCWatchStreamSpinnerCell";
        NSTableCellView *spinnerCell = [tableView makeViewWithIdentifier:kSpinnerCellId owner:self];
        if (!spinnerCell) {
            spinnerCell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, 200, 32)];
            spinnerCell.identifier = kSpinnerCellId;

            NSProgressIndicator *spin = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
            spin.translatesAutoresizingMaskIntoConstraints = NO;
            spin.style = NSProgressIndicatorStyleSpinning;
            spin.controlSize = NSControlSizeSmall;
            [spin startAnimation:nil];
            [spinnerCell addSubview:spin];

            NSTextField *lbl = [NSTextField labelWithString:_NS("Searching for streams…")];
            lbl.translatesAutoresizingMaskIntoConstraints = NO;
            lbl.font = MacLCDesign.subheadline;
            lbl.textColor = MacLCDesign.secondaryLabel;
            [spinnerCell addSubview:lbl];

            [NSLayoutConstraint activateConstraints:@[
                [spin.leadingAnchor constraintEqualToAnchor:spinnerCell.leadingAnchor constant:MacLCDesign.spacingM],
                [spin.centerYAnchor constraintEqualToAnchor:spinnerCell.centerYAnchor],
                [lbl.leadingAnchor constraintEqualToAnchor:spin.trailingAnchor constant:MacLCDesign.spacingS],
                [lbl.centerYAnchor constraintEqualToAnchor:spinnerCell.centerYAnchor],
            ]];
        }
        return spinnerCell;
    }

    if ([item isKindOfClass:[MacLCAddonStream class]]) {
        static NSString * const kStreamCellId = @"MacLCWatchStreamCell";
        MacLCAddonStream *stream = (MacLCAddonStream *)item;
        MacLCWatchStreamCellView *cell = [tableView makeViewWithIdentifier:kStreamCellId owner:self];
        if (!cell) {
            cell = [[MacLCWatchStreamCellView alloc] initWithFrame:NSMakeRect(0, 0, 200, 52)];
            cell.identifier = kStreamCellId;
        }

        NSMutableArray<NSString *> *badgeTitles = [NSMutableArray array];
        for (NSString *tok in stream.qualityTokens) {
            NSString *trimmed = [tok stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (trimmed.length > 0) {
                if ([trimmed caseInsensitiveCompare:@"4k"] == NSOrderedSame) {
                    [badgeTitles addObject:@"4K"];
                } else if ([trimmed caseInsensitiveCompare:@"dv"] == NSOrderedSame) {
                    [badgeTitles addObject:@"Dolby Vision"];
                } else {
                    [badgeTitles addObject:trimmed];
                }
            }
        }
        [cell configureWithBadges:badgeTitles];

        cell.headlineLabel.stringValue = stream.headline ?: @"";
        cell.detailsLabel.stringValue = stream.details ?: @"";

        if (stream.details.length > 0) {
            cell.toolTip = [NSString stringWithFormat:@"%@\n%@", stream.headline, stream.details];
            cell.accessibilityLabel = [NSString stringWithFormat:@"%@, %@", stream.headline, stream.details];
        } else {
            cell.toolTip = stream.headline ?: @"";
            cell.accessibilityLabel = stream.headline ?: @"";
        }
        return cell;
    }

    return nil;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
    NSInteger row = _tableView.selectedRow;
    if (row >= 0 && row < (NSInteger)_displayItems.count) {
        id item = _displayItems[row];
        if ([item isKindOfClass:[MacLCAddonStream class]]) {
            _selectedStream = (MacLCAddonStream *)item;
            _playButton.enabled = YES;
            _queueButton.enabled = YES;
            return;
        }
    }
    _selectedStream = nil;
    _playButton.enabled = NO;
    _queueButton.enabled = NO;
}

- (void)tableDoubleClicked:(id)sender
{
    NSInteger row = _tableView.clickedRow;
    if (row >= 0 && row < (NSInteger)_displayItems.count) {
        id item = _displayItems[row];
        if ([item isKindOfClass:[MacLCAddonStream class]]) {
            [self playStream:(MacLCAddonStream *)item];
        }
    }
}

- (void)playSelectedStream:(id)sender
{
    if (_selectedStream) {
        [self playStream:_selectedStream];
    }
}

- (void)queueSelectedStream:(id)sender
{
    if (_selectedStream) {
        [self queueStream:_selectedStream];
    }
}

- (void)playStream:(MacLCAddonStream *)stream
{
    if (!stream) return;
    NSString *itemName = [MacLCAddonStore itemNameForItem:_item video:_video];
    VLCOpenInputMetadata *meta = [[VLCOpenInputMetadata alloc] init];
    meta.MRLString = stream.MRL;
    meta.itemName = itemName;
    [VLCMain.sharedInstance.playQueueController addPlayQueueItems:@[meta] atPosition:(size_t)-1 startPlayback:YES];
    [_popover performClose:nil];
}

- (void)queueStream:(MacLCAddonStream *)stream
{
    if (!stream) return;
    NSString *itemName = [MacLCAddonStore itemNameForItem:_item video:_video];
    VLCOpenInputMetadata *meta = [[VLCOpenInputMetadata alloc] init];
    meta.MRLString = stream.MRL;
    meta.itemName = itemName;
    [VLCMain.sharedInstance.playQueueController addPlayQueueItems:@[meta]];
    [_popover performClose:nil];
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

    NSPopover *_currentStreamPopover;
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
    NSTextField *_factsLabel;
    NSStackView *_descStack;
    NSTextField *_descLabel;
    NSButton *_moreButton;
    NSTextField *_detailsLabel;
    NSStackView *_buttonsStack;
    NSButton *_playButton;
    NSButton *_trailerButton;

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
    [_metaRequest cancel];
    [_pictureRequest cancel];
    [_logoRequest cancel];
    if (_currentStreamPopover) {
        [_currentStreamPopover performClose:nil];
    }
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

    _playButton = [NSButton buttonWithTitle:_NS("Play") target:self action:@selector(playButtonAction:)];
    _playButton.translatesAutoresizingMaskIntoConstraints = NO;
    _playButton.image = [NSImage imageWithSystemSymbolName:@"play.fill" accessibilityDescription:nil];
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

    _trailerButton = [NSButton buttonWithTitle:_NS("Trailer") target:self action:@selector(trailerButtonAction:)];
    _trailerButton.translatesAutoresizingMaskIntoConstraints = NO;
    _trailerButton.image = [NSImage imageWithSystemSymbolName:@"film" accessibilityDescription:nil];
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

    _buttonsStack = [NSStackView stackViewWithViews:@[_playButton, _trailerButton]];
    _buttonsStack.translatesAutoresizingMaskIntoConstraints = NO;
    _buttonsStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    _buttonsStack.spacing = 12.0;

    _headerLeadingStack = [NSStackView stackViewWithViews:@[_logoImageView, _titleLabel, _factsLabel, _descStack, _detailsLabel, _buttonsStack]];
    _headerLeadingStack.translatesAutoresizingMaskIntoConstraints = NO;
    _headerLeadingStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    _headerLeadingStack.alignment = NSLayoutAttributeLeading;
    _headerLeadingStack.spacing = 6.0;
    [_headerLeadingStack setCustomSpacing:12.0 afterView:_factsLabel];
    [_headerLeadingStack setCustomSpacing:12.0 afterView:_descStack];
    [_headerLeadingStack setCustomSpacing:16.0 afterView:_detailsLabel];
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

    _episodesCollectionView = [[NSCollectionView alloc] initWithFrame:NSZeroRect];
    _episodesCollectionView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _episodesCollectionView.collectionViewLayout = layout;
    _episodesCollectionView.dataSource = self;
    _episodesCollectionView.delegate = self;
    _episodesCollectionView.selectable = YES;
    _episodesCollectionView.backgroundColors = @[NSColor.clearColor];
    [_episodesCollectionView registerClass:[MacLCWatchEpisodeItem class] forItemWithIdentifier:MacLCWatchEpisodeItemIdentifier];

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

    // Description & More button
    [self updateDescriptionText];

    // Details line
    [self updateDetailsLine];

    // Play button
    [self updatePlayButton];

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

    // Description & More button
    [self updateDescriptionText];

    // Details line
    [self updateDetailsLine];

    // Play button
    [self updatePlayButton];

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

- (void)updatePlayButton
{
    if ([self isSeries]) {
        MacLCAddonVideo *firstEp = [self firstPlayableEpisode];
        if (firstEp && firstEp.season >= 1 && firstEp.episode >= 1) {
            _playButton.title = [NSString stringWithFormat:_NS("Play S%ld, E%ld"), (long)firstEp.season, (long)firstEp.episode];
        } else {
            _playButton.title = _NS("Play S1, E1");
        }
    } else {
        _playButton.title = _NS("Play");
    }
    _playButton.accessibilityLabel = _playButton.title;
    _playButton.toolTip = _playButton.title;
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
        [item configureWithVideo:video];

        __weak typeof(self) weakSelf = self;
        __weak typeof(item) weakItem = item;
        item.activationHandler = ^(MacLCAddonVideo *v) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            __strong typeof(weakItem) strongItem = weakItem;
            if (strongSelf && strongItem) {
                [strongSelf showStreamPickerForVideo:v anchoredToView:strongItem.view];
            }
        };
    }
    return item;
}

#pragma mark - User Actions

- (void)playButtonAction:(id)sender
{
    MacLCAddonVideo *video = nil;
    if ([self isSeries]) {
        video = [self firstPlayableEpisode];
    }
    [self showStreamPickerForVideo:video anchoredToView:_playButton];
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

- (void)showStreamPickerForVideo:(nullable MacLCAddonVideo *)video anchoredToView:(NSView *)anchorView
{
    if (_currentStreamPopover) {
        [_currentStreamPopover performClose:nil];
        _currentStreamPopover = nil;
    }

    MacLCWatchStreamPickerViewController *pickerVC = [[MacLCWatchStreamPickerViewController alloc] initWithItem:_item
                                                                                                           video:video
                                                                                                            meta:_meta];
    NSPopover *popover = [[NSPopover alloc] init];
    popover.behavior = NSPopoverBehaviorTransient;
    popover.contentSize = NSMakeSize(420.0, [pickerVC preferredPickerHeight]);
    popover.contentViewController = pickerVC;
    pickerVC.popover = popover;
    _currentStreamPopover = popover;

    [popover showRelativeToRect:anchorView.bounds ofView:anchorView preferredEdge:NSRectEdgeMaxY];
}

@end
