/*****************************************************************************
 * VLCMain.m: MacOS X interface module
 *****************************************************************************
 * Copyright (C) 2002-2020 VLC authors and VideoLAN
 *
 * Authors: Derk-Jan Hartman <hartman at videolan.org>
 *          Felix Paul Kühne <fkuehne at videolan dot org>
 *          Pierre d'Herbemont <pdherbemont # videolan org>
 *          David Fuhrmann <david dot fuhrmann at googlemail dot com>
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

/*****************************************************************************
 * Preamble
 *****************************************************************************/
#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#import "main/VLCMain.h"

#include <stdlib.h>                                      /* malloc(), free() */
#include <string.h>
#include <stdatomic.h>
#include <sys/sysctl.h>

#include <vlc_common.h>
#include <vlc_actions.h>
#include <vlc_dialog.h>
#include <vlc_url.h>
#include <vlc_variables.h>
#include <vlc_preparser.h>

#include <Metal/Metal.h>

#import "extensions/NSString+Helpers.h"

#import "library/VLCLibraryController.h"
#import "library/VLCLibraryWindow.h"
#import "webvideo/MacLCWebVideoPanelController.h"
#import "addons/MacLCAddons.h"
#import "addons/MacLCAddonSearchWindowController.h"
#import "addons/watch/MacLCWatchSections.h"
#import "library/VLCLibraryWindowController.h"
#import "library/VLCLibraryWindowNavigationSidebarViewController.h"
#import "medialib/shell/MacLCLibrarySidebarViewController.h"
#import "library/VLCLibraryWindowSplitViewController.h"

#import "library/VLCLibrarySegment.h"

#import "medialib/data/MacLCLibraryActions.h"
#import "medialib/data/MacLCLibraryStore.h"
#import "medialib/sections/MacLCLibrarySectionViewController.h"
#import "medialib/shell/MacLCLibraryRouter.h"

#import "main/CompatibilityFixes.h"
#import "main/VLCMain+OldPrefs.h"
#import "main/VLCApplication.h"

#import "menus/VLCMainMenu.h"
#import "hdr/MacLCHDRController.h"
#import "cast/MacLCCastController.h"
#import "sound/MacLCSoundMode.h"
#import "sound/MacLCSoundPanelViewController.h"
#import "coreinteraction/MacLCOSDController.h"
#import "hdr/MacLCHDRMenuController.h"
#import "hdr/MacLCHDRPanelViewController.h"
#import "hdr/MacLCSDRToHDRPanelViewController.h"
#import "menus/VLCStatusBarIcon.h"

#import "os-integration/VLCClickerManager.h"

#import "panels/dialogs/VLCCoreDialogProvider.h"
#import "panels/VLCAudioEffectsWindowController.h"
#import "panels/VLCBookmarksWindowController.h"
#import "panels/VLCVideoEffectsWindowController.h"
#import "panels/VLCTrackSynchronizationWindowController.h"

#import "playqueue/VLCPlayQueueController.h"
#import "playqueue/VLCPlayerController.h"
#import "playqueue/VLCPlayQueueModel.h"
#import "playqueue/VLCPlayQueueTableCellView.h"
#import "playqueue/VLCPlaybackContinuityController.h"

#import "preferences/prefs.h"
#import "preferences/VLCSimplePrefsController.h"
#import "settings/MacLCSettingsWindowController.h"
#import "settings/MacLCSettingsSelfTest.h"

#import "views/VLCPlaybackEndViewController.h"

#import "windows/VLCDetachedAudioWindow.h"
#import "windows/VLCOpenWindowController.h"
#import "windows/VLCOpenInputMetadata.h"
#import "windows/convertandsave/VLCConvertAndSaveWindowController.h"
#import "windows/extensions/VLCExtensionsManager.h"
#import "windows/logging/VLCLogWindowController.h"
#import "windows/video/VLCVoutView.h"
#import "windows/video/VLCVideoOutputProvider.h"
#import "windows/video/VLCMainVideoViewController.h"

#ifdef HAVE_SPARKLE
#import "main/VLCMain+Sparkle.h"
#endif

NSString *VLCConfigurationChangedNotification = @"VLCConfigurationChangedNotification";

NSString * const kVLCPreferencesVersion = @"VLCPreferencesVersion";

#pragma mark -
#pragma mark Private extension

