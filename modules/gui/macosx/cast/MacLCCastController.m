/*****************************************************************************
 * MacLCCastController.m: Play on TV (Chromecast & AirPlay) controller
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

#import "MacLCCastController.h"

#import "cast/MacLCNetworkAddress.h"
#import "extensions/NSString+Helpers.h"
#import "main/VLCMain.h"
#import "menus/renderers/VLCRendererDiscovery.h"
#import "menus/renderers/VLCRendererItem.h"
#import "playqueue/VLCPlayQueueController.h"
#import "playqueue/VLCPlayerController.h"
#import "theme/MacLCDesign.h"

#include <vlc_common.h>
#include <vlc_renderer_discovery.h>
#include <vlc_variables.h>
#include <vlc_objects.h>

NSString * const MacLCCastStateDidChangeNotification = @"MacLCCastStateDidChangeNotification";

static void * const kAirPlayKVOContext = (void *)&kAirPlayKVOContext;

#pragma mark - Custom Cast Button

@interface MacLCCastButton : NSButton
@end

@implementation MacLCCastButton

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        self.bordered = NO;
        self.buttonType = NSButtonTypeMomentaryChange;
        self.imagePosition = NSImageOnly;
        self.imageScaling = NSImageScaleProportionallyDown;
        self.toolTip = _NS("Play On");
        [self setAccessibilityLabel:_NS("Play On")];
        self.target = self;
        self.action = @selector(castButtonClicked:);

        [NSNotificationCenter.defaultCenter addObserver:self
                                               selector:@selector(castStateChanged:)
                                                   name:MacLCCastStateDidChangeNotification
                                                 object:nil];
        [self updateButtonAppearance];
    }
    return self;
}

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)castStateChanged:(NSNotification *)note
{
    [self updateButtonAppearance];
}

- (void)updateButtonAppearance
{
    MacLCCastController * const controller = MacLCCastController.sharedController;
    const BOOL isCasting = controller.isCasting;
    const BOOL hasDevices = controller.hasCastDevices;

    self.hidden = (!hasDevices && !isCasting);

    NSString * const symbolName = isCasting ? @"tv.badge.wifi.fill" : @"tv.badge.wifi";
    NSImage *symbolImage = [MacLCDesign symbolNamed:symbolName accessibilityLabel:_NS("Play On")];
    if (!symbolImage) {
        symbolImage = [NSImage imageWithSystemSymbolName:symbolName accessibilityDescription:_NS("Play On")];
    }
    self.image = symbolImage;
    self.contentTintColor = isCasting ? MacLCDesign.accent : nil;
}

- (void)castButtonClicked:(id)sender
{
    NSMenu *menu = [[NSMenu alloc] initWithTitle:_NS("Play On")];
    [MacLCCastController.sharedController populateCastMenu:menu];
    const NSPoint location = self.isFlipped ? NSMakePoint(0, NSMaxY(self.bounds)) : NSMakePoint(0, NSMinY(self.bounds));
    [menu popUpMenuPositioningItem:nil atLocation:location inView:self];
}

- (NSSize)intrinsicContentSize
{
    return NSMakeSize(24.0, 24.0);
}

@end

#pragma mark - MacLCCastController Implementation

@interface MacLCCastController () <AVRoutePickerViewDelegate, VLCRendererDiscoveryDelegate>
{
    BOOL _started;
    BOOL _casting;
    BOOL _destinationIsAirPlay;
    NSString *_destinationName;

    NSMutableArray<VLCRendererDiscovery *> *_rendererDiscoveries;
    NSMutableArray<VLCRendererItem *> *_discoveredItems;
    NSArray<VLCRendererItem *> *_rendererItems;

    AVRouteDetector *_routeDetector;
    NSTimer *_probeRemovalTimer;
    NSTimer *_airplayDisconnectTimer;
    id<NSObject> _itemDidPlayToEndObserver;
    BOOL _debugWithoutRoute; /* MACLC_DEBUG_AIRPLAY_RENDERER: no receiver to lose */
}

- (void)setupAirPlayPlayer;
- (void)setupRouteDetector;
- (void)startRendererDiscoveries;
- (void)setupPlayerObservers;
- (void)handleExternalPlaybackChange;
- (void)cleanUpProbeItem;
- (void)updateSortedRendererItems;

@end

@implementation MacLCCastController

