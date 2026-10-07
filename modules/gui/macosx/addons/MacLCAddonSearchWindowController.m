/*****************************************************************************
 * MacLCAddonSearchWindowController.m: search titles and play streams through
 * the installed add-ons
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

#import "MacLCAddonSearchWindowController.h"
#import "MacLCAddons.h"

#import "theme/MacLCDesign.h"
#import "theme/MacLCFormatBadgeView.h"
#import "main/VLCMain.h"
#import "settings/MacLCSettingsWindowController.h"
#import "playqueue/VLCPlayQueueController.h"
#import "windows/VLCOpenInputMetadata.h"
#import "extensions/NSString+Helpers.h"

static NSString * const MacLCAddonSearchToolbarIdentifier = @"MacLCAddonSearchToolbar";
static NSToolbarItemIdentifier const MacLCAddonSearchSearchToolbarItemIdentifier = @"MacLCAddonSearchSearchToolbarItemIdentifier";

static NSString * const kResultCellIdentifier = @"MacLCAddonSearchResultCell";
static NSString * const kGroupCellIdentifier = @"MacLCAddonSearchGroupCell";
static NSString * const kEpisodeCellIdentifier = @"MacLCAddonSearchEpisodeCell";
static NSString * const kStreamCellIdentifier = @"MacLCAddonSearchStreamCell";

static NSString *TypeNameForGroupType(NSString *type)
{
    if ([type isEqualToString:@"movie"]) {
        return _NS("Movies");
    } else if ([type isEqualToString:@"series"]) {
        return _NS("Series");
    } else if ([type isEqualToString:@"channel"]) {
        return _NS("Channels");
    } else if ([type isEqualToString:@"tv"]) {
        return _NS("TV");
    } else if (type.length > 0) {
        NSString *firstChar = [[type substringToIndex:1] uppercaseString];
        NSString *rest = [type substringFromIndex:1];
        return [firstChar stringByAppendingString:rest];
    }
    return @"";
}

static NSString *SingularNameForType(NSString *type)
{
    if ([type isEqualToString:@"movie"]) {
        return _NS("Movie");
    } else if ([type isEqualToString:@"series"]) {
        return _NS("Series");
    } else if ([type isEqualToString:@"channel"]) {
        return _NS("Channel");
    } else if ([type isEqualToString:@"tv"]) {
        return _NS("TV");
    } else if (type.length > 0) {
        NSString *firstChar = [[type substringToIndex:1] uppercaseString];
        NSString *rest = [type substringFromIndex:1];
        return [firstChar stringByAppendingString:rest];
    }
    return @"";
}

#pragma mark - State View Helper

@interface MacLCAddonSearchStateView : NSView

@property (nonatomic, strong) NSStackView *contentStack;
@property (nonatomic, strong) NSProgressIndicator *spinner;
@property (nonatomic, strong) NSImageView *iconView;
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSTextField *messageLabel;
@property (nonatomic, strong) NSButton *actionButton;

- (void)showIdle;
- (void)showLoading;
- (void)showEmptyWithTitle:(NSString *)title message:(NSString *)message;
- (void)showEmptyWithIcon:(nullable NSImage *)icon title:(NSString *)title message:(NSString *)message;
- (void)showErrorWithTitle:(NSString *)title
                   message:(NSString *)message
               buttonTitle:(nullable NSString *)btnTitle
                    target:(nullable id)target
                    action:(nullable SEL)action;

@end

@implementation MacLCAddonSearchStateView

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;

        _contentStack = [[NSStackView alloc] initWithFrame:NSZeroRect];
        _contentStack.translatesAutoresizingMaskIntoConstraints = NO;
        _contentStack.orientation = NSUserInterfaceLayoutOrientationVertical;
        _contentStack.alignment = NSLayoutAttributeCenterX;
        _contentStack.spacing = MacLCDesign.spacingS;
        [self addSubview:_contentStack];

        _spinner = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
        _spinner.translatesAutoresizingMaskIntoConstraints = NO;
        _spinner.style = NSProgressIndicatorStyleSpinning;
        _spinner.controlSize = NSControlSizeSmall;
        _spinner.displayedWhenStopped = NO;
        [_contentStack addArrangedSubview:_spinner];

        _iconView = [[NSImageView alloc] initWithFrame:NSZeroRect];
        _iconView.translatesAutoresizingMaskIntoConstraints = NO;
        _iconView.imageScaling = NSImageScaleProportionallyUpOrDown;
        _iconView.accessibilityElement = NO;
        [_contentStack addArrangedSubview:_iconView];
        [_contentStack setCustomSpacing:MacLCDesign.spacingM afterView:_iconView];

        _titleLabel = [NSTextField labelWithString:@""];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _titleLabel.alignment = NSTextAlignmentCenter;
        _titleLabel.font = MacLCDesign.headline;
        _titleLabel.textColor = MacLCDesign.primaryLabel;
        _titleLabel.maximumNumberOfLines = 2;
        _titleLabel.lineBreakMode = NSLineBreakByWordWrapping;
        [_contentStack addArrangedSubview:_titleLabel];
        [_contentStack setCustomSpacing:MacLCDesign.spacingXS afterView:_titleLabel];

        _messageLabel = [NSTextField labelWithString:@""];
        _messageLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _messageLabel.alignment = NSTextAlignmentCenter;
        _messageLabel.font = MacLCDesign.subheadline;
        _messageLabel.textColor = MacLCDesign.secondaryLabel;
        _messageLabel.maximumNumberOfLines = 3;
        _messageLabel.lineBreakMode = NSLineBreakByWordWrapping;
        [_contentStack addArrangedSubview:_messageLabel];

        _actionButton = [NSButton buttonWithTitle:_NS("Try Again") target:nil action:nil];
        _actionButton.translatesAutoresizingMaskIntoConstraints = NO;
        _actionButton.bezelStyle = NSBezelStylePush;
        [_contentStack addArrangedSubview:_actionButton];
        [_contentStack setCustomSpacing:MacLCDesign.spacingM afterView:_messageLabel];

        [NSLayoutConstraint activateConstraints:@[
            [_contentStack.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [_contentStack.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_contentStack.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.leadingAnchor constant:MacLCDesign.spacingL],
            [_contentStack.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-MacLCDesign.spacingL],
        ]];

        [self showIdle];
    }
    return self;
}

- (void)showIdle
{
    self.hidden = YES;
    [_spinner stopAnimation:nil];
    _spinner.hidden = YES;
    _iconView.hidden = YES;
    _titleLabel.hidden = YES;
    _messageLabel.hidden = YES;
    _actionButton.hidden = YES;
}

- (void)showLoading
{
    self.hidden = NO;
    _iconView.hidden = YES;
    _titleLabel.hidden = YES;
    _messageLabel.hidden = YES;
    _actionButton.hidden = YES;
    _spinner.hidden = NO;
    [_spinner startAnimation:nil];
}

- (void)showEmptyWithTitle:(NSString *)title message:(NSString *)message
{
    [self showEmptyWithIcon:nil title:title message:message];
}

- (void)showEmptyWithIcon:(nullable NSImage *)icon title:(NSString *)title message:(NSString *)message
{
    self.hidden = NO;
    [_spinner stopAnimation:nil];
    _spinner.hidden = YES;
    _actionButton.hidden = YES;

    if (icon) {
        _iconView.image = icon;
        _iconView.hidden = NO;
    } else {
        _iconView.hidden = YES;
    }

    _titleLabel.stringValue = title ?: @"";
    _titleLabel.hidden = (title.length == 0);

    _messageLabel.stringValue = message ?: @"";
    _messageLabel.hidden = (message.length == 0);
}

- (void)showErrorWithTitle:(NSString *)title
                   message:(NSString *)message
               buttonTitle:(nullable NSString *)btnTitle
                    target:(nullable id)target
                    action:(nullable SEL)action
{
    self.hidden = NO;
    [_spinner stopAnimation:nil];
    _spinner.hidden = YES;
    _iconView.hidden = YES;

    _titleLabel.stringValue = title ?: @"";
    _titleLabel.hidden = NO;

    _messageLabel.stringValue = message ?: @"";
    _messageLabel.hidden = NO;

    if (btnTitle.length > 0 && target && action) {
        _actionButton.title = btnTitle;
        _actionButton.target = target;
        _actionButton.action = action;
        _actionButton.hidden = NO;
    } else {
        _actionButton.hidden = YES;
    }
}

@end

#pragma mark - Poster View

/* A poster sits on a fill until its image arrives. A layer colour is resolved
 * once, for one appearance: resolve it again whenever the appearance changes. */
@interface MacLCAddonSearchPosterView : NSImageView
@end

@implementation MacLCAddonSearchPosterView

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.wantsLayer = YES;
        self.layer.masksToBounds = YES;
        self.imageScaling = NSImageScaleProportionallyUpOrDown;
        self.accessibilityElement = NO;
    }
    return self;
}

- (void)viewDidChangeEffectiveAppearance
{
    [super viewDidChangeEffectiveAppearance];
    [self.effectiveAppearance performAsCurrentDrawingAppearance:^{
        self.layer.backgroundColor = MacLCDesign.controlBackground.CGColor;
    }];
}

- (void)viewDidMoveToWindow
{
    [super viewDidMoveToWindow];
    [self viewDidChangeEffectiveAppearance];
}

@end

#pragma mark - Custom Table Cell Views

@interface MacLCAddonSearchResultCellView : NSTableCellView

@property (nonatomic, strong) MacLCAddonSearchPosterView *posterImageView;
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSTextField *subtitleLabel;

@end

@implementation MacLCAddonSearchResultCellView

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        _posterImageView = [[MacLCAddonSearchPosterView alloc] initWithFrame:NSZeroRect];
        _posterImageView.layer.cornerRadius = 3.0;
        [self addSubview:_posterImageView];

        _titleLabel = [NSTextField labelWithString:@""];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _titleLabel.font = MacLCDesign.body;
        _titleLabel.textColor = MacLCDesign.primaryLabel;
        _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self addSubview:_titleLabel];

        _subtitleLabel = [NSTextField labelWithString:@""];
        _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _subtitleLabel.font = MacLCDesign.subheadline;
        _subtitleLabel.textColor = MacLCDesign.secondaryLabel;
        _subtitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self addSubview:_subtitleLabel];

        [NSLayoutConstraint activateConstraints:@[
            [_posterImageView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:MacLCDesign.spacingS],
            [_posterImageView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_posterImageView.widthAnchor constraintEqualToConstant:28.0],
            [_posterImageView.heightAnchor constraintEqualToConstant:42.0],

            [_titleLabel.leadingAnchor constraintEqualToAnchor:_posterImageView.trailingAnchor constant:MacLCDesign.spacingS],
            [_titleLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-MacLCDesign.spacingS],
            [_titleLabel.bottomAnchor constraintEqualToAnchor:self.centerYAnchor constant:1.0],

            [_subtitleLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
            [_subtitleLabel.trailingAnchor constraintEqualToAnchor:_titleLabel.trailingAnchor],
            [_subtitleLabel.topAnchor constraintEqualToAnchor:self.centerYAnchor constant:2.0],
        ]];
    }
    return self;
}

