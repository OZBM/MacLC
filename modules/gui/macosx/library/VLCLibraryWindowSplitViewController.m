/*****************************************************************************
 * VLCLibraryWindowSplitViewManager.h: MacOS X interface module
 *****************************************************************************
 * Copyright (C) 2023 VLC authors and VideoLAN
 *
 * Authors: Claudio Cambra <developer@claudiocambra.com>
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

#import "VLCLibraryWindowSplitViewController.h"

#import "extensions/NSView+VLCAdditions.h"

#import "library/VLCLibraryWindow.h"

#import "main/VLCMain.h"

#import "medialib/shell/MacLCLibrarySidebarViewController.h"
#import "medialib/shell/MacLCNowPlayingBar.h"
#import "medialib/shell/MacLCUpNextViewController.h"

#import "views/VLCBottomBarView.h"
#import "views/VLCUIUnits.h"

#import "windows/controlsbar/VLCMainWindowControlsBar.h"

#import "windows/video/VLCMainVideoViewController.h"

@interface VLCLibraryWindowSplitViewController ()

@property (readwrite) BOOL priorNavSidebarCollapsedState;
@property (readwrite, strong) NSView *legacyBottomBarView;

@end

@implementation VLCLibraryWindowSplitViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

    VLCLibraryWindow * const libraryWindow = VLCMain.sharedInstance.libraryWindow;

    self.splitView.wantsLayer = YES;
    /* A new name for the new layout: the old one remembered a sidebar that
     * embedded video had collapsed, and a play queue that no longer exists. */
    self.splitView.autosaveName = @"MacLCLibrarySplitView";
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(applicationWillTerminate:)
                                               name:NSApplicationWillTerminateNotification
                                             object:nil];

    _navSidebarViewController =
        [[MacLCLibrarySidebarViewController alloc] initWithLibraryWindow:libraryWindow];
    _multifunctionSidebarViewController =
        [[MacLCUpNextViewController alloc] initWithLibraryWindow:libraryWindow];

    /* Library sections, Browse and the embedded video all replace the
     * subviews of libraryTargetView, so the floating Now Playing bar lives one
     * level up, in a container that also holds libraryTargetView. */
    NSView * const libraryTargetView = self.libraryWindow.libraryTargetView;
    NSView * const contentView = [[NSView alloc] init];
    libraryTargetView.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:libraryTargetView];
    [libraryTargetView applyConstraintsToFillSuperview];

    _nowPlayingBar = [[MacLCNowPlayingBar alloc] initWithLibraryWindow:libraryWindow];
    [contentView addSubview:_nowPlayingBar]; // it constrains itself, bottom centre
    __weak NSView * const weakLibraryTargetView = libraryTargetView;
    _nowPlayingBar.visibilityHandler = ^(const BOOL shown) {
        /* Let the content scroll under the bar but end above it. */
        weakLibraryTargetView.additionalSafeAreaInsets =
            NSEdgeInsetsMake(0., 0., shown ? MacLCNowPlayingBar.reservedHeight : 0., 0.);
    };
    _nowPlayingBar.visibilityHandler(_nowPlayingBar.isShown);

    _libraryTargetViewController = [[NSViewController alloc] init];
    self.libraryTargetViewController.view = contentView;

    /* macOS 26: the sidebar and the inspector float as Liquid Glass over the
     * content, which extends under them through its safe area. */
    _navSidebarItem = [NSSplitViewItem sidebarWithViewController:self.navSidebarViewController];
    _libraryTargetViewItem = [NSSplitViewItem splitViewItemWithViewController:self.libraryTargetViewController];
    _multifunctionSidebarItem = [NSSplitViewItem inspectorWithViewController:self.multifunctionSidebarViewController];

    _navSidebarItem.allowsFullHeightLayout = YES;
    _multifunctionSidebarItem.allowsFullHeightLayout = YES;
    _libraryTargetViewItem.automaticallyAdjustsSafeAreaInsets = YES;

    _navSidebarItem.preferredThicknessFraction = 0.2;
    _navSidebarItem.minimumThickness = VLCUIUnits.libraryWindowNavSidebarMinWidth;
    _navSidebarItem.maximumThickness = VLCUIUnits.libraryWindowNavSidebarMaxWidth;

    self.multifunctionSidebarItem.minimumThickness = 280.;
    self.multifunctionSidebarItem.maximumThickness = 420.;
    self.multifunctionSidebarItem.canCollapse = YES;
    self.multifunctionSidebarItem.collapseBehavior =
        NSSplitViewItemCollapseBehaviorPreferResizingSiblingsWithFixedSplitView;
    self.multifunctionSidebarItem.collapsed = YES;

    self.splitViewItems = @[_navSidebarItem, _libraryTargetViewItem, self.multifunctionSidebarItem];

    /* The XIB controls bar is replaced by the Now Playing bar. Detach it (but
     * keep it alive, its controller still updates it): its fixed-width
     * content would otherwise set a minimum width for the content, which
     * collapsed the sidebar and pinned the window to 808 pt. */
    VLCBottomBarView * const bottomBarView = libraryWindow.controlsBar.bottomBarView;
    _legacyBottomBarView = bottomBarView;
    [bottomBarView removeFromSuperview];
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
    /* Embedded video hides the sidebar; save the user's choice instead. */
    if (self.mainVideoModeEnabled) {
        self.navSidebarItem.collapsed = self.priorNavSidebarCollapsedState;
    }
}