+ (MacLCCastController *)sharedController
{
    static MacLCCastController *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[MacLCCastController alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init
{
    NSAssert(NSThread.isMainThread, @"MacLCCastController must be initialized on the main thread");
    self = [super init];
    if (self) {
        _rendererDiscoveries = [NSMutableArray array];
        _discoveredItems = [NSMutableArray array];
        _rendererItems = @[];
    }
    return self;
}

- (void)dealloc
{
    [_airplayDisconnectTimer invalidate];
    [_probeRemovalTimer invalidate];

    if (_itemDidPlayToEndObserver) {
        [NSNotificationCenter.defaultCenter removeObserver:_itemDidPlayToEndObserver];
    }

    if (_airPlayPlayer) {
        [_airPlayPlayer removeObserver:self forKeyPath:@"externalPlaybackActive" context:kAirPlayKVOContext];
        [_airPlayPlayer removeObserver:self forKeyPath:@"currentItem" context:kAirPlayKVOContext];
    }

    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)start
{
    NSAssert(NSThread.isMainThread, @"MacLCCastController must be started on the main thread");
    if (_started) {
        return;
    }
    _started = YES;

    [self setupAirPlayPlayer];
    [self setupRouteDetector];
    [self startRendererDiscoveries];
    [self setupPlayerObservers];

    /* Developer hook: MACLC_DEBUG_AIRPLAY_RENDERER=<seconds> switches to the
     * AirPlay renderer that long after launch, without any receiver: the
     * shared player then plays the stream on this Mac, which exercises the
     * whole renderer path (cc_demux, HLS, time, pause, seek) headlessly. */
    const char * const debugAirPlay = getenv("MACLC_DEBUG_AIRPLAY_RENDERER");
    if (debugAirPlay != NULL) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(atof(debugAirPlay) * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            self->_debugWithoutRoute = YES;
            [self activateAirPlayRenderer];
        });
    }
}

#pragma mark - AirPlay Initialization & Glue

- (void)setupAirPlayPlayer
{
    _airPlayPlayer = [[AVPlayer alloc] init];
    _airPlayPlayer.allowsExternalPlayback = YES;

    intf_thread_t * const p_intf = getIntf();
    if (p_intf != NULL) {
        libvlc_int_t * const p_instance = vlc_object_instance(p_intf);
        if (p_instance != NULL) {
            var_Create(p_instance, "maclc-airplay-player", VLC_VAR_ADDRESS);
            var_SetAddress(p_instance, "maclc-airplay-player", (__bridge void *)_airPlayPlayer);
        }
    }

    [_airPlayPlayer addObserver:self
                     forKeyPath:@"externalPlaybackActive"
                        options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld
                        context:kAirPlayKVOContext];
    [_airPlayPlayer addObserver:self
                     forKeyPath:@"currentItem"
                        options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld
                        context:kAirPlayKVOContext];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(applicationWillTerminate:)
                                               name:NSApplicationWillTerminateNotification
                                             object:nil];
}

- (void)applicationWillTerminate:(NSNotification *)note
{
    intf_thread_t * const p_intf = getIntf();
    if (p_intf != NULL) {
        libvlc_int_t * const p_instance = vlc_object_instance(p_intf);
        if (p_instance != NULL) {
            var_SetAddress(p_instance, "maclc-airplay-player", NULL);
            var_Destroy(p_instance, "maclc-airplay-player");
        }
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey,id> *)change
                       context:(void *)context
{
    if (context == kAirPlayKVOContext) {
        /* AVFoundation does not promise which thread reports these changes. */
        if (!NSThread.isMainThread) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self handleExternalPlaybackChange];
            });
            return;
        }
        [self handleExternalPlaybackChange];
        return;
    }
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

- (void)handleExternalPlaybackChange
{
    const BOOL isExternalActive = _airPlayPlayer.isExternalPlaybackActive;

    if (isExternalActive) {
        [_probeRemovalTimer invalidate];
        _probeRemovalTimer = nil;

        [_airplayDisconnectTimer invalidate];
        _airplayDisconnectTimer = nil;

        if (!_destinationIsAirPlay) {
            [self activateAirPlayRenderer];
        }
    } else {
        if (_destinationIsAirPlay && !_debugWithoutRoute) {
            if (!_airplayDisconnectTimer) {
                __weak typeof(self) weakSelf = self;
                _airplayDisconnectTimer = [NSTimer scheduledTimerWithTimeInterval:4.0
                                                                          repeats:NO
                                                                            block:^(NSTimer * _Nonnull timer) {
                    __strong typeof(weakSelf) strongSelf = weakSelf;
                    if (!strongSelf) return;
                    strongSelf->_airplayDisconnectTimer = nil;
                    if (strongSelf->_destinationIsAirPlay && !strongSelf->_airPlayPlayer.isExternalPlaybackActive) {
                        VLCPlayerController * const pc = VLCMain.sharedInstance.playQueueController.playerController;
                        [pc setRendererItem:NULL];
                        [strongSelf->_airPlayPlayer replaceCurrentItemWithPlayerItem:nil];
                        strongSelf->_destinationIsAirPlay = NO;
                        strongSelf->_destinationName = nil;
                        strongSelf->_casting = NO;
                        [NSNotificationCenter.defaultCenter postNotificationName:MacLCCastStateDidChangeNotification
                                                                          object:strongSelf];
                    }
                }];
            }
        }
    }
}

