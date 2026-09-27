/*****************************************************************************
 * MacLCHeroView.m: the Home screen's featured video, under the glass
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

#import "medialib/components/MacLCHeroView.h"

#import <QuartzCore/QuartzCore.h>

#import <vlc_common.h>
#import <vlc_media_library.h>

#import "extensions/NSString+Helpers.h"
#import "library/VLCLibraryDataTypes.h"
#import "library/VLCLibraryController.h"
#import "main/VLCMain.h"
#import "medialib/data/MacLCArtworkLoader.h"
#import "medialib/data/MacLCLibraryActions.h"
#import "medialib/data/MacLCMediaFormat.h"
#import "theme/MacLCDesign.h"

static const CGFloat MacLCHeroTextInset = 32.0;

/* The picture: a layer whose contents fill the view, cropped (aspect fill). */
@interface MacLCHeroPictureView : NSView
@property (nonatomic, nullable) NSImage *image;
@end

@implementation MacLCHeroPictureView

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
    self.layer.backgroundColor = self.image == nil ? NSColor.quaternarySystemFillColor.CGColor : NULL;
}

- (void)setImage:(NSImage *)image
{
    _image = image;
    self.needsDisplay = YES;
}

@end

/* The scrim keeps white text legible on any frame. */
@interface MacLCHeroScrimView : NSView
@end

@implementation MacLCHeroScrimView

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
    gradient.colors = @[(__bridge id)[NSColor colorWithWhite:0.0 alpha:0.0].CGColor,
                        (__bridge id)[NSColor colorWithWhite:0.0 alpha:0.6].CGColor];
    /* Layer coordinates are flipped from the view's: 0 is the bottom. */
    gradient.startPoint = CGPointMake(0.5, 0.55);
    gradient.endPoint = CGPointMake(0.5, 0.0);
    return gradient;
}

- (NSView *)hitTest:(NSPoint)point
{
    return nil;
}

@end

@interface MacLCHeroView ()
{
    NSView *_extensionView;
    MacLCHeroPictureView *_pictureView;
    MacLCHeroScrimView *_scrimView;
    NSTextField *_eyebrowField;
    NSTextField *_titleField;
    NSTextField *_detailField;
    NSButton *_playButton;
    NSButton *_restartButton;
    MacLCArtworkRequest *_request;
    NSSize _requestedSize;
}
@end

@implementation MacLCHeroView

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        [self setUpViews];
    }
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (self) {
        [self setUpViews];
    }
    return self;
}

- (void)dealloc
{
    [_request cancel];
}

