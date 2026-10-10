/*****************************************************************************
 * MacLCYouTubeSections.m: the YouTube section of the library window: Home,
 * Subscriptions, History, Watch Later, Liked Videos, Playlists, and the
 * feed root view controller
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

#import "youtube/MacLCYouTubeSections.h"
#import "youtube/MacLCYouTubeViews.h"
#import "youtube/MacLCYouTubeAccount.h"
#import "youtube/MacLCYouTubeService.h"
#import "medialib/components/MacLCEmptyStateView.h"
#import "library/VLCLibrarySegment.h"
#import "theme/MacLCDesign.h"
#import "extensions/NSString+Helpers.h"

@interface MacLCYouTubeVideoItem (Placeholder)
- (void)configureAsPlaceholder;
@end

@interface MacLCYouTubeResultRowItem (Placeholder)
- (void)configureAsPlaceholder;
@end

@interface MacLCYouTubePlaylistItem (Placeholder)
- (void)configureAsPlaceholder;
@end

#pragma mark - Feed Header Supplementary View

@interface MacLCYouTubeFeedHeaderView : NSView <NSCollectionViewElement>

@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) MacLCYouTubeAccountButton *accountButton;
@property (nonatomic, strong) MacLCYouTubeChipsBar *chipsBar;

@property (nonatomic, strong) NSLayoutConstraint *withChipsBottomConstraint;
@property (nonatomic, strong) NSLayoutConstraint *withoutChipsBottomConstraint;

@property (nonatomic) BOOL showsChips;

- (void)configureWithTitle:(NSString *)title
                showsChips:(BOOL)showsChips
                chipTitles:(NSArray<NSString *> *)chipTitles
             selectedIndex:(NSInteger)selectedIndex
          selectionHandler:(nullable void (^)(NSInteger index))selectionHandler;

@end

@implementation MacLCYouTubeFeedHeaderView

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;

        _titleLabel = [NSTextField labelWithString:@""];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _titleLabel.font = [NSFont systemFontOfSize:MacLCDesign.largeTitle.pointSize weight:NSFontWeightBold];
        _titleLabel.textColor = MacLCDesign.primaryLabel;
        _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _titleLabel.selectable = NO;
        _titleLabel.accessibilityRole = NSAccessibilityHeadingRole;
        [self addSubview:_titleLabel];

        _accountButton = [[MacLCYouTubeAccountButton alloc] initWithFrame:NSZeroRect];
        _accountButton.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_accountButton];

        _chipsBar = [[MacLCYouTubeChipsBar alloc] initWithFrame:NSZeroRect];
        _chipsBar.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_chipsBar];

        _withChipsBottomConstraint = [_chipsBar.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-8.0];
        _withoutChipsBottomConstraint = [_titleLabel.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-8.0];

        [NSLayoutConstraint activateConstraints:@[
            [_titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:24.0],
            [_titleLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:12.0],
            [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_accountButton.leadingAnchor constant:-16.0],

            [_accountButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-24.0],
            [_accountButton.centerYAnchor constraintEqualToAnchor:_titleLabel.centerYAnchor],

            [_chipsBar.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:24.0],
            [_chipsBar.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-24.0],
            [_chipsBar.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:12.0],
            [_chipsBar.heightAnchor constraintEqualToConstant:32.0],
        ]];
    }
    return self;
}

- (void)configureWithTitle:(NSString *)title
                showsChips:(BOOL)showsChips
                chipTitles:(NSArray<NSString *> *)chipTitles
             selectedIndex:(NSInteger)selectedIndex
          selectionHandler:(nullable void (^)(NSInteger index))selectionHandler
{
    _titleLabel.stringValue = title ?: @"";
    _showsChips = showsChips;
    _chipsBar.hidden = !showsChips;

    if (showsChips) {
        _withoutChipsBottomConstraint.active = NO;
        _withChipsBottomConstraint.active = YES;
        _chipsBar.titles = chipTitles;
        _chipsBar.selectedIndex = selectedIndex;
        _chipsBar.selectionHandler = selectionHandler;
    } else {
        _withChipsBottomConstraint.active = NO;
        _withoutChipsBottomConstraint.active = YES;
        _chipsBar.titles = @[];
        _chipsBar.selectionHandler = nil;
    }
}

@end

#pragma mark - MacLCYouTubeFeedViewController Private Interface

@interface MacLCYouTubeFeedViewController () <NSCollectionViewDataSource, NSCollectionViewDelegate>

@property (nonatomic, weak) MacLCYouTubeSectionViewController *section;
@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, strong) NSCollectionView *collectionView;
@property (nonatomic, strong, nullable) MacLCEmptyStateView *emptyStateView;

/* Data and state */
@property (nonatomic, copy) NSArray<MacLCYouTubeVideo *> *videos;
@property (nonatomic, copy) NSArray<MacLCYouTubePlaylist *> *playlists;
@property (nonatomic, copy) NSArray<MacLCYouTubeResult *> *searchResults;
@property (nonatomic, strong, nullable) MacLCYouTubePage *currentPage;

