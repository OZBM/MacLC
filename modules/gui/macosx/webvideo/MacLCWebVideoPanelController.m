/*****************************************************************************
 * MacLCWebVideoPanelController.m: open web video panel
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

#import "MacLCWebVideoPanelController.h"

#import "MacLCWebVideoResolver.h"
#import "MacLCWebVideoHistory.h"

#import "theme/MacLCDesign.h"
#import "theme/MacLCGlassContainerView.h"
#import "theme/MacLCCardView.h"
#import "theme/MacLCSymbolButton.h"
#import "theme/MacLCFormatBadgeView.h"

#import "main/VLCMain.h"
#import "playqueue/VLCPlayQueueController.h"
#import "windows/VLCOpenInputMetadata.h"
#import "extensions/NSString+Helpers.h"

NS_ASSUME_NONNULL_BEGIN

@interface MacLCWebVideoPanelController () <NSTextFieldDelegate, NSWindowDelegate, NSMenuDelegate>

@property (nonatomic) NSView *panelContentView;
@property (nonatomic) NSTextField *titleLabel;
@property (nonatomic) NSTextField *subtitleLabel;
@property (nonatomic) NSTextField *addressField;
@property (nonatomic) MacLCSymbolButton *recentsButton;

@property (nonatomic) NSButton *cancelButton;
@property (nonatomic) NSButton *playButton;
@property (nonatomic) NSButton *addToQueueButton;

@property (nonatomic) NSProgressIndicator *spinner;
@property (nonatomic) NSTextField *resolvingLabel;

@property (nonatomic, nullable) MacLCCardView *previewCard;
@property (nonatomic, nullable) NSImageView *thumbnailView;
@property (nonatomic, nullable) NSTextField *previewTitleLabel;
@property (nonatomic, nullable) NSTextField *previewSubtitleLabel;
@property (nonatomic, nullable) MacLCFormatBadgeView *durationBadge;

@property (nonatomic, nullable) NSView *errorRow;
@property (nonatomic, nullable) NSImageView *errorIcon;
@property (nonatomic, nullable) NSTextField *errorLabel;
@property (nonatomic, nullable) NSButton *errorButton;

@property (nonatomic, nullable) NSUUID *resolveToken;
@property (nonatomic, nullable) MacLCWebVideoItem *resolvedItem;
@property (nonatomic) BOOL pendingPlay;
@property (nonatomic) BOOL pendingAddToQueue;
@property (nonatomic) MacLCWebVideoErrorCode lastErrorCode;

@property (nonatomic) NSStackView *mainStack;
@property (nonatomic) NSView *bottomRow;
@property (nonatomic) NSStackView *bottomStack;

@property (nonatomic) NSTimer *resolveTimer;
@property (nonatomic) NSURLSession *session;
@property (nonatomic, nullable) NSURLSessionDataTask *thumbnailTask;


@end

@implementation MacLCWebVideoPanelController

+ (MacLCWebVideoPanelController *)sharedController {
    static MacLCWebVideoPanelController *shared;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[self alloc] init];
    });
    return shared;
}

- (instancetype)init {
    NSPanel *panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 460, 200)
                                                styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskFullSizeContentView
                                                  backing:NSBackingStoreBuffered
                                                    defer:NO];
    panel.titlebarAppearsTransparent = YES;
    panel.titleVisibility = NSWindowTitleHidden;
    panel.movableByWindowBackground = YES;
    panel.level = NSNormalWindowLevel;
    panel.releasedWhenClosed = NO;
    
    self = [super initWithWindow:panel];
    if (self) {
        panel.delegate = self;
        [self setupUI];
        [self sizeWindowToFitContentAnimated:NO];
    }
    return self;
}

- (void)setupUI {
    NSView *backgroundView;
    if (NSClassFromString(@"NSGlassEffectContainerView") && !MacLCDesign.reduceTransparency) {
        backgroundView = [[MacLCGlassContainerView alloc] initWithFrame:NSZeroRect];
    } else if (!MacLCDesign.reduceTransparency) {
        backgroundView = [MacLCDesign floatingHUDMaterialView];
    } else {
        backgroundView = [[NSView alloc] initWithFrame:NSZeroRect];
        backgroundView.wantsLayer = YES;
        backgroundView.layer.backgroundColor = MacLCDesign.windowBackground.CGColor;
    }
    backgroundView.translatesAutoresizingMaskIntoConstraints = NO;
    self.window.contentView = backgroundView;
    
    NSView *hostView = backgroundView;
    if ([backgroundView isKindOfClass:[MacLCGlassContainerView class]]) {
        hostView = ((MacLCGlassContainerView *)backgroundView).contentView;
    }
    _panelContentView = hostView;
    
    _mainStack = [[NSStackView alloc] init];
    _mainStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    _mainStack.alignment = NSLayoutAttributeLeading;
    _mainStack.spacing = MacLCDesign.spacingL;
    _mainStack.translatesAutoresizingMaskIntoConstraints = NO;
    [hostView addSubview:_mainStack];
    
    /* The panel keeps one width: a long title truncates instead of widening it. */
    [_mainStack.widthAnchor constraintEqualToConstant:460. - 2. * MacLCDesign.spacingXL].active = YES;
    
    NSStackView *headerStack = [[NSStackView alloc] init];
    headerStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    headerStack.alignment = NSLayoutAttributeLeading;
    headerStack.spacing = MacLCDesign.spacingXS;
    
    _titleLabel = [NSTextField labelWithString:_NS("Open Web Video")];
    _titleLabel.font = MacLCDesign.title3;
    _titleLabel.textColor = MacLCDesign.primaryLabel;
    [headerStack addArrangedSubview:_titleLabel];
    
    _subtitleLabel = [NSTextField labelWithString:_NS("Paste a link and MacLC plays it like any other file.")];
    _subtitleLabel.font = MacLCDesign.subheadline;
    _subtitleLabel.textColor = MacLCDesign.secondaryLabel;
    [headerStack addArrangedSubview:_subtitleLabel];
    
    [_mainStack addArrangedSubview:headerStack];
    
    NSView *fieldContainer = [[NSView alloc] init];
    fieldContainer.translatesAutoresizingMaskIntoConstraints = NO;
    
    _addressField = [NSTextField textFieldWithString:@""];
    _addressField.font = MacLCDesign.body;
    _addressField.placeholderString = _NS("Paste a YouTube or video page link");
    _addressField.backgroundColor = MacLCDesign.controlBackground;
    _addressField.textColor = MacLCDesign.primaryLabel;
    _addressField.bezelStyle = NSTextFieldRoundedBezel;
    _addressField.wantsLayer = YES;
    _addressField.layer.cornerRadius = MacLCDesign.cornerRadiusMedium;
    _addressField.delegate = self;
    [_addressField setAccessibilityLabel:_NS("Video page address")];
    _addressField.translatesAutoresizingMaskIntoConstraints = NO;
    [fieldContainer addSubview:_addressField];
    
    _recentsButton = [MacLCSymbolButton buttonWithSymbolName:@"clock.arrow.circlepath" label:_NS("Recent links") pointSize:15 target:self action:@selector(showRecentsMenu:)];
    _recentsButton.translatesAutoresizingMaskIntoConstraints = NO;
    [fieldContainer addSubview:_recentsButton];
    
    [_mainStack addArrangedSubview:fieldContainer];
    
    _bottomRow = [[NSView alloc] init];
    _bottomRow.translatesAutoresizingMaskIntoConstraints = NO;
    
    _spinner = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
    _spinner.style = NSProgressIndicatorStyleSpinning;
    _spinner.controlSize = NSControlSizeSmall;
    _spinner.displayedWhenStopped = NO;
    _spinner.translatesAutoresizingMaskIntoConstraints = NO;
    [_bottomRow addSubview:_spinner];
    
    _resolvingLabel = [NSTextField labelWithString:_NS("Resolving…")];
    _resolvingLabel.font = MacLCDesign.footnote;
    _resolvingLabel.textColor = MacLCDesign.secondaryLabel;
    _resolvingLabel.hidden = YES;
    _resolvingLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_bottomRow addSubview:_resolvingLabel];
    
    _bottomStack = [[NSStackView alloc] init];
    _bottomStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    _bottomStack.spacing = MacLCDesign.spacingS;
    _bottomStack.translatesAutoresizingMaskIntoConstraints = NO;
    
    _addToQueueButton = [NSButton buttonWithTitle:_NS("Add to Queue") target:self action:@selector(addToQueueAction:)];
    _addToQueueButton.bezelStyle = NSBezelStyleRounded;
    [_bottomStack addArrangedSubview:_addToQueueButton];
    
    _cancelButton = [NSButton buttonWithTitle:_NS("Cancel") target:self action:@selector(cancelAction:)];
    _cancelButton.keyEquivalent = @"\033";
    _cancelButton.bezelStyle = NSBezelStyleRounded;
    [_bottomStack addArrangedSubview:_cancelButton];
    
    _playButton = [NSButton buttonWithTitle:_NS("Play") target:self action:@selector(playAction:)];
    _playButton.keyEquivalent = @"\r";
    _playButton.bezelStyle = NSBezelStyleRounded;
    [_bottomStack addArrangedSubview:_playButton];
    
    [_bottomRow addSubview:_bottomStack];
    [_mainStack addArrangedSubview:_bottomRow];
    
    [NSLayoutConstraint activateConstraints:@[
        /* The window draws its own title bar over the content, so the first
         * label starts below the close button rather than behind it. */
        [_mainStack.topAnchor constraintEqualToAnchor:hostView.topAnchor
                                             constant:MacLCDesign.spacingXL + 16.],
        [_mainStack.leadingAnchor constraintEqualToAnchor:hostView.leadingAnchor constant:MacLCDesign.spacingXL],
        [_mainStack.trailingAnchor constraintEqualToAnchor:hostView.trailingAnchor constant:-MacLCDesign.spacingXL],
        [_mainStack.bottomAnchor constraintEqualToAnchor:hostView.bottomAnchor constant:-MacLCDesign.spacingXL],
        
        [fieldContainer.widthAnchor constraintEqualToAnchor:_mainStack.widthAnchor],
        [_addressField.leadingAnchor constraintEqualToAnchor:fieldContainer.leadingAnchor],
        [_addressField.topAnchor constraintEqualToAnchor:fieldContainer.topAnchor],
        [_addressField.bottomAnchor constraintEqualToAnchor:fieldContainer.bottomAnchor],
        [_addressField.trailingAnchor constraintEqualToAnchor:fieldContainer.trailingAnchor],
        
        [_recentsButton.centerYAnchor constraintEqualToAnchor:fieldContainer.centerYAnchor],
        [_recentsButton.trailingAnchor constraintEqualToAnchor:fieldContainer.trailingAnchor constant:-MacLCDesign.spacingS],
        
        [_bottomRow.widthAnchor constraintEqualToAnchor:_mainStack.widthAnchor],
        [_bottomStack.trailingAnchor constraintEqualToAnchor:_bottomRow.trailingAnchor],
        [_bottomStack.topAnchor constraintEqualToAnchor:_bottomRow.topAnchor],
        [_bottomStack.bottomAnchor constraintEqualToAnchor:_bottomRow.bottomAnchor],
        
        [_spinner.leadingAnchor constraintEqualToAnchor:_bottomRow.leadingAnchor],
        [_spinner.centerYAnchor constraintEqualToAnchor:_bottomRow.centerYAnchor],
        [_resolvingLabel.leadingAnchor constraintEqualToAnchor:_spinner.trailingAnchor constant:MacLCDesign.spacingS],
        [_resolvingLabel.centerYAnchor constraintEqualToAnchor:_bottomRow.centerYAnchor]
    ]];
    
    [self.window setInitialFirstResponder:_addressField];
    _session = [NSURLSession sharedSession];
    
    [self updateState];
}

