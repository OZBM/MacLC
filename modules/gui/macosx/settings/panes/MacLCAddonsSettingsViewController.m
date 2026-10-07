/*****************************************************************************
 * MacLCAddonsSettingsViewController.m: the Add-ons settings pane
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

#import "settings/panes/MacLCAddonsSettingsViewController.h"
#import "addons/MacLCAddons.h"
#import "theme/MacLCDesign.h"
#import "theme/MacLCCardView.h"
#import "main/VLCMain.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnullability-completeness"
#import "extensions/NSString+Helpers.h"
#pragma clang diagnostic pop

#import <vlc_common.h>
#import <vlc_interface.h>

#pragma mark - Helper Functions

static NSString *MacLCDisplayNameForResource(NSString *resource)
{
    if ([resource isEqualToString:@"catalog"]) {
        return _NS("Catalogs");
    } else if ([resource isEqualToString:@"meta"]) {
        return _NS("Episodes");
    } else if ([resource isEqualToString:@"stream"]) {
        return _NS("Streams");
    } else if ([resource isEqualToString:@"subtitles"]) {
        return _NS("Subtitles");
    } else if ([resource isEqualToString:@"addon_catalog"]) {
        return _NS("Add-on Catalogs");
    }
    return resource.capitalizedString;
}

#pragma mark - Logo View

@interface MacLCAddonLogoView : NSImageView
@end

@implementation MacLCAddonLogoView

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.wantsLayer = YES;
        self.layer.masksToBounds = YES;
        self.layer.cornerRadius = 8.0;
        self.imageScaling = NSImageScaleProportionallyUpOrDown;
        self.accessibilityElement = NO;
        [self viewDidChangeEffectiveAppearance];
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

#pragma mark - Table Cell View

@interface MacLCAddonTableCellView : NSTableCellView

@property (nonatomic, strong) MacLCAddonLogoView *logoImageView;
@property (nonatomic, strong) NSTextField *nameLabel;
@property (nonatomic, strong) NSTextField *versionLabel;
@property (nonatomic, strong) NSTextField *descriptionLabel;
@property (nonatomic, strong) NSTextField *providesLabel;
@property (nonatomic, strong) NSStackView *buttonsStack;
@property (nonatomic, strong) NSButton *configureButton;
@property (nonatomic, strong) NSButton *removeButton;
@property (nonatomic, strong) NSButton *installButton;

@property (nonatomic, strong, nullable) MacLCAddon *addon;
@property (nonatomic, copy, nullable) void (^onConfigure)(MacLCAddon *addon);
@property (nonatomic, copy, nullable) void (^onRemove)(MacLCAddon *addon);
@property (nonatomic, copy, nullable) void (^onInstall)(MacLCAddon *addon);

- (void)configureWithAddon:(MacLCAddon *)addon
        isInstalledSegment:(BOOL)isInstalledSegment
               isInstalled:(BOOL)isInstalled
               cachedImage:(nullable NSImage *)cachedImage;

@end

@implementation MacLCAddonTableCellView

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        _logoImageView = [[MacLCAddonLogoView alloc] initWithFrame:NSZeroRect];
        [self addSubview:_logoImageView];

        NSStackView *textStack = [[NSStackView alloc] init];
        textStack.translatesAutoresizingMaskIntoConstraints = NO;
        textStack.orientation = NSUserInterfaceLayoutOrientationVertical;
        textStack.alignment = NSLayoutAttributeLeading;
        textStack.spacing = [MacLCDesign spacingXXS];
        /* A stack made with -init keeps the room of its hidden views. */
        textStack.detachesHiddenViews = YES;
        [self addSubview:textStack];

        NSStackView *titleRowStack = [[NSStackView alloc] init];
        titleRowStack.translatesAutoresizingMaskIntoConstraints = NO;
        titleRowStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
        titleRowStack.alignment = NSLayoutAttributeFirstBaseline;
        titleRowStack.spacing = [MacLCDesign spacingXS];
        titleRowStack.detachesHiddenViews = YES;
        [textStack addArrangedSubview:titleRowStack];

        _nameLabel = [NSTextField labelWithString:@""];
        _nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _nameLabel.font = [MacLCDesign headline];
        _nameLabel.textColor = [MacLCDesign primaryLabel];
        _nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [_nameLabel setContentHuggingPriority:NSLayoutPriorityDefaultHigh forOrientation:NSLayoutConstraintOrientationHorizontal];
        [_nameLabel setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
        [titleRowStack addArrangedSubview:_nameLabel];

        _versionLabel = [NSTextField labelWithString:@""];
        _versionLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _versionLabel.font = [MacLCDesign subheadline];
        _versionLabel.textColor = [MacLCDesign secondaryLabel];
        _versionLabel.lineBreakMode = NSLineBreakByClipping;
        [_versionLabel setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
        [_versionLabel setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
        [titleRowStack addArrangedSubview:_versionLabel];

        _descriptionLabel = [NSTextField labelWithString:@""];
        _descriptionLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _descriptionLabel.font = [MacLCDesign subheadline];
        _descriptionLabel.textColor = [MacLCDesign secondaryLabel];
        _descriptionLabel.maximumNumberOfLines = 2;
        _descriptionLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [_descriptionLabel setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
        [textStack addArrangedSubview:_descriptionLabel];

        _providesLabel = [NSTextField labelWithString:@""];
        _providesLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _providesLabel.font = [MacLCDesign footnote];
        /* Information, not decoration: secondary keeps small text above 4.5:1. */
        _providesLabel.textColor = [MacLCDesign secondaryLabel];
        _providesLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [_providesLabel setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
        [textStack addArrangedSubview:_providesLabel];

        _buttonsStack = [[NSStackView alloc] init];
        _buttonsStack.translatesAutoresizingMaskIntoConstraints = NO;
        _buttonsStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
        _buttonsStack.alignment = NSLayoutAttributeCenterY;
        _buttonsStack.spacing = [MacLCDesign spacingS];
        _buttonsStack.detachesHiddenViews = YES;
        [_buttonsStack setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
        [_buttonsStack setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
        [self addSubview:_buttonsStack];

        _configureButton = [NSButton buttonWithTitle:_NS("Configure…") target:self action:@selector(configureButtonClicked:)];
        _configureButton.bezelStyle = NSBezelStyleRounded;
        _configureButton.controlSize = NSControlSizeSmall;
        _configureButton.font = [NSFont systemFontOfSize:[NSFont systemFontSizeForControlSize:NSControlSizeSmall]];
        _configureButton.toolTip = _NS("Opens the add-on's own settings page. To apply them, install the address it gives you.");
        [_buttonsStack addView:_configureButton inGravity:NSStackViewGravityTrailing];

        _removeButton = [NSButton buttonWithTitle:_NS("Remove") target:self action:@selector(removeButtonClicked:)];
        _removeButton.bezelStyle = NSBezelStyleRounded;
        _removeButton.controlSize = NSControlSizeSmall;
        _removeButton.font = [NSFont systemFontOfSize:[NSFont systemFontSizeForControlSize:NSControlSizeSmall]];
        [_buttonsStack addView:_removeButton inGravity:NSStackViewGravityTrailing];

        _installButton = [NSButton buttonWithTitle:_NS("Install") target:self action:@selector(installButtonClicked:)];
        _installButton.bezelStyle = NSBezelStyleRounded;
        _installButton.controlSize = NSControlSizeSmall;
        _installButton.font = [NSFont systemFontOfSize:[NSFont systemFontSizeForControlSize:NSControlSizeSmall]];
        [_buttonsStack addView:_installButton inGravity:NSStackViewGravityTrailing];

        [NSLayoutConstraint activateConstraints:@[
            [_logoImageView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:[MacLCDesign spacingM]],
            [_logoImageView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_logoImageView.widthAnchor constraintEqualToConstant:36.0],
            [_logoImageView.heightAnchor constraintEqualToConstant:36.0],

            [_buttonsStack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-[MacLCDesign spacingM]],
            [_buttonsStack.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],

            [textStack.leadingAnchor constraintEqualToAnchor:_logoImageView.trailingAnchor constant:[MacLCDesign spacingM]],
            [textStack.trailingAnchor constraintLessThanOrEqualToAnchor:_buttonsStack.leadingAnchor constant:-[MacLCDesign spacingM]],
            [textStack.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [textStack.topAnchor constraintGreaterThanOrEqualToAnchor:self.topAnchor constant:[MacLCDesign spacingXS]],
            [textStack.bottomAnchor constraintLessThanOrEqualToAnchor:self.bottomAnchor constant:-[MacLCDesign spacingXS]],
        ]];
    }
    return self;
}

- (void)configureButtonClicked:(id)sender
{
    if (_onConfigure && _addon) {
        _onConfigure(_addon);
    }
}

- (void)removeButtonClicked:(id)sender
{
    if (_onRemove && _addon) {
        _onRemove(_addon);
    }
}

- (void)installButtonClicked:(id)sender
{
    if (_onInstall && _addon) {
        _onInstall(_addon);
    }
}

- (void)configureWithAddon:(MacLCAddon *)addon
        isInstalledSegment:(BOOL)isInstalledSegment
               isInstalled:(BOOL)isInstalled
               cachedImage:(nullable NSImage *)cachedImage
{
    _addon = addon;

    if (cachedImage) {
        _logoImageView.image = cachedImage;
        _logoImageView.contentTintColor = nil;
    } else {
        _logoImageView.image = [NSImage imageWithSystemSymbolName:@"puzzlepiece.extension" accessibilityDescription:nil];
        _logoImageView.contentTintColor = [MacLCDesign tertiaryLabel];
    }

    _nameLabel.stringValue = addon.name ?: @"";
    if (addon.version.length > 0) {
        _versionLabel.stringValue = addon.version;
        _versionLabel.hidden = NO;
    } else {
        _versionLabel.stringValue = @"";
        _versionLabel.hidden = YES;
    }

    if (addon.addonDescription.length > 0) {
        _descriptionLabel.stringValue = addon.addonDescription;
        _descriptionLabel.hidden = NO;
    } else {
        _descriptionLabel.stringValue = @"";
        _descriptionLabel.hidden = YES;
    }

    NSMutableArray<NSString *> *names = [NSMutableArray arrayWithCapacity:addon.resourceNames.count];
    for (NSString *res in addon.resourceNames) {
        [names addObject:MacLCDisplayNameForResource(res)];
    }
    NSString *provides = [names componentsJoinedByString:@" · "];
    if (provides.length > 0) {
        _providesLabel.stringValue = provides;
        _providesLabel.hidden = NO;
    } else {
        _providesLabel.stringValue = @"";
        _providesLabel.hidden = YES;
    }

    if (isInstalledSegment) {
        _installButton.hidden = YES;
        _configureButton.hidden = (addon.configureURL == nil);
        _removeButton.hidden = (!addon.isRemovable);
    } else {
        _configureButton.hidden = YES;
        _removeButton.hidden = YES;
        _installButton.hidden = NO;
        if (isInstalled) {
            _installButton.title = _NS("Installed");
            _installButton.enabled = NO;
        } else {
            _installButton.title = _NS("Install");
            _installButton.enabled = YES;
        }
    }

    NSMutableString *accLabel = [NSMutableString stringWithFormat:@"%@, %@", addon.name ?: @"", addon.version ?: @""];
    if (addon.addonDescription.length > 0) {
        [accLabel appendFormat:@", %@", addon.addonDescription];
    }
    self.accessibilityLabel = accLabel;
}

@end

#pragma mark - State View

@interface MacLCAddonsStateView : NSView

@property (nonatomic, strong) NSStackView *contentStack;
@property (nonatomic, strong) NSProgressIndicator *spinner;
@property (nonatomic, strong) NSImageView *iconView;
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSTextField *messageLabel;
@property (nonatomic, strong) NSButton *actionButton;

- (void)showIdle;
- (void)showLoading;
- (void)showEmptyWithTitle:(NSString *)title message:(NSString *)message;
- (void)showErrorWithTitle:(NSString *)title
                   message:(NSString *)message
               buttonTitle:(nullable NSString *)btnTitle
                    target:(nullable id)target
                    action:(nullable SEL)action;

@end

@implementation MacLCAddonsStateView

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;

        _contentStack = [[NSStackView alloc] initWithFrame:NSZeroRect];
        _contentStack.translatesAutoresizingMaskIntoConstraints = NO;
        _contentStack.orientation = NSUserInterfaceLayoutOrientationVertical;
        _contentStack.alignment = NSLayoutAttributeCenterX;
        _contentStack.spacing = [MacLCDesign spacingS];
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
        [_contentStack setCustomSpacing:[MacLCDesign spacingM] afterView:_iconView];

        _titleLabel = [NSTextField labelWithString:@""];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _titleLabel.alignment = NSTextAlignmentCenter;
        _titleLabel.font = [MacLCDesign headline];
        _titleLabel.textColor = [MacLCDesign primaryLabel];
        _titleLabel.maximumNumberOfLines = 2;
        _titleLabel.lineBreakMode = NSLineBreakByWordWrapping;
        [_contentStack addArrangedSubview:_titleLabel];
        [_contentStack setCustomSpacing:[MacLCDesign spacingXS] afterView:_titleLabel];

        _messageLabel = [NSTextField labelWithString:@""];
        _messageLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _messageLabel.alignment = NSTextAlignmentCenter;
        _messageLabel.font = [MacLCDesign subheadline];
        _messageLabel.textColor = [MacLCDesign secondaryLabel];
        _messageLabel.maximumNumberOfLines = 3;
        _messageLabel.lineBreakMode = NSLineBreakByWordWrapping;
        [_contentStack addArrangedSubview:_messageLabel];

        _actionButton = [NSButton buttonWithTitle:_NS("Try Again") target:nil action:nil];
        _actionButton.translatesAutoresizingMaskIntoConstraints = NO;
        _actionButton.bezelStyle = NSBezelStylePush;
        [_contentStack addArrangedSubview:_actionButton];
        [_contentStack setCustomSpacing:[MacLCDesign spacingM] afterView:_messageLabel];

        [NSLayoutConstraint activateConstraints:@[
            [_contentStack.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [_contentStack.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_contentStack.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.leadingAnchor constant:[MacLCDesign spacingL]],
            [_contentStack.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-[MacLCDesign spacingL]],
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
    self.hidden = NO;
    [_spinner stopAnimation:nil];
    _spinner.hidden = YES;
    _actionButton.hidden = YES;
    _iconView.hidden = YES;

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

#pragma mark - Addons Settings View Controller

@interface MacLCAddonsSettingsViewController () <NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSTextFieldDelegate>
{
    intf_thread_t *_p_intf;
}

@property (nonatomic, strong) NSSegmentedControl *segmentedControl;
@property (nonatomic, strong) NSSearchField *filterSearchField;
@property (nonatomic, strong) NSTableView *tableView;
@property (nonatomic, strong) MacLCAddonsStateView *stateView;
@property (nonatomic, strong) NSButton *installAddressButton;
@property (nonatomic, strong) NSButton *resetButton;

@property (nonatomic, strong) NSArray<MacLCAddon *> *currentSourceAddons;
@property (nonatomic, strong) NSArray<MacLCAddon *> *displayedAddons;
@property (nonatomic, assign) BOOL isInstalledSegment;
@property (nonatomic, strong, nullable) MacLCAddonCatalog *selectedCatalog;
@property (nonatomic, assign) BOOL isLoadingCatalog;
@property (nonatomic, strong, nullable) NSError *currentCatalogError;
@property (nonatomic, assign) BOOL didRefreshManifestsOnCurrentAppearance;

@property (nonatomic, strong, nullable) MacLCAddonRequest *activeCatalogRequest;
@property (nonatomic, strong, nullable) MacLCAddonRequest *activeInstallRequest;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSArray<MacLCAddon *> *> *catalogCache;
@property (nonatomic, strong) NSCache<NSString *, NSImage *> *logoCache;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSURLSessionDataTask *> *logoTasks;

@property (nonatomic, strong, nullable) NSWindow *installSheet;
@property (nonatomic, strong) NSTextField *addressTextField;
@property (nonatomic, strong) NSProgressIndicator *installSpinner;
@property (nonatomic, strong) NSImageView *installErrorIcon;
@property (nonatomic, strong) NSTextField *installStatusLabel;
@property (nonatomic, strong) NSButton *installCancelButton;
@property (nonatomic, strong) NSButton *installConfirmButton;
@property (nonatomic, assign) BOOL isInstalling;

@end

@implementation MacLCAddonsSettingsViewController

- (instancetype)initWithIntf:(intf_thread_t *)intf
{
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _p_intf = intf;
        [self commonInit];
    }
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (self) {
        _p_intf = getIntf();
        [self commonInit];
    }
    return self;
}

- (void)commonInit
{
    _logoCache = [[NSCache alloc] init];
    _logoCache.countLimit = 150;
    _logoTasks = [NSMutableDictionary dictionary];
    _catalogCache = [NSMutableDictionary dictionary];
    _currentSourceAddons = @[];
    _displayedAddons = @[];
    _isInstalledSegment = YES;

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(addonsDidChange:)
                                                 name:MacLCAddonsDidChangeNotification
                                               object:nil];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    for (NSURLSessionDataTask *task in _logoTasks.allValues) {
        [task cancel];
    }
    [_activeCatalogRequest cancel];
    [_activeInstallRequest cancel];
}

#pragma mark - MacLCSettingsPane Protocol Properties

- (NSString *)paneTitle
{
    return _NS("Add-ons");
}

- (NSString *)paneSymbolName
{
    return @"puzzlepiece.extension";
}

- (NSString *)paneIdentifier
{
    return @"addons";
}

- (NSArray<NSString *> *)searchKeywords
{
    return @[
        @"add-ons",
        @"addons",
        @"add-on",
        @"plugins",
        @"extensions",
        @"stremio",
        @"catalog",
        @"catalogs",
        @"streams",
        @"install",
        @"cinemeta",
        @"official",
        @"community"
    ];
}

- (BOOL)hasUnsavedChanges
{
    return NO;
}

- (void)applyChanges
{
    // Changes apply immediately
}

- (void)loadSettings
{
    [self reloadAddonsList];
    if (!_didRefreshManifestsOnCurrentAppearance) {
        _didRefreshManifestsOnCurrentAppearance = YES;
        [MacLCAddonStore.sharedStore refreshManifests];
    }
}

- (void)resetToDefaults
{
    [MacLCAddonStore.sharedStore resetToDefaults];
    [self loadSettings];
}

- (void)paneDidAppear
{
    /* Developer hook for headless checks: MACLC_DEBUG_ADDONS_SEGMENT=<n> shows
     * segment n (1 = the first add-on catalog). Unset, it does nothing. */
    const char * const debugSegment = getenv("MACLC_DEBUG_ADDONS_SEGMENT");
    if (debugSegment != NULL && atoi(debugSegment) < _segmentedControl.segmentCount) {
        _segmentedControl.selectedSegment = atoi(debugSegment);
        [self segmentedControlChanged:_segmentedControl];
    }
}

- (void)paneDidDisappear
{
    _didRefreshManifestsOnCurrentAppearance = NO;
    if (_activeCatalogRequest) {
        [_activeCatalogRequest cancel];
        _activeCatalogRequest = nil;
    }
    if (_activeInstallRequest) {
        [_activeInstallRequest cancel];
        _activeInstallRequest = nil;
    }
}

#pragma mark - View Layout

- (void)viewDidLayout
{
    [super viewDidLayout];
    /* The one column follows the table, so the row buttons sit at its trailing edge. */
    [_tableView sizeLastColumnToFit];
}

- (void)loadView
{
    NSView *container = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 600, 650)];
    container.translatesAutoresizingMaskIntoConstraints = NO;
    self.view = container;

    NSStackView *rootStack = [[NSStackView alloc] init];
    rootStack.translatesAutoresizingMaskIntoConstraints = NO;
    rootStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    rootStack.alignment = NSLayoutAttributeLeading;
    rootStack.spacing = [MacLCDesign groupSpacing];

    [container addSubview:rootStack];

    [NSLayoutConstraint activateConstraints:@[
        [rootStack.leadingAnchor constraintEqualToAnchor:container.leadingAnchor
                                                constant:[MacLCDesign windowContentMargin]],
        [rootStack.trailingAnchor constraintEqualToAnchor:container.trailingAnchor
                                                 constant:-[MacLCDesign windowContentMargin]],
        [rootStack.topAnchor constraintEqualToAnchor:container.topAnchor
                                            constant:[MacLCDesign windowContentMargin]],
        [rootStack.bottomAnchor constraintEqualToAnchor:container.bottomAnchor
                                               constant:-[MacLCDesign windowContentMargin]],
        [container.widthAnchor constraintGreaterThanOrEqualToConstant:480]
    ]];

    // Card: "Add-ons"
    MacLCCardView *addonsCard = [MacLCCardView cardViewWithTitle:nil];
    addonsCard.translatesAutoresizingMaskIntoConstraints = NO;
    [rootStack addArrangedSubview:addonsCard];
    [addonsCard.trailingAnchor constraintEqualToAnchor:rootStack.trailingAnchor].active = YES;

    // 1. Explanation
    NSTextField *explanationLabel = [NSTextField wrappingLabelWithString:_NS("Add-ons are third-party services, as in Stremio: some list movies and series, others find streams to play. MacLC sends them the titles you look up, and other people in a torrent can see your IP address. Install only add-ons you trust.")];
    explanationLabel.translatesAutoresizingMaskIntoConstraints = NO;
    explanationLabel.font = [MacLCDesign subheadline];
    explanationLabel.textColor = [MacLCDesign secondaryLabel];
    [addonsCard.contentStackView addArrangedSubview:explanationLabel];

    // 2. Row: Segmented control + Filter search field
    NSView *filterRowView = [[NSView alloc] initWithFrame:NSZeroRect];
    filterRowView.translatesAutoresizingMaskIntoConstraints = NO;

    _segmentedControl = [NSSegmentedControl segmentedControlWithLabels:@[_NS("Installed")]
                                                          trackingMode:NSSegmentSwitchTrackingSelectOne
                                                                target:self
                                                                action:@selector(segmentedControlChanged:)];
    _segmentedControl.translatesAutoresizingMaskIntoConstraints = NO;
    _segmentedControl.selectedSegment = 0;
    [filterRowView addSubview:_segmentedControl];

    _filterSearchField = [[NSSearchField alloc] initWithFrame:NSZeroRect];
    _filterSearchField.translatesAutoresizingMaskIntoConstraints = NO;
    _filterSearchField.placeholderString = _NS("Filter");
    _filterSearchField.delegate = self;
    [filterRowView addSubview:_filterSearchField];

    [NSLayoutConstraint activateConstraints:@[
        [_segmentedControl.leadingAnchor constraintEqualToAnchor:filterRowView.leadingAnchor],
        [_segmentedControl.centerYAnchor constraintEqualToAnchor:filterRowView.centerYAnchor],
        [_segmentedControl.trailingAnchor constraintLessThanOrEqualToAnchor:_filterSearchField.leadingAnchor constant:-[MacLCDesign spacingM]],

        [_filterSearchField.trailingAnchor constraintEqualToAnchor:filterRowView.trailingAnchor],
        [_filterSearchField.centerYAnchor constraintEqualToAnchor:filterRowView.centerYAnchor],
        [_filterSearchField.widthAnchor constraintEqualToConstant:180.0],

        [filterRowView.heightAnchor constraintGreaterThanOrEqualToAnchor:_segmentedControl.heightAnchor],
        [filterRowView.heightAnchor constraintGreaterThanOrEqualToAnchor:_filterSearchField.heightAnchor],
    ]];

    [addonsCard.contentStackView addArrangedSubview:filterRowView];

    // 3. View-based table inside scroll view with StateView overlay
    NSView *tableContainer = [[NSView alloc] initWithFrame:NSZeroRect];
    tableContainer.translatesAutoresizingMaskIntoConstraints = NO;

    NSScrollView *tableScrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    tableScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    tableScrollView.hasVerticalScroller = YES;
    tableScrollView.autohidesScrollers = YES;
    tableScrollView.borderType = NSNoBorder;
    tableScrollView.drawsBackground = NO;

    /* A scroll view's document view sizes itself by autoresizing: no
     * translatesAutoresizingMaskIntoConstraints = NO, or it shrinks to its column. */
    _tableView = [[NSTableView alloc] initWithFrame:NSZeroRect];
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.headerView = nil;
    _tableView.rowHeight = 64.0;
    _tableView.backgroundColor = NSColor.clearColor;
    /* A column made in code keeps its default width unless told to follow the table. */
    _tableView.columnAutoresizingStyle = NSTableViewLastColumnOnlyAutoresizingStyle;
    _tableView.accessibilityLabel = _NS("Add-ons");
    if (@available(macOS 11.0, *)) {
        _tableView.style = NSTableViewStyleInset;
    }

    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"addon"];
    column.resizingMask = NSTableColumnAutoresizingMask;
    [_tableView addTableColumn:column];

    tableScrollView.documentView = _tableView;
    [tableContainer addSubview:tableScrollView];

    _stateView = [[MacLCAddonsStateView alloc] initWithFrame:NSZeroRect];
    [tableContainer addSubview:_stateView];

    [NSLayoutConstraint activateConstraints:@[
        [tableScrollView.leadingAnchor constraintEqualToAnchor:tableContainer.leadingAnchor],
        [tableScrollView.trailingAnchor constraintEqualToAnchor:tableContainer.trailingAnchor],
        [tableScrollView.topAnchor constraintEqualToAnchor:tableContainer.topAnchor],
        [tableScrollView.bottomAnchor constraintEqualToAnchor:tableContainer.bottomAnchor],
        [tableScrollView.heightAnchor constraintEqualToConstant:340.0],

        [_stateView.leadingAnchor constraintEqualToAnchor:tableContainer.leadingAnchor],
        [_stateView.trailingAnchor constraintEqualToAnchor:tableContainer.trailingAnchor],
        [_stateView.topAnchor constraintEqualToAnchor:tableContainer.topAnchor],
        [_stateView.bottomAnchor constraintEqualToAnchor:tableContainer.bottomAnchor],
    ]];

    [addonsCard.contentStackView addArrangedSubview:tableContainer];

    // 4. Under the table, leading: "Install from Address…"
    _installAddressButton = [NSButton buttonWithTitle:_NS("Install from Address…")
                                               target:self
                                               action:@selector(showInstallAddressSheet:)];
    _installAddressButton.translatesAutoresizingMaskIntoConstraints = NO;
    _installAddressButton.bezelStyle = NSBezelStyleRounded;
    /* Card rows are stretched to the card's width: hold the button in a row. */
    NSView *installRow = [[NSView alloc] initWithFrame:NSZeroRect];
    installRow.translatesAutoresizingMaskIntoConstraints = NO;
    [installRow addSubview:_installAddressButton];
    [NSLayoutConstraint activateConstraints:@[
        [_installAddressButton.leadingAnchor constraintEqualToAnchor:installRow.leadingAnchor],
        [_installAddressButton.topAnchor constraintEqualToAnchor:installRow.topAnchor],
        [_installAddressButton.bottomAnchor constraintEqualToAnchor:installRow.bottomAnchor],
        [_installAddressButton.trailingAnchor constraintLessThanOrEqualToAnchor:installRow.trailingAnchor],
    ]];
    [addonsCard.contentStackView addArrangedSubview:installRow];

    // Card bottom: "Restore Default Add-ons…"
    _resetButton = [NSButton buttonWithTitle:_NS("Restore Default Add-ons…")
                                      target:self
                                      action:@selector(restoreDefaultsAction:)];
    _resetButton.translatesAutoresizingMaskIntoConstraints = NO;
    _resetButton.bezelStyle = NSBezelStyleRounded;
    [rootStack addArrangedSubview:_resetButton];

    // Key view loop
    _segmentedControl.nextKeyView = _filterSearchField;
    _filterSearchField.nextKeyView = _tableView;
    _tableView.nextKeyView = _installAddressButton;
    _installAddressButton.nextKeyView = _resetButton;
    _resetButton.nextKeyView = _segmentedControl;

    [self loadSettings];
}

#pragma mark - Catalog Keys & Presentation

- (NSString *)catalogKeyForCatalog:(MacLCAddonCatalog *)catalog
{
    return [NSString stringWithFormat:@"%@/%@/%@", catalog.addon.identifier, catalog.type, catalog.identifier];
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
            message = [NSString stringWithFormat:_NS("The add-on answered with error %ld. Try again in a moment."), code];
        } else if (error.code == MacLCAddonsErrorBadResponse || error.code == MacLCAddonsErrorNotAnAddon) {
            title = [NSString stringWithFormat:_NS("Unexpected Answer from %@"), serviceName];
            message = _NS("The add-on answered with invalid data.");
        }
    }

    if (!title) {
        title = [NSString stringWithFormat:_NS("Can't Reach %@"), serviceName];
        message = _NS("Check your internet connection, then try again.");
    }

    if (outTitle) *outTitle = title;
    if (outMessage) *outMessage = message;
}

#pragma mark - List & Filter Management

- (void)addonsDidChange:(NSNotification *)notification
{
    /* Posted on the main queue: reload now, before an install's completion
     * selects the new row (a deferred reload wiped that selection). */
    [self reloadAddonsList];
}

- (void)reloadAddonsList
{
    MacLCAddonStore *store = MacLCAddonStore.sharedStore;
    NSArray<MacLCAddonCatalog *> *catalogs = store.addonCatalogs;

    NSCountedSet<NSString *> *nameCounts = [[NSCountedSet alloc] init];
    for (MacLCAddonCatalog *cat in catalogs) {
        if (cat.name.length > 0) {
            [nameCounts addObject:cat.name];
        }
    }

    NSInteger previousSegment = _segmentedControl.selectedSegment;
    NSString *previousCatalogKey = (_selectedCatalog != nil) ? [self catalogKeyForCatalog:_selectedCatalog] : nil;

    NSInteger totalSegments = 1 + catalogs.count;
    _segmentedControl.segmentCount = totalSegments;
    [_segmentedControl setLabel:_NS("Installed") forSegment:0];

    NSInteger newCatalogSegment = -1;
    for (NSUInteger i = 0; i < catalogs.count; i++) {
        MacLCAddonCatalog *cat = catalogs[i];
        NSString *label = cat.name ?: @"";
        if ([nameCounts countForObject:label] > 1) {
            label = [NSString stringWithFormat:@"%@ — %@", label, cat.addon.name];
        }
        [_segmentedControl setLabel:label forSegment:i + 1];

        if (previousCatalogKey && [[self catalogKeyForCatalog:cat] isEqualToString:previousCatalogKey]) {
            newCatalogSegment = (NSInteger)i + 1;
        }
    }

    if (previousSegment <= 0 || newCatalogSegment == -1) {
        _segmentedControl.selectedSegment = 0;
        _isInstalledSegment = YES;
        _selectedCatalog = nil;
        _currentCatalogError = nil;
        _isLoadingCatalog = NO;
        _currentSourceAddons = [store.installedAddons copy];
        [self updateFilteredList];
    } else {
        _segmentedControl.selectedSegment = newCatalogSegment;
        _isInstalledSegment = NO;
        _selectedCatalog = catalogs[newCatalogSegment - 1];
        NSString *key = [self catalogKeyForCatalog:_selectedCatalog];
        NSArray<MacLCAddon *> *cached = _catalogCache[key];
        if (cached) {
            _currentSourceAddons = cached;
            _currentCatalogError = nil;
            _isLoadingCatalog = NO;
            [self updateFilteredList];
        } else {
            [self fetchCatalog:_selectedCatalog];
        }
    }
}

- (void)segmentedControlChanged:(id)sender
{
    NSInteger selected = _segmentedControl.selectedSegment;
    if (selected <= 0) {
        _isInstalledSegment = YES;
        _selectedCatalog = nil;
        _currentCatalogError = nil;
        _isLoadingCatalog = NO;
        if (_activeCatalogRequest) {
            [_activeCatalogRequest cancel];
            _activeCatalogRequest = nil;
        }
        _currentSourceAddons = [MacLCAddonStore.sharedStore.installedAddons copy];
        [self updateFilteredList];
    } else {
        _isInstalledSegment = NO;
        NSArray<MacLCAddonCatalog *> *catalogs = MacLCAddonStore.sharedStore.addonCatalogs;
        NSInteger catalogIndex = selected - 1;
        if (catalogIndex >= 0 && catalogIndex < (NSInteger)catalogs.count) {
            MacLCAddonCatalog *catalog = catalogs[catalogIndex];
            _selectedCatalog = catalog;
            NSString *catalogKey = [self catalogKeyForCatalog:catalog];
            NSArray<MacLCAddon *> *cached = _catalogCache[catalogKey];
            if (cached) {
                _currentSourceAddons = cached;
                _currentCatalogError = nil;
                _isLoadingCatalog = NO;
                if (_activeCatalogRequest) {
                    [_activeCatalogRequest cancel];
                    _activeCatalogRequest = nil;
                }
                [self updateFilteredList];
            } else {
                [self fetchCatalog:catalog];
            }
        }
    }
}

- (void)fetchCatalog:(MacLCAddonCatalog *)catalog
{
    if (_activeCatalogRequest) {
        [_activeCatalogRequest cancel];
        _activeCatalogRequest = nil;
    }
    _isLoadingCatalog = YES;
    _currentCatalogError = nil;
    _currentSourceAddons = @[];
    [self updateFilteredList];

    NSString *catalogKey = [self catalogKeyForCatalog:catalog];
    __weak typeof(self) weakSelf = self;
    _activeCatalogRequest = [MacLCAddonStore.sharedStore fetchAddonCatalog:catalog completion:^(NSArray<MacLCAddon *> * _Nullable addons, NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        strongSelf->_activeCatalogRequest = nil;
        strongSelf->_isLoadingCatalog = NO;

        if (strongSelf->_isInstalledSegment || strongSelf->_selectedCatalog != catalog) {
            return;
        }

        if (error) {
            strongSelf->_currentCatalogError = error;
            strongSelf->_currentSourceAddons = @[];
            [strongSelf updateFilteredList];
        } else {
            strongSelf->_currentCatalogError = nil;
            strongSelf->_catalogCache[catalogKey] = addons ?: @[];
            strongSelf->_currentSourceAddons = addons ?: @[];
            [strongSelf updateFilteredList];
        }
    }];
}

- (void)retryCatalogFetch:(id)sender
{
    if (_selectedCatalog) {
        NSString *catalogKey = [self catalogKeyForCatalog:_selectedCatalog];
        [_catalogCache removeObjectForKey:catalogKey];
        [self fetchCatalog:_selectedCatalog];
    }
}

- (void)updateFilteredList
{
    NSString *search = [_filterSearchField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].lowercaseString;

    if (search.length == 0) {
        _displayedAddons = [_currentSourceAddons copy];
    } else {
        NSMutableArray<MacLCAddon *> *filtered = [NSMutableArray array];
        for (MacLCAddon *addon in _currentSourceAddons) {
            BOOL match = NO;
            if ([addon.name.lowercaseString containsString:search]) {
                match = YES;
            } else if (addon.addonDescription && [addon.addonDescription.lowercaseString containsString:search]) {
                match = YES;
            }
            if (match) {
                [filtered addObject:addon];
            }
        }
        _displayedAddons = [filtered copy];
    }

    [_tableView reloadData];

    if (_isLoadingCatalog) {
        [_stateView showLoading];
    } else if (_currentCatalogError) {
        NSString *errTitle = nil;
        NSString *errMsg = nil;
        [self getErrorTitle:&errTitle message:&errMsg forError:_currentCatalogError service:_selectedCatalog.addon.name];
        [_stateView showErrorWithTitle:errTitle
                               message:errMsg
                           buttonTitle:_NS("Try Again")
                                target:self
                                action:@selector(retryCatalogFetch:)];
    } else if (_displayedAddons.count == 0) {
        [_stateView showEmptyWithTitle:_NS("No Add-ons") message:@""];
    } else {
        [_stateView showIdle];
    }
}

- (void)controlTextDidChange:(NSNotification *)obj
{
    id sender = obj.object;
    if (sender == _filterSearchField) {
        [self updateFilteredList];
    } else if (sender == _addressTextField) {
        NSString *trimmed = [_addressTextField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        _installConfirmButton.enabled = (trimmed.length > 0 && !_isInstalling);
        if (!_installErrorIcon.isHidden) {
            _installErrorIcon.hidden = YES;
            _installStatusLabel.stringValue = @"";
            _installStatusLabel.hidden = YES;
        }
    }
}

#pragma mark - Table View Data Source & Delegate

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    return (NSInteger)_displayedAddons.count;
}

- (nullable NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(nullable NSTableColumn *)tableColumn row:(NSInteger)row
{
    if (row < 0 || row >= (NSInteger)_displayedAddons.count) {
        return nil;
    }

    MacLCAddon *addon = _displayedAddons[row];
    MacLCAddonTableCellView *cell = [tableView makeViewWithIdentifier:@"MacLCAddonCell" owner:self];
    if (!cell) {
        cell = [[MacLCAddonTableCellView alloc] initWithFrame:NSZeroRect];
        cell.identifier = @"MacLCAddonCell";
    }

    NSImage *cached = nil;
    if (addon.logoURL) {
        cached = [_logoCache objectForKey:addon.logoURL.absoluteString];
        if (!cached) {
            [self loadLogoForURL:addon.logoURL];
        }
    }

    BOOL installed = [MacLCAddonStore.sharedStore isInstalled:addon.identifier];
    [cell configureWithAddon:addon
          isInstalledSegment:_isInstalledSegment
                 isInstalled:installed
                 cachedImage:cached];

    __weak typeof(self) weakSelf = self;
    cell.onConfigure = ^(MacLCAddon *a) {
        if (a.configureURL) {
            [[NSWorkspace sharedWorkspace] openURL:a.configureURL];
        }
    };
    cell.onRemove = ^(MacLCAddon *a) {
        [weakSelf promptRemoveAddon:a];
    };
    cell.onInstall = ^(MacLCAddon *a) {
        [weakSelf installCatalogAddon:a];
    };

    return cell;
}

#pragma mark - Logo Loading

- (void)loadLogoForURL:(NSURL *)url
{
    if (!url) return;
    NSString *key = url.absoluteString;
    if (!key) return;

    if ([_logoCache objectForKey:key] != nil || _logoTasks[key] != nil) {
        return;
    }

    __weak typeof(self) weakSelf = self;
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;

            [strongSelf->_logoTasks removeObjectForKey:key];
            if (data) {
                NSImage *img = [[NSImage alloc] initWithData:data];
                if (img) {
                    [strongSelf->_logoCache setObject:img forKey:key];
                    [strongSelf applyLogoImage:img forURLString:key];
                }
            }
        });
    }];
    _logoTasks[key] = task;
    [task resume];
}

