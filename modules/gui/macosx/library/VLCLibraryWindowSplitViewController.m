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

@end

@implementation VLCLibraryWindowSplitViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

    VLCLibraryWindow * const libraryWindow = VLCMain.sharedInstance.libraryWindow;
    [libraryWindow addObserver:self
                    forKeyPath:VLCLibraryWindowEmbeddedVideoPlaybackActiveKey
                       options:0
                       context:nil];

    self.splitView.wantsLayer = YES;

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

    VLCMainWindowControlsBar * const controlsBar = libraryWindow.controlsBar;
    VLCBottomBarView * const bottomBarView = controlsBar.bottomBarView;
    bottomBarView.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [bottomBarView.leadingAnchor constraintEqualToAnchor:self.libraryTargetViewController.view.leadingAnchor
                                                    constant:VLCUIUnits.largeSpacing * 2],
        [bottomBarView.trailingAnchor constraintEqualToAnchor:self.libraryTargetViewController.view.trailingAnchor
                                                     constant:-(VLCUIUnits.largeSpacing * 2)],
    ]];
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context
{
    if([keyPath isEqualToString:VLCLibraryWindowEmbeddedVideoPlaybackActiveKey]) {
        VLCLibraryWindow * const libraryWindow = VLCMain.sharedInstance.libraryWindow;
        const BOOL videoPlaybackActive = libraryWindow.embeddedVideoPlaybackActive;
        _navSidebarItem.collapsed = videoPlaybackActive;
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

    const NSControlStateValue controlState =
        self.multifunctionSidebarItem.isCollapsed ? NSControlStateValueOff : NSControlStateValueOn;
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
    return subview != self.navSidebarViewController.view
           || !self.mainVideoModeEnabled
           || [super splitView:splitView canCollapseSubview:subview];
}

@end