/* Sends playback to the AirPlay stream output; the route itself is whatever
 * the user picked for the shared player. */
- (void)activateAirPlayRenderer
{
    _airPlayPlayer.muted = NO;

    NSString *lanIP = [MacLCNetworkAddress primaryIPv4Address];
    if (!lanIP || lanIP.length == 0) {
        lanIP = @"0.0.0.0";
    }
    NSString * const uriStr = [NSString stringWithFormat:@"airplay://%@:8011", lanIP];
    NSString * const nameStr = _NS("AirPlay");

    vlc_renderer_item_t * const item = vlc_renderer_item_new(
        "airplay",
        nameStr.UTF8String,
        uriStr.UTF8String,
        NULL,
        "cc_demux",
        NULL,
        VLC_RENDERER_CAN_VIDEO | VLC_RENDERER_CAN_AUDIO
    );

    if (item != NULL) {
        VLCPlayerController * const pc = VLCMain.sharedInstance.playQueueController.playerController;
        [pc setRendererItem:item];
        vlc_renderer_item_release(item);
    }

    _destinationIsAirPlay = YES;
    _destinationName = nameStr;
    _casting = YES;

    [NSNotificationCenter.defaultCenter postNotificationName:MacLCCastStateDidChangeNotification
                                                      object:self];
}

- (void)cleanUpProbeItem
{
    if (_itemDidPlayToEndObserver) {
        [NSNotificationCenter.defaultCenter removeObserver:_itemDidPlayToEndObserver];
        _itemDidPlayToEndObserver = nil;
    }
    [_airPlayPlayer replaceCurrentItemWithPlayerItem:nil];
}

#pragma mark - AVRoutePickerViewDelegate

- (void)routePickerViewWillBeginPresentingRoutes:(AVRoutePickerView *)routePickerView
{
    if (_destinationIsAirPlay || _airPlayPlayer.isExternalPlaybackActive) {
        return;
    }

    [_probeRemovalTimer invalidate];
    _probeRemovalTimer = nil;

    NSURL *probeURL = [[NSBundle bundleForClass:self.class] URLForResource:@"airplay-probe" withExtension:@"mp4"];
    if (!probeURL) {
        probeURL = [[NSBundle mainBundle] URLForResource:@"airplay-probe" withExtension:@"mp4"];
    }
    if (!probeURL) {
        return;
    }

    AVPlayerItem * const probeItem = [AVPlayerItem playerItemWithURL:probeURL];
    _airPlayPlayer.actionAtItemEnd = AVPlayerActionAtItemEndNone;
    _airPlayPlayer.muted = YES;
    [_airPlayPlayer replaceCurrentItemWithPlayerItem:probeItem];

    if (_itemDidPlayToEndObserver) {
        [NSNotificationCenter.defaultCenter removeObserver:_itemDidPlayToEndObserver];
        _itemDidPlayToEndObserver = nil;
    }

    __weak typeof(self) weakSelf = self;
    _itemDidPlayToEndObserver = [NSNotificationCenter.defaultCenter
        addObserverForName:AVPlayerItemDidPlayToEndTimeNotification
                    object:probeItem
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification * _Nonnull note) {
                    __strong typeof(weakSelf) strongSelf = weakSelf;
                    if (strongSelf) {
                        [strongSelf->_airPlayPlayer seekToTime:kCMTimeZero];
                    }
                }];

    [_airPlayPlayer play];
}

- (void)routePickerViewDidEndPresentingRoutes:(AVRoutePickerView *)routePickerView
{
    if (_destinationIsAirPlay || _airPlayPlayer.isExternalPlaybackActive) {
        return;
    }

    [_probeRemovalTimer invalidate];
    __weak typeof(self) weakSelf = self;
    _probeRemovalTimer = [NSTimer scheduledTimerWithTimeInterval:3.0
                                                         repeats:NO
                                                           block:^(NSTimer * _Nonnull timer) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf->_probeRemovalTimer = nil;
        if (!strongSelf->_destinationIsAirPlay && !strongSelf->_airPlayPlayer.isExternalPlaybackActive) {
            [strongSelf cleanUpProbeItem];
        }
    }];
}

