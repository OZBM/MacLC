/*****************************************************************************
 * MacLCBrowseItemCollectionViewItem.m: Folder contents grid item
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

#import "MacLCBrowseItemCollectionViewItem.h"

#import "extensions/NSString+Helpers.h"

#import "library/VLCInputItem.h"
#import "library/VLCInputNode.h"
#import "library/VLCLibraryImageCache.h"

#import "main/VLCMain.h"
#import "playqueue/VLCPlayQueueController.h"
#import "theme/MacLCDesign.h"

NSString * const MacLCBrowseItemCollectionViewItemIdentifier = @"MacLCBrowseItemCollectionViewItemIdentifier";

/* What the 16:9 artwork box shows. */
typedef NS_ENUM(NSInteger, MacLCBrowseArtworkStyle) {
    MacLCBrowseArtworkStyleFolder,      // system folder icon, 60 % of the box height
    MacLCBrowseArtworkStyleThumbnail,   // video frame covering the whole box
    MacLCBrowseArtworkStyleSquareArt,   // album art, full box height, centred
    MacLCBrowseArtworkStyleSymbol,      // SF Symbol, 40 % of the box height
};

static const CGFloat MacLCBrowseItemTitleLineCount = 2.;

/* Height a wrapping label needs at a width, at most maxLines lines, measured
 * with a copy of its own cell so insets and leading match what it draws. */
static CGFloat MacLCBrowseWrappedLabelHeight(NSTextField *label, CGFloat width, NSInteger maxLines)
{
    NSTextFieldCell * const probe = [label.cell copy];
    NSMutableString * const sample = [NSMutableString stringWithString:@"X"];
    for (NSInteger line = 1; line < maxLines; line++) {
        [sample appendString:@"\nX"];
    }
    probe.stringValue = sample;
    const CGFloat maxHeight = ceil([probe cellSizeForBounds:NSMakeRect(0, 0, 10000., 10000.)].height);
    if (width <= 0.) {
        return maxHeight;
    }
    /* The cell draws its text slightly inset from its bounds: measure a
     * little narrower so a title that barely fits wraps instead of being cut. */
    const CGFloat needed = ceil([label.cell cellSizeForBounds:NSMakeRect(0, 0, MAX(width - 6., 1.), 10000.)].height);
    return MIN(needed, maxHeight);
}

@interface MacLCBrowseItemView ()
{
    NSTrackingArea *_trackingArea;
    BOOL _isHovered;
    MacLCBrowseArtworkStyle _artworkStyle;
    NSView *_thumbnailFillView;
    NSLayoutConstraint *_folderIconHeightConstraint;
    NSLayoutConstraint *_symbolHeightConstraint;
    NSLayoutConstraint *_squareArtHeightConstraint;
    NSLayoutConstraint *_titleHeightConstraint;
}

- (void)showFolderIcon:(NSImage *)icon;
- (void)showSymbolNamed:(NSString *)symbolName accessibilityLabel:(nullable NSString *)label;
- (void)showSquareArtwork:(NSImage *)image;
- (void)showThumbnail:(NSImage *)image;

@end

