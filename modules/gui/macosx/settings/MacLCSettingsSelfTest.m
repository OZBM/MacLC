// MacLCSettingsSelfTest.m
#import "settings/MacLCSettingsSelfTest.h"
#import "settings/MacLCSettingsWindowController.h"
#import "settings/MacLCSettingsPane.h"
#import <Cocoa/Cocoa.h>

// Helper to recursively count views and NSControl instances
static void countViewsAndControls(NSView *view, NSUInteger *viewCount, NSUInteger *controlCount) {
    if (!view) return;
    (*viewCount)++;
    if ([view isKindOfClass:[NSControl class]]) {
        (*controlCount)++;
    }
    for (NSView *sub in view.subviews) {
        countViewsAndControls(sub, viewCount, controlCount);
    }
}

@implementation MacLCSettingsSelfTest
+ (BOOL)runWithIntf:(intf_thread_t *)intf {
    // Ordered list of pane class names as registered by the window controller
    NSArray<NSString *> *paneClassNames = @[
        @"MacLCGeneralSettingsViewController",
        @"MacLCPlaybackSettingsViewController",
        @"MacLCVideoSettingsViewController",
        @"MacLCHDRSettingsViewController",
        @"MacLCAudioSettingsViewController",
        @"MacLCSubtitlesSettingsViewController",
        @"MacLCInterfaceSettingsViewController",
        @"MacLCShortcutsSettingsViewController"
    ];
    NSUInteger totalPanes = paneClassNames.count;
    NSUInteger okCount = 0;
    NSUInteger failCount = 0;

    for (NSString *className in paneClassNames) {
        @try {
            Class c = NSClassFromString(className);
            if (!c) {
                msg_Info(intf, "MACLC-SELFTEST pane=%s status=FAIL exception=class-not-found: %s", className.UTF8String, "(null)");
                failCount++;
                continue;
            }
            id<MacLCSettingsPane> pane = [[c alloc] initWithIntf:intf];
            // Force view loading and layout
            NSView *v = [(NSViewController *)pane view];
            [v layoutSubtreeIfNeeded];
            // Load settings (may throw)
            [pane loadSettings];
            // Count views and controls
            NSUInteger viewCount = 0, controlCount = 0;
            countViewsAndControls(v, &viewCount, &controlCount);
            // Resolve symbol
            NSString *symbolName = [pane paneSymbolName];
            NSImage *symbolImg = nil;
            if (symbolName) {
                symbolImg = [NSImage imageWithSystemSymbolName:symbolName accessibilityDescription:nil];
            }
            const char *symbolOk = (symbolImg != nil) ? "YES" : "NO";
            const char *titleC = pane.paneTitle ? pane.paneTitle.UTF8String : "(null)";
            msg_Info(intf, "MACLC-SELFTEST pane=%s title=\"%s\" symbol=%s views=%lu controls=%lu status=OK",
                     className.UTF8String, titleC, symbolOk, (unsigned long)viewCount, (unsigned long)controlCount);
            okCount++;
        } @catch (NSException *e) {
            const char *nameC = e.name ? e.name.UTF8String : "(null)";
            const char *reasonC = e.reason ? e.reason.UTF8String : "(null)";
            msg_Info(intf, "MACLC-SELFTEST pane=%s status=FAIL exception=%s: %s", className.UTF8String, nameC, reasonC);
            failCount++;
        }
    }

    // Test window controller construction
    @try {
        MacLCSettingsWindowController *wc = [[MacLCSettingsWindowController alloc] initWithIntf:intf];
        // Touch window property to force loading
        (void)wc.window;
        msg_Info(intf, "MACLC-SELFTEST window status=OK");
    } @catch (NSException *e) {
        const char *nameC = e.name ? e.name.UTF8String : "(null)";
        const char *reasonC = e.reason ? e.reason.UTF8String : "(null)";
        msg_Info(intf, "MACLC-SELFTEST window status=FAIL exception=%s: %s", nameC, reasonC);
        failCount++;
    }

    msg_Info(intf, "MACLC-SELFTEST summary: %lu panes, %lu ok, %lu failed", (unsigned long)totalPanes, (unsigned long)okCount, (unsigned long)failCount);
    return (failCount == 0);
}
@end