- (void)updateState {
    NSString *text = _addressField.stringValue;
    BOOL valid = [MacLCWebVideoResolver looksLikeWebVideoAddress:text];
    
    _playButton.enabled = valid;
    _addToQueueButton.enabled = valid;
    
    _recentsButton.hidden = (MacLCWebVideoHistory.sharedHistory.entries.count == 0);
}

- (void)showPanel {
    [self showPanelWithAddress:nil];
}

- (void)showPanelWithAddress:(nullable NSString *)address {
    [self showPanelWithAddress:address playWhenResolved:NO];
}

- (void)showPanelWithAddress:(nullable NSString *)address playWhenResolved:(BOOL)playWhenResolved {
    if (address) {
        _addressField.stringValue = address;
    }
    
    [self updateState];
    [self clearPreviewAndError];
    
    /* An address handed to the panel was already chosen by the user, in the
     * clipboard or in a link: start reading it without waiting for a key. */
    if (address.length > 0 && [MacLCWebVideoResolver looksLikeWebVideoAddress:address]) {
        _pendingPlay = playWhenResolved;
        [self startResolution];
    }
    
    if (MacLCDesign.reduceTransparency || MacLCDesign.reducedMotion) {
        [self.window center];
        [self.window makeKeyAndOrderFront:nil];
    } else {
        self.window.alphaValue = 0.0;
        [self.window center];
        
        NSRect frame = self.window.frame;
        frame.origin.y -= 8.0;
        [self.window setFrame:frame display:YES];
        
        [self.window makeKeyAndOrderFront:nil];
        
        frame.origin.y += 8.0;
        
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext * _Nonnull context) {
            context.duration = MacLCDesign.motionStandardDuration;
            context.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
            [[self.window animator] setFrame:frame display:YES];
            [[self.window animator] setAlphaValue:1.0];
        }];
    }
}