@implementation MacLCBrowseItemView

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        self.layerContentsRedrawPolicy = NSViewLayerContentsRedrawOnSetNeedsDisplay;

        _artworkBox = [[NSView alloc] initWithFrame:NSZeroRect];
        _artworkBox.translatesAutoresizingMaskIntoConstraints = NO;
        _artworkBox.wantsLayer = YES;
        _artworkBox.layer.cornerRadius = MacLCDesign.cornerRadiusMedium;
        _artworkBox.layer.masksToBounds = YES;
        _artworkBox.layer.borderWidth = 1.0;
        _artworkBox.layer.borderColor = MacLCDesign.separator.CGColor;
        [self addSubview:_artworkBox];

        /* NSImageView cannot aspect-fill: video frames go into a layer. */
        _thumbnailFillView = [[NSView alloc] initWithFrame:NSZeroRect];
        _thumbnailFillView.translatesAutoresizingMaskIntoConstraints = NO;
        _thumbnailFillView.wantsLayer = YES;
        _thumbnailFillView.layer.contentsGravity = kCAGravityResizeAspectFill;
        _thumbnailFillView.layer.masksToBounds = YES;
        _thumbnailFillView.hidden = YES;
        [_artworkBox addSubview:_thumbnailFillView];

        _thumbnailImageView = [[NSImageView alloc] initWithFrame:NSZeroRect];
        _thumbnailImageView.translatesAutoresizingMaskIntoConstraints = NO;
        _thumbnailImageView.imageScaling = NSImageScaleProportionallyUpOrDown;
        [_artworkBox addSubview:_thumbnailImageView];

        // Duration badge
        _durationBadgeView = [[NSView alloc] initWithFrame:NSZeroRect];
        _durationBadgeView.translatesAutoresizingMaskIntoConstraints = NO;
        _durationBadgeView.wantsLayer = YES;
        _durationBadgeView.layer.cornerRadius = MacLCDesign.cornerRadiusSmall;
        _durationBadgeView.layer.masksToBounds = YES;
        _durationBadgeView.layer.backgroundColor = MacLCDesign.mediaOverlayBackground.CGColor;
        _durationBadgeView.hidden = YES;
        [_artworkBox addSubview:_durationBadgeView];

        _durationLabel = [NSTextField labelWithString:@""];
        _durationLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _durationLabel.font = [MacLCDesign monospacedDigitFontForTextStyle:NSFontTextStyleFootnote weight:NSFontWeightMedium];
        _durationLabel.textColor = NSColor.whiteColor;
        _durationLabel.alignment = NSTextAlignmentCenter;
        _durationLabel.drawsBackground = NO;
        [_durationBadgeView addSubview:_durationLabel];

        // Play button (hover)
        _playButton = [[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 44, 44)];
        _playButton.translatesAutoresizingMaskIntoConstraints = NO;
        _playButton.bordered = YES;
        if (@available(macOS 26.0, *)) {
            _playButton.bezelStyle = NSBezelStyleGlass;
            _playButton.borderShape = NSControlBorderShapeCircle;
        } else {
            _playButton.bezelStyle = NSBezelStyleCircular;
        }
        _playButton.image = [MacLCDesign symbolNamed:@"play.fill"
                                           pointSize:18.0
                                              weight:NSFontWeightSemibold
                                  accessibilityLabel:_NS("Play")];
        _playButton.imageScaling = NSImageScaleProportionallyUpOrDown;
        _playButton.toolTip = _NS("Play");
        _playButton.hidden = YES;
        [_artworkBox addSubview:_playButton];

        // Labels: the title wraps on up to two lines; the secondary line
        // follows it (the item itself always has room for two lines).
        _titleLabel = [NSTextField wrappingLabelWithString:@""];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _titleLabel.font = MacLCDesign.bodyEmphasized;
        _titleLabel.textColor = MacLCDesign.primaryLabel;
        _titleLabel.lineBreakMode = NSLineBreakByWordWrapping;
        _titleLabel.maximumNumberOfLines = (NSInteger)MacLCBrowseItemTitleLineCount;
        _titleLabel.cell.truncatesLastVisibleLine = YES;
        _titleLabel.selectable = NO;
        _titleLabel.drawsBackground = NO;
        [self addSubview:_titleLabel];

        _secondaryLabel = [NSTextField labelWithString:@""];
        _secondaryLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _secondaryLabel.font = MacLCDesign.footnote;
        _secondaryLabel.textColor = MacLCDesign.secondaryLabel;
        _secondaryLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _secondaryLabel.maximumNumberOfLines = 1;
        _secondaryLabel.drawsBackground = NO;
        [self addSubview:_secondaryLabel];

        // Base layout
        [NSLayoutConstraint activateConstraints:@[
            [_artworkBox.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_artworkBox.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_artworkBox.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_artworkBox.heightAnchor constraintEqualToAnchor:_artworkBox.widthAnchor multiplier:(9.0 / 16.0)],

            [_durationBadgeView.trailingAnchor constraintEqualToAnchor:_artworkBox.trailingAnchor constant:-6.0],
            [_durationBadgeView.bottomAnchor constraintEqualToAnchor:_artworkBox.bottomAnchor constant:-6.0],
            [_durationLabel.topAnchor constraintEqualToAnchor:_durationBadgeView.topAnchor constant:2.0],
            [_durationLabel.bottomAnchor constraintEqualToAnchor:_durationBadgeView.bottomAnchor constant:-2.0],
            [_durationLabel.leadingAnchor constraintEqualToAnchor:_durationBadgeView.leadingAnchor constant:5.0],
            [_durationLabel.trailingAnchor constraintEqualToAnchor:_durationBadgeView.trailingAnchor constant:-5.0],

            [_playButton.centerXAnchor constraintEqualToAnchor:_artworkBox.centerXAnchor],
            [_playButton.centerYAnchor constraintEqualToAnchor:_artworkBox.centerYAnchor],
            [_playButton.widthAnchor constraintEqualToConstant:44.0],
            [_playButton.heightAnchor constraintEqualToConstant:44.0],

            [_titleLabel.topAnchor constraintEqualToAnchor:_artworkBox.bottomAnchor constant:8.0],
            [_titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_titleLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],

            [_secondaryLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:2.0],
            [_secondaryLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_secondaryLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_secondaryLabel.bottomAnchor constraintLessThanOrEqualToAnchor:self.bottomAnchor],

            [_thumbnailFillView.topAnchor constraintEqualToAnchor:_artworkBox.topAnchor],
            [_thumbnailFillView.bottomAnchor constraintEqualToAnchor:_artworkBox.bottomAnchor],
            [_thumbnailFillView.leadingAnchor constraintEqualToAnchor:_artworkBox.leadingAnchor],
            [_thumbnailFillView.trailingAnchor constraintEqualToAnchor:_artworkBox.trailingAnchor],

            [_thumbnailImageView.centerXAnchor constraintEqualToAnchor:_artworkBox.centerXAnchor],
            [_thumbnailImageView.centerYAnchor constraintEqualToAnchor:_artworkBox.centerYAnchor],
            [_thumbnailImageView.widthAnchor constraintEqualToAnchor:_thumbnailImageView.heightAnchor],
        ]];

        _folderIconHeightConstraint =
            [_thumbnailImageView.heightAnchor constraintEqualToAnchor:_artworkBox.heightAnchor multiplier:0.6];
        _symbolHeightConstraint =
            [_thumbnailImageView.heightAnchor constraintEqualToAnchor:_artworkBox.heightAnchor multiplier:0.4];
        _squareArtHeightConstraint =
            [_thumbnailImageView.heightAnchor constraintEqualToAnchor:_artworkBox.heightAnchor];
        _artworkStyle = MacLCBrowseArtworkStyleSymbol;
        _symbolHeightConstraint.active = YES;

        _titleHeightConstraint = [_titleLabel.heightAnchor constraintEqualToConstant:
                                  MacLCBrowseWrappedLabelHeight(_titleLabel, 0., 1)];
        _titleHeightConstraint.active = YES;

        [self setAccessibilityElement:YES];
        [self setAccessibilityRole:NSAccessibilityButtonRole];
    }
    return self;
}

