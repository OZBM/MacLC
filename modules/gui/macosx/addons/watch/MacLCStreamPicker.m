/*****************************************************************************
 * MacLCStreamPicker.m: "Choose a Version" sheet
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

#import "addons/watch/MacLCStreamPicker.h"
#import "addons/MacLCStreamFacts.h"
#import "addons/watch/MacLCExplainer.h"
#import "addons/watch/MacLCWatchComponents.h"
#import "addons/watch/MacLCWatchLibrary.h"
#import "addons/watch/MacLCWatchPlayback.h"
#import "addons/MacLCAddons.h"
#import "theme/MacLCDesign.h"
#import "main/VLCMain.h"
#import "playqueue/VLCPlayQueueController.h"
#import "windows/VLCOpenInputMetadata.h"
#import "settings/MacLCSettingsWindowController.h"
#import "extensions/NSString+Helpers.h"

#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

/// "52:10", "1:12:05": a position in seconds.
static NSString *ClockText(NSTimeInterval seconds)
{
    const long total = (long)MAX(0.0, seconds);
    if (total >= 3600) {
        return [NSString stringWithFormat:@"%ld:%02ld:%02ld", total / 3600, (total / 60) % 60, total % 60];
    }
    return [NSString stringWithFormat:@"%ld:%02ld", total / 60, total % 60];
}

#pragma mark - Topic Mapping Helpers

static MacLCExplainerTopic _Nullable TopicForResolution(MacLCStreamResolution res)
{
    switch (res) {
        case MacLCStreamResolution4K: return MacLCExplainerTopicResolution4K;
        case MacLCStreamResolution1080p: return MacLCExplainerTopicResolution1080p;
        case MacLCStreamResolution720p: return MacLCExplainerTopicResolution720p;
        default: return nil;
    }
}

static MacLCExplainerTopic _Nullable TopicForDynamicRange(MacLCStreamDynamicRange dr)
{
    switch (dr) {
        case MacLCStreamDynamicRangeDolbyVision: return MacLCExplainerTopicDolbyVision;
        case MacLCStreamDynamicRangeHDR10Plus: return MacLCExplainerTopicHDR10Plus;
        case MacLCStreamDynamicRangeHDR10:
        case MacLCStreamDynamicRangeHDR: return MacLCExplainerTopicHDR10;
        case MacLCStreamDynamicRangeHLG: return MacLCExplainerTopicHLG;
        case MacLCStreamDynamicRangeSDR: return MacLCExplainerTopicSDR;
        default: return nil;
    }
}

static MacLCExplainerTopic _Nullable TopicForSource(MacLCStreamSource src)
{
    switch (src) {
        case MacLCStreamSourceRemux: return MacLCExplainerTopicRemux;
        case MacLCStreamSourceBluRay: return MacLCExplainerTopicBluRay;
        case MacLCStreamSourceWebDL: return MacLCExplainerTopicWebDL;
        case MacLCStreamSourceWebRip: return MacLCExplainerTopicWebRip;
        case MacLCStreamSourceCam:
        case MacLCStreamSourceTelesync:
        case MacLCStreamSourceScreener: return MacLCExplainerTopicCam;
        default: return nil;
    }
}

static MacLCExplainerTopic _Nullable TopicForAudio(MacLCStreamAudio *audio)
{
    if (audio.isImmersive) return MacLCExplainerTopicAtmos;
    if (audio.isLossless) return MacLCExplainerTopicLosslessAudio;
    if ([audio.channels isEqualToString:@"7.1"] || [audio.channels isEqualToString:@"5.1"]) {
        return MacLCExplainerTopicSurround;
    }
    return nil;
}

#pragma mark - Resolution Tile View

@interface MacLCStreamResolutionTileView : NSView
@property (nonatomic, strong) NSTextField *label;
- (void)configureWithResolution:(MacLCStreamResolution)resolution;
@end

@implementation MacLCStreamResolutionTileView

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        self.layer.cornerRadius = MacLCDesign.cornerRadiusMedium;
        self.layer.masksToBounds = YES;
        self.layer.backgroundColor = NSColor.quaternarySystemFillColor.CGColor;

        [self.widthAnchor constraintEqualToConstant:64.0].active = YES; /* "1080p" fits */
        [self.heightAnchor constraintEqualToConstant:40.0].active = YES;

        _label = [NSTextField labelWithString:@""];
        _label.translatesAutoresizingMaskIntoConstraints = NO;
        _label.alignment = NSTextAlignmentCenter;
        [self addSubview:_label];

        [NSLayoutConstraint activateConstraints:@[
            [_label.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [_label.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_label.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.leadingAnchor constant:2.0],
            [_label.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-2.0],
        ]];
    }
    return self;
}

- (void)configureWithResolution:(MacLCStreamResolution)resolution
{
    CGFloat const pointSize = MacLCDesign.title2.pointSize;
    NSFont *baseFont = [NSFont systemFontOfSize:pointSize weight:NSFontWeightHeavy];
    NSFontDescriptor *desc = [[baseFont fontDescriptor] fontDescriptorWithDesign:NSFontDescriptorSystemDesignRounded];
    NSFont *roundedHeavy = desc ? ([NSFont fontWithDescriptor:desc size:pointSize] ?: baseFont) : baseFont;
    NSColor *textColor = NSColor.labelColor;

    NSAttributedString *attrStr = nil;
    switch (resolution) {
        case MacLCStreamResolution4K:
            attrStr = [[NSAttributedString alloc] initWithString:@"4K"
                                                      attributes:@{ NSFontAttributeName: roundedHeavy,
                                                                    NSForegroundColorAttributeName: textColor }];
            break;
        case MacLCStreamResolution1080p: {
            NSMutableAttributedString *mas = [[NSMutableAttributedString alloc] initWithString:@"1080"
                                                                                     attributes:@{ NSFontAttributeName: roundedHeavy,
                                                                                                   NSForegroundColorAttributeName: textColor }];
            NSFont *pFont = desc ? ([NSFont fontWithDescriptor:desc size:10.0] ?: [NSFont systemFontOfSize:10.0 weight:NSFontWeightBold])
                                 : [NSFont systemFontOfSize:10.0 weight:NSFontWeightBold];
            [mas appendAttributedString:[[NSAttributedString alloc] initWithString:@"p"
                                                                        attributes:@{ NSFontAttributeName: pFont,
                                                                                      NSForegroundColorAttributeName: textColor,
                                                                                      NSBaselineOffsetAttributeName: @(1.0) }]];
            attrStr = mas;
            break;
        }
        case MacLCStreamResolution720p: {
            NSMutableAttributedString *mas = [[NSMutableAttributedString alloc] initWithString:@"720"
                                                                                     attributes:@{ NSFontAttributeName: roundedHeavy,
                                                                                                   NSForegroundColorAttributeName: textColor }];
            NSFont *pFont = desc ? ([NSFont fontWithDescriptor:desc size:10.0] ?: [NSFont systemFontOfSize:10.0 weight:NSFontWeightBold])
                                 : [NSFont systemFontOfSize:10.0 weight:NSFontWeightBold];
            [mas appendAttributedString:[[NSAttributedString alloc] initWithString:@"p"
                                                                        attributes:@{ NSFontAttributeName: pFont,
                                                                                      NSForegroundColorAttributeName: textColor,
                                                                                      NSBaselineOffsetAttributeName: @(1.0) }]];
            attrStr = mas;
            break;
        }
        case MacLCStreamResolutionSD:
            attrStr = [[NSAttributedString alloc] initWithString:@"SD"
                                                      attributes:@{ NSFontAttributeName: roundedHeavy,
                                                                    NSForegroundColorAttributeName: textColor }];
            break;
        default:
            attrStr = [[NSAttributedString alloc] initWithString:@"?"
                                                      attributes:@{ NSFontAttributeName: roundedHeavy,
                                                                    NSForegroundColorAttributeName: textColor }];
            break;
    }

    _label.attributedStringValue = attrStr;
    [MacLCExplainer attachToView:self topic:TopicForResolution(resolution)];
}

@end

#pragma mark - Verdict Pill View

@interface MacLCStreamVerdictPillView : NSView
@property (nonatomic, strong) NSImageView *iconView;
@property (nonatomic, strong) NSTextField *label;
- (void)configureWithVerdict:(MacLCStreamVerdict)verdict;
@end

@implementation MacLCStreamVerdictPillView

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        self.layer.cornerRadius = 10.0;
        self.layer.masksToBounds = YES;
        [self.heightAnchor constraintEqualToConstant:20.0].active = YES;

        _iconView = [[NSImageView alloc] initWithFrame:NSZeroRect];
        _iconView.translatesAutoresizingMaskIntoConstraints = NO;
        _iconView.imageScaling = NSImageScaleProportionallyUpOrDown;
        [self addSubview:_iconView];

        _label = [NSTextField labelWithString:@""];
        _label.translatesAutoresizingMaskIntoConstraints = NO;
        _label.font = [NSFont systemFontOfSize:11.0 weight:NSFontWeightSemibold];
        [self addSubview:_label];

        [NSLayoutConstraint activateConstraints:@[
            [_iconView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:6.0],
            [_iconView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_iconView.widthAnchor constraintEqualToConstant:12.0],
            [_iconView.heightAnchor constraintEqualToConstant:12.0],

            [_label.leadingAnchor constraintEqualToAnchor:_iconView.trailingAnchor constant:3.0],
            [_label.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-6.0],
            [_label.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        ]];
    }
    return self;
}

- (void)configureWithVerdict:(MacLCStreamVerdict)verdict
{
    NSString *symbolName = nil;
    NSColor *tint = nil;
    NSString *word = [MacLCStreamFacts nameForVerdict:verdict];

    switch (verdict) {
        case MacLCStreamVerdictGreat:
            symbolName = @"checkmark.seal.fill";
            tint = NSColor.systemGreenColor;
            break;
        case MacLCStreamVerdictGood:
            symbolName = @"hand.thumbsup.fill";
            tint = NSColor.systemTealColor;
            break;
        case MacLCStreamVerdictOkay:
            symbolName = @"minus.circle.fill";
            tint = NSColor.secondaryLabelColor;
            break;
        case MacLCStreamVerdictPoor:
            symbolName = @"exclamationmark.triangle.fill";
            tint = NSColor.systemOrangeColor;
            break;
        default:
            symbolName = @"questionmark.circle";
            tint = NSColor.secondaryLabelColor;
            break;
    }

    self.layer.backgroundColor = [tint colorWithAlphaComponent:0.15].CGColor;
    _iconView.image = [NSImage imageWithSystemSymbolName:symbolName accessibilityDescription:nil];
    _iconView.contentTintColor = tint;
    _label.stringValue = word ?: @"";
    _label.textColor = tint;

    [MacLCExplainer attachToView:self topic:MacLCExplainerTopicVerdict];
}

@end

#pragma mark - Fact Chip View

@interface MacLCStreamChipView : NSView
@property (nonatomic, strong) NSImageView *iconView;
@property (nonatomic, strong) NSTextField *label;
@property (nonatomic, strong) NSLayoutConstraint *iconWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *labelLeadingToIcon;
@property (nonatomic, strong) NSLayoutConstraint *labelLeadingToSelf;
- (void)configureWithText:(NSString *)text
                   symbol:(nullable NSString *)symbolName
                    topic:(nullable MacLCExplainerTopic)topic;
@end

@implementation MacLCStreamChipView

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        self.layer.cornerRadius = 10.0;
        self.layer.masksToBounds = YES;
        self.layer.backgroundColor = NSColor.quaternarySystemFillColor.CGColor;
        [self.heightAnchor constraintEqualToConstant:20.0].active = YES;

        _iconView = [[NSImageView alloc] initWithFrame:NSZeroRect];
        _iconView.translatesAutoresizingMaskIntoConstraints = NO;
        _iconView.imageScaling = NSImageScaleProportionallyUpOrDown;
        [self addSubview:_iconView];

        _label = [NSTextField labelWithString:@""];
        _label.translatesAutoresizingMaskIntoConstraints = NO;
        _label.font = [NSFont systemFontOfSize:11.0 weight:NSFontWeightMedium];
        _label.textColor = NSColor.labelColor;
        [self addSubview:_label];

        _iconWidthConstraint = [_iconView.widthAnchor constraintEqualToConstant:12.0];
        _labelLeadingToIcon = [_label.leadingAnchor constraintEqualToAnchor:_iconView.trailingAnchor constant:3.0];
        _labelLeadingToSelf = [_label.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:6.0];

        [NSLayoutConstraint activateConstraints:@[
            [_iconView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:6.0],
            [_iconView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            _iconWidthConstraint,
            [_iconView.heightAnchor constraintEqualToConstant:12.0],

            [_label.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-6.0],
            [_label.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        ]];
    }
    return self;
}

