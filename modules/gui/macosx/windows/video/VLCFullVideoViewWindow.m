/*****************************************************************************
 * VLCFullVideoViewWindow.m: MacOS X interface module
 *****************************************************************************
 * Copyright (C) 2023 VLC authors and VideoLAN
 *
 * Authors: Claudio Cambra <developer@claudiocambra.com>
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

#import "VLCFullVideoViewWindow.h"

#import "VLCMainVideoViewController.h"

#import "extensions/NSAnimationContext+VLCAdditions.h"

#import "main/VLCMain.h"

#import "playqueue/VLCPlayerController.h"
#import "playqueue/VLCPlayQueueController.h"

#import "views/VLCUIUnits.h"

#import "windows/video/MacLCVideoFitGeometry.h"

#import <vlc_configuration.h>
#import <vlc_variables.h>

@interface VLCFullVideoViewWindow ()
{
    BOOL _autohideTitlebar;
    NSTimer *_hideTitlebarTimer;
    BOOL _isFadingIn;

    BOOL _videoFitSessionActive;
    NSRect _savedFrame;
    NSSize _savedMinSize;
    NSSize _savedContentMinSize;
    MacLCVideoFitMode _fitMode;
    NSRect _arrangedBounds;
    NSRect _lastExternalFrame;
    /* Counted, not a flag: two fits can animate at once (a new item starts
     * inside the previous animation) and the first completion handler must
     * not declare the second one finished. */
    NSInteger _applyingVideoFrameCount;
    BOOL _userLiveResize;
    BOOL _hasPendingRestoreFrame;
    NSRect _pendingRestoreFrame;
    BOOL _restoringFrame;
    NSRect _restoreTargetFrame;
    NSTimer *_externalResizeTimer;
}
@end

@implementation VLCFullVideoViewWindow

@synthesize nativeVideoSize = _nativeVideoSize;
@synthesize videoFitSessionActive = _videoFitSessionActive;

- (void)setup
{
    [super setup];
    _autohideTitlebar = NO;

    NSNotificationCenter *notificationCenter = NSNotificationCenter.defaultCenter;
    [notificationCenter addObserver:self
                           selector:@selector(shouldShowFullscreenController:)
                               name:VLCVideoWindowShouldShowFullscreenController
                             object:nil];

    [notificationCenter addObserver:self
                           selector:@selector(playerAspectRatioLockChanged:)
                               name:VLCPlayerAspectRatioLockChanged
                             object:nil];

    self.titleVisibility = NSWindowTitleHidden;
    self.styleMask |= NSWindowStyleMaskFullSizeContentView;
    self.ignoresMouseEvents = NO;
    self.acceptsMouseMovedEvents = YES;
}

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [_hideTitlebarTimer invalidate];
    [_externalResizeTimer invalidate];
}

- (void)playerAspectRatioLockChanged:(NSNotification *)aNotification
{
    [self updateVideoAspectConstraint];
}

- (void)stopTitlebarAutohideTimer
{
    [_hideTitlebarTimer invalidate];
}

- (void)startTitlebarAutohideTimer
{
    /* Do nothing if timer is already in place */
    if (_hideTitlebarTimer.valid) {
        return;
    }

    /* Get timeout and make sure it is not lower than 1 second */
    long long timeToKeepVisibleInSec = MAX(var_CreateGetInteger(getIntf(), "mouse-hide-timeout") / 1000, 1);

    _hideTitlebarTimer = [NSTimer scheduledTimerWithTimeInterval:timeToKeepVisibleInSec
                                                          target:self
                                                        selector:@selector(hideTitleBar:)
                                                        userInfo:nil
                                                         repeats:NO];
}

- (void)showTitleBar
{
    [self stopTitlebarAutohideTimer];

    NSView *titlebarView = [self standardWindowButton:NSWindowCloseButton].superview;

    if (!_autohideTitlebar) {
        titlebarView.alphaValue = 1.0f;
        return;
    }

    [NSAnimationContext runAnimationRespectingPreferencesWithDuration:VLCUIUnits.controlsFadeAnimationDuration
                                                              changes:^(NSAnimationContext * const _Nonnull __unused context){
        self->_isFadingIn = YES;
        [titlebarView.animator setAlphaValue:1.0f];
    } completionHandler:^{
        self->_isFadingIn = NO;
        [self startTitlebarAutohideTimer];
    }];
}

