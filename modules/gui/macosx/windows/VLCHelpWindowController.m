/*****************************************************************************
 * HelpWindowController.m
 *****************************************************************************
 * Copyright (C) 2001-2014 VLC authors and VideoLAN
 *
 * Authors: Derk-Jan Hartman <thedj@users.sourceforge.net>
 *          Felix Paul Kühne <fkuehne -at- videolan.org>
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

#import "VLCHelpWindowController.h"

#import <vlc_about.h>

#import "extensions/NSString+Helpers.h"
#import "main/CompatibilityFixes.h"
#import "main/VLCMain.h"
#import "views/VLCScrollingClipView.h"

@implementation VLCHelpWindowController

- (id)init
{
    self = [super initWithWindowNibName:@"Help"];
    if (self) {
        self.windowFrameAutosaveName = @"help";
    }
    return self;
}

- (void)windowDidLoad
{
    self.window.title = _NS("MacLC Help");
    self.window.tabbingMode = NSWindowTabbingModeDisallowed;

    _helpWebView = [[WKWebView alloc] initWithFrame:self.window.contentView.bounds];
    self.helpWebView.navigationDelegate = self;
    self.helpWebView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.window.contentView addSubview:self.helpWebView positioned:NSWindowBelow relativeTo:self.visualEffectView];

    [self.helpWebView.topAnchor constraintEqualToAnchor:self.window.contentView.topAnchor].active = YES;
    [self.helpWebView.bottomAnchor constraintEqualToAnchor:self.visualEffectView.topAnchor].active = YES;
    [self.helpWebView.leadingAnchor constraintEqualToAnchor:self.window.contentView.leadingAnchor].active = YES;
    [self.helpWebView.trailingAnchor constraintEqualToAnchor:self.window.contentView.trailingAnchor].active = YES;

    self.forwardButton.toolTip = _NS("Next");
    self.backButton.toolTip = _NS("Previous");
    self.homeButton.toolTip = _NS("Index");
}

- (void)showHelp
{
    [self showWindow:nil];
    [self helpGoHome:nil];
}

- (IBAction)helpGoHome:(id)sender
{
    NSString * const style = @"<style>body { font-family: -apple-system, Helvetica Neue; }</style>";
    NSString * const help = [NSString stringWithFormat:_NS("<html><head><meta http-equiv=\"Content-Type\" content=\"text/html; charset=utf-8\" /></head><body>"
        "<h2>Welcome to MacLC Help</h2>"
        "<p>MacLC is a media player for macOS, developed by %@.</p>"
        "<h3>Playing media</h3>"
            "<p>Choose <em>File &gt; Open File...</em>, or drag files onto the MacLC window or its Dock icon. "
            "Discs and network streams open from the same <em>File</em> menu.</p>"
        "<h3>Settings and shortcuts</h3>"
            "<p>Choose <em>MacLC &gt; Preferences...</em> to change how MacLC behaves. "
            "Every keyboard shortcut is listed, and can be changed, in the Shortcuts pane.</p>"
        "<h3>Documentation and support</h3>"
            "<p>Documentation, news and support are on the %@ website: <a href=\"%@\">www.hazenstudio.com</a>.</p>"
        "</body></html>"), MacLCDeveloperName, MacLCDeveloperName, MacLCWebsiteURLString];
    NSString * const htmlWithStyle = [style stringByAppendingString:help];
    NSURL * const baseURL = [NSURL URLWithString:MacLCWebsiteURLString];
    [self.helpWebView loadHTMLString:htmlWithStyle baseURL:baseURL];
}

- (IBAction)helpGoBack:(id)sender
{
    [self.helpWebView goBack];
}

- (IBAction)helpGoForward:(id)sender
{
    [self.helpWebView goForward];
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation
{
    /* Update back/forward button states whenever a new page is loaded */
    self.forwardButton.enabled = webView.canGoForward;
    self.backButton.enabled = webView.canGoBack;
    self.progressIndicator.hidden = YES;
    [self.progressIndicator stopAnimation:nil];
}

- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation
{
    self.progressIndicator.hidden = NO;
    [self.progressIndicator startAnimation:nil];
}

@end