@property (nonatomic) BOOL isSearchMode;
@property (nonatomic, copy, nullable) NSString *currentSearchQuery;
@property (nonatomic) MacLCYouTubeSearchFilter currentSearchFilter;
@property (nonatomic) NSPoint savedScrollOrigin;

@property (nonatomic) NSInteger selectedCategoryIndex;
@property (nonatomic, strong, nullable) MacLCYouTubeCategory *currentCategory;

@property (nonatomic) NSUInteger currentLimit;
@property (nonatomic) BOOL isLoading;
@property (nonatomic) BOOL isLoadingMore;
@property (nonatomic, strong, nullable) MacLCYouTubeRequest *inFlightRequest;
@property (nonatomic, strong, nullable) NSTimer *searchDebounceTimer;

@end

#pragma mark - MacLCYouTubeFeedViewController Implementation

@implementation MacLCYouTubeFeedViewController

- (instancetype)initWithSection:(MacLCYouTubeSectionViewController *)section
{
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _section = section;
        _currentLimit = 36;
        _selectedCategoryIndex = 0;
        _currentSearchFilter = MacLCYouTubeSearchFilterAll;
        _videos = @[];
        _playlists = @[];
        _searchResults = @[];
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_searchDebounceTimer invalidate];
    [_inFlightRequest cancel];
}

- (void)loadView
{
    NSView *rootView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 1100, 700)];
    rootView.wantsLayer = YES;

    __weak typeof(self) weakSelf = self;
    NSCollectionViewCompositionalLayout *layout =
        [[NSCollectionViewCompositionalLayout alloc] initWithSectionProvider:^NSCollectionLayoutSection * _Nullable(NSInteger sectionIndex, id<NSCollectionLayoutEnvironment> environment) {
        if (weakSelf.isSearchMode) {
            return [MacLCYouTubeLayout resultListSectionWithEnvironment:environment hasHeader:YES];
        } else if (weakSelf.section.feed == MacLCYouTubeFeedPlaylists) {
            return [MacLCYouTubeLayout playlistGridSectionWithEnvironment:environment hasHeader:YES];
        } else {
            return [MacLCYouTubeLayout videoGridSectionWithEnvironment:environment hasHeader:YES];
        }
    }];

    _collectionView = [[NSCollectionView alloc] initWithFrame:rootView.bounds];
    _collectionView.collectionViewLayout = layout;
    _collectionView.dataSource = self;
    _collectionView.delegate = self;
    _collectionView.selectable = YES;
    _collectionView.backgroundColors = @[NSColor.clearColor];

    [_collectionView registerClass:MacLCYouTubeVideoItem.class
             forItemWithIdentifier:MacLCYouTubeVideoItemIdentifier];
    [_collectionView registerClass:MacLCYouTubeResultRowItem.class
             forItemWithIdentifier:MacLCYouTubeResultRowItemIdentifier];
    [_collectionView registerClass:MacLCYouTubePlaylistItem.class
             forItemWithIdentifier:MacLCYouTubePlaylistItemIdentifier];

    [_collectionView registerClass:MacLCYouTubeFeedHeaderView.class
        forSupplementaryViewOfKind:NSCollectionElementKindSectionHeader
                    withIdentifier:@"MacLCYouTubeFeedHeaderIdentifier"];

    _scrollView = [[NSScrollView alloc] initWithFrame:rootView.bounds];
    _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _scrollView.documentView = _collectionView;
    _scrollView.drawsBackground = NO;
    _scrollView.hasVerticalScroller = YES;
    _scrollView.autohidesScrollers = YES;
    [rootView addSubview:_scrollView];

    [NSLayoutConstraint activateConstraints:@[
        [_scrollView.topAnchor constraintEqualToAnchor:rootView.topAnchor],
        [_scrollView.bottomAnchor constraintEqualToAnchor:rootView.bottomAnchor],
        [_scrollView.leadingAnchor constraintEqualToAnchor:rootView.leadingAnchor],
        [_scrollView.trailingAnchor constraintEqualToAnchor:rootView.trailingAnchor],
    ]];

    self.view = rootView;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(accountDidChange:)
                                                 name:MacLCYouTubeAccountDidChangeNotification
                                               object:nil];

    [self loadInitialContent];
}

- (void)accountDidChange:(NSNotification *)note
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [[MacLCYouTubeService sharedService] invalidateCache];
        [self loadInitialContent];
    });
}