- (void)hideTitleBar:(id)sender
{
    [self stopTitlebarAutohideTimer];

    if (self.videoViewController.mouseOnControls ||
        !_autohideTitlebar ||
        self.isInNativeFullscreen ||
        self.videoViewController.view.hidden ||
        !self.videoViewController.autohideControls) {

        [self showTitleBar];
        return;
    }

    NSView *titlebarView = [self standardWindowButton:NSWindowCloseButton].superview;

    [NSAnimationContext runAnimationRespectingPreferencesWithDuration:VLCUIUnits.controlsFadeAnimationDuration
                                                              changes:^(NSAnimationContext * const _Nonnull __unused context) {
        [titlebarView.animator setAlphaValue:0.0f];
    } completionHandler:nil];
}

- (void)enableVideoTitleBarMode
{
    self.toolbar.visible = NO;
    self.titlebarAppearsTransparent = YES;

    _autohideTitlebar = YES;
    [self showTitleBar];
}

- (void)disableVideoTitleBarMode
{
    self.toolbar.visible = YES;
    self.titlebarAppearsTransparent = NO;

    _autohideTitlebar = NO;
    [self showTitleBar];
}

- (void)shouldShowFullscreenController:(NSNotification *)aNotification
{
    [self showTitleBar];
}

- (void)mouseMoved:(NSEvent *)event
{
    [super mouseExited:event];

    NSPoint mouseLocation = [event locationInWindow];

    BOOL mouseOutsideWindow = ![self.contentView mouse:mouseLocation inRect:self.contentView.frame];

    if (_autohideTitlebar && mouseOutsideWindow) {
        [self hideTitleBar:self];
    }

    if (self.videoViewController.autohideControls && mouseOutsideWindow) {
        [self.videoViewController hideControls];
    }
}

#pragma mark - Video Fit Session and Sizing

- (void)setNativeVideoSize:(NSSize)size
{
    NSSize previousSize = _nativeVideoSize;
    _nativeVideoSize = size;

    if (_videoFitSessionActive &&
        size.width > 0. && size.height > 0. &&
        !NSEqualSizes(size, previousSize)) {
        [self updateVideoAspectConstraint];
        [self fitWindowToVideoAnimated:YES];
    }
}

- (NSSize)currentChromeSize
{
    if (self.videoViewController.view == nil || self.videoViewController.view.window != self) {
        return NSZeroSize;
    }
    [self.contentView layoutSubtreeIfNeeded];
    NSSize frameSize = self.frame.size;
    NSSize videoViewSize = self.videoViewController.view.frame.size;
    return NSMakeSize(MAX(0.0, frameSize.width - videoViewSize.width),
                      MAX(0.0, frameSize.height - videoViewSize.height));
}