- (void)clearPreviewAndError {
    /* A thumbnail still downloading belongs to the preview going away. */
    [_thumbnailTask cancel];
    _thumbnailTask = nil;
    if (_previewCard) {
        [_previewCard removeFromSuperview];
        _previewCard = nil;
    }
    if (_errorRow) {
        [_errorRow removeFromSuperview];
        _errorRow = nil;
    }
    _thumbnailView = nil;
    _previewTitleLabel = nil;
    _previewSubtitleLabel = nil;
    _durationBadge = nil;
    _errorIcon = nil;
    _errorLabel = nil;
    _errorButton = nil;
    
    /* Taking a row out gives the height back, or the stack stretches what is
     * left over a window that is now too tall. */
    [self sizeWindowToFitContentAnimated:NO];
}

- (void)controlTextDidChange:(NSNotification *)obj {
    [self updateState];
    
    // Clear preview/error immediately on edit
    [self clearPreviewAndError];
    [self stopResolution];
    
    // 600ms timer
    _resolveTimer = [NSTimer scheduledTimerWithTimeInterval:0.6 target:self selector:@selector(startResolution) userInfo:nil repeats:NO];
}

- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)commandSelector {
    if (commandSelector == @selector(insertNewline:)) {
        [self playAction:nil];
        return YES;
    }
    return NO;
}