#pragma mark - Content Loading

- (void)loadInitialContent
{
    [_inFlightRequest cancel];
    _inFlightRequest = nil;

    _isLoading = YES;
    _isLoadingMore = NO;
    _currentLimit = 36;
    [self removeEmptyStateView];
    [_collectionView reloadData];

    __weak typeof(self) weakSelf = self;
    MacLCYouTubePageCompletion completion = ^(MacLCYouTubePage * _Nullable page, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf handlePageResponse:page error:error isAppend:NO];
        });
    };

    if (self.section.isHome) {
        _inFlightRequest = [[MacLCYouTubeService sharedService] homeForCategory:_currentCategory
                                                                          limit:_currentLimit
                                                                     completion:completion];
    } else {
        _inFlightRequest = [[MacLCYouTubeService sharedService] feed:self.section.feed
                                                               limit:_currentLimit
                                                          completion:completion];
    }
}

- (void)loadMoreContent
{
    if (_isLoading || _isLoadingMore || !_currentPage.mayHaveMore) {
        return;
    }

    _isLoadingMore = YES;
    const NSUInteger nextLimit = _currentLimit + 36;

    __weak typeof(self) weakSelf = self;
    MacLCYouTubePageCompletion completion = ^(MacLCYouTubePage * _Nullable page, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            weakSelf.isLoadingMore = NO;
            if (error == nil && page != nil) {
                weakSelf.currentLimit = nextLimit;
                [weakSelf handlePageResponse:page error:nil isAppend:YES];
            }
        });
    };

    if (_isSearchMode) {
        _inFlightRequest = [[MacLCYouTubeService sharedService] search:_currentSearchQuery ?: @""
                                                                filter:_currentSearchFilter
                                                                 limit:nextLimit
                                                            completion:completion];
    } else if (self.section.isHome) {
        _inFlightRequest = [[MacLCYouTubeService sharedService] homeForCategory:_currentCategory
                                                                          limit:nextLimit
                                                                     completion:completion];
    } else {
        _inFlightRequest = [[MacLCYouTubeService sharedService] feed:self.section.feed
                                                               limit:nextLimit
                                                          completion:completion];
    }
}

- (void)handlePageResponse:(nullable MacLCYouTubePage *)page error:(nullable NSError *)error isAppend:(BOOL)isAppend
{
    _isLoading = NO;
    _inFlightRequest = nil;

    if (error != nil) {
        if (!isAppend) {
            /* The state replaces the content: nothing of the previous list stays
             * under it (the header with the account button stays). */
            _videos = @[];
            _playlists = @[];
            _searchResults = @[];
            _currentPage = nil;
            [self showEmptyStateForError:error];
            [_collectionView reloadData];
        }
        return;
    }

    if (page == nil) {
        return;
    }

    _currentPage = page;

    if (_isSearchMode) {
        if (isAppend) {
            [self appendSearchResults:page.results];
        } else {
            _searchResults = page.results ?: @[];
        }
        if (_searchResults.count == 0) {
            [self showEmptyStateWithSymbol:@"magnifyingglass" title:_NS("Nothing Here Yet") message:nil];
        } else {
            [self removeEmptyStateView];
        }
    } else if (self.section.feed == MacLCYouTubeFeedPlaylists) {
        NSMutableArray<MacLCYouTubePlaylist *> *list = [NSMutableArray array];
        for (MacLCYouTubeResult *res in page.results) {
            if (res.playlist != nil) {
                [list addObject:res.playlist];
            }
        }
        if (isAppend) {
            [self appendPlaylists:list];
        } else {
            _playlists = [list copy];
        }
        if (_playlists.count == 0) {
            [self showEmptyStateWithSymbol:@"tray" title:_NS("Nothing Here Yet") message:nil];
        } else {
            [self removeEmptyStateView];
        }
    } else {
        if (isAppend) {
            [self appendVideos:page.videos];
        } else {
            _videos = page.videos ?: @[];
        }
        if (_videos.count == 0) {
            [self showEmptyStateWithSymbol:@"tray" title:_NS("Nothing Here Yet") message:nil];
        } else {
            [self removeEmptyStateView];
        }
    }

    [_collectionView reloadData];
}

- (void)appendVideos:(NSArray<MacLCYouTubeVideo *> *)newVideos
{
    NSMutableSet<NSString *> *existingIDs = [NSMutableSet set];
    for (MacLCYouTubeVideo *v in _videos) {
        if (v.identifier.length > 0) [existingIDs addObject:v.identifier];
    }
    NSMutableArray<MacLCYouTubeVideo *> *updated = [_videos mutableCopy];
    for (MacLCYouTubeVideo *v in newVideos) {
        if (v.identifier.length > 0 && ![existingIDs containsObject:v.identifier]) {
            [updated addObject:v];
            [existingIDs addObject:v.identifier];
        }
    }
    _videos = [updated copy];
}