@end

@interface MacLCAddonSearchEpisodeCellView : NSTableCellView

@property (nonatomic, strong) NSTextField *numberLabel;
@property (nonatomic, strong) NSTextField *nameLabel;
@property (nonatomic, strong) NSTextField *dateLabel;
@property (nonatomic, strong) NSLayoutConstraint *numberWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *nameLeadingConstraint;

@end

@implementation MacLCAddonSearchEpisodeCellView

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        _numberLabel = [NSTextField labelWithString:@""];
        _numberLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _numberLabel.font = MacLCDesign.monospacedDigitBody;
        _numberLabel.textColor = MacLCDesign.secondaryLabel;
        _numberLabel.alignment = NSTextAlignmentRight; /* 9 and 10 end on the same column */
        [_numberLabel setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
        [self addSubview:_numberLabel];

        _nameLabel = [NSTextField labelWithString:@""];
        _nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _nameLabel.font = MacLCDesign.body;
        _nameLabel.textColor = MacLCDesign.primaryLabel;
        _nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [_nameLabel setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
        [self addSubview:_nameLabel];

        _dateLabel = [NSTextField labelWithString:@""];
        _dateLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _dateLabel.font = MacLCDesign.subheadline;
        _dateLabel.textColor = MacLCDesign.secondaryLabel;
        [_dateLabel setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
        [self addSubview:_dateLabel];

        _numberWidthConstraint = [_numberLabel.widthAnchor constraintGreaterThanOrEqualToConstant:20.0];
        _nameLeadingConstraint = [_nameLabel.leadingAnchor constraintEqualToAnchor:_numberLabel.trailingAnchor constant:MacLCDesign.spacingS];

        [NSLayoutConstraint activateConstraints:@[
            [_numberLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:MacLCDesign.spacingS],
            [_numberLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            _numberWidthConstraint,

            _nameLeadingConstraint,
            [_nameLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_nameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_dateLabel.leadingAnchor constant:-MacLCDesign.spacingS],

            [_dateLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-MacLCDesign.spacingS],
            [_dateLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        ]];
    }
    return self;
}

@end

@interface MacLCAddonSearchStreamCellView : NSTableCellView

@property (nonatomic, strong) NSStackView *outerStackView;
@property (nonatomic, strong) NSStackView *badgesStackView;
@property (nonatomic, strong) NSTextField *primaryLabel;
@property (nonatomic, strong) NSTextField *secondaryLabel;

@end

@implementation MacLCAddonSearchStreamCellView

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        /* Headline on top, quality badges then details below it:
         * the names line up whatever the badges, which keeps the list easy to
         * scan. */
        _primaryLabel = [NSTextField labelWithString:@""];
        _primaryLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _primaryLabel.font = MacLCDesign.body;
        _primaryLabel.textColor = MacLCDesign.primaryLabel;
        _primaryLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
        [_primaryLabel setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];

        _badgesStackView = [[NSStackView alloc] initWithFrame:NSZeroRect];
        _badgesStackView.translatesAutoresizingMaskIntoConstraints = NO;
        _badgesStackView.orientation = NSUserInterfaceLayoutOrientationHorizontal;
        _badgesStackView.alignment = NSLayoutAttributeCenterY;
        _badgesStackView.spacing = MacLCDesign.spacingXS;
        [_badgesStackView setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];

        _secondaryLabel = [NSTextField labelWithString:@""];
        _secondaryLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _secondaryLabel.font = MacLCDesign.subheadline;
        _secondaryLabel.textColor = MacLCDesign.secondaryLabel;
        _secondaryLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [_secondaryLabel setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];

        NSStackView *detailRow = [NSStackView stackViewWithViews:@[_badgesStackView, _secondaryLabel]];
        detailRow.translatesAutoresizingMaskIntoConstraints = NO;
        detailRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
        detailRow.alignment = NSLayoutAttributeCenterY;
        detailRow.spacing = MacLCDesign.spacingS;

        NSStackView *textStack = [NSStackView stackViewWithViews:@[_primaryLabel, detailRow]];
        textStack.translatesAutoresizingMaskIntoConstraints = NO;
        textStack.orientation = NSUserInterfaceLayoutOrientationVertical;
        textStack.alignment = NSLayoutAttributeLeading;
        textStack.spacing = 3.0;
        [self addSubview:textStack];

        [NSLayoutConstraint activateConstraints:@[
            [textStack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:MacLCDesign.spacingM],
            [textStack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-MacLCDesign.spacingM],
            [textStack.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_primaryLabel.widthAnchor constraintLessThanOrEqualToAnchor:textStack.widthAnchor],
            [detailRow.widthAnchor constraintLessThanOrEqualToAnchor:textStack.widthAnchor],
        ]];
    }
    return self;
}

- (void)configureWithBadges:(NSArray<NSString *> *)badgeTitles
{
    for (NSView *v in [_badgesStackView.arrangedSubviews copy]) {
        [_badgesStackView removeView:v];
        [v removeFromSuperview];
    }

    for (NSString *title in badgeTitles) {
        /* The filled style: primary label text, legible on a selected row too. */
        MacLCFormatBadgeView *badge = [MacLCFormatBadgeView badgeWithTitle:title active:YES];
        [_badgesStackView addArrangedSubview:badge];
    }
    _badgesStackView.hidden = (badgeTitles.count == 0);
}

@end

#pragma mark - Window Controller

@interface MacLCAddonSearchWindowController () <NSToolbarDelegate, NSSearchFieldDelegate, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate, NSMenuItemValidation, NSMenuDelegate>

// Root split view and child controllers
@property (nonatomic, strong) NSSplitViewController *splitViewController;
@property (nonatomic, strong) NSViewController *listViewController;
@property (nonatomic, strong) NSViewController *detailViewController;

// Toolbar item
@property (nonatomic, strong) NSSearchToolbarItem *searchToolbarItem;

// Results Pane UI
@property (nonatomic, strong) NSScrollView *resultsScrollView;
@property (nonatomic, strong) NSTableView *resultsTableView;
@property (nonatomic, strong) MacLCAddonSearchStateView *resultsStateView;

// Detail Pane UI
@property (nonatomic, strong) NSView *detailContainerView;
@property (nonatomic, strong) MacLCAddonSearchStateView *detailEmptyStateView;
@property (nonatomic, strong) NSView *detailContentView;

// Detail Header
@property (nonatomic, strong) NSView *headerView;
@property (nonatomic, strong) MacLCAddonSearchPosterView *detailHeaderPosterView;
@property (nonatomic, strong) NSTextField *detailNameLabel;
@property (nonatomic, strong) NSTextField *detailMetaLabel;
@property (nonatomic, strong) NSButton *playButton;
@property (nonatomic, strong) NSButton *addToQueueButton;
@property (nonatomic, strong) NSTextField *statusLabel;

// Series & Streams Split View
@property (nonatomic, strong) NSView *detailBodyView;
@property (nonatomic, strong) NSBox *episodesSeparator;
@property (nonatomic, strong) NSLayoutConstraint *episodesShownHeight;
@property (nonatomic, strong) NSLayoutConstraint *episodesHiddenHeight;

// Episodes Section
@property (nonatomic, strong) NSView *episodesContainerView;
@property (nonatomic, strong) NSPopUpButton *seasonPopUpButton;
@property (nonatomic, strong) NSScrollView *episodesScrollView;
@property (nonatomic, strong) NSTableView *episodesTableView;
@property (nonatomic, strong) MacLCAddonSearchStateView *episodesStateView;
@property (nonatomic, strong) NSLayoutConstraint *seasonPopUpTopConstraint;
@property (nonatomic, strong) NSLayoutConstraint *noSeasonPopUpTopConstraint;
@property (nonatomic, strong) NSLayoutConstraint *episodesStateViewSeasonTopConstraint;
@property (nonatomic, strong) NSLayoutConstraint *episodesStateViewNoSeasonTopConstraint;

// Streams Section
@property (nonatomic, strong) NSView *streamsContainerView;
@property (nonatomic, strong) NSTextField *streamsSectionLabel;
@property (nonatomic, strong) NSScrollView *streamsScrollView;
@property (nonatomic, strong) NSTableView *streamsTableView;
@property (nonatomic, strong) MacLCAddonSearchStateView *streamsStateView;

// Data state
@property (nonatomic, copy) NSArray<id> *resultsDisplayItems; // NSString for headers, MacLCAddonItem for rows
@property (nonatomic, strong, nullable) MacLCAddonItem *selectedItem;

@property (nonatomic, copy) NSArray<MacLCAddonVideo *> *allVideos;
@property (nonatomic, copy) NSArray<NSNumber *> *availableSeasons;
@property (nonatomic, copy) NSArray<MacLCAddonVideo *> *currentSeasonVideos;
@property (nonatomic, strong, nullable) MacLCAddonVideo *selectedVideo;

@property (nonatomic, strong) NSMutableArray<MacLCAddonStreamGroup *> *streamGroups;
@property (nonatomic, copy) NSArray<id> *streamDisplayItems; // NSString for headers, MacLCAddonStream for rows
@property (nonatomic, strong, nullable) MacLCAddonStream *selectedStream;

// Tasks & Generations
@property (nonatomic) NSUInteger searchGeneration;
@property (nonatomic, strong, nullable) MacLCAddonRequest *searchRequest;
@property (nonatomic, copy, nullable) NSString *currentSearchQuery;

@property (nonatomic) NSUInteger metaGeneration;
@property (nonatomic, strong, nullable) MacLCAddonRequest *metaRequest;

@property (nonatomic) NSUInteger streamsGeneration;
@property (nonatomic, strong, nullable) MacLCAddonRequest *streamsRequest;
@property (nonatomic, copy, nullable) NSString *streamsType;
@property (nonatomic, copy, nullable) NSString *streamsVideoIdentifier;

// Poster cache & tasks
@property (nonatomic, strong) NSCache<NSString *, NSImage *> *posterCache;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSURLSessionDataTask *> *posterTasks;

// Autoplay developer hook
@property (nonatomic, copy, nullable) NSString *autoplayType;
@property (nonatomic) BOOL autoplayPending;
@property (nonatomic) BOOL autoplayPlays;

@end

@implementation MacLCAddonSearchWindowController

#pragma mark - Shared Instance

+ (MacLCAddonSearchWindowController *)sharedController
{
    static MacLCAddonSearchWindowController *s_controller = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        s_controller = [[self alloc] init];
    });
    return s_controller;
}

#pragma mark - Initialization & Teardown