- (void)stopResolution {
    if (_resolveTimer) {
        [_resolveTimer invalidate];
        _resolveTimer = nil;
    }
    if (_resolveToken) {
        [MacLCWebVideoResolver.sharedResolver cancelResolution:_resolveToken];
        _resolveToken = nil;
    }
    [_spinner stopAnimation:nil];
    _resolvingLabel.hidden = YES;
}

- (void)startResolution {
    [self stopResolution];
    
    NSString *address = _addressField.stringValue;
    if (![MacLCWebVideoResolver looksLikeWebVideoAddress:address]) {
        return;
    }
    
    _resolvedItem = nil;
    _lastErrorCode = 0;
    
    [_spinner startAnimation:nil];
    _resolvingLabel.hidden = NO;
    
    __weak typeof(self) weakSelf = self;
    _resolveToken = [MacLCWebVideoResolver.sharedResolver resolveAddress:address completion:^(MacLCWebVideoItem * _Nullable item, NSError * _Nullable error) {
        [weakSelf handleResolutionResult:item error:error];
    }];
}

- (void)cancelAction:(id)sender {
    if (_resolveToken) {
        [self stopResolution];
        return;
    }
    [self.window close];
}

- (void)playAction:(id)sender {
    if (_resolvedItem) {
        [self enqueueItemAndClose:_resolvedItem startPlayback:YES];
    } else if (_lastErrorCode == MacLCWebVideoErrorExtractorMissing) {
        // Fallback for extractor missing: play raw address
        [self enqueueRawAddressAndClose:_addressField.stringValue startPlayback:YES];
    } else {
        _pendingPlay = YES;
        _pendingAddToQueue = NO;
        [self startResolution];
    }
}

- (void)addToQueueAction:(id)sender {
    if (_resolvedItem) {
        [self enqueueItemAndClose:_resolvedItem startPlayback:NO];
    } else if (_lastErrorCode == MacLCWebVideoErrorExtractorMissing) {
        [self enqueueRawAddressAndClose:_addressField.stringValue startPlayback:NO];
    } else {
        _pendingPlay = NO;
        _pendingAddToQueue = YES;
        [self startResolution];
    }
}