- (void)configureWithText:(NSString *)text
                   symbol:(nullable NSString *)symbolName
                    topic:(nullable MacLCExplainerTopic)topic
{
    _label.stringValue = text ?: @"";
    if (symbolName.length > 0) {
        _iconView.image = [NSImage imageWithSystemSymbolName:symbolName accessibilityDescription:nil];
        _iconView.contentTintColor = NSColor.labelColor;
        _iconView.hidden = NO;
        _iconWidthConstraint.constant = 12.0;
        _labelLeadingToSelf.active = NO;
        _labelLeadingToIcon.active = YES;
    } else {
        _iconView.image = nil;
        _iconView.hidden = YES;
        _iconWidthConstraint.constant = 0.0;
        _labelLeadingToIcon.active = NO;
        _labelLeadingToSelf.active = YES;
    }

    [MacLCExplainer attachToView:self topic:topic];
}

@end

#pragma mark - Health Meter View

@interface MacLCStreamHealthMeterView : NSView
@property (nonatomic, assign) MacLCStreamHealth health;
- (void)configureWithHealth:(MacLCStreamHealth)health;
@end

@implementation MacLCStreamHealthMeterView

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        [self.widthAnchor constraintEqualToConstant:18.0].active = YES;
        [self.heightAnchor constraintEqualToConstant:15.0].active = YES;
    }
    return self;
}

- (BOOL)isFlipped
{
    return YES;
}

- (void)drawRect:(NSRect)dirtyRect
{
    [super drawRect:dirtyRect];

    const CGFloat barWidth = 3.0;
    const CGFloat barSpacing = 2.0;
    const CGFloat heights[4] = { 6.0, 9.0, 12.0, 15.0 };

    NSInteger filledCount = 0;
    NSColor *fillColor = NSColor.quaternaryLabelColor;
    switch (_health) {
        case MacLCStreamHealthExcellent:
            filledCount = 4;
            fillColor = NSColor.systemGreenColor;
            break;
        case MacLCStreamHealthGood:
            filledCount = 3;
            fillColor = NSColor.systemGreenColor;
            break;
        case MacLCStreamHealthFair:
            filledCount = 2;
            fillColor = NSColor.systemYellowColor;
            break;
        case MacLCStreamHealthWeak:
            filledCount = 1;
            fillColor = NSColor.systemOrangeColor;
            break;
        case MacLCStreamHealthNone:
            filledCount = 0;
            fillColor = NSColor.systemOrangeColor;
            break;
        default:
            filledCount = 0;
            fillColor = NSColor.quaternaryLabelColor;
            break;
    }

    for (NSInteger i = 0; i < 4; i++) {
        CGFloat const h = heights[i];
        CGFloat const x = i * (barWidth + barSpacing);
        CGFloat const y = 15.0 - h;
        NSRect const barRect = NSMakeRect(x, y, barWidth, h);
        NSColor *color = (i < filledCount) ? fillColor : NSColor.quaternaryLabelColor;
        [color setFill];
        NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:barRect xRadius:1.0 yRadius:1.0];
        [path fill];
    }
}

- (void)configureWithHealth:(MacLCStreamHealth)health
{
    _health = health;
    self.toolTip = [MacLCStreamFacts nameForHealth:health];
    [MacLCExplainer attachToView:self topic:MacLCExplainerTopicHealth];
    self.needsDisplay = YES;
}

@end

#pragma mark - Stream Table View (Return / Escape handling)

@interface MacLCStreamTableView : NSTableView
@property (nonatomic, copy, nullable) void (^returnKeyHandler)(void);
@property (nonatomic, copy, nullable) void (^escapeKeyHandler)(void);
@end

@implementation MacLCStreamTableView

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

#pragma mark - Placeholder Cell View

@interface MacLCStreamPlaceholderCellView : NSTableCellView
@end

@implementation MacLCStreamPlaceholderCellView

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        NSView *tile = [[NSView alloc] initWithFrame:NSZeroRect];
        tile.translatesAutoresizingMaskIntoConstraints = NO;
        tile.wantsLayer = YES;
        tile.layer.cornerRadius = MacLCDesign.cornerRadiusMedium;
        tile.layer.backgroundColor = NSColor.quaternarySystemFillColor.CGColor;
        [self addSubview:tile];

        NSView *bar1 = [[NSView alloc] initWithFrame:NSZeroRect];
        bar1.translatesAutoresizingMaskIntoConstraints = NO;
        bar1.wantsLayer = YES;
        bar1.layer.cornerRadius = 4.0;
        bar1.layer.backgroundColor = NSColor.quaternarySystemFillColor.CGColor;
        [self addSubview:bar1];

        NSView *bar2 = [[NSView alloc] initWithFrame:NSZeroRect];
        bar2.translatesAutoresizingMaskIntoConstraints = NO;
        bar2.wantsLayer = YES;
        bar2.layer.cornerRadius = 4.0;
        bar2.layer.backgroundColor = NSColor.quaternarySystemFillColor.CGColor;
        [self addSubview:bar2];

        NSView *trailingBar = [[NSView alloc] initWithFrame:NSZeroRect];
        trailingBar.translatesAutoresizingMaskIntoConstraints = NO;
        trailingBar.wantsLayer = YES;
        trailingBar.layer.cornerRadius = 4.0;
        trailingBar.layer.backgroundColor = NSColor.quaternarySystemFillColor.CGColor;
        [self addSubview:trailingBar];

        [NSLayoutConstraint activateConstraints:@[
            [tile.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12.0],
            [tile.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [tile.widthAnchor constraintEqualToConstant:52.0],
            [tile.heightAnchor constraintEqualToConstant:40.0],

            [bar1.leadingAnchor constraintEqualToAnchor:tile.trailingAnchor constant:12.0],
            [bar1.topAnchor constraintEqualToAnchor:self.topAnchor constant:22.0],
            [bar1.widthAnchor constraintEqualToConstant:180.0],
            [bar1.heightAnchor constraintEqualToConstant:14.0],

            [bar2.leadingAnchor constraintEqualToAnchor:tile.trailingAnchor constant:12.0],
            [bar2.topAnchor constraintEqualToAnchor:bar1.bottomAnchor constant:8.0],
            [bar2.widthAnchor constraintEqualToConstant:260.0],
            [bar2.heightAnchor constraintEqualToConstant:12.0],

            [trailingBar.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16.0],
            [trailingBar.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [trailingBar.widthAnchor constraintEqualToConstant:60.0],
            [trailingBar.heightAnchor constraintEqualToConstant:14.0],
        ]];
    }
    return self;
}

@end

#pragma mark - Table Row Cell View

@interface MacLCStreamRowCellView : NSTableCellView
@property (nonatomic, strong) MacLCStreamResolutionTileView *resTile;
@property (nonatomic, strong) MacLCStreamVerdictPillView *verdictPill;
@property (nonatomic, strong) NSStackView *chipsStack;
@property (nonatomic, strong) NSTextField *line2Label;
@property (nonatomic, strong) NSView *cautionRow;
@property (nonatomic, strong) NSTextField *cautionLabel;

@property (nonatomic, strong) MacLCStreamHealthMeterView *healthMeter;
@property (nonatomic, strong) NSTextField *peersLabel;
@property (nonatomic, strong) NSTextField *sizeLabel;

@property (nonatomic, strong, nullable) MacLCStreamChoice *choice;
@property (nonatomic, copy, nullable) void (^playHandler)(void);
@property (nonatomic, copy, nullable) void (^queueHandler)(void);

- (void)configureWithChoice:(MacLCStreamChoice *)choice;
@end

@implementation MacLCStreamRowCellView

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        _resTile = [[MacLCStreamResolutionTileView alloc] initWithFrame:NSZeroRect];
        _resTile.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_resTile];

        _verdictPill = [[MacLCStreamVerdictPillView alloc] initWithFrame:NSZeroRect];
        _verdictPill.translatesAutoresizingMaskIntoConstraints = NO;

        _chipsStack = [[NSStackView alloc] initWithFrame:NSZeroRect];
        _chipsStack.translatesAutoresizingMaskIntoConstraints = NO;
        _chipsStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
        _chipsStack.alignment = NSLayoutAttributeCenterY;
        _chipsStack.spacing = 6.0;

        NSStackView *line1Stack = [NSStackView stackViewWithViews:@[_verdictPill, _chipsStack]];
        line1Stack.translatesAutoresizingMaskIntoConstraints = NO;
        line1Stack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
        line1Stack.alignment = NSLayoutAttributeCenterY;
        line1Stack.spacing = 6.0;

        _line2Label = [NSTextField labelWithString:@""];
        _line2Label.translatesAutoresizingMaskIntoConstraints = NO;
        _line2Label.font = MacLCDesign.footnote;
        _line2Label.textColor = MacLCDesign.tertiaryLabel;
        _line2Label.lineBreakMode = NSLineBreakByTruncatingMiddle;
        _line2Label.maximumNumberOfLines = 1;

        _cautionRow = [[NSView alloc] initWithFrame:NSZeroRect];
        _cautionRow.translatesAutoresizingMaskIntoConstraints = NO;
        NSImageView *cautionIcon = [[NSImageView alloc] initWithFrame:NSZeroRect];
        cautionIcon.translatesAutoresizingMaskIntoConstraints = NO;
        cautionIcon.image = [NSImage imageWithSystemSymbolName:@"exclamationmark.triangle.fill" accessibilityDescription:nil];
        cautionIcon.contentTintColor = NSColor.systemOrangeColor;
        [_cautionRow addSubview:cautionIcon];

        _cautionLabel = [NSTextField labelWithString:@""];
        _cautionLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _cautionLabel.font = MacLCDesign.footnote;
        _cautionLabel.textColor = NSColor.systemOrangeColor;
        _cautionLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _cautionLabel.maximumNumberOfLines = 1;
        [_cautionRow addSubview:_cautionLabel];

        [NSLayoutConstraint activateConstraints:@[
            [cautionIcon.leadingAnchor constraintEqualToAnchor:_cautionRow.leadingAnchor],
            [cautionIcon.centerYAnchor constraintEqualToAnchor:_cautionRow.centerYAnchor],
            [cautionIcon.widthAnchor constraintEqualToConstant:12.0],
            [cautionIcon.heightAnchor constraintEqualToConstant:12.0],

            [_cautionLabel.leadingAnchor constraintEqualToAnchor:cautionIcon.trailingAnchor constant:4.0],
            [_cautionLabel.trailingAnchor constraintEqualToAnchor:_cautionRow.trailingAnchor],
            [_cautionLabel.centerYAnchor constraintEqualToAnchor:_cautionRow.centerYAnchor],
            [_cautionRow.heightAnchor constraintEqualToConstant:16.0],
        ]];

        NSStackView *middleStack = [NSStackView stackViewWithViews:@[line1Stack, _line2Label, _cautionRow]];
        middleStack.translatesAutoresizingMaskIntoConstraints = NO;
        middleStack.orientation = NSUserInterfaceLayoutOrientationVertical;
        middleStack.alignment = NSLayoutAttributeLeading;
        middleStack.spacing = 2.0;
        [self addSubview:middleStack];

        _healthMeter = [[MacLCStreamHealthMeterView alloc] initWithFrame:NSZeroRect];
        _healthMeter.translatesAutoresizingMaskIntoConstraints = NO;

        _peersLabel = [NSTextField labelWithString:@""];
        _peersLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _peersLabel.font = [MacLCDesign monospacedDigitFontForTextStyle:NSFontTextStyleFootnote];
        _peersLabel.textColor = MacLCDesign.secondaryLabel;
        _peersLabel.alignment = NSTextAlignmentRight;

        _sizeLabel = [NSTextField labelWithString:@""];
        _sizeLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _sizeLabel.font = MacLCDesign.footnote;
        _sizeLabel.textColor = MacLCDesign.secondaryLabel;
        _sizeLabel.alignment = NSTextAlignmentRight;

        NSStackView *trailingStack = [NSStackView stackViewWithViews:@[_healthMeter, _peersLabel, _sizeLabel]];
        trailingStack.translatesAutoresizingMaskIntoConstraints = NO;
        trailingStack.orientation = NSUserInterfaceLayoutOrientationVertical;
        trailingStack.alignment = NSLayoutAttributeTrailing;
        trailingStack.spacing = 2.0;
        [self addSubview:trailingStack];

        [NSLayoutConstraint activateConstraints:@[
            [_resTile.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12.0],
            [_resTile.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],

            [middleStack.leadingAnchor constraintEqualToAnchor:_resTile.trailingAnchor constant:12.0],
            [middleStack.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [middleStack.trailingAnchor constraintLessThanOrEqualToAnchor:trailingStack.leadingAnchor constant:-12.0],

            [trailingStack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16.0],
            [trailingStack.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        ]];
    }
    return self;
}

