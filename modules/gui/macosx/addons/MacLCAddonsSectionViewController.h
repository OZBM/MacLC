/*****************************************************************************
 * MacLCAddonsSectionViewController.h: the Add-ons section of the library window
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

#import "medialib/sections/MacLCLibrarySectionViewController.h"

NS_ASSUME_NONNULL_BEGIN

/// The installed add-ons as cards, an "Add from Address…" button, and the
/// Discover grid of the add-on catalogs of the installed add-ons. It replaces
/// the Add-ons pane of the Settings window. The toolbar search field filters
/// both lists by name and description.
@interface MacLCAddonsSectionViewController : MacLCLibrarySectionViewController

- (instancetype)init;

@end

NS_ASSUME_NONNULL_END