#pragma mark - Route Detection

- (void)setupRouteDetector
{
    _routeDetector = [[AVRouteDetector alloc] init];
    _routeDetector.routeDetectionEnabled = NO;

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(routeDetectorDidChange:)
                                               name:AVRouteDetectorMultipleRoutesDetectedDidChangeNotification
                                             object:_routeDetector];
}

- (void)routeDetectorDidChange:(NSNotification *)note
{
    [NSNotificationCenter.defaultCenter postNotificationName:MacLCCastStateDidChangeNotification
                                                      object:self];
}

- (BOOL)hasAirPlayRoutes
{
    return _routeDetector.multipleRoutesDetected;
}

#pragma mark - Player Observers

- (void)setupPlayerObservers
{
    NSNotificationCenter * const nc = NSNotificationCenter.defaultCenter;
    [nc addObserver:self
           selector:@selector(playerCurrentMediaItemChanged:)
               name:VLCPlayerCurrentMediaItemChanged
             object:nil];
    [nc addObserver:self
           selector:@selector(playerRendererChanged:)
               name:VLCPlayerRendererChanged
             object:nil];
}

- (void)playerCurrentMediaItemChanged:(NSNotification *)note
{
    VLCPlayerController * const pc = VLCMain.sharedInstance.playQueueController.playerController;
    const BOOL hasMedia = (pc.currentMedia != nil);
    if (_routeDetector.isRouteDetectionEnabled != hasMedia) {
        _routeDetector.routeDetectionEnabled = hasMedia;
    }
}

- (void)playerRendererChanged:(NSNotification *)note
{
    VLCPlayerController * const pc = VLCMain.sharedInstance.playQueueController.playerController;
    vlc_renderer_item_t * const renderer = pc.rendererItem;

    if (renderer == NULL) {
        if (_destinationIsAirPlay) {
            [_airplayDisconnectTimer invalidate];
            _airplayDisconnectTimer = nil;
            [self cleanUpProbeItem];
        }
        _destinationIsAirPlay = NO;
        _destinationName = nil;
        _casting = NO;
    } else {
        const char * const type = vlc_renderer_item_type(renderer);
        const char * const name = vlc_renderer_item_name(renderer);
        NSString * const nameStr = toNSStr(name);

        if (type != NULL && strcmp(type, "airplay") == 0) {
            _destinationIsAirPlay = YES;
            _destinationName = (nameStr.length > 0) ? nameStr : _NS("AirPlay");
            _casting = YES;
        } else {
            if (_destinationIsAirPlay) {
                [_airplayDisconnectTimer invalidate];
                _airplayDisconnectTimer = nil;
                [self cleanUpProbeItem];
            }
            _destinationIsAirPlay = NO;
            _destinationName = nameStr;
            _casting = YES;
        }
    }

    [NSNotificationCenter.defaultCenter postNotificationName:MacLCCastStateDidChangeNotification
                                                      object:self];
}

#pragma mark - Renderer Discovery

- (void)startRendererDiscoveries
{
    intf_thread_t * const p_intf = getIntf();
    if (!p_intf) {
        return;
    }

    char **ppsz_longnames = NULL;
    char **ppsz_names = NULL;

    if (vlc_rd_get_names(VLC_OBJECT(p_intf), &ppsz_names, &ppsz_longnames) != VLC_SUCCESS) {
        return;
    }

    char **ppsz_name = ppsz_names;
    char **ppsz_longname = ppsz_longnames;

    for (; *ppsz_name; ppsz_name++, ppsz_longname++) {
        VLCRendererDiscovery * const dc =
            [[VLCRendererDiscovery alloc] initWithName:*ppsz_name andLongname:*ppsz_longname];
        dc.delegate = self;
        [_rendererDiscoveries addObject:dc];
        [dc startDiscovery];

        free(*ppsz_name);
        free(*ppsz_longname);
    }
    free(ppsz_names);
    free(ppsz_longnames);
}

- (void)addedRendererItem:(VLCRendererItem *)item from:(VLCRendererDiscovery *)sender
{
    NSAssert(NSThread.isMainThread, @"addedRendererItem must be handled on main thread");
    if (![_discoveredItems containsObject:item]) {
        [_discoveredItems addObject:item];
        [self updateSortedRendererItems];
        [NSNotificationCenter.defaultCenter postNotificationName:MacLCCastStateDidChangeNotification
                                                          object:self];
    }
}