- (void)configureWithChoice:(MacLCStreamChoice *)choice
{
    _choice = choice;
    MacLCStreamFacts *facts = choice.facts;

    [_resTile configureWithResolution:facts.resolution];
    [_verdictPill configureWithVerdict:facts.verdict];

    for (NSView *v in [_chipsStack.arrangedSubviews copy]) {
        [_chipsStack removeView:v];
        [v removeFromSuperview];
    }

    if (facts.dynamicRange != MacLCStreamDynamicRangeUnknown) {
        NSString *drName = [MacLCStreamFacts nameForDynamicRange:facts.dynamicRange];
        MacLCExplainerTopic drTopic = TopicForDynamicRange(facts.dynamicRange);
        MacLCStreamChipView *chip = [[MacLCStreamChipView alloc] init];
        [chip configureWithText:drName symbol:nil topic:drTopic];
        [_chipsStack addArrangedSubview:chip];
    }

    if (facts.audio.count > 0) {
        MacLCStreamAudio *a = facts.audio.firstObject;
        NSString *aStr = (a.channels.length > 0) ? [NSString stringWithFormat:@"%@ %@", a.format, a.channels] : a.format;
        MacLCExplainerTopic aTopic = TopicForAudio(a);
        MacLCStreamChipView *chip = [[MacLCStreamChipView alloc] init];
        [chip configureWithText:aStr symbol:nil topic:aTopic];
        [_chipsStack addArrangedSubview:chip];
    }

    if (facts.isMultiLanguage) {
        MacLCStreamChipView *chip = [[MacLCStreamChipView alloc] init];
        [chip configureWithText:_NS("Multi-language") symbol:@"globe" topic:MacLCExplainerTopicMultiAudio];
        [_chipsStack addArrangedSubview:chip];
    } else if (facts.languages.count > 0) {
        NSMutableArray *langNames = [NSMutableArray array];
        for (NSString *code in facts.languages) {
            [langNames addObject:[MacLCStreamFacts displayNameForLanguage:code]];
        }
        MacLCStreamChipView *chip = [[MacLCStreamChipView alloc] init];
        [chip configureWithText:[langNames componentsJoinedByString:@", "] symbol:nil topic:nil];
        [_chipsStack addArrangedSubview:chip];
    }

    if (facts.source != MacLCStreamSourceUnknown) {
        NSString *srcName = [MacLCStreamFacts nameForSource:facts.source];
        MacLCExplainerTopic srcTopic = TopicForSource(facts.source);
        MacLCStreamChipView *chip = [[MacLCStreamChipView alloc] init];
        [chip configureWithText:srcName symbol:nil topic:srcTopic];
        [_chipsStack addArrangedSubview:chip];
    }

    if (facts.isPack) {
        MacLCStreamChipView *chip = [[MacLCStreamChipView alloc] init];
        [chip configureWithText:_NS("Season pack") symbol:nil topic:MacLCExplainerTopicPack];
        [_chipsStack addArrangedSubview:chip];
    }

    NSString *rel = facts.releaseName;
    NSString *addonName = choice.stream.addon.name;
    NSString *provider = facts.provider;
    NSMutableArray *parts = [NSMutableArray array];
    if (addonName.length > 0) [parts addObject:addonName];
    if (provider.length > 0) [parts addObject:provider];
    NSString *metaInfo = [parts componentsJoinedByString:@" · "];
    if (metaInfo.length > 0) {
        _line2Label.stringValue = [NSString stringWithFormat:@"%@ · %@", rel, metaInfo];
    } else {
        _line2Label.stringValue = rel ?: @"";
    }
    _line2Label.toolTip = rel ?: @"";

    if (facts.cautions.count > 0) {
        _cautionRow.hidden = NO;
        _cautionLabel.stringValue = facts.cautions.firstObject;
    } else {
        _cautionRow.hidden = YES;
    }

    [_healthMeter configureWithHealth:facts.health];

    if (facts.debridService.length > 0) {
        _peersLabel.stringValue = _NS("Cached");
        [MacLCExplainer attachToView:_peersLabel topic:MacLCExplainerTopicDebrid];
        _peersLabel.hidden = NO;
    } else if (facts.seeders >= 0) {
        _peersLabel.stringValue = facts.seeders == 1 ? _NS("1 peer")
                                                     : [NSString stringWithFormat:_NS("%ld peers"), (long)facts.seeders];
        [MacLCExplainer attachToView:_peersLabel topic:MacLCExplainerTopicPeers];
        _peersLabel.hidden = NO;
    } else {
        _peersLabel.hidden = YES;
    }

    if (facts.sizeBytes > 0) {
        _sizeLabel.stringValue = [MacLCStreamFacts displaySize:facts.sizeBytes];
        [MacLCExplainer attachToView:_sizeLabel topic:MacLCExplainerTopicSize];
        _sizeLabel.hidden = NO;
    } else {
        _sizeLabel.hidden = YES;
    }

    [self updateVoiceOver];
}

- (void)updateVoiceOver
{
    MacLCStreamFacts *facts = _choice.facts;
    NSMutableArray<NSString *> *elements = [NSMutableArray array];
    if (facts.verdict != MacLCStreamVerdictUnknown) {
        [elements addObject:[MacLCStreamFacts nameForVerdict:facts.verdict]];
    }
    if (facts.resolution != MacLCStreamResolutionUnknown) {
        [elements addObject:[MacLCStreamFacts nameForResolution:facts.resolution]];
    }
    if (facts.dynamicRange != MacLCStreamDynamicRangeUnknown) {
        [elements addObject:[MacLCStreamFacts nameForDynamicRange:facts.dynamicRange]];
    }
    if (facts.audio.count > 0) {
        MacLCStreamAudio *a = facts.audio.firstObject;
        if (a.channels.length > 0) {
            [elements addObject:[NSString stringWithFormat:@"%@ %@", a.format, a.channels]];
        } else {
            [elements addObject:a.format];
        }
    }
    if (facts.isMultiLanguage) {
        [elements addObject:_NS("Multi-language")];
    } else if (facts.languages.count > 0) {
        NSMutableArray *langNames = [NSMutableArray array];
        for (NSString *code in facts.languages) {
            [langNames addObject:[MacLCStreamFacts displayNameForLanguage:code]];
        }
        [elements addObject:[langNames componentsJoinedByString:@", "]];
    }
    if (facts.debridService.length > 0) {
        [elements addObject:_NS("Cached")];
    } else if (facts.seeders >= 0) {
        [elements addObject:[NSString stringWithFormat:_NS("%ld people sharing"), (long)facts.seeders]];
    }
    if (facts.health != MacLCStreamHealthUnknown) {
        [elements addObject:[MacLCStreamFacts nameForHealth:facts.health]];
    }
    if (facts.sizeBytes > 0) {
        [elements addObject:[MacLCStreamFacts displaySize:facts.sizeBytes]];
    }
    if (facts.releaseName.length > 0) {
        [elements addObject:facts.releaseName];
    }

    self.accessibilityElement = YES;
    self.accessibilityLabel = [elements componentsJoinedByString:@", "];

    __weak typeof(self) weakSelf = self;
    NSAccessibilityCustomAction *playAct = [[NSAccessibilityCustomAction alloc] initWithName:_NS("Play") handler:^BOOL{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf && strongSelf.playHandler) {
            strongSelf.playHandler();
            return YES;
        }
        return NO;
    }];
    NSAccessibilityCustomAction *queueAct = [[NSAccessibilityCustomAction alloc] initWithName:_NS("Add to Queue") handler:^BOOL{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf && strongSelf.queueHandler) {
            strongSelf.queueHandler();
            return YES;
        }
        return NO;
    }];
    self.accessibilityCustomActions = @[playAct, queueAct];
}

@end

#pragma mark - Best Match Card View

@interface MacLCStreamBestMatchCardView : NSView
@property (nonatomic, assign) BOOL selected;
@property (nonatomic, strong, nullable) MacLCStreamChoice *choice;
@property (nonatomic, copy, nullable) void (^selectHandler)(void);
@property (nonatomic, copy, nullable) void (^playHandler)(void);

@property (nonatomic, strong) MacLCStreamResolutionTileView *resTile;
@property (nonatomic, strong) NSTextField *factsLabel;
@property (nonatomic, strong) NSStackView *reasonsStack;

@property (nonatomic, strong) MacLCStreamHealthMeterView *healthMeter;
@property (nonatomic, strong) NSTextField *peersLabel;
@property (nonatomic, strong) NSButton *peersInfoButton;
@property (nonatomic, strong) NSTextField *sizeLabel;

- (void)configureWithChoice:(MacLCStreamChoice *)choice filter:(MacLCStreamFilter *)filter;
@end

@implementation MacLCStreamBestMatchCardView

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        self.layer.cornerRadius = MacLCDesign.cornerRadiusLarge;
        self.layer.masksToBounds = YES;
        self.layer.borderWidth = 1.0;
        self.layer.borderColor = MacLCDesign.separator.CGColor;
        self.layer.backgroundColor = MacLCDesign.cardBackground.CGColor;

        _resTile = [[MacLCStreamResolutionTileView alloc] initWithFrame:NSZeroRect];
        _resTile.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_resTile];

        _factsLabel = [NSTextField labelWithString:@""];
        _factsLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _factsLabel.font = MacLCDesign.callout;
        _factsLabel.textColor = MacLCDesign.primaryLabel;
        _factsLabel.lineBreakMode = NSLineBreakByTruncatingTail;

        _reasonsStack = [[NSStackView alloc] initWithFrame:NSZeroRect];
        _reasonsStack.translatesAutoresizingMaskIntoConstraints = NO;
        _reasonsStack.orientation = NSUserInterfaceLayoutOrientationVertical;
        _reasonsStack.alignment = NSLayoutAttributeLeading;
        _reasonsStack.spacing = 3.0;

        NSStackView *middleStack = [NSStackView stackViewWithViews:@[_factsLabel, _reasonsStack]];
        middleStack.translatesAutoresizingMaskIntoConstraints = NO;
        middleStack.orientation = NSUserInterfaceLayoutOrientationVertical;
        middleStack.alignment = NSLayoutAttributeLeading;
        middleStack.spacing = 4.0;
        [self addSubview:middleStack];

        _healthMeter = [[MacLCStreamHealthMeterView alloc] initWithFrame:NSZeroRect];
        _healthMeter.translatesAutoresizingMaskIntoConstraints = NO;

        _peersLabel = [NSTextField labelWithString:@""];
        _peersLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _peersLabel.font = [MacLCDesign monospacedDigitFontForTextStyle:NSFontTextStyleFootnote];
        _peersLabel.textColor = MacLCDesign.secondaryLabel;
        _peersLabel.alignment = NSTextAlignmentRight;

        _peersInfoButton = [MacLCExplainer infoButtonForTopic:MacLCExplainerTopicPeers];
        _peersInfoButton.translatesAutoresizingMaskIntoConstraints = NO;

        NSStackView *peersRow = [NSStackView stackViewWithViews:@[_healthMeter, _peersLabel, _peersInfoButton]];
        peersRow.translatesAutoresizingMaskIntoConstraints = NO;
        peersRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
        peersRow.alignment = NSLayoutAttributeCenterY;
        peersRow.spacing = 4.0;

        _sizeLabel = [NSTextField labelWithString:@""];
        _sizeLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _sizeLabel.font = MacLCDesign.footnote;
        _sizeLabel.textColor = MacLCDesign.secondaryLabel;
        _sizeLabel.alignment = NSTextAlignmentRight;

        NSStackView *trailingStack = [NSStackView stackViewWithViews:@[peersRow, _sizeLabel]];
        trailingStack.translatesAutoresizingMaskIntoConstraints = NO;
        trailingStack.orientation = NSUserInterfaceLayoutOrientationVertical;
        trailingStack.alignment = NSLayoutAttributeTrailing;
        trailingStack.spacing = 4.0;
        [self addSubview:trailingStack];

        [NSLayoutConstraint activateConstraints:@[
            [_resTile.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16.0],
            [_resTile.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],

            [middleStack.leadingAnchor constraintEqualToAnchor:_resTile.trailingAnchor constant:14.0],
            [middleStack.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [middleStack.trailingAnchor constraintLessThanOrEqualToAnchor:trailingStack.leadingAnchor constant:-12.0],

            [trailingStack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16.0],
            [trailingStack.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        ]];
    }
    return self;
}

- (void)setSelected:(BOOL)selected
{
    _selected = selected;
    self.layer.borderWidth = selected ? 2.0 : 1.0;
    self.layer.borderColor = (selected ? MacLCDesign.accent : MacLCDesign.separator).CGColor;
}

- (void)mouseDown:(NSEvent *)event
{
    if (event.clickCount == 2) {
        if (self.playHandler) {
            self.playHandler();
        }
    } else {
        if (self.selectHandler) {
            self.selectHandler();
        }
    }
}