@interface VLCMain ()
<NSApplicationDelegate>
{
    intf_thread_t *_p_intf;
    BOOL _launched;

    VLCMainMenu *_mainmenu;
    VLCPrefs *_prefs;
    VLCSimplePrefsController *_sprefs;
    MacLCSettingsWindowController *_settingsWindowController;
    VLCOpenWindowController *_open;
    VLCCoreDialogProvider *_coredialogs;
    VLCBookmarksWindowController *_bookmarks;
    VLCPlaybackContinuityController *_continuityController;
    VLCLogWindowController *_messagePanelController;
    VLCStatusBarIcon *_statusBarIcon;
    VLCTrackSynchronizationWindowController *_trackSyncPanel;
    VLCAudioEffectsWindowController *_audioEffectsPanel;
    VLCVideoEffectsWindowController *_videoEffectsPanel;
    VLCConvertAndSaveWindowController *_convertAndSaveWindow;
    VLCClickerManager *_clickerManager;
    VLCDetachedAudioWindow *_detachedAudioWindow;
#ifdef HAVE_SPARKLE
    SPUStandardUpdaterController *_sparkleUpdaterController;
#endif

    bool _interfaceIsTerminating; /* Makes sure applicationWillTerminate will be called only once */
}
+ (void)killInstance;
- (void)applicationWillTerminate:(NSNotification *)notification;
#ifdef HAVE_SPARKLE
@property (readwrite) SPUStandardUpdaterController *sparkleUpdaterController;
#endif

@end

#pragma mark -
#pragma mark VLC Interface Object Callbacks

/*****************************************************************************
 * OpenIntf: initialize interface
 *****************************************************************************/

static intf_thread_t *p_interface_thread;
static vlc_preparser_t *p_network_preparser;
static vlc_preparser_t *p_thumbnailer;
vlc_sem_t g_wait_quit;

intf_thread_t *getIntf()
{
    return p_interface_thread;
}

vlc_preparser_t *getNetworkPreparser()
{
    return p_network_preparser;
}

vlc_preparser_t *getThumbnailer()
{
    return p_thumbnailer;
}

int OpenIntf (vlc_object_t *p_this)
{
    __block int retcode = VLC_SUCCESS;
    __block dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    CFRunLoopPerformBlock(CFRunLoopGetMain(), kCFRunLoopDefaultMode, ^{
        @autoreleasepool {
            intf_thread_t *p_intf = (intf_thread_t*) p_this;
            p_interface_thread = p_intf;

            const struct vlc_preparser_cfg cfg = {
                .types = VLC_PREPARSER_TYPE_PARSE,
                .max_parser_threads = 1,
                .timeout = 0,
                .external_process = false,
            };
            p_network_preparser = vlc_preparser_New(p_this, &cfg);
            if (p_network_preparser == nil)
            {
                retcode = VLC_ENOMEM;
                dispatch_semaphore_signal(sem);
                return;
            }

            const struct vlc_preparser_cfg thumbnailer_cfg = {
                .types = VLC_PREPARSER_TYPE_THUMBNAIL_TO_FILES,
                .max_thumbnailer_threads = 1,
                .timeout = VLC_TICK_FROM_SEC(3),
                .external_process = false,
            };
            p_thumbnailer = vlc_preparser_New(p_this, &thumbnailer_cfg);
            if (p_thumbnailer == NULL) {
                msg_Warn(p_intf, "Could not initialize the thumbnailer");
            }
            msg_Dbg(p_intf, "Starting macosx interface");

            @try {
                VLCApplication * const application = VLCApplication.sharedApplication;
                NSCAssert(application != nil, @"VLCApplication must not be nil");
                [application setIntf:p_intf];

                VLCMain * const main = VLCMain.sharedInstance;
                NSCAssert(main != nil, @"VLCMain must not be nil");

                msg_Dbg(p_intf, "Finished loading macosx interface");
            } @catch (NSException *exception) {
                msg_Err(p_intf, "Loading the macosx interface failed. Do you have a valid window server?");
                retcode = VLC_EGENERIC;
                dispatch_semaphore_signal(sem);
                return;
            }
            dispatch_semaphore_signal(sem);
            [NSApp run];
        }
        vlc_sem_post(&g_wait_quit);
    });
    CFRunLoopWakeUp(CFRunLoopGetMain());

    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);

    return retcode;
}

/* -[NSApplication stop:] only takes effect once the event loop dequeues
 * something, and a session nobody is typing into may never produce another
 * event; a single nudge can also be swallowed by whatever else is pumping
 * events while the interface tears itself down. Both leave -run blocked
 * forever while CloseIntf waits for it below. Keep offering one until -run
 * has actually returned. */
enum { kMacLCStopAttempts = 500 };  /* ten seconds, far more than it takes */

static void MacLCStopApplication(int attempts)
{
    if (NSApp == nil || !NSApp.running || attempts <= 0)
        return;

    [NSApp stop:nil];
    [NSApp postEvent:[NSEvent otherEventWithType:NSEventTypeApplicationDefined
                                        location:NSZeroPoint
                                   modifierFlags:0
                                       timestamp:0.0
                                    windowNumber:0
                                         context:nil
                                         subtype:0
                                          data1:0
                                          data2:0]
             atStart:YES];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_MSEC),
                   dispatch_get_main_queue(), ^{
        MacLCStopApplication(attempts - 1);
    });
}