- (void)removedRendererItem:(VLCRendererItem *)item from:(VLCRendererDiscovery *)sender
{
    NSAssert(NSThread.isMainThread, @"removedRendererItem must be handled on main thread");
    if ([_discoveredItems containsObject:item]) {
        [_discoveredItems removeObject:item];
        [self updateSortedRendererItems];
        [NSNotificationCenter.defaultCenter postNotificationName:MacLCCastStateDidChangeNotification
                                                          object:self];
    }
}

- (void)updateSortedRendererItems
{
    _rendererItems = [_discoveredItems sortedArrayUsingComparator:^NSComparisonResult(VLCRendererItem *a, VLCRendererItem *b) {
        return [a.name localizedStandardCompare:b.name];
    }];
}

#pragma mark - Properties & Control Methods

- (BOOL)hasCastDevices
{
    return _rendererItems.count > 0;
}

- (BOOL)isCasting
{
    return _casting;
}

- (NSString *)destinationName
{
    return _destinationName;
}

- (BOOL)destinationIsAirPlay
{
    return _destinationIsAirPlay;
}

- (void)playOnRendererItem:(nullable VLCRendererItem *)item
{
    NSAssert(NSThread.isMainThread, @"playOnRendererItem must be called on main thread");
    VLCPlayerController * const pc = VLCMain.sharedInstance.playQueueController.playerController;

    if (_destinationIsAirPlay) {
        [_airplayDisconnectTimer invalidate];
        _airplayDisconnectTimer = nil;
        [self cleanUpProbeItem];
        _destinationIsAirPlay = NO;
        _destinationName = nil;
        _casting = NO;
    }

    if (item != nil) {
        [item setRendererForPlayerController:pc];
    } else {
        [pc setRendererItem:NULL];
    }
}

- (void)populateCastMenu:(NSMenu *)menu
{
    NSAssert(NSThread.isMainThread, @"populateCastMenu must be called on main thread");
    [menu removeAllItems];

    VLCPlayerController * const pc = VLCMain.sharedInstance.playQueueController.playerController;
    vlc_renderer_item_t * const currentRenderer = pc.rendererItem;

    NSMenuItem * const thisMacItem = [[NSMenuItem alloc] initWithTitle:_NS("This Mac")
                                                                action:@selector(castMenuItemSelected:)
                                                         keyEquivalent:@""];
    thisMacItem.target = self;
    thisMacItem.representedObject = nil;
    NSImage * const macIcon = [MacLCDesign symbolNamed:@"laptopcomputer" accessibilityLabel:_NS("This Mac")];
    if (macIcon) {
        thisMacItem.image = macIcon;
    }
    thisMacItem.state = (!self.isCasting) ? NSControlStateValueOn : NSControlStateValueOff;
    [menu addItem:thisMacItem];

    for (VLCRendererItem *item in self.rendererItems) {
        NSMenuItem * const deviceItem = [[NSMenuItem alloc] initWithTitle:item.name
                                                                   action:@selector(castMenuItemSelected:)
                                                            keyEquivalent:@""];
        deviceItem.target = self;
        deviceItem.representedObject = item;
        NSString * const symbolName = (item.capabilityFlags & VLC_RENDERER_CAN_VIDEO) ? @"tv" : @"hifispeaker";
        NSImage * const icon = [MacLCDesign symbolNamed:symbolName accessibilityLabel:item.name];
        if (icon) {
            deviceItem.image = icon;
        }
        if (currentRenderer != NULL && item.rendererItem == currentRenderer) {
            deviceItem.state = NSControlStateValueOn;
        } else {
            deviceItem.state = NSControlStateValueOff;
        }
        [menu addItem:deviceItem];
    }
}

- (void)castMenuItemSelected:(NSMenuItem *)sender
{
    VLCRendererItem * const item = sender.representedObject;
    [self playOnRendererItem:item];
}

- (NSButton *)makeCastButton
{
    return [[MacLCCastButton alloc] initWithFrame:NSMakeRect(0, 0, 24, 24)];
}

- (NSView *)makeAirPlayButtonWithTint:(NSColor *)tint
{
    AVRoutePickerView * const picker = [[AVRoutePickerView alloc] initWithFrame:NSMakeRect(0, 0, 24, 24)];
    picker.player = _airPlayPlayer;
    picker.delegate = self;
    picker.routePickerButtonBordered = NO;
    [picker setRoutePickerButtonColor:tint forState:AVRoutePickerViewButtonStateNormal];
    [picker setRoutePickerButtonColor:NSColor.controlAccentColor forState:AVRoutePickerViewButtonStateActive];
    return picker;
}

@end