- (instancetype)init
{
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 940, 600)
                                                   styleMask:NSWindowStyleMaskTitled |
                                                             NSWindowStyleMaskClosable |
                                                             NSWindowStyleMaskMiniaturizable |
                                                             NSWindowStyleMaskResizable |
                                                             NSWindowStyleMaskFullSizeContentView
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];

    self = [super initWithWindow:window];
    if (self) {
        _posterCache = [[NSCache alloc] init];
        _posterCache.countLimit = 150;
        _posterTasks = [NSMutableDictionary dictionary];

        _resultsDisplayItems = @[];
        _allVideos = @[];
        _availableSeasons = @[];
        _currentSeasonVideos = @[];
        _streamGroups = [NSMutableArray array];
        _streamDisplayItems = @[];

        [self setupWindowAndViews];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(addonsDidChange:)
                                                     name:MacLCAddonsDidChangeNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self cancelAllTasks];
}

- (void)windowWillClose:(NSNotification *)notification
{
    [self cancelAllTasks];
}

- (void)addonsDidChange:(NSNotification *)notification
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!MacLCAddonStore.sharedStore.hasStreamAddon && self.window.isVisible) {
            [self.window close];
        }
    });
}

- (void)cancelAllTasks
{
    [_searchRequest cancel];
    _searchRequest = nil;

    [_metaRequest cancel];
    _metaRequest = nil;

    [_streamsRequest cancel];
    _streamsRequest = nil;

    for (NSURLSessionDataTask *task in _posterTasks.allValues) {
        [task cancel];
    }
    [_posterTasks removeAllObjects];

    /* An answer may already wait on the main queue: make it stale. */
    _searchGeneration++;
    _metaGeneration++;
    _streamsGeneration++;
    _autoplayPending = NO;
    _autoplayType = nil;
}

/* What a previous title still has in flight must not land in the next one. */
- (void)cancelDetailRequests
{
    [_metaRequest cancel];
    _metaRequest = nil;
    _metaGeneration++;

    [_streamsRequest cancel];
    _streamsRequest = nil;
    _streamsGeneration++;

    _allVideos = @[];
    _availableSeasons = @[];
    _currentSeasonVideos = @[];
    _selectedVideo = nil;
    _streamGroups = [NSMutableArray array];
    _streamDisplayItems = @[];
    _selectedStream = nil;
    [_episodesTableView reloadData];
    [_streamsTableView reloadData];
    [_episodesStateView showIdle];
    [_streamsStateView showIdle];
    [self updateButtons];
}

#pragma mark - Date Formatter

+ (NSDateFormatter *)episodeDateFormatter
{
    static NSDateFormatter *formatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.dateStyle = NSDateFormatterMediumStyle;
        formatter.timeStyle = NSDateFormatterNoStyle;
    });
    return formatter;
}

#pragma mark - Window and Views Setup

- (void)setupWindowAndViews
{
    NSWindow *window = self.window;
    window.delegate = self;
    window.releasedWhenClosed = NO;
    window.title = _NS("Search Add-ons");
    window.subtitle = @"";
    window.titleVisibility = NSWindowTitleVisible;
    window.toolbarStyle = NSWindowToolbarStyleUnified;
    window.minSize = NSMakeSize(760, 480);
    [window setContentSize:NSMakeSize(940, 600)];
    [window center];
    [window setFrameAutosaveName:@"MacLCAddonSearch"];

    [self setupToolbar];

    // Build Results Pane
    _listViewController = [[NSViewController alloc] init];
    NSView *resultsContainer = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 280, 600)];
    _listViewController.view = resultsContainer;
    [self setupResultsPaneInContainer:resultsContainer];

    // Build Detail Pane
    _detailViewController = [[NSViewController alloc] init];
    _detailContainerView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 660, 600)];
    _detailViewController.view = _detailContainerView;
    [self setupDetailPaneInContainer:_detailContainerView];

    // Build Split View Controller
    _splitViewController = [[NSSplitViewController alloc] init];
    _splitViewController.splitView.dividerStyle = NSSplitViewDividerStyleThin;
    _splitViewController.splitView.autosaveName = @"MacLCAddonSearchSplit";

    NSSplitViewItem *listItem = [NSSplitViewItem contentListWithViewController:_listViewController];
    listItem.minimumThickness = 240.0;
    listItem.maximumThickness = 380.0;
    listItem.canCollapse = NO;
    [_splitViewController addSplitViewItem:listItem];

    NSSplitViewItem *detailItem = [NSSplitViewItem splitViewItemWithViewController:_detailViewController];
    detailItem.minimumThickness = 480.0;
    detailItem.canCollapse = NO;
    [_splitViewController addSplitViewItem:detailItem];

    window.contentViewController = _splitViewController;

    // Set default list width
    NSLayoutConstraint *defaultWidthConstraint = [_listViewController.view.widthAnchor constraintEqualToConstant:280.0];
    defaultWidthConstraint.priority = NSLayoutPriorityDefaultLow;
    defaultWidthConstraint.active = YES;

    [self setupKeyViewLoop];
}

- (void)setupToolbar
{
    NSToolbar *toolbar = [[NSToolbar alloc] initWithIdentifier:MacLCAddonSearchToolbarIdentifier];
    toolbar.allowsUserCustomization = NO;
    toolbar.displayMode = NSToolbarDisplayModeIconOnly;
    toolbar.delegate = self;

    _searchToolbarItem = [[NSSearchToolbarItem alloc] initWithItemIdentifier:MacLCAddonSearchSearchToolbarItemIdentifier];
    _searchToolbarItem.searchField.placeholderString = _NS("Movies, Series and More");
    _searchToolbarItem.searchField.sendsWholeSearchString = NO;
    _searchToolbarItem.searchField.sendsSearchStringImmediately = NO;
    _searchToolbarItem.searchField.target = self;
    _searchToolbarItem.searchField.action = @selector(searchFieldAction:);
    _searchToolbarItem.searchField.delegate = self;
    _searchToolbarItem.resignsFirstResponderWithCancel = YES;
    _searchToolbarItem.preferredWidthForSearchField = 260.0;

    self.window.toolbar = toolbar;
}