+ (CGFloat)titleHeight
{
    static CGFloat height = 0.;
    if (height == 0.) {
        NSTextField * const probe = [NSTextField wrappingLabelWithString:@""];
        probe.font = MacLCDesign.bodyEmphasized;
        height = MacLCBrowseWrappedLabelHeight(probe, 0., (NSInteger)MacLCBrowseItemTitleLineCount);
    }
    return height;
}

+ (CGFloat)heightBelowArtwork
{
    static CGFloat height = 0.;
    if (height == 0.) {
        NSTextField * const probe = [NSTextField labelWithString:@"X"];
        probe.font = MacLCDesign.footnote;
        const CGFloat secondaryHeight = ceil(probe.intrinsicContentSize.height);
        height = 8. + [self titleHeight] + 2. + secondaryHeight + 4.;
    }
    return height;
}

- (void)layout
{
    [super layout];

    /* One or two lines, depending on the title and the tile width. */
    const CGFloat titleWidth = NSWidth(self.bounds);
    _titleLabel.preferredMaxLayoutWidth = titleWidth;
    const CGFloat titleHeight = MacLCBrowseWrappedLabelHeight(_titleLabel, titleWidth,
                                                              (NSInteger)MacLCBrowseItemTitleLineCount);
    if (fabs(_titleHeightConstraint.constant - titleHeight) > 0.5) {
        _titleHeightConstraint.constant = titleHeight;
        [super layout];
    }
}

