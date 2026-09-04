/*****************************************************************************
 * MacLCDesign.m: MacLC macOS design token layer
 *****************************************************************************
 * Copyright (C) 2026 VLC authors and VideoLAN
 *
 * Authors: MacLC Design System Team
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

#import "MacLCDesign.h"
#import "MacLCCardView.h"

#import <os/lock.h>

@interface MacLCVisualEffectView : NSVisualEffectView

@property (nonatomic, strong, nullable) NSColor *opaqueFallbackColor;
@property (nonatomic, assign) NSVisualEffectState normalState;

- (void)updateTransparencyFallback;

@end

@implementation MacLCVisualEffectView

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        _normalState = NSVisualEffectStateFollowsWindowActiveState;
        [self setupAccessibilityObserver];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (self) {
        _normalState = NSVisualEffectStateFollowsWindowActiveState;
        [self setupAccessibilityObserver];
    }
    return self;
}

- (void)dealloc
{
    [[NSWorkspace.sharedWorkspace notificationCenter] removeObserver:self];
}

- (void)setupAccessibilityObserver
{
    [[NSWorkspace.sharedWorkspace notificationCenter] addObserver:self
                                                         selector:@selector(accessibilityOptionsDidChange:)
                                                             name:NSWorkspaceAccessibilityDisplayOptionsDidChangeNotification
                                                           object:nil];
}

- (void)accessibilityOptionsDidChange:(NSNotification *)notification
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateTransparencyFallback];
    });
}

- (void)viewDidChangeEffectiveAppearance
{
    [super viewDidChangeEffectiveAppearance];
    [self updateTransparencyFallback];
}

- (void)updateTransparencyFallback
{
    const BOOL reduceTransparency = NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceTransparency;
    if (reduceTransparency) {
        self.state = NSVisualEffectStateInactive;
        self.wantsLayer = YES;
        NSColor *fallback = self.opaqueFallbackColor ?: MacLCDesign.windowBackground;
        self.layer.backgroundColor = fallback.CGColor;
    } else {
        self.state = self.normalState;
        if (self.layer) {
            self.layer.backgroundColor = nil;
        }
    }
    [self setNeedsDisplay:YES];
}

- (void)setOpaqueFallbackColor:(NSColor *)opaqueFallbackColor
{
    _opaqueFallbackColor = opaqueFallbackColor;
    [self updateTransparencyFallback];
}

@end


@implementation MacLCDesign

#pragma mark - Bundle Helper

+ (NSBundle *)designBundle
{
    static NSBundle *bundle = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        bundle = [NSBundle bundleForClass:[MacLCDesign class]];
    });
    return bundle;
}


#pragma mark - Colours

+ (NSColor *)primaryLabel
{
    return [NSColor labelColor];
}

+ (NSColor *)secondaryLabel
{
    return [NSColor secondaryLabelColor];
}

+ (NSColor *)tertiaryLabel
{
    return [NSColor tertiaryLabelColor];
}

+ (NSColor *)quaternaryLabel
{
    return [NSColor quaternaryLabelColor];
}

+ (NSColor *)accent
{
    return [NSColor controlAccentColor];
}

+ (NSColor *)separator
{
    return [NSColor separatorColor];
}

+ (NSColor *)windowBackground
{
    return [NSColor windowBackgroundColor];
}

+ (NSColor *)contentBackground
{
    return [NSColor colorNamed:@"MacLCContentBackground" bundle:[self designBundle]] ?: [NSColor controlBackgroundColor];
}

+ (NSColor *)cardBackground
{
    return [NSColor colorNamed:@"MacLCCardBackground" bundle:[self designBundle]] ?: [NSColor controlBackgroundColor];
}

+ (NSColor *)controlBackground
{
    return [NSColor controlBackgroundColor];
}

+ (NSColor *)selectionBackground
{
    return [NSColor selectedContentBackgroundColor];
}

+ (NSColor *)selectionLabel
{
    return [NSColor alternateSelectedControlTextColor];
}

+ (NSColor *)destructive
{
    return [NSColor systemRedColor];
}

+ (NSColor *)warning
{
    return [NSColor systemOrangeColor];
}

+ (NSColor *)success
{
    return [NSColor systemGreenColor];
}

+ (NSColor *)placeholder
{
    return [NSColor placeholderTextColor];
}

+ (NSColor *)scrubberTrack
{
    return [NSColor colorNamed:@"MacLCScrubberTrack" bundle:[self designBundle]] ?: [NSColor quaternaryLabelColor];
}

+ (NSColor *)scrubberFill
{
    return [NSColor colorNamed:@"MacLCScrubberFill" bundle:[self designBundle]] ?: [NSColor controlAccentColor];
}


#pragma mark - Typography

+ (NSFont *)largeTitle
{
    return [NSFont preferredFontForTextStyle:NSFontTextStyleLargeTitle options:@{}];
}

+ (NSFont *)title1
{
    return [NSFont preferredFontForTextStyle:NSFontTextStyleTitle1 options:@{}];
}

+ (NSFont *)title2
{
    return [NSFont preferredFontForTextStyle:NSFontTextStyleTitle2 options:@{}];
}

+ (NSFont *)title3
{
    return [NSFont preferredFontForTextStyle:NSFontTextStyleTitle3 options:@{}];
}

+ (NSFont *)headline
{
    return [NSFont preferredFontForTextStyle:NSFontTextStyleHeadline options:@{}];
}

+ (NSFont *)body
{
    return [NSFont preferredFontForTextStyle:NSFontTextStyleBody options:@{}];
}

+ (NSFont *)bodyEmphasized
{
    NSFont * const baseFont = [self body];
    NSFontDescriptor * const boldDescriptor = [baseFont.fontDescriptor fontDescriptorWithSymbolicTraits:NSFontDescriptorTraitBold];
    if (boldDescriptor) {
        NSFont * const font = [NSFont fontWithDescriptor:boldDescriptor size:0.0];
        if (font) {
            return font;
        }
    }
    return baseFont;
}

+ (NSFont *)callout
{
    return [NSFont preferredFontForTextStyle:NSFontTextStyleCallout options:@{}];
}

+ (NSFont *)subheadline
{
    return [NSFont preferredFontForTextStyle:NSFontTextStyleSubheadline options:@{}];
}

+ (NSFont *)footnote
{
    return [NSFont preferredFontForTextStyle:NSFontTextStyleFootnote options:@{}];
}

+ (NSFont *)caption
{
    return [NSFont preferredFontForTextStyle:NSFontTextStyleCaption1 options:@{}];
}

+ (NSFont *)monospacedDigitBody
{
    return [self monospacedDigitFontForTextStyle:NSFontTextStyleBody];
}

+ (NSFont *)monospacedDigitFontForTextStyle:(NSFontTextStyle)style
{
    if (!style) {
        style = NSFontTextStyleBody;
    }

    NSFont * const baseFont = [NSFont preferredFontForTextStyle:style options:@{}];
    NSArray * const features = @[
        @{
            NSFontFeatureTypeIdentifierKey: @(kNumberSpacingType),
            NSFontFeatureSelectorIdentifierKey: @(kMonospacedNumbersSelector)
        }
    ];

    NSFontDescriptor * const descriptor = [baseFont.fontDescriptor fontDescriptorByAddingAttributes:@{
        NSFontFeatureSettingsAttribute: features
    }];

    NSFont * const font = [NSFont fontWithDescriptor:descriptor size:0.0];
    return font ?: baseFont;
}

+ (NSFont *)monospacedDigitFontForTextStyle:(NSFontTextStyle)style weight:(NSFontWeight)weight
{
    if (!style) {
        style = NSFontTextStyleBody;
    }

    NSFont * const baseFont = [NSFont preferredFontForTextStyle:style options:@{}];
    NSFontDescriptor * const weightDesc = [baseFont.fontDescriptor fontDescriptorByAddingAttributes:@{
        NSFontTraitsAttribute: @{
            NSFontWeightTrait: @(weight)
        }
    }];

    NSArray * const features = @[
        @{
            NSFontFeatureTypeIdentifierKey: @(kNumberSpacingType),
            NSFontFeatureSelectorIdentifierKey: @(kMonospacedNumbersSelector)
        }
    ];

    NSFontDescriptor * const descriptor = [weightDesc fontDescriptorByAddingAttributes:@{
        NSFontFeatureSettingsAttribute: features
    }];

    NSFont * const font = [NSFont fontWithDescriptor:descriptor size:0.0];
    return font ?: baseFont;
}


#pragma mark - Spacing (8-pt grid)

+ (CGFloat)spacingXXS
{
    return 2.0;
}

+ (CGFloat)spacingXS
{
    return 4.0;
}

+ (CGFloat)spacingS
{
    return 8.0;
}

+ (CGFloat)spacingM
{
    return 12.0;
}

+ (CGFloat)spacingL
{
    return 16.0;
}

+ (CGFloat)spacingXL
{
    return 20.0;
}

+ (CGFloat)spacingXXL
{
    return 28.0;
}

+ (CGFloat)spacingXXXL
{
    return 40.0;
}

+ (CGFloat)windowContentMargin
{
    return 20.0;
}

+ (CGFloat)groupSpacing
{
    return 20.0;
}

+ (CGFloat)labelControlSpacing
{
    return 8.0;
}

+ (CGFloat)rowMinimumHeight
{
    return 32.0;
}

+ (CGFloat)sectionHeaderSpacing
{
    return 16.0;
}


#pragma mark - Radii

+ (CGFloat)cornerRadiusSmall
{
    return 6.0;
}

+ (CGFloat)cornerRadiusMedium
{
    return 8.0;
}

+ (CGFloat)cornerRadiusLarge
{
    return 12.0;
}

+ (CGFloat)cornerRadiusCapsule
{
    return CGFLOAT_MAX;
}


#pragma mark - Materials

+ (NSVisualEffectView *)sidebarMaterialView
{
    MacLCVisualEffectView * const view = [[MacLCVisualEffectView alloc] initWithFrame:NSZeroRect];
    view.material = NSVisualEffectMaterialSidebar;
    view.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    view.normalState = NSVisualEffectStateFollowsWindowActiveState;
    view.opaqueFallbackColor = self.windowBackground;
    [view updateTransparencyFallback];
    return view;
}

+ (NSVisualEffectView *)headerMaterialView
{
    MacLCVisualEffectView * const view = [[MacLCVisualEffectView alloc] initWithFrame:NSZeroRect];
    view.material = NSVisualEffectMaterialHeaderView;
    view.blendingMode = NSVisualEffectBlendingModeWithinWindow;
    view.normalState = NSVisualEffectStateFollowsWindowActiveState;
    view.opaqueFallbackColor = self.windowBackground;
    [view updateTransparencyFallback];
    return view;
}

+ (NSVisualEffectView *)contentBackgroundMaterialView
{
    MacLCVisualEffectView * const view = [[MacLCVisualEffectView alloc] initWithFrame:NSZeroRect];
    view.material = NSVisualEffectMaterialUnderWindowBackground;
    view.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    view.normalState = NSVisualEffectStateFollowsWindowActiveState;
    view.opaqueFallbackColor = self.contentBackground;
    [view updateTransparencyFallback];
    return view;
}

+ (NSVisualEffectView *)floatingHUDMaterialView
{
    MacLCVisualEffectView * const view = [[MacLCVisualEffectView alloc] initWithFrame:NSZeroRect];
    view.material = NSVisualEffectMaterialHUDWindow;
    view.blendingMode = NSVisualEffectBlendingModeWithinWindow;
    view.normalState = NSVisualEffectStateActive;
    view.opaqueFallbackColor = self.windowBackground;
    [view updateTransparencyFallback];
    return view;
}

+ (NSVisualEffectView *)sidebarVisualEffectView
{
    return [self sidebarMaterialView];
}

+ (NSVisualEffectView *)headerVisualEffectView
{
    return [self headerMaterialView];
}

+ (NSVisualEffectView *)contentBackgroundVisualEffectView
{
    return [self contentBackgroundMaterialView];
}

+ (NSVisualEffectView *)floatingHUDVisualEffectView
{
    return [self floatingHUDMaterialView];
}

+ (NSVisualEffectView *)floatingHUDPanelMaterialView
{
    return [self floatingHUDMaterialView];
}


#pragma mark - Symbols

+ (nullable NSImage *)symbolNamed:(NSString *)name accessibilityLabel:(nullable NSString *)accessibilityLabel
{
    return [self symbolNamed:name pointSize:0.0 weight:NSFontWeightRegular accessibilityLabel:accessibilityLabel];
}

+ (nullable NSImage *)symbolNamed:(NSString *)name
                        pointSize:(CGFloat)pointSize
                           weight:(NSFontWeight)weight
               accessibilityLabel:(nullable NSString *)accessibilityLabel
{
    if (!name || name.length == 0) {
        return nil;
    }

    NSImage *symbolImage = [NSImage imageWithSystemSymbolName:name accessibilityDescription:accessibilityLabel];
    if (!symbolImage) {
        static NSMutableSet<NSString *> *sMissingSymbols = nil;
        static dispatch_once_t sOnceToken;
        static os_unfair_lock sLock = OS_UNFAIR_LOCK_INIT;

        dispatch_once(&sOnceToken, ^{
            sMissingSymbols = [NSMutableSet set];
        });

        os_unfair_lock_lock(&sLock);
        const BOOL alreadyLogged = [sMissingSymbols containsObject:name];
        if (!alreadyLogged) {
            [sMissingSymbols addObject:name];
        }
        os_unfair_lock_unlock(&sLock);

        if (!alreadyLogged) {
            NSLog(@"[MacLCDesign] SF Symbol named '%@' is not available on this macOS version.", name);
        }
        return nil;
    }

    if (pointSize > 0.0) {
        NSImageSymbolConfiguration * const config = [NSImageSymbolConfiguration configurationWithPointSize:pointSize
                                                                                                     weight:weight];
        symbolImage = [symbolImage imageWithSymbolConfiguration:config] ?: symbolImage;
    }

    if (accessibilityLabel) {
        symbolImage.accessibilityDescription = accessibilityLabel;
    }

    return symbolImage;
}


#pragma mark - Motion

+ (NSTimeInterval)animationDuration
{
    return 0.25;
}

+ (BOOL)reducedMotion
{
    return NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion;
}

+ (void)performAnimated:(void(^)(void))actions
{
    if (!actions) {
        return;
    }

    if (self.reducedMotion) {
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext * _Nonnull context) {
            context.duration = 0.0;
            context.allowsImplicitAnimation = NO;
            actions();
        }];
    } else {
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext * _Nonnull context) {
            context.duration = self.animationDuration;
            context.allowsImplicitAnimation = YES;
            actions();
        }];
    }
}


#pragma mark - Card Helper

+ (MacLCCardView *)cardViewWithTitle:(nullable NSString *)title
{
    return [MacLCCardView cardViewWithTitle:title];
}

@end