- (void)showRecentsMenu:(id)sender {
    NSArray<NSDictionary *> *entries = MacLCWebVideoHistory.sharedHistory.entries;
    if (entries.count == 0) return;
    
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@""];
    for (NSDictionary *entry in entries) {
        NSString *title = entry[@"title"] ?: entry[@"address"];
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:@selector(recentSelected:) keyEquivalent:@""];
        item.target = self;
        item.representedObject = entry[@"address"];
        
        NSString *site = entry[@"site"];
        if (site) {
            NSMutableAttributedString *attr = [[NSMutableAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@  %@", title, site]];
            [attr setAttributes:@{NSForegroundColorAttributeName: MacLCDesign.secondaryLabel} range:NSMakeRange(title.length + 2, site.length)];
            item.attributedTitle = attr;
        }
        [menu addItem:item];
    }
    [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *clearItem = [[NSMenuItem alloc] initWithTitle:_NS("Clear Menu") action:@selector(clearRecents:) keyEquivalent:@""];
    clearItem.target = self;
    [menu addItem:clearItem];
    
    [menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(0, -5) inView:_recentsButton];
}

- (void)recentSelected:(NSMenuItem *)item {
    NSString *address = item.representedObject;
    if (address) {
        _addressField.stringValue = address;
        [self updateState];
        [self startResolution];
    }
}

- (void)clearRecents:(NSMenuItem *)item {
    [MacLCWebVideoHistory.sharedHistory clear];
    [self updateState];
}

- (void)handleResolutionResult:(MacLCWebVideoItem *)item error:(NSError *)error {
    _resolveToken = nil;
    [_spinner stopAnimation:nil];
    _resolvingLabel.hidden = YES;
    
    [self clearPreviewAndError];
    
    if (error) {
        _lastErrorCode = error.code;
        if (error.code == MacLCWebVideoErrorCancelled) {
            return;
        }
        [self showError:error];
    } else if (item) {
        _resolvedItem = item;
        _lastErrorCode = 0;
        [self showPreviewCardForItem:item];
        
        if (_pendingPlay) {
            _pendingPlay = NO;
            [self enqueueItemAndClose:item startPlayback:YES];
        } else if (_pendingAddToQueue) {
            _pendingAddToQueue = NO;
            [self enqueueItemAndClose:item startPlayback:NO];
        }
    }
}

- (void)showError:(NSError *)error {
    _errorRow = [[NSView alloc] init];
    _errorRow.translatesAutoresizingMaskIntoConstraints = NO;
    
    _errorIcon = [[NSImageView alloc] init];
    BOOL isHardFailure = (error.code == MacLCWebVideoErrorExtractorMissing || error.code == MacLCWebVideoErrorExtractorFailed || error.code == MacLCWebVideoErrorNoNetwork || error.code == MacLCWebVideoErrorUnavailable || error.code == MacLCWebVideoErrorNotAVideo || error.code == MacLCWebVideoErrorInvalidAddress); // Actually specs says warning or destructive for hard failure. I'll use destructive for ExtractorFailed, Missing.
    
    NSColor *color = isHardFailure ? MacLCDesign.destructive : MacLCDesign.warning;
    _errorIcon.image = [MacLCDesign symbolNamed:@"exclamationmark.triangle" pointSize:15 weight:NSFontWeightRegular accessibilityLabel:nil];
    _errorIcon.contentTintColor = color;
    _errorIcon.translatesAutoresizingMaskIntoConstraints = NO;
    [_errorRow addSubview:_errorIcon];
    
    NSString *sentence = @"";
    NSString *buttonTitle = nil;
    SEL buttonAction = NULL;
    
    switch (error.code) {
        case MacLCWebVideoErrorInvalidAddress:
            sentence = _NS("That does not look like a web address.");
            _addressField.layer.borderColor = MacLCDesign.destructive.CGColor;
            _addressField.layer.borderWidth = 1.0;
            break;
        case MacLCWebVideoErrorExtractorMissing:
            sentence = _NS("MacLC needs yt-dlp to read video pages.");
            buttonTitle = _NS("Copy Install Command");
            buttonAction = @selector(copyInstallCommand:);
            break;
        case MacLCWebVideoErrorExtractorOutdated:
            sentence = _NS("yt-dlp is too old to read this page.");
            buttonTitle = _NS("Copy Update Command");
            buttonAction = @selector(copyUpdateCommand:);
            break;
        case MacLCWebVideoErrorNoNetwork:
            sentence = _NS("MacLC cannot reach the internet.");
            buttonTitle = _NS("Network Settings");
            buttonAction = @selector(openNetworkSettings:);
            break;
        case MacLCWebVideoErrorNotAVideo:
            sentence = _NS("No video was found on that page.");
            break;
        case MacLCWebVideoErrorUnavailable:
            sentence = _NS("This video cannot be played: it may be private, paid or blocked in your country.");
            buttonTitle = _NS("Open in Browser");
            buttonAction = @selector(openInBrowser:);
            break;
        case MacLCWebVideoErrorExtractorFailed:
            sentence = _NS("MacLC could not read that page.");
            buttonTitle = _NS("Copy Details");
            buttonAction = @selector(copyDetails:);
            _errorRow.toolTip = error.localizedFailureReason; // store details for copy
            break;
        default:
            break;
    }
    
    _errorLabel = [NSTextField labelWithString:sentence];
    _errorLabel.font = MacLCDesign.callout;
    _errorLabel.textColor = MacLCDesign.primaryLabel;
    _errorLabel.lineBreakMode = NSLineBreakByWordWrapping;
    _errorLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_errorRow addSubview:_errorLabel];
    
    if (buttonTitle) {
        _errorButton = [NSButton buttonWithTitle:buttonTitle target:self action:buttonAction];
        _errorButton.bezelStyle = NSBezelStyleInline;
        _errorButton.translatesAutoresizingMaskIntoConstraints = NO;
        [_errorRow addSubview:_errorButton];
    }
    
    [_mainStack insertArrangedSubview:_errorRow atIndex:2];
    [_errorRow.widthAnchor constraintEqualToAnchor:_mainStack.widthAnchor].active = YES;
    
    [NSLayoutConstraint activateConstraints:@[
        [_errorIcon.leadingAnchor constraintEqualToAnchor:_errorRow.leadingAnchor],
        [_errorIcon.topAnchor constraintEqualToAnchor:_errorRow.topAnchor],
        
        [_errorLabel.leadingAnchor constraintEqualToAnchor:_errorIcon.trailingAnchor constant:MacLCDesign.spacingS],
        [_errorLabel.topAnchor constraintEqualToAnchor:_errorRow.topAnchor],
        [_errorLabel.trailingAnchor constraintEqualToAnchor:_errorRow.trailingAnchor],
    ]];
    
    if (_errorButton == nil) {
        [_errorLabel.bottomAnchor constraintEqualToAnchor:_errorRow.bottomAnchor].active = YES;
    }
    
    if (_errorButton) {
        /* The panel keeps its width, so the recovery button sits under the
         * sentence rather than squeezing it. */
        [NSLayoutConstraint activateConstraints:@[
            [_errorButton.topAnchor constraintEqualToAnchor:_errorLabel.bottomAnchor
                                                   constant:MacLCDesign.spacingS],
            [_errorButton.trailingAnchor constraintEqualToAnchor:_errorRow.trailingAnchor],
            [_errorButton.bottomAnchor constraintEqualToAnchor:_errorRow.bottomAnchor]
        ]];
    }
    
    [self animateWindowHeightChange];
    
    NSAccessibilityPostNotificationWithUserInfo(self.window,
                                                NSAccessibilityAnnouncementRequestedNotification,
                                                @{NSAccessibilityAnnouncementKey: sentence,
                                                  NSAccessibilityPriorityKey: @(NSAccessibilityPriorityHigh)});
}