void CloseIntf (vlc_object_t *p_this)
{
    void (^release_intf)() = ^{
        @autoreleasepool {
            msg_Dbg(p_this, "Closing macosx interface");
            [VLCMain.sharedInstance applicationWillTerminate:nil];
            if (p_thumbnailer != NULL) {
                vlc_preparser_Cancel(p_thumbnailer, NULL);
                vlc_preparser_Delete(p_thumbnailer);
                p_thumbnailer = NULL;
            }
            [VLCMain killInstance];
        }
        /* The interface object is destroyed as soon as this callback returns.
         * Clear the global so that getIntf() reports the interface as gone
         * instead of handing out a dangling pointer to work that is still
         * queued on the main thread. */
        p_interface_thread = NULL;
        vlc_preparser_Delete(p_network_preparser);
        MacLCStopApplication(kMacLCStopAttempts);
    };
    if (CFRunLoopGetCurrent() == CFRunLoopGetMain())
        release_intf();
    else
        dispatch_sync(dispatch_get_main_queue(), release_intf);
    vlc_sem_wait(&g_wait_quit);
}

/*****************************************************************************
 * VLCMain implementation
 *****************************************************************************/
@implementation VLCMain

#pragma mark -
#pragma mark Initialization

static VLCMain *sharedInstance = nil;

+ (VLCMain *)sharedInstance
{
    static dispatch_once_t pred;
    dispatch_once(&pred, ^{
        sharedInstance = [[VLCMain alloc] init];
    });

    return sharedInstance;
}

+ (void)killInstance
{
    sharedInstance = nil;
}

+ (void)relaunchApplication
{
    const char *path = [[[NSBundle mainBundle] executablePath] UTF8String];

    /* For some reason we need to fork(), not just execl(), which reports a ENOTSUP then. */
    if (fork() != 0) {
        exit(0);
    }
    execl(path, path, (char *)NULL);
}

- (id)init
{
    self = [super init];
    if (self) {
        _p_intf = getIntf();

        VLCApplication.sharedApplication.delegate = self;

        _playQueueController = [[VLCPlayQueueController alloc] initWithPlaylist:vlc_intf_GetMainPlaylist(_p_intf)];
        _libraryController = [[VLCLibraryController alloc] init];
        _continuityController = [[VLCPlaybackContinuityController alloc] init];

        // first initialize extensions dialog provider, then core dialog
        // provider which will register both at the core
        _extensionsManager = [[VLCExtensionsManager alloc] init];
        _coredialogs = [[VLCCoreDialogProvider alloc] init];

        _mainmenu = [[VLCMainMenu alloc] init];
        _voutProvider = [[VLCVideoOutputProvider alloc] init];

        // Load them here already to apply stored profiles
        _videoEffectsPanel = [[VLCVideoEffectsWindowController alloc] init];
        _audioEffectsPanel = [[VLCAudioEffectsWindowController alloc] init];

        if ([NSApp currentSystemPresentationOptions] & NSApplicationPresentationFullScreen)
            [_playQueueController.playerController setFullscreen:YES];
    }

    return self;
}