- (void)configureWithChoice:(MacLCStreamChoice *)choice filter:(MacLCStreamFilter *)filter
{
    _choice = choice;
    MacLCStreamFacts *facts = choice.facts;

    [_resTile configureWithResolution:facts.resolution];

    NSMutableArray *factsParts = [NSMutableArray array];
    if (facts.dynamicRange != MacLCStreamDynamicRangeUnknown) {
        [factsParts addObject:[MacLCStreamFacts nameForDynamicRange:facts.dynamicRange]];
    }
    if (facts.audio.count > 0) {
        MacLCStreamAudio *a = facts.audio.firstObject;
        if (a.channels.length > 0) {
            [factsParts addObject:[NSString stringWithFormat:@"%@ %@", a.format, a.channels]];
        } else {
            [factsParts addObject:a.format];
        }
    }
    if (facts.isMultiLanguage) {
        [factsParts addObject:_NS("Multi-language")];
    } else if (facts.languages.count > 0) {
        NSMutableArray *langs = [NSMutableArray array];
        for (NSString *c in facts.languages) {
            [langs addObject:[MacLCStreamFacts displayNameForLanguage:c]];
        }
        [factsParts addObject:[langs componentsJoinedByString:@", "]];
    }
    if (facts.source != MacLCStreamSourceUnknown) {
        [factsParts addObject:[MacLCStreamFacts nameForSource:facts.source]];
    }
    _factsLabel.stringValue = [factsParts componentsJoinedByString:@" · "];

    for (NSView *v in [_reasonsStack.arrangedSubviews copy]) {
        [_reasonsStack removeView:v];
        [v removeFromSuperview];
    }

    NSArray<NSString *> *reasons = [MacLCStreamFilter reasonsForBestMatch:choice language:filter.language];
    for (NSString *reason in reasons) {
        NSImageView *check = [[NSImageView alloc] initWithFrame:NSZeroRect];
        check.translatesAutoresizingMaskIntoConstraints = NO;
        check.image = [NSImage imageWithSystemSymbolName:@"checkmark.circle.fill" accessibilityDescription:nil];
        check.contentTintColor = NSColor.systemGreenColor;

        NSTextField *rLabel = [NSTextField labelWithString:reason];
        rLabel.translatesAutoresizingMaskIntoConstraints = NO;
        rLabel.font = MacLCDesign.callout;
        rLabel.textColor = MacLCDesign.primaryLabel;

        NSStackView *rRow = [NSStackView stackViewWithViews:@[check, rLabel]];
        rRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
        rRow.alignment = NSLayoutAttributeCenterY;
        rRow.spacing = 6.0;

        [NSLayoutConstraint activateConstraints:@[
            [check.widthAnchor constraintEqualToConstant:14.0],
            [check.heightAnchor constraintEqualToConstant:14.0],
        ]];

        [_reasonsStack addArrangedSubview:rRow];
    }

    [_healthMeter configureWithHealth:facts.health];

    if (facts.debridService.length > 0) {
        _peersLabel.stringValue = _NS("Cached");
        [MacLCExplainer attachToView:_peersLabel topic:MacLCExplainerTopicDebrid];
        _peersLabel.hidden = NO;
        _peersInfoButton.hidden = YES;
    } else if (facts.seeders >= 0) {
        _peersLabel.stringValue = facts.seeders == 1 ? _NS("1 peer")
                                                     : [NSString stringWithFormat:_NS("%ld peers"), (long)facts.seeders];
        [MacLCExplainer attachToView:_peersLabel topic:MacLCExplainerTopicPeers];
        _peersLabel.hidden = NO;
        _peersInfoButton.hidden = NO;
    } else {
        _peersLabel.hidden = YES;
        _peersInfoButton.hidden = YES;
    }

    if (facts.sizeBytes > 0) {
        _sizeLabel.stringValue = [MacLCStreamFacts displaySize:facts.sizeBytes];
        [MacLCExplainer attachToView:_sizeLabel topic:MacLCExplainerTopicSize];
        _sizeLabel.hidden = NO;
    } else {
        _sizeLabel.hidden = YES;
    }
}

@end

#pragma mark - Stream Picker Controller Implementation

typedef NS_ENUM(NSInteger, MacLCStreamSelectionSource) {
    MacLCStreamSelectionSourceNone = 0,
    MacLCStreamSelectionSourceBestMatch,
    MacLCStreamSelectionSourceTable,
};

@interface MacLCStreamPickerController () <NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate>
{
    BOOL _loading;
    BOOL _updatingSelection;
    MacLCStreamSelectionSource _selectedSource;
    MacLCAddonRequest *_fetchRequest;
    MacLCWatchImageRequest *_posterRequest;
    NSPopover *_explanationsPopover;
}

@property (nonatomic, strong) MacLCAddonItem *item;
@property (nonatomic, strong, nullable) MacLCAddonVideo *video;
@property (nonatomic, strong) NSMutableArray<MacLCStreamChoice *> *allChoices;
@property (nonatomic, copy) NSArray<MacLCStreamChoice *> *filteredChoices;
@property (nonatomic, strong, nullable) MacLCStreamChoice *bestMatch;
@property (nonatomic, strong, nullable) MacLCStreamChoice *selectedChoice;
@property (nonatomic, strong) NSMutableArray<NSString *> *failedAddons;
@property (nonatomic, strong) MacLCStreamFilter *filter;

// Header UI
@property (nonatomic, strong) NSImageView *posterView;
@property (nonatomic, strong) NSView *headerView;

// Best Match UI
@property (nonatomic, strong) NSView *bestMatchContainer;
@property (nonatomic, strong) MacLCStreamBestMatchCardView *bestMatchCard;

// Filter Bar UI
@property (nonatomic, strong) NSView *filterBar;
@property (nonatomic, strong) NSPopUpButton *languagePopUp;
@property (nonatomic, strong) NSPopUpButton *qualityPopUp;
@property (nonatomic, strong) NSPopUpButton *picturePopUp;
@property (nonatomic, strong) NSButton *bestSoundCheckBox;
@property (nonatomic, strong) NSPopUpButton *sortPopUp;
@property (nonatomic, strong) NSButton *hiddenButton;
@property (nonatomic, strong) NSProgressIndicator *loadingSpinner;
@property (nonatomic, strong) NSTextField *loadingLabel;

// Layout constraints for Best Match show/hide
@property (nonatomic, strong) NSLayoutConstraint *filterBarTopWithBestMatch;
@property (nonatomic, strong) NSLayoutConstraint *filterBarTopWithoutBestMatch;

// Table UI
@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, strong) MacLCStreamTableView *tableView;

// Error footnote UI
@property (nonatomic, strong) NSView *errorFootnoteView;
@property (nonatomic, strong) NSTextField *errorLabel;
@property (nonatomic, strong) NSButton *errorRetryButton;

// Empty state UI
@property (nonatomic, strong) NSView *emptyStateView;
@property (nonatomic, strong) NSImageView *emptyIconView;
@property (nonatomic, strong) NSTextField *emptyTitleLabel;
@property (nonatomic, strong) NSTextField *emptyMessageLabel;
@property (nonatomic, strong) NSButton *emptyActionButton;

// Footer UI
@property (nonatomic, strong) NSView *footerView;
@property (nonatomic, strong) NSButton *whatDoTheseMeanButton;
@property (nonatomic, strong) NSButton *queueButton;
@property (nonatomic, strong) NSButton *cancelButton;
@property (nonatomic, strong) NSButton *playButton;
@property (nonatomic, strong) NSButton *startOverButton;
/// Where this title or episode stopped last time, when it can be picked up (nil: Play starts at 0).
@property (nonatomic, strong, nullable) MacLCWatchProgress *resumeProgress;

@end

@implementation MacLCStreamPickerController

- (instancetype)initWithItem:(MacLCAddonItem *)item video:(nullable MacLCAddonVideo *)video
{
    self = [super initWithWindow:nil];
    if (self) {
        _item = item;
        _video = video;
        _allChoices = [NSMutableArray array];
        _filteredChoices = @[];
        _failedAddons = [NSMutableArray array];
        _filter = [[MacLCStreamFilter alloc] init];
        _filter.hidePoor = YES;

        NSDictionary *saved = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"MacLCStreamPickerFilter"];
        if (saved) {
            if ([saved[@"language"] isKindOfClass:[NSString class]]) {
                _filter.language = saved[@"language"];
            }
            if (saved[@"picture"]) {
                _filter.picture = [saved[@"picture"] integerValue];
            }
            if (saved[@"sort"]) {
                _filter.sortOrder = [saved[@"sort"] integerValue];
            }
            if (saved[@"bestSoundOnly"]) {
                _filter.bestSoundOnly = [saved[@"bestSoundOnly"] boolValue];
            }
        }
    }
    return self;
}

- (void)dealloc
{
    [self cleanup];
}

- (void)cleanup
{
    [_fetchRequest cancel];
    _fetchRequest = nil;
    [_posterRequest cancel];
    _posterRequest = nil;
    if (_explanationsPopover) {
        [_explanationsPopover performClose:nil];
        _explanationsPopover = nil;
    }
}

- (void)loadWindow
{
    NSRect const frame = NSMakeRect(0, 0, 780, 640);
    NSWindow *sheet = [[NSWindow alloc] initWithContentRect:frame
                                                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable | NSWindowStyleMaskClosable
                                                    backing:NSBackingStoreBuffered
                                                      defer:NO];
    sheet.title = _NS("Choose a Version");
    sheet.minSize = NSMakeSize(640, 460);
    sheet.delegate = self;
    sheet.contentView.wantsLayer = YES;
    sheet.contentView.layer.backgroundColor = MacLCDesign.contentBackground.CGColor;
    self.window = sheet;

    [self buildUserInterfaceInWindow:sheet];
}

#pragma mark - Sheet Lifecycle

- (void)beginSheetModalForWindow:(NSWindow *)parentWindow
{
    if (!self.window) {
        [self loadWindow];
    }
    NSWindow *sheet = self.window;
    /* 780 x 640 (MacLCStreamPicker.h), never larger than the window it
     * slides out of. */
    const NSSize parentSize = parentWindow.contentLayoutRect.size;
    [sheet setContentSize:NSMakeSize(MAX(640.0, MIN(780.0, parentSize.width - 40.0)),
                                     MAX(460.0, MIN(640.0, parentSize.height - 40.0)))];

    __weak typeof(self) weakSelf = self;
    [parentWindow beginSheet:sheet completionHandler:^(NSModalResponse returnCode) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf cleanup];
        if (strongSelf.completionHandler) {
            void (^handler)(BOOL) = strongSelf.completionHandler;
            strongSelf.completionHandler = nil;
            handler(returnCode == NSModalResponseOK);
        }
    }];

    [self fetchStreams];
}

- (void)endSheetWithResponse:(NSModalResponse)response
{
    NSWindow *sheet = self.window;
    NSWindow *parent = sheet.sheetParent;
    if (parent) {
        [parent endSheet:sheet returnCode:response];
    } else {
        [sheet orderOut:nil];
        [self cleanup];
        if (self.completionHandler) {
            void (^handler)(BOOL) = self.completionHandler;
            self.completionHandler = nil;
            handler(response == NSModalResponseOK);
        }
    }
}

- (void)cancelOperation:(id)sender
{
    [self cancelAction:sender];
}

- (BOOL)windowShouldClose:(NSWindow *)sender
{
    [self cancelAction:nil];
    return YES;
}

#pragma mark - Building UI