- (void)setUpViews
{
    self.wantsLayer = YES;

    _pictureView = [[MacLCHeroPictureView alloc] initWithFrame:self.bounds];
    _pictureView.translatesAutoresizingMaskIntoConstraints = NO;

    /* The background extension view mirrors the picture's edges under the
     * floating sidebar and toolbar, so the glass has colour to refract. The
     * picture itself also runs to the extension view's edges. */
    NSBackgroundExtensionView * const extensionView = [[NSBackgroundExtensionView alloc] initWithFrame:self.bounds];
    extensionView.automaticallyPlacesContentView = NO;
    extensionView.contentView = _pictureView;
    _extensionView = extensionView;
    _extensionView.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_extensionView];

    _scrimView = [[MacLCHeroScrimView alloc] initWithFrame:self.bounds];
    _scrimView.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_scrimView];

    _eyebrowField = [NSTextField labelWithString:@""];
    _eyebrowField.font = [NSFont systemFontOfSize:MacLCDesign.footnote.pointSize weight:NSFontWeightSemibold];
    _eyebrowField.textColor = [NSColor colorWithWhite:1.0 alpha:0.75];

    _titleField = [NSTextField wrappingLabelWithString:@""];
    _titleField.font = [NSFont systemFontOfSize:MacLCDesign.largeTitle.pointSize weight:NSFontWeightBold];
    _titleField.textColor = NSColor.whiteColor;
    _titleField.maximumNumberOfLines = 2;
    _titleField.lineBreakMode = NSLineBreakByTruncatingTail;
    _titleField.selectable = NO;

    _detailField = [NSTextField labelWithString:@""];
    _detailField.font = MacLCDesign.callout;
    _detailField.textColor = [NSColor colorWithWhite:1.0 alpha:0.85];

    _playButton = [NSButton buttonWithTitle:_NS("Play") target:self action:@selector(play:)];
    _playButton.image = [NSImage imageWithSystemSymbolName:@"play.fill" accessibilityDescription:nil];
    _playButton.imagePosition = NSImageLeading;
    _playButton.bezelStyle = NSBezelStyleGlass;
    _playButton.controlSize = NSControlSizeLarge;
    _playButton.tintProminence = NSTintProminencePrimary;
    _playButton.bezelColor = MacLCDesign.accent;

    _restartButton = [NSButton buttonWithTitle:_NS("Start Over") target:self action:@selector(startOver:)];
    _restartButton.image = [NSImage imageWithSystemSymbolName:@"arrow.counterclockwise" accessibilityDescription:nil];
    _restartButton.imagePosition = NSImageLeading;
    _restartButton.bezelStyle = NSBezelStyleGlass;
    _restartButton.controlSize = NSControlSizeLarge;

    NSStackView * const buttons = [NSStackView stackViewWithViews:@[_playButton, _restartButton]];
    buttons.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    buttons.spacing = 12.0;

    NSStackView * const text = [NSStackView stackViewWithViews:@[_eyebrowField, _titleField, _detailField, buttons]];
    text.orientation = NSUserInterfaceLayoutOrientationVertical;
    text.alignment = NSLayoutAttributeLeading;
    text.spacing = 4.0;
    [text setCustomSpacing:16.0 afterView:_detailField];
    text.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:text];

    NSLayoutGuide * const safeArea = self.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [_extensionView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_extensionView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [_extensionView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_extensionView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_pictureView.topAnchor constraintEqualToAnchor:_extensionView.topAnchor],
        [_pictureView.bottomAnchor constraintEqualToAnchor:_extensionView.bottomAnchor],
        [_pictureView.leadingAnchor constraintEqualToAnchor:_extensionView.leadingAnchor],
        [_pictureView.trailingAnchor constraintEqualToAnchor:_extensionView.trailingAnchor],
        [_scrimView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_scrimView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [_scrimView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_scrimView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [text.leadingAnchor constraintEqualToAnchor:safeArea.leadingAnchor constant:MacLCHeroTextInset],
        [text.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-MacLCHeroTextInset],
        [text.trailingAnchor constraintLessThanOrEqualToAnchor:safeArea.trailingAnchor constant:-MacLCHeroTextInset],
        [_titleField.widthAnchor constraintLessThanOrEqualToConstant:640.0],
    ]];

    self.alphaValue = 1.0;
    [self updateContents];
}

// MARK: - Contents

- (void)setMediaItem:(nullable VLCMediaLibraryMediaItem *)mediaItem
{
    const BOOL changed = mediaItem.libraryID != _mediaItem.libraryID || (mediaItem == nil) != (_mediaItem == nil);
    _mediaItem = mediaItem;
    [self updateContents];
    if (changed) {
        _pictureView.image = nil;
        _requestedSize = NSZeroSize;
        [self requestPicture];
    }
}

- (void)setEyebrow:(nullable NSString *)eyebrow
{
    _eyebrow = [eyebrow copy];
    [self updateContents];
}