- (IBAction)toggleNavigationSidebar:(id)sender
{
    if (self.mainVideoModeEnabled) {
        return;
    }
    const BOOL navigationSidebarCollapsed = self.navSidebarItem.isCollapsed;
    self.navSidebarItem.animator.collapsed = !navigationSidebarCollapsed;
}

- (IBAction)toggleMultifunctionSidebar:(id)sender
{
    const BOOL sidebarCollapsed = self.multifunctionSidebarItem.isCollapsed;
    self.multifunctionSidebarItem.animator.collapsed = !sidebarCollapsed;

    /* From the target state: the animation has not changed isCollapsed yet. */
    const NSControlStateValue controlState = sidebarCollapsed ? NSControlStateValueOn : NSControlStateValueOff;
    self.libraryWindow.playQueueToggle.state = controlState;
    self.libraryWindow.videoViewController.playQueueButton.state = controlState;
}

- (void)setMainVideoModeEnabled:(BOOL)mainVideoModeEnabled
{
    if (self.mainVideoModeEnabled == mainVideoModeEnabled) {
        return;
    } else if (mainVideoModeEnabled) {
        self.priorNavSidebarCollapsedState = self.navSidebarItem.isCollapsed;
        self.navSidebarItem.collapsed = YES;
    } else {
        self.navSidebarItem.collapsed = self.priorNavSidebarCollapsedState;
    }

    _mainVideoModeEnabled = mainVideoModeEnabled;
}

- (BOOL)splitView:(NSSplitView *)splitView canCollapseSubview:(NSView *)subview
{
    /* The items decide (the content never collapses); embedded video keeps
     * the sidebar out of the way. */
    if (self.mainVideoModeEnabled && subview == self.navSidebarViewController.view) {
        return YES;
    }
    return [super splitView:splitView canCollapseSubview:subview];
}

/* The toolbar's sidebar button and View ▸ Show Sidebar reach the split view
 * controller first: keep the sidebar away from embedded video here too. */
- (IBAction)toggleSidebar:(id)sender
{
    if (self.mainVideoModeEnabled) {
        return;
    }
    [super toggleSidebar:sender];
}

- (BOOL)validateUserInterfaceItem:(id<NSValidatedUserInterfaceItem>)item
{
    if (item.action == @selector(toggleSidebar:) && self.mainVideoModeEnabled) {
        return NO;
    }
    return [super validateUserInterfaceItem:item];
}

@end