- (void)showPreviewCardForItem:(MacLCWebVideoItem *)item {
    _previewCard = [MacLCCardView cardViewWithTitle:nil];
    _previewCard.translatesAutoresizingMaskIntoConstraints = NO;
    
    [NSLayoutConstraint activateConstraints:@[
        [_previewCard.heightAnchor constraintEqualToConstant:88]
    ]];
    
    NSView *container = _previewCard.cardContainerView;
    
    _thumbnailView = [[NSImageView alloc] init];
    _thumbnailView.wantsLayer = YES;
    _thumbnailView.layer.cornerRadius = MacLCDesign.cornerRadiusSmall;
    _thumbnailView.layer.masksToBounds = YES;
    _thumbnailView.layer.backgroundColor = MacLCDesign.mediaBackground.CGColor;
    _thumbnailView.imageScaling = NSImageScaleProportionallyUpOrDown;
    _thumbnailView.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:_thumbnailView];
    
    NSString *titleText = item.title ?: _NS("Unknown Title");
    if (item.children.count > 0) {
        titleText = item.title ?: _NS("Playlist");
    }
    _previewTitleLabel = [NSTextField labelWithString:titleText];
    _previewTitleLabel.font = MacLCDesign.headline;
    _previewTitleLabel.textColor = MacLCDesign.primaryLabel;
    _previewTitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    _previewTitleLabel.maximumNumberOfLines = 1;
    _previewTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:_previewTitleLabel];
    
    NSString *subText = @"";
    if (item.children.count > 0) {
        subText = [NSString localizedStringWithFormat:_NS("%lu videos"), (unsigned long)item.children.count];
    } else {
        NSString *author = item.author;
        NSString *site = item.siteName;
        if (author && site) {
            subText = [NSString stringWithFormat:@"%@ • %@", author, site];
        } else if (author) {
            subText = author;
        } else if (site) {
            subText = site;
        }
    }
    
    _previewSubtitleLabel = [NSTextField labelWithString:subText];
    _previewSubtitleLabel.font = MacLCDesign.subheadline;
    _previewSubtitleLabel.textColor = MacLCDesign.secondaryLabel;
    _previewSubtitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    _previewSubtitleLabel.maximumNumberOfLines = 1;
    _previewSubtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:_previewSubtitleLabel];
    
    NSString *durationText = nil;
    if (item.isLive) {
        durationText = @"LIVE";
    } else if (item.duration > 0 && item.children.count == 0) {
        int totalSeconds = (int)item.duration;
        int h = totalSeconds / 3600;
        int m = (totalSeconds % 3600) / 60;
        int s = totalSeconds % 60;
        if (h > 0) {
            durationText = [NSString stringWithFormat:@"%d:%02d:%02d", h, m, s];
        } else {
            durationText = [NSString stringWithFormat:@"%d:%02d", m, s];
        }
    }
    
    if (durationText) {
        _durationBadge = [MacLCFormatBadgeView badgeWithTitle:durationText active:YES];
        _durationBadge.translatesAutoresizingMaskIntoConstraints = NO;
        [_thumbnailView addSubview:_durationBadge];
        
        [NSLayoutConstraint activateConstraints:@[
            [_durationBadge.trailingAnchor constraintEqualToAnchor:_thumbnailView.trailingAnchor constant:-MacLCDesign.spacingXS],
            [_durationBadge.bottomAnchor constraintEqualToAnchor:_thumbnailView.bottomAnchor constant:-MacLCDesign.spacingXS]
        ]];
    }
    
    [NSLayoutConstraint activateConstraints:@[
        [_thumbnailView.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:MacLCDesign.spacingS],
        [_thumbnailView.centerYAnchor constraintEqualToAnchor:container.centerYAnchor],
        [_thumbnailView.widthAnchor constraintEqualToConstant:140],
        [_thumbnailView.heightAnchor constraintEqualToConstant:78],
        
        [_previewTitleLabel.leadingAnchor constraintEqualToAnchor:_thumbnailView.trailingAnchor constant:MacLCDesign.spacingL],
        [_previewTitleLabel.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-MacLCDesign.spacingS],
        [_previewTitleLabel.bottomAnchor constraintEqualToAnchor:container.centerYAnchor constant:-2],
        
        [_previewSubtitleLabel.leadingAnchor constraintEqualToAnchor:_previewTitleLabel.leadingAnchor],
        [_previewSubtitleLabel.trailingAnchor constraintEqualToAnchor:_previewTitleLabel.trailingAnchor],
        [_previewSubtitleLabel.topAnchor constraintEqualToAnchor:container.centerYAnchor constant:2],
    ]];
    
    [_mainStack insertArrangedSubview:_previewCard atIndex:2];
    [self animateWindowHeightChange];
    
    [_thumbnailTask cancel];
    _thumbnailTask = nil;
    if (item.thumbnailAddress) {
        NSURL *url = [NSURL URLWithString:item.thumbnailAddress];
        if (url) {
            /* The image goes to this preview's own view: a slow download
             * for an earlier address must not land on a later preview. */
            __weak NSImageView * const thumbnailView = _thumbnailView;
            _thumbnailTask = [_session dataTaskWithURL:url completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
                if (data) {
                    NSImage *image = [[NSImage alloc] initWithData:data];
                    if (image) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            thumbnailView.image = image;
                        });
                    }
                }
            }];
            [_thumbnailTask resume];
        }
    }
}