- (void)beginVideoFitSession
{
    if (_videoFitSessionActive) {
        return;
    }
    _videoFitSessionActive = YES;

    /* A previous session may still be animating back to the frame it saved
     * (the next item started right after the last one ended): keep that
     * frame, not the intermediate one. A restore waiting for a fullscreen
     * exit holds it too, and self.frame is the fullscreen one there. */
    if (_hasPendingRestoreFrame && !NSIsEmptyRect(_pendingRestoreFrame)) {
        _savedFrame = _pendingRestoreFrame;
        _hasPendingRestoreFrame = NO;
        _pendingRestoreFrame = NSZeroRect;
    } else if (_restoringFrame) {
        _savedFrame = _restoreTargetFrame;
    } else {
        _savedFrame = self.frame;
    }
    _savedMinSize = self.minSize;
    _savedContentMinSize = self.contentMinSize;

    NSScreen *screen = self.screen ?: NSScreen.mainScreen;
    NSRect visibleFrame = screen.visibleFrame;

    /* Tiled halves reach two opposite edges of the visible frame; tiled
     * quarters reach one horizontal and one vertical edge and are about half
     * as wide and half as high. Tiled windows may have margins, and a tile
     * can extend under the menu bar, so an edge counts as reached when the
     * frame is within the tolerance of it or beyond it. */
    const CGFloat tolerance = 12.;
    const BOOL touchesLeft = NSMinX(_savedFrame) <= NSMinX(visibleFrame) + tolerance;
    const BOOL touchesRight = NSMaxX(_savedFrame) >= NSMaxX(visibleFrame) - tolerance;
    const BOOL touchesBottom = NSMinY(_savedFrame) <= NSMinY(visibleFrame) + tolerance;
    const BOOL touchesTop = NSMaxY(_savedFrame) >= NSMaxY(visibleFrame) - tolerance;
    const BOOL touchesTopAndBottom = touchesTop && touchesBottom;
    const BOOL touchesLeftAndRight = touchesLeft && touchesRight;
    const BOOL isQuarter = (touchesLeft || touchesRight) && (touchesTop || touchesBottom) &&
        fabs(NSWidth(_savedFrame) - NSWidth(visibleFrame) / 2.) <= 4. * tolerance &&
        fabs(NSHeight(_savedFrame) - NSHeight(visibleFrame) / 2.) <= 4. * tolerance;
    const NSRect arrangedBounds = NSIntersectionRect(_savedFrame, visibleFrame);

    if ((self.isZoomed || touchesTopAndBottom || touchesLeftAndRight || isQuarter)
        && !NSIsEmptyRect(arrangedBounds)) {
        _fitMode = MacLCVideoFitModeArranged;
        _arrangedBounds = arrangedBounds;
        _lastExternalFrame = _savedFrame;
    } else {
        _fitMode = MacLCVideoFitModeNative;
        _arrangedBounds = NSZeroRect;
    }

    self.minSize = NSMakeSize(320., 180.);
    self.contentMinSize = NSMakeSize(320., 180.);

    if (self.nativeVideoSize.width > 0. && self.nativeVideoSize.height > 0.) {
        [self updateVideoAspectConstraint];
        [self fitWindowToVideoAnimated:YES];
    }
}

- (void)endVideoFitSessionRestoringFrame:(BOOL)restoreFrame
{
    if (!_videoFitSessionActive) {
        return;
    }
    _videoFitSessionActive = NO;

    [_externalResizeTimer invalidate];
    _externalResizeTimer = nil;

    self.contentResizeIncrements = NSMakeSize(1., 1.);

    self.minSize = _savedMinSize;
    self.contentMinSize = _savedContentMinSize;

    if (restoreFrame) {
        BOOL isInFS = self.fullscreen || self.isInNativeFullscreen || self.inFullscreenTransition ||
                      ((self.styleMask & NSWindowStyleMaskFullScreen) != 0);
        if (isInFS) {
            _hasPendingRestoreFrame = YES;
            _pendingRestoreFrame = _savedFrame;
        } else if (!self.isVisible || NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion) {
            _applyingVideoFrameCount++;
            [self setFrame:_savedFrame display:YES];
            _applyingVideoFrameCount--;
        } else {
            _applyingVideoFrameCount++;
            _restoringFrame = YES;
            _restoreTargetFrame = _savedFrame;
            const NSRect savedFrame = _savedFrame;
            __weak typeof(self) weakSelf = self;
            [NSAnimationContext runAnimationRespectingPreferencesWithDuration:0.25
                                                                      changes:^(NSAnimationContext * _Nonnull context) {
                [weakSelf.animator setFrame:savedFrame display:YES];
            } completionHandler:^{
                VLCFullVideoViewWindow *strongSelf = weakSelf;
                if (strongSelf) {
                    strongSelf->_applyingVideoFrameCount--;
                    strongSelf->_restoringFrame = NO;
                }
            }];
        }
    } else {
        _hasPendingRestoreFrame = NO;
        _pendingRestoreFrame = NSZeroRect;
    }

    /* nativeVideoSize is kept: the library window can leave video mode while
     * the video keeps playing and come back to it (artwork button). The video
     * output provider clears it when the video output goes away. */
    _fitMode = MacLCVideoFitModeNative;
    _arrangedBounds = NSZeroRect;
}

