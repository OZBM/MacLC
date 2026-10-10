/*****************************************************************************
 * MacLCYouTubeAccount.h: signing in to YouTube with a Google account, so the
 * YouTube section shows the person's own recommendations, subscriptions,
 * history, Watch Later, liked videos and playlists
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

/* No API key, no OAuth client: yt-dlp reads the person's lists with the
 * cookies of a signed-in YouTube session, given one of two ways.
 *
 * 1. "Sign In with Google…" (MacLC): a window with a WKWebView on Google's
 *    own sign-in page for YouTube
 *    (https://accounts.google.com/ServiceLogin?service=youtube&continue=
 *    https://www.youtube.com/signin?action_handle_signin=true&next=/ ...).
 *    The person types their credentials into Google's page; MacLC never sees
 *    or stores a password. The web view uses a NON-persistent data store
 *    (WKWebsiteDataStore nonPersistentDataStore) and a Safari user agent
 *    (Google refuses sign-in from agents it takes for embedded browsers).
 *    Signed in = the .youtube.com cookie store holds SAPISID (or
 *    __Secure-3PAPISID) and LOGIN_INFO. Then every cookie of youtube.com and
 *    google.com is written in Netscape format ("#HttpOnly_" prefix for
 *    HttpOnly cookies; expiry 0 for session cookies) to
 *      <Application Support>/org.maclc.MacLC/YouTube/cookies.txt
 *    ($MACLC_YOUTUBE_DATA_DIR/cookies.txt when set), created with mode 0600
 *    in a 0700 folder, and the window closes. yt-dlp keeps it up to date
 *    (it writes refreshed cookies back to that file). The avatar URL is read
 *    from the signed-in youtube.com page before closing (best effort, by
 *    evaluating JavaScript on ytInitialData / the topbar avatar image) and
 *    kept in NSUserDefaults "MacLCYouTubeAvatarURL"; no name is stored.
 *    Exporting cookies from a private session (nothing else touches them)
 *    is also what yt-dlp recommends so that YouTube does not rotate them.
 * 2. "Use <Browser>'s Session": yt-dlp's --cookies-from-browser <name> reads
 *    the cookies of a browser where the person is signed in to YouTube (Safari
 *    needs Full Disk Access for MacLC; Chrome-family browsers ask for their
 *    Keychain item the first time). Only the browser's name is stored
 *    (NSUserDefaults "MacLCYouTubeBrowser").
 *
 * Signed out = no cookie file and no browser. -signOut deletes the cookie
 * file and the stored avatar/browser, and posts the notification.
 *
 * Security (trust boundary): the cookie file is a session secret. It is never
 * logged, never put in a URL or a command line other than its path, never
 * copied elsewhere, and only passed to yt-dlp with --cookies <path>.
 * Main thread only. */
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// Posted on the main queue after sign-in, sign-out or a change of method.
extern NSNotificationName const MacLCYouTubeAccountDidChangeNotification;

typedef NS_ENUM(NSInteger, MacLCYouTubeSignInMethod) {
    MacLCYouTubeSignInMethodNone,
    /// The in-app sign-in window (cookie file).
    MacLCYouTubeSignInMethodMacLC,
    /// A browser's session (--cookies-from-browser).
    MacLCYouTubeSignInMethodBrowser,
};

@interface MacLCYouTubeAccount : NSObject

@property (class, readonly) MacLCYouTubeAccount *sharedAccount;

@property (readonly, getter=isSignedIn) BOOL signedIn;
@property (readonly) MacLCYouTubeSignInMethod method;
/// yt-dlp's name of the browser ("safari", "chrome", "firefox", "brave",
/// "edge", "vivaldi", "opera", "chromium"), nil unless method is Browser.
@property (readonly, copy, nullable) NSString *browserName;
/// "Safari", "Google Chrome"... for the menus; nil unless method is Browser.
@property (readonly, copy, nullable) NSString *browserDisplayName;
@property (readonly, nullable) NSURL *avatarURL;

/// ["--cookies", <path>], ["--cookies-from-browser", <name>] or [].
@property (readonly, copy) NSArray<NSString *> *extractorArguments;

/// Shows the sign-in window, as a sheet on window when given. completion:
/// YES once signed in, NO when the person closed the window. Main queue.
- (void)beginSignInFromWindow:(nullable NSWindow *)window
                   completion:(nullable void (^)(BOOL signedIn))completion;
/// Switches to a browser's session (one of availableBrowsers' names).
- (void)useBrowserSession:(NSString *)browserName;
- (void)signOut;

/// yt-dlp names of the supported browsers installed on this Mac, in this
/// order: safari, chrome, firefox, brave, edge, vivaldi, opera, chromium
/// (found with NSWorkspace URLForApplicationWithBundleIdentifier:; yt-dlp
/// cannot read Arc's cookies, so it is not offered).
+ (NSArray<NSString *> *)availableBrowsers;
+ (NSString *)displayNameForBrowser:(NSString *)browserName;

@end

NS_ASSUME_NONNULL_END