- (void)animateWindowHeightChange {
    [self sizeWindowToFitContentAnimated:YES];
}

/* The panel is exactly as tall as what it shows: the preview strip and the
 * error row grow it, and leaving them takes the height back. */
- (void)sizeWindowToFitContentAnimated:(BOOL)animated {
    [self.window layoutIfNeeded];
    
    NSRect currentFrame = self.window.frame;
    NSSize newSize = [self.window.contentView fittingSize];
    
    if (ABS(currentFrame.size.height - newSize.height) <= 1.0) {
        return;
    }
    
    NSRect newFrame = currentFrame;
    newFrame.size.height = newSize.height;
    newFrame.origin.y = currentFrame.origin.y + (currentFrame.size.height - newSize.height);
    
    if (!animated || MacLCDesign.reducedMotion) {
        [self.window setFrame:newFrame display:YES];
        return;
    }
    
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext * _Nonnull context) {
        context.duration = MacLCDesign.motionStandardDuration;
        [[self.window animator] setFrame:newFrame display:YES];
    }];
}

- (void)enqueueItemAndClose:(MacLCWebVideoItem *)item startPlayback:(BOOL)start {
    [MacLCWebVideoHistory.sharedHistory recordAddress:item.pageAddress title:item.title site:item.siteName];
    
    NSMutableArray *items = [NSMutableArray array];
    if (item.children.count > 0) {
        for (MacLCWebVideoItem *child in item.children) {
            if (child.playQueueItem) {
                [items addObject:child.playQueueItem];
            }
        }
    } else {
        if (item.playQueueItem) {
            [items addObject:item.playQueueItem];
        }
    }
    
    if (items.count > 0) {
        if (start) {
            [VLCMain.sharedInstance.playQueueController addPlayQueueItems:items atPosition:(size_t)-1 startPlayback:YES];
            [self.window close];
        } else {
            [VLCMain.sharedInstance.playQueueController addPlayQueueItems:items];
            _addressField.stringValue = @"";
            [self updateState];
            [self clearPreviewAndError];
            
            _resolvingLabel.stringValue = _NS("Added to the queue");
            _resolvingLabel.hidden = NO;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                self.resolvingLabel.hidden = YES;
                self.resolvingLabel.stringValue = _NS("Resolving…");
            });
        }
    }
}