- (void)buildUserInterfaceInWindow:(NSWindow *)window
{
    NSView *root = window.contentView;

    // 1. Header (64 pt)
    _headerView = [[NSView alloc] initWithFrame:NSZeroRect];
    _headerView.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:_headerView];
    [self setupHeaderInView:_headerView];

    // 2. Best Match Container
    _bestMatchContainer = [[NSView alloc] initWithFrame:NSZeroRect];
    _bestMatchContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:_bestMatchContainer];
    [self setupBestMatchInView:_bestMatchContainer];

    // 3. Filter Bar (32 pt)
    _filterBar = [[NSView alloc] initWithFrame:NSZeroRect];
    _filterBar.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:_filterBar];
    [self setupFilterBarInView:_filterBar];

    // 4. Content Area (Table + Empty state)
    _tableView = [[MacLCStreamTableView alloc] initWithFrame:NSZeroRect];
    _tableView.autoresizingMask = NSViewWidthSizable;
    _tableView.headerView = nil;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.target = self;
    _tableView.doubleAction = @selector(tableDoubleClicked:);
    _tableView.rowHeight = 76.0;
    _tableView.usesAlternatingRowBackgroundColors = NO;
    if (@available(macOS 11.0, *)) {
        _tableView.style = NSTableViewStyleInset;
    }

    __weak typeof(self) weakSelf = self;
    _tableView.returnKeyHandler = ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf && strongSelf.selectedChoice) {
            [strongSelf playAction:nil];
        }
    };
    _tableView.escapeKeyHandler = ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf) {
            [strongSelf cancelAction:nil];
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

    _emptyStateView = [[NSView alloc] initWithFrame:NSZeroRect];
    _emptyStateView.translatesAutoresizingMaskIntoConstraints = NO;
    _emptyStateView.hidden = YES;
    [root addSubview:_emptyStateView];
    [self setupEmptyStateInView:_emptyStateView];

    // 5. Error Footnote
    _errorFootnoteView = [[NSView alloc] initWithFrame:NSZeroRect];
    _errorFootnoteView.translatesAutoresizingMaskIntoConstraints = NO;
    _errorFootnoteView.hidden = YES;
    [root addSubview:_errorFootnoteView];
    [self setupErrorFootnoteInView:_errorFootnoteView];

    // 6. Footer (56 pt)
    _footerView = [[NSView alloc] initWithFrame:NSZeroRect];
    _footerView.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:_footerView];
    [self setupFooterInView:_footerView];

    // Auto Layout Wiring
    _filterBarTopWithBestMatch = [_filterBar.topAnchor constraintEqualToAnchor:_bestMatchContainer.bottomAnchor constant:MacLCDesign.spacingS];
    _filterBarTopWithoutBestMatch = [_filterBar.topAnchor constraintEqualToAnchor:_headerView.bottomAnchor constant:MacLCDesign.spacingS];

    _filterBarTopWithoutBestMatch.active = YES;
    _bestMatchContainer.hidden = YES;

    /* The sheet's own size (MacLCStreamPicker.h): preferred 780 x 640, at
     * least 640 x 460; without these the content fitting size wins. */
    NSLayoutConstraint * const preferredWidth = [root.widthAnchor constraintEqualToConstant:780.0];
    NSLayoutConstraint * const preferredHeight = [root.heightAnchor constraintEqualToConstant:640.0];
    preferredWidth.priority = NSLayoutPriorityDragThatCannotResizeWindow;
    preferredHeight.priority = NSLayoutPriorityDragThatCannotResizeWindow;
    [NSLayoutConstraint activateConstraints:@[
        preferredWidth, preferredHeight,
        [root.widthAnchor constraintGreaterThanOrEqualToConstant:640.0],
        [root.heightAnchor constraintGreaterThanOrEqualToConstant:460.0],
    ]];

    [NSLayoutConstraint activateConstraints:@[
        [_headerView.topAnchor constraintEqualToAnchor:root.topAnchor],
        [_headerView.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [_headerView.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [_headerView.heightAnchor constraintEqualToConstant:64.0],

        [_bestMatchContainer.topAnchor constraintEqualToAnchor:_headerView.bottomAnchor constant:MacLCDesign.spacingS],
        [_bestMatchContainer.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:MacLCDesign.windowContentMargin],
        [_bestMatchContainer.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-MacLCDesign.windowContentMargin],

        [_filterBar.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:MacLCDesign.windowContentMargin],
        [_filterBar.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-MacLCDesign.windowContentMargin],
        [_filterBar.heightAnchor constraintEqualToConstant:32.0],

        [_scrollView.topAnchor constraintEqualToAnchor:_filterBar.bottomAnchor constant:MacLCDesign.spacingS],
        [_scrollView.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:MacLCDesign.spacingS],
        [_scrollView.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-MacLCDesign.spacingS],
        [_scrollView.bottomAnchor constraintEqualToAnchor:_errorFootnoteView.topAnchor],
        [_scrollView.heightAnchor constraintGreaterThanOrEqualToConstant:160.0],

        [_emptyStateView.topAnchor constraintEqualToAnchor:_scrollView.topAnchor],
        [_emptyStateView.leadingAnchor constraintEqualToAnchor:_scrollView.leadingAnchor],
        [_emptyStateView.trailingAnchor constraintEqualToAnchor:_scrollView.trailingAnchor],
        [_emptyStateView.bottomAnchor constraintEqualToAnchor:_scrollView.bottomAnchor],

        [_errorFootnoteView.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:MacLCDesign.windowContentMargin],
        [_errorFootnoteView.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-MacLCDesign.windowContentMargin],
        [_errorFootnoteView.bottomAnchor constraintEqualToAnchor:_footerView.topAnchor],
        [_errorFootnoteView.heightAnchor constraintEqualToConstant:24.0],

        [_footerView.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [_footerView.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [_footerView.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],
        [_footerView.heightAnchor constraintEqualToConstant:56.0],
    ]];
}

- (void)setupHeaderInView:(NSView *)headerView
{
    _posterView = [[NSImageView alloc] initWithFrame:NSZeroRect];
    _posterView.translatesAutoresizingMaskIntoConstraints = NO;
    _posterView.wantsLayer = YES;
    _posterView.layer.cornerRadius = MacLCDesign.cornerRadiusSmall;
    _posterView.layer.masksToBounds = YES;
    _posterView.layer.backgroundColor = NSColor.quaternarySystemFillColor.CGColor;
    _posterView.imageScaling = NSImageScaleProportionallyUpOrDown;
    [headerView addSubview:_posterView];

    if (_item.posterURL) {
        CGFloat scale = NSScreen.mainScreen ? NSScreen.mainScreen.backingScaleFactor : 2.0;
        __weak typeof(self) weakSelf = self;
        MacLCWatchImageRequest *req = nil;
        NSImage *cached = [MacLCWatchImageCache.sharedCache imageForURL:_item.posterURL
                                                              pointSize:NSMakeSize(40, 60)
                                                                  scale:scale
                                                                request:&req
                                                             completion:^(NSImage * _Nullable img) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf && img) {
                strongSelf.posterView.image = img;
            }
        }];
        _posterRequest = req;
        if (cached) {
            _posterView.image = cached;
        }
    }

    NSTextField *titleLabel = [NSTextField labelWithString:_item.name ?: @""];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.font = [NSFont systemFontOfSize:MacLCDesign.title3.pointSize weight:NSFontWeightSemibold];
    titleLabel.textColor = MacLCDesign.primaryLabel;
    titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;

    NSString *subStr = @"";
    if (_video != nil && (_video.season > 0 || _video.episode > 0)) {
        NSString *epStr = [NSString stringWithFormat:@"S%ld, E%ld", (long)_video.season, (long)_video.episode];
        if (_video.name.length > 0) {
            subStr = [NSString stringWithFormat:@"%@ · %@", epStr, _video.name];
        } else {
            subStr = epStr;
        }
    } else {
        if (_item.releaseInfo.length > 0) {
            subStr = [NSString stringWithFormat:@"%@ · %@", _item.releaseInfo, _NS("Movie")];
        } else {
            subStr = _NS("Movie");
        }
    }

    NSTextField *subLabel = [NSTextField labelWithString:subStr];
    subLabel.translatesAutoresizingMaskIntoConstraints = NO;
    subLabel.font = MacLCDesign.subheadline;
    subLabel.textColor = MacLCDesign.secondaryLabel;
    subLabel.lineBreakMode = NSLineBreakByTruncatingTail;

    NSStackView *textStack = [NSStackView stackViewWithViews:@[titleLabel, subLabel]];
    textStack.translatesAutoresizingMaskIntoConstraints = NO;
    textStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    textStack.alignment = NSLayoutAttributeLeading;
    textStack.spacing = 2.0;
    [headerView addSubview:textStack];

    NSBox *sep = [[NSBox alloc] initWithFrame:NSZeroRect];
    sep.translatesAutoresizingMaskIntoConstraints = NO;
    sep.boxType = NSBoxSeparator;
    [headerView addSubview:sep];

    [NSLayoutConstraint activateConstraints:@[
        [_posterView.leadingAnchor constraintEqualToAnchor:headerView.leadingAnchor constant:MacLCDesign.windowContentMargin],
        [_posterView.centerYAnchor constraintEqualToAnchor:headerView.centerYAnchor],
        [_posterView.widthAnchor constraintEqualToConstant:40.0],
        [_posterView.heightAnchor constraintEqualToConstant:60.0],

        [textStack.leadingAnchor constraintEqualToAnchor:_posterView.trailingAnchor constant:14.0],
        [textStack.trailingAnchor constraintLessThanOrEqualToAnchor:headerView.trailingAnchor constant:-MacLCDesign.windowContentMargin],
        [textStack.centerYAnchor constraintEqualToAnchor:headerView.centerYAnchor],

        [sep.leadingAnchor constraintEqualToAnchor:headerView.leadingAnchor],
        [sep.trailingAnchor constraintEqualToAnchor:headerView.trailingAnchor],
        [sep.bottomAnchor constraintEqualToAnchor:headerView.bottomAnchor],
    ]];
}

- (void)setupBestMatchInView:(NSView *)container
{
    NSTextField *eyebrow = [NSTextField labelWithString:@""];
    eyebrow.translatesAutoresizingMaskIntoConstraints = NO;
    NSFont *eyebrowFont = [NSFont systemFontOfSize:MacLCDesign.footnote.pointSize weight:NSFontWeightSemibold];
    NSMutableAttributedString *as = [[NSMutableAttributedString alloc] initWithString:_NS("BEST MATCH") attributes:@{
        NSFontAttributeName: eyebrowFont,
        NSForegroundColorAttributeName: MacLCDesign.accent,
        NSKernAttributeName: @(0.6),
    }];
    eyebrow.attributedStringValue = as;
    [MacLCExplainer attachToView:eyebrow topic:MacLCExplainerTopicBestMatch];

    NSButton *eyebrowInfo = [MacLCExplainer infoButtonForTopic:MacLCExplainerTopicBestMatch];
    eyebrowInfo.translatesAutoresizingMaskIntoConstraints = NO;

    NSStackView *eyebrowRow = [NSStackView stackViewWithViews:@[eyebrow, eyebrowInfo]];
    eyebrowRow.translatesAutoresizingMaskIntoConstraints = NO;
    eyebrowRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    eyebrowRow.alignment = NSLayoutAttributeCenterY;
    eyebrowRow.spacing = 4.0;
    [container addSubview:eyebrowRow];

    _bestMatchCard = [[MacLCStreamBestMatchCardView alloc] initWithFrame:NSZeroRect];
    _bestMatchCard.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:_bestMatchCard];

    __weak typeof(self) weakSelf = self;
    _bestMatchCard.selectHandler = ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf && strongSelf.bestMatch) {
            [strongSelf selectChoice:strongSelf.bestMatch source:MacLCStreamSelectionSourceBestMatch];
        }
    };
    _bestMatchCard.playHandler = ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf && strongSelf.bestMatch) {
            [strongSelf selectChoice:strongSelf.bestMatch source:MacLCStreamSelectionSourceBestMatch];
            [strongSelf playAction:nil];
        }
    };

    [NSLayoutConstraint activateConstraints:@[
        [eyebrowRow.topAnchor constraintEqualToAnchor:container.topAnchor],
        [eyebrowRow.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],

        [_bestMatchCard.topAnchor constraintEqualToAnchor:eyebrowRow.bottomAnchor constant:4.0],
        [_bestMatchCard.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [_bestMatchCard.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [_bestMatchCard.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
        /* Fixed: the card must not take the room of the list below it. */
        [_bestMatchCard.heightAnchor constraintEqualToConstant:104.0],
    ]];
}

- (void)setupFilterBarInView:(NSView *)bar
{
    _languagePopUp = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    _languagePopUp.translatesAutoresizingMaskIntoConstraints = NO;
    _languagePopUp.bezelStyle = NSBezelStylePush;
    _languagePopUp.controlSize = NSControlSizeSmall;
    _languagePopUp.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    _languagePopUp.target = self;
    _languagePopUp.action = @selector(languageChanged:);

    _qualityPopUp = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    _qualityPopUp.translatesAutoresizingMaskIntoConstraints = NO;
    _qualityPopUp.bezelStyle = NSBezelStylePush;
    _qualityPopUp.controlSize = NSControlSizeSmall;
    _qualityPopUp.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    _qualityPopUp.target = self;
    _qualityPopUp.action = @selector(qualityChanged:);

    _picturePopUp = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    _picturePopUp.translatesAutoresizingMaskIntoConstraints = NO;
    _picturePopUp.bezelStyle = NSBezelStylePush;
    _picturePopUp.controlSize = NSControlSizeSmall;
    _picturePopUp.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    _picturePopUp.target = self;
    _picturePopUp.action = @selector(pictureChanged:);

    _bestSoundCheckBox = [NSButton checkboxWithTitle:_NS("Best sound only") target:self action:@selector(bestSoundChanged:)];
    _bestSoundCheckBox.translatesAutoresizingMaskIntoConstraints = NO;
    _bestSoundCheckBox.controlSize = NSControlSizeSmall;
    _bestSoundCheckBox.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    _bestSoundCheckBox.hidden = YES;

    NSStackView *leadingStack = [NSStackView stackViewWithViews:@[_languagePopUp, _qualityPopUp, _picturePopUp, _bestSoundCheckBox]];
    leadingStack.translatesAutoresizingMaskIntoConstraints = NO;
    leadingStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    leadingStack.alignment = NSLayoutAttributeCenterY;
    leadingStack.spacing = MacLCDesign.spacingS;
    [bar addSubview:leadingStack];

    _loadingSpinner = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
    _loadingSpinner.translatesAutoresizingMaskIntoConstraints = NO;
    _loadingSpinner.style = NSProgressIndicatorStyleSpinning;
    _loadingSpinner.controlSize = NSControlSizeSmall;
    _loadingSpinner.displayedWhenStopped = NO;
    _loadingSpinner.hidden = YES;

    _loadingLabel = [NSTextField labelWithString:_NS("Looking for versions…")];
    _loadingLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _loadingLabel.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    _loadingLabel.textColor = MacLCDesign.secondaryLabel;
    _loadingLabel.hidden = YES;

    NSStackView *loadingStack = [NSStackView stackViewWithViews:@[_loadingSpinner, _loadingLabel]];
    loadingStack.translatesAutoresizingMaskIntoConstraints = NO;
    loadingStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    loadingStack.alignment = NSLayoutAttributeCenterY;
    loadingStack.spacing = 4.0;

    NSTextField *sortLabel = [NSTextField labelWithString:_NS("Sort:")];
    sortLabel.translatesAutoresizingMaskIntoConstraints = NO;
    sortLabel.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    sortLabel.textColor = MacLCDesign.secondaryLabel;

    _sortPopUp = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    _sortPopUp.translatesAutoresizingMaskIntoConstraints = NO;
    _sortPopUp.bezelStyle = NSBezelStylePush;
    _sortPopUp.controlSize = NSControlSizeSmall;
    _sortPopUp.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    _sortPopUp.target = self;
    _sortPopUp.action = @selector(sortChanged:);
    [self setupSortMenu];

    _hiddenButton = [NSButton buttonWithTitle:@"" target:self action:@selector(toggleHidePoorAction:)];
    _hiddenButton.translatesAutoresizingMaskIntoConstraints = NO;
    _hiddenButton.bezelStyle = NSBezelStyleInline;
    _hiddenButton.font = MacLCDesign.footnote;
    _hiddenButton.contentTintColor = MacLCDesign.secondaryLabel;
    _hiddenButton.hidden = YES;

    NSStackView *trailingStack = [NSStackView stackViewWithViews:@[loadingStack, sortLabel, _sortPopUp, _hiddenButton]];
    trailingStack.translatesAutoresizingMaskIntoConstraints = NO;
    trailingStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    trailingStack.alignment = NSLayoutAttributeCenterY;
    trailingStack.spacing = MacLCDesign.spacingS;
    [bar addSubview:trailingStack];

    [NSLayoutConstraint activateConstraints:@[
        [leadingStack.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor],
        [leadingStack.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor],

        [trailingStack.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor],
        [trailingStack.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor],
        [leadingStack.trailingAnchor constraintLessThanOrEqualToAnchor:trailingStack.leadingAnchor constant:-MacLCDesign.spacingS],
    ]];
}

- (void)setupEmptyStateInView:(NSView *)view
{
    _emptyIconView = [[NSImageView alloc] initWithFrame:NSZeroRect];
    _emptyIconView.translatesAutoresizingMaskIntoConstraints = NO;
    _emptyIconView.imageScaling = NSImageScaleProportionallyUpOrDown;
    [view addSubview:_emptyIconView];

    _emptyTitleLabel = [NSTextField labelWithString:@""];
    _emptyTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _emptyTitleLabel.font = MacLCDesign.headline;
    _emptyTitleLabel.textColor = MacLCDesign.primaryLabel;
    _emptyTitleLabel.alignment = NSTextAlignmentCenter;
    [view addSubview:_emptyTitleLabel];

    _emptyMessageLabel = [NSTextField labelWithString:@""];
    _emptyMessageLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _emptyMessageLabel.font = MacLCDesign.subheadline;
    _emptyMessageLabel.textColor = MacLCDesign.secondaryLabel;
    _emptyMessageLabel.alignment = NSTextAlignmentCenter;
    _emptyMessageLabel.maximumNumberOfLines = 3;
    [view addSubview:_emptyMessageLabel];

    _emptyActionButton = [NSButton buttonWithTitle:@"" target:nil action:nil];
    _emptyActionButton.translatesAutoresizingMaskIntoConstraints = NO;
    _emptyActionButton.bezelStyle = NSBezelStylePush;
    [view addSubview:_emptyActionButton];

    [NSLayoutConstraint activateConstraints:@[
        [_emptyIconView.centerXAnchor constraintEqualToAnchor:view.centerXAnchor],
        [_emptyIconView.centerYAnchor constraintEqualToAnchor:view.centerYAnchor constant:-36.0],
        [_emptyIconView.widthAnchor constraintEqualToConstant:40.0],
        [_emptyIconView.heightAnchor constraintEqualToConstant:40.0],

        [_emptyTitleLabel.topAnchor constraintEqualToAnchor:_emptyIconView.bottomAnchor constant:MacLCDesign.spacingM],
        [_emptyTitleLabel.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:MacLCDesign.spacingXL],
        [_emptyTitleLabel.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-MacLCDesign.spacingXL],

        [_emptyMessageLabel.topAnchor constraintEqualToAnchor:_emptyTitleLabel.bottomAnchor constant:MacLCDesign.spacingXS],
        [_emptyMessageLabel.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:MacLCDesign.spacingXL],
        [_emptyMessageLabel.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-MacLCDesign.spacingXL],

        [_emptyActionButton.topAnchor constraintEqualToAnchor:_emptyMessageLabel.bottomAnchor constant:MacLCDesign.spacingL],
        [_emptyActionButton.centerXAnchor constraintEqualToAnchor:view.centerXAnchor],
    ]];
}

- (void)setupErrorFootnoteInView:(NSView *)view
{
    _errorLabel = [NSTextField labelWithString:@""];
    _errorLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _errorLabel.font = MacLCDesign.footnote;
    _errorLabel.textColor = MacLCDesign.secondaryLabel;
    [view addSubview:_errorLabel];

    _errorRetryButton = [NSButton buttonWithTitle:_NS("Try Again") target:self action:@selector(fetchStreams)];
    _errorRetryButton.translatesAutoresizingMaskIntoConstraints = NO;
    _errorRetryButton.bezelStyle = NSBezelStyleInline;
    _errorRetryButton.font = MacLCDesign.footnote;
    [view addSubview:_errorRetryButton];

    [NSLayoutConstraint activateConstraints:@[
        [_errorLabel.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
        [_errorLabel.centerYAnchor constraintEqualToAnchor:view.centerYAnchor],

        [_errorRetryButton.leadingAnchor constraintEqualToAnchor:_errorLabel.trailingAnchor constant:8.0],
        [_errorRetryButton.centerYAnchor constraintEqualToAnchor:view.centerYAnchor],
    ]];
}

- (void)setupFooterInView:(NSView *)footerView
{
    NSBox *sep = [[NSBox alloc] initWithFrame:NSZeroRect];
    sep.translatesAutoresizingMaskIntoConstraints = NO;
    sep.boxType = NSBoxSeparator;
    [footerView addSubview:sep];

    _whatDoTheseMeanButton = [NSButton buttonWithTitle:_NS("What do these mean?")
                                                 image:[NSImage imageWithSystemSymbolName:@"questionmark.circle" accessibilityDescription:nil]
                                                target:self
                                                action:@selector(showExplanationsPopover:)];
    _whatDoTheseMeanButton.translatesAutoresizingMaskIntoConstraints = NO;
    _whatDoTheseMeanButton.imagePosition = NSImageLeading;
    _whatDoTheseMeanButton.bordered = NO;
    _whatDoTheseMeanButton.font = MacLCDesign.subheadline;
    _whatDoTheseMeanButton.contentTintColor = MacLCDesign.accent;
    [footerView addSubview:_whatDoTheseMeanButton];

    _queueButton = [NSButton buttonWithTitle:_NS("Add to Queue") target:self action:@selector(addToQueueAction:)];
    _queueButton.translatesAutoresizingMaskIntoConstraints = NO;
    _queueButton.bezelStyle = NSBezelStylePush;
    _queueButton.enabled = NO;

    _cancelButton = [NSButton buttonWithTitle:_NS("Cancel") target:self action:@selector(cancelAction:)];
    _cancelButton.translatesAutoresizingMaskIntoConstraints = NO;
    _cancelButton.bezelStyle = NSBezelStylePush;
    _cancelButton.keyEquivalent = @"\e";

    /* Something half-watched: Play becomes Resume, and Start Over appears. */
    _resumeProgress = [MacLCWatchLibrary.sharedLibrary progressForTitle:_item.identifier video:_video.identifier];
    if (!_resumeProgress.canResume) {
        _resumeProgress = nil;
    }

    _startOverButton = [NSButton buttonWithTitle:_NS("Start Over") target:self action:@selector(startOverAction:)];
    _startOverButton.translatesAutoresizingMaskIntoConstraints = NO;
    _startOverButton.bezelStyle = NSBezelStylePush;
    _startOverButton.hidden = (_resumeProgress == nil);
    _startOverButton.enabled = NO;

    _playButton = [NSButton buttonWithTitle:_resumeProgress ? _NS("Resume") : _NS("Play")
                                     target:self
                                     action:@selector(playAction:)];
    _playButton.translatesAutoresizingMaskIntoConstraints = NO;
    _playButton.bezelStyle = NSBezelStylePush;
    _playButton.image = [NSImage imageWithSystemSymbolName:@"play.fill" accessibilityDescription:nil];
    _playButton.imagePosition = NSImageLeading;
    _playButton.keyEquivalent = @"\r";
    _playButton.enabled = NO;
    if (_resumeProgress) {
        _playButton.toolTip = [NSString stringWithFormat:_NS("Resume from %@"), ClockText(_resumeProgress.position)];
    }

    NSStackView *trailingButtons = [NSStackView stackViewWithViews:@[_queueButton, _cancelButton, _startOverButton, _playButton]];
    trailingButtons.translatesAutoresizingMaskIntoConstraints = NO;
    trailingButtons.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    trailingButtons.spacing = MacLCDesign.spacingS;
    trailingButtons.alignment = NSLayoutAttributeCenterY;
    [footerView addSubview:trailingButtons];

    [NSLayoutConstraint activateConstraints:@[
        [sep.topAnchor constraintEqualToAnchor:footerView.topAnchor],
        [sep.leadingAnchor constraintEqualToAnchor:footerView.leadingAnchor],
        [sep.trailingAnchor constraintEqualToAnchor:footerView.trailingAnchor],

        [_whatDoTheseMeanButton.leadingAnchor constraintEqualToAnchor:footerView.leadingAnchor constant:MacLCDesign.windowContentMargin],
        [_whatDoTheseMeanButton.centerYAnchor constraintEqualToAnchor:footerView.centerYAnchor],

        [trailingButtons.trailingAnchor constraintEqualToAnchor:footerView.trailingAnchor constant:-MacLCDesign.windowContentMargin],
        [trailingButtons.centerYAnchor constraintEqualToAnchor:footerView.centerYAnchor],
    ]];
}

#pragma mark - Filter Bar Logic

- (void)setupSortMenu
{
    [_sortPopUp removeAllItems];
    [_sortPopUp addItemWithTitle:_NS("Recommended")];
    _sortPopUp.lastItem.representedObject = @(MacLCStreamSortRecommended);
    [_sortPopUp addItemWithTitle:_NS("Most Shared")];
    _sortPopUp.lastItem.representedObject = @(MacLCStreamSortMostShared);
    [_sortPopUp addItemWithTitle:_NS("Highest Quality")];
    _sortPopUp.lastItem.representedObject = @(MacLCStreamSortHighestQuality);
    [_sortPopUp addItemWithTitle:_NS("Smallest Size")];
    _sortPopUp.lastItem.representedObject = @(MacLCStreamSortSmallest);

    NSInteger idx = [_sortPopUp indexOfItemWithRepresentedObject:@(_filter.sortOrder)];
    [_sortPopUp selectItemAtIndex:(idx >= 0 ? idx : 0)];
}

- (void)rebuildFilterBarControls
{
    // Language
    [_languagePopUp removeAllItems];
    [_languagePopUp addItemWithTitle:_NS("Any Language")];
    _languagePopUp.lastItem.representedObject = nil;

    NSDictionary<NSString *, NSNumber *> *counts = nil;
    NSArray<NSString *> *languages = [MacLCStreamFilter languagesIn:_allChoices counts:&counts];
    if (languages.count > 0) {
        [[_languagePopUp menu] addItem:[NSMenuItem separatorItem]];
        for (NSString *code in languages) {
            NSString *name = [MacLCStreamFacts displayNameForLanguage:code];
            NSNumber *cnt = counts[code] ?: @0;
            NSString *title = [NSString stringWithFormat:@"%@ (%@)", name, cnt];
            [_languagePopUp addItemWithTitle:title];
            _languagePopUp.lastItem.representedObject = code;
        }
    }

    if (_filter.language == nil) {
        NSString *preferred = [MacLCStreamFilter preferredLanguageIn:_allChoices];
        if (preferred) {
            _filter.language = preferred;
        }
    }

    NSInteger selectedLangIdx = 0;
    if (_filter.language) {
        NSInteger idx = [_languagePopUp indexOfItemWithRepresentedObject:_filter.language];
        if (idx >= 0) selectedLangIdx = idx;
    }
    [_languagePopUp selectItemAtIndex:selectedLangIdx];

    // Quality
    [_qualityPopUp removeAllItems];
    [_qualityPopUp addItemWithTitle:_NS("Any Quality")];
    _qualityPopUp.lastItem.representedObject = @(MacLCStreamResolutionUnknown);

    NSArray<NSNumber *> *resolutions = [MacLCStreamFilter resolutionsIn:_allChoices];
    for (NSNumber *resNum in resolutions) {
        MacLCStreamResolution res = resNum.integerValue;
        NSString *title = nil;
        switch (res) {
            case MacLCStreamResolution4K:
                title = _NS("4K and Better");
                break;
            case MacLCStreamResolution1080p:
                title = _NS("1080p and Better");
                break;
            case MacLCStreamResolution720p:
                title = _NS("720p and Better");
                break;
            case MacLCStreamResolutionSD:
                title = _NS("SD and Better");
                break;
            default:
                break;
        }
        if (title) {
            [_qualityPopUp addItemWithTitle:title];
            _qualityPopUp.lastItem.representedObject = resNum;
        }
    }
    NSInteger selectedResIdx = 0;
    if (_filter.minimumResolution != MacLCStreamResolutionUnknown) {
        NSInteger idx = [_qualityPopUp indexOfItemWithRepresentedObject:@(_filter.minimumResolution)];
        if (idx >= 0) selectedResIdx = idx;
    }
    [_qualityPopUp selectItemAtIndex:selectedResIdx];

    // Picture
    [_picturePopUp removeAllItems];
    [_picturePopUp addItemWithTitle:_NS("Any Picture")];
    _picturePopUp.lastItem.representedObject = @(MacLCStreamPictureAny);

    BOOL hasHDR = NO;
    BOOL hasDV = NO;
    BOOL hasSDR = NO;
    for (MacLCStreamChoice *c in _allChoices) {
        MacLCStreamFacts *f = c.facts;
        if (f.dynamicRange == MacLCStreamDynamicRangeDolbyVision || [f.hdrFormats containsObject:@"Dolby Vision"]) {
            hasDV = YES;
        }
        if (f.dynamicRange == MacLCStreamDynamicRangeHDR ||
            f.dynamicRange == MacLCStreamDynamicRangeHDR10 ||
            f.dynamicRange == MacLCStreamDynamicRangeHDR10Plus ||
            f.dynamicRange == MacLCStreamDynamicRangeHLG) {
            hasHDR = YES;
        }
        if (f.dynamicRange == MacLCStreamDynamicRangeSDR || f.dynamicRange == MacLCStreamDynamicRangeUnknown) {
            hasSDR = YES;
        }
    }

    if (hasHDR) {
        [_picturePopUp addItemWithTitle:_NS("HDR")];
        _picturePopUp.lastItem.representedObject = @(MacLCStreamPictureHDR);
    }
    if (hasDV) {
        [_picturePopUp addItemWithTitle:_NS("Dolby Vision")];
        _picturePopUp.lastItem.representedObject = @(MacLCStreamPictureDolbyVision);
    }
    if (hasSDR) {
        [_picturePopUp addItemWithTitle:_NS("SDR")];
        _picturePopUp.lastItem.representedObject = @(MacLCStreamPictureSDR);
    }
    NSInteger selectedPicIdx = 0;
    if (_filter.picture != MacLCStreamPictureAny) {
        NSInteger idx = [_picturePopUp indexOfItemWithRepresentedObject:@(_filter.picture)];
        if (idx >= 0) selectedPicIdx = idx;
    }
    [_picturePopUp selectItemAtIndex:selectedPicIdx];

    // Best sound checkbox
    BOOL hasBestSound = NO;
    for (MacLCStreamChoice *c in _allChoices) {
        for (MacLCStreamAudio *a in c.facts.audio) {
            if (a.isLossless || a.isImmersive) {
                hasBestSound = YES;
                break;
            }
        }
        if (hasBestSound) break;
    }
    _bestSoundCheckBox.hidden = !hasBestSound;
    _bestSoundCheckBox.state = (_filter.bestSoundOnly && hasBestSound) ? NSControlStateValueOn : NSControlStateValueOff;

    // Sort
    NSInteger sortIdx = [_sortPopUp indexOfItemWithRepresentedObject:@(_filter.sortOrder)];
    [_sortPopUp selectItemAtIndex:(sortIdx >= 0 ? sortIdx : 0)];

    // Hidden button
    [self updateHiddenButton];
}

- (void)updateHiddenButton
{
    NSUInteger hidden = [_filter hiddenCountIn:_allChoices];
    if (_filter.hidePoor) {
        if (hidden > 0) {
            _hiddenButton.title = [NSString stringWithFormat:_NS("%lu hidden"), (unsigned long)hidden];
            _hiddenButton.hidden = NO;
        } else {
            _hiddenButton.hidden = YES;
        }
    } else {
        _hiddenButton.title = _NS("Hide poor versions");
        _hiddenButton.hidden = NO;
    }
    [MacLCExplainer attachToView:_hiddenButton topic:MacLCExplainerTopicVerdict];
}

- (void)saveFilterPreferences
{
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    if (_filter.language) {
        dict[@"language"] = _filter.language;
    }
    dict[@"picture"] = @(_filter.picture);
    dict[@"sort"] = @(_filter.sortOrder);
    dict[@"bestSoundOnly"] = @(_filter.bestSoundOnly);
    [[NSUserDefaults standardUserDefaults] setObject:[dict copy] forKey:@"MacLCStreamPickerFilter"];
}

- (void)languageChanged:(NSPopUpButton *)sender
{
    _filter.language = sender.selectedItem.representedObject;
    [self saveFilterPreferences];
    [self applyFiltersWithAnimation];
}

- (void)qualityChanged:(NSPopUpButton *)sender
{
    NSNumber *resNum = sender.selectedItem.representedObject;
    _filter.minimumResolution = resNum ? resNum.integerValue : MacLCStreamResolutionUnknown;
    [self applyFiltersWithAnimation];
}

- (void)pictureChanged:(NSPopUpButton *)sender
{
    NSNumber *picNum = sender.selectedItem.representedObject;
    _filter.picture = picNum ? picNum.integerValue : MacLCStreamPictureAny;
    [self saveFilterPreferences];
    [self applyFiltersWithAnimation];
}

- (void)bestSoundChanged:(NSButton *)sender
{
    _filter.bestSoundOnly = (sender.state == NSControlStateValueOn);
    [self saveFilterPreferences];
    [self applyFiltersWithAnimation];
}

- (void)sortChanged:(NSPopUpButton *)sender
{
    NSNumber *sortNum = sender.selectedItem.representedObject;
    _filter.sortOrder = sortNum ? sortNum.integerValue : MacLCStreamSortRecommended;
    [self saveFilterPreferences];
    [self applyFiltersWithAnimation];
}

- (void)toggleHidePoorAction:(id)sender
{
    _filter.hidePoor = !_filter.hidePoor;
    [self applyFiltersWithAnimation];
}

- (void)applyFiltersWithAnimation
{
    if (MacLCDesign.reducedMotion) {
        [self applyFilters];
    } else {
        __weak typeof(self) weakSelf = self;
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = 0.1;
            weakSelf.tableView.animator.alphaValue = 0.2;
            weakSelf.bestMatchContainer.animator.alphaValue = 0.2;
        } completionHandler:^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            [strongSelf applyFilters];
            [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
                context.duration = 0.1;
                strongSelf.tableView.animator.alphaValue = 1.0;
                strongSelf.bestMatchContainer.animator.alphaValue = 1.0;
            }];
        }];
    }
}

