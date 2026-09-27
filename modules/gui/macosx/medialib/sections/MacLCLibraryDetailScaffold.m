/*****************************************************************************
 * MacLCLibraryDetailScaffold.m: layout shared by the library detail screens
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

#import "medialib/sections/MacLCLibraryDetailScaffold.h"

#import "medialib/components/MacLCDetailHeaderView.h"
#import "medialib/data/MacLCLibraryStore.h"

@interface MacLCLibraryDetailScaffold ()
{
    MacLCArtworkShape _shape;
    NSView *_choiceContainer;
    NSView *_bodyContainer;
    NSView *_bodyView;
    NSLayoutConstraint *_choiceHeight;
}
@end

@implementation MacLCLibraryDetailScaffold

- (instancetype)initWithArtworkShape:(MacLCArtworkShape)shape
{
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _shape = shape;
        _headerView = [[MacLCDetailHeaderView alloc] initWithArtworkShape:shape];
    }
    return self;
}

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)loadView
{
    NSView * const root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 800, 600)];

    _headerView.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:_headerView];

    _choiceContainer = [[NSView alloc] initWithFrame:NSZeroRect];
    _choiceContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:_choiceContainer];

    _bodyContainer = [[NSView alloc] initWithFrame:NSZeroRect];
    _bodyContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:_bodyContainer];

    NSBox * const separator = [[NSBox alloc] initWithFrame:NSZeroRect];
    separator.boxType = NSBoxSeparator;
    separator.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:separator];

    _choiceHeight = [_choiceContainer.heightAnchor constraintEqualToConstant:0.0];
    [NSLayoutConstraint activateConstraints:@[
        [_headerView.topAnchor constraintEqualToAnchor:root.safeAreaLayoutGuide.topAnchor],
        [_headerView.leadingAnchor constraintEqualToAnchor:root.safeAreaLayoutGuide.leadingAnchor],
        [_headerView.trailingAnchor constraintEqualToAnchor:root.safeAreaLayoutGuide.trailingAnchor],
        [_choiceContainer.topAnchor constraintEqualToAnchor:_headerView.bottomAnchor],
        [_choiceContainer.leadingAnchor constraintEqualToAnchor:root.safeAreaLayoutGuide.leadingAnchor constant:24.0],
        [_choiceContainer.trailingAnchor constraintEqualToAnchor:root.safeAreaLayoutGuide.trailingAnchor constant:-24.0],
        _choiceHeight,
        [separator.topAnchor constraintEqualToAnchor:_choiceContainer.bottomAnchor constant:4.0],
        [separator.leadingAnchor constraintEqualToAnchor:root.safeAreaLayoutGuide.leadingAnchor],
        [separator.trailingAnchor constraintEqualToAnchor:root.safeAreaLayoutGuide.trailingAnchor],
        [_bodyContainer.topAnchor constraintEqualToAnchor:separator.bottomAnchor],
        [_bodyContainer.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [_bodyContainer.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [_bodyContainer.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],
    ]];
    self.view = root;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(storeDidChange:)
                                               name:MacLCLibraryStoreDidChangeNotification
                                             object:nil];
    [self reloadContents];
}

- (void)storeDidChange:(NSNotification *)notification
{
    [self reloadContents];
}

- (void)setChoiceView:(nullable NSView *)choiceView
{
    [self view];
    [_choiceView removeFromSuperview];
    _choiceView = choiceView;
    if (choiceView == nil) {
        _choiceHeight.constant = 0.0;
        return;
    }
    choiceView.translatesAutoresizingMaskIntoConstraints = NO;
    [_choiceContainer addSubview:choiceView];
    [NSLayoutConstraint activateConstraints:@[
        [choiceView.leadingAnchor constraintEqualToAnchor:_choiceContainer.leadingAnchor],
        [choiceView.centerYAnchor constraintEqualToAnchor:_choiceContainer.centerYAnchor],
        [choiceView.trailingAnchor constraintLessThanOrEqualToAnchor:_choiceContainer.trailingAnchor],
    ]];
    _choiceHeight.constant = 36.0;
}

- (void)setBodyView:(NSView *)bodyView
{
    [self view];
    if (bodyView == _bodyView) {
        return;
    }
    [_bodyView removeFromSuperview];
    _bodyView = bodyView;
    bodyView.translatesAutoresizingMaskIntoConstraints = NO;
    [_bodyContainer addSubview:bodyView];
    [NSLayoutConstraint activateConstraints:@[
        [bodyView.topAnchor constraintEqualToAnchor:_bodyContainer.topAnchor],
        [bodyView.bottomAnchor constraintEqualToAnchor:_bodyContainer.bottomAnchor],
        [bodyView.leadingAnchor constraintEqualToAnchor:_bodyContainer.leadingAnchor],
        [bodyView.trailingAnchor constraintEqualToAnchor:_bodyContainer.trailingAnchor],
    ]];
}

- (void)reloadContents
{
}

- (void)applySearchString:(NSString *)searchString
{
}

@end