- (void)appendPlaylists:(NSArray<MacLCYouTubePlaylist *> *)newPlaylists
{
    NSMutableSet<NSString *> *existingIDs = [NSMutableSet set];
    for (MacLCYouTubePlaylist *p in _playlists) {
        if (p.identifier.length > 0) [existingIDs addObject:p.identifier];
    }
    NSMutableArray<MacLCYouTubePlaylist *> *updated = [_playlists mutableCopy];
    for (MacLCYouTubePlaylist *p in newPlaylists) {
        if (p.identifier.length > 0 && ![existingIDs containsObject:p.identifier]) {
            [updated addObject:p];
            [existingIDs addObject:p.identifier];
        }
    }
    _playlists = [updated copy];
}

- (void)appendSearchResults:(NSArray<MacLCYouTubeResult *> *)newResults
{
    _searchResults = [_searchResults arrayByAddingObjectsFromArray:newResults ?: @[]];
}

#pragma mark - Search Handling

- (void)applySearchString:(NSString *)searchString
{
    [_searchDebounceTimer invalidate];
    _searchDebounceTimer = nil;

    NSString * const trimmed = [searchString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    if (trimmed.length < 2) {
        if (_isSearchMode) {
            [_inFlightRequest cancel];
            _inFlightRequest = nil;
            _isSearchMode = NO;
            _currentSearchQuery = nil;
            _searchResults = @[];
            [self removeEmptyStateView];
            [_collectionView.collectionViewLayout invalidateLayout];
            [_collectionView reloadData];
            [_scrollView.contentView scrollPoint:_savedScrollOrigin];
        }
        return;
    }

    if (!_isSearchMode) {
        _savedScrollOrigin = _scrollView.contentView.bounds.origin;
        _isSearchMode = YES;
        _currentSearchFilter = MacLCYouTubeSearchFilterAll;
        [_collectionView.collectionViewLayout invalidateLayout];
    }

    _currentSearchQuery = [trimmed copy];

    /* 600 ms debounce after keystroke */
    __weak typeof(self) weakSelf = self;
    _searchDebounceTimer = [NSTimer scheduledTimerWithTimeInterval:0.6
                                                           repeats:NO
                                                             block:^(NSTimer * _Nonnull timer) {
        [weakSelf executeSearch];
    }];
}

- (void)executeSearch
{
    if (_currentSearchQuery.length < 2) {
        return;
    }

    [_inFlightRequest cancel];
    _inFlightRequest = nil;

    _isLoading = YES;
    _isLoadingMore = NO;
    _currentLimit = 36;
    [self removeEmptyStateView];
    [_collectionView reloadData];

    __weak typeof(self) weakSelf = self;
    _inFlightRequest = [[MacLCYouTubeService sharedService] search:_currentSearchQuery
                                                            filter:_currentSearchFilter
                                                             limit:_currentLimit
                                                        completion:^(MacLCYouTubePage * _Nullable page, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf handlePageResponse:page error:error isAppend:NO];
        });
    }];
}

#pragma mark - Empty & Error States

- (void)removeEmptyStateView
{
    if (_emptyStateView != nil) {
        [_emptyStateView removeFromSuperview];
        _emptyStateView = nil;
    }
}