- (void)updateVideoAspectConstraint
{
    NSSize chromeSize = [self currentChromeSize];
    BOOL chromeIsZero = (chromeSize.width <= 0.001 && chromeSize.height <= 0.001);

    if (_videoFitSessionActive &&
        self.nativeVideoSize.width > 0. && self.nativeVideoSize.height > 0. &&
        self.playerController.aspectRatioIsLocked &&
        chromeIsZero) {
        self.contentAspectRatio = self.nativeVideoSize;
    } else {
        self.contentResizeIncrements = NSMakeSize(1., 1.);
    }
}

- (void)fitWindowToVideoAnimated:(BOOL)animated
{
    /* The interface can be gone when a debounced resize fires during
     * termination. */
    if (!_videoFitSessionActive || getIntf() == NULL) {
        return;
    }
    if (self.nativeVideoSize.width <= 0. || self.nativeVideoSize.height <= 0.) {
        return;
    }
    if (self.fullscreen || self.isInNativeFullscreen || self.inFullscreenTransition ||
        ((self.styleMask & NSWindowStyleMaskFullScreen) != 0)) {
        return;
    }
    if (self.isMiniaturized) {
        return;
    }
    if (self.videoViewController.pipIsActive) {
        return;
    }
    if (var_InheritBool(getIntf(), "video-wallpaper")) {
        return;
    }

    if (!var_InheritBool(getIntf(), "macosx-video-autoresize")) {
        [self updateVideoAspectConstraint];
        return;
    }

    NSSize chromeSize = [self currentChromeSize];

    NSScreen *screen = self.screen ?: NSScreen.mainScreen;
    NSRect visibleFrame = screen.visibleFrame;
    CGFloat scaleFactor = screen.backingScaleFactor > 0.0 ? screen.backingScaleFactor : 1.0;

    const MacLCVideoFitInput fitInput = {
        .nativeVideoSize = self.nativeVideoSize,
        .chromeSize = chromeSize,
        .currentFrame = self.frame,
        .arrangedBounds = _arrangedBounds,
        .visibleFrame = visibleFrame,
        .scaleFactor = scaleFactor,
        .mode = _fitMode,
    };
    if (!MacLCVideoFitInputIsUsable(fitInput)) {
        return;
    }
    NSRect targetFrame = MacLCVideoFitTargetFrame(fitInput);

    targetFrame = [screen backingAlignedRect:targetFrame options:NSAlignAllEdgesNearest];

    const char *modeString = "native";
    if (_fitMode == MacLCVideoFitModeArranged) {
        modeString = "arranged";
    } else if (_fitMode == MacLCVideoFitModeKeepWidth) {
        modeString = "keep-width";
    }

    msg_Dbg(getIntf(), "video fit: mode=%s video=%.0fx%.0f px scale=%.1f chrome=%.0fx%.0f frame=%.0fx%.0f+%.0f+%.0f",
            modeString,
            self.nativeVideoSize.width, self.nativeVideoSize.height,
            scaleFactor,
            chromeSize.width, chromeSize.height,
            targetFrame.size.width, targetFrame.size.height,
            targetFrame.origin.x, targetFrame.origin.y);

    if (NSEqualRects(targetFrame, self.frame)) {
        return;
    }

    /* A window that is not on screen yet (a new detached video window) takes
     * its size at once. */
    BOOL shouldAnimate = animated && self.isVisible &&
        !NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion;
    if (shouldAnimate) {
        _applyingVideoFrameCount++;
        __weak typeof(self) weakSelf = self;
        [NSAnimationContext runAnimationRespectingPreferencesWithDuration:0.25
                                                                  changes:^(NSAnimationContext * _Nonnull context) {
            [weakSelf.animator setFrame:targetFrame display:YES];
        } completionHandler:^{
            VLCFullVideoViewWindow *strongSelf = weakSelf;
            if (strongSelf) {
                strongSelf->_applyingVideoFrameCount--;
            }
        }];
    } else {
        _applyingVideoFrameCount++;
        [self setFrame:targetFrame display:YES];
        _applyingVideoFrameCount--;
    }
}

#pragma mark - Window Delegate & Fullscreen Overrides

- (void)windowWillEnterFullScreen:(NSNotification *)notification
{
    [super windowWillEnterFullScreen:notification];
    self.contentResizeIncrements = NSMakeSize(1., 1.);
}