- (void)applyLogoImage:(NSImage *)image forURLString:(NSString *)urlString
{
    NSInteger count = _tableView.numberOfRows;
    for (NSInteger i = 0; i < count; i++) {
        MacLCAddonTableCellView *cell = [_tableView viewAtColumn:0 row:i makeIfNecessary:NO];
        if (cell && [cell.addon.logoURL.absoluteString isEqualToString:urlString]) {
            cell.logoImageView.image = image;
            cell.logoImageView.contentTintColor = nil;
        }
    }
}

#pragma mark - Actions

- (void)installCatalogAddon:(MacLCAddon *)addon
{
    MacLCAddonStore *store = MacLCAddonStore.sharedStore;
    BOOL replaced = [store isInstalled:addon.identifier];
    [store installAddon:addon];

    intf_thread_t *p_intf = _p_intf ?: getIntf();
    if (p_intf) {
        msg_Dbg(p_intf, "addons: installed \"%s\" %s from %s%s",
                addon.name.UTF8String,
                addon.version.UTF8String,
                addon.transportURL.UTF8String,
                replaced ? " (replaced)" : "");
    }
}

- (void)promptRemoveAddon:(MacLCAddon *)addon
{
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = [NSString stringWithFormat:_NS("Remove “%@”?"), addon.name];
    alert.informativeText = _NS("You can install it again from a catalog or from its address.");
    NSButton *removeButton = [alert addButtonWithTitle:_NS("Remove")];
    if (@available(macOS 11.0, *)) {
        removeButton.hasDestructiveAction = YES;
    }
    [alert addButtonWithTitle:_NS("Cancel")];

    NSWindow *parentWindow = self.view.window;
    __weak typeof(self) weakSelf = self;
    void (^handler)(NSModalResponse) = ^(NSModalResponse returnCode) {
        if (returnCode == NSAlertFirstButtonReturn) {
            [MacLCAddonStore.sharedStore removeAddon:addon];
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf) {
                intf_thread_t *p_intf = strongSelf->_p_intf ?: getIntf();
                if (p_intf) {
                    msg_Dbg(p_intf, "addons: removed \"%s\"", addon.name.UTF8String);
                }
            }
        }
    };

    if (parentWindow) {
        [alert beginSheetModalForWindow:parentWindow completionHandler:handler];
    } else {
        handler([alert runModal]);
    }
}