- (void)applicationWillFinishLaunching:(NSNotification *)aNotification
{
    // Only Metal shader in use at the moment is for holiday theming, so only load during this time.
    // Change this if you are going to add new shaders!
    if (((VLCApplication *)NSApplication.sharedApplication).winterHolidaysTheming) {
        _metalDevice = MTLCreateSystemDefaultDevice();
        NSString * const libraryPath =
            [NSBundle.mainBundle pathForResource:@"Shaders" ofType:@"metallib"];
        if (libraryPath) {
            NSError *error = nil;
            _metalLibrary = [_metalDevice newLibraryWithFile:libraryPath error:&error];
            if (!_metalLibrary) {
                NSLog(@"Error creating Metal library: %@", error);
            }
        } else {
            NSLog(@"Error: Could not find Shaders.metallib in the bundle.");
        }
    }

    _clickerManager = [[VLCClickerManager alloc] init];

#ifdef HAVE_SPARKLE
    [self setupSparkle];
#endif

    [[NSBundle mainBundle] loadNibNamed:@"MainMenu" owner:_mainmenu topLevelObjects:nil];

    /* HDR: start following the player before the first file opens, and
     * give the Video menu its HDR submenu. */
    [MacLCHDRController sharedController];
    [MacLCOSDController sharedController];
    [[MacLCHDRMenuController sharedMenuController] installInVideoMenu:_mainmenu.videoMenu];

    NSImage *appIconImage = [VLCApplication.sharedApplication vlcAppIconImage];
    [VLCApplication.sharedApplication
        setApplicationIconImage:appIconImage];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    _launched = YES;

    if (_libraryWindowController == nil) {
        _libraryWindowController = [[VLCLibraryWindowController alloc] initWithLibraryWindow];
    }

    [_libraryWindowController.window makeKeyAndOrderFront:nil];

    /* Play on TV (Chromecast discovery, AirPlay route) and the Sound modes,
     * whose filters live on the player's audio output. */
    [MacLCCastController.sharedController start];
    [MacLCSoundMode.sharedMode applyToAudioOutput];

    /* Developer hook for headless UI checks: MACLC_DEBUG_OPEN_BROWSE=home opens
     * the Browse section at launch, MACLC_DEBUG_OPEN_BROWSE=file:///dir/ opens
     * that folder in it. Unset, it does nothing. */
    const char * const debugOpenBrowse = getenv("MACLC_DEBUG_OPEN_BROWSE");
    if (debugOpenBrowse != NULL) {
        NSString * const target = [NSString stringWithUTF8String:debugOpenBrowse];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            VLCLibraryWindow * const window = (VLCLibraryWindow *)self->_libraryWindowController.window;
            if ([target hasPrefix:@"file://"]) {
                [window browseFolderByMrl:target];
            } else {
                [window goToBrowseSection:window];
            }
        });
    }

    /* Developer hooks for headless library checks: MACLC_DEBUG_ML_FOLDER=/dir
     * adds that folder to the media library at launch, and
     * MACLC_DEBUG_LIBRARY_SECTION=<segment type number> selects that section
     * of the library window. Unset, they do nothing. */
    const char * const debugLibraryFolder = getenv("MACLC_DEBUG_ML_FOLDER");
    if (debugLibraryFolder != NULL && [NSString stringWithUTF8String:debugLibraryFolder] != nil) {
        NSURL * const folderURL =
            [NSURL fileURLWithPath:[NSString stringWithUTF8String:debugLibraryFolder] isDirectory:YES];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self.libraryController addFolderWithFileURL:folderURL];
        });
    }
    /* MACLC_DEBUG_ML_REMOVE_FOLDER=/dir takes a test folder back out of the
     * library (its media and thumbnails with it). */
    const char * const debugRemoveFolder = getenv("MACLC_DEBUG_ML_REMOVE_FOLDER");
    if (debugRemoveFolder != NULL && [NSString stringWithUTF8String:debugRemoveFolder] != nil) {
        NSURL * const folderURL =
            [NSURL fileURLWithPath:[NSString stringWithUTF8String:debugRemoveFolder] isDirectory:YES];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [MacLCLibraryStore.sharedStore removeFolderAtURL:folderURL];
        });
    }
    const char * const debugLibrarySection = getenv("MACLC_DEBUG_LIBRARY_SECTION");
    if (debugLibrarySection != NULL) {
        const NSInteger segmentType = atoi(debugLibrarySection);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            VLCLibraryWindow * const window = (VLCLibraryWindow *)self->_libraryWindowController.window;
            [window.splitViewController.navSidebarViewController selectSegment:segmentType];
        });
    }
    /* MACLC_DEBUG_WATCH=home|movies|shows selects that Watch section;
     * ":detail" then opens the first featured title's page, ":play" its page
     * and stream picker. */
    const char * const debugWatch = getenv("MACLC_DEBUG_WATCH");
    if (debugWatch != NULL) {
        NSArray<NSString *> * const parts = [@(debugWatch) componentsSeparatedByString:@":"];
        NSInteger segmentType = VLCLibraryWatchHomeSegmentType;
        if ([parts.firstObject isEqualToString:@"movies"])
            segmentType = VLCLibraryWatchMoviesSegmentType;
        else if ([parts.firstObject isEqualToString:@"shows"])
            segmentType = VLCLibraryWatchShowsSegmentType;
        NSString * const then = parts.count > 1 ? parts[1] : @"";
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            VLCLibraryWindow * const window = (VLCLibraryWindow *)self->_libraryWindowController.window;
            [window.splitViewController.navSidebarViewController selectSegment:segmentType];
            MacLCLibrarySectionViewController * const section =
                [MacLCLibraryRouter routerForLibraryWindow:window].currentSection;
            if (then.length > 0 && [section isKindOfClass:MacLCWatchSectionViewController.class])
                [(MacLCWatchSectionViewController *)section
                    debugOpenFirstFeaturedShowingStreams:[then isEqualToString:@"play"]];
        });
    }

    /* Developer hooks for headless screenshots:
     * MACLC_DEBUG_APPEARANCE=dark|light forces the appearance,
     * MACLC_DEBUG_WINDOW_SIZE=<width>x<height> resizes the library window and
     * MACLC_DEBUG_UP_NEXT=1 opens the Up Next inspector. Unset, they do
     * nothing. */
    const char * const debugAppearance = getenv("MACLC_DEBUG_APPEARANCE");
    if (debugAppearance != NULL) {
        NSApp.appearance = [NSAppearance appearanceNamed:strcmp(debugAppearance, "dark") == 0
                                                             ? NSAppearanceNameDarkAqua
                                                             : NSAppearanceNameAqua];
    }
    const char * const debugWindowSize = getenv("MACLC_DEBUG_WINDOW_SIZE");
    if (debugWindowSize != NULL) {
        int width = 0, height = 0;
        if (sscanf(debugWindowSize, "%dx%d", &width, &height) == 2 && width > 0 && height > 0) {
            /* After the window has restored its own frame. */
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                NSWindow * const window = self->_libraryWindowController.window;
                const NSRect visible = window.screen.visibleFrame;
                NSRect frame = NSMakeRect(NSMinX(visible), NSMaxY(visible) - height, width, height);
                [window setFrame:NSIntersectionRect(frame, visible) display:YES];
            });
        }
    }
    /* MACLC_DEBUG_FRONT=1 floats the library window over the current Stage
     * Manager stage without activating MacLC (no keyboard focus is taken), so
     * a background launch can still be captured at full size. */
    if (getenv("MACLC_DEBUG_FRONT") != NULL) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NSWindow * const window = self->_libraryWindowController.window;
            window.level = NSFloatingWindowLevel;
            [window orderFrontRegardless];
        });
    }
    /* MACLC_DEBUG_DUMP_LAYOUT=1 logs, 5 s after launch, the library window's
     * frame and size limits, its split view items and the menu bar as it is
     * drawn (hidden items left out, a trailing * marks items with an image),
     * prefixed with LAYOUTDUMP. */
    if (getenv("MACLC_DEBUG_DUMP_LAYOUT") != NULL) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            VLCLibraryWindow * const window = (VLCLibraryWindow *)self->_libraryWindowController.window;
            NSLog(@"LAYOUTDUMP frame %@ min %@ fitting %@", NSStringFromRect(window.frame),
                  NSStringFromSize(window.minSize), NSStringFromSize(window.contentView.fittingSize));
            for (NSSplitViewItem * const item in window.splitViewController.splitViewItems) {
                NSLog(@"LAYOUTDUMP item %@ collapsed %d frame %@", item.viewController.className,
                      item.isCollapsed, NSStringFromRect(item.viewController.view.frame));
            }
            for (NSMenuItem * const top in NSApp.mainMenu.itemArray) {
                NSMutableArray * const titles = [NSMutableArray array];
                for (NSMenuItem * const item in top.submenu.itemArray) {
                    /* Never drawn. AppKit adds hidden copies of Start
                     * Dictation… and Emoji & Symbols to the Edit menu only so
                     * that their other shortcuts (fn-D, ⌃⌘Space, fn-E) work. */
                    if (item.isHidden) {
                        continue;
                    }
                    [titles addObject:item.isSeparatorItem ? @"|" : [NSString stringWithFormat:@"%@%@", item.title,
                        item.image != nil ? @"*" : @""]];
                }
                NSLog(@"LAYOUTDUMP menu %@: %@", top.submenu.title, [titles componentsJoinedByString:@", "]);
            }
        });
    }
    /* MACLC_DEBUG_SNAPSHOT=<prefix> draws every visible MacLC window at least
     * 200 points wide into <prefix>-<window number>.png, 3 s after the panel
     * hook fires (or 9 s after launch). The app draws its own views, so it
     * works when the screen is locked or cannot be recorded; materials that
     * sample what lies behind a window (Liquid Glass) come out plain. */
    const char * const debugSnapshot = getenv("MACLC_DEBUG_SNAPSHOT");
    if (debugSnapshot != NULL) {
        const char * const panelDelay = getenv("MACLC_DEBUG_SHOW_PANEL_DELAY");
        const double delay = (panelDelay != NULL ? atof(panelDelay) : 6.0) + 3.0;
        NSString * const prefix = @(debugSnapshot);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            for (NSWindow * const window in NSApp.windows) {
                NSView * const view = window.contentView.superview ?: window.contentView;
                if (!window.isVisible || view == nil || NSWidth(view.bounds) < 200.0)
                    continue;
                NSBitmapImageRep * const rep = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
                [view cacheDisplayInRect:view.bounds toBitmapImageRep:rep];
                NSData * const png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
                NSString * const path = [NSString stringWithFormat:@"%@-%ld.png", prefix, (long)window.windowNumber];
                [png writeToFile:path atomically:YES];
                NSLog(@"SNAPSHOT %@ %@ %@", path, window.title, NSStringFromRect(window.frame));
            }
        });
    }
    /* MACLC_DEBUG_SHOW_PANEL=sound|sound-panel|sdr2hdr|hdr|settings-<pane>[+advanced][:y] opens, after
     * MACLC_DEBUG_SHOW_PANEL_DELAY seconds (6 by default), the SDR to HDR
     * popover, the HDR popover or the HDR & Colour settings pane, anchored to
     * the library window, so headless captures can see them. */
    const char * const debugPanel = getenv("MACLC_DEBUG_SHOW_PANEL");
    if (debugPanel != NULL) {
        const char * const debugPanelDelay = getenv("MACLC_DEBUG_SHOW_PANEL_DELAY");
        const double delay = debugPanelDelay != NULL ? atof(debugPanelDelay) : 6.0;
        NSString * const panel = @(debugPanel);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NSView * const anchor = self->_libraryWindowController.window.contentView;
            if (anchor == nil && ![panel hasPrefix:@"settings-"])
                return;
            if ([panel isEqualToString:@"sound"]) {
                [MacLCSoundPanelViewController showRelativeToView:anchor preferredEdge:NSRectEdgeMinY];
            } else if ([panel isEqualToString:@"sound-panel"]) {
                [MacLCSoundPanelViewController showPanel];
            } else if ([panel isEqualToString:@"sdr2hdr"]) {
                [MacLCSDRToHDRPanelViewController showRelativeToView:anchor preferredEdge:NSRectEdgeMinY];
            } else if ([panel isEqualToString:@"hdr"]) {
                [MacLCHDRPanelViewController showRelativeToView:anchor preferredEdge:NSRectEdgeMinY];
            } else if ([panel hasPrefix:@"settings-"]) {
                /* settings-<pane identifier>; settings-hdr is the HDR & Colour pane. */
                NSString *pane = [[panel substringFromIndex:9] componentsSeparatedByCharactersInSet:
                    [NSCharacterSet characterSetWithCharactersInString:@"+:"]].firstObject;
                if ([pane isEqualToString:@"hdr"])
                    pane = @"video-hdr";
                [self.settingsWindowController showSettingsWindowWithLevel:NSNormalWindowLevel];
                [self.settingsWindowController selectPaneWithIdentifier:pane];
                /* settings-hdr+advanced also opens Advanced Options. */
                if ([panel containsString:@"+advanced"]) {
                    NSMutableArray<NSView *> * const views =
                        [NSMutableArray arrayWithObject:self.settingsWindowController.window.contentView];
                    while (views.count > 0) {
                        NSView * const view = views.firstObject;
                        [views removeObjectAtIndex:0];
                        if ([view isKindOfClass:[NSButton class]]
                            && [((NSButton *)view).title isEqualToString:_NS("Advanced Options")]) {
                            [(NSButton *)view performClick:nil];
                            break;
                        }
                        [views addObjectsFromArray:view.subviews];
                    }
                }
                /* settings-hdr:<y> scrolls the pane down to <y> points. */
                const NSRange colon = [panel rangeOfString:@":"];
                if (colon.location != NSNotFound) {
                    const CGFloat y = [[panel substringFromIndex:colon.location + 1] doubleValue];
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        NSMutableArray<NSView *> * const queue =
                            [NSMutableArray arrayWithObject:self.settingsWindowController.window.contentView];
                        while (queue.count > 0) {
                            NSView * const view = queue.firstObject;
                            [queue removeObjectAtIndex:0];
                            if ([view isKindOfClass:[NSScrollView class]]
                                && NSHeight(((NSScrollView *)view).documentView.frame)
                                   > NSHeight(((NSScrollView *)view).contentView.bounds) + 1.0) {
                                NSScrollView * const scroll = (NSScrollView *)view;
                                [scroll.documentView scrollPoint:NSMakePoint(0, scroll.documentView.isFlipped
                                    ? y : NSHeight(scroll.documentView.frame) - y - NSHeight(scroll.contentView.bounds))];
                                break;
                            }
                            [queue addObjectsFromArray:view.subviews];
                        }
                    });
                }
            }
        });
    }
    /* MACLC_DEBUG_SHOW_FIRST=1 opens the detail of the first item of the
     * section chosen with MACLC_DEBUG_LIBRARY_SECTION (album, show, artist,
     * genre or playlist). */
    if (getenv("MACLC_DEBUG_SHOW_FIRST") != NULL) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            VLCLibraryWindow * const window = (VLCLibraryWindow *)self->_libraryWindowController.window;
            MacLCLibrarySectionViewController * const section =
                [MacLCLibraryRouter routerForLibraryWindow:window].currentSection;
            MacLCLibraryCollection collection;
            switch (window.librarySegmentType) {
                case VLCLibraryShowsVideoSubSegmentType: collection = MacLCLibraryCollectionShows; break;
                case VLCLibraryArtistsMusicSubSegmentType: collection = MacLCLibraryCollectionArtists; break;
                case VLCLibraryAlbumsMusicSubSegmentType: collection = MacLCLibraryCollectionAlbums; break;
                case VLCLibraryGenresMusicSubSegmentType: collection = MacLCLibraryCollectionGenres; break;
                case VLCLibraryPlaylistsSegmentType: collection = MacLCLibraryCollectionPlaylists; break;
                default: return;
            }
            id<VLCMediaLibraryItemProtocol> const item =
                [MacLCLibraryStore.sharedStore itemsInCollection:collection].firstObject;
            if (item != nil) {
                [section showItem:item];
            }
        });
    }
    /* MACLC_DEBUG_PLAY=album|video plays the first album or video of the
     * library through the library's own play action; MACLC_DEBUG_LEAVE_VIDEO=1
     * then goes back from the embedded video to the library. */
    const char * const debugPlay = getenv("MACLC_DEBUG_PLAY");
    if (debugPlay != NULL) {
        const BOOL video = strcmp(debugPlay, "video") == 0;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            id<VLCMediaLibraryItemProtocol> const item = [MacLCLibraryStore.sharedStore
                itemsInCollection:video ? MacLCLibraryCollectionVideos : MacLCLibraryCollectionAlbums].firstObject;
            if (item != nil) {
                [MacLCLibraryActions playItems:@[item] startingAt:0];
            }
        });
    }
    if (getenv("MACLC_DEBUG_LEAVE_VIDEO") != NULL) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            VLCLibraryWindow * const window = (VLCLibraryWindow *)self->_libraryWindowController.window;
            if (window.embeddedVideoPlaybackActive) {
                [window disableVideoPlaybackAppearance];
            }
        });
    }
    if (getenv("MACLC_DEBUG_UP_NEXT") != NULL) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            VLCLibraryWindow * const window = (VLCLibraryWindow *)self->_libraryWindowController.window;
            [window.splitViewController toggleMultifunctionSidebar:nil];
        });
    }

    /* Developer hook for headless UI checks: MACLC_DEBUG_OPEN_WEB_VIDEO opens
     * the web video panel at launch, pre-filled with the address it holds
     * (an empty value opens it empty, a "play:" prefix plays it as soon as it
     * resolves). Unset, it does nothing. */
    const char * const debugOpenWebVideo = getenv("MACLC_DEBUG_OPEN_WEB_VIDEO");
    if (debugOpenWebVideo != NULL) {
        NSString *address = [NSString stringWithUTF8String:debugOpenWebVideo];
        const BOOL playWhenResolved = [address hasPrefix:@"play:"];
        if (playWhenResolved) {
            address = [address substringFromIndex:5];
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [MacLCWebVideoPanelController.sharedController
                showPanelWithAddress:address.length > 0 ? address : nil
                    playWhenResolved:playWhenResolved];
        });
    }

    /* Developer hooks for headless checks: MACLC_DEBUG_ADDONS_INSTALL=<address>
     * installs that add-on at launch (several: separated by spaces), then
     * MACLC_DEBUG_ADDONS_SEARCH opens Search Add-ons on the query it holds
     * (prefix "play-movie:" or "play-series:" picks and plays the first
     * result, "select-movie:" or "select-series:" only picks it). Unset, they
     * do nothing. */
    const char * const debugAddonsInstall = getenv("MACLC_DEBUG_ADDONS_INSTALL");
    const char * const debugAddonsSearch = getenv("MACLC_DEBUG_ADDONS_SEARCH");
    if (debugAddonsInstall != NULL || debugAddonsSearch != NULL) {
        NSArray<NSString *> * const addresses = [@(debugAddonsInstall ?: "")
            componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        NSString * const search = debugAddonsSearch != NULL ? @(debugAddonsSearch) : nil;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            dispatch_group_t const installs = dispatch_group_create();
            for (NSString * const address in addresses) {
                if (address.length == 0)
                    continue;
                dispatch_group_enter(installs);
                [MacLCAddonStore.sharedStore installFromAddress:address
                                                     completion:^(MacLCAddon *addon, BOOL replaced, NSError *error) {
                    if (addon != nil)
                        msg_Dbg(getIntf(), "addons: debug hook installed \"%s\"", addon.name.UTF8String);
                    else
                        msg_Warn(getIntf(), "addons: debug hook could not install %s: %s",
                                 address.UTF8String, error.localizedDescription.UTF8String);
                    dispatch_group_leave(installs);
                }];
            }
            dispatch_group_notify(installs, dispatch_get_main_queue(), ^{
                if (search == nil)
                    return;
                NSString *query = search, *type = nil;
                for (NSString * const prefix in @[@"play-movie", @"play-series", @"select-movie", @"select-series"]) {
                    if ([query hasPrefix:[prefix stringByAppendingString:@":"]]) {
                        type = [prefix hasPrefix:@"play-"] ? [prefix substringFromIndex:5] : prefix;
                        query = [query substringFromIndex:prefix.length + 1];
                        break;
                    }
                }
                [MacLCAddonSearchWindowController.sharedController showWindowWithQuery:query autoplayType:type];
            });
        });
    }

    if (!_p_intf)
        return;

    [self migrateFromLegacyBundleIdentifier];

    NSUserDefaults * const defaults = NSUserDefaults.standardUserDefaults;
    if ([defaults integerForKey:kVLCPreferencesVersion] != 4) {
        [defaults setBool:YES forKey:VLCPlaybackEndViewEnabledKey];
        [defaults setBool:NO forKey:VLCDisplayTrackNumberPlayQueueKey];
        [defaults setBool:YES forKey:VLCUseClassicVideoPlayerLayoutKey];
        [self migrateOldPreferences];
    }

    _statusBarIcon = [[VLCStatusBarIcon alloc] init:_p_intf];

    /* on macOS 11 and later, check whether the user attempts to deploy
     * the x86_64 binary on ARM-64 - if yes, log it */
    if (OSX_BIGSUR_AND_HIGHER) {
        if ([self processIsTranslated] > 0) {
            msg_Warn(getIntf(), "Process is translated!");
        }
    }
    if (getenv("MACLC_SELFTEST") != NULL) {
        [MacLCSettingsSelfTest runWithIntf:getIntf()];
    }
}