- (void)applyFilters
{
    MacLCStreamChoice *keptSelected = _selectedChoice;
    _filteredChoices = [_filter apply:_allChoices];

    [self updateHiddenButton];

    MacLCStreamChoice *best = [MacLCStreamFilter bestMatchIn:_filteredChoices];
    _bestMatch = best;
    if (best) {
        [_bestMatchCard configureWithChoice:best filter:_filter];
        _filterBarTopWithoutBestMatch.active = NO;
        _filterBarTopWithBestMatch.active = YES;
        _bestMatchContainer.hidden = NO;
    } else {
        _bestMatchContainer.hidden = YES;
        _filterBarTopWithBestMatch.active = NO;
        _filterBarTopWithoutBestMatch.active = YES;
    }

    if (_allChoices.count > 0 && _filteredChoices.count == 0) {
        [self showEmptyStateWithTitle:_NS("No Versions Match")
                              message:_NS("Try changing or clearing your filters.")
                          buttonTitle:_NS("Clear Filters")
                               action:@selector(clearFiltersAction:)];
    } else if (_allChoices.count > 0) {
        _emptyStateView.hidden = YES;
        _scrollView.hidden = NO;
    }

    [_tableView reloadData];

    if (keptSelected) {
        if (_selectedSource == MacLCStreamSelectionSourceBestMatch && _bestMatch == keptSelected) {
            [self selectChoice:_bestMatch source:MacLCStreamSelectionSourceBestMatch];
        } else {
            NSUInteger idx = [_filteredChoices indexOfObject:keptSelected];
            if (idx != NSNotFound) {
                [self selectChoice:keptSelected source:MacLCStreamSelectionSourceTable];
            } else {
                [self selectChoice:nil source:MacLCStreamSelectionSourceNone];
            }
        }
    } else if (_bestMatch != nil && !_bestMatchContainer.hidden) {
        /* Play works at once: the suggestion is the selection. */
        [self selectChoice:_bestMatch source:MacLCStreamSelectionSourceBestMatch];
    } else if (_filteredChoices.count > 0) {
        [self selectChoice:_filteredChoices.firstObject source:MacLCStreamSelectionSourceTable];
    } else {
        [self selectChoice:nil source:MacLCStreamSelectionSourceNone];
    }
}