- (void)showEmptyStateForError:(NSError *)error
{
    [self removeEmptyStateView];

    __weak typeof(self) weakSelf = self;

    if ([error.domain isEqualToString:MacLCYouTubeErrorDomain]) {
        if (error.code == MacLCYouTubeErrorExtractorMissing) {
            _emptyStateView = [MacLCEmptyStateView emptyStateWithSymbolName:@"exclamationmark.triangle"
                                                                      title:_NS("yt-dlp Is Needed")
                                                                    message:_NS("MacLC uses the free yt-dlp tool to read YouTube. Install it with Homebrew (brew install yt-dlp), then try again.")];
            [_emptyStateView addButtonWithTitle:_NS("Try Again") prominent:YES action:^{
                [weakSelf loadInitialContent];
            }];
            [_emptyStateView addButtonWithTitle:_NS("Copy Install Command") prominent:NO action:^{
                NSPasteboard *pb = [NSPasteboard generalPasteboard];
                [pb clearContents];
                [pb setString:@"brew install yt-dlp" forType:NSPasteboardTypeString];
            }];
            [self attachEmptyStateView];
            return;
        } else if (error.code == MacLCYouTubeErrorSignInRequired) {
            NSString *feedTitle = [self feedDisplayName];
            NSString *title = [NSString stringWithFormat:_NS("Sign In to See Your %@"), feedTitle];
            _emptyStateView = [MacLCEmptyStateView emptyStateWithSymbolName:@"person.crop.circle"
                                                                      title:title
                                                                    message:_NS("MacLC shows your own YouTube when you sign in with Google.")];
            [_emptyStateView addButtonWithTitle:_NS("Sign In with Google…") prominent:YES action:^{
                [[MacLCYouTubeAccount sharedAccount] beginSignInFromWindow:weakSelf.view.window completion:^(BOOL signedIn) {
                    if (signedIn) {
                        [weakSelf loadInitialContent];
                    }
                }];
            }];
            [_emptyStateView addButtonWithTitle:_NS("Use Browser Session…") prominent:NO action:^{
                [weakSelf showBrowserSessionMenu];
            }];
            [self attachEmptyStateView];
            return;
        } else if (error.code == MacLCYouTubeErrorBrowserCookies) {
            _emptyStateView = MacLCYouTubeBrowserCookiesStateView(^NSWindow *{ return weakSelf.view.window; }, ^{
                [weakSelf loadInitialContent];
            });
            [self attachEmptyStateView];
            return;
        } else if (error.code == MacLCYouTubeErrorNetwork) {
            _emptyStateView = [MacLCEmptyStateView emptyStateWithSymbolName:@"wifi.exclamationmark"
                                                                      title:_NS("Can’t Reach YouTube")
                                                                    message:error.localizedDescription ?: _NS("Check your internet connection, then try again.")];
            [_emptyStateView addButtonWithTitle:_NS("Try Again") prominent:YES action:^{
                [weakSelf loadInitialContent];
            }];
            [self attachEmptyStateView];
            return;
        }
    }

    _emptyStateView = [MacLCEmptyStateView emptyStateWithSymbolName:@"exclamationmark.circle"
                                                              title:_NS("Can’t Reach YouTube")
                                                            message:error.localizedDescription ?: _NS("An unexpected error occurred.")];
    [_emptyStateView addButtonWithTitle:_NS("Try Again") prominent:YES action:^{
        [weakSelf loadInitialContent];
    }];
    [self attachEmptyStateView];
}

- (void)showEmptyStateWithSymbol:(NSString *)symbol title:(NSString *)title message:(nullable NSString *)message
{
    [self removeEmptyStateView];
    _emptyStateView = [MacLCEmptyStateView emptyStateWithSymbolName:symbol title:title message:message];
    [self attachEmptyStateView];
}

- (void)attachEmptyStateView
{
    if (_emptyStateView == nil) return;
    _emptyStateView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_emptyStateView];
    [NSLayoutConstraint activateConstraints:@[
        [_emptyStateView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_emptyStateView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [_emptyStateView.widthAnchor constraintLessThanOrEqualToAnchor:self.view.widthAnchor constant:-48.0],
    ]];
}

- (void)showBrowserSessionMenu
{
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Browser Sessions"];
    NSArray<NSString *> *browsers = [MacLCYouTubeAccount availableBrowsers];
    for (NSString *b in browsers) {
        NSString *disp = [MacLCYouTubeAccount displayNameForBrowser:b];
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:_NS("Use %@’s Session"), disp]
                                                      action:@selector(browserSessionSelected:)
                                               keyEquivalent:@""];
        item.target = self;
        item.representedObject = b;
        [menu addItem:item];
    }
    [menu popUpMenuPositioningItem:nil atLocation:NSEvent.mouseLocation inView:nil];
}

- (void)browserSessionSelected:(NSMenuItem *)sender
{
    NSString *browser = sender.representedObject;
    if (browser.length > 0) {
        [[MacLCYouTubeAccount sharedAccount] useBrowserSession:browser];
    }
}

- (NSString *)feedDisplayName
{
    if (self.section.isHome) return _NS("Recommendations");
    switch (self.section.feed) {
        case MacLCYouTubeFeedRecommended: return _NS("Recommendations");
        case MacLCYouTubeFeedSubscriptions: return _NS("Subscriptions");
        case MacLCYouTubeFeedHistory: return _NS("History");
        case MacLCYouTubeFeedWatchLater: return _NS("Watch Later");
        case MacLCYouTubeFeedLiked: return _NS("Liked Videos");
        case MacLCYouTubeFeedPlaylists: return _NS("Playlists");
    }
}

#pragma mark - NSCollectionViewDataSource & Delegate

- (NSInteger)numberOfSectionsInCollectionView:(NSCollectionView *)collectionView
{
    return 1;
}

