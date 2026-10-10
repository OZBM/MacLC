/*****************************************************************************
 * MacLCYouTubeSignInWindowController.m: the "Sign In to YouTube" window
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

#import "MacLCYouTubeSignInWindowController.h"

#import <WebKit/WebKit.h>

#import "extensions/NSString+Helpers.h"
#import "theme/MacLCDesign.h"

static const NSTimeInterval kAvatarTimeout = 3.0;

/* Read-only: looks for the account button's image, then for an avatar URL in
 * the page's own initial data. Runs on www.youtube.com only, never on Google's
 * sign-in pages. */
static NSString * const kAvatarScript =
    @"(function(){try{"
    @"var i=document.querySelector('button#avatar-btn img, #avatar-btn img, ytd-topbar-menu-button-renderer img');"
    @"if(i&&i.src)return i.src;"
    @"var t=window.ytInitialData&&window.ytInitialData.topbar;"
    @"var m=t&&JSON.stringify(t).match(/\"url\":\"(https:[^\"]*)\"/);"
    @"return m?m[1]:null;}catch(e){return null;}})()";

#pragma mark - Hosts

static BOOL HostMatches(NSString *host, NSArray<NSString *> *bases)
{
    NSString *h = host.lowercaseString;
    for (NSString *base in bases) {
        if ([h isEqualToString:base] || [h hasSuffix:[@"." stringByAppendingString:base]])
            return YES;
    }
    return NO;
}

/* Where the sign-in view may navigate; everything else opens in the browser. */
static BOOL IsAllowedHost(NSString *host)
{
    return HostMatches(host, @[@"google.com", @"youtube.com", @"gstatic.com",
                               @"googleusercontent.com", @"youtube-nocookie.com"]);
}

static BOOL IsYouTubeHost(NSString *host)
{
    return HostMatches(host, @[@"youtube.com"]);
}

static BOOL IsWebURL(NSURL *url)
{
    return [url.scheme.lowercaseString isEqualToString:@"https"] || [url.scheme.lowercaseString isEqualToString:@"http"];
}

static NSURL *SignInURL(void)
{
    NSMutableCharacterSet *unreserved = [NSMutableCharacterSet alphanumericCharacterSet];
    [unreserved addCharactersInString:@"-._~"];
    NSString *continueURL = [@"https://www.youtube.com/signin?action_handle_signin=true&next=/"
                             stringByAddingPercentEncodingWithAllowedCharacters:unreserved];
    return [NSURL URLWithString:[@"https://accounts.google.com/ServiceLogin?service=youtube&continue="
                                 stringByAppendingString:continueURL]];
}

/* Google refuses sign-in from agents it takes for embedded browsers. */
static NSString *SafariUserAgent(void)
{
    NSString *major = @"26";
    NSURL *safari = [NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:@"com.apple.Safari"];
    NSString *version = safari ? [NSBundle bundleWithURL:safari].infoDictionary[@"CFBundleShortVersionString"] : nil;
    NSString *first = [version componentsSeparatedByString:@"."].firstObject;
    if (first.length && [first rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet.invertedSet].location == NSNotFound)
        major = first;
    return [NSString stringWithFormat:@"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
            "(KHTML, like Gecko) Version/%@.0 Safari/605.1.15", major];
}

/* Signed in = SAPISID (or __Secure-3PAPISID) and LOGIN_INFO on .youtube.com. */
static BOOL HasSignedInSession(NSArray<NSHTTPCookie *> *cookies)
{
    BOOL api = NO, login = NO;
    for (NSHTTPCookie *c in cookies) {
        if (!IsYouTubeHost([c.domain hasPrefix:@"."] ? [c.domain substringFromIndex:1] : c.domain))
            continue;
        if ([c.name isEqualToString:@"SAPISID"] || [c.name isEqualToString:@"__Secure-3PAPISID"])
            api = YES;
        else if ([c.name isEqualToString:@"LOGIN_INFO"])
            login = YES;
    }
    return api && login;
}

#pragma mark - Controller

@interface MacLCYouTubeSignInWindowController () <WKNavigationDelegate, WKUIDelegate, WKHTTPCookieStoreObserver, NSWindowDelegate>
@end