- (void)clearFiltersAction:(id)sender
{
    _filter.language = nil;
    _filter.minimumResolution = MacLCStreamResolutionUnknown;
    _filter.picture = MacLCStreamPictureAny;
    _filter.bestSoundOnly = NO;
    _filter.hidePoor = NO;
    [self saveFilterPreferences];
    [self rebuildFilterBarControls];
    [self applyFiltersWithAnimation];
}

#pragma mark - Selection Logic

- (void)selectChoice:(nullable MacLCStreamChoice *)choice source:(MacLCStreamSelectionSource)source
{
    _selectedChoice = choice;
    _selectedSource = source;

    _updatingSelection = YES;
    if (source == MacLCStreamSelectionSourceBestMatch) {
        [_tableView deselectAll:nil];
        _bestMatchCard.selected = YES;
    } else if (source == MacLCStreamSelectionSourceTable) {
        _bestMatchCard.selected = NO;
        if (choice) {
            NSUInteger idx = [_filteredChoices indexOfObject:choice];
            if (idx != NSNotFound && _tableView.selectedRow != (NSInteger)idx) {
                [_tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:idx] byExtendingSelection:NO];
                [_tableView scrollRowToVisible:idx];
            }
        } else {
            [_tableView deselectAll:nil];
        }
    } else {
        [_tableView deselectAll:nil];
        _bestMatchCard.selected = NO;
    }
    _updatingSelection = NO;

    _playButton.enabled = (_selectedChoice != nil);
    _startOverButton.enabled = (_selectedChoice != nil);
    _queueButton.enabled = (_selectedChoice != nil);
}

#pragma mark - Fetching Streams

- (void)fetchStreams
{
    [_fetchRequest cancel];
    _fetchRequest = nil;

    [_allChoices removeAllObjects];
    _filteredChoices = @[];
    [_failedAddons removeAllObjects];
    _selectedChoice = nil;
    _selectedSource = MacLCStreamSelectionSourceNone;
    _playButton.enabled = NO;
    _startOverButton.enabled = NO;
    _queueButton.enabled = NO;

    if (!MacLCAddonStore.sharedStore.hasStreamAddon) {
        [self showNoStreamAddonState];
        return;
    }

    _loading = YES;
    _emptyStateView.hidden = YES;
    _scrollView.hidden = NO;
    _bestMatchContainer.hidden = YES;
    _filterBarTopWithBestMatch.active = NO;
    _filterBarTopWithoutBestMatch.active = YES;
    _loadingSpinner.hidden = NO;
    [_loadingSpinner startAnimation:nil];
    _loadingLabel.hidden = NO;
    _errorFootnoteView.hidden = YES;

    [_tableView reloadData];

    NSString *type = _item.type ?: @"movie";
    NSString *videoID = _video ? _video.identifier : _item.identifier;

    __weak typeof(self) weakSelf = self;
    _fetchRequest = [MacLCAddonStore.sharedStore fetchStreamsForType:type
                                                     videoIdentifier:videoID
                                                           eachGroup:^(MacLCAddonStreamGroup *group) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        if (group.error && group.streams.count == 0) {
            NSString *addonName = group.addon.name ?: _NS("Add-on");
            if (![strongSelf.failedAddons containsObject:addonName]) {
                [strongSelf.failedAddons addObject:addonName];
                [strongSelf updateErrorFootnote];
            }
        }

        if (group.streams.count > 0) {
            for (MacLCAddonStream *s in group.streams) {
                MacLCStreamChoice *choice = [[MacLCStreamChoice alloc] initWithStream:s];
                [strongSelf.allChoices addObject:choice];
            }
            [strongSelf rebuildFilterBarControls];
            [strongSelf applyFilters];
        }
    } completion:^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf->_loading = NO;
        [strongSelf.loadingSpinner stopAnimation:nil];
        strongSelf.loadingSpinner.hidden = YES;
        strongSelf.loadingLabel.hidden = YES;

        [strongSelf rebuildFilterBarControls];
        [strongSelf applyFilters];

        if (strongSelf.allChoices.count == 0) {
            [strongSelf showEmptyStateWithTitle:_NS("No Versions Found")
                                        message:_NS("No streams available for this title.")
                                    buttonTitle:_NS("Try Again")
                                         action:@selector(fetchStreams)];
        }

        if (strongSelf.debugPlayWhenLoaded) {
            MacLCStreamChoice *target = strongSelf.bestMatch ?: strongSelf.filteredChoices.firstObject;
            if (target) {
                [strongSelf playChoice:target];
            }
        }
    }];
}