- (void)setArtworkStyle:(MacLCBrowseArtworkStyle)style
{
    _artworkStyle = style;
    _isFolder = (style == MacLCBrowseArtworkStyleFolder);

    _folderIconHeightConstraint.active = NO;
    _symbolHeightConstraint.active = NO;
    _squareArtHeightConstraint.active = NO;
    switch (style) {
        case MacLCBrowseArtworkStyleFolder:
            _folderIconHeightConstraint.active = YES;
            break;
        case MacLCBrowseArtworkStyleSquareArt:
            _squareArtHeightConstraint.active = YES;
            break;
        case MacLCBrowseArtworkStyleThumbnail:
        case MacLCBrowseArtworkStyleSymbol:
            _symbolHeightConstraint.active = YES;
            break;
    }

    const BOOL showsFill = (style == MacLCBrowseArtworkStyleThumbnail);
    _thumbnailFillView.hidden = !showsFill;
    _thumbnailImageView.hidden = showsFill;
    if (!showsFill) {
        _thumbnailFillView.layer.contents = nil;
    }
    if (_isFolder) {
        _durationBadgeView.hidden = YES;
        _playButton.hidden = YES;
    }
    [self setNeedsDisplay:YES];
}

- (void)showFolderIcon:(NSImage *)icon
{
    [self setArtworkStyle:MacLCBrowseArtworkStyleFolder];
    _thumbnailImageView.contentTintColor = nil;
    _thumbnailImageView.image = icon;
}

- (void)showSymbolNamed:(NSString *)symbolName accessibilityLabel:(nullable NSString *)label
{
    [self setArtworkStyle:MacLCBrowseArtworkStyleSymbol];
    _thumbnailImageView.image = [MacLCDesign symbolNamed:symbolName
                                               pointSize:48.0
                                                  weight:NSFontWeightRegular
                                      accessibilityLabel:label];
    _thumbnailImageView.contentTintColor = MacLCDesign.accent;
}

- (void)showSquareArtwork:(NSImage *)image
{
    [self setArtworkStyle:MacLCBrowseArtworkStyleSquareArt];
    _thumbnailImageView.contentTintColor = nil;
    _thumbnailImageView.image = image;
}

- (void)showThumbnail:(NSImage *)image
{
    [self setArtworkStyle:MacLCBrowseArtworkStyleThumbnail];
    const CGFloat scale = self.window.backingScaleFactor > 0. ? self.window.backingScaleFactor : 2.;
    _thumbnailFillView.layer.contentsScale = [image recommendedLayerContentsScale:scale];
    _thumbnailFillView.layer.contents = [image layerContentsForContentsScale:_thumbnailFillView.layer.contentsScale];
}

- (NSColor *)artworkBackgroundColor
{
    switch (_artworkStyle) {
        case MacLCBrowseArtworkStyleFolder:
            return [MacLCDesign.cardBackground blendedColorWithFraction:0.06 ofColor:NSColor.labelColor]
                ?: MacLCDesign.cardBackground;
        case MacLCBrowseArtworkStyleThumbnail:
            return MacLCDesign.mediaBackground;
        case MacLCBrowseArtworkStyleSquareArt:
        case MacLCBrowseArtworkStyleSymbol:
            return [MacLCDesign.accent colorWithAlphaComponent:0.10];
    }
    return MacLCDesign.cardBackground;
}

- (BOOL)wantsUpdateLayer
{
    return YES;
}

- (void)updateLayer
{
    [super updateLayer];

    _artworkBox.layer.cornerRadius = MacLCDesign.cornerRadiusMedium;
    if (self.isSelected) {
        _artworkBox.layer.borderWidth = 2.0;
        _artworkBox.layer.borderColor = MacLCDesign.accent.CGColor;
        _titleLabel.textColor = MacLCDesign.accent;
    } else {
        _artworkBox.layer.borderWidth = 1.0;
        _artworkBox.layer.borderColor = MacLCDesign.separator.CGColor;
        _titleLabel.textColor = MacLCDesign.primaryLabel;
    }

    _artworkBox.layer.backgroundColor = [self artworkBackgroundColor].CGColor;
    _durationBadgeView.layer.backgroundColor = MacLCDesign.mediaOverlayBackground.CGColor;
}

- (void)updateTrackingAreas
{
    [super updateTrackingAreas];
    if (_trackingArea != nil) {
        [self removeTrackingArea:_trackingArea];
    }
    _trackingArea = [[NSTrackingArea alloc] initWithRect:self.bounds
                                                 options:NSTrackingMouseEnteredAndExited |
                                                         NSTrackingActiveInActiveApp |
                                                         NSTrackingInVisibleRect
                                                   owner:self
                                                userInfo:nil];
    [self addTrackingArea:_trackingArea];
}