@implementation MacLCYouTubeSignInWindowController {
    MacLCYouTubeSignInSaveHandler _saveHandler;
    void (^_completion)(BOOL);
    __weak NSWindow *_sheetParent;

    WKWebView *_webView;
    WKHTTPCookieStore *_cookieStore;
    NSProgressIndicator *_progress;
    NSImageView *_lockView;
    NSTextField *_hostLabel;
    NSBox *_errorBox;
    NSTextField *_errorLabel;

    NSURL *_failedURL;
    BOOL _youtubeLoaded;
    BOOL _finalizing;
    BOOL _finished;
    BOOL _signedIn;
}

- (instancetype)initWithSaveHandler:(MacLCYouTubeSignInSaveHandler)saveHandler
{
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 480, 640)
                                                   styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    self = [super initWithWindow:window];
    if (self) {
        _saveHandler = [saveHandler copy];
        window.title = _NS("Sign In to YouTube");
        window.releasedWhenClosed = NO;
        window.tabbingMode = NSWindowTabbingModeDisallowed;
        window.delegate = self;
        [self buildContent];
        [window center];
    }
    return self;
}

- (void)dealloc
{
    [self tearDown];
}

#pragma mark Layout

- (NSBox *)separator
{
    NSBox *box = [[NSBox alloc] init];
    box.boxType = NSBoxSeparator;
    box.translatesAutoresizingMaskIntoConstraints = NO;
    return box;
}