- (NSInteger)collectionView:(NSCollectionView *)collectionView numberOfItemsInSection:(NSInteger)section
{
    if (_isLoading) {
        return 12; // 12 placeholder skeleton cards
    }
    if (_isSearchMode) {
        return (NSInteger)_searchResults.count;
    }
    if (self.section.feed == MacLCYouTubeFeedPlaylists) {
        return (NSInteger)_playlists.count;
    }
    return (NSInteger)_videos.count;
}

- (NSCollectionViewItem *)collectionView:(NSCollectionView *)collectionView
     itemForRepresentedObjectAtIndexPath:(NSIndexPath *)indexPath
{
    __weak typeof(self) weakSelf = self;
    __weak typeof(self.section) weakSection = self.section;

    if (_isSearchMode) {
        MacLCYouTubeResultRowItem *rowItem =
            [collectionView makeItemWithIdentifier:MacLCYouTubeResultRowItemIdentifier forIndexPath:indexPath];
        if (_isLoading) {
            [rowItem configureAsPlaceholder];
            return rowItem;
        }
        if (indexPath.item < (NSInteger)_searchResults.count) {
            MacLCYouTubeResult *res = _searchResults[indexPath.item];
            [rowItem configureWithResult:res];
            __weak typeof(rowItem) weakRowItem = rowItem;
            rowItem.activationHandler = ^(MacLCYouTubeResult *r) {
                if (r.kind == MacLCYouTubeResultKindVideo && r.video != nil) {
                    [MacLCYouTubeActions playVideo:r.video fromItem:weakRowItem window:weakSelf.view.window];
                } else if (r.kind == MacLCYouTubeResultKindChannel && r.channel != nil) {
                    [weakSection showChannelWithURL:r.channel.URL name:r.channel.name];
                } else if (r.kind == MacLCYouTubeResultKindPlaylist && r.playlist != nil) {
                    [weakSection showPlaylist:r.playlist];
                }
            };
            rowItem.enqueueHandler = ^(MacLCYouTubeVideo *v) {
                [MacLCYouTubeActions enqueueVideo:v];
            };
            rowItem.detailsHandler = ^(MacLCYouTubeVideo *v) {
                [weakSection showDetailsForVideo:v];
            };
            rowItem.channelHandler = ^(MacLCYouTubeVideo *v) {
                if (v.channelURL != nil) {
                    [weakSection showChannelWithURL:v.channelURL name:v.channelName];
                }
            };
        }
        return rowItem;
    }

    if (self.section.feed == MacLCYouTubeFeedPlaylists) {
        MacLCYouTubePlaylistItem *plItem =
            [collectionView makeItemWithIdentifier:MacLCYouTubePlaylistItemIdentifier forIndexPath:indexPath];
        if (_isLoading) {
            [plItem configureAsPlaceholder];
            return plItem;
        }
        if (indexPath.item < (NSInteger)_playlists.count) {
            MacLCYouTubePlaylist *pl = _playlists[indexPath.item];
            [plItem configureWithPlaylist:pl];
            plItem.activationHandler = ^(MacLCYouTubePlaylist *p) {
                [weakSection showPlaylist:p];
            };
        }
        return plItem;
    }

    /* Video grid item */
    MacLCYouTubeVideoItem *videoItem =
        [collectionView makeItemWithIdentifier:MacLCYouTubeVideoItemIdentifier forIndexPath:indexPath];
    if (_isLoading) {
        [videoItem configureAsPlaceholder];
        return videoItem;
    }
    if (indexPath.item < (NSInteger)_videos.count) {
        MacLCYouTubeVideo *vid = _videos[indexPath.item];
        [videoItem configureWithVideo:vid];
        __weak typeof(videoItem) weakVideoItem = videoItem;
        videoItem.activationHandler = ^(MacLCYouTubeVideo *v) {
            [MacLCYouTubeActions playVideo:v fromItem:weakVideoItem window:weakSelf.view.window];
        };
        videoItem.enqueueHandler = ^(MacLCYouTubeVideo *v) {
            [MacLCYouTubeActions enqueueVideo:v];
        };
        videoItem.detailsHandler = ^(MacLCYouTubeVideo *v) {
            [weakSection showDetailsForVideo:v];
        };
        videoItem.channelHandler = ^(MacLCYouTubeVideo *v) {
            if (v.channelURL != nil) {
                [weakSection showChannelWithURL:v.channelURL name:v.channelName];
            }
        };
    }
    return videoItem;
}