- (void)windowDidExitFullScreen:(NSNotification *)notification
{
    [super windowDidExitFullScreen:notification];

    if (_hasPendingRestoreFrame) {
        _hasPendingRestoreFrame = NO;
        NSRect frameToRestore = _pendingRestoreFrame;
        _pendingRestoreFrame = NSZeroRect;
        if (!NSEqualRects(frameToRestore, NSZeroRect)) {
            _applyingVideoFrameCount++;
            __weak typeof(self) weakSelf = self;
            [NSAnimationContext runAnimationRespectingPreferencesWithDuration:0.25
                                                                      changes:^(NSAnimationContext * _Nonnull context) {
                [weakSelf.animator setFrame:frameToRestore display:YES];
            } completionHandler:^{
                VLCFullVideoViewWindow *strongSelf = weakSelf;
                if (strongSelf) {
                    strongSelf->_applyingVideoFrameCount--;
                }
            }];
        }
    }

    [self updateVideoAspectConstraint];
}

- (NSSize)windowWillResize:(NSWindow *)window toSize:(NSSize)proposedFrameSize
{
    if (window != self ||
        !_videoFitSessionActive ||
        self.nativeVideoSize.width <= 0. || self.nativeVideoSize.height <= 0. ||
        self.fullscreen || self.isInNativeFullscreen || self.inFullscreenTransition ||
        ((self.styleMask & NSWindowStyleMaskFullScreen) != 0) ||
        self.videoViewController.view == nil || self.videoViewController.view.isHidden ||
        !self.playerController.aspectRatioIsLocked) {
        return proposedFrameSize;
    }

    if (!self.inLiveResize) {
        return proposedFrameSize;
    }

    NSSize chromeSize = [self currentChromeSize];
    if (chromeSize.width <= 0.001 && chromeSize.height <= 0.001) {
        return proposedFrameSize;
    }

    NSSize currentSize = self.frame.size;
    CGFloat currentVideoW = MAX(1.0, currentSize.width - chromeSize.width);
    CGFloat currentVideoH = MAX(1.0, currentSize.height - chromeSize.height);

    CGFloat relChangeW = currentVideoW > 0.0 ? fabs(proposedFrameSize.width - currentSize.width) / currentVideoW : 0.0;
    CGFloat relChangeH = currentVideoH > 0.0 ? fabs(proposedFrameSize.height - currentSize.height) / currentVideoH : 0.0;

    CGFloat aspect = self.nativeVideoSize.width / self.nativeVideoSize.height;

    NSSize resultSize = proposedFrameSize;
    if (relChangeH > relChangeW) {
        CGFloat proposedVideoH = MAX(1.0, proposedFrameSize.height - chromeSize.height);
        CGFloat derivedVideoW = proposedVideoH * aspect;
        resultSize.width = round(derivedVideoW + chromeSize.width);
        resultSize.height = proposedFrameSize.height;
    } else {
        CGFloat proposedVideoW = MAX(1.0, proposedFrameSize.width - chromeSize.width);
        CGFloat derivedVideoH = proposedVideoW / aspect;
        resultSize.height = round(derivedVideoH + chromeSize.height);
        resultSize.width = proposedFrameSize.width;
    }

    /* Whatever we return, the window server clamps each axis to minSize on its
     * own, which would break the ratio we just computed: grow both axes
     * together instead. */
    const NSSize minimum = self.minSize;
    if (minimum.width > 0. && minimum.height > 0.) {
        const CGFloat scaleToMinW = resultSize.width > 0. ? minimum.width / resultSize.width : 1.;
        const CGFloat scaleToMinH = resultSize.height > 0. ? minimum.height / resultSize.height : 1.;
        const CGFloat upScale = MAX(scaleToMinW, scaleToMinH);
        if (upScale > 1.) {
            const CGFloat videoW = MAX(1.0, resultSize.width * upScale - chromeSize.width);
            resultSize.width = round(videoW + chromeSize.width);
            resultSize.height = round(videoW / aspect + chromeSize.height);
        }
    }

    return resultSize;
}

