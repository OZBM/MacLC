/*****************************************************************************
 * MacLCSoundMode.m
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

#ifdef HAVE_CONFIG_H
# import "config.h"
#endif

#import "MacLCSoundMode.h"

#import <vlc_common.h>
#import <vlc_aout.h>
#import <vlc_variables.h>

#import "sound/MacLCSoundPresets.h"
#import "main/VLCMain.h"
#import "playqueue/VLCPlayQueueController.h"
#import "playqueue/VLCPlayerController.h"

#import "extensions/NSString+Helpers.h"

NSString * const MacLCSoundModeDidChangeNotification = @"MacLCSoundModeDidChangeNotification";

static NSString * const kMacLCSoundModeEnabledKey = @"MacLCSoundModeEnabled";
static NSString * const kMacLCSoundModePresetKey = @"MacLCSoundModePreset";
static NSString * const kMacLCSoundModeIntensitiesKey = @"MacLCSoundModeIntensities";
static NSString * const kMacLCSoundModeCustomBandsKey = @"MacLCSoundModeCustomBands";
static NSString * const kMacLCSoundModeOwnedFiltersKey = @"MacLCSoundModeOwnedFilters";

@interface MacLCSoundMode () <NSMenuItemValidation>
@end

@implementation MacLCSoundMode
{
    BOOL _enabled;
    NSString *_presetIdentifier;
    NSArray<NSNumber *> *_customBands;
}

+ (MacLCSoundMode *)sharedMode
{
    static MacLCSoundMode *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[MacLCSoundMode alloc] init];
    });
    return shared;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        _enabled = [defaults boolForKey:kMacLCSoundModeEnabledKey];

        NSString *savedPreset = [defaults stringForKey:kMacLCSoundModePresetKey];
        if (savedPreset.length > 0 && [MacLCSoundPresets presetForIdentifier:savedPreset] != nil) {
            _presetIdentifier = [savedPreset copy];
        } else {
            _presetIdentifier = @"voice";
        }

        NSArray *savedBands = [defaults arrayForKey:kMacLCSoundModeCustomBandsKey];
        if (savedBands.count == 10) {
            NSMutableArray<NSNumber *> *validBands = [NSMutableArray arrayWithCapacity:10];
            for (id item in savedBands) {
                float val = [item respondsToSelector:@selector(floatValue)] ? [item floatValue] : 0.0f;
                val = fmaxf(-20.0f, fminf(20.0f, val));
                [validBands addObject:@(val)];
            }
            _customBands = [validBands copy];
        } else {
            _customBands = @[@0.0f, @0.0f, @0.0f, @0.0f, @0.0f, @0.0f, @0.0f, @0.0f, @0.0f, @0.0f];
        }

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(playerMediaItemChanged:)
                                                     name:VLCPlayerCurrentMediaItemChanged
                                                   object:nil];
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Media Notifications

- (void)playerMediaItemChanged:(NSNotification *)notification
{
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self applyToAudioOutput];
        });
        return;
    }
    [self applyToAudioOutput];
}

#pragma mark - Properties

- (BOOL)isEnabled
{
    NSAssert([NSThread isMainThread], @"MacLCSoundMode must be accessed on the main thread");
    return _enabled;
}

- (void)setEnabled:(BOOL)enabled
{
    NSAssert([NSThread isMainThread], @"MacLCSoundMode must be accessed on the main thread");
    if (_enabled == enabled) {
        return;
    }
    _enabled = enabled;
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:kMacLCSoundModeEnabledKey];
    [self applyToAudioOutput];
    [[NSNotificationCenter defaultCenter] postNotificationName:MacLCSoundModeDidChangeNotification object:self];
}

- (NSString *)presetIdentifier
{
    NSAssert([NSThread isMainThread], @"MacLCSoundMode must be accessed on the main thread");
    return _presetIdentifier;
}

- (void)setPresetIdentifier:(NSString *)presetIdentifier
{
    NSAssert([NSThread isMainThread], @"MacLCSoundMode must be accessed on the main thread");
    if (presetIdentifier == nil || [_presetIdentifier isEqualToString:presetIdentifier]) {
        return;
    }
    _presetIdentifier = [presetIdentifier copy];
    [[NSUserDefaults standardUserDefaults] setObject:_presetIdentifier forKey:kMacLCSoundModePresetKey];
    [self applyToAudioOutput];
    [[NSNotificationCenter defaultCenter] postNotificationName:MacLCSoundModeDidChangeNotification object:self];
}

- (float)intensity
{
    NSAssert([NSThread isMainThread], @"MacLCSoundMode must be accessed on the main thread");
    if ([_presetIdentifier isEqualToString:@"custom"]) {
        return 1.0f;
    }
    NSDictionary *intensities = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kMacLCSoundModeIntensitiesKey];
    NSNumber *val = intensities[_presetIdentifier];
    if (val != nil) {
        return fmaxf(0.0f, fminf(1.0f, val.floatValue));
    }
    MacLCSoundPreset *preset = [MacLCSoundPresets presetForIdentifier:_presetIdentifier];
    return preset ? preset.defaultIntensity : 0.7f;
}

- (void)setIntensity:(float)intensity
{
    NSAssert([NSThread isMainThread], @"MacLCSoundMode must be accessed on the main thread");
    if ([_presetIdentifier isEqualToString:@"custom"]) {
        return;
    }
    float clamped = fmaxf(0.0f, fminf(1.0f, intensity));
    NSMutableDictionary *intensities = [[[NSUserDefaults standardUserDefaults] dictionaryForKey:kMacLCSoundModeIntensitiesKey] mutableCopy];
    if (!intensities) {
        intensities = [NSMutableDictionary dictionary];
    }
    intensities[_presetIdentifier] = @(clamped);
    [[NSUserDefaults standardUserDefaults] setObject:intensities forKey:kMacLCSoundModeIntensitiesKey];
    [self applyToAudioOutput];
    [[NSNotificationCenter defaultCenter] postNotificationName:MacLCSoundModeDidChangeNotification object:self];
}

- (NSArray<NSNumber *> *)customBands
{
    NSAssert([NSThread isMainThread], @"MacLCSoundMode must be accessed on the main thread");
    return _customBands;
}

- (void)setCustomBands:(NSArray<NSNumber *> *)customBands
{
    NSAssert([NSThread isMainThread], @"MacLCSoundMode must be accessed on the main thread");
    NSMutableArray<NSNumber *> *validBands = [NSMutableArray arrayWithCapacity:10];
    for (NSUInteger i = 0; i < 10; i++) {
        float val = (i < customBands.count) ? customBands[i].floatValue : 0.0f;
        val = fmaxf(-20.0f, fminf(20.0f, val));
        [validBands addObject:@(val)];
    }
    _customBands = [validBands copy];
    [[NSUserDefaults standardUserDefaults] setObject:_customBands forKey:kMacLCSoundModeCustomBandsKey];
    [self applyToAudioOutput];
    [[NSNotificationCenter defaultCenter] postNotificationName:MacLCSoundModeDidChangeNotification object:self];
}

- (NSArray<MacLCSoundPreset *> *)presets
{
    return [MacLCSoundPresets allPresets];
}

- (NSArray<NSNumber *> *)effectiveBands
{
    NSAssert([NSThread isMainThread], @"MacLCSoundMode must be accessed on the main thread");
    if ([_presetIdentifier isEqualToString:@"custom"]) {
        return self.customBands;
    }
    MacLCSoundPreset *preset = [MacLCSoundPresets presetForIdentifier:_presetIdentifier];
    if (!preset) {
        return self.customBands;
    }
    return [MacLCSoundPresets scaledBandsForPreset:preset intensity:self.intensity];
}

#pragma mark - Audio Output Application

- (void)applyToAudioOutput
{
    NSAssert([NSThread isMainThread], @"MacLCSoundMode must be accessed on the main thread");

    VLCPlayerController *player = VLCMain.sharedInstance.playQueueController.playerController;
    if (!player) {
        return;
    }
    audio_output_t *p_aout = [player mainAudioOutput];
    if (!p_aout) {
        return;
    }

    if (self.isEnabled) {
        // Set parameters BEFORE changing "audio-filter"
        // 1. Equalizer: ISO bands -> equalizer-vlcfreqs = false. The equalizer reads
        //    it only when it is created: one built earlier with the legacy bands
        //    (Audio Effects panel) must be rebuilt.
        var_Create(p_aout, "equalizer-vlcfreqs", VLC_VAR_BOOL | VLC_VAR_DOINHERIT);
        const bool hadLegacyBands = var_GetBool(p_aout, "equalizer-vlcfreqs");
        var_SetBool(p_aout, "equalizer-vlcfreqs", false);

        NSArray<NSNumber *> *bands = self.effectiveBands;
        NSString *bandsString = [MacLCSoundPresets formatBandsString:bands];
        var_Create(p_aout, "equalizer-bands", VLC_VAR_STRING | VLC_VAR_DOINHERIT);
        var_SetString(p_aout, "equalizer-bands", [bandsString UTF8String]);

        float preamp = [MacLCSoundPresets calculatePreampForBands:bands];
        var_Create(p_aout, "equalizer-preamp", VLC_VAR_FLOAT | VLC_VAR_DOINHERIT);
        var_SetFloat(p_aout, "equalizer-preamp", preamp);

        // 2. Dialogue boost: maclc_dialogue
        MacLCSoundPreset *preset = [MacLCSoundPresets presetForIdentifier:self.presetIdentifier];
        float dialogueAmount = [MacLCSoundPresets scaledDialogueAmountForPreset:preset intensity:self.intensity];
        var_Create(p_aout, "maclc-dialogue-amount", VLC_VAR_FLOAT | VLC_VAR_DOINHERIT);
        var_SetFloat(p_aout, "maclc-dialogue-amount", dialogueAmount);

        // 3. Compressor
        if (preset && preset.hasCompressor) {
            float ratio = [MacLCSoundPresets scaledCompressorRatioForPreset:preset intensity:self.intensity];
            float makeup = [MacLCSoundPresets scaledCompressorMakeupForPreset:preset intensity:self.intensity];

            var_Create(p_aout, "compressor-rms-peak", VLC_VAR_FLOAT | VLC_VAR_DOINHERIT);
            var_SetFloat(p_aout, "compressor-rms-peak", preset.compressorRMSPeak);

            var_Create(p_aout, "compressor-attack", VLC_VAR_FLOAT | VLC_VAR_DOINHERIT);
            var_SetFloat(p_aout, "compressor-attack", preset.compressorAttack);

            var_Create(p_aout, "compressor-release", VLC_VAR_FLOAT | VLC_VAR_DOINHERIT);
            var_SetFloat(p_aout, "compressor-release", preset.compressorRelease);

            var_Create(p_aout, "compressor-threshold", VLC_VAR_FLOAT | VLC_VAR_DOINHERIT);
            var_SetFloat(p_aout, "compressor-threshold", preset.compressorThreshold);

            var_Create(p_aout, "compressor-ratio", VLC_VAR_FLOAT | VLC_VAR_DOINHERIT);
            var_SetFloat(p_aout, "compressor-ratio", ratio);

            var_Create(p_aout, "compressor-knee", VLC_VAR_FLOAT | VLC_VAR_DOINHERIT);
            var_SetFloat(p_aout, "compressor-knee", preset.compressorKnee);

            var_Create(p_aout, "compressor-makeup-gain", VLC_VAR_FLOAT | VLC_VAR_DOINHERIT);
            var_SetFloat(p_aout, "compressor-makeup-gain", makeup);
        }

        // 4. Safety limiter: limiter-threshold = -1.5
        var_Create(p_aout, "limiter-threshold", VLC_VAR_FLOAT | VLC_VAR_DOINHERIT);
        var_SetFloat(p_aout, "limiter-threshold", -1.5f);

        // 5. Update audio-filter chain if changed
        char *psz_filters = var_GetString(p_aout, "audio-filter");
        NSString *currentFilters = psz_filters ? [NSString stringWithUTF8String:psz_filters] : @"";
        free(psz_filters);

        NSArray<NSString *> *newOwned = nil;
        NSString *newFilters = [MacLCSoundPresets filterStringForEnablingPreset:preset
                                                                     intensity:self.intensity
                                                           currentFilterString:currentFilters
                                                                  ownedFilters:&newOwned];

        [[NSUserDefaults standardUserDefaults] setObject:newOwned forKey:kMacLCSoundModeOwnedFiltersKey];

        const BOOL equalizerRunning =
            [[currentFilters componentsSeparatedByString:@":"] containsObject:@"equalizer"];
        if (![newFilters isEqualToString:currentFilters] || (hadLegacyBands && equalizerRunning)) {
            var_Create(p_aout, "audio-filter", VLC_VAR_STRING | VLC_VAR_DOINHERIT);
            var_SetString(p_aout, "audio-filter", [newFilters UTF8String]);
        }
    } else {
        // Sound mode is OFF: remove owned filters
        char *psz_filters = var_GetString(p_aout, "audio-filter");
        NSString *currentFilters = psz_filters ? [NSString stringWithUTF8String:psz_filters] : @"";
        free(psz_filters);

        NSArray<NSString *> *owned = [[NSUserDefaults standardUserDefaults] arrayForKey:kMacLCSoundModeOwnedFiltersKey];
        NSString *newFilters = [MacLCSoundPresets filterStringForDisablingCurrentFilterString:currentFilters
                                                                                 ownedFilters:owned];
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:kMacLCSoundModeOwnedFiltersKey];

        if (![newFilters isEqualToString:currentFilters]) {
            var_Create(p_aout, "audio-filter", VLC_VAR_STRING | VLC_VAR_DOINHERIT);
            var_SetString(p_aout, "audio-filter", [newFilters UTF8String]);
        }
    }

    aout_Release(p_aout);
}

#pragma mark - Menu Population

- (void)populateMenu:(NSMenu *)menu
{
    [menu removeAllItems];

    NSMenuItem *offItem = [[NSMenuItem alloc] initWithTitle:_NS("Off")
                                                     action:@selector(selectMenuOff:)
                                              keyEquivalent:@""];
    offItem.target = self;
    offItem.state = !self.isEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    [menu addItem:offItem];

    [menu addItem:[NSMenuItem separatorItem]];

    for (MacLCSoundPreset *preset in self.presets) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:preset.title
                                                      action:@selector(selectMenuPreset:)
                                               keyEquivalent:@""];
        item.target = self;
        item.representedObject = preset.identifier;
        if (@available(macOS 11.0, *)) {
            item.image = [NSImage imageWithSystemSymbolName:preset.symbolName
                                   accessibilityDescription:nil];
        }
        item.state = (self.isEnabled && [self.presetIdentifier isEqualToString:preset.identifier]) ?
                     NSControlStateValueOn : NSControlStateValueOff;
        [menu addItem:item];
    }
}

- (void)selectMenuOff:(id)sender
{
    self.enabled = NO;
}

- (void)selectMenuPreset:(NSMenuItem *)sender
{
    NSString *presetId = sender.representedObject;
    if (presetId.length > 0) {
        self.presetIdentifier = presetId;
        self.enabled = YES;
    }
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem
{
    if (menuItem.action == @selector(selectMenuOff:)) {
        menuItem.state = !self.isEnabled ? NSControlStateValueOn : NSControlStateValueOff;
        return YES;
    }
    if (menuItem.action == @selector(selectMenuPreset:)) {
        NSString *presetId = menuItem.representedObject;
        menuItem.state = (self.isEnabled && [self.presetIdentifier isEqualToString:presetId]) ?
                         NSControlStateValueOn : NSControlStateValueOff;
        return YES;
    }
    return YES;
}

@end