- (void)setupResultsPaneInContainer:(NSView *)container
{
    _resultsTableView = [[NSTableView alloc] initWithFrame:NSZeroRect];
    _resultsTableView.style = NSTableViewStyleAutomatic;
    _resultsTableView.headerView = nil;
    _resultsTableView.dataSource = self;
    _resultsTableView.delegate = self;
    _resultsTableView.accessibilityLabel = _NS("Search Results");
    _resultsTableView.allowsEmptySelection = YES;
    _resultsTableView.allowsMultipleSelection = NO;
    _resultsTableView.columnAutoresizingStyle = NSTableViewUniformColumnAutoresizingStyle;

    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"ResultColumn"];
    col.resizingMask = NSTableColumnAutoresizingMask;
    [_resultsTableView addTableColumn:col];

    _resultsScrollView = [[NSScrollView alloc] init];
    _resultsScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _resultsScrollView.documentView = _resultsTableView;
    _resultsScrollView.hasVerticalScroller = YES;
    _resultsScrollView.autohidesScrollers = YES;
    _resultsScrollView.drawsBackground = NO;
    _resultsScrollView.automaticallyAdjustsContentInsets = YES;
    [container addSubview:_resultsScrollView];

    _resultsStateView = [[MacLCAddonSearchStateView alloc] initWithFrame:NSZeroRect];
    [container addSubview:_resultsStateView];

    [NSLayoutConstraint activateConstraints:@[
        [_resultsScrollView.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [_resultsScrollView.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [_resultsScrollView.topAnchor constraintEqualToAnchor:container.topAnchor],
        [_resultsScrollView.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],

        [_resultsStateView.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [_resultsStateView.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [_resultsStateView.topAnchor constraintEqualToAnchor:container.topAnchor],
        [_resultsStateView.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
    ]];
}

- (void)setupDetailPaneInContainer:(NSView *)container
{
    // Empty state view
    _detailEmptyStateView = [[MacLCAddonSearchStateView alloc] initWithFrame:NSZeroRect];
    _detailEmptyStateView.titleLabel.font = MacLCDesign.title3;
    NSImage *emptyIcon = [MacLCDesign symbolNamed:@"play.rectangle.on.rectangle" pointSize:40.0 weight:NSFontWeightRegular accessibilityLabel:nil];
    _detailEmptyStateView.iconView.contentTintColor = MacLCDesign.secondaryLabel;
    [_detailEmptyStateView showEmptyWithIcon:emptyIcon
                                       title:_NS("Search for Movies, Series and More")
                                     message:_NS("Search for a title, then choose it to see its streams.")];
    [container addSubview:_detailEmptyStateView];

    // Detail content view
    _detailContentView = [[NSView alloc] initWithFrame:NSZeroRect];
    _detailContentView.translatesAutoresizingMaskIntoConstraints = NO;
    _detailContentView.hidden = YES;
    [container addSubview:_detailContentView];

    [NSLayoutConstraint activateConstraints:@[
        [_detailEmptyStateView.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [_detailEmptyStateView.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [_detailEmptyStateView.topAnchor constraintEqualToAnchor:container.topAnchor],
        [_detailEmptyStateView.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],

        [_detailContentView.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [_detailContentView.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [_detailContentView.topAnchor constraintEqualToAnchor:container.topAnchor],
        [_detailContentView.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
    ]];

    [self setupDetailHeader];
    [self setupSeriesAndStreamsSplitView];
}

- (void)setupDetailHeader
{
    _headerView = [[NSView alloc] initWithFrame:NSZeroRect];
    _headerView.translatesAutoresizingMaskIntoConstraints = NO;
    [_detailContentView addSubview:_headerView];

    _detailHeaderPosterView = [[MacLCAddonSearchPosterView alloc] initWithFrame:NSZeroRect];
    _detailHeaderPosterView.layer.cornerRadius = 6.0;
    [_headerView addSubview:_detailHeaderPosterView];

    NSStackView *headerStack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    headerStack.translatesAutoresizingMaskIntoConstraints = NO;
    headerStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    headerStack.alignment = NSLayoutAttributeLeading;
    headerStack.spacing = MacLCDesign.spacingS;
    [_headerView addSubview:headerStack];

    _detailNameLabel = [NSTextField labelWithString:@""];
    _detailNameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _detailNameLabel.font = MacLCDesign.title1;
    _detailNameLabel.textColor = MacLCDesign.primaryLabel;
    _detailNameLabel.maximumNumberOfLines = 2;
    _detailNameLabel.lineBreakMode = NSLineBreakByWordWrapping;
    [headerStack addArrangedSubview:_detailNameLabel];

    _detailMetaLabel = [NSTextField labelWithString:@""];
    _detailMetaLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _detailMetaLabel.font = MacLCDesign.subheadline;
    _detailMetaLabel.textColor = MacLCDesign.secondaryLabel;
    [headerStack addArrangedSubview:_detailMetaLabel];

    NSStackView *buttonsStack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    buttonsStack.translatesAutoresizingMaskIntoConstraints = NO;
    buttonsStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    buttonsStack.alignment = NSLayoutAttributeCenterY;
    buttonsStack.spacing = MacLCDesign.spacingS;
    [headerStack addArrangedSubview:buttonsStack];

    _playButton = [NSButton buttonWithTitle:_NS("Play") target:self action:@selector(playAction:)];
    _playButton.translatesAutoresizingMaskIntoConstraints = NO;
    _playButton.bezelStyle = NSBezelStylePush;
    _playButton.keyEquivalent = @"\r";
    _playButton.enabled = NO;
    self.window.defaultButtonCell = _playButton.cell;
    [buttonsStack addArrangedSubview:_playButton];

    _addToQueueButton = [NSButton buttonWithTitle:_NS("Add to Queue") target:self action:@selector(addToQueueAction:)];
    _addToQueueButton.translatesAutoresizingMaskIntoConstraints = NO;
    _addToQueueButton.bezelStyle = NSBezelStylePush;
    _addToQueueButton.enabled = NO;
    [buttonsStack addArrangedSubview:_addToQueueButton];

    _statusLabel = [NSTextField labelWithString:@""];
    _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _statusLabel.font = MacLCDesign.subheadline;
    _statusLabel.textColor = MacLCDesign.secondaryLabel;
    _statusLabel.hidden = YES;
    [buttonsStack addArrangedSubview:_statusLabel];

    [NSLayoutConstraint activateConstraints:@[
        [_headerView.topAnchor constraintEqualToAnchor:_detailContentView.safeAreaLayoutGuide.topAnchor constant:MacLCDesign.windowContentMargin],
        [_headerView.leadingAnchor constraintEqualToAnchor:_detailContentView.leadingAnchor constant:MacLCDesign.windowContentMargin],
        [_headerView.trailingAnchor constraintEqualToAnchor:_detailContentView.trailingAnchor constant:-MacLCDesign.windowContentMargin],

        [_detailHeaderPosterView.leadingAnchor constraintEqualToAnchor:_headerView.leadingAnchor],
        [_detailHeaderPosterView.topAnchor constraintEqualToAnchor:_headerView.topAnchor],
        [_detailHeaderPosterView.bottomAnchor constraintLessThanOrEqualToAnchor:_headerView.bottomAnchor],
        [_detailHeaderPosterView.widthAnchor constraintEqualToConstant:96.0],
        [_detailHeaderPosterView.heightAnchor constraintEqualToConstant:144.0],

        [headerStack.leadingAnchor constraintEqualToAnchor:_detailHeaderPosterView.trailingAnchor constant:MacLCDesign.spacingL],
        [headerStack.trailingAnchor constraintEqualToAnchor:_headerView.trailingAnchor],
        [headerStack.topAnchor constraintEqualToAnchor:_headerView.topAnchor],
        [headerStack.bottomAnchor constraintEqualToAnchor:_headerView.bottomAnchor],
    ]];
}

- (void)setupSeriesAndStreamsSplitView
{
    /* Episodes over streams for a series/channel, streams alone for a movie:
     * the episodes area folds to zero height (its own vertical constraints
     * give way, they are not required). */
    _detailBodyView = [[NSView alloc] initWithFrame:NSZeroRect];
    _detailBodyView.translatesAutoresizingMaskIntoConstraints = NO;
    [_detailContentView addSubview:_detailBodyView];

    // 1. Episodes container
    _episodesContainerView = [[NSView alloc] initWithFrame:NSZeroRect];
    _episodesContainerView.translatesAutoresizingMaskIntoConstraints = NO;

    _seasonPopUpButton = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    _seasonPopUpButton.translatesAutoresizingMaskIntoConstraints = NO;
    _seasonPopUpButton.target = self;
    _seasonPopUpButton.action = @selector(seasonSelected:);
    [_episodesContainerView addSubview:_seasonPopUpButton];

    _episodesTableView = [[NSTableView alloc] initWithFrame:NSZeroRect];
    _episodesTableView.style = NSTableViewStyleAutomatic;
    _episodesTableView.headerView = nil;
    _episodesTableView.dataSource = self;
    _episodesTableView.delegate = self;
    _episodesTableView.accessibilityLabel = _NS("Episodes");
    _episodesTableView.allowsEmptySelection = NO;
    _episodesTableView.allowsMultipleSelection = NO;
    _episodesTableView.backgroundColor = [NSColor clearColor];

    NSTableColumn *epCol = [[NSTableColumn alloc] initWithIdentifier:@"EpisodeColumn"];
    epCol.resizingMask = NSTableColumnAutoresizingMask;
    [_episodesTableView addTableColumn:epCol];

    _episodesScrollView = [[NSScrollView alloc] init];
    _episodesScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _episodesScrollView.documentView = _episodesTableView;
    _episodesScrollView.hasVerticalScroller = YES;
    _episodesScrollView.autohidesScrollers = YES;
    _episodesScrollView.drawsBackground = NO;
    [_episodesContainerView addSubview:_episodesScrollView];

    _episodesStateView = [[MacLCAddonSearchStateView alloc] initWithFrame:NSZeroRect];
    [_episodesContainerView addSubview:_episodesStateView];

    _seasonPopUpTopConstraint = [_episodesScrollView.topAnchor constraintEqualToAnchor:_seasonPopUpButton.bottomAnchor constant:MacLCDesign.spacingS];
    _seasonPopUpTopConstraint.priority = NSLayoutPriorityRequired - 1;

    _noSeasonPopUpTopConstraint = [_episodesScrollView.topAnchor constraintEqualToAnchor:_episodesContainerView.topAnchor constant:MacLCDesign.spacingS];
    _noSeasonPopUpTopConstraint.priority = NSLayoutPriorityRequired - 1;

    _episodesStateViewSeasonTopConstraint = [_episodesStateView.topAnchor constraintEqualToAnchor:_seasonPopUpButton.bottomAnchor];
    _episodesStateViewSeasonTopConstraint.priority = NSLayoutPriorityRequired - 1;

    _episodesStateViewNoSeasonTopConstraint = [_episodesStateView.topAnchor constraintEqualToAnchor:_episodesContainerView.topAnchor];
    _episodesStateViewNoSeasonTopConstraint.priority = NSLayoutPriorityRequired - 1;

    NSArray<NSLayoutConstraint *> * const foldable = @[
        [_seasonPopUpButton.topAnchor constraintEqualToAnchor:_episodesContainerView.topAnchor constant:MacLCDesign.spacingS],
        _seasonPopUpTopConstraint,
        [_episodesScrollView.bottomAnchor constraintEqualToAnchor:_episodesContainerView.bottomAnchor constant:-MacLCDesign.spacingS],
        _episodesStateViewSeasonTopConstraint,
        [_episodesStateView.bottomAnchor constraintEqualToAnchor:_episodesContainerView.bottomAnchor],
    ];
    for (NSLayoutConstraint *constraint in foldable)
        constraint.priority = NSLayoutPriorityRequired - 1;
    [NSLayoutConstraint activateConstraints:foldable];

    [NSLayoutConstraint activateConstraints:@[
        [_seasonPopUpButton.leadingAnchor constraintEqualToAnchor:_episodesContainerView.leadingAnchor constant:MacLCDesign.windowContentMargin],
        [_seasonPopUpButton.widthAnchor constraintGreaterThanOrEqualToConstant:140.0],
        [_episodesScrollView.leadingAnchor constraintEqualToAnchor:_episodesContainerView.leadingAnchor constant:MacLCDesign.windowContentMargin],
        [_episodesScrollView.trailingAnchor constraintEqualToAnchor:_episodesContainerView.trailingAnchor constant:-MacLCDesign.windowContentMargin],
        [_episodesStateView.leadingAnchor constraintEqualToAnchor:_episodesContainerView.leadingAnchor],
        [_episodesStateView.trailingAnchor constraintEqualToAnchor:_episodesContainerView.trailingAnchor],
    ]];

    // 2. Streams container
    _streamsContainerView = [[NSView alloc] initWithFrame:NSZeroRect];
    _streamsContainerView.translatesAutoresizingMaskIntoConstraints = NO;

    _streamsSectionLabel = [NSTextField labelWithString:_NS("Streams")];
    _streamsSectionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _streamsSectionLabel.font = MacLCDesign.headline;
    _streamsSectionLabel.textColor = MacLCDesign.primaryLabel;
    [_streamsContainerView addSubview:_streamsSectionLabel];

    _streamsTableView = [[NSTableView alloc] initWithFrame:NSZeroRect];
    _streamsTableView.style = NSTableViewStyleAutomatic;
    _streamsTableView.headerView = nil;
    _streamsTableView.dataSource = self;
    _streamsTableView.delegate = self;
    _streamsTableView.accessibilityLabel = _NS("Streams");
    _streamsTableView.allowsEmptySelection = YES;
    _streamsTableView.allowsMultipleSelection = NO;
    _streamsTableView.backgroundColor = [NSColor clearColor];
    _streamsTableView.target = self;
    _streamsTableView.doubleAction = @selector(tableDoubleClicked:);

    NSTableColumn *streamCol = [[NSTableColumn alloc] initWithIdentifier:@"StreamColumn"];
    streamCol.resizingMask = NSTableColumnAutoresizingMask;
    [_streamsTableView addTableColumn:streamCol];

    [self setupStreamsContextMenu];

    _streamsScrollView = [[NSScrollView alloc] init];
    _streamsScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _streamsScrollView.documentView = _streamsTableView;
    _streamsScrollView.hasVerticalScroller = YES;
    _streamsScrollView.autohidesScrollers = YES;
    _streamsScrollView.drawsBackground = NO;
    [_streamsContainerView addSubview:_streamsScrollView];

    _streamsStateView = [[MacLCAddonSearchStateView alloc] initWithFrame:NSZeroRect];
    [_streamsContainerView addSubview:_streamsStateView];

    [NSLayoutConstraint activateConstraints:@[
        [_streamsSectionLabel.topAnchor constraintEqualToAnchor:_streamsContainerView.topAnchor constant:MacLCDesign.spacingM],
        [_streamsSectionLabel.leadingAnchor constraintEqualToAnchor:_streamsContainerView.leadingAnchor constant:MacLCDesign.windowContentMargin],

        [_streamsScrollView.topAnchor constraintEqualToAnchor:_streamsSectionLabel.bottomAnchor constant:MacLCDesign.spacingS],
        [_streamsScrollView.leadingAnchor constraintEqualToAnchor:_streamsContainerView.leadingAnchor constant:MacLCDesign.windowContentMargin],
        [_streamsScrollView.trailingAnchor constraintEqualToAnchor:_streamsContainerView.trailingAnchor constant:-MacLCDesign.windowContentMargin],
        [_streamsScrollView.bottomAnchor constraintEqualToAnchor:_streamsContainerView.bottomAnchor constant:-MacLCDesign.spacingM],

        [_streamsStateView.topAnchor constraintEqualToAnchor:_streamsSectionLabel.bottomAnchor],
        [_streamsStateView.leadingAnchor constraintEqualToAnchor:_streamsContainerView.leadingAnchor],
        [_streamsStateView.trailingAnchor constraintEqualToAnchor:_streamsContainerView.trailingAnchor],
        [_streamsStateView.bottomAnchor constraintEqualToAnchor:_streamsContainerView.bottomAnchor],
    ]];

    _episodesSeparator = [[NSBox alloc] initWithFrame:NSZeroRect];
    _episodesSeparator.boxType = NSBoxSeparator;
    _episodesSeparator.translatesAutoresizingMaskIntoConstraints = NO;

    [_detailBodyView addSubview:_episodesContainerView];
    [_detailBodyView addSubview:_episodesSeparator];
    [_detailBodyView addSubview:_streamsContainerView];

    _episodesShownHeight = [_episodesContainerView.heightAnchor constraintEqualToAnchor:_detailBodyView.heightAnchor multiplier:0.42];
    _episodesHiddenHeight = [_episodesContainerView.heightAnchor constraintEqualToConstant:0.0];
    _episodesContainerView.hidden = YES;
    _episodesSeparator.hidden = YES;

    [NSLayoutConstraint activateConstraints:@[
        [_detailBodyView.topAnchor constraintEqualToAnchor:_headerView.bottomAnchor constant:MacLCDesign.spacingM],
        [_detailBodyView.leadingAnchor constraintEqualToAnchor:_detailContentView.leadingAnchor],
        [_detailBodyView.trailingAnchor constraintEqualToAnchor:_detailContentView.trailingAnchor],
        [_detailBodyView.bottomAnchor constraintEqualToAnchor:_detailContentView.bottomAnchor],

        [_episodesContainerView.topAnchor constraintEqualToAnchor:_detailBodyView.topAnchor],
        [_episodesContainerView.leadingAnchor constraintEqualToAnchor:_detailBodyView.leadingAnchor],
        [_episodesContainerView.trailingAnchor constraintEqualToAnchor:_detailBodyView.trailingAnchor],
        _episodesHiddenHeight,

        [_episodesSeparator.topAnchor constraintEqualToAnchor:_episodesContainerView.bottomAnchor],
        [_episodesSeparator.leadingAnchor constraintEqualToAnchor:_detailBodyView.leadingAnchor],
        [_episodesSeparator.trailingAnchor constraintEqualToAnchor:_detailBodyView.trailingAnchor],

        [_streamsContainerView.topAnchor constraintEqualToAnchor:_episodesSeparator.bottomAnchor],
        [_streamsContainerView.leadingAnchor constraintEqualToAnchor:_detailBodyView.leadingAnchor],
        [_streamsContainerView.trailingAnchor constraintEqualToAnchor:_detailBodyView.trailingAnchor],
        [_streamsContainerView.bottomAnchor constraintEqualToAnchor:_detailBodyView.bottomAnchor],
    ]];
}

- (void)setupStreamsContextMenu
{
    NSMenu *contextMenu = [[NSMenu alloc] initWithTitle:_NS("Streams Context Menu")];
    contextMenu.delegate = self;

    NSMenuItem *playItem = [[NSMenuItem alloc] initWithTitle:_NS("Play") action:@selector(playAction:) keyEquivalent:@""];
    playItem.target = self;
    [contextMenu addItem:playItem];

    NSMenuItem *queueItem = [[NSMenuItem alloc] initWithTitle:_NS("Add to Queue") action:@selector(addToQueueAction:) keyEquivalent:@""];
    queueItem.target = self;
    [contextMenu addItem:queueItem];

    self.streamsTableView.menu = contextMenu;
}

- (void)setupKeyViewLoop
{
    _searchToolbarItem.searchField.nextKeyView = _resultsTableView;
    if (!_episodesContainerView.isHidden) {
        if (!_seasonPopUpButton.isHidden) {
            _resultsTableView.nextKeyView = _seasonPopUpButton;
            _seasonPopUpButton.nextKeyView = _episodesTableView;
        } else {
            _resultsTableView.nextKeyView = _episodesTableView;
        }
        _episodesTableView.nextKeyView = _streamsTableView;
    } else {
        _resultsTableView.nextKeyView = _streamsTableView;
    }
    _streamsTableView.nextKeyView = _playButton;
    _playButton.nextKeyView = _addToQueueButton;
    _addToQueueButton.nextKeyView = _searchToolbarItem.searchField;
}

#pragma mark - Window Visibility & Search Interaction

- (IBAction)showWindow:(nullable id)sender
{
    [super showWindow:sender];
    [self.window makeKeyAndOrderFront:sender];
    [self.window makeFirstResponder:_searchToolbarItem.searchField];
    [_searchToolbarItem beginSearchInteraction];
}

- (void)showWindowWithQuery:(NSString *)query autoplayType:(nullable NSString *)type
{
    [self showWindow:nil];
    self.searchToolbarItem.searchField.stringValue = query ?: @"";
    /* "select-movie" / "select-series" stop once the streams are listed. */
    _autoplayPlays = ![type hasPrefix:@"select-"];
    _autoplayType = _autoplayPlays ? [type copy] : [type substringFromIndex:7];
    _autoplayPending = (_autoplayType.length > 0);
    [self performSearchWithQuery:query];
}

- (IBAction)performFindPanelAction:(nullable id)sender
{
    [_searchToolbarItem beginSearchInteraction];
}

- (IBAction)performTextFinderAction:(nullable id)sender
{
    [_searchToolbarItem beginSearchInteraction];
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem
{
    if (menuItem.action == @selector(playAction:) || menuItem.action == @selector(addToQueueAction:)) {
        return (self.selectedStream != nil);
    }
    if (menuItem.action == @selector(performFindPanelAction:) ||
        menuItem.action == @selector(performTextFinderAction:)) {
        return YES;
    }
    return YES;
}

- (void)menuNeedsUpdate:(NSMenu *)menu
{
    if (menu == _streamsTableView.menu) {
        NSInteger clickedRow = _streamsTableView.clickedRow;
        if (clickedRow >= 0 && clickedRow < (NSInteger)_streamDisplayItems.count) {
            id item = _streamDisplayItems[clickedRow];
            if ([item isKindOfClass:[MacLCAddonStream class]]) {
                [_streamsTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:clickedRow] byExtendingSelection:NO];
                _selectedStream = (MacLCAddonStream *)item;
                [self updateButtons];
            }
        }
    }
}

#pragma mark - Search Field Actions

- (void)searchFieldAction:(NSSearchField *)sender
{
    /* The field sends its action again when editing ends, as when a click in the
     * results takes the focus: searching again would wipe them and that click. */
    NSString * const query = [sender.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([query isEqualToString:_currentSearchQuery] && _resultsDisplayItems.count > 0)
        return;
    [self performSearchWithQuery:sender.stringValue];
}

- (void)retrySearch:(nullable id)sender
{
    [self performSearchWithQuery:_currentSearchQuery];
}

- (void)openAddonsSettings:(nullable id)sender
{
    MacLCSettingsWindowController *swc = VLCMain.sharedInstance.settingsWindowController;
    [swc showSettingsWindowWithLevel:NSNormalWindowLevel];
    [swc selectPaneWithIdentifier:@"addons"];
}

- (void)performSearchWithQuery:(NSString *)rawQuery
{
    NSString *query = [rawQuery stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    _currentSearchQuery = query;

    [_searchRequest cancel];
    _searchRequest = nil;

    _searchGeneration++;
    const NSUInteger currentGen = _searchGeneration;

    if (query.length < 2) {
        _resultsDisplayItems = @[];
        [_resultsTableView reloadData];
        [_resultsStateView showIdle];
        [self clearSelectionAndDetail];
        return;
    }

    // Check if any installed add-on provides search
    NSUInteger searchAddonsCount = 0;
    for (MacLCAddon *addon in MacLCAddonStore.sharedStore.installedAddons) {
        if (addon.providesSearch) {
            searchAddonsCount++;
        }
    }

    if (searchAddonsCount == 0) {
        _resultsDisplayItems = @[];
        [_resultsTableView deselectAll:nil];
        [_resultsTableView reloadData];
        [self clearSelectionAndDetail];

        [_resultsStateView showErrorWithTitle:_NS("No Search Add-on")
                                      message:_NS("Install an add-on that can search, such as Cinemeta, in Add-ons settings.")
                                  buttonTitle:_NS("Open Add-ons Settings…")
                                       target:self
                                       action:@selector(openAddonsSettings:)];
        return;
    }

    [_resultsStateView showLoading];
    _resultsDisplayItems = @[];
    [_resultsTableView deselectAll:nil];
    [_resultsTableView reloadData];
    [self clearSelectionAndDetail];

    __weak typeof(self) weakSelf = self;
    _searchRequest = [MacLCAddonStore.sharedStore searchTitles:query completion:^(NSArray<MacLCAddonSearchGroup *> *groups) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || strongSelf.searchGeneration != currentGen) {
            return;
        }
        strongSelf.searchRequest = nil;

        // Check if all groups failed
        BOOL allFailed = (groups.count > 0);
        NSError *firstError = nil;
        NSString *firstErrorAddonName = nil;
        for (MacLCAddonSearchGroup *g in groups) {
            if (g.error == nil) {
                allFailed = NO;
            } else if (!firstError) {
                firstError = g.error;
                firstErrorAddonName = g.addon.name;
            }
        }

        if (allFailed && firstError) {
            NSString *serviceName = firstErrorAddonName.length > 0 ? firstErrorAddonName : _NS("Add-on");
            NSString *errTitle = nil;
            NSString *errMessage = nil;
            [strongSelf getErrorTitle:&errTitle message:&errMessage forError:firstError service:serviceName];
            msg_Warn(getIntf(), "addons: %s: %s: %s", serviceName.UTF8String, errTitle.UTF8String, errMessage.UTF8String);

            [strongSelf.resultsStateView showErrorWithTitle:errTitle
                                                    message:errMessage
                                                buttonTitle:_NS("Try Again")
                                                     target:strongSelf
                                                     action:@selector(retrySearch:)];
            return;
        }

        // Build results
        NSMutableArray *display = [NSMutableArray array];
        NSUInteger totalResults = 0;
        NSUInteger nonEmptyGroups = 0;

        for (MacLCAddonSearchGroup *group in groups) {
            if (group.items.count > 0) {
                totalResults += group.items.count;
                nonEmptyGroups++;

                NSString *typeName = TypeNameForGroupType(group.type);
                NSString *header = typeName;
                if (searchAddonsCount > 1 && group.addon.name.length > 0) {
                    header = [NSString stringWithFormat:@"%@ · %@", header, group.addon.name];
                }
                [display addObject:header];
                [display addObjectsFromArray:group.items];
            }
        }

        msg_Dbg(getIntf(), "addons: search \"%s\": %lu results in %lu groups",
                query.UTF8String,
                (unsigned long)totalResults,
                (unsigned long)nonEmptyGroups);

        strongSelf.resultsDisplayItems = [display copy];
        [strongSelf.resultsTableView reloadData];

        if (strongSelf.resultsDisplayItems.count == 0) {
            [strongSelf.resultsStateView showEmptyWithTitle:_NS("No Results")
                                                    message:_NS("Check the spelling or try another title.")];
        } else {
            [strongSelf.resultsStateView showIdle];
            [strongSelf handleAutoplaySearchSelection];
        }
    }];
}

- (void)handleAutoplaySearchSelection
{
    if (!_autoplayPending || _autoplayType.length == 0) {
        return;
    }

    if ([_autoplayType isEqualToString:@"movie"]) {
        for (NSUInteger i = 0; i < _resultsDisplayItems.count; i++) {
            id item = _resultsDisplayItems[i];
            if ([item isKindOfClass:[MacLCAddonItem class]] && [((MacLCAddonItem *)item).type isEqualToString:@"movie"]) {
                [_resultsTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:i] byExtendingSelection:NO];
                [_resultsTableView scrollRowToVisible:i];
                break;
            }
        }
    } else if ([_autoplayType isEqualToString:@"series"]) {
        for (NSUInteger i = 0; i < _resultsDisplayItems.count; i++) {
            id item = _resultsDisplayItems[i];
            if ([item isKindOfClass:[MacLCAddonItem class]] && [((MacLCAddonItem *)item).type isEqualToString:@"series"]) {
                [_resultsTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:i] byExtendingSelection:NO];
                [_resultsTableView scrollRowToVisible:i];
                break;
            }
        }
    }
}

#pragma mark - Title Selection & Detail Presentation

- (void)clearSelectionAndDetail
{
    self.window.subtitle = @"";
    _selectedItem = nil;
    [self cancelDetailRequests];

    _detailContentView.hidden = YES;
    _detailEmptyStateView.hidden = NO;
    [self setupKeyViewLoop];
}

- (void)selectItem:(MacLCAddonItem *)item
{
    [self cancelDetailRequests];
    _selectedItem = item;
    self.window.subtitle = item.name;

    _detailEmptyStateView.hidden = YES;
    _detailContentView.hidden = NO;

    // Header updates
    _detailNameLabel.stringValue = item.name;
    NSString *kindString = SingularNameForType(item.type);
    if (item.releaseInfo.length > 0) {
        _detailMetaLabel.stringValue = [NSString stringWithFormat:@"%@ · %@", item.releaseInfo, kindString];
    } else {
        _detailMetaLabel.stringValue = kindString;
    }

    NSString *placeholderSymbol = [item.type isEqualToString:@"movie"] ? @"film" : @"tv";
    NSImage *placeholder = [MacLCDesign symbolNamed:placeholderSymbol
                                          pointSize:36.0
                                             weight:NSFontWeightRegular
                                 accessibilityLabel:nil];
    _detailHeaderPosterView.image = placeholder;
    _detailHeaderPosterView.contentTintColor = MacLCDesign.tertiaryLabel;

    if (item.posterURL) {
        NSString *key = item.posterURL.absoluteString;
        NSImage *cached = [_posterCache objectForKey:key];
        if (cached) {
            _detailHeaderPosterView.image = cached;
            _detailHeaderPosterView.contentTintColor = nil;
        } else {
            [self loadPosterForURL:item.posterURL];
        }
    }

    if ([item.type isEqualToString:@"movie"]) {
        _episodesContainerView.hidden = YES;
        _episodesSeparator.hidden = YES;
        _episodesShownHeight.active = NO;
        _episodesHiddenHeight.active = YES;

        [self updateButtons];
        [self setupKeyViewLoop];

        _selectedVideo = nil;
        [self loadStreamsForType:@"movie" videoIdentifier:item.identifier];
    } else {
        _episodesContainerView.hidden = NO;
        _episodesSeparator.hidden = NO;
        _episodesHiddenHeight.active = NO;
        _episodesShownHeight.active = YES;

        [self updateButtons];
        [self setupKeyViewLoop];

        [self loadMetaForItem:item];
    }
}

#pragma mark - Episodes Loading & Presentation

- (void)loadMetaForItem:(MacLCAddonItem *)item
{
    [_metaRequest cancel];
    _metaRequest = nil;

    _metaGeneration++;
    const NSUInteger currentGen = _metaGeneration;

    _allVideos = @[];
    _availableSeasons = @[];
    _currentSeasonVideos = @[];
    [_seasonPopUpButton removeAllItems];
    [_episodesTableView reloadData];

    [_episodesStateView showLoading];

    __weak typeof(self) weakSelf = self;
    _metaRequest = [MacLCAddonStore.sharedStore fetchMetaForItem:item completion:^(MacLCAddonMeta * _Nullable meta, NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || strongSelf.metaGeneration != currentGen) {
            return;
        }
        strongSelf.metaRequest = nil;

        if (error) {
            NSString *serviceName = item.addon.name.length > 0 ? item.addon.name : _NS("Add-on");
            NSString *errTitle = nil;
            NSString *errMessage = nil;
            [strongSelf getErrorTitle:&errTitle message:&errMessage forError:error service:serviceName];
            msg_Warn(getIntf(), "addons: %s: %s: %s", serviceName.UTF8String, errTitle.UTF8String, errMessage.UTF8String);

            [strongSelf.episodesStateView showErrorWithTitle:errTitle
                                                     message:errMessage
                                                 buttonTitle:_NS("Try Again")
                                                      target:strongSelf
                                                      action:@selector(retryEpisodes:)];
            return;
        }

        if (!meta || meta.videos.count == 0) {
            // Fold episodes area to zero height
            strongSelf.episodesContainerView.hidden = YES;
            strongSelf.episodesSeparator.hidden = YES;
            strongSelf.episodesShownHeight.active = NO;
            strongSelf.episodesHiddenHeight.active = YES;
            [strongSelf setupKeyViewLoop];

            strongSelf.selectedVideo = nil;
            NSString *videoId = (meta && meta.defaultVideoIdentifier.length > 0) ? meta.defaultVideoIdentifier : item.identifier;
            [strongSelf loadStreamsForType:item.type videoIdentifier:videoId];
            return;
        }

        msg_Dbg(getIntf(), "addons: %lu videos for %s", (unsigned long)meta.videos.count, item.identifier.UTF8String);

        strongSelf.allVideos = meta.videos;
        [strongSelf.episodesStateView showIdle];
        [strongSelf populateVideosAndSelectDefault];
    }];
}

- (void)retryEpisodes:(nullable id)sender
{
    if (_selectedItem) {
        [self loadMetaForItem:_selectedItem];
    }
}

- (void)populateVideosAndSelectDefault
{
    BOOL hasPositiveSeason = NO;
    for (MacLCAddonVideo *v in _allVideos) {
        if (v.season > 0) {
            hasPositiveSeason = YES;
            break;
        }
    }

    if (hasPositiveSeason) {
        _seasonPopUpButton.hidden = NO;
        _noSeasonPopUpTopConstraint.active = NO;
        _seasonPopUpTopConstraint.active = YES;
        _episodesStateViewNoSeasonTopConstraint.active = NO;
        _episodesStateViewSeasonTopConstraint.active = YES;

        NSMutableSet<NSNumber *> *seasonSet = [NSMutableSet set];
        for (MacLCAddonVideo *v in _allVideos) {
            [seasonSet addObject:@(v.season)];
        }

        NSMutableArray<NSNumber *> *sortedSeasons = [[seasonSet allObjects] mutableCopy];
        [sortedSeasons sortUsingSelector:@selector(compare:)];

        BOOL hasZero = [sortedSeasons containsObject:@(0)];
        if (hasZero) {
            [sortedSeasons removeObject:@(0)];
            [sortedSeasons addObject:@(0)];
        }
        _availableSeasons = [sortedSeasons copy];

        [_seasonPopUpButton removeAllItems];
        for (NSNumber *seasonNum in _availableSeasons) {
            NSInteger s = seasonNum.integerValue;
            NSString *title = (s == 0) ? _NS("Specials") : [NSString stringWithFormat:_NS("Season %ld"), (long)s];
            NSMenuItem *menuItem = [[NSMenuItem alloc] initWithTitle:title action:nil keyEquivalent:@""];
            menuItem.tag = s;
            [_seasonPopUpButton.menu addItem:menuItem];
        }

        // Series default: lowest season >= 1, else 0
        NSInteger targetSeason = 0;
        BOOL foundPositive = NO;
        for (NSNumber *seasonNum in _availableSeasons) {
            if (seasonNum.integerValue >= 1) {
                targetSeason = seasonNum.integerValue;
                foundPositive = YES;
                break;
            }
        }
        if (!foundPositive && _availableSeasons.count > 0) {
            targetSeason = _availableSeasons.firstObject.integerValue;
        }

        [_seasonPopUpButton selectItemWithTag:targetSeason];
        [self setupKeyViewLoop];
        [self filterVideosForSeason:targetSeason selectFirstRow:YES];
    } else {
        _seasonPopUpButton.hidden = YES;
        _seasonPopUpTopConstraint.active = NO;
        _noSeasonPopUpTopConstraint.active = YES;
        _episodesStateViewSeasonTopConstraint.active = NO;
        _episodesStateViewNoSeasonTopConstraint.active = YES;
        _availableSeasons = @[];
        [_seasonPopUpButton removeAllItems];

        [self setupKeyViewLoop];

        _currentSeasonVideos = [_allVideos copy];
        [_episodesTableView reloadData];

        _selectedVideo = nil;
        [_episodesTableView deselectAll:nil];
        if (_currentSeasonVideos.count > 0) {
            /* The selection delegate loads the video's streams. */
            [_episodesTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
            [_episodesTableView scrollRowToVisible:0];
        } else {
            _streamGroups = [NSMutableArray array];
            _streamDisplayItems = @[];
            _selectedStream = nil;
            [_streamsTableView reloadData];
            [self updateButtons];
        }
    }
}

- (void)seasonSelected:(NSPopUpButton *)sender
{
    NSInteger season = sender.selectedItem.tag;
    [self filterVideosForSeason:season selectFirstRow:YES];
}

- (void)filterVideosForSeason:(NSInteger)season selectFirstRow:(BOOL)selectFirst
{
    NSMutableArray<MacLCAddonVideo *> *filtered = [NSMutableArray array];
    for (MacLCAddonVideo *v in _allVideos) {
        if (v.season == season) {
            [filtered addObject:v];
        }
    }
    [filtered sortUsingComparator:^NSComparisonResult(MacLCAddonVideo *obj1, MacLCAddonVideo *obj2) {
        if (obj1.episode < obj2.episode) return NSOrderedAscending;
        if (obj1.episode > obj2.episode) return NSOrderedDescending;
        return NSOrderedSame;
    }];
    _currentSeasonVideos = [filtered copy];
    [_episodesTableView reloadData];

    _selectedVideo = nil;
    [_episodesTableView deselectAll:nil];
    if (selectFirst && _currentSeasonVideos.count > 0) {
        /* The selection delegate loads the video's streams. */
        [_episodesTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
        [_episodesTableView scrollRowToVisible:0];
    } else {
        _streamGroups = [NSMutableArray array];
        _streamDisplayItems = @[];
        _selectedStream = nil;
        [_streamsTableView reloadData];
        [self updateButtons];
    }
}

#pragma mark - Streams Loading & Presentation

- (void)loadStreamsForType:(NSString *)type videoIdentifier:(NSString *)identifier
{
    /* What Try Again asks for (a defaultVideoId included). */
    _streamsType = [type copy];
    _streamsVideoIdentifier = [identifier copy];
    [_streamsRequest cancel];
    _streamsRequest = nil;

    _streamsGeneration++;
    const NSUInteger currentGen = _streamsGeneration;

    _streamGroups = [NSMutableArray array];
    _streamDisplayItems = @[];
    _selectedStream = nil;
    [_streamsTableView reloadData];
    [self updateButtons];

    [_streamsStateView showLoading];

    __weak typeof(self) weakSelf = self;
    _streamsRequest = [MacLCAddonStore.sharedStore fetchStreamsForType:type
                                                      videoIdentifier:identifier
                                                            eachGroup:^(MacLCAddonStreamGroup *group) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || strongSelf.streamsGeneration != currentGen) {
            return;
        }

        [strongSelf handleStreamGroup:group type:type identifier:identifier];
    } completion:^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || strongSelf.streamsGeneration != currentGen) {
            return;
        }
        strongSelf.streamsRequest = nil;

        [strongSelf handleStreamsCompletionForType:type identifier:identifier];
    }];
}

- (void)handleStreamGroup:(MacLCAddonStreamGroup *)group
                     type:(NSString *)type
               identifier:(NSString *)identifier
{
    msg_Dbg(getIntf(), "addons: %lu streams from %s for %s/%s",
            (unsigned long)group.streams.count,
            group.addon.name.UTF8String,
            type.UTF8String,
            identifier.UTF8String);

    if (group.error) {
        NSString *serviceName = group.addon.name.length > 0 ? group.addon.name : _NS("Add-on");
        NSString *errTitle = nil;
        NSString *errMessage = nil;
        [self getErrorTitle:&errTitle message:&errMessage forError:group.error service:serviceName];
        msg_Warn(getIntf(), "addons: %s: %s: %s", serviceName.UTF8String, errTitle.UTF8String, errMessage.UTF8String);
    }

    [_streamGroups addObject:group];

    // Sort received groups by addon index in installedAddons
    NSArray<MacLCAddon *> *installed = MacLCAddonStore.sharedStore.installedAddons;
    [_streamGroups sortUsingComparator:^NSComparisonResult(MacLCAddonStreamGroup *g1, MacLCAddonStreamGroup *g2) {
        NSUInteger idx1 = [installed indexOfObjectPassingTest:^BOOL(MacLCAddon *a, NSUInteger idx, BOOL *stop) {
            return [a.identifier isEqualToString:g1.addon.identifier];
        }];
        NSUInteger idx2 = [installed indexOfObjectPassingTest:^BOOL(MacLCAddon *a, NSUInteger idx, BOOL *stop) {
            return [a.identifier isEqualToString:g2.addon.identifier];
        }];
        if (idx1 < idx2) return NSOrderedAscending;
        if (idx1 > idx2) return NSOrderedDescending;
        return NSOrderedSame;
    }];

    // Flatten into streamDisplayItems. When every add-on failed so far, the
    // centred error state says it once: no "Not Responding" rows on top.
    BOOL anyAnswered = NO;
    for (MacLCAddonStreamGroup *g in _streamGroups)
        anyAnswered = anyAnswered || g.error == nil;
    NSMutableArray *items = [NSMutableArray array];
    for (MacLCAddonStreamGroup *g in _streamGroups) {
        if (g.error && !anyAnswered) {
            continue;
        } else if (g.error) {
            [items addObject:[NSString stringWithFormat:@"%@ — %@", g.addon.name, _NS("Not Responding")]];
        } else {
            [items addObject:g.addon.name];
            [items addObjectsFromArray:g.streams];
        }
    }
    _streamDisplayItems = [items copy];
    [_streamsTableView reloadData];

    // When the first stream row appears and nothing is selected, select it
    if (_selectedStream == nil) {
        for (NSUInteger i = 0; i < _streamDisplayItems.count; i++) {
            id item = _streamDisplayItems[i];
            if ([item isKindOfClass:[MacLCAddonStream class]]) {
                _selectedStream = (MacLCAddonStream *)item;
                [_streamsTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:i] byExtendingSelection:NO];
                [_streamsTableView scrollRowToVisible:i];
                [self updateButtons];
                break;
            }
        }
    } else {
        NSUInteger newIndex = [_streamDisplayItems indexOfObject:_selectedStream];
        if (newIndex != NSNotFound && _streamsTableView.selectedRow != (NSInteger)newIndex) {
            [_streamsTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:newIndex] byExtendingSelection:NO];
        }
    }

    if (_selectedStream != nil) {
        [_streamsStateView showIdle];
    }
}

- (void)handleStreamsCompletionForType:(NSString *)type identifier:(NSString *)identifier
{
    // Check if any installed add-on provides streams for this title/video
    BOOL anyProvidesStreams = NO;
    for (MacLCAddon *addon in MacLCAddonStore.sharedStore.installedAddons) {
        if ([addon providesResource:@"stream" forType:type identifier:identifier]) {
            anyProvidesStreams = YES;
            break;
        }
    }

    if (!anyProvidesStreams) {
        [_streamsStateView showErrorWithTitle:_NS("No Stream Add-on")
                                      message:_NS("Install an add-on that provides streams in Add-ons settings.")
                                  buttonTitle:_NS("Open Add-ons Settings…")
                                       target:self
                                       action:@selector(openAddonsSettings:)];
        return;
    }

    NSUInteger totalStreams = 0;
    NSUInteger failedGroups = 0;
    for (MacLCAddonStreamGroup *g in _streamGroups) {
        totalStreams += g.streams.count;
        if (g.error) {
            failedGroups++;
        }
    }

    // Every add-on failed -> first error state with Try Again
    if (_streamGroups.count > 0 && failedGroups == _streamGroups.count) {
        NSError *firstError = _streamGroups.firstObject.error;
        NSString *serviceName = _streamGroups.firstObject.addon.name.length > 0 ? _streamGroups.firstObject.addon.name : _NS("Add-on");
        NSString *errTitle = nil;
        NSString *errMessage = nil;
        [self getErrorTitle:&errTitle message:&errMessage forError:firstError service:serviceName];

        [_streamsStateView showErrorWithTitle:errTitle
                                      message:errMessage
                                  buttonTitle:_NS("Try Again")
                                       target:self
                                       action:@selector(retryStreams:)];
        return;
    }

    // No stream row -> No Streams
    if (totalStreams == 0) {
        const BOOL isVideo = (_selectedVideo != nil) || [type isEqualToString:@"series"];
        NSString *emptyMsg = isVideo ?
            _NS("No installed add-on has streams for this episode.") :
            _NS("No installed add-on has streams for this title.");
        [_streamsStateView showEmptyWithTitle:_NS("No Streams") message:emptyMsg];
        return;
    }

    [_streamsStateView showIdle];

    // Autoplay hook plays the first stream row after completion (not before)
    if (_autoplayPending) {
        _autoplayPending = NO;
        _autoplayType = nil;
        if (_autoplayPlays) {
            /* The first row in display order, whatever add-on answered first. */
            for (NSUInteger i = 0; i < _streamDisplayItems.count; i++) {
                if ([_streamDisplayItems[i] isKindOfClass:[MacLCAddonStream class]]) {
                    _selectedStream = _streamDisplayItems[i];
                    [_streamsTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:i] byExtendingSelection:NO];
                    [self playAction:nil];
                    break;
                }
            }
        }
    }
}

- (void)retryStreams:(nullable id)sender
{
    if (_streamsType != nil && _streamsVideoIdentifier != nil)
        [self loadStreamsForType:_streamsType videoIdentifier:_streamsVideoIdentifier];
}

#pragma mark - Playback Actions

- (void)updateButtons
{
    if (_selectedStream) {
        _playButton.enabled = YES;
        _addToQueueButton.enabled = YES;

        NSString *desc = _selectedStream.headline;
        if (_selectedStream.addon.name.length > 0) {
            desc = [NSString stringWithFormat:@"%@ (%@)", desc, _selectedStream.addon.name];
        }
        _playButton.toolTip = [NSString stringWithFormat:_NS("Play %@"), desc];
    } else {
        _playButton.enabled = NO;
        _addToQueueButton.enabled = NO;
        _playButton.toolTip = nil;
    }
}

- (void)playAction:(nullable id)sender
{
    if (!_selectedStream || !_selectedItem) {
        return;
    }

    NSString *itemName = [MacLCAddonStore itemNameForItem:_selectedItem video:_selectedVideo];
    NSString *mrl = _selectedStream.MRL;

    msg_Dbg(getIntf(), "addons: playing \"%s\" %s", itemName.UTF8String, mrl.UTF8String);

    VLCOpenInputMetadata * const meta = [[VLCOpenInputMetadata alloc] init];
    meta.MRLString = mrl;
    meta.itemName = itemName;

    [VLCMain.sharedInstance.playQueueController addPlayQueueItems:@[meta] atPosition:(size_t)-1 startPlayback:YES];
    [self.window close];
}

- (void)addToQueueAction:(nullable id)sender
{
    if (!_selectedStream || !_selectedItem) {
        return;
    }

    NSString *itemName = [MacLCAddonStore itemNameForItem:_selectedItem video:_selectedVideo];
    NSString *mrl = _selectedStream.MRL;

    msg_Dbg(getIntf(), "addons: queued \"%s\" %s", itemName.UTF8String, mrl.UTF8String);

    VLCOpenInputMetadata * const meta = [[VLCOpenInputMetadata alloc] init];
    meta.MRLString = mrl;
    meta.itemName = itemName;

    [VLCMain.sharedInstance.playQueueController addPlayQueueItems:@[meta]];

    _statusLabel.stringValue = _NS("Added to the queue");
    _statusLabel.hidden = NO;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf) {
            strongSelf.statusLabel.hidden = YES;
        }
    });
}