- (int)processIsTranslated
{
   int ret = 0;
   size_t size = sizeof(ret);
   if (sysctlbyname("sysctl.proc_translated", &ret, &size, NULL, 0) == -1) {
      if (errno == ENOENT)
         return 0;
      return -1;
   }
   return ret;
}

#pragma mark -
#pragma mark Termination

- (BOOL)isTerminating
{
    return _interfaceIsTerminating;
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
    if (_interfaceIsTerminating)
        return;
    _interfaceIsTerminating = true;

    NSNotificationCenter *notiticationCenter = NSNotificationCenter.defaultCenter;
    if (notification == nil) {
        [notiticationCenter postNotificationName: NSApplicationWillTerminateNotification object: nil];
    }
    [notiticationCenter removeObserver: self];

    // closes all open vouts
    _voutProvider = nil;
    _continuityController = nil;

    /* write cached user defaults to disk */
    CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication);
}

#pragma mark -
#pragma mark File opening over dock icon

- (void)application:(NSApplication *)o_app openFiles:(NSArray *)o_names
{
    // Only add items here which are getting dropped to to the application icon
    // or are given at startup. If a file is passed via command line, libvlccore
    // will add the item, but cocoa also calls this function. In this case, the
    // invocation is ignored here.
    NSArray *resultItems = o_names;
    if (_launched == NO) {
        NSArray *launchArgs = [[NSProcessInfo processInfo] arguments];

        if (launchArgs) {
            NSSet *launchArgsSet = [NSSet setWithArray:launchArgs];
            NSMutableSet *itemSet = [NSMutableSet setWithArray:o_names];
            [itemSet minusSet:launchArgsSet];
            resultItems = [itemSet allObjects];
        }
    }

    NSArray *o_sorted_names = [resultItems sortedArrayUsingSelector: @selector(caseInsensitiveCompare:)];
    NSMutableArray *o_result = [NSMutableArray arrayWithCapacity: [o_sorted_names count]];
    for (NSString *filepath in o_sorted_names) {
        VLCOpenInputMetadata *inputMetadata;

        inputMetadata = [VLCOpenInputMetadata inputMetaWithPath:filepath];
        if (!inputMetadata)
            continue;

        [o_result addObject:inputMetadata];
    }

    [_playQueueController addPlayQueueItems:o_result];
}