- (void)mouseEntered:(NSEvent *)event
{
    _isHovered = YES;
    if (!_isFolder) {
        if (!MacLCDesign.reducedMotion) {
            _playButton.alphaValue = 0.0;
            _playButton.hidden = NO;
            [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
                context.duration = MacLCDesign.motionQuickDuration;
                self->_playButton.animator.alphaValue = 1.0;
            }];
        } else {
            _playButton.alphaValue = 1.0;
            _playButton.hidden = NO;
        }
    }
}

- (void)mouseExited:(NSEvent *)event
{
    _isHovered = NO;
    if (!_isFolder) {
        if (!MacLCDesign.reducedMotion) {
            [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
                context.duration = MacLCDesign.motionQuickDuration;
                self->_playButton.animator.alphaValue = 0.0;
            } completionHandler:^{
                if (!self->_isHovered) {
                    self->_playButton.hidden = YES;
                }
            }];
        } else {
            _playButton.hidden = YES;
        }
    }
}

- (void)setSelected:(BOOL)selected
{
    if (_selected != selected) {
        _selected = selected;
        [self setNeedsDisplay:YES];
    }
}

- (NSMenu *)menuForEvent:(NSEvent *)event
{
    if (event.type == NSEventTypeRightMouseDown ||
        (event.type == NSEventTypeLeftMouseDown && (event.modifierFlags & NSEventModifierFlagControl))) {
        if ([self.nextResponder respondsToSelector:@selector(openContextMenu:)]) {
            [(MacLCBrowseItemCollectionViewItem *)self.nextResponder openContextMenu:event];
            return nil;
        }
    }
    return [super menuForEvent:event];
}

- (void)rightMouseDown:(NSEvent *)event
{
    if ([self.nextResponder respondsToSelector:@selector(openContextMenu:)]) {
        [(MacLCBrowseItemCollectionViewItem *)self.nextResponder openContextMenu:event];
        return;
    }
    [super rightMouseDown:event];
}

@end


@implementation MacLCBrowseItemCollectionViewItem

- (void)loadView
{
    self.view = [[MacLCBrowseItemView alloc] initWithFrame:NSMakeRect(0, 0, 180, 180)];
}

- (MacLCBrowseItemView *)browseItemView
{
    return (MacLCBrowseItemView *)self.view;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    [self.browseItemView.playButton setTarget:self];
    [self.browseItemView.playButton setAction:@selector(playButtonAction:)];
}

- (void)playButtonAction:(id)sender
{
    if ([self.browseDelegate respondsToSelector:@selector(browseItemPlayInstantly:)]) {
        [self.browseDelegate browseItemPlayInstantly:self];
    } else if (self.representedInputItem != nil) {
        [VLCMain.sharedInstance.playQueueController addInputItem:self.representedInputItem.vlcInputItem
                                                      atPosition:-1
                                                   startPlayback:YES];
    }
}

- (void)setRepresentedInputItem:(VLCInputItem *)representedInputItem
{
    _representedInputItem = representedInputItem;
    [self updateRepresentation];
}

- (void)setSecondaryInfoString:(NSString *)secondaryInfoString
{
    _secondaryInfoString = [secondaryInfoString copy];
    self.browseItemView.secondaryLabel.stringValue = secondaryInfoString ?: @"";
}

- (void)setSelected:(BOOL)selected
{
    [super setSelected:selected];
    self.browseItemView.selected = selected;
}

- (void)prepareForReuse
{
    [super prepareForReuse];
    self.representedInputItem = nil;
    self.representedInputNode = nil;
    [self.browseItemView showSymbolNamed:@"film" accessibilityLabel:nil];
    self.browseItemView.titleLabel.stringValue = @"";
    self.browseItemView.secondaryLabel.stringValue = @"";
    self.browseItemView.durationBadgeView.hidden = YES;
    self.browseItemView.playButton.hidden = YES;
    self.selected = NO;
}