- (void)tableDoubleClicked:(id)sender
{
    NSInteger row = _streamsTableView.clickedRow;
    if (row >= 0 && row < (NSInteger)_streamDisplayItems.count) {
        id item = _streamDisplayItems[row];
        if ([item isKindOfClass:[MacLCAddonStream class]]) {
            _selectedStream = (MacLCAddonStream *)item;
            [self playAction:nil];
        }
    }
}

#pragma mark - Error Presentation Mapping

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

#pragma mark - Posters

- (void)loadPosterForURL:(NSURL *)url
{
    NSString *key = url.absoluteString;
    NSImage *cached = [_posterCache objectForKey:key];
    if (cached) {
        [self applyPosterImage:cached forURLString:key];
        return;
    }

    if (_posterTasks[key] != nil) {
        return;
    }

    __weak typeof(self) weakSelf = self;
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;

            [strongSelf.posterTasks removeObjectForKey:key];
            if (data) {
                NSImage *img = [[NSImage alloc] initWithData:data];
                if (img) {
                    [strongSelf.posterCache setObject:img forKey:key];
                    [strongSelf applyPosterImage:img forURLString:key];
                }
            }
        });
    }];
    _posterTasks[key] = task;
    [task resume];
}

- (void)applyPosterImage:(NSImage *)image forURLString:(NSString *)urlString
{
    if (_selectedItem && [_selectedItem.posterURL.absoluteString isEqualToString:urlString]) {
        _detailHeaderPosterView.image = image;
        _detailHeaderPosterView.contentTintColor = nil;
    }

    for (NSInteger i = 0; i < (NSInteger)_resultsDisplayItems.count; i++) {
        id item = _resultsDisplayItems[i];
        if ([item isKindOfClass:[MacLCAddonItem class]]) {
            MacLCAddonItem *addonItem = (MacLCAddonItem *)item;
            if ([addonItem.posterURL.absoluteString isEqualToString:urlString]) {
                MacLCAddonSearchResultCellView *cell = [_resultsTableView viewAtColumn:0 row:i makeIfNecessary:NO];
                if (cell) {
                    cell.posterImageView.image = image;
                    cell.posterImageView.contentTintColor = nil;
                }
            }
        }
    }
}