/* When user click in the Dock icon our double click in the finder */
- (BOOL)applicationShouldHandleReopen:(NSApplication *)theApplication hasVisibleWindows:(BOOL)hasVisibleWindows
{
    if (!hasVisibleWindows)
        [[self libraryWindow] makeKeyAndOrderFront:self];

    return YES;
}

- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app
{
    return YES;
}

#pragma mark -
#pragma mark Other objects getters

- (VLCMainMenu *)mainMenu
{
    return _mainmenu;
}

- (VLCLibraryWindow *)libraryWindow
{
    return (VLCLibraryWindow *)_libraryWindowController.window;
}

- (VLCLogWindowController *)debugMsgPanel
{
    if (!_messagePanelController)
        _messagePanelController = [[VLCLogWindowController alloc] init];

    return _messagePanelController;
}

- (VLCTrackSynchronizationWindowController *)trackSyncPanel
{
    if (!_trackSyncPanel)
        _trackSyncPanel = [[VLCTrackSynchronizationWindowController alloc] init];

    return _trackSyncPanel;
}

- (VLCAudioEffectsWindowController *)audioEffectsPanel
{
    return _audioEffectsPanel;
}

- (VLCVideoEffectsWindowController *)videoEffectsPanel
{
    return _videoEffectsPanel;
}