- (void)updateErrorFootnote
{
    if (_failedAddons.count > 0) {
        _errorLabel.stringValue = [NSString stringWithFormat:_NS("%@ didn’t answer"), [_failedAddons componentsJoinedByString:@", "]];
        _errorFootnoteView.hidden = NO;
    } else {
        _errorFootnoteView.hidden = YES;
    }
}

- (void)showNoStreamAddonState
{
    _emptyIconView.image = [NSImage imageWithSystemSymbolName:@"play.slash" accessibilityDescription:nil];
    _emptyIconView.contentTintColor = MacLCDesign.secondaryLabel;
    _emptyTitleLabel.stringValue = _NS("No Streams Add-on");
    _emptyMessageLabel.stringValue = _NS("Install an add-on that provides streams to play titles.");
    _emptyActionButton.title = _NS("Browse Add-ons…");
    _emptyActionButton.target = self;
    _emptyActionButton.action = @selector(openAddonsSettings:);
    _emptyActionButton.hidden = NO;

    _scrollView.hidden = YES;
    _bestMatchContainer.hidden = YES;
    _filterBarTopWithBestMatch.active = NO;
    _filterBarTopWithoutBestMatch.active = YES;
    _emptyStateView.hidden = NO;
}

- (void)showEmptyStateWithTitle:(NSString *)title
                        message:(NSString *)message
                    buttonTitle:(NSString *)buttonTitle
                         action:(SEL)action
{
    _emptyIconView.image = [NSImage imageWithSystemSymbolName:@"magnifyingglass" accessibilityDescription:nil];
    _emptyIconView.contentTintColor = MacLCDesign.secondaryLabel;
    _emptyTitleLabel.stringValue = title ?: @"";
    _emptyMessageLabel.stringValue = message ?: @"";
    _emptyActionButton.title = buttonTitle;
    _emptyActionButton.target = self;
    _emptyActionButton.action = action;
    _emptyActionButton.hidden = NO;

    _scrollView.hidden = YES;
    _bestMatchContainer.hidden = YES;
    _filterBarTopWithBestMatch.active = NO;
    _filterBarTopWithoutBestMatch.active = YES;
    _emptyStateView.hidden = NO;
}

- (void)openAddonsSettings:(id)sender
{
    [self endSheetWithResponse:NSModalResponseCancel];
    MacLCSettingsWindowController *swc = VLCMain.sharedInstance.settingsWindowController;
    [swc showSettingsWindowWithLevel:NSNormalWindowLevel];
    [swc selectPaneWithIdentifier:@"addons"];
}

#pragma mark - Table View Data Source & Delegate

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    if (_loading && _allChoices.count == 0) {
        return 4;
    }
    return _filteredChoices.count;
}

- (nullable NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(nullable NSTableColumn *)tableColumn row:(NSInteger)row
{
    if (_loading && _allChoices.count == 0) {
        static NSString * const kPlaceholderCellId = @"MacLCStreamPlaceholderCell";
        MacLCStreamPlaceholderCellView *cell = [tableView makeViewWithIdentifier:kPlaceholderCellId owner:self];
        if (!cell) {
            cell = [[MacLCStreamPlaceholderCellView alloc] initWithFrame:NSMakeRect(0, 0, 400, 76)];
            cell.identifier = kPlaceholderCellId;
        }
        return cell;
    }

    if (row < 0 || row >= (NSInteger)_filteredChoices.count) return nil;

    static NSString * const kStreamCellId = @"MacLCStreamRowCell";
    MacLCStreamRowCellView *cell = [tableView makeViewWithIdentifier:kStreamCellId owner:self];
    if (!cell) {
        cell = [[MacLCStreamRowCellView alloc] initWithFrame:NSMakeRect(0, 0, 400, 76)];
        cell.identifier = kStreamCellId;
    }

    MacLCStreamChoice *choice = _filteredChoices[row];
    [cell configureWithChoice:choice];

    __weak typeof(self) weakSelf = self;
    __weak typeof(choice) weakChoice = choice;
    cell.playHandler = ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        __strong typeof(weakChoice) strongChoice = weakChoice;
        if (strongSelf && strongChoice) {
            [strongSelf selectChoice:strongChoice source:MacLCStreamSelectionSourceTable];
            [strongSelf playAction:nil];
        }
    };
    cell.queueHandler = ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        __strong typeof(weakChoice) strongChoice = weakChoice;
        if (strongSelf && strongChoice) {
            [strongSelf selectChoice:strongChoice source:MacLCStreamSelectionSourceTable];
            [strongSelf addToQueueAction:nil];
        }
    };

    return cell;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
    if (_updatingSelection) return;

    NSInteger row = _tableView.selectedRow;
    if (row >= 0 && row < (NSInteger)_filteredChoices.count) {
        [self selectChoice:_filteredChoices[row] source:MacLCStreamSelectionSourceTable];
    } else {
        if (_selectedSource == MacLCStreamSelectionSourceTable) {
            [self selectChoice:nil source:MacLCStreamSelectionSourceNone];
        }
    }
}

- (void)tableDoubleClicked:(id)sender
{
    NSInteger row = _tableView.clickedRow;
    if (row >= 0 && row < (NSInteger)_filteredChoices.count) {
        [self selectChoice:_filteredChoices[row] source:MacLCStreamSelectionSourceTable];
        [self playAction:nil];
    }
}

#pragma mark - Playing & Actions

- (void)playAction:(nullable id)sender
{
    if (_selectedChoice) {
        [self playChoice:_selectedChoice startPosition:_resumeProgress.position];
    }
}

- (void)startOverAction:(nullable id)sender
{
    if (_selectedChoice) {
        [self playChoice:_selectedChoice startPosition:0];
    }
}

- (void)addToQueueAction:(nullable id)sender
{
    if (_selectedChoice) {
        [self queueChoice:_selectedChoice];
    }
}

- (void)cancelAction:(nullable id)sender
{
    [self endSheetWithResponse:NSModalResponseCancel];
}

- (void)playChoice:(MacLCStreamChoice *)choice
{
    [self playChoice:choice startPosition:_resumeProgress.position];
}

- (void)playChoice:(MacLCStreamChoice *)choice startPosition:(NSTimeInterval)startPosition
{
    if (!choice.stream) return;

    [MacLCWatchPlayback.sharedPlayback playStream:choice.stream
                                             item:_item
                                            video:_video
                                    startPosition:startPosition];
    [self endSheetWithResponse:NSModalResponseOK];
}

- (void)queueChoice:(MacLCStreamChoice *)choice
{
    if (!choice.stream) return;

    NSString *itemName = [MacLCAddonStore itemNameForItem:_item video:_video];
    VLCOpenInputMetadata *meta = [[VLCOpenInputMetadata alloc] init];
    meta.MRLString = choice.stream.MRL;
    meta.itemName = itemName;

    [VLCMain.sharedInstance.playQueueController addPlayQueueItems:@[meta]];
    [self endSheetWithResponse:NSModalResponseCancel];
}

#pragma mark - Explanations Popover

- (void)showExplanationsPopover:(NSButton *)sender
{
    if (_explanationsPopover) {
        [_explanationsPopover performClose:nil];
        _explanationsPopover = nil;
        return;
    }

    NSMutableOrderedSet<MacLCExplainerTopic> *topics = [NSMutableOrderedSet orderedSet];
    [topics addObject:MacLCExplainerTopicBestMatch];
    [topics addObject:MacLCExplainerTopicVerdict];

    for (MacLCStreamChoice *choice in _filteredChoices) {
        MacLCStreamFacts *f = choice.facts;
        MacLCExplainerTopic resTopic = TopicForResolution(f.resolution);
        if (resTopic) [topics addObject:resTopic];

        MacLCExplainerTopic drTopic = TopicForDynamicRange(f.dynamicRange);
        if (drTopic) [topics addObject:drTopic];

        for (MacLCStreamAudio *a in f.audio) {
            MacLCExplainerTopic aTopic = TopicForAudio(a);
            if (aTopic) [topics addObject:aTopic];
        }

        if (f.isMultiLanguage) {
            [topics addObject:MacLCExplainerTopicMultiAudio];
        }

        MacLCExplainerTopic srcTopic = TopicForSource(f.source);
        if (srcTopic) [topics addObject:srcTopic];

        if (f.isPack) [topics addObject:MacLCExplainerTopicPack];
        if (f.debridService.length > 0) [topics addObject:MacLCExplainerTopicDebrid];
        if (f.seeders >= 0) [topics addObject:MacLCExplainerTopicPeers];
        if (f.health != MacLCStreamHealthUnknown) [topics addObject:MacLCExplainerTopicHealth];
        if (f.sizeBytes > 0) [topics addObject:MacLCExplainerTopicSize];
    }

    NSViewController *vc = [[NSViewController alloc] init];
    NSView *container = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 360, 380)];

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:container.bounds];
    scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    scroll.drawsBackground = NO;
    scroll.hasVerticalScroller = YES;
    scroll.autohidesScrollers = YES;

    NSView *docView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 360, 40)];
    docView.translatesAutoresizingMaskIntoConstraints = NO;

    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 12.0;
    stack.edgeInsets = NSEdgeInsetsMake(12, 16, 12, 16);
    [docView addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:docView.topAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:docView.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:docView.trailingAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:docView.bottomAnchor],
        [docView.widthAnchor constraintEqualToConstant:360],
    ]];

    NSTextField *header = [NSTextField labelWithString:_NS("What do these mean?")];
    header.font = MacLCDesign.headline;
    header.textColor = MacLCDesign.primaryLabel;
    [stack addArrangedSubview:header];

    for (MacLCExplainerTopic topic in topics) {
        NSButton *rowBtn = [self makeTopicButtonForTopic:topic];
        [stack addArrangedSubview:rowBtn];
    }

    scroll.documentView = docView;
    [container addSubview:scroll];

    vc.view = container;
    _explanationsPopover = [[NSPopover alloc] init];
    _explanationsPopover.behavior = NSPopoverBehaviorTransient;
    _explanationsPopover.contentSize = NSMakeSize(360, 380);
    _explanationsPopover.contentViewController = vc;
    [_explanationsPopover showRelativeToRect:sender.bounds ofView:sender preferredEdge:NSRectEdgeMaxY];
}

- (NSButton *)makeTopicButtonForTopic:(MacLCExplainerTopic)topic
{
    NSButton *btn = [NSButton buttonWithTitle:@"" target:self action:@selector(topicButtonClicked:)];
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    btn.bordered = NO;
    btn.wantsLayer = YES;

    NSImageView *icon = [[NSImageView alloc] initWithFrame:NSZeroRect];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.image = [NSImage imageWithSystemSymbolName:[MacLCExplainer symbolNameForTopic:topic] accessibilityDescription:nil];
    icon.contentTintColor = [MacLCExplainer tintForTopic:topic];
    [btn addSubview:icon];

    NSTextField *title = [NSTextField labelWithString:[MacLCExplainer titleForTopic:topic]];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.font = MacLCDesign.bodyEmphasized;
    title.textColor = MacLCDesign.primaryLabel;
    [btn addSubview:title];

    NSTextField *desc = [NSTextField labelWithString:[MacLCExplainer explanationForTopic:topic]];
    desc.translatesAutoresizingMaskIntoConstraints = NO;
    desc.font = MacLCDesign.subheadline;
    desc.textColor = MacLCDesign.secondaryLabel;
    desc.maximumNumberOfLines = 2;
    desc.lineBreakMode = NSLineBreakByWordWrapping;
    [btn addSubview:desc];

    [NSLayoutConstraint activateConstraints:@[
        [icon.leadingAnchor constraintEqualToAnchor:btn.leadingAnchor constant:4.0],
        [icon.topAnchor constraintEqualToAnchor:btn.topAnchor constant:4.0],
        [icon.widthAnchor constraintEqualToConstant:20.0],
        [icon.heightAnchor constraintEqualToConstant:20.0],

        [title.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:8.0],
        [title.topAnchor constraintEqualToAnchor:btn.topAnchor constant:4.0],
        [title.trailingAnchor constraintEqualToAnchor:btn.trailingAnchor constant:-4.0],

        [desc.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [desc.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:2.0],
        [desc.trailingAnchor constraintEqualToAnchor:btn.trailingAnchor constant:-4.0],
        [desc.bottomAnchor constraintEqualToAnchor:btn.bottomAnchor constant:-4.0],
    ]];

    objc_setAssociatedObject(btn, "MacLCTopicKey", topic, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return btn;
}

- (void)topicButtonClicked:(NSButton *)sender
{
    MacLCExplainerTopic topic = objc_getAssociatedObject(sender, "MacLCTopicKey");
    if (topic) {
        [MacLCExplainer showTopic:topic relativeToView:sender];
    }
}

@end