#pragma mark - NSTableViewDataSource & Delegate

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    if (tableView == _resultsTableView) {
        return _resultsDisplayItems.count;
    } else if (tableView == _episodesTableView) {
        return _currentSeasonVideos.count;
    } else if (tableView == _streamsTableView) {
        return _streamDisplayItems.count;
    }
    return 0;
}

- (BOOL)tableView:(NSTableView *)tableView isGroupRow:(NSInteger)row
{
    if (tableView == _resultsTableView) {
        return [_resultsDisplayItems[row] isKindOfClass:[NSString class]];
    } else if (tableView == _streamsTableView) {
        return [_streamDisplayItems[row] isKindOfClass:[NSString class]];
    }
    return NO;
}

- (BOOL)tableView:(NSTableView *)tableView shouldSelectRow:(NSInteger)row
{
    if (tableView == _resultsTableView) {
        return ![_resultsDisplayItems[row] isKindOfClass:[NSString class]];
    } else if (tableView == _streamsTableView) {
        return ![_streamDisplayItems[row] isKindOfClass:[NSString class]];
    }
    return YES;
}

- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row
{
    if (tableView == _resultsTableView) {
        if ([_resultsDisplayItems[row] isKindOfClass:[NSString class]]) {
            return 28.0;
        }
        return 48.0;
    } else if (tableView == _episodesTableView) {
        return 28.0;
    } else if (tableView == _streamsTableView) {
        if ([_streamDisplayItems[row] isKindOfClass:[NSString class]]) {
            return 28.0;
        }
        return 50.0;
    }
    return 32.0;
}

