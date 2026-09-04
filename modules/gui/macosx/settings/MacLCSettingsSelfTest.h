// MacLCSettingsSelfTest.h

#import <Cocoa/Cocoa.h>

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#import <vlc_common.h>
#import <vlc_interface.h>

/// Constructs every settings pane and reports what worked, via msg_Info.
/// Diagnostic only: runs from the MACLC_SELFTEST=1 startup hook and is inert
/// otherwise. Returns YES when every pane built cleanly.
@interface MacLCSettingsSelfTest : NSObject
+ (BOOL)runWithIntf:(intf_thread_t *)intf;
@end