- (void)enqueueRawAddressAndClose:(NSString *)address startPlayback:(BOOL)start {
    [MacLCWebVideoHistory.sharedHistory recordAddress:address title:nil site:nil];
    
    VLCOpenInputMetadata * const meta = [[VLCOpenInputMetadata alloc] init];
    meta.MRLString = address;
    meta.itemName = address;
    
    if (start) {
        [VLCMain.sharedInstance.playQueueController addPlayQueueItems:@[meta] atPosition:(size_t)-1 startPlayback:YES];
        [self.window close];
    } else {
        [VLCMain.sharedInstance.playQueueController addPlayQueueItems:@[meta]];
        _addressField.stringValue = @"";
        [self updateState];
        [self clearPreviewAndError];
        
        _resolvingLabel.stringValue = _NS("Added to the queue");
        _resolvingLabel.hidden = NO;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            self.resolvingLabel.hidden = YES;
            self.resolvingLabel.stringValue = _NS("Resolving…");
        });
    }
}

- (void)copyInstallCommand:(id)sender {
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    [pb clearContents];
    [pb setString:@"brew install yt-dlp" forType:NSPasteboardTypeString];
    [_errorButton setTitle:_NS("Copied")];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self->_errorButton setTitle:_NS("Copy Install Command")];
    });
}

- (void)copyUpdateCommand:(id)sender {
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    [pb clearContents];
    [pb setString:@"brew upgrade yt-dlp" forType:NSPasteboardTypeString];
    [_errorButton setTitle:_NS("Copied")];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self->_errorButton setTitle:_NS("Copy Update Command")];
    });
}

- (void)openNetworkSettings:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"x-apple.systempreferences:com.apple.Network-Settings.extension"]];
}

- (void)openInBrowser:(id)sender {
    NSString *addr = _addressField.stringValue;
    if (addr.length > 0) {
        [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:addr]];
    }
}

- (void)copyDetails:(id)sender {
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    [pb clearContents];
    if (_errorRow.toolTip) {
        [pb setString:_errorRow.toolTip forType:NSPasteboardTypeString];
    }
    [_errorButton setTitle:_NS("Copied")];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self->_errorButton setTitle:_NS("Copy Details")];
    });
}

@end

NS_ASSUME_NONNULL_END