- (void)restoreDefaultsAction:(id)sender
{
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = _NS("Remove All the Add-ons You Installed?");
    alert.informativeText = _NS("Cinemeta stays.");
    NSButton *removeButton = [alert addButtonWithTitle:_NS("Remove Add-ons")];
    if (@available(macOS 11.0, *)) {
        removeButton.hasDestructiveAction = YES;
    }
    [alert addButtonWithTitle:_NS("Cancel")];

    NSWindow *parentWindow = self.view.window;
    __weak typeof(self) weakSelf = self;
    void (^handler)(NSModalResponse) = ^(NSModalResponse returnCode) {
        if (returnCode == NSAlertFirstButtonReturn) {
            [weakSelf resetToDefaults];
        }
    };

    if (parentWindow) {
        [alert beginSheetModalForWindow:parentWindow completionHandler:handler];
    } else {
        handler([alert runModal]);
    }
}

#pragma mark - Install from Address Sheet

- (void)setupInstallSheet
{
    _installSheet = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 420, 220)
                                                styleMask:NSWindowStyleMaskTitled
                                                  backing:NSBackingStoreBuffered
                                                    defer:NO];
    _installSheet.title = _NS("Install an Add-on");

    NSView *content = _installSheet.contentView;

    NSStackView *sheetStack = [[NSStackView alloc] init];
    sheetStack.translatesAutoresizingMaskIntoConstraints = NO;
    sheetStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    sheetStack.alignment = NSLayoutAttributeLeading;
    sheetStack.spacing = [MacLCDesign spacingM];
    [content addSubview:sheetStack];

    [NSLayoutConstraint activateConstraints:@[
        [sheetStack.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:[MacLCDesign windowContentMargin]],
        [sheetStack.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-[MacLCDesign windowContentMargin]],
        [sheetStack.topAnchor constraintEqualToAnchor:content.topAnchor constant:[MacLCDesign windowContentMargin]],
        [sheetStack.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-[MacLCDesign windowContentMargin]],
    ]];

    NSTextField *titleLabel = [NSTextField labelWithString:_NS("Install an Add-on")];
    titleLabel.font = [MacLCDesign headline];
    titleLabel.textColor = [MacLCDesign primaryLabel];
    [sheetStack addArrangedSubview:titleLabel];

    NSTextField *messageLabel = [NSTextField wrappingLabelWithString:_NS("Paste the address of a Stremio-compatible add-on. It usually ends with manifest.json.")];
    messageLabel.font = [MacLCDesign subheadline];
    messageLabel.textColor = [MacLCDesign secondaryLabel];
    [sheetStack addArrangedSubview:messageLabel];
    [messageLabel.trailingAnchor constraintEqualToAnchor:sheetStack.trailingAnchor].active = YES;

    _addressTextField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    _addressTextField.translatesAutoresizingMaskIntoConstraints = NO;
    _addressTextField.placeholderString = @"https://example.com/manifest.json";
    _addressTextField.delegate = self;
    _addressTextField.target = self;
    _addressTextField.action = @selector(addressFieldSubmitted:);
    [sheetStack addArrangedSubview:_addressTextField];
    [_addressTextField.widthAnchor constraintEqualToAnchor:sheetStack.widthAnchor].active = YES;

    NSStackView *statusStack = [[NSStackView alloc] init];
    statusStack.translatesAutoresizingMaskIntoConstraints = NO;
    statusStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    statusStack.alignment = NSLayoutAttributeCenterY;
    statusStack.spacing = [MacLCDesign spacingXS];

    _installSpinner = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
    _installSpinner.translatesAutoresizingMaskIntoConstraints = NO;
    _installSpinner.style = NSProgressIndicatorStyleSpinning;
    _installSpinner.controlSize = NSControlSizeSmall;
    _installSpinner.displayedWhenStopped = NO;
    [statusStack addArrangedSubview:_installSpinner];

    _installErrorIcon = [[NSImageView alloc] initWithFrame:NSZeroRect];
    _installErrorIcon.translatesAutoresizingMaskIntoConstraints = NO;
    _installErrorIcon.image = [NSImage imageWithSystemSymbolName:@"exclamationmark.triangle" accessibilityDescription:nil];
    _installErrorIcon.contentTintColor = [MacLCDesign secondaryLabel];
    _installErrorIcon.accessibilityElement = NO;
    _installErrorIcon.hidden = YES;
    [statusStack addArrangedSubview:_installErrorIcon];

    _installStatusLabel = [NSTextField wrappingLabelWithString:@""];
    _installStatusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _installStatusLabel.font = [MacLCDesign subheadline];
    _installStatusLabel.textColor = [MacLCDesign secondaryLabel];
    _installStatusLabel.hidden = YES;
    [statusStack addArrangedSubview:_installStatusLabel];

    [sheetStack addArrangedSubview:statusStack];
    [statusStack.trailingAnchor constraintLessThanOrEqualToAnchor:sheetStack.trailingAnchor].active = YES;

    NSStackView *btnStack = [[NSStackView alloc] init];
    btnStack.translatesAutoresizingMaskIntoConstraints = NO;
    btnStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    btnStack.alignment = NSLayoutAttributeCenterY;
    btnStack.spacing = [MacLCDesign spacingM];

    _installCancelButton = [NSButton buttonWithTitle:_NS("Cancel") target:self action:@selector(cancelInstallSheet:)];
    _installCancelButton.bezelStyle = NSBezelStyleRounded;
    _installCancelButton.keyEquivalent = @"\e";
    /* Dialog buttons sit at the trailing edge. */
    [btnStack addView:_installCancelButton inGravity:NSStackViewGravityTrailing];

    _installConfirmButton = [NSButton buttonWithTitle:_NS("Install") target:self action:@selector(confirmInstallSheet:)];
    _installConfirmButton.bezelStyle = NSBezelStyleRounded;
    _installConfirmButton.keyEquivalent = @"\r";
    _installConfirmButton.enabled = NO;
    [btnStack addView:_installConfirmButton inGravity:NSStackViewGravityTrailing];

    [sheetStack addArrangedSubview:btnStack];
    [btnStack.trailingAnchor constraintEqualToAnchor:sheetStack.trailingAnchor].active = YES;

    _addressTextField.nextKeyView = _installConfirmButton;
    _installConfirmButton.nextKeyView = _installCancelButton;
    _installCancelButton.nextKeyView = _addressTextField;
}

