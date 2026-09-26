/*****************************************************************************
 * MacLCLibrarySectionViewController.h: base of every native library section
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

#import <Cocoa/Cocoa.h>

#import "medialib/MacLCLibraryTypes.h"

@protocol VLCMediaLibraryItemProtocol;

NS_ASSUME_NONNULL_BEGIN

/// Posted (object: the section) whenever something the toolbar shows changed:
/// title, subtitle, view mode availability, sort menu, back availability.
extern NSNotificationName const MacLCLibrarySectionChromeDidChangeNotification;

/// A section of the library (Home, Videos, Albums...). It owns a navigation
/// stack: a root view controller for the list, and detail view controllers
/// pushed on top (an album, a show...). The toolbar reads its chrome, the
/// router shows its view in the library window.
///
/// The base class does the container work: it hosts the top view
/// controller's view filling its own view, cross-fades pushes and pops
/// (MacLCDesign.motionStandardDuration, plain cut under Reduce Motion),
/// keeps the root alive, restores first responder to the root's
/// preferred view on pop, and posts the chrome notification.
///
/// Subclasses override the "Subclass hooks" and never touch the stack
/// directly except through push/pop.
@interface MacLCLibrarySectionViewController : NSViewController

- (instancetype)initWithSegmentType:(NSInteger)segmentType NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithNibName:(nullable NSNibName)nibNameOrNil
                         bundle:(nullable NSBundle *)nibBundleOrNil NS_UNAVAILABLE;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

/// A VLCLibrarySegmentType value.
@property (readonly) NSInteger segmentType;

// MARK: Chrome read by the toolbar

/// Title case, e.g. "Albums". Also the window title.
@property (readonly, copy) NSString *sectionTitle;
/// Sentence case count, e.g. "38 albums"; nil while a detail is shown.
@property (readonly, copy, nullable) NSString *sectionSubtitle;
@property (readonly) BOOL supportsViewModes;
@property (nonatomic) MacLCLibraryViewMode viewMode;
/// A menu of NSMenuItems with states (sort key radio group, separator,
/// Ascending/Descending radio group). nil hides the sort control.
@property (readonly, nullable) NSMenu *sortMenu;
@property (readonly, copy) NSString *searchPlaceholder;
@property (readonly) BOOL canGoBack;

// MARK: Actions from the toolbar and the router

/// Filters what the section shows (as-you-type, in memory). "" clears.
- (void)applySearchString:(NSString *)searchString;
- (void)goBack;
/// Shows a library object: pushes its detail if the section has one for it,
/// otherwise scrolls to and selects it.
- (void)showItem:(id<VLCMediaLibraryItemProtocol>)item;

// MARK: Navigation stack (for subclasses)

@property (readonly) NSViewController *rootViewController;
@property (readonly) NSViewController *topViewController;
- (void)pushViewController:(NSViewController *)viewController;
- (void)popViewController;
/// Call after changing anything listed under "Chrome".
- (void)chromeDidChange;

// MARK: Subclass hooks

/// Builds the root view controller for a view mode (called at load and when
/// viewMode changes; the base class swaps them without animation).
- (NSViewController *)makeRootViewControllerForViewMode:(MacLCLibraryViewMode)viewMode;
/// Default: NO.
- (BOOL)sectionSupportsViewModes;
/// Default: nil.
- (nullable NSMenu *)makeSortMenu;
/// Default: sectionTitle-based "Search Albums".
- (NSString *)makeSearchPlaceholder;
/// Default: nil.
- (nullable NSString *)currentSubtitle;
/// Default: forwards to the root view controller if it responds to
/// -applySearchString:.
- (void)searchStringDidChange:(NSString *)searchString;
/// Default: returns nil (no detail). Return a view controller to push.
- (nullable NSViewController *)detailViewControllerForItem:(id<VLCMediaLibraryItemProtocol>)item;

@end

NS_ASSUME_NONNULL_END
