/*****************************************************************************
 * MacLCLibraryToolbarController.h: the library window's Liquid Glass toolbar
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

@class VLCLibraryWindow;

NS_ASSUME_NONNULL_BEGIN

/// A code-built NSToolbar (unified style, system glass pills, no custom
/// backgrounds or tints: toolbars.md › "Reduce the use of toolbar
/// backgrounds and tinted controls"), in three groups at most:
///
///  [sidebar toggle] [sidebar tracking separator] [‹ ›]  Title — subtitle
///        ...flexible space...
///  [▦ ☰ view mode] [↑↓ sort]   [🔍 search]  [inspector tracking separator] [Up Next]
///
/// - Sidebar toggle: NSToolbarToggleSidebarItemIdentifier.
/// - Back/Forward: NSToolbarItemGroup (chevron.backward / chevron.forward),
///   enabled from the current section's canGoBack (Browse: its own history).
/// - Title and subtitle: the window's title/subtitle, set by the router.
/// - View mode: NSToolbarItemGroup, selectOne, square.grid.2x2 / list.bullet,
///   hidden (not disabled) when the section has no view modes.
/// - Sort: NSMenuToolbarItem, arrow.up.arrow.down, the section's sortMenu;
///   hidden when nil.
/// - Search: NSSearchToolbarItem, placeholder from the section, filters as you
///   type (debounced 120 ms), Escape clears; ⌘F focuses it (menu item).
/// - Up Next: toggles the split view's inspector item (Up Next queue),
///   symbol text.line.first.and.arrowtriangle.forward, label "Up Next".
/// Every item has a label and palette label; the toolbar is customizable and
/// autosaves under "MacLCLibraryToolbar". Every command also exists in the
/// menu bar (toolbars.md › Desktop).
@interface MacLCLibraryToolbarController : NSObject <NSToolbarDelegate>

- (instancetype)initWithLibraryWindow:(VLCLibraryWindow *)libraryWindow;

@property (readonly) NSToolbar *toolbar;

/// Installs the toolbar on the window (replacing the XIB one) and configures
/// the window chrome: toolbarStyle unified, titleVisibility visible,
/// titlebarSeparatorStyle automatic, full-size content view.
- (void)install;

/// Makes the search field first responder (Edit ▸ Find, ⌘F).
- (void)focusSearchField;

@end

NS_ASSUME_NONNULL_END