- (void)showInstallAddressSheet:(id)sender
{
    if (!_installSheet) {
        [self setupInstallSheet];
    }
    _addressTextField.stringValue = @"";
    _addressTextField.enabled = YES;
    [_installSpinner stopAnimation:nil];
    _installSpinner.hidden = YES;
    _installErrorIcon.hidden = YES;
    _installStatusLabel.stringValue = @"";
    _installStatusLabel.hidden = YES;
    _installConfirmButton.enabled = NO;
    _isInstalling = NO;

    NSWindow *parentWindow = self.view.window;
    if (parentWindow) {
        [parentWindow beginSheet:_installSheet completionHandler:nil];
        [_installSheet makeFirstResponder:_addressTextField];
    }
}

- (void)cancelInstallSheet:(id)sender
{
    if (_activeInstallRequest) {
        [_activeInstallRequest cancel];
        _activeInstallRequest = nil;
    }
    _isInstalling = NO;
    NSWindow *parentWindow = self.view.window;
    if (parentWindow && _installSheet) {
        [parentWindow endSheet:_installSheet returnCode:NSModalResponseCancel];
        [_installSheet orderOut:nil];
    }
}

- (void)addressFieldSubmitted:(id)sender
{
    if (_installConfirmButton.isEnabled && !_isInstalling) {
        [self confirmInstallSheet:sender];
    }
}