- (void)buildContent
{
    NSView *content = self.window.contentView;

    /* Header: lock + one calm sentence. */
    NSImageView *headerIcon = [NSImageView imageViewWithImage:
        [MacLCDesign symbolNamed:@"lock.shield" accessibilityLabel:nil] ?: [[NSImage alloc] init]];
    headerIcon.contentTintColor = MacLCDesign.secondaryLabel;
    [headerIcon setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSTextField *headerLabel = [NSTextField wrappingLabelWithString:
        _NS("Sign in with your Google account to see your own YouTube in MacLC.")];
    headerLabel.font = MacLCDesign.callout;
    headerLabel.textColor = MacLCDesign.secondaryLabel;
    NSStackView *header = [NSStackView stackViewWithViews:@[headerIcon, headerLabel]];
    header.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    header.alignment = NSLayoutAttributeCenterY;
    header.spacing = MacLCDesign.spacingS;
    header.edgeInsets = NSEdgeInsetsMake(MacLCDesign.spacingS, MacLCDesign.spacingM, MacLCDesign.spacingS, MacLCDesign.spacingM);
    header.translatesAutoresizingMaskIntoConstraints = NO;

    /* Web view: Google's own page, nothing persisted. */
    WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
    configuration.websiteDataStore = [WKWebsiteDataStore nonPersistentDataStore];
    _webView = [[WKWebView alloc] initWithFrame:NSZeroRect configuration:configuration];
    _webView.customUserAgent = SafariUserAgent();
    _webView.navigationDelegate = self;
    _webView.UIDelegate = self;
    _webView.translatesAutoresizingMaskIntoConstraints = NO;
    _webView.accessibilityLabel = _NS("Google sign-in");
    _cookieStore = configuration.websiteDataStore.httpCookieStore;
    [_cookieStore addObserver:self];

    /* Error state over the web view. */
    _errorLabel = [NSTextField wrappingLabelWithString:@""];
    _errorLabel.alignment = NSTextAlignmentCenter;
    _errorLabel.font = MacLCDesign.body;
    NSButton *retry = [NSButton buttonWithTitle:_NS("Try Again") target:self action:@selector(retry:)];
    [retry.heightAnchor constraintGreaterThanOrEqualToConstant:MacLCDesign.minimumHitTarget].active = YES;
    NSStackView *errorStack = [NSStackView stackViewWithViews:@[_errorLabel, retry]];
    errorStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    errorStack.alignment = NSLayoutAttributeCenterX;
    errorStack.spacing = MacLCDesign.spacingM;
    errorStack.translatesAutoresizingMaskIntoConstraints = NO;
    _errorBox = [[NSBox alloc] init];
    _errorBox.boxType = NSBoxCustom;
    _errorBox.borderWidth = 0;
    _errorBox.fillColor = MacLCDesign.windowBackground;
    _errorBox.titlePosition = NSNoTitle;
    _errorBox.contentView = [[NSView alloc] init];
    [_errorBox.contentView addSubview:errorStack];
    [NSLayoutConstraint activateConstraints:@[
        [errorStack.centerYAnchor constraintEqualToAnchor:_errorBox.contentView.centerYAnchor],
        [errorStack.leadingAnchor constraintEqualToAnchor:_errorBox.contentView.leadingAnchor constant:MacLCDesign.spacingXL],
        [errorStack.trailingAnchor constraintEqualToAnchor:_errorBox.contentView.trailingAnchor constant:-MacLCDesign.spacingXL],
    ]];
    _errorBox.hidden = YES;
    _errorBox.translatesAutoresizingMaskIntoConstraints = NO;

    /* Bottom bar: progress, host with lock, Cancel. */
    _progress = [[NSProgressIndicator alloc] init];
    _progress.style = NSProgressIndicatorStyleSpinning;
    _progress.controlSize = NSControlSizeSmall;
    _progress.displayedWhenStopped = NO;
    _progress.indeterminate = YES;
    _progress.accessibilityLabel = _NS("Loading");
    _lockView = [NSImageView imageViewWithImage:
        [MacLCDesign symbolNamed:@"lock.fill" accessibilityLabel:_NS("Secure connection")] ?: [[NSImage alloc] init]];
    _lockView.contentTintColor = MacLCDesign.secondaryLabel;
    _lockView.hidden = YES;
    _hostLabel = [NSTextField labelWithString:@""];
    _hostLabel.font = MacLCDesign.footnote;
    _hostLabel.textColor = MacLCDesign.secondaryLabel;
    _hostLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [_hostLabel setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSButton *cancel = [NSButton buttonWithTitle:_NS("Cancel") target:self action:@selector(cancel:)];
    cancel.keyEquivalent = @"\033";
    [cancel.heightAnchor constraintGreaterThanOrEqualToConstant:MacLCDesign.minimumHitTarget].active = YES;
    NSView *spacer = [[NSView alloc] init];
    [spacer setContentHuggingPriority:NSLayoutPriorityDefaultLow - 1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSStackView *bar = [NSStackView stackViewWithViews:@[_progress, _lockView, _hostLabel, spacer, cancel]];
    bar.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    bar.alignment = NSLayoutAttributeCenterY;
    bar.spacing = MacLCDesign.spacingS;
    bar.edgeInsets = NSEdgeInsetsMake(MacLCDesign.spacingS, MacLCDesign.spacingM, MacLCDesign.spacingS, MacLCDesign.spacingM);
    bar.translatesAutoresizingMaskIntoConstraints = NO;

    NSBox *topRule = [self separator], *bottomRule = [self separator];
    for (NSView *v in @[header, topRule, _webView, _errorBox, bottomRule, bar])
        [content addSubview:v];

    [NSLayoutConstraint activateConstraints:@[
        [header.topAnchor constraintEqualToAnchor:content.topAnchor],
        [header.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [header.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [topRule.topAnchor constraintEqualToAnchor:header.bottomAnchor],
        [topRule.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [topRule.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [_webView.topAnchor constraintEqualToAnchor:topRule.bottomAnchor],
        [_webView.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [_webView.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [_webView.bottomAnchor constraintEqualToAnchor:bottomRule.topAnchor],
        [_errorBox.topAnchor constraintEqualToAnchor:_webView.topAnchor],
        [_errorBox.leadingAnchor constraintEqualToAnchor:_webView.leadingAnchor],
        [_errorBox.trailingAnchor constraintEqualToAnchor:_webView.trailingAnchor],
        [_errorBox.bottomAnchor constraintEqualToAnchor:_webView.bottomAnchor],
        [bottomRule.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [bottomRule.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [bottomRule.bottomAnchor constraintEqualToAnchor:bar.topAnchor],
        [bar.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [bar.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [bar.bottomAnchor constraintEqualToAnchor:content.bottomAnchor],
    ]];
}

#pragma mark Presenting and finishing

- (void)presentFromWindow:(NSWindow *)parent completion:(void (^)(BOOL))completion
{
    _completion = [completion copy];
    [_webView loadRequest:[NSURLRequest requestWithURL:SignInURL()]];
    if (parent && !parent.attachedSheet && parent.visible) {
        _sheetParent = parent;
        [parent beginSheet:self.window completionHandler:^(NSModalResponse response) {
            [self deliverCompletion];
        }];
    } else {
        [self showWindow:nil];
    }
}

- (void)bringToFront
{
    if (!_sheetParent)
        [self.window makeKeyAndOrderFront:nil];
}

- (void)tearDown
{
    [_cookieStore removeObserver:self];
    _cookieStore = nil;
    _webView.navigationDelegate = nil;
    _webView.UIDelegate = nil;
    [_webView stopLoading];
}

/* Exactly once: tears the web view down, dismisses the window and, once it is
 * gone, calls the completion. fromClose: the window is already closing. */
- (void)finishSignedIn:(BOOL)signedIn closeWindow:(BOOL)closeWindow
{
    if (_finished)
        return;
    _finished = YES;
    _signedIn = signedIn;
    _saveHandler = nil;
    [self tearDown];
    NSWindow *parent = _sheetParent;
    if (parent) {
        _sheetParent = nil;
        [parent endSheet:self.window returnCode:signedIn ? NSModalResponseOK : NSModalResponseCancel];
        return; /* the sheet's completion handler delivers */
    }
    if (closeWindow)
        [self.window close];
    [self deliverCompletion];
}

- (void)deliverCompletion
{
    void (^completion)(BOOL) = _completion;
    _completion = nil;
    self.window.delegate = nil;
    if (completion)
        completion(_signedIn);
}

- (void)cancel:(id)sender
{
    [self finishSignedIn:NO closeWindow:YES];
}

- (void)windowWillClose:(NSNotification *)notification
{
    [self finishSignedIn:NO closeWindow:NO];
}

#pragma mark Session detection

/* Only once a youtube.com page has finished loading: the cookie observer alone
 * would fire in the middle of Google's own pages. */
- (void)checkSession
{
    if (_finalizing || _finished || !_youtubeLoaded)
        return;
    __weak MacLCYouTubeSignInWindowController *weakSelf = self;
    [_cookieStore getAllCookies:^(NSArray<NSHTTPCookie *> *cookies) {
        MacLCYouTubeSignInWindowController *strongSelf = weakSelf;
        if (strongSelf && !strongSelf->_finalizing && !strongSelf->_finished && HasSignedInSession(cookies))
            [strongSelf finalizeSession];
    }];
}

- (void)cookiesDidChangeInCookieStore:(WKHTTPCookieStore *)cookieStore
{
    [self checkSession];
}

- (void)finalizeSession
{
    _finalizing = YES;
    [_progress startAnimation:nil];
    _lockView.hidden = YES;
    _hostLabel.stringValue = _NS("Finishing sign-in…");

    __block BOOL proceeded = NO;
    __weak MacLCYouTubeSignInWindowController *weakSelf = self;
    void (^proceed)(NSURL *) = ^(NSURL *avatar) {
        if (proceeded)
            return;
        proceeded = YES;
        [weakSelf saveSessionWithAvatar:avatar];
    };
    if (!IsYouTubeHost(_webView.URL.host)) {
        proceed(nil);
        return;
    }
    [_webView evaluateJavaScript:kAvatarScript completionHandler:^(id result, NSError *error) {
        NSURL *url = [result isKindOfClass:NSString.class] ? [NSURL URLWithString:result] : nil;
        /* Only Google's image hosts: the URL is stored and later fetched. */
        if (![url.scheme isEqualToString:@"https"]
            || !HostMatches(url.host, @[@"ggpht.com", @"googleusercontent.com", @"gstatic.com"]))
            url = nil;
        proceed(url);
    }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kAvatarTimeout * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        proceed(nil);
    });
}

- (void)saveSessionWithAvatar:(NSURL *)avatar
{
    if (_finished)
        return;
    __weak MacLCYouTubeSignInWindowController *weakSelf = self;
    [_cookieStore getAllCookies:^(NSArray<NSHTTPCookie *> *cookies) {
        MacLCYouTubeSignInWindowController *strongSelf = weakSelf;
        if (!strongSelf || strongSelf->_finished)
            return;
        MacLCYouTubeSignInSaveHandler handler = strongSelf->_saveHandler;
        if (handler && handler(cookies, avatar)) {
            [strongSelf finishSignedIn:YES closeWindow:YES];
        } else {
            strongSelf->_finalizing = NO;
            [strongSelf->_progress stopAnimation:nil];
            [strongSelf showError:_NS("MacLC couldn't save your sign-in.") failingURL:nil];
        }
    }];
}

#pragma mark Errors

- (void)showError:(NSString *)message failingURL:(NSURL *)url
{
    _failedURL = url;
    _youtubeLoaded = NO;
    _errorLabel.stringValue = message;
    _errorBox.hidden = NO;
    _hostLabel.stringValue = @"";
    _lockView.hidden = YES;
}

- (void)retry:(id)sender
{
    _errorBox.hidden = YES;
    _finalizing = NO;
    NSURL *url = _failedURL;
    _failedURL = nil;
    if (!url || !IsWebURL(url) || !IsAllowedHost(url.host))
        url = SignInURL();
    [_webView loadRequest:[NSURLRequest requestWithURL:url]];
}

- (void)handleFailure:(NSError *)error
{
    [_progress stopAnimation:nil];
    if ([error.domain isEqualToString:NSURLErrorDomain] && error.code == NSURLErrorCancelled)
        return;
    /* "Frame load interrupted": a navigation we sent to the browser instead. */
    if ([error.domain isEqualToString:@"WebKitErrorDomain"] && error.code == 102)
        return;
    NSString *message;
    if ([error.domain isEqualToString:NSURLErrorDomain]) {
        switch (error.code) {
            case NSURLErrorNotConnectedToInternet:
            case NSURLErrorNetworkConnectionLost:
            case NSURLErrorTimedOut:
            case NSURLErrorCannotFindHost:
            case NSURLErrorCannotConnectToHost:
            case NSURLErrorDNSLookupFailed:
                message = _NS("You appear to be offline. Check your connection and try again.");
                break;
            case NSURLErrorSecureConnectionFailed:
            case NSURLErrorServerCertificateHasBadDate:
            case NSURLErrorServerCertificateUntrusted:
            case NSURLErrorServerCertificateHasUnknownRoot:
            case NSURLErrorServerCertificateNotYetValid:
            case NSURLErrorClientCertificateRejected:
            case NSURLErrorClientCertificateRequired:
                message = _NS("MacLC couldn't make a secure connection to Google.");
                break;
        }
    }
    if (!message)
        message = _NS("The sign-in page couldn't be loaded.");
    NSURL *failing = error.userInfo[NSURLErrorFailingURLErrorKey];
    [self showError:message failingURL:[failing isKindOfClass:NSURL.class] ? failing : nil];
}

#pragma mark WKNavigationDelegate

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction
decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler
{
    NSURL *url = navigationAction.request.URL;
    if (navigationAction.targetFrame && !navigationAction.targetFrame.mainFrame) {
        decisionHandler(WKNavigationActionPolicyAllow);
    } else if ([url.scheme.lowercaseString isEqualToString:@"about"]) {
        decisionHandler(WKNavigationActionPolicyAllow);
    } else if (IsWebURL(url) && IsAllowedHost(url.host)) {
        decisionHandler(WKNavigationActionPolicyAllow);
    } else {
        if (IsWebURL(url))
            [NSWorkspace.sharedWorkspace openURL:url];
        decisionHandler(WKNavigationActionPolicyCancel);
    }
}

- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation
{
    _youtubeLoaded = NO;
    _errorBox.hidden = YES;
    [_progress startAnimation:nil];
}

- (void)webView:(WKWebView *)webView didCommitNavigation:(WKNavigation *)navigation
{
    if (_finalizing)
        return;
    NSURL *url = webView.URL;
    _hostLabel.stringValue = url.host ?: @"";
    _lockView.hidden = ![url.scheme isEqualToString:@"https"];
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation
{
    [_progress stopAnimation:nil];
    _youtubeLoaded = IsYouTubeHost(webView.URL.host);
    [self checkSession];
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error
{
    [self handleFailure:error];
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error
{
    [self handleFailure:error];
}

- (void)webViewWebContentProcessDidTerminate:(WKWebView *)webView
{
    [self showError:_NS("The sign-in page stopped responding.") failingURL:webView.URL];
}

#pragma mark WKUIDelegate

/* target=_blank and window.open load in the same view (or in the browser when
 * they leave Google and YouTube). */
- (WKWebView *)webView:(WKWebView *)webView createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration
   forNavigationAction:(WKNavigationAction *)navigationAction windowFeatures:(WKWindowFeatures *)windowFeatures
{
    NSURL *url = navigationAction.request.URL;
    if (IsWebURL(url)) {
        if (IsAllowedHost(url.host))
            [webView loadRequest:navigationAction.request];
        else
            [NSWorkspace.sharedWorkspace openURL:url];
    }
    return nil;
}

@end