- (void)windowWillStartLiveResize:(NSNotification *)notification
{
    /* Animated frame changes, ours included, also count as live resizes:
     * only a resize we did not start is the user's. */
    _userLiveResize = _applyingVideoFrameCount == 0;

    /* The play queue sidebar may have been shown or hidden since the
     * constraint was set: the whole-window ratio only fits without it. */
    [self updateVideoAspectConstraint];
}

- (void)windowDidEndLiveResize:(NSNotification *)notification
{
    const BOOL userLiveResize = _userLiveResize && _applyingVideoFrameCount == 0;
    _userLiveResize = NO;

    /* With the aspect ratio unlocked, the size the user chose stays as is. */
    if (!userLiveResize || !_videoFitSessionActive ||
        self.nativeVideoSize.width <= 0. || self.nativeVideoSize.height <= 0. ||
        !self.playerController.aspectRatioIsLocked) {
        return;
    }

    _fitMode = MacLCVideoFitModeKeepWidth;
    [self fitWindowToVideoAnimated:NO];
}

- (void)windowDidResize:(NSNotification *)notification
{
    if (!_videoFitSessionActive ||
        self.nativeVideoSize.width <= 0. || self.nativeVideoSize.height <= 0. ||
        self.inLiveResize ||
        _applyingVideoFrameCount > 0) {
        return;
    }

    BOOL isInFS = self.fullscreen || self.isInNativeFullscreen || self.inFullscreenTransition ||
                  ((self.styleMask & NSWindowStyleMaskFullScreen) != 0);
    if (isInFS) {
        return;
    }

    /* The window manager put back the frame we already fitted from: leave it
     * alone rather than fight it. */
    if (_fitMode == MacLCVideoFitModeArranged && NSEqualRects(self.frame, _lastExternalFrame)) {
        return;
    }

    [_externalResizeTimer invalidate];
    _externalResizeTimer = nil;

    __weak typeof(self) weakSelf = self;
    _externalResizeTimer = [NSTimer scheduledTimerWithTimeInterval:0.3
                                                           repeats:NO
                                                             block:^(NSTimer * _Nonnull timer) {
        VLCFullVideoViewWindow *strongSelf = weakSelf;
        if (!strongSelf || !strongSelf->_videoFitSessionActive) {
            return;
        }
        strongSelf->_externalResizeTimer = nil;
        const NSRect frame = strongSelf.frame;
        NSScreen * const screen = strongSelf.screen ?: NSScreen.mainScreen;
        const NSRect bounds = NSIntersectionRect(frame, screen.visibleFrame);
        if (NSIsEmptyRect(bounds)) {
            return;
        }
        strongSelf->_fitMode = MacLCVideoFitModeArranged;
        strongSelf->_arrangedBounds = bounds;
        strongSelf->_lastExternalFrame = frame;
        [strongSelf fitWindowToVideoAnimated:YES];
    }];
}

- (NSRect)windowWillUseStandardFrame:(NSWindow *)window defaultFrame:(NSRect)newFrame
{
    if (!_videoFitSessionActive || self.nativeVideoSize.width <= 0. || self.nativeVideoSize.height <= 0.) {
        return newFrame;
    }

    CGFloat aspect = self.nativeVideoSize.width / self.nativeVideoSize.height;
    NSSize chromeSize = [self currentChromeSize];
    CGFloat availW = MAX(0.0, newFrame.size.width - chromeSize.width);
    CGFloat availH = MAX(0.0, newFrame.size.height - chromeSize.height);

    CGFloat contentW = 0.0;
    CGFloat contentH = 0.0;
    if (availW <= 0.0 || availH <= 0.0) {
        return newFrame;
    } else if (availW / aspect <= availH) {
        contentW = availW;
        contentH = contentW / aspect;
    } else {
        contentH = availH;
        contentW = contentH * aspect;
    }

    NSSize targetSize = NSMakeSize(contentW + chromeSize.width, contentH + chromeSize.height);
    NSRect resultFrame = NSMakeRect(NSMidX(newFrame) - targetSize.width / 2.0,
                                    NSMidY(newFrame) - targetSize.height / 2.0,
                                    targetSize.width,
                                    targetSize.height);

    NSScreen * const screen = self.screen ?: NSScreen.mainScreen;
    resultFrame = [screen backingAlignedRect:resultFrame options:NSAlignAllEdgesNearest];
    return resultFrame;
}

@end
