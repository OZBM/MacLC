/*****************************************************************************
 * MacLCLibrarySectionViewController.m: base of every native library section
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

#import "medialib/sections/MacLCLibrarySectionViewController.h"

#import "theme/MacLCDesign.h"
#import "extensions/NSString+Helpers.h"

NSNotificationName const MacLCLibrarySectionChromeDidChangeNotification = @"MacLCLibrarySectionChromeDidChangeNotification";

@interface MacLCLibrarySectionViewController ()
{
    NSInteger _segmentType;
    MacLCLibraryViewMode _viewMode;
    NSMutableArray<NSViewController *> *_viewControllerStack;
    NSMapTable<NSViewController *, NSResponder *> *_savedFirstResponders;
}
@end

@implementation MacLCLibrarySectionViewController

- (instancetype)initWithSegmentType:(NSInteger)segmentType
{
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _segmentType = segmentType;
        _viewMode = MacLCLibraryViewModeGrid;
        _viewControllerStack = [NSMutableArray array];
        _savedFirstResponders = [NSMapTable weakToWeakObjectsMapTable];
    }
    return self;
}

- (NSInteger)segmentType
{
    return _segmentType;
}

- (void)loadView
{
    self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 800, 600)];
    self.view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.view.wantsLayer = YES;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    if (_viewControllerStack.count == 0) {
        NSViewController *root = [self makeRootViewControllerForViewMode:_viewMode];
        if (root) {
            [_viewControllerStack addObject:root];
            [self addChildViewController:root];
            root.view.translatesAutoresizingMaskIntoConstraints = NO;
            [self.view addSubview:root.view];
            [NSLayoutConstraint activateConstraints:@[
                [root.view.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
                [root.view.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
                [root.view.topAnchor constraintEqualToAnchor:self.view.topAnchor],
                [root.view.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
            ]];
        }
    } else {
        NSViewController *top = _viewControllerStack.lastObject;
        if (top && top.view.superview != self.view) {
            [self addChildViewController:top];
            top.view.translatesAutoresizingMaskIntoConstraints = NO;
            [self.view addSubview:top.view];
            [NSLayoutConstraint activateConstraints:@[
                [top.view.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
                [top.view.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
                [top.view.topAnchor constraintEqualToAnchor:self.view.topAnchor],
                [top.view.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
            ]];
        }
    }
}

// MARK: - Navigation stack

- (NSViewController *)rootViewController
{
    return _viewControllerStack.firstObject;
}

- (NSViewController *)topViewController
{
    return _viewControllerStack.lastObject;
}

- (BOOL)canGoBack
{
    return _viewControllerStack.count > 1;
}

- (void)goBack
{
    [self popViewController];
}

- (void)pushViewController:(NSViewController *)viewController
{
    if (!viewController) {
        return;
    }

    NSViewController *oldTop = self.topViewController;
    if (oldTop && self.view.window) {
        NSResponder *firstResponder = self.view.window.firstResponder;
        if (firstResponder) {
            [_savedFirstResponders setObject:firstResponder forKey:oldTop];
        }
    }

    [_viewControllerStack addObject:viewController];
    [self addChildViewController:viewController];

    if (!self.isViewLoaded) {
        [self chromeDidChange];
        return;
    }

    viewController.view.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:viewController.view];
    [NSLayoutConstraint activateConstraints:@[
        [viewController.view.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [viewController.view.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [viewController.view.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [viewController.view.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    BOOL reduceMotion = NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion;
    if (reduceMotion || !oldTop || !self.view.window.isVisible) {
        [oldTop.view removeFromSuperview];
        viewController.view.alphaValue = 1.0;
        if (self.view.window) {
            [self.view.window makeFirstResponder:viewController.view];
        }
        [self chromeDidChange];
    } else {
        viewController.view.alphaValue = 0.0;
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = MacLCDesign.motionStandardDuration;
            oldTop.view.animator.alphaValue = 0.0;
            viewController.view.animator.alphaValue = 1.0;
        } completionHandler:^{
            [oldTop.view removeFromSuperview];
            oldTop.view.alphaValue = 1.0;
            if (self.view.window) {
                [self.view.window makeFirstResponder:viewController.view];
            }
        }];
        [self chromeDidChange];
    }
}

- (void)popViewController
{
    if (_viewControllerStack.count <= 1) {
        return;
    }

    NSViewController *oldTop = _viewControllerStack.lastObject;
    [_viewControllerStack removeLastObject];
    NSViewController *newTop = _viewControllerStack.lastObject;

    if (!self.isViewLoaded) {
        [oldTop removeFromParentViewController];
        [self chromeDidChange];
        return;
    }

    newTop.view.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:newTop.view positioned:NSWindowBelow relativeTo:oldTop.view];
    [NSLayoutConstraint activateConstraints:@[
        [newTop.view.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [newTop.view.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [newTop.view.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [newTop.view.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    NSResponder *savedResponder = [_savedFirstResponders objectForKey:newTop];
    [_savedFirstResponders removeObjectForKey:newTop];

    void (^completionBlock)(void) = ^{
        [oldTop.view removeFromSuperview];
        [oldTop removeFromParentViewController];
        if (savedResponder && [savedResponder isKindOfClass:[NSView class]] &&
            [(NSView *)savedResponder isDescendantOf:newTop.view]) {
            [self.view.window makeFirstResponder:savedResponder];
        } else if (self.view.window) {
            [self.view.window makeFirstResponder:newTop.view];
        }
    };

    BOOL reduceMotion = NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion;
    if (reduceMotion || !self.view.window.isVisible) {
        newTop.view.alphaValue = 1.0;
        completionBlock();
        [self chromeDidChange];
    } else {
        newTop.view.alphaValue = 0.0;
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = MacLCDesign.motionStandardDuration;
            oldTop.view.animator.alphaValue = 0.0;
            newTop.view.animator.alphaValue = 1.0;
        } completionHandler:completionBlock];
        [self chromeDidChange];
    }
}

// MARK: - View modes

- (MacLCLibraryViewMode)viewMode
{
    return _viewMode;
}

- (void)setViewMode:(MacLCLibraryViewMode)viewMode
{
    if (_viewMode == viewMode) {
        return;
    }
    _viewMode = viewMode;

    if (!self.isViewLoaded) {
        return;
    }

    NSViewController *oldRoot = _viewControllerStack.firstObject;
    NSViewController *newRoot = [self makeRootViewControllerForViewMode:_viewMode];
    if (!newRoot) {
        return;
    }

    BOOL isRootVisible = (_viewControllerStack.count == 1);
    if (oldRoot) {
        if (isRootVisible) {
            [oldRoot.view removeFromSuperview];
        }
        [oldRoot removeFromParentViewController];
        [_viewControllerStack replaceObjectAtIndex:0 withObject:newRoot];
    } else {
        [_viewControllerStack addObject:newRoot];
    }

    [self addChildViewController:newRoot];
    if (isRootVisible) {
        newRoot.view.translatesAutoresizingMaskIntoConstraints = NO;
        [self.view addSubview:newRoot.view];
        [NSLayoutConstraint activateConstraints:@[
            [newRoot.view.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
            [newRoot.view.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
            [newRoot.view.topAnchor constraintEqualToAnchor:self.view.topAnchor],
            [newRoot.view.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        ]];
    }

    [self chromeDidChange];
}

// MARK: - Chrome

- (NSString *)sectionTitle
{
    if (self.topViewController && self.topViewController != self.rootViewController && self.topViewController.title.length > 0) {
        return self.topViewController.title;
    }
    return @"";
}

- (NSString *)sectionSubtitle
{
    if (self.topViewController != self.rootViewController) {
        return nil;
    }
    return [self currentSubtitle];
}

- (BOOL)supportsViewModes
{
    return [self sectionSupportsViewModes];
}

- (NSMenu *)sortMenu
{
    if (self.topViewController != self.rootViewController) {
        return nil;
    }
    return [self makeSortMenu];
}

- (NSString *)searchPlaceholder
{
    return [self makeSearchPlaceholder];
}

- (void)chromeDidChange
{
    [[NSNotificationCenter defaultCenter] postNotificationName:MacLCLibrarySectionChromeDidChangeNotification
                                                        object:self];
}

// MARK: - Actions

- (void)applySearchString:(NSString *)searchString
{
    [self searchStringDidChange:searchString];
}

- (void)showItem:(id<VLCMediaLibraryItemProtocol>)item
{
    NSViewController *detail = [self detailViewControllerForItem:item];
    if (detail) {
        [self pushViewController:detail];
    } else if ([self.rootViewController respondsToSelector:@selector(showItem:)]) {
        [(id)self.rootViewController showItem:item];
    }
}

// MARK: - Subclass hooks

- (NSViewController *)makeRootViewControllerForViewMode:(MacLCLibraryViewMode)viewMode
{
    return [[NSViewController alloc] initWithNibName:nil bundle:nil];
}

- (BOOL)sectionSupportsViewModes
{
    return NO;
}

- (NSMenu *)makeSortMenu
{
    return nil;
}

- (NSString *)makeSearchPlaceholder
{
    NSString *title = self.sectionTitle;
    if (title.length > 0) {
        return [NSString stringWithFormat:_NS("Search %@"), title];
    }
    return _NS("Search");
}

- (NSString *)currentSubtitle
{
    return nil;
}

- (void)searchStringDidChange:(NSString *)searchString
{
    if ([self.topViewController respondsToSelector:@selector(applySearchString:)]) {
        [(id)self.topViewController applySearchString:searchString];
    } else if ([self.rootViewController respondsToSelector:@selector(applySearchString:)]) {
        [(id)self.rootViewController applySearchString:searchString];
    }
}

- (NSViewController *)detailViewControllerForItem:(id<VLCMediaLibraryItemProtocol>)item
{
    return nil;
}

@end