- (void)confirmInstallSheet:(id)sender
{
    NSString *rawAddress = _addressTextField.stringValue;
    NSString *trimmed = [rawAddress stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0 || _isInstalling) {
        return;
    }

    _isInstalling = YES;
    _installConfirmButton.enabled = NO;
    _addressTextField.enabled = NO;
    _installErrorIcon.hidden = YES;
    _installStatusLabel.stringValue = _NS("Installing…");
    _installStatusLabel.textColor = [MacLCDesign secondaryLabel];
    _installStatusLabel.hidden = NO;
    _installSpinner.hidden = NO;
    [_installSpinner startAnimation:nil];

    __weak typeof(self) weakSelf = self;
    _activeInstallRequest = [MacLCAddonStore.sharedStore installFromAddress:trimmed completion:^(MacLCAddon * _Nullable addon, BOOL replaced, NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        strongSelf->_activeInstallRequest = nil;
        strongSelf->_isInstalling = NO;
        strongSelf->_addressTextField.enabled = YES;
        [strongSelf->_installSpinner stopAnimation:nil];
        strongSelf->_installSpinner.hidden = YES;

        if (error) {
            [strongSelf handleInstallError:error];
            strongSelf->_installConfirmButton.enabled = YES;
            return;
        }

        if (addon) {
            intf_thread_t *p_intf = strongSelf->_p_intf ?: getIntf();
            if (p_intf) {
                msg_Dbg(p_intf, "addons: installed \"%s\" %s from %s%s",
                        addon.name.UTF8String,
                        addon.version.UTF8String,
                        addon.transportURL.UTF8String,
                        replaced ? " (replaced)" : "");
            }

            NSWindow *parentWindow = strongSelf.view.window;
            if (parentWindow && strongSelf->_installSheet) {
                [parentWindow endSheet:strongSelf->_installSheet returnCode:NSModalResponseOK];
                [strongSelf->_installSheet orderOut:nil];
            }

            strongSelf->_filterSearchField.stringValue = @"";
            strongSelf->_segmentedControl.selectedSegment = 0;
            [strongSelf segmentedControlChanged:strongSelf->_segmentedControl];

            NSString *targetID = addon.identifier;
            NSInteger targetRow = -1;
            for (NSInteger i = 0; i < (NSInteger)strongSelf->_displayedAddons.count; i++) {
                if ([strongSelf->_displayedAddons[i].identifier isEqualToString:targetID]) {
                    targetRow = i;
                    break;
                }
            }
            if (targetRow >= 0) {
                [strongSelf->_tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:targetRow] byExtendingSelection:NO];
                [strongSelf->_tableView scrollRowToVisible:targetRow];
            }
        }
    }];
}

