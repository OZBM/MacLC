/*****************************************************************************
 * MacLCYouTubeAccount.m: signing in to YouTube with a Google account
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

#import "MacLCYouTubeAccount.h"
#import "MacLCYouTubeSignInWindowController.h"

#include <limits.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>

NSNotificationName const MacLCYouTubeAccountDidChangeNotification = @"MacLCYouTubeAccountDidChange";

static NSString * const kAvatarDefaultsKey = @"MacLCYouTubeAvatarURL";
static NSString * const kBrowserDefaultsKey = @"MacLCYouTubeBrowser";
static NSString * const kDataDirEnvironmentKey = @"MACLC_YOUTUBE_DATA_DIR";

/* yt-dlp name, bundle identifier, display name; the order is the one of
 * +availableBrowsers. */
static NSArray<NSArray<NSString *> *> *SupportedBrowsers(void)
{
    return @[
        @[@"safari",   @"com.apple.Safari",           @"Safari"],
        @[@"chrome",   @"com.google.Chrome",          @"Google Chrome"],
        @[@"firefox",  @"org.mozilla.firefox",        @"Firefox"],
        @[@"brave",    @"com.brave.Browser",          @"Brave"],
        @[@"edge",     @"com.microsoft.edgemac",      @"Microsoft Edge"],
        @[@"vivaldi",  @"com.vivaldi.Vivaldi",        @"Vivaldi"],
        @[@"opera",    @"com.operasoftware.Opera",    @"Opera"],
        @[@"chromium", @"org.chromium.Chromium",      @"Chromium"],
    ];
}

static NSArray<NSString *> *BrowserEntry(NSString *name)
{
    for (NSArray<NSString *> *entry in SupportedBrowsers()) {
        if ([entry[0] isEqualToString:name])
            return entry;
    }
    return nil;
}

#pragma mark - Netscape cookie file

/* Cookies of youtube.com and google.com (and their subdomains) only. */
static BOOL IsYouTubeOrGoogleDomain(NSString *domain)
{
    NSString *d = domain.lowercaseString;
    if ([d hasPrefix:@"."])
        d = [d substringFromIndex:1];
    for (NSString *base in @[@"youtube.com", @"google.com"]) {
        if ([d isEqualToString:base] || [d hasSuffix:[@"." stringByAppendingString:base]])
            return YES;
    }
    return NO;
}

static BOOL HasLineBreakOrTab(NSString *s)
{
    return [s rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"\t\r\n"]].location != NSNotFound;
}

/* Not static: the standalone serialisation test links it. */
NSString *MacLCYouTubeNetscapeCookieFile(NSArray<NSHTTPCookie *> *cookies);
NSString *MacLCYouTubeNetscapeCookieFile(NSArray<NSHTTPCookie *> *cookies)
{
    NSMutableString *out = [NSMutableString stringWithString:@"# Netscape HTTP Cookie File\n"];
    for (NSHTTPCookie *c in cookies) {
        NSString *domain = c.domain, *path = c.path.length ? c.path : @"/";
        if (!domain.length || !c.name.length)
            continue;
        if (HasLineBreakOrTab(domain) || HasLineBreakOrTab(path)
            || HasLineBreakOrTab(c.name) || HasLineBreakOrTab(c.value))
            continue;
        long long expiry = 0;
        if (c.expiresDate && !c.sessionOnly)
            expiry = MAX(0LL, (long long)c.expiresDate.timeIntervalSince1970);
        [out appendFormat:@"%@%@\t%@\t%@\t%@\t%lld\t%@\t%@\n",
         c.HTTPOnly ? @"#HttpOnly_" : @"", domain,
         [domain hasPrefix:@"."] ? @"TRUE" : @"FALSE",
         path, c.secure ? @"TRUE" : @"FALSE", expiry, c.name, c.value];
    }
    return out;
}

#pragma mark - Files

static NSURL *DataDirectory(void)
{
    NSString *override = NSProcessInfo.processInfo.environment[kDataDirEnvironmentKey];
    if (override.length)
        return [NSURL fileURLWithPath:override.stringByStandardizingPath isDirectory:YES];
    NSURL *support = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory
                                                          inDomains:NSUserDomainMask].firstObject;
    return [[support URLByAppendingPathComponent:@"org.maclc.MacLC" isDirectory:YES]
            URLByAppendingPathComponent:@"YouTube" isDirectory:YES];
}

static NSString *CookieFilePath(void)
{
    return [DataDirectory() URLByAppendingPathComponent:@"cookies.txt"].path;
}

/* The folder is 0700, the file is created 0600 by mkstemp and renamed over the
 * destination, so a reader never sees a partial file. */
static BOOL WriteCookieFile(NSString *text)
{
    NSFileManager *fm = NSFileManager.defaultManager;
    NSURL *dir = DataDirectory();
    NSDictionary *attributes = @{ NSFilePosixPermissions: @(0700) };
    if (![fm createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:attributes error:NULL])
        return NO;
    [fm setAttributes:attributes ofItemAtPath:dir.path error:NULL];

    char tmp[PATH_MAX];
    snprintf(tmp, sizeof tmp, "%s/.cookies.txt.XXXXXX", dir.fileSystemRepresentation);
    int fd = mkstemp(tmp);
    if (fd < 0)
        return NO;

    NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
    const char *bytes = data.bytes;
    size_t left = data.length;
    BOOL ok = YES;
    while (left > 0) {
        ssize_t n = write(fd, bytes, left);
        if (n < 0) {
            ok = NO;
            break;
        }
        bytes += n;
        left -= (size_t)n;
    }
    ok = ok && fsync(fd) == 0;
    ok = (close(fd) == 0) && ok;
    if (ok)
        ok = rename(tmp, CookieFilePath().fileSystemRepresentation) == 0;
    if (!ok)
        unlink(tmp);
    return ok;
}