- (void)updateContents
{
    VLCMediaLibraryMediaItem * const item = _mediaItem;
    _eyebrowField.attributedStringValue = [[NSAttributedString alloc]
        initWithString:_eyebrow.uppercaseString ?: @""
            attributes:@{NSKernAttributeName: @0.6,
                         NSFontAttributeName: _eyebrowField.font,
                         NSForegroundColorAttributeName: _eyebrowField.textColor}];
    _titleField.stringValue = item.displayString ?: @"";

    const BOOL started = item.progress > 0.02f && item.progress < 0.95f;
    NSMutableArray<NSString *> * const detail = [NSMutableArray array];
    if (started && item.duration > 0) {
        const int64_t remainingMinutes = (int64_t)ceil(item.duration * (1.0 - item.progress) / 60000.0);
        [detail addObject:remainingMinutes <= 1
            ? _NS("Less than a minute left")
            : [NSString stringWithFormat:_NS("%lld min left"), remainingMinutes]];
    } else if (item.duration > 0) {
        [detail addObject:item.durationString ?: @""];
    }
    if (item != nil) {
        MacLCMediaFormat * const format = [MacLCMediaFormat formatForMediaItem:item];
        if (format.resolutionBadge != nil) {
            [detail addObject:format.resolutionBadge];
        }
        if (format.dynamicRangeBadge != nil) {
            [detail addObject:[format.accessibilityDescription componentsSeparatedByString:@", "].lastObject];
        }
    }
    _detailField.stringValue = [detail componentsJoinedByString:@" · "];

    _playButton.title = started ? _NS("Resume") : _NS("Play");
    _restartButton.hidden = !started;
    _playButton.enabled = item != nil;

    [self setAccessibilityElement:NO];
}

- (void)layout
{
    [super layout];
    [self requestPicture];
}

- (void)requestPicture
{
    if (_mediaItem == nil || NSIsEmptyRect(self.bounds)) {
        return;
    }
    /* Ask again only when the size changed a lot: resizing the window must
     * not decode a banner per frame. */
    const NSSize size = self.bounds.size;
    if (fabs(size.width - _requestedSize.width) < 64.0 && fabs(size.height - _requestedSize.height) < 64.0) {
        return;
    }
    _requestedSize = size;
    [_request cancel];
    __weak typeof(self) weakSelf = self;
    const int64_t itemID = _mediaItem.libraryID;
    _request = [MacLCArtworkLoader.sharedLoader heroArtworkForItem:_mediaItem
                                                         pointSize:size
                                                             scale:self.window.backingScaleFactor
                                                        completion:^(NSImage * const image) {
        MacLCHeroView * const strongSelf = weakSelf;
        if (strongSelf == nil || strongSelf->_mediaItem.libraryID != itemID || image == nil) {
            return;
        }
        const BOOL firstImage = strongSelf->_pictureView.image == nil;
        strongSelf->_pictureView.image = image;
        if (firstImage) {
            strongSelf->_pictureView.alphaValue = 0.0;
            [NSAnimationContext runAnimationGroup:^(NSAnimationContext * const context) {
                context.duration = MacLCDesign.motionStandardDuration;
                strongSelf->_pictureView.animator.alphaValue = 1.0;
            }];
        }
    }];
}

- (void)viewDidMoveToWindow
{
    [super viewDidMoveToWindow];
    _requestedSize = NSZeroSize;
    [self requestPicture];
}

// MARK: - Actions

- (void)play:(id)sender
{
    if (_mediaItem != nil) {
        [MacLCLibraryActions playItems:@[_mediaItem] startingAt:0];
    }
}

- (void)startOver:(id)sender
{
    VLCMediaLibraryMediaItem * const item = _mediaItem;
    if (item == nil || !VLCMain.sharedInstance.libraryController.shouldUseMediaLibrary) {
        return;
    }
    /* Forget the saved position first, so playback starts at the beginning. */
    vlc_medialibrary_t * const ml = vlc_ml_instance_get(getIntf());
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        if (ml != NULL) {
            vlc_ml_media_update_progress(ml, item.libraryID, 0.0);
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [MacLCLibraryActions playItems:@[item] startingAt:0];
        });
    });
}

// MARK: - Accessibility

- (NSArray *)accessibilityChildren
{
    return @[_titleField, _playButton, _restartButton];
}

- (NSString *)accessibilityLabel
{
    return [NSString stringWithFormat:@"%@, %@, %@",
            _eyebrow ?: @"", _mediaItem.displayString ?: @"", _detailField.stringValue];
}

@end