- (void)handleInstallError:(NSError *)error
{
    intf_thread_t *p_intf = _p_intf ?: getIntf();

    NSString *errorMsg = nil;
    if ([error.domain isEqualToString:MacLCAddonsErrorDomain]) {
        if (error.code == MacLCAddonsErrorBadAddress) {
            errorMsg = _NS("This is not an add-on address.");
        } else if (error.code == MacLCAddonsErrorNotAnAddon || error.code == MacLCAddonsErrorBadResponse) {
            errorMsg = _NS("This address doesn't lead to an add-on.");
        } else if (error.code == MacLCAddonsErrorHTTPStatus) {
            NSNumber *status = error.userInfo[@"status"];
            long code = status ? status.longValue : 0;
            errorMsg = [NSString stringWithFormat:_NS("The add-on answered with error %ld."), code];
        }
    } else if (MacLCAddonsUnresolvedHost(error)) {
        errorMsg = [NSString stringWithFormat:_NS("Can't find the server “%@”. Check your network settings."), MacLCAddonsUnresolvedHost(error)];
    } else if ([error.domain isEqualToString:NSURLErrorDomain]) {
        errorMsg = _NS("Can't reach this address. Check your internet connection.");
    }

    if (!errorMsg) {
        errorMsg = error.localizedDescription ?: _NS("This address doesn't lead to an add-on.");
    }

    if (p_intf) {
        msg_Warn(p_intf, "addons: install failed: %s", errorMsg.UTF8String);
    }

    _installErrorIcon.hidden = NO;
    _installStatusLabel.stringValue = errorMsg;
    _installStatusLabel.hidden = NO;
}

@end