#pragma mark - Account

@implementation MacLCYouTubeAccount {
    MacLCYouTubeSignInWindowController *_signInController;
    NSMutableArray<void (^)(BOOL)> *_pendingCompletions;
}

+ (MacLCYouTubeAccount *)sharedAccount
{
    static MacLCYouTubeAccount *account;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        account = [[MacLCYouTubeAccount alloc] init];
    });
    return account;
}

- (void)postChange
{
    [NSNotificationCenter.defaultCenter postNotificationName:MacLCYouTubeAccountDidChangeNotification object:self];
}

- (NSString *)storedBrowserName
{
    NSString *name = [NSUserDefaults.standardUserDefaults stringForKey:kBrowserDefaultsKey];
    return name && BrowserEntry(name) ? name : nil;
}

- (MacLCYouTubeSignInMethod)method
{
    if ([self storedBrowserName])
        return MacLCYouTubeSignInMethodBrowser;
    if ([NSFileManager.defaultManager fileExistsAtPath:CookieFilePath()])
        return MacLCYouTubeSignInMethodMacLC;
    return MacLCYouTubeSignInMethodNone;
}

- (BOOL)isSignedIn
{
    return self.method != MacLCYouTubeSignInMethodNone;
}

- (NSString *)browserName
{
    return [self storedBrowserName];
}

- (NSString *)browserDisplayName
{
    NSString *name = [self storedBrowserName];
    return name ? [MacLCYouTubeAccount displayNameForBrowser:name] : nil;
}

- (NSURL *)avatarURL
{
    if (self.method != MacLCYouTubeSignInMethodMacLC)
        return nil;
    NSString *s = [NSUserDefaults.standardUserDefaults stringForKey:kAvatarDefaultsKey];
    NSURL *url = s ? [NSURL URLWithString:s] : nil;
    return [url.scheme isEqualToString:@"https"] ? url : nil;
}

- (NSArray<NSString *> *)extractorArguments
{
    switch (self.method) {
        case MacLCYouTubeSignInMethodMacLC:
            return @[@"--cookies", CookieFilePath()];
        case MacLCYouTubeSignInMethodBrowser:
            return @[@"--cookies-from-browser", [self storedBrowserName]];
        default:
            return @[];
    }
}

#pragma mark Sign in

- (void)beginSignInFromWindow:(NSWindow *)window completion:(void (^)(BOOL))completion
{
    if (_signInController) {
        if (completion)
            [_pendingCompletions addObject:[completion copy]];
        [_signInController bringToFront];
        return;
    }
    _pendingCompletions = [NSMutableArray array];
    if (completion)
        [_pendingCompletions addObject:[completion copy]];

    MacLCYouTubeAccount *account = self;
    MacLCYouTubeSignInWindowController *controller =
        [[MacLCYouTubeSignInWindowController alloc] initWithSaveHandler:^BOOL(NSArray<NSHTTPCookie *> *cookies, NSURL *avatar) {
            return [account saveSessionCookies:cookies avatarURL:avatar];
        }];
    _signInController = controller;
    [controller presentFromWindow:window completion:^(BOOL signedIn) {
        NSArray<void (^)(BOOL)> *pending = account->_pendingCompletions;
        account->_pendingCompletions = nil;
        account->_signInController = nil;
        for (void (^block)(BOOL) in pending)
            block(signedIn);
    }];
}

/* Called by the sign-in window with the cookies of the signed-in session. */
- (BOOL)saveSessionCookies:(NSArray<NSHTTPCookie *> *)cookies avatarURL:(NSURL *)avatar
{
    NSMutableArray<NSHTTPCookie *> *kept = [NSMutableArray array];
    for (NSHTTPCookie *c in cookies) {
        if (IsYouTubeOrGoogleDomain(c.domain))
            [kept addObject:c];
    }
    if (!kept.count || !WriteCookieFile(MacLCYouTubeNetscapeCookieFile(kept)))
        return NO;

    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults removeObjectForKey:kBrowserDefaultsKey];
    if ([avatar.scheme isEqualToString:@"https"])
        [defaults setObject:avatar.absoluteString forKey:kAvatarDefaultsKey];
    else
        [defaults removeObjectForKey:kAvatarDefaultsKey];
    [self postChange];
    return YES;
}

- (void)useBrowserSession:(NSString *)browserName
{
    if (!BrowserEntry(browserName))
        return;
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setObject:browserName forKey:kBrowserDefaultsKey];
    [defaults removeObjectForKey:kAvatarDefaultsKey];
    /* One source of truth: the browser replaces the cookie file. */
    [NSFileManager.defaultManager removeItemAtPath:CookieFilePath() error:NULL];
    [self postChange];
}

- (void)signOut
{
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults removeObjectForKey:kBrowserDefaultsKey];
    [defaults removeObjectForKey:kAvatarDefaultsKey];
    [NSFileManager.defaultManager removeItemAtPath:CookieFilePath() error:NULL];
    [self postChange];
}

#pragma mark Browsers

+ (NSArray<NSString *> *)availableBrowsers
{
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (NSArray<NSString *> *entry in SupportedBrowsers()) {
        if ([NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:entry[1]])
            [names addObject:entry[0]];
    }
    return names;
}

+ (NSString *)displayNameForBrowser:(NSString *)browserName
{
    NSArray<NSString *> *entry = BrowserEntry(browserName);
    return entry ? entry[2] : browserName.capitalizedString;
}

@end
