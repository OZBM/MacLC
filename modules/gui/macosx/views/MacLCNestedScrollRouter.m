/*****************************************************************************
 * MacLCNestedScrollRouter.m: trackpad gestures over shelves inside a page
 *****************************************************************************
 * Copyright (C) 2026 Hazen Studio
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

#import "MacLCNestedScrollRouter.h"

/* A gesture's direction is known once the fingers travelled this far
 * (points), or after this many events, whichever comes first. Until then
 * its events are held: about two frames at most. */
static const CGFloat MacLCNestedScrollDecisionTravel = 4.0;
static const NSUInteger MacLCNestedScrollMaxHeldEvents = 3;

static BOOL MacLCScrollsVertically(NSScrollView *scrollView)
{
    NSView * const document = scrollView.documentView;
    return document != nil
        && NSHeight(document.frame) > NSHeight(scrollView.contentView.bounds) + 0.5;
}

/* The event with the other axis cleared, so that the scroll view it goes to
 * never hands it on along that axis. */
static NSEvent *MacLCEventAlongAxis(NSEvent *event, BOOL horizontal)
{
    CGEventRef const copy = CGEventCreateCopy(event.CGEvent);
    if (copy == NULL)
        return event;
    CGEventSetIntegerValueField(copy, horizontal ? kCGScrollWheelEventDeltaAxis1 : kCGScrollWheelEventDeltaAxis2, 0);
    CGEventSetIntegerValueField(copy, horizontal ? kCGScrollWheelEventPointDeltaAxis1 : kCGScrollWheelEventPointDeltaAxis2, 0);
    CGEventSetDoubleValueField(copy, horizontal ? kCGScrollWheelEventFixedPtDeltaAxis1 : kCGScrollWheelEventFixedPtDeltaAxis2, 0.0);
    NSEvent * const result = [NSEvent eventWithCGEvent:copy];
    CFRelease(copy);
    return result ?: event;
}

@implementation MacLCNestedScrollRouter
{
    NSScrollView *_shelf;   /* nil: the current gesture is left to AppKit */
    NSScrollView *_page;
    NSScrollView *_target;  /* _shelf or _page once the direction is known */
    NSMutableArray<NSEvent *> *_heldEvents;
    CGFloat _travelX;
    CGFloat _travelY;
}

- (instancetype)init
{
    self = [super init];
    if (self)
        _heldEvents = [NSMutableArray array];
    return self;
}

- (void)reset
{
    _shelf = _page = _target = nil;
    [_heldEvents removeAllObjects];
    _travelX = _travelY = 0.0;
}

/* The shelf under the pointer and the page around it, if there is a page. */
- (void)beginGestureWithEvent:(NSEvent *)event inWindow:(NSWindow *)window
{
    [self reset];

    NSView * const root = window.contentView.superview ?: window.contentView;
    NSView *view = [root hitTest:event.locationInWindow];
    while (view != nil && ![view isKindOfClass:NSScrollView.class])
        view = view.superview;
    NSScrollView * const shelf = (NSScrollView *)view;
    if (shelf == nil || MacLCScrollsVertically(shelf))
        return;

    for (view = shelf.superview; view != nil; view = view.superview) {
        if ([view isKindOfClass:NSScrollView.class] && MacLCScrollsVertically((NSScrollView *)view)) {
            _shelf = shelf;
            _page = (NSScrollView *)view;
            return;
        }
    }
}

- (void)deliver:(NSEvent *)event
{
    [_target scrollWheel:MacLCEventAlongAxis(event, _target == _shelf)];
}

- (BOOL)routeScrollEvent:(NSEvent *)event inWindow:(NSWindow *)window
{
    const NSEventPhase phase = event.phase;
    /* A mouse wheel makes no gestures: AppKit's event by event way suits it. */
    if (phase == NSEventPhaseNone && event.momentumPhase == NSEventPhaseNone)
        return NO;

    /* Fingers down: AppKit's delivery stops whatever still glides. */
    if (phase == NSEventPhaseMayBegin) {
        [self reset];
        return NO;
    }
    if (phase == NSEventPhaseBegan)
        [self beginGestureWithEvent:event inWindow:window];
    if (_shelf == nil)
        return NO;
    /* The shelf went away during the gesture (its section was reloaded). */
    if (_shelf.window != window || _page.window != window) {
        [self reset];
        return NO;
    }

    if (_target != nil) {
        [self deliver:event];
        return YES;
    }

    [_heldEvents addObject:event];
    _travelX += event.scrollingDeltaX;
    _travelY += event.scrollingDeltaY;
    const BOOL ending = phase == NSEventPhaseEnded || phase == NSEventPhaseCancelled
        || phase == NSEventPhaseNone;
    if (!ending && hypot(_travelX, _travelY) < MacLCNestedScrollDecisionTravel
        && _heldEvents.count < MacLCNestedScrollMaxHeldEvents)
        return YES;

    /* A tie goes to the page: vertical is the main way through it. */
    _target = fabs(_travelX) > fabs(_travelY) ? _shelf : _page;
    for (NSEvent *held in _heldEvents)
        [self deliver:held];
    [_heldEvents removeAllObjects];
    return YES;
}

@end