- (void)updateRepresentation
{
    VLCInputItem * const inputItem = self.representedInputItem;
    if (inputItem == nil) {
        return;
    }

    MacLCBrowseItemView * const view = self.browseItemView;
    view.titleLabel.stringValue = inputItem.name ?: @"";
    view.needsLayout = YES;

    const enum input_item_type_e inputType = inputItem.inputType;
    const BOOL isDirectory = (inputType == ITEM_TYPE_DIRECTORY || inputType == ITEM_TYPE_NODE || inputType == ITEM_TYPE_PLAYLIST);

    if (isDirectory) {
        // Centred system folder icon
        NSString * const path = inputItem.path;
        NSImage *folderIcon = nil;
        if (path.length > 0 && [NSFileManager.defaultManager fileExistsAtPath:path]) {
            folderIcon = [NSWorkspace.sharedWorkspace iconForFile:path];
        }
        if (folderIcon != nil) {
            [view showFolderIcon:folderIcon];
        } else {
            [view showSymbolNamed:@"folder.fill" accessibilityLabel:_NS("Folder")];
            view.isFolder = YES;
        }
        view.durationBadgeView.hidden = YES;

        if (self.secondaryInfoString.length > 0) {
            view.secondaryLabel.stringValue = self.secondaryInfoString;
        } else {
            view.secondaryLabel.stringValue = _NS("Folder");
        }
    } else {
        // Media item
        const vlc_tick_t duration = inputItem.duration;
        if (duration > 0) {
            view.durationLabel.stringValue = [NSString stringWithTimeFromTicks:duration];
            view.durationBadgeView.hidden = NO;
        } else {
            view.durationBadgeView.hidden = YES;
        }

        if (self.secondaryInfoString.length > 0) {
            view.secondaryLabel.stringValue = self.secondaryInfoString;
        } else if (duration > 0) {
            view.secondaryLabel.stringValue = [NSString stringWithTimeFromTicks:duration];
        } else {
            NSString * const ext = inputItem.MRL.pathExtension.uppercaseString;
            view.secondaryLabel.stringValue = ext.length > 0 ? ext : _NS("Media file");
        }

        // A calm symbol until (or unless) real artwork arrives. Audio files
        // only show real album art: without it, the image cache falls back to
        // Quick Look, which returns a file-type icon.
        NSString * const extension = inputItem.MRL.pathExtension.lowercaseString;
        const BOOL isAudio = [@[@"mp3", @"m4a", @"m4b", @"flac", @"wav", @"aac", @"alac", @"ogg", @"oga",
                                @"opus", @"aif", @"aiff", @"wma", @"ape", @"dsf", @"mka"] containsObject:extension];
        [view showSymbolNamed:isAudio ? @"music.note" : @"film" accessibilityLabel:inputItem.name];
        if (isAudio && inputItem.artworkURL == nil) {
            view.durationBadgeView.hidden = YES;
        } else {
            __weak typeof(self) weakSelf = self;
            [VLCLibraryImageCache thumbnailForInputItem:inputItem
                                         withCompletion:^(NSImage * const thumbnail) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    __strong typeof(weakSelf) strongSelf = weakSelf;
                    if (!strongSelf || strongSelf.representedInputItem != inputItem || thumbnail == nil) {
                        return;
                    }
                    if (isAudio) {
                        [strongSelf.browseItemView showSquareArtwork:thumbnail];
                    } else {
                        [strongSelf.browseItemView showThumbnail:thumbnail];
                    }
                });
            }];
        }
    }

    NSString * const combined = [NSString stringWithFormat:@"%@, %@",
                                 view.titleLabel.stringValue ?: @"",
                                 view.secondaryLabel.stringValue ?: @""];
    [view setAccessibilityLabel:combined];
}

#pragma mark - Mouse and Keyboard Events

- (void)openContextMenu:(NSEvent *)event
{
    if ([self.browseDelegate respondsToSelector:@selector(browseItemOpenContextMenu:forItem:)]) {
        [self.browseDelegate browseItemOpenContextMenu:event forItem:self];
    }
}

- (void)rightMouseDown:(NSEvent *)event
{
    [self openContextMenu:event];
    [super rightMouseDown:event];
}

- (void)mouseDown:(NSEvent *)event
{
    if (event.modifierFlags & NSEventModifierFlagControl) {
        [self openContextMenu:event];
        return;
    }

    if (event.clickCount == 2) {
        if ([self.browseDelegate respondsToSelector:@selector(browseItemDidDoubleClick:)]) {
            [self.browseDelegate browseItemDidDoubleClick:self];
            return;
        }
    }

    [super mouseDown:event];
}

- (void)keyDown:(NSEvent *)event
{
    if (event.characters.length > 0) {
        const unichar key = [event.characters characterAtIndex:0];
        if (key == '\r' || key == '\n' || event.keyCode == 36 || event.keyCode == 76) {
            if ([self.browseDelegate respondsToSelector:@selector(browseItemDidDoubleClick:)]) {
                [self.browseDelegate browseItemDidDoubleClick:self];
                return;
            }
        }
    }
    [super keyDown:event];
}

@end