- (VLCBookmarksWindowController *)bookmarks
{
    if (!self.libraryController.libraryModel) {
        return nil;
    }

    if (!_bookmarks)
        _bookmarks = [[VLCBookmarksWindowController alloc] init];

    return _bookmarks;
}

- (VLCOpenWindowController *)open
{
    if (!_open)
        _open = [[VLCOpenWindowController alloc] init];

    return _open;
}

- (VLCConvertAndSaveWindowController *)convertAndSaveWindow
{
    if (_convertAndSaveWindow == nil)
        _convertAndSaveWindow = [[VLCConvertAndSaveWindowController alloc] init];

    return _convertAndSaveWindow;
}

- (VLCSimplePrefsController *)simplePreferences
{
    if (!_sprefs)
        _sprefs = [[VLCSimplePrefsController alloc] init];

    return _sprefs;
}

- (MacLCSettingsWindowController *)settingsWindowController
{
    if (!_settingsWindowController)
        _settingsWindowController = [[MacLCSettingsWindowController alloc] initWithIntf:_p_intf];

    return _settingsWindowController;
}

- (VLCPrefs *)preferences
{
    if (!_prefs)
        _prefs = [[VLCPrefs alloc] init];

    return _prefs;
}

- (VLCCoreDialogProvider *)coreDialogProvider
{
    return _coredialogs;
}

- (VLCDetachedAudioWindow *)detachedAudioWindow
{
    if (_detachedAudioWindow == nil) {
        NSWindowController * const windowController = [[NSWindowController alloc] initWithWindowNibName:NSStringFromClass(VLCDetachedAudioWindow.class)];
        [windowController loadWindow];
        _detachedAudioWindow = (VLCDetachedAudioWindow *)windowController.window;
    }

    return _detachedAudioWindow;
}

@end
