/*****************************************************************************
 * MacLCYouTubeSignInWindowController.h: the "Sign In to YouTube" window
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

/* Private to MacLCYouTubeAccount: a WKWebView on Google's own sign-in page
 * (non-persistent data store, Safari user agent). It never reads or stores what
 * is typed and injects nothing into Google's pages; once www.youtube.com shows
 * a signed-in session it reads the avatar (read-only JavaScript, youtube.com
 * only) and hands the session cookies to the save handler. Main thread only. */
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// Called on the main thread once the person is signed in, with every cookie of
/// the session and the avatar URL when it could be read. Return YES when the
/// session was saved (the window then closes), NO to show an error with
/// "Try Again" in the window.
typedef BOOL (^MacLCYouTubeSignInSaveHandler)(NSArray<NSHTTPCookie *> *cookies,
                                              NSURL * _Nullable avatarURL);

@interface MacLCYouTubeSignInWindowController : NSWindowController

- (instancetype)initWithSaveHandler:(MacLCYouTubeSignInSaveHandler)saveHandler NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithWindow:(nullable NSWindow *)window NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

/// Shows the window, as a sheet on parent when given. completion is called
/// exactly once, after the window is gone: YES when the save handler accepted
/// a session, NO when the person closed the window.
- (void)presentFromWindow:(nullable NSWindow *)parent completion:(void (^)(BOOL signedIn))completion;

/// Brings an already visible window forward.
- (void)bringToFront;

@end

NS_ASSUME_NONNULL_END