- (NSView *)collectionView:(NSCollectionView *)collectionView
viewForSupplementaryElementOfKind:(NSCollectionViewSupplementaryElementKind)kind
               atIndexPath:(NSIndexPath *)indexPath
{
    if ([kind isEqualToString:NSCollectionElementKindSectionHeader]) {
        MacLCYouTubeFeedHeaderView *header =
            [collectionView makeSupplementaryViewOfKind:kind
                                         withIdentifier:@"MacLCYouTubeFeedHeaderIdentifier"
                                           forIndexPath:indexPath];
        [self configureHeaderView:header];
        return header;
    }
    return [[NSView alloc] initWithFrame:NSZeroRect];
}

- (void)configureHeaderView:(MacLCYouTubeFeedHeaderView *)header
{
    __weak typeof(self) weakSelf = self;

    if (_isSearchMode) {
        NSString *title = [NSString stringWithFormat:_NS("Results for “%@”"), _currentSearchQuery ?: @""];
        NSArray<NSString *> *searchChips = @[_NS("All"), _NS("Videos"), _NS("Channels"), _NS("Playlists")];
        [header configureWithTitle:title
                        showsChips:YES
                        chipTitles:searchChips
                     selectedIndex:(NSInteger)_currentSearchFilter
                  selectionHandler:^(NSInteger index) {
            weakSelf.currentSearchFilter = (MacLCYouTubeSearchFilter)index;
            [weakSelf executeSearch];
        }];
        return;
    }

    if (self.section.isHome) {
        NSArray<NSString *> *categoryTitles = [MacLCYouTubeCategory.homeCategories valueForKey:@"title"];
        [header configureWithTitle:_NS("Home")
                        showsChips:YES
                        chipTitles:categoryTitles
                     selectedIndex:_selectedCategoryIndex
                  selectionHandler:^(NSInteger index) {
            weakSelf.selectedCategoryIndex = index;
            NSArray<MacLCYouTubeCategory *> *cats = [MacLCYouTubeCategory homeCategories];
            if (index >= 0 && index < (NSInteger)cats.count) {
                weakSelf.currentCategory = cats[index];
            } else {
                weakSelf.currentCategory = nil;
            }
            [weakSelf loadInitialContent];
        }];
        return;
    }

    [header configureWithTitle:[self feedDisplayName]
                    showsChips:NO
                    chipTitles:@[]
                 selectedIndex:0
              selectionHandler:nil];
}

- (void)collectionView:(NSCollectionView *)collectionView
       willDisplayItem:(NSCollectionViewItem *)item
forRepresentedObjectAtIndexPath:(NSIndexPath *)indexPath
{
    NSInteger totalCount = [self collectionView:collectionView numberOfItemsInSection:0];
    if (indexPath.item >= (totalCount - 4)) {
        [self loadMoreContent];
    }
}

@end

#pragma mark - Section Base Implementation

@implementation MacLCYouTubeSectionViewController

- (BOOL)isHome
{
    return NO;
}

- (MacLCYouTubeFeed)feed
{
    return MacLCYouTubeFeedRecommended;
}

- (NSString *)sectionTitle
{
    if (self.topViewController != self.rootViewController && self.topViewController.title.length > 0) {
        return self.topViewController.title;
    }
    return [self defaultSectionTitle];
}

- (NSString *)defaultSectionTitle
{
    return _NS("YouTube");
}

- (NSString *)searchPlaceholder
{
    return _NS("Search YouTube");
}

- (NSString *)makeSearchPlaceholder
{
    return _NS("Search YouTube");
}

- (BOOL)sectionSupportsViewModes
{
    return NO;
}

- (nullable NSMenu *)makeSortMenu
{
    return nil;
}

- (NSViewController *)makeRootViewControllerForViewMode:(MacLCLibraryViewMode)viewMode
{
    return [[MacLCYouTubeFeedViewController alloc] initWithSection:self];
}

- (void)searchStringDidChange:(NSString *)searchString
{
    if ([self.rootViewController isKindOfClass:[MacLCYouTubeFeedViewController class]]) {
        [(MacLCYouTubeFeedViewController *)self.rootViewController applySearchString:searchString];
    }
}

- (void)showChannelWithURL:(NSURL *)channelURL name:(nullable NSString *)name
{
    MacLCYouTubeChannelViewController *vc =
        [[MacLCYouTubeChannelViewController alloc] initWithSection:self
                                                        channelURL:channelURL
                                                              name:name];
    [self pushViewController:vc];
}

- (void)showPlaylist:(MacLCYouTubePlaylist *)playlist
{
    MacLCYouTubePlaylistViewController *vc =
        [[MacLCYouTubePlaylistViewController alloc] initWithSection:self
                                                           playlist:playlist];
    [self pushViewController:vc];
}

- (void)showDetailsForVideo:(MacLCYouTubeVideo *)video
{
    MacLCYouTubeVideoViewController *vc =
        [[MacLCYouTubeVideoViewController alloc] initWithSection:self
                                                           video:video];
    [self pushViewController:vc];
}

