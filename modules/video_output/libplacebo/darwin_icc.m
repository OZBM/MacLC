/*****************************************************************************
 * darwin_icc.m: Darwin screen ICC profile resolver for libplacebo
 *****************************************************************************
 * Copyright (C) 2026 VLC authors and VideoLAN
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation; either version 2.1 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#import <Cocoa/Cocoa.h>
#import <stdatomic.h>
#import <stdlib.h>

#include "darwin_icc.h"

@interface VLCDarwinICCWatcher : NSObject
- (instancetype)initWithView:(NSView *)viewObject;
- (CGDirectDisplayID)displayID;
- (void)requestUpdate;
- (bool)checkAndClearDirty;
- (void)invalidate;
@end

@implementation VLCDarwinICCWatcher {
    __weak NSView *_view;
    atomic_bool _dirty;
    _Atomic CGDirectDisplayID _cachedDisplayID;
    atomic_bool _invalidated;
}

- (instancetype)initWithView:(NSView *)viewObject
{
    self = [super init];
    if (!self)
        return nil;

    atomic_init(&_dirty, false);
    atomic_init(&_invalidated, false);
    atomic_init(&_cachedDisplayID, CGMainDisplayID());
    _view = viewObject;

    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self
           selector:@selector(screenParametersDidChange:)
               name:NSApplicationDidChangeScreenParametersNotification
             object:nil];
    [nc addObserver:self
           selector:@selector(windowDidChangeScreen:)
               name:NSWindowDidChangeScreenNotification
             object:nil];
    [nc addObserver:self
           selector:@selector(windowDidChangeScreenProfile:)
               name:NSWindowDidChangeScreenProfileNotification
             object:nil];

    if ([NSThread isMainThread]) {
        [self updateDisplayIDForcingDirty:NO];
    } else {
        __weak VLCDarwinICCWatcher *weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            VLCDarwinICCWatcher *strongSelf = weakSelf;
            if (strongSelf != nil) {
                [strongSelf updateDisplayIDForcingDirty:NO];
            }
        });
    }

    return self;
}

- (CGDirectDisplayID)resolveDisplayID
{
    NSView *view = _view;
    if (view == nil)
        return CGMainDisplayID();

    NSWindow *window = [view window];
    if (window == nil)
        return CGMainDisplayID();

    NSScreen *screen = [window screen];
    if (screen == nil)
        screen = [NSScreen mainScreen];
    if (screen == nil)
        return CGMainDisplayID();

    NSDictionary *deviceDesc = [screen deviceDescription];
    if (deviceDesc == nil)
        return CGMainDisplayID();

    id screenNumber = [deviceDesc objectForKey:@"NSScreenNumber"];
    if (![screenNumber isKindOfClass:[NSNumber class]])
        return CGMainDisplayID();

    CGDirectDisplayID displayID = (CGDirectDisplayID)[(NSNumber *)screenNumber unsignedIntValue];
    if (displayID == 0)
        return CGMainDisplayID();

    return displayID;
}

- (void)updateDisplayIDForcingDirty:(BOOL)forceDirty
{
    if (atomic_load_explicit(&_invalidated, memory_order_relaxed))
        return;

    CGDirectDisplayID newID = [self resolveDisplayID];
    CGDirectDisplayID oldID = atomic_exchange_explicit(&_cachedDisplayID, newID, memory_order_relaxed);

    if (forceDirty || newID != oldID) {
        atomic_store_explicit(&_dirty, true, memory_order_relaxed);
    }
}

- (bool)checkAndClearDirty
{
    return atomic_exchange_explicit(&_dirty, false, memory_order_relaxed);
}

- (void)screenParametersDidChange:(NSNotification *)notification
{
    [self updateDisplayIDForcingDirty:YES];
}

- (void)windowDidChangeScreen:(NSNotification *)notification
{
    NSView *view = _view;
    if (view == nil)
        return;
    NSWindow *myWindow = [view window];
    if (myWindow != nil && notification.object != nil && notification.object != myWindow)
        return;

    [self updateDisplayIDForcingDirty:NO];
}

- (void)windowDidChangeScreenProfile:(NSNotification *)notification
{
    NSView *view = _view;
    if (view == nil)
        return;
    NSWindow *myWindow = [view window];
    if (myWindow != nil && notification.object != nil && notification.object != myWindow)
        return;

    [self updateDisplayIDForcingDirty:YES];
}

- (CGDirectDisplayID)displayID
{
    return atomic_load_explicit(&_cachedDisplayID, memory_order_relaxed);
}

- (void)requestUpdate
{
    if (atomic_load_explicit(&_invalidated, memory_order_relaxed))
        return;

    if ([NSThread isMainThread]) {
        [self updateDisplayIDForcingDirty:NO];
    } else {
        __weak VLCDarwinICCWatcher *weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            VLCDarwinICCWatcher *strongSelf = weakSelf;
            if (strongSelf != nil) {
                [strongSelf updateDisplayIDForcingDirty:NO];
            }
        });
    }
}

- (void)invalidate
{
    if (atomic_exchange_explicit(&_invalidated, true, memory_order_relaxed))
        return;

    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)dealloc
{
    [self invalidate];
}

@end

struct vlc_placebo_darwin_icc {
    void *watcher;
};

vlc_placebo_darwin_icc *vlc_placebo_darwin_icc_create(void *nsobject)
{
    if (nsobject == NULL)
        return NULL;

    id view = (__bridge id)nsobject;
    if (![view isKindOfClass:[NSView class]])
        return NULL;

    struct vlc_placebo_darwin_icc *icc = malloc(sizeof(*icc));
    if (icc == NULL)
        return NULL;

    VLCDarwinICCWatcher *watcher = [[VLCDarwinICCWatcher alloc] initWithView:(NSView *)view];
    if (watcher == nil) {
        free(icc);
        return NULL;
    }

    icc->watcher = (void *)CFBridgingRetain(watcher);
    return icc;
}

void vlc_placebo_darwin_icc_destroy(vlc_placebo_darwin_icc *icc)
{
    if (icc == NULL)
        return;

    if (icc->watcher != NULL) {
        VLCDarwinICCWatcher *watcher = CFBridgingRelease(icc->watcher);
        [watcher invalidate];
        watcher = nil;
        icc->watcher = NULL;
    }
    free(icc);
}

CGDirectDisplayID vlc_placebo_darwin_icc_get_display_id(vlc_placebo_darwin_icc *icc)
{
    if (icc == NULL || icc->watcher == NULL)
        return CGMainDisplayID();

    VLCDarwinICCWatcher *watcher = (__bridge VLCDarwinICCWatcher *)icc->watcher;
    return [watcher displayID];
}

void vlc_placebo_darwin_icc_request_update(vlc_placebo_darwin_icc *icc)
{
    if (icc == NULL || icc->watcher == NULL)
        return;

    VLCDarwinICCWatcher *watcher = (__bridge VLCDarwinICCWatcher *)icc->watcher;
    [watcher requestUpdate];
}

bool vlc_placebo_darwin_icc_check_and_clear_dirty(vlc_placebo_darwin_icc *icc)
{
    if (icc == NULL || icc->watcher == NULL)
        return false;

    VLCDarwinICCWatcher *watcher = (__bridge VLCDarwinICCWatcher *)icc->watcher;
    return [watcher checkAndClearDirty];
}