- (nullable NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(nullable NSTableColumn *)tableColumn row:(NSInteger)row
{
    if (tableView == _resultsTableView) {
        id item = _resultsDisplayItems[row];
        if ([item isKindOfClass:[NSString class]]) {
            NSTableCellView *groupView = [tableView makeViewWithIdentifier:kGroupCellIdentifier owner:self];
            if (!groupView) {
                groupView = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, 200, 28)];
                groupView.identifier = kGroupCellIdentifier;
                NSTextField *label = [NSTextField labelWithString:@""];
                label.translatesAutoresizingMaskIntoConstraints = NO;
                label.font = MacLCDesign.headline;
                label.textColor = MacLCDesign.secondaryLabel;
                [groupView addSubview:label];
                groupView.textField = label;

                [NSLayoutConstraint activateConstraints:@[
                    [label.leadingAnchor constraintEqualToAnchor:groupView.leadingAnchor constant:MacLCDesign.spacingS],
                    [label.centerYAnchor constraintEqualToAnchor:groupView.centerYAnchor],
                ]];
            }
            groupView.textField.stringValue = (NSString *)item;
            return groupView;
        }

        MacLCAddonItem *addonItem = (MacLCAddonItem *)item;
        MacLCAddonSearchResultCellView *cell = [tableView makeViewWithIdentifier:kResultCellIdentifier owner:self];
        if (!cell) {
            cell = [[MacLCAddonSearchResultCellView alloc] initWithFrame:NSMakeRect(0, 0, 200, 48)];
            cell.identifier = kResultCellIdentifier;
        }

        cell.titleLabel.stringValue = addonItem.name;
        cell.subtitleLabel.stringValue = addonItem.releaseInfo ?: @"";
        /* VoiceOver reads one row, not its parts. */
        cell.accessibilityLabel = addonItem.releaseInfo.length > 0
            ? [NSString stringWithFormat:@"%@, %@", addonItem.name, addonItem.releaseInfo] : addonItem.name;

        NSString *placeholderSymbol = [addonItem.type isEqualToString:@"movie"] ? @"film" : @"tv";
        NSImage *placeholder = [MacLCDesign symbolNamed:placeholderSymbol
                                              pointSize:16.0
                                                 weight:NSFontWeightRegular
                                     accessibilityLabel:nil];
        cell.posterImageView.image = placeholder;
        cell.posterImageView.contentTintColor = MacLCDesign.tertiaryLabel;

        if (addonItem.posterURL) {
            NSString *key = addonItem.posterURL.absoluteString;
            NSImage *cached = [_posterCache objectForKey:key];
            if (cached) {
                cell.posterImageView.image = cached;
                cell.posterImageView.contentTintColor = nil;
            } else {
                [self loadPosterForURL:addonItem.posterURL];
            }
        }

        return cell;
    } else if (tableView == _episodesTableView) {
        MacLCAddonVideo *video = _currentSeasonVideos[row];
        MacLCAddonSearchEpisodeCellView *cell = [tableView makeViewWithIdentifier:kEpisodeCellIdentifier owner:self];
        if (!cell) {
            cell = [[MacLCAddonSearchEpisodeCellView alloc] initWithFrame:NSMakeRect(0, 0, 200, 28)];
            cell.identifier = kEpisodeCellIdentifier;
        }

        if (video.episode > 0) {
            cell.numberLabel.stringValue = [NSString stringWithFormat:@"%ld", (long)video.episode];
            cell.numberWidthConstraint.constant = 20.0;
            cell.nameLeadingConstraint.constant = MacLCDesign.spacingS;
        } else {
            cell.numberLabel.stringValue = @"";
            cell.numberWidthConstraint.constant = 0.0;
            cell.nameLeadingConstraint.constant = 0.0;
        }

        if (video.name.length > 0) {
            cell.nameLabel.stringValue = video.name;
        } else if (video.episode > 0) {
            cell.nameLabel.stringValue = [NSString stringWithFormat:_NS("Episode %ld"), (long)video.episode];
        } else {
            cell.nameLabel.stringValue = @"";
        }

        if (video.released) {
            cell.dateLabel.stringValue = [[MacLCAddonSearchWindowController episodeDateFormatter] stringFromDate:video.released];
        } else {
            cell.dateLabel.stringValue = @"";
        }
        NSMutableArray<NSString *> * const spoken = [NSMutableArray array];
        if (video.episode > 0)
            [spoken addObject:[NSString stringWithFormat:_NS("Episode %ld"), (long)video.episode]];
        if (video.name.length > 0)
            [spoken addObject:video.name];
        if (cell.dateLabel.stringValue.length > 0)
            [spoken addObject:cell.dateLabel.stringValue];
        cell.accessibilityLabel = [spoken componentsJoinedByString:@", "];

        BOOL isFuture = video.released && ([video.released compare:[NSDate date]] == NSOrderedDescending);
        if (isFuture) {
            cell.numberLabel.textColor = MacLCDesign.tertiaryLabel;
            cell.nameLabel.textColor = MacLCDesign.tertiaryLabel;
            cell.dateLabel.textColor = MacLCDesign.tertiaryLabel;
        } else {
            cell.numberLabel.textColor = MacLCDesign.secondaryLabel;
            cell.nameLabel.textColor = MacLCDesign.primaryLabel;
            cell.dateLabel.textColor = MacLCDesign.secondaryLabel;
        }

        return cell;
    } else if (tableView == _streamsTableView) {
        id item = _streamDisplayItems[row];
        if ([item isKindOfClass:[NSString class]]) {
            NSTableCellView *groupView = [tableView makeViewWithIdentifier:kGroupCellIdentifier owner:self];
            if (!groupView) {
                groupView = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, 200, 28)];
                groupView.identifier = kGroupCellIdentifier;
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

        MacLCAddonStream *stream = (MacLCAddonStream *)item;
        MacLCAddonSearchStreamCellView *cell = [tableView makeViewWithIdentifier:kStreamCellIdentifier owner:self];
        if (!cell) {
            cell = [[MacLCAddonSearchStreamCellView alloc] initWithFrame:NSMakeRect(0, 0, 200, 50)];
            cell.identifier = kStreamCellIdentifier;
        }

        // Quality badges
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

        cell.primaryLabel.stringValue = stream.headline ?: @"";
        cell.secondaryLabel.stringValue = stream.details ?: @"";

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
    NSTableView *tableView = notification.object;
    if (tableView == _resultsTableView) {
        NSInteger row = _resultsTableView.selectedRow;
        if (row >= 0 && row < (NSInteger)_resultsDisplayItems.count) {
            id item = _resultsDisplayItems[row];
            if ([item isKindOfClass:[MacLCAddonItem class]]) {
                [self selectItem:(MacLCAddonItem *)item];
            }
        }
    } else if (tableView == _episodesTableView) {
        NSInteger row = _episodesTableView.selectedRow;
        if (row >= 0 && row < (NSInteger)_currentSeasonVideos.count
            && _currentSeasonVideos[row] != _selectedVideo) {
            _selectedVideo = _currentSeasonVideos[row];
            [self loadStreamsForType:_selectedItem.type videoIdentifier:_selectedVideo.identifier];
        }
    } else if (tableView == _streamsTableView) {
        NSInteger row = _streamsTableView.selectedRow;
        if (row >= 0 && row < (NSInteger)_streamDisplayItems.count) {
            id item = _streamDisplayItems[row];
            if ([item isKindOfClass:[MacLCAddonStream class]]) {
                _selectedStream = (MacLCAddonStream *)item;
            } else {
                _selectedStream = nil;
            }
        } else {
            _selectedStream = nil;
        }
        [self updateButtons];
    }
}

#pragma mark - NSToolbarDelegate

- (NSArray<NSToolbarItemIdentifier> *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar
{
    return @[
        NSToolbarFlexibleSpaceItemIdentifier,
        MacLCAddonSearchSearchToolbarItemIdentifier,
    ];
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar
{
    return @[
        NSToolbarFlexibleSpaceItemIdentifier,
        MacLCAddonSearchSearchToolbarItemIdentifier,
    ];
}

- (nullable NSToolbarItem *)toolbar:(NSToolbar *)toolbar
               itemForItemIdentifier:(NSToolbarItemIdentifier)itemIdentifier
           willBeInsertedIntoToolbar:(BOOL)flag
{
    if ([itemIdentifier isEqualToString:MacLCAddonSearchSearchToolbarItemIdentifier]) {
        return self.searchToolbarItem;
    }
    return nil;
}

@end