- (void)debugOpen:(NSString *)page
{
    if ([page hasPrefix:@"search="]) {
        NSString *q = [page substringFromIndex:7];
        if ([self.rootViewController isKindOfClass:[MacLCYouTubeFeedViewController class]]) {
            [(MacLCYouTubeFeedViewController *)self.rootViewController applySearchString:q];
        }
    } else if ([page hasPrefix:@"channel="]) {
        NSString *urlStr = [page substringFromIndex:8];
        NSURL *url = [NSURL URLWithString:urlStr];
        if (url != nil) {
            [self showChannelWithURL:url name:nil];
        }
    } else if ([page hasPrefix:@"playlist="]) {
        NSString *urlStr = [page substringFromIndex:9];
        NSURL *url = [NSURL URLWithString:urlStr];
        if (url != nil && url.scheme == nil) {
            url = [NSURL URLWithString:[NSString stringWithFormat:@"https://www.youtube.com/playlist?list=%@", urlStr]];
        }
        if (url != nil) {
            __weak typeof(self) weakSelf = self;
            [[MacLCYouTubeService sharedService] playlist:url limit:36 completion:^(MacLCYouTubePage * _Nullable p, NSError * _Nullable err) {
                if (p.playlist != nil) {
                    [weakSelf showPlaylist:p.playlist];
                }
            }];
        }
    } else if ([page hasPrefix:@"video="]) {
        NSString *vid = [page substringFromIndex:6];
        if (vid.length > 0) {
            MacLCYouTubeVideo *dummyVideo = [[MacLCYouTubeVideo alloc] init];
            @try {
                [dummyVideo setValue:vid forKey:@"identifier"];
                [dummyVideo setValue:[NSURL URLWithString:[NSString stringWithFormat:@"https://www.youtube.com/watch?v=%@", vid]] forKey:@"watchURL"];
                [dummyVideo setValue:vid forKey:@"title"];
            } @catch (NSException *e) {}
            [self showDetailsForVideo:dummyVideo];
        }
    }
}

@end

#pragma mark - Six Section Subclasses

@implementation MacLCYouTubeHomeSectionViewController

- (instancetype)init
{
    return [super initWithSegmentType:VLCLibraryYouTubeHomeSegmentType];
}

- (BOOL)isHome
{
    return YES;
}

- (MacLCYouTubeFeed)feed
{
    return MacLCYouTubeFeedRecommended;
}

- (NSString *)defaultSectionTitle
{
    return _NS("Home");
}

@end

@implementation MacLCYouTubeSubscriptionsSectionViewController

- (instancetype)init
{
    return [super initWithSegmentType:VLCLibraryYouTubeSubscriptionsSegmentType];
}

- (BOOL)isHome
{
    return NO;
}

- (MacLCYouTubeFeed)feed
{
    return MacLCYouTubeFeedSubscriptions;
}

- (NSString *)defaultSectionTitle
{
    return _NS("Subscriptions");
}

@end

@implementation MacLCYouTubeHistorySectionViewController

- (instancetype)init
{
    return [super initWithSegmentType:VLCLibraryYouTubeHistorySegmentType];
}

- (BOOL)isHome
{
    return NO;
}

- (MacLCYouTubeFeed)feed
{
    return MacLCYouTubeFeedHistory;
}

- (NSString *)defaultSectionTitle
{
    return _NS("History");
}

@end

@implementation MacLCYouTubeWatchLaterSectionViewController

- (instancetype)init
{
    return [super initWithSegmentType:VLCLibraryYouTubeWatchLaterSegmentType];
}

- (BOOL)isHome
{
    return NO;
}

- (MacLCYouTubeFeed)feed
{
    return MacLCYouTubeFeedWatchLater;
}

- (NSString *)defaultSectionTitle
{
    return _NS("Watch Later");
}

@end

@implementation MacLCYouTubeLikedSectionViewController

- (instancetype)init
{
    return [super initWithSegmentType:VLCLibraryYouTubeLikedSegmentType];
}

- (BOOL)isHome
{
    return NO;
}

- (MacLCYouTubeFeed)feed
{
    return MacLCYouTubeFeedLiked;
}

- (NSString *)defaultSectionTitle
{
    return _NS("Liked Videos");
}

@end

@implementation MacLCYouTubePlaylistsSectionViewController

- (instancetype)init
{
    return [super initWithSegmentType:VLCLibraryYouTubePlaylistsSegmentType];
}

- (BOOL)isHome
{
    return NO;
}

- (MacLCYouTubeFeed)feed
{
    return MacLCYouTubeFeedPlaylists;
}

- (NSString *)defaultSectionTitle
{
    return _NS("Playlists");
}

@end
