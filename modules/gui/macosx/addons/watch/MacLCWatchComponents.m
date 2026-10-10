/*****************************************************************************
 * MacLCWatchComponents.m: the building blocks of Watch (Home, Movies, TV
 * Shows): posters, the featured carousel, episode cards, images, layouts
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

#import "addons/watch/MacLCWatchComponents.h"

#import <QuartzCore/QuartzCore.h>

#import <vlc_common.h>

#import "addons/MacLCAddons.h"
#import "addons/watch/MacLCWatchLibrary.h"
#import "addons/watch/MacLCWatchLibraryViews.h"
#import "extensions/NSString+Helpers.h"
#import "main/VLCMain.h"
#import "medialib/components/MacLCMediaCardItem.h"
#import "medialib/components/MacLCSectionHeaderView.h"
#import "theme/MacLCDesign.h"

#pragma mark - Facts Line

NSString *MacLCWatchFactsLine(NSString *type,
                              NSArray<NSString *> *genres,
                              NSString * _Nullable releaseInfo,
                              NSString * _Nullable imdbRating)
{
    NSMutableArray<NSString *> * const parts = [NSMutableArray array];

    if (type.length > 0) {
        NSString * const lower = type.lowercaseString;
        if ([lower isEqualToString:@"movie"]) {
            [parts addObject:_NS("Movie")];
        } else if ([lower isEqualToString:@"series"]) {
            [parts addObject:_NS("TV Show")];
        } else {
            [parts addObject:type.capitalizedString];
        }
    }

    if (genres.count > 0 && genres[0].length > 0) {
        [parts addObject:genres[0]];
    }
    if (genres.count > 1 && genres[1].length > 0) {
        [parts addObject:genres[1]];
    }

    if (releaseInfo.length > 0) {
        [parts addObject:releaseInfo];
    }

    if (imdbRating.length > 0) {
        if ([imdbRating containsString:@"★"]) {
            [parts addObject:imdbRating];
        } else {
            [parts addObject:[NSString stringWithFormat:@"★ %@", imdbRating]];
        }
    }

    return [parts componentsJoinedByString:@" · "];
}

#pragma mark - Images

@interface MacLCWatchImageRequest ()
@property (atomic, getter=isCancelled) BOOL cancelled;
@property (nonatomic, strong, nullable) NSURLSessionTask *task;
@property (nonatomic, copy, nullable) void (^completion)(NSImage * _Nullable);
@end

@implementation MacLCWatchImageRequest

- (void)cancel
{
    @synchronized (self) {
        _cancelled = YES;
        [_task cancel];
        _task = nil;
        _completion = nil;
    }
}

@end

@interface MacLCWatchImageCache ()
{
    NSCache<NSString *, NSImage *> *_cache;
    NSURLSession *_session;
}
@end

@implementation MacLCWatchImageCache

+ (MacLCWatchImageCache *)sharedCache
{
    static MacLCWatchImageCache *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _cache = [[NSCache alloc] init];
        _cache.totalCostLimit = 200 * 1024 * 1024; // 200 MB
        NSURLSessionConfiguration * const config = [NSURLSessionConfiguration defaultSessionConfiguration];
        config.requestCachePolicy = NSURLRequestReturnCacheDataElseLoad;
        config.timeoutIntervalForRequest = 20.0;
        _session = [NSURLSession sessionWithConfiguration:config];
    }
    return self;
}

- (nullable NSImage *)imageForURL:(NSURL *)url
                        pointSize:(NSSize)pointSize
                            scale:(CGFloat)scale
                          request:(MacLCWatchImageRequest * _Nullable * _Nullable)outRequest
                       completion:(void (^)(NSImage * _Nullable image))completion
{
    if (url == nil) {
        if (outRequest != NULL) {
            *outRequest = nil;
        }
        return nil;
    }

    const CGFloat effectiveScale = scale > 0.0 ? scale : 2.0;
    const CGFloat pixelWidth = ceil(pointSize.width * effectiveScale);
    const CGFloat pixelHeight = ceil(pointSize.height * effectiveScale);
    NSString * const cacheKey = [NSString stringWithFormat:@"%@#%.0fx%.0f", url.absoluteString, pixelWidth, pixelHeight];

    NSImage * const cached = [_cache objectForKey:cacheKey];
    if (cached != nil) {
        if (outRequest != NULL) {
            *outRequest = nil;
        }
        return cached;
    }

    MacLCWatchImageRequest * const request = [[MacLCWatchImageRequest alloc] init];
    request.completion = completion;
    if (outRequest != NULL) {
        *outRequest = request;
    }

    void (^deliver)(NSImage * _Nullable) = ^(NSImage * _Nullable image) {
        dispatch_async(dispatch_get_main_queue(), ^{
            void (^comp)(NSImage *) = nil;
            @synchronized (request) {
                if (!request.isCancelled) {
                    comp = request.completion;
                    request.completion = nil;
                }
            }
            if (comp != nil) {
                comp(image);
            }
        });
    };

    void (^decodeBlock)(NSData * _Nullable) = ^(NSData * _Nullable data) {
        if (request.isCancelled) {
            return;
        }
        if (data == nil || data.length == 0) {
            deliver(nil);
            return;
        }

        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            if (request.isCancelled) {
                return;
            }

            CGImageSourceRef const source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
            if (source == NULL) {
                deliver(nil);
                return;
            }

            const CGFloat maxPixelSize = MAX(pixelWidth, pixelHeight);
            CGImageRef cgImage = NULL;
            if (maxPixelSize > 0.0) {
                NSDictionary * const downsampleOptions = @{
                    (NSString *)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
                    (NSString *)kCGImageSourceCreateThumbnailWithTransform: @YES,
                    (NSString *)kCGImageSourceShouldCacheImmediately: @YES,
                    (NSString *)kCGImageSourceThumbnailMaxPixelSize: @(maxPixelSize),
                };
                cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)downsampleOptions);
            }
            if (cgImage == NULL) {
                NSDictionary * const fallbackOptions = @{
                    (NSString *)kCGImageSourceShouldCacheImmediately: @YES,
                };
                cgImage = CGImageSourceCreateImageAtIndex(source, 0, (__bridge CFDictionaryRef)fallbackOptions);
            }
            CFRelease(source);

            if (cgImage == NULL || request.isCancelled) {
                if (cgImage != NULL) {
                    CGImageRelease(cgImage);
                }
                deliver(nil);
                return;
            }

            const CGFloat cgWidth = (CGFloat)CGImageGetWidth(cgImage);
            const CGFloat cgHeight = (CGFloat)CGImageGetHeight(cgImage);
            const NSSize drawnSize = NSMakeSize(cgWidth / effectiveScale, cgHeight / effectiveScale);
            NSImage * const decoded = [[NSImage alloc] initWithCGImage:cgImage size:drawnSize];

            NSUInteger cost = (NSUInteger)(CGImageGetBytesPerRow(cgImage) * CGImageGetHeight(cgImage));
            if (cost == 0) {
                cost = (NSUInteger)(cgWidth * cgHeight * 4);
            }
            CGImageRelease(cgImage);

            [self->_cache setObject:decoded forKey:cacheKey cost:cost];
            deliver(decoded);
        });
    };

    if (url.isFileURL) {
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            if (request.isCancelled) {
                return;
            }
            NSData * const fileData = [NSData dataWithContentsOfURL:url options:0 error:nil];
            decodeBlock(fileData);
        });
    } else {
        NSURLSessionDataTask * const task = [_session dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            decodeBlock(data);
        }];
        @synchronized (request) {
            if (!request.isCancelled) {
                request.task = task;
                [task resume];
            }
        }
    }

    return nil;
}

@end

#pragma mark - Layouts

NSString * const MacLCWatchHeaderElementKind = @"MacLCWatchHeaderElementKind";

static const CGFloat MacLCWatchHorizontalInset = 40.0;
static const CGFloat MacLCWatchItemSpacing = 20.0;
static const CGFloat MacLCWatchSectionSpacing = 36.0;
static const CGFloat MacLCWatchRankColumnWidth = 52.0;

/* Shelves hide their scroll bar even with "Show scroll bars: Always" — justified by scroll-views.md (page controls present: chevrons). */
static CGFloat __unused MacLCWatchShelfScrollerAllowance(void)
{
    return 0.0;
}

@implementation MacLCWatchLayout

+ (NSCollectionLayoutBoundarySupplementaryItem *)headerSupplementaryItemWithSubtitle:(BOOL)hasSubtitle
{
    const CGFloat headerHeight = hasSubtitle ? 58.0 : 44.0;
    NSCollectionLayoutSize * const size =
        [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1.0]
                                       heightDimension:[NSCollectionLayoutDimension absoluteDimension:headerHeight]];
    return [NSCollectionLayoutBoundarySupplementaryItem
        boundarySupplementaryItemWithLayoutSize:size
                                    elementKind:MacLCWatchHeaderElementKind
                                      alignment:NSRectAlignmentTop];
}

+ (NSCollectionLayoutBoundarySupplementaryItem *)headerSupplementaryItem
{
    return [self headerSupplementaryItemWithSubtitle:NO];
}

+ (CGFloat)posterItemHeightForWidth:(CGFloat)width
{
    NSFont * const titleFont = [NSFont systemFontOfSize:MacLCDesign.body.pointSize weight:NSFontWeightMedium];
    const CGFloat titleHeight = ceil(titleFont.ascender - titleFont.descender + titleFont.leading);

    NSFont * const subtitleFont = MacLCDesign.subheadline;
    const CGFloat subtitleHeight = ceil(subtitleFont.ascender - subtitleFont.descender + subtitleFont.leading);

    const CGFloat textHeight = titleHeight + 2.0 + subtitleHeight;
    return ceil(width * 1.5) + 8.0 + textHeight;
}

+ (NSCollectionLayoutSection *)posterShelfSectionWithEnvironment:(id<NSCollectionLayoutEnvironment>)environment
{
    return [self posterShelfSectionWithItemWidth:168.0];
}

+ (NSCollectionLayoutSection *)rankedPosterShelfSectionWithEnvironment:(id<NSCollectionLayoutEnvironment>)environment
{
    return [self posterShelfSectionWithItemWidth:168.0 + MacLCWatchRankColumnWidth];
}

+ (NSCollectionLayoutSection *)posterShelfSectionWithItemWidth:(CGFloat)itemWidth
{
    /* The poster is 168 wide in both shelves; a ranked item adds its rank. */
    const CGFloat itemHeight = [self posterItemHeightForWidth:168.0];

    NSCollectionLayoutSize * const itemSize =
        [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension absoluteDimension:itemWidth]
                                       heightDimension:[NSCollectionLayoutDimension absoluteDimension:itemHeight]];
    NSCollectionLayoutItem * const item = [NSCollectionLayoutItem itemWithLayoutSize:itemSize];

    NSCollectionLayoutSize * const groupSize =
        [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension absoluteDimension:itemWidth]
                                       heightDimension:[NSCollectionLayoutDimension absoluteDimension:itemHeight]];
    NSCollectionLayoutGroup * const group =
        [NSCollectionLayoutGroup horizontalGroupWithLayoutSize:groupSize subitems:@[item]];

    NSCollectionLayoutSection * const section = [NSCollectionLayoutSection sectionWithGroup:group];
    section.orthogonalScrollingBehavior = NSCollectionLayoutSectionOrthogonalScrollingBehaviorContinuousGroupLeadingBoundary;
    section.interGroupSpacing = MacLCWatchItemSpacing;
    section.contentInsets = NSDirectionalEdgeInsetsMake(0.0, MacLCWatchHorizontalInset,
                                                        MacLCWatchSectionSpacing, MacLCWatchHorizontalInset);
    section.boundarySupplementaryItems = @[[self headerSupplementaryItem]];
    return section;
}

+ (NSCollectionLayoutSection *)posterGridSectionWithEnvironment:(id<NSCollectionLayoutEnvironment>)environment
                                                      hasHeader:(BOOL)hasHeader
{
    const CGFloat minWidth = 150.0;
    const CGFloat maxWidth = 200.0;
    const CGFloat colSpacing = MacLCWatchItemSpacing;
    const CGFloat rowSpacing = 32.0;
    const CGFloat available = MAX(environment.container.effectiveContentSize.width - 2.0 * MacLCWatchHorizontalInset, minWidth);

    NSInteger columns = MAX(1, (NSInteger)floor((available + colSpacing) / (minWidth + colSpacing)));
    CGFloat itemWidth = (available - (columns - 1) * colSpacing) / columns;
    while (itemWidth > maxWidth) {
        columns += 1;
        itemWidth = (available - (columns - 1) * colSpacing) / columns;
    }
    itemWidth = floor(itemWidth);
    const CGFloat itemHeight = [self posterItemHeightForWidth:itemWidth];

    NSCollectionLayoutSize * const itemSize =
        [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension absoluteDimension:itemWidth]
                                       heightDimension:[NSCollectionLayoutDimension absoluteDimension:itemHeight]];
    NSCollectionLayoutItem * const item = [NSCollectionLayoutItem itemWithLayoutSize:itemSize];

    NSCollectionLayoutSize * const groupSize =
        [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1.0]
                                       heightDimension:[NSCollectionLayoutDimension absoluteDimension:itemHeight]];
    NSCollectionLayoutGroup * const group =
        [NSCollectionLayoutGroup horizontalGroupWithLayoutSize:groupSize subitem:item count:columns];
    group.interItemSpacing = [NSCollectionLayoutSpacing fixedSpacing:colSpacing];

    NSCollectionLayoutSection * const section = [NSCollectionLayoutSection sectionWithGroup:group];
    section.interGroupSpacing = rowSpacing;
    section.contentInsets = NSDirectionalEdgeInsetsMake(16.0, MacLCWatchHorizontalInset,
                                                        MacLCWatchSectionSpacing, MacLCWatchHorizontalInset);
    if (hasHeader) {
        section.boundarySupplementaryItems = @[[self headerSupplementaryItem]];
    }
    return section;
}

+ (NSCollectionLayoutSection *)episodeShelfSectionWithEnvironment:(id<NSCollectionLayoutEnvironment>)environment
{
    const CGFloat itemWidth = 300.0;
    const CGFloat itemHeight = [MacLCWatchEpisodeItem heightForWidth:itemWidth];

    NSCollectionLayoutSize * const itemSize =
        [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension absoluteDimension:itemWidth]
                                       heightDimension:[NSCollectionLayoutDimension absoluteDimension:itemHeight]];
    NSCollectionLayoutItem * const item = [NSCollectionLayoutItem itemWithLayoutSize:itemSize];

    NSCollectionLayoutSize * const groupSize =
        [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension absoluteDimension:itemWidth]
                                       heightDimension:[NSCollectionLayoutDimension absoluteDimension:itemHeight]];
    NSCollectionLayoutGroup * const group =
        [NSCollectionLayoutGroup horizontalGroupWithLayoutSize:groupSize subitems:@[item]];

    NSCollectionLayoutSection * const section = [NSCollectionLayoutSection sectionWithGroup:group];
    section.orthogonalScrollingBehavior = NSCollectionLayoutSectionOrthogonalScrollingBehaviorContinuousGroupLeadingBoundary;
    section.interGroupSpacing = MacLCWatchItemSpacing;
    section.contentInsets = NSDirectionalEdgeInsetsMake(0.0, MacLCWatchHorizontalInset,
                                                        MacLCWatchSectionSpacing, MacLCWatchHorizontalInset);
    section.boundarySupplementaryItems = @[[self headerSupplementaryItem]];
    return section;
}

+ (NSCollectionLayoutSection *)fullWidthSectionWithHeight:(CGFloat)height
{
    NSCollectionLayoutSize * const size =
        [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1.0]
                                       heightDimension:[NSCollectionLayoutDimension absoluteDimension:height]];
    NSCollectionLayoutItem * const item = [NSCollectionLayoutItem itemWithLayoutSize:size];
    NSCollectionLayoutGroup * const group =
        [NSCollectionLayoutGroup horizontalGroupWithLayoutSize:size subitems:@[item]];

    NSCollectionLayoutSection * const section = [NSCollectionLayoutSection sectionWithGroup:group];
    section.contentInsets = NSDirectionalEdgeInsetsZero;
    return section;
}

+ (NSCollectionLayoutSection *)collectionShelfSectionWithEnvironment:(id<NSCollectionLayoutEnvironment>)environment
{
    const CGFloat itemWidth = 340.0;
    const CGFloat itemHeight = 216.0;

    NSCollectionLayoutSize * const itemSize =
        [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension absoluteDimension:itemWidth]
                                       heightDimension:[NSCollectionLayoutDimension absoluteDimension:itemHeight]];
    NSCollectionLayoutItem * const item = [NSCollectionLayoutItem itemWithLayoutSize:itemSize];

    NSCollectionLayoutSize * const groupSize =
        [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension absoluteDimension:itemWidth]
                                       heightDimension:[NSCollectionLayoutDimension absoluteDimension:itemHeight]];
    NSCollectionLayoutGroup * const group =
        [NSCollectionLayoutGroup horizontalGroupWithLayoutSize:groupSize subitems:@[item]];

    NSCollectionLayoutSection * const section = [NSCollectionLayoutSection sectionWithGroup:group];
    section.orthogonalScrollingBehavior = NSCollectionLayoutSectionOrthogonalScrollingBehaviorContinuousGroupLeadingBoundary;
    section.interGroupSpacing = MacLCWatchItemSpacing;
    section.contentInsets = NSDirectionalEdgeInsetsMake(0.0, MacLCWatchHorizontalInset,
                                                        MacLCWatchSectionSpacing, MacLCWatchHorizontalInset);
    section.boundarySupplementaryItems = @[[self headerSupplementaryItemWithSubtitle:YES]];
    return section;
}

+ (NSCollectionLayoutSection *)genreShelfSectionWithEnvironment:(id<NSCollectionLayoutEnvironment>)environment
{
    const CGFloat itemWidth = 196.0;
    const CGFloat itemHeight = 110.0;

    NSCollectionLayoutSize * const itemSize =
        [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension absoluteDimension:itemWidth]
                                       heightDimension:[NSCollectionLayoutDimension absoluteDimension:itemHeight]];
    NSCollectionLayoutItem * const item = [NSCollectionLayoutItem itemWithLayoutSize:itemSize];

    NSCollectionLayoutSize * const groupSize =
        [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension absoluteDimension:itemWidth]
                                       heightDimension:[NSCollectionLayoutDimension absoluteDimension:itemHeight]];
    NSCollectionLayoutGroup * const group =
        [NSCollectionLayoutGroup horizontalGroupWithLayoutSize:groupSize subitems:@[item]];

    NSCollectionLayoutSection * const section = [NSCollectionLayoutSection sectionWithGroup:group];
    section.orthogonalScrollingBehavior = NSCollectionLayoutSectionOrthogonalScrollingBehaviorContinuousGroupLeadingBoundary;
    section.interGroupSpacing = 16.0;
    section.contentInsets = NSDirectionalEdgeInsetsMake(0.0, MacLCWatchHorizontalInset,
                                                        MacLCWatchSectionSpacing, MacLCWatchHorizontalInset);
    section.boundarySupplementaryItems = @[[self headerSupplementaryItemWithSubtitle:NO]];
    return section;
}

+ (NSCollectionLayoutSection *)insetBarSectionWithHeight:(CGFloat)height
{
    NSCollectionLayoutSize * const size =
        [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1.0]
                                       heightDimension:[NSCollectionLayoutDimension absoluteDimension:height]];
    NSCollectionLayoutItem * const item = [NSCollectionLayoutItem itemWithLayoutSize:size];
    NSCollectionLayoutGroup * const group =
        [NSCollectionLayoutGroup horizontalGroupWithLayoutSize:size subitems:@[item]];

    NSCollectionLayoutSection * const section = [NSCollectionLayoutSection sectionWithGroup:group];
    section.contentInsets = NSDirectionalEdgeInsetsMake(0.0, MacLCWatchHorizontalInset,
                                                        MacLCWatchSectionSpacing, MacLCWatchHorizontalInset);
    return section;
}

@end

#pragma mark - Poster Item

NSUserInterfaceItemIdentifier const MacLCWatchPosterItemIdentifier = @"MacLCWatchPosterItemIdentifier";

@interface MacLCWatchPosterItem ()
@property (nonatomic, readwrite, nullable) MacLCAddonItem *addonItem;
@property (nonatomic, assign) NSInteger rank;
- (NSString *)subtitleString;
@end

@interface MacLCWatchPosterView : NSView

@property (nonatomic, weak) MacLCWatchPosterItem *item;
@property (nonatomic, readonly) NSView *posterWrapperView;
@property (nonatomic, readonly) NSView *posterContainerView;
@property (nonatomic, readonly) NSImageView *placeholderImageView;
@property (nonatomic, readonly) NSView *posterImageView;
@property (nonatomic, readonly) MacLCWatchProgressBar *progressBar;
@property (nonatomic, readonly) MacLCWatchedBadge *watchedBadge;
@property (nonatomic, readonly) MacLCWatchFavoriteButton *favoriteButton;
@property (nonatomic, readonly) NSTextField *rankLabel;
@property (nonatomic, readonly) NSTextField *titleLabel;
@property (nonatomic, readonly) NSTextField *subtitleLabel;
@property (nonatomic, readonly) CAShapeLayer *selectionRingLayer;

@property (nonatomic, nullable) NSImage *image;
@property (nonatomic) NSInteger rank;
@property (nonatomic, assign) BOOL isHovered;

- (void)updateHoverState:(BOOL)hovered animated:(BOOL)animated;

@end

@implementation MacLCWatchPosterView
{
    NSTrackingArea *_trackingArea;
    NSLayoutConstraint *_posterLeadingConstraint;
}

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;

        _posterWrapperView = [[NSView alloc] initWithFrame:NSZeroRect];
        _posterWrapperView.translatesAutoresizingMaskIntoConstraints = NO;
        _posterWrapperView.wantsLayer = YES;
        _posterWrapperView.layer.masksToBounds = NO;
        [self addSubview:_posterWrapperView];

        _posterContainerView = [[NSView alloc] initWithFrame:NSZeroRect];
        _posterContainerView.translatesAutoresizingMaskIntoConstraints = NO;
        _posterContainerView.wantsLayer = YES;
        _posterContainerView.layer.masksToBounds = YES;
        _posterContainerView.layer.cornerRadius = MacLCDesign.cornerRadiusMedium;
        _posterContainerView.layer.cornerCurve = kCACornerCurveContinuous;
        _posterContainerView.layer.borderWidth = 1.0;
        _posterContainerView.layer.borderColor = NSColor.separatorColor.CGColor;
        _posterContainerView.layer.backgroundColor = NSColor.quaternarySystemFillColor.CGColor;
        [_posterWrapperView addSubview:_posterContainerView];

        _placeholderImageView = [[NSImageView alloc] initWithFrame:NSZeroRect];
        _placeholderImageView.translatesAutoresizingMaskIntoConstraints = NO;
        _placeholderImageView.imageScaling = NSImageScaleProportionallyUpOrDown;
        _placeholderImageView.contentTintColor = NSColor.tertiaryLabelColor;
        NSImageSymbolConfiguration * const config =
            [NSImageSymbolConfiguration configurationWithPointSize:36.0 weight:NSFontWeightLight];
        NSImage *placeholder = [NSImage imageWithSystemSymbolName:@"film" accessibilityDescription:nil];
        if (placeholder != nil) {
            placeholder = [placeholder imageWithSymbolConfiguration:config];
        }
        _placeholderImageView.image = placeholder;
        [_posterContainerView addSubview:_placeholderImageView];

        _posterImageView = [[NSView alloc] initWithFrame:NSZeroRect];
        _posterImageView.translatesAutoresizingMaskIntoConstraints = NO;
        _posterImageView.wantsLayer = YES;
        _posterImageView.layer.contentsGravity = kCAGravityResizeAspectFill;
        _posterImageView.layer.masksToBounds = YES;
        _posterImageView.hidden = YES;
        [_posterContainerView addSubview:_posterImageView];

        _progressBar = [[MacLCWatchProgressBar alloc] initWithFrame:NSZeroRect];
        _progressBar.translatesAutoresizingMaskIntoConstraints = NO;
        [_posterContainerView addSubview:_progressBar];

        _watchedBadge = [[MacLCWatchedBadge alloc] initWithFrame:NSZeroRect];
        _watchedBadge.translatesAutoresizingMaskIntoConstraints = NO;
        _watchedBadge.hidden = YES;
        [_posterContainerView addSubview:_watchedBadge];

        _favoriteButton = [[MacLCWatchFavoriteButton alloc] initWithFrame:NSZeroRect];
        _favoriteButton.translatesAutoresizingMaskIntoConstraints = NO;
        _favoriteButton.onPicture = YES;
        _favoriteButton.alphaValue = 0.0;
        _favoriteButton.hidden = YES;
        [_posterContainerView addSubview:_favoriteButton];

        _rankLabel = [NSTextField labelWithString:@""];
        _rankLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _rankLabel.textColor = NSColor.labelColor;
        _rankLabel.alignment = NSTextAlignmentRight;
        _rankLabel.selectable = NO;
        _rankLabel.hidden = YES;

        NSFontDescriptor * const baseDesc = [NSFont systemFontOfSize:80.0 weight:NSFontWeightHeavy].fontDescriptor;
        NSFontDescriptor * const roundedDesc = [baseDesc fontDescriptorWithDesign:NSFontDescriptorSystemDesignRounded];
        _rankLabel.font = [NSFont fontWithDescriptor:roundedDesc size:80.0] ?: [NSFont systemFontOfSize:80.0 weight:NSFontWeightHeavy];
        /* Behind the poster, which overlaps its last digit a little. */
        [self addSubview:_rankLabel positioned:NSWindowBelow relativeTo:_posterWrapperView];

        _selectionRingLayer = [CAShapeLayer layer];
        _selectionRingLayer.fillColor = nil;
        _selectionRingLayer.strokeColor = MacLCDesign.accent.CGColor;
        _selectionRingLayer.lineWidth = 3.0;
        _selectionRingLayer.hidden = YES;
        [_posterWrapperView.layer addSublayer:_selectionRingLayer];

        _titleLabel = [NSTextField labelWithString:@""];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _titleLabel.font = [NSFont systemFontOfSize:MacLCDesign.body.pointSize weight:NSFontWeightMedium];
        _titleLabel.textColor = MacLCDesign.primaryLabel;
        _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _titleLabel.maximumNumberOfLines = 1;
        _titleLabel.selectable = NO;
        [self addSubview:_titleLabel];

        _subtitleLabel = [NSTextField labelWithString:@""];
        _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _subtitleLabel.font = MacLCDesign.subheadline;
        _subtitleLabel.textColor = MacLCDesign.secondaryLabel;
        _subtitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _subtitleLabel.maximumNumberOfLines = 1;
        _subtitleLabel.selectable = NO;
        [self addSubview:_subtitleLabel];

        _posterLeadingConstraint = [_posterWrapperView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor];
        [NSLayoutConstraint activateConstraints:@[
            [_posterWrapperView.topAnchor constraintEqualToAnchor:self.topAnchor],
            _posterLeadingConstraint,
            [_posterWrapperView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_posterWrapperView.heightAnchor constraintEqualToAnchor:_posterWrapperView.widthAnchor multiplier:1.5],

            [_posterContainerView.topAnchor constraintEqualToAnchor:_posterWrapperView.topAnchor],
            [_posterContainerView.bottomAnchor constraintEqualToAnchor:_posterWrapperView.bottomAnchor],
            [_posterContainerView.leadingAnchor constraintEqualToAnchor:_posterWrapperView.leadingAnchor],
            [_posterContainerView.trailingAnchor constraintEqualToAnchor:_posterWrapperView.trailingAnchor],

            [_placeholderImageView.centerXAnchor constraintEqualToAnchor:_posterContainerView.centerXAnchor],
            [_placeholderImageView.centerYAnchor constraintEqualToAnchor:_posterContainerView.centerYAnchor],
            [_placeholderImageView.widthAnchor constraintEqualToConstant:40.0],
            [_placeholderImageView.heightAnchor constraintEqualToConstant:40.0],

            [_posterImageView.topAnchor constraintEqualToAnchor:_posterContainerView.topAnchor],
            [_posterImageView.bottomAnchor constraintEqualToAnchor:_posterContainerView.bottomAnchor],
            [_posterImageView.leadingAnchor constraintEqualToAnchor:_posterContainerView.leadingAnchor],
            [_posterImageView.trailingAnchor constraintEqualToAnchor:_posterContainerView.trailingAnchor],

            [_progressBar.leadingAnchor constraintEqualToAnchor:_posterContainerView.leadingAnchor],
            [_progressBar.trailingAnchor constraintEqualToAnchor:_posterContainerView.trailingAnchor],
            [_progressBar.bottomAnchor constraintEqualToAnchor:_posterContainerView.bottomAnchor],
            [_progressBar.heightAnchor constraintEqualToConstant:4.0],

            [_watchedBadge.trailingAnchor constraintEqualToAnchor:_posterContainerView.trailingAnchor constant:-8.0],
            [_watchedBadge.bottomAnchor constraintEqualToAnchor:_posterContainerView.bottomAnchor constant:-8.0],
            [_watchedBadge.widthAnchor constraintEqualToConstant:24.0],
            [_watchedBadge.heightAnchor constraintEqualToConstant:24.0],

            [_favoriteButton.trailingAnchor constraintEqualToAnchor:_posterContainerView.trailingAnchor constant:-6.0],
            [_favoriteButton.topAnchor constraintEqualToAnchor:_posterContainerView.topAnchor constant:6.0],
            [_favoriteButton.widthAnchor constraintEqualToConstant:28.0],
            [_favoriteButton.heightAnchor constraintEqualToConstant:28.0],

            [_rankLabel.trailingAnchor constraintEqualToAnchor:_posterWrapperView.leadingAnchor constant:10.0],
            [_rankLabel.lastBaselineAnchor constraintEqualToAnchor:_posterWrapperView.bottomAnchor],

            [_titleLabel.topAnchor constraintEqualToAnchor:_posterWrapperView.bottomAnchor constant:8.0],
            [_titleLabel.leadingAnchor constraintEqualToAnchor:_posterWrapperView.leadingAnchor],
            [_titleLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],

            [_subtitleLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:2.0],
            [_subtitleLabel.leadingAnchor constraintEqualToAnchor:_posterWrapperView.leadingAnchor],
            [_subtitleLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        ]];
    }
    return self;
}

- (void)viewDidChangeEffectiveAppearance
{
    [super viewDidChangeEffectiveAppearance];
    _posterContainerView.layer.borderColor = NSColor.separatorColor.CGColor;
    _posterContainerView.layer.backgroundColor = NSColor.quaternarySystemFillColor.CGColor;
    _selectionRingLayer.strokeColor = MacLCDesign.accent.CGColor;
}

- (void)layout
{
    [super layout];

    const NSRect ringRect = NSInsetRect(_posterContainerView.bounds, -4.5, -4.5);
    const CGFloat cornerR = MacLCDesign.cornerRadiusMedium + 3.0;
    CGPathRef const path = CGPathCreateWithRoundedRect(NSRectToCGRect(ringRect), cornerR, cornerR, NULL);
    _selectionRingLayer.path = path;
    CGPathRelease(path);
}

- (void)setImage:(nullable NSImage *)image
{
    _image = image;
    if (image != nil) {
        _posterImageView.layer.contents = image;
        _posterImageView.hidden = NO;
        _placeholderImageView.hidden = YES;
    } else {
        _posterImageView.layer.contents = nil;
        _posterImageView.hidden = YES;
        _placeholderImageView.hidden = NO;
    }
}

- (void)setRank:(NSInteger)rank
{
    _rank = rank;
    _rankLabel.stringValue = rank > 0 ? [NSString stringWithFormat:@"%ld", (long)rank] : @"";
    _rankLabel.hidden = rank <= 0;
    /* A negative rank keeps the rank column empty (loading placeholders). */
    _posterLeadingConstraint.constant = rank != 0 ? MacLCWatchRankColumnWidth : 0.0;
}

- (void)updateTrackingAreas
{
    [super updateTrackingAreas];
    if (_trackingArea != nil) {
        [self removeTrackingArea:_trackingArea];
    }
    _trackingArea = [[NSTrackingArea alloc] initWithRect:self.bounds
                                                 options:(NSTrackingActiveInKeyWindow |
                                                          NSTrackingMouseEnteredAndExited |
                                                          NSTrackingInVisibleRect)
                                                   owner:self
                                                userInfo:nil];
    [self addTrackingArea:_trackingArea];
}

- (void)resetCursorRects
{
    [super resetCursorRects];
    if (_isHovered) {
        [self addCursorRect:self.bounds cursor:NSCursor.pointingHandCursor];
    }
}

- (void)mouseEntered:(NSEvent *)event
{
    _isHovered = YES;
    [self updateHoverState:YES animated:YES];
    [self.window invalidateCursorRectsForView:self];
}

- (void)mouseExited:(NSEvent *)event
{
    _isHovered = NO;
    [self updateHoverState:NO animated:YES];
    [self.window invalidateCursorRectsForView:self];
}

- (void)updateHoverState:(BOOL)hovered animated:(BOOL)animated
{
    const CATransform3D targetTransform = (hovered && !MacLCDesign.reducedMotion)
        ? CATransform3DMakeScale(1.05, 1.05, 1.0)
        : CATransform3DIdentity;
    const float targetOpacity = hovered ? 0.30f : 0.0f;

    CALayer * const layer = _posterWrapperView.layer;
    if (layer == nil) {
        return;
    }

    if (!animated || MacLCDesign.reducedMotion) {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        [layer removeAnimationForKey:@"hoverTransform"];
        [layer removeAnimationForKey:@"hoverShadow"];
        layer.transform = targetTransform;
        layer.shadowColor = NSColor.blackColor.CGColor;
        layer.shadowRadius = 14.0;
        layer.shadowOffset = CGSizeMake(0.0, -6.0);
        layer.shadowOpacity = targetOpacity;
        [CATransaction commit];
        return;
    }

    CALayer * const presentation = layer.presentationLayer ?: layer;
    CATransform3D const fromTransform = presentation.transform;
    const float fromOpacity = presentation.shadowOpacity;

    layer.transform = targetTransform;
    layer.shadowColor = NSColor.blackColor.CGColor;
    layer.shadowRadius = 14.0;
    layer.shadowOffset = CGSizeMake(0.0, -6.0);
    layer.shadowOpacity = targetOpacity;

    CASpringAnimation * const transformAnim = [CASpringAnimation animationWithKeyPath:@"transform"];
    transformAnim.damping = 15.0;
    transformAnim.stiffness = 260.0;
    transformAnim.mass = 1.0;
    transformAnim.duration = transformAnim.settlingDuration;
    transformAnim.fromValue = [NSValue valueWithCATransform3D:fromTransform];
    transformAnim.toValue = [NSValue valueWithCATransform3D:targetTransform];

    CASpringAnimation * const shadowAnim = [CASpringAnimation animationWithKeyPath:@"shadowOpacity"];
    shadowAnim.damping = 15.0;
    shadowAnim.stiffness = 260.0;
    shadowAnim.mass = 1.0;
    shadowAnim.duration = shadowAnim.settlingDuration;
    shadowAnim.fromValue = @(fromOpacity);
    shadowAnim.toValue = @(targetOpacity);

    [layer addAnimation:transformAnim forKey:@"hoverTransform"];
    [layer addAnimation:shadowAnim forKey:@"hoverShadow"];

    const BOOL isFav = (self.item.addonItem != nil)
        ? [MacLCWatchLibrary.sharedLibrary isFavorite:self.item.addonItem.identifier]
        : NO;
    const CGFloat favTargetAlpha = (isFav || hovered) ? 1.0f : 0.0f;
    if (isFav || hovered) {
        _favoriteButton.hidden = NO;
    }
    if (!animated || MacLCDesign.reducedMotion) {
        _favoriteButton.alphaValue = favTargetAlpha;
        if (favTargetAlpha == 0.0f) {
            _favoriteButton.hidden = YES;
        }
    } else {
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx) {
            ctx.duration = MacLCDesign.motionQuickDuration;
            self->_favoriteButton.animator.alphaValue = favTargetAlpha;
        } completionHandler:^{
            if (!hovered && !isFav) {
                self->_favoriteButton.hidden = YES;
            }
        }];
    }
}

- (NSMenu *)menuForEvent:(NSEvent *)event
{
    if (self.item.addonItem != nil) {
        return [MacLCWatchActions menuForItem:self.item.addonItem video:nil inHistory:NO];
    }
    return [super menuForEvent:event];
}

- (void)mouseUp:(NSEvent *)event
{
    const NSPoint location = [self convertPoint:event.locationInWindow fromView:nil];
    if (NSPointInRect(location, self.bounds)) {
        if (self.item.activationHandler != nil && self.item.addonItem != nil) {
            self.item.activationHandler(self.item.addonItem);
        }
    }
}

- (void)keyDown:(NSEvent *)event
{
    if (event.keyCode == 36 || event.keyCode == 76) { // Return / Enter
        if (self.item.activationHandler != nil && self.item.addonItem != nil) {
            self.item.activationHandler(self.item.addonItem);
            return;
        }
    }
    [super keyDown:event];
}

- (BOOL)isAccessibilityElement
{
    return YES;
}

- (NSAccessibilityRole)accessibilityRole
{
    return NSAccessibilityButtonRole;
}

- (nullable NSArray *)accessibilityChildren
{
    return @[];
}

- (nullable id)accessibilityValue
{
    if (self.item.addonItem == nil) {
        return nil;
    }
    MacLCWatchLibrary * const lib = MacLCWatchLibrary.sharedLibrary;
    MacLCWatchEntry * const entry = [lib entryForTitle:self.item.addonItem.identifier];
    const BOOL isWatched = entry != nil && entry.isWatched;
    const BOOL isFav = [lib isFavorite:self.item.addonItem.identifier];
    double frac = entry != nil ? entry.fraction : 0.0;
    if (frac <= 0.0 && entry.resumeTarget.progress != nil) {
        frac = entry.resumeTarget.progress.fraction;
    }

    NSMutableArray<NSString *> * const states = [NSMutableArray array];
    if (isWatched) {
        [states addObject:_NS("Watched")];
    } else if (frac > 0.0 && frac < 1.0) {
        [states addObject:[NSString stringWithFormat:_NS("In progress, %ld %%"), (long)round(frac * 100)]];
    }
    if (isFav) {
        [states addObject:_NS("Favorite")];
    }
    return states.count > 0 ? [states componentsJoinedByString:@", "] : nil;
}

- (nullable NSString *)accessibilityLabel
{
    NSMutableArray<NSString *> * const parts = [NSMutableArray array];
    if (self.rank > 0) {
        [parts addObject:[NSString stringWithFormat:@"%ld", (long)self.rank]];
    }
    if (self.item.addonItem.name.length > 0) {
        [parts addObject:self.item.addonItem.name];
    }
    NSString * const sub = [self.item subtitleString];
    if (sub.length > 0) {
        [parts addObject:sub];
    }
    return [parts componentsJoinedByString:@", "];
}

- (BOOL)accessibilityPerformPress
{
    if (self.item.activationHandler != nil && self.item.addonItem != nil) {
        self.item.activationHandler(self.item.addonItem);
        return YES;
    }
    return NO;
}

@end

@implementation MacLCWatchPosterItem
{
    MacLCWatchImageRequest *_imageRequest;
}

- (void)loadView
{
    MacLCWatchPosterView * const view = [[MacLCWatchPosterView alloc] initWithFrame:NSZeroRect];
    view.item = self;
    self.view = view;

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(libraryDidChange:)
                                               name:MacLCWatchLibraryDidChangeNotification
                                             object:nil];
}

- (MacLCWatchPosterView *)posterView
{
    return (MacLCWatchPosterView *)self.view;
}

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self name:MacLCWatchLibraryDidChangeNotification object:nil];
    [_imageRequest cancel];
}

- (void)prepareForReuse
{
    [super prepareForReuse];
    [_imageRequest cancel];
    _imageRequest = nil;
    _addonItem = nil;
    _rank = 0;
    self.selected = NO;

    MacLCWatchPosterView * const v = self.posterView;
    v.rank = 0;
    v.image = nil;
    v.titleLabel.stringValue = @"";
    v.subtitleLabel.stringValue = @"";
    v.progressBar.fraction = 0.0;
    v.progressBar.hidden = YES;
    v.watchedBadge.hidden = YES;
    v.posterImageView.alphaValue = 1.0;
    v.placeholderImageView.alphaValue = 1.0;
    v.favoriteButton.alphaValue = 0.0;
    v.favoriteButton.hidden = YES;
    [v.favoriteButton configureWithItem:nil];
    v.selectionRingLayer.hidden = YES;
    [v updateHoverState:NO animated:NO];
}

- (void)setSelected:(BOOL)selected
{
    [super setSelected:selected];
    self.posterView.selectionRingLayer.hidden = !selected;
}

- (NSString *)subtitleString
{
    if (_addonItem == nil) {
        return @"";
    }
    NSMutableArray<NSString *> * const parts = [NSMutableArray array];
    if (_addonItem.releaseInfo.length > 0) {
        [parts addObject:_addonItem.releaseInfo];
    }
    if (_addonItem.genres.count > 0 && _addonItem.genres[0].length > 0) {
        [parts addObject:_addonItem.genres[0]];
    }
    if (parts.count == 0 && _addonItem.type.length > 0) {
        [parts addObject:_addonItem.type.capitalizedString];
    }
    return [parts componentsJoinedByString:@" · "];
}

- (void)updateWatchStates
{
    MacLCWatchPosterView * const v = self.posterView;
    if (_addonItem == nil || _addonItem.identifier.length == 0) {
        v.progressBar.fraction = 0.0;
        v.progressBar.hidden = YES;
        v.watchedBadge.hidden = YES;
        v.posterImageView.alphaValue = 1.0;
        v.placeholderImageView.alphaValue = 1.0;
        [v.favoriteButton configureWithItem:nil];
        v.favoriteButton.hidden = YES;
        return;
    }

    MacLCWatchLibrary * const lib = MacLCWatchLibrary.sharedLibrary;
    MacLCWatchEntry * const entry = [lib entryForTitle:_addonItem.identifier];
    const BOOL isWatched = entry != nil && entry.isWatched;
    const BOOL isFav = [lib isFavorite:_addonItem.identifier];

    v.watchedBadge.hidden = !isWatched;
    v.posterImageView.alphaValue = isWatched ? 0.6 : 1.0;
    v.placeholderImageView.alphaValue = isWatched ? 0.6 : 1.0;

    double frac = 0.0;
    if (!isWatched && entry != nil) {
        frac = entry.fraction;
        if (frac <= 0.0 && entry.resumeTarget.progress != nil) {
            frac = entry.resumeTarget.progress.fraction;
        }
    }
    if (frac > 0.0 && frac < 1.0) {
        v.progressBar.fraction = frac;
        v.progressBar.hidden = NO;
    } else {
        v.progressBar.fraction = 0.0;
        v.progressBar.hidden = YES;
    }

    [v.favoriteButton configureWithItem:_addonItem];
    if (isFav) {
        v.favoriteButton.alphaValue = 1.0;
        v.favoriteButton.hidden = NO;
    } else if (v.isHovered) {
        v.favoriteButton.alphaValue = 1.0;
        v.favoriteButton.hidden = NO;
    } else {
        v.favoriteButton.alphaValue = 0.0;
        v.favoriteButton.hidden = YES;
    }
}

- (void)libraryDidChange:(NSNotification *)note
{
    if (_addonItem == nil) {
        return;
    }
    NSSet<NSString *> * const changed = note.userInfo[MacLCWatchLibraryChangedTitlesKey];
    if (changed == nil || [changed containsObject:_addonItem.identifier]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self updateWatchStates];
        });
    }
}

- (void)configureWithItem:(MacLCAddonItem *)item rank:(NSInteger)rank
{
    _addonItem = item;
    _rank = rank;
    [_imageRequest cancel];
    _imageRequest = nil;

    MacLCWatchPosterView * const v = self.posterView;
    v.rank = rank;
    v.titleLabel.stringValue = item.name ?: @"";
    v.subtitleLabel.stringValue = self.subtitleString ?: @"";

    if (item.posterURL != nil) {
        const CGFloat scale = self.view.window.backingScaleFactor > 0.0 ? self.view.window.backingScaleFactor : 2.0;
        const NSSize drawnSize = NSMakeSize(168.0, 252.0);
        __weak typeof(self) weakSelf = self;
        MacLCWatchImageRequest *req = nil;
        NSImage * const cached = [MacLCWatchImageCache.sharedCache imageForURL:item.posterURL
                                                                    pointSize:drawnSize
                                                                        scale:scale
                                                                      request:&req
                                                                   completion:^(NSImage *image) {
            MacLCWatchPosterItem *strongSelf = weakSelf;
            if (strongSelf != nil && strongSelf.addonItem == item) {
                strongSelf.posterView.image = image;
            }
        }];
        _imageRequest = req;
        v.image = cached;
    } else {
        v.image = nil;
    }

    [self updateWatchStates];
}

@end

#pragma mark - Episode Card

NSUserInterfaceItemIdentifier const MacLCWatchEpisodeItemIdentifier = @"MacLCWatchEpisodeItemIdentifier";

@interface MacLCWatchEpisodeView : NSView

@property (nonatomic, weak) MacLCWatchEpisodeItem *item;
@property (nonatomic, readonly) NSView *stillWrapperView;
@property (nonatomic, readonly) NSView *stillContainerView;
@property (nonatomic, readonly) NSImageView *placeholderImageView;
@property (nonatomic, readonly) NSView *stillImageView;
@property (nonatomic, readonly) MacLCWatchProgressBar *progressBar;
@property (nonatomic, readonly) MacLCWatchedBadge *watchedBadge;
@property (nonatomic, readonly) CAShapeLayer *selectionRingLayer;
@property (nonatomic, readonly) NSTextField *eyebrowLabel;
@property (nonatomic, readonly) NSTextField *titleLabel;
@property (nonatomic, readonly) NSTextField *overviewLabel;
@property (nonatomic, readonly) NSTextField *airDateLabel;

@property (nonatomic, nullable) NSImage *image;
@property (nonatomic, assign) BOOL isHovered;

- (void)updateHoverState:(BOOL)hovered animated:(BOOL)animated;

@end

@implementation MacLCWatchEpisodeView
{
    NSTrackingArea *_trackingArea;
}

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;

        _stillWrapperView = [[NSView alloc] initWithFrame:NSZeroRect];
        _stillWrapperView.translatesAutoresizingMaskIntoConstraints = NO;
        _stillWrapperView.wantsLayer = YES;
        _stillWrapperView.layer.masksToBounds = NO;
        [self addSubview:_stillWrapperView];

        _stillContainerView = [[NSView alloc] initWithFrame:NSZeroRect];
        _stillContainerView.translatesAutoresizingMaskIntoConstraints = NO;
        _stillContainerView.wantsLayer = YES;
        _stillContainerView.layer.masksToBounds = YES;
        _stillContainerView.layer.cornerRadius = MacLCDesign.cornerRadiusMedium;
        _stillContainerView.layer.cornerCurve = kCACornerCurveContinuous;
        _stillContainerView.layer.borderWidth = 1.0;
        _stillContainerView.layer.borderColor = NSColor.separatorColor.CGColor;
        _stillContainerView.layer.backgroundColor = NSColor.quaternarySystemFillColor.CGColor;
        [_stillWrapperView addSubview:_stillContainerView];

        _placeholderImageView = [[NSImageView alloc] initWithFrame:NSZeroRect];
        _placeholderImageView.translatesAutoresizingMaskIntoConstraints = NO;
        _placeholderImageView.imageScaling = NSImageScaleProportionallyUpOrDown;
        _placeholderImageView.contentTintColor = NSColor.tertiaryLabelColor;
        NSImageSymbolConfiguration * const config =
            [NSImageSymbolConfiguration configurationWithPointSize:36.0 weight:NSFontWeightLight];
        NSImage *placeholder = [NSImage imageWithSystemSymbolName:@"tv" accessibilityDescription:nil];
        if (placeholder != nil) {
            placeholder = [placeholder imageWithSymbolConfiguration:config];
        }
        _placeholderImageView.image = placeholder;
        [_stillContainerView addSubview:_placeholderImageView];

        _stillImageView = [[NSView alloc] initWithFrame:NSZeroRect];
        _stillImageView.translatesAutoresizingMaskIntoConstraints = NO;
        _stillImageView.wantsLayer = YES;
        _stillImageView.layer.contentsGravity = kCAGravityResizeAspectFill;
        _stillImageView.layer.masksToBounds = YES;
        _stillImageView.hidden = YES;
        [_stillContainerView addSubview:_stillImageView];

        _progressBar = [[MacLCWatchProgressBar alloc] initWithFrame:NSZeroRect];
        _progressBar.translatesAutoresizingMaskIntoConstraints = NO;
        [_stillContainerView addSubview:_progressBar];

        _watchedBadge = [[MacLCWatchedBadge alloc] initWithFrame:NSZeroRect];
        _watchedBadge.translatesAutoresizingMaskIntoConstraints = NO;
        _watchedBadge.hidden = YES;
        [_stillContainerView addSubview:_watchedBadge];

        _selectionRingLayer = [CAShapeLayer layer];
        _selectionRingLayer.fillColor = nil;
        _selectionRingLayer.strokeColor = MacLCDesign.accent.CGColor;
        _selectionRingLayer.lineWidth = 3.0;
        _selectionRingLayer.hidden = YES;
        [_stillWrapperView.layer addSublayer:_selectionRingLayer];

        _eyebrowLabel = [NSTextField labelWithString:@""];
        _eyebrowLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _eyebrowLabel.selectable = NO;
        [self addSubview:_eyebrowLabel];

        _titleLabel = [NSTextField labelWithString:@""];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _titleLabel.font = [NSFont systemFontOfSize:MacLCDesign.body.pointSize weight:NSFontWeightSemibold];
        _titleLabel.textColor = MacLCDesign.primaryLabel;
        _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _titleLabel.maximumNumberOfLines = 1;
        _titleLabel.selectable = NO;
        [self addSubview:_titleLabel];

        _overviewLabel = [NSTextField wrappingLabelWithString:@""];
        _overviewLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _overviewLabel.font = MacLCDesign.subheadline;
        _overviewLabel.textColor = MacLCDesign.secondaryLabel;
        /* Truncating line break modes turn wrapping off: wrap, and cut the last line. */
        _overviewLabel.lineBreakMode = NSLineBreakByWordWrapping;
        _overviewLabel.cell.truncatesLastVisibleLine = YES;
        _overviewLabel.maximumNumberOfLines = 2;
        _overviewLabel.selectable = NO;
        [self addSubview:_overviewLabel];

        _airDateLabel = [NSTextField labelWithString:@""];
        _airDateLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _airDateLabel.font = MacLCDesign.footnote;
        _airDateLabel.textColor = MacLCDesign.tertiaryLabel;
        _airDateLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _airDateLabel.maximumNumberOfLines = 1;
        _airDateLabel.selectable = NO;
        [self addSubview:_airDateLabel];

        [NSLayoutConstraint activateConstraints:@[
            [_stillWrapperView.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_stillWrapperView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_stillWrapperView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_stillWrapperView.heightAnchor constraintEqualToAnchor:_stillWrapperView.widthAnchor multiplier:(9.0 / 16.0)],

            [_stillContainerView.topAnchor constraintEqualToAnchor:_stillWrapperView.topAnchor],
            [_stillContainerView.bottomAnchor constraintEqualToAnchor:_stillWrapperView.bottomAnchor],
            [_stillContainerView.leadingAnchor constraintEqualToAnchor:_stillWrapperView.leadingAnchor],
            [_stillContainerView.trailingAnchor constraintEqualToAnchor:_stillWrapperView.trailingAnchor],

            [_placeholderImageView.centerXAnchor constraintEqualToAnchor:_stillContainerView.centerXAnchor],
            [_placeholderImageView.centerYAnchor constraintEqualToAnchor:_stillContainerView.centerYAnchor],
            [_placeholderImageView.widthAnchor constraintEqualToConstant:40.0],
            [_placeholderImageView.heightAnchor constraintEqualToConstant:40.0],

            [_stillImageView.topAnchor constraintEqualToAnchor:_stillContainerView.topAnchor],
            [_stillImageView.bottomAnchor constraintEqualToAnchor:_stillContainerView.bottomAnchor],
            [_stillImageView.leadingAnchor constraintEqualToAnchor:_stillContainerView.leadingAnchor],
            [_stillImageView.trailingAnchor constraintEqualToAnchor:_stillContainerView.trailingAnchor],

            [_progressBar.leadingAnchor constraintEqualToAnchor:_stillContainerView.leadingAnchor],
            [_progressBar.trailingAnchor constraintEqualToAnchor:_stillContainerView.trailingAnchor],
            [_progressBar.bottomAnchor constraintEqualToAnchor:_stillContainerView.bottomAnchor],
            [_progressBar.heightAnchor constraintEqualToConstant:4.0],

            [_watchedBadge.trailingAnchor constraintEqualToAnchor:_stillContainerView.trailingAnchor constant:-8.0],
            [_watchedBadge.bottomAnchor constraintEqualToAnchor:_stillContainerView.bottomAnchor constant:-8.0],
            [_watchedBadge.widthAnchor constraintEqualToConstant:24.0],
            [_watchedBadge.heightAnchor constraintEqualToConstant:24.0],

            [_eyebrowLabel.topAnchor constraintEqualToAnchor:_stillWrapperView.bottomAnchor constant:8.0],
            [_eyebrowLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_eyebrowLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],

            [_titleLabel.topAnchor constraintEqualToAnchor:_eyebrowLabel.bottomAnchor constant:2.0],
            [_titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_titleLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],

            [_overviewLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:4.0],
            [_overviewLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_overviewLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],

            [_airDateLabel.topAnchor constraintEqualToAnchor:_overviewLabel.bottomAnchor constant:4.0],
            [_airDateLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_airDateLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        ]];
    }
    return self;
}

- (void)viewDidChangeEffectiveAppearance
{
    [super viewDidChangeEffectiveAppearance];
    _stillContainerView.layer.borderColor = NSColor.separatorColor.CGColor;
    _stillContainerView.layer.backgroundColor = NSColor.quaternarySystemFillColor.CGColor;
    _selectionRingLayer.strokeColor = MacLCDesign.accent.CGColor;
}

- (void)layout
{
    [super layout];

    const NSRect ringRect = NSInsetRect(_stillContainerView.bounds, -4.5, -4.5);
    const CGFloat cornerR = MacLCDesign.cornerRadiusMedium + 3.0;
    CGPathRef const path = CGPathCreateWithRoundedRect(NSRectToCGRect(ringRect), cornerR, cornerR, NULL);
    _selectionRingLayer.path = path;
    CGPathRelease(path);
}

- (void)setImage:(nullable NSImage *)image
{
    _image = image;
    if (image != nil) {
        _stillImageView.layer.contents = image;
        _stillImageView.hidden = NO;
        _placeholderImageView.hidden = YES;
    } else {
        _stillImageView.layer.contents = nil;
        _stillImageView.hidden = YES;
        _placeholderImageView.hidden = NO;
    }
}

- (void)updateTrackingAreas
{
    [super updateTrackingAreas];
    if (_trackingArea != nil) {
        [self removeTrackingArea:_trackingArea];
    }
    _trackingArea = [[NSTrackingArea alloc] initWithRect:self.bounds
                                                 options:(NSTrackingActiveInKeyWindow |
                                                          NSTrackingMouseEnteredAndExited |
                                                          NSTrackingInVisibleRect)
                                                   owner:self
                                                userInfo:nil];
    [self addTrackingArea:_trackingArea];
}

- (void)resetCursorRects
{
    [super resetCursorRects];
    if (_isHovered) {
        [self addCursorRect:self.bounds cursor:NSCursor.pointingHandCursor];
    }
}

- (void)mouseEntered:(NSEvent *)event
{
    _isHovered = YES;
    [self updateHoverState:YES animated:YES];
    [self.window invalidateCursorRectsForView:self];
}

- (void)mouseExited:(NSEvent *)event
{
    _isHovered = NO;
    [self updateHoverState:NO animated:YES];
    [self.window invalidateCursorRectsForView:self];
}

- (void)updateHoverState:(BOOL)hovered animated:(BOOL)animated
{
    const CATransform3D targetTransform = (hovered && !MacLCDesign.reducedMotion)
        ? CATransform3DMakeScale(1.05, 1.05, 1.0)
        : CATransform3DIdentity;
    const float targetOpacity = hovered ? 0.30f : 0.0f;

    CALayer * const layer = _stillWrapperView.layer;
    if (layer == nil) {
        return;
    }

    if (!animated || MacLCDesign.reducedMotion) {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        [layer removeAnimationForKey:@"hoverTransform"];
        [layer removeAnimationForKey:@"hoverShadow"];
        layer.transform = targetTransform;
        layer.shadowColor = NSColor.blackColor.CGColor;
        layer.shadowRadius = 14.0;
        layer.shadowOffset = CGSizeMake(0.0, -6.0);
        layer.shadowOpacity = targetOpacity;
        [CATransaction commit];
        return;
    }

    CALayer * const presentation = layer.presentationLayer ?: layer;
    CATransform3D const fromTransform = presentation.transform;
    const float fromOpacity = presentation.shadowOpacity;

    layer.transform = targetTransform;
    layer.shadowColor = NSColor.blackColor.CGColor;
    layer.shadowRadius = 14.0;
    layer.shadowOffset = CGSizeMake(0.0, -6.0);
    layer.shadowOpacity = targetOpacity;

    CASpringAnimation * const transformAnim = [CASpringAnimation animationWithKeyPath:@"transform"];
    transformAnim.damping = 15.0;
    transformAnim.stiffness = 260.0;
    transformAnim.mass = 1.0;
    transformAnim.duration = transformAnim.settlingDuration;
    transformAnim.fromValue = [NSValue valueWithCATransform3D:fromTransform];
    transformAnim.toValue = [NSValue valueWithCATransform3D:targetTransform];

    CASpringAnimation * const shadowAnim = [CASpringAnimation animationWithKeyPath:@"shadowOpacity"];
    shadowAnim.damping = 15.0;
    shadowAnim.stiffness = 260.0;
    shadowAnim.mass = 1.0;
    shadowAnim.duration = shadowAnim.settlingDuration;
    shadowAnim.fromValue = @(fromOpacity);
    shadowAnim.toValue = @(targetOpacity);

    [layer addAnimation:transformAnim forKey:@"hoverTransform"];
    [layer addAnimation:shadowAnim forKey:@"hoverShadow"];
}

- (NSMenu *)menuForEvent:(NSEvent *)event
{
    if (self.item.video != nil && self.item.titleIdentifier.length > 0) {
        MacLCWatchEntry * const entry = [MacLCWatchLibrary.sharedLibrary entryForTitle:self.item.titleIdentifier];
        MacLCAddonItem * const item = entry.item;
        if (item != nil) {
            return [MacLCWatchActions menuForItem:item video:self.item.video inHistory:NO];
        }
    }
    return [super menuForEvent:event];
}

- (void)mouseUp:(NSEvent *)event
{
    const NSPoint location = [self convertPoint:event.locationInWindow fromView:nil];
    if (NSPointInRect(location, self.bounds)) {
        if (self.item.activationHandler != nil && self.item.video != nil) {
            self.item.activationHandler(self.item.video);
        }
    }
}

- (void)keyDown:(NSEvent *)event
{
    if (event.keyCode == 36 || event.keyCode == 76) {
        if (self.item.activationHandler != nil && self.item.video != nil) {
            self.item.activationHandler(self.item.video);
            return;
        }
    }
    [super keyDown:event];
}

- (BOOL)isAccessibilityElement
{
    return YES;
}

- (NSAccessibilityRole)accessibilityRole
{
    return NSAccessibilityButtonRole;
}

- (nullable NSArray *)accessibilityChildren
{
    return @[];
}

- (nullable id)accessibilityValue
{
    if (self.item.video == nil || self.item.titleIdentifier.length == 0) {
        return nil;
    }
    MacLCWatchProgress * const p =
        [MacLCWatchLibrary.sharedLibrary progressForTitle:self.item.titleIdentifier video:self.item.video.identifier];
    if (p.isWatched) {
        return _NS("Watched");
    }
    if (p != nil && p.canResume && p.fraction > 0.0 && p.fraction < 1.0) {
        return [NSString stringWithFormat:_NS("In progress, %ld %%"), (long)round(p.fraction * 100)];
    }
    return nil;
}

- (nullable NSString *)accessibilityLabel
{
    NSMutableArray<NSString *> * const parts = [NSMutableArray array];
    if (self.eyebrowLabel.stringValue.length > 0) {
        [parts addObject:self.eyebrowLabel.stringValue];
    }
    if (self.titleLabel.stringValue.length > 0) {
        [parts addObject:self.titleLabel.stringValue];
    }
    if (self.overviewLabel.stringValue.length > 0) {
        [parts addObject:self.overviewLabel.stringValue];
    }
    if (self.airDateLabel.stringValue.length > 0) {
        [parts addObject:self.airDateLabel.stringValue];
    }
    return [parts componentsJoinedByString:@", "];
}

- (BOOL)accessibilityPerformPress
{
    if (self.item.activationHandler != nil && self.item.video != nil) {
        self.item.activationHandler(self.item.video);
        return YES;
    }
    return NO;
}

@end

@interface MacLCWatchEpisodeItem ()
@property (nonatomic, readwrite, nullable) MacLCAddonVideo *video;
@property (nonatomic, copy, readwrite, nullable) NSString *titleIdentifier;
@property (nonatomic, readonly) MacLCWatchEpisodeView *episodeView;
@end

@implementation MacLCWatchEpisodeItem
{
    MacLCWatchImageRequest *_imageRequest;
}

+ (CGFloat)heightForWidth:(CGFloat)width
{
    const CGFloat stillHeight = ceil(width * 9.0 / 16.0);

    NSFont * const footnoteFont = [NSFont systemFontOfSize:MacLCDesign.footnote.pointSize weight:NSFontWeightSemibold];
    const CGFloat eyebrowHeight = ceil(footnoteFont.ascender - footnoteFont.descender + footnoteFont.leading);

    NSFont * const titleFont = [NSFont systemFontOfSize:MacLCDesign.body.pointSize weight:NSFontWeightSemibold];
    const CGFloat titleHeight = ceil(titleFont.ascender - titleFont.descender + titleFont.leading);

    NSFont * const subheadlineFont = MacLCDesign.subheadline;
    const CGFloat overviewHeight = 2.0 * ceil(subheadlineFont.ascender - subheadlineFont.descender + subheadlineFont.leading);

    NSFont * const dateFont = MacLCDesign.footnote;
    const CGFloat dateHeight = ceil(dateFont.ascender - dateFont.descender + dateFont.leading);

    const CGFloat textHeight = eyebrowHeight + 2.0 + titleHeight + 4.0 + overviewHeight + 4.0 + dateHeight;
    return stillHeight + 8.0 + textHeight;
}

- (void)loadView
{
    MacLCWatchEpisodeView * const view = [[MacLCWatchEpisodeView alloc] initWithFrame:NSZeroRect];
    view.item = self;
    self.view = view;

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(libraryDidChange:)
                                               name:MacLCWatchLibraryDidChangeNotification
                                             object:nil];
}

- (MacLCWatchEpisodeView *)episodeView
{
    return (MacLCWatchEpisodeView *)self.view;
}

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self name:MacLCWatchLibraryDidChangeNotification object:nil];
    [_imageRequest cancel];
}

- (void)prepareForReuse
{
    [super prepareForReuse];
    [_imageRequest cancel];
    _imageRequest = nil;
    _video = nil;
    _titleIdentifier = nil;
    self.selected = NO;

    MacLCWatchEpisodeView * const v = self.episodeView;
    v.image = nil;
    v.eyebrowLabel.attributedStringValue = [[NSAttributedString alloc] initWithString:@""];
    v.titleLabel.stringValue = @"";
    v.overviewLabel.stringValue = @"";
    v.airDateLabel.stringValue = @"";
    v.progressBar.fraction = 0.0;
    v.progressBar.hidden = YES;
    v.watchedBadge.hidden = YES;
    v.stillImageView.alphaValue = 1.0;
    v.placeholderImageView.alphaValue = 1.0;
    v.selectionRingLayer.hidden = YES;
    [v updateHoverState:NO animated:NO];
}

- (void)setSelected:(BOOL)selected
{
    [super setSelected:selected];
    self.episodeView.selectionRingLayer.hidden = !selected;
}

- (void)updateWatchStates
{
    MacLCWatchEpisodeView * const v = self.episodeView;
    if (_video == nil || _titleIdentifier.length == 0) {
        v.progressBar.fraction = 0.0;
        v.progressBar.hidden = YES;
        v.watchedBadge.hidden = YES;
        v.stillImageView.alphaValue = 1.0;
        v.placeholderImageView.alphaValue = 1.0;
        return;
    }

    MacLCWatchProgress * const p =
        [MacLCWatchLibrary.sharedLibrary progressForTitle:_titleIdentifier video:_video.identifier];
    const BOOL isWatched = p != nil && p.isWatched;

    v.watchedBadge.hidden = !isWatched;
    v.stillImageView.alphaValue = isWatched ? 0.6 : 1.0;
    v.placeholderImageView.alphaValue = isWatched ? 0.6 : 1.0;

    if (!isWatched && p != nil && p.canResume && p.fraction > 0.0 && p.fraction < 1.0) {
        v.progressBar.fraction = p.fraction;
        v.progressBar.hidden = NO;
    } else {
        v.progressBar.fraction = 0.0;
        v.progressBar.hidden = YES;
    }
}

- (void)libraryDidChange:(NSNotification *)note
{
    if (_titleIdentifier == nil) {
        return;
    }
    NSSet<NSString *> * const changed = note.userInfo[MacLCWatchLibraryChangedTitlesKey];
    if (changed == nil || [changed containsObject:_titleIdentifier]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self updateWatchStates];
        });
    }
}

- (void)configureWithVideo:(MacLCAddonVideo *)video
{
    NSString *titleId = nil;
    NSRange const colonRange = [video.identifier rangeOfString:@":"];
    if (colonRange.location != NSNotFound) {
        titleId = [video.identifier substringToIndex:colonRange.location];
    } else {
        titleId = video.identifier;
    }
    [self configureWithVideo:video titleIdentifier:titleId];
}

- (void)configureWithVideo:(MacLCAddonVideo *)video titleIdentifier:(NSString *)titleIdentifier
{
    _video = video;
    _titleIdentifier = [titleIdentifier copy];
    [_imageRequest cancel];
    _imageRequest = nil;

    MacLCWatchEpisodeView * const v = self.episodeView;

    NSString *eyebrow = @"";
    if (video.episode > 0) {
        eyebrow = [NSString stringWithFormat:_NS("EPISODE %ld"), (long)video.episode];
    } else if (video.season > 0) {
        eyebrow = [NSString stringWithFormat:_NS("SEASON %ld"), (long)video.season];
    }
    if (eyebrow.length > 0) {
        NSFont * const font = [NSFont systemFontOfSize:MacLCDesign.footnote.pointSize weight:NSFontWeightSemibold];
        NSDictionary * const attrs = @{
            NSFontAttributeName: font,
            NSKernAttributeName: @0.6,
            NSForegroundColorAttributeName: MacLCDesign.secondaryLabel,
        };
        v.eyebrowLabel.attributedStringValue = [[NSAttributedString alloc] initWithString:eyebrow.uppercaseString attributes:attrs];
    } else {
        v.eyebrowLabel.attributedStringValue = [[NSAttributedString alloc] initWithString:@""];
    }

    NSString *title = video.name;
    if (title.length == 0 && video.episode > 0) {
        title = [NSString stringWithFormat:_NS("Episode %ld"), (long)video.episode];
    }
    v.titleLabel.stringValue = title ?: @"";
    v.overviewLabel.stringValue = video.overview ?: @"";

    static NSDateFormatter *sDateFormatter = nil;
    static dispatch_once_t sOnceToken;
    dispatch_once(&sOnceToken, ^{
        sDateFormatter = [[NSDateFormatter alloc] init];
        sDateFormatter.dateStyle = NSDateFormatterMediumStyle;
        sDateFormatter.timeStyle = NSDateFormatterNoStyle;
    });

    NSString *dateStr = @"";
    if (video.released != nil) {
        if ([video.released timeIntervalSinceNow] > 0) {
            dateStr = _NS("Upcoming");
        } else {
            dateStr = [sDateFormatter stringFromDate:video.released];
        }
    }
    v.airDateLabel.stringValue = dateStr ?: @"";

    if (video.thumbnailURL != nil) {
        const CGFloat scale = self.view.window.backingScaleFactor > 0.0 ? self.view.window.backingScaleFactor : 2.0;
        const NSSize drawnSize = NSMakeSize(300.0, ceil(300.0 * 9.0 / 16.0));
        __weak typeof(self) weakSelf = self;
        MacLCWatchImageRequest *req = nil;
        NSImage * const cached = [MacLCWatchImageCache.sharedCache imageForURL:video.thumbnailURL
                                                                    pointSize:drawnSize
                                                                        scale:scale
                                                                      request:&req
                                                                   completion:^(NSImage *image) {
            MacLCWatchEpisodeItem *strongSelf = weakSelf;
            if (strongSelf != nil && strongSelf.video == video) {
                strongSelf.episodeView.image = image;
            }
        }];
        _imageRequest = req;
        v.image = cached;
    } else {
        v.image = nil;
    }

    [self updateWatchStates];
}

@end

#pragma mark - Featured Carousel (Hero View)

@interface MacLCWatchHeroPictureView : NSView
@property (nonatomic, nullable) NSImage *image;
@end

@implementation MacLCWatchHeroPictureView

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        self.layer.contentsGravity = kCAGravityResizeAspectFill;
        self.layer.masksToBounds = YES;
    }
    return self;
}

- (BOOL)wantsUpdateLayer
{
    return YES;
}

- (void)updateLayer
{
    self.layer.contents = self.image;
    self.layer.backgroundColor = (self.image == nil) ? NSColor.quaternarySystemFillColor.CGColor : NULL;
}

- (void)setImage:(NSImage *)image
{
    _image = image;
    self.needsDisplay = YES;
}

@end

@interface MacLCWatchHeroBottomScrimView : NSView
@end

@implementation MacLCWatchHeroBottomScrimView

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
    }
    return self;
}

- (CALayer *)makeBackingLayer
{
    CAGradientLayer * const gradient = [CAGradientLayer layer];
    gradient.colors = @[
        (__bridge id)[NSColor colorWithWhite:0.0 alpha:0.0].CGColor,
        (__bridge id)[NSColor colorWithWhite:0.0 alpha:0.70].CGColor,
    ];
    gradient.startPoint = CGPointMake(0.5, 0.60);
    gradient.endPoint = CGPointMake(0.5, 0.0);
    return gradient;
}

- (NSView *)hitTest:(NSPoint)point
{
    return nil;
}

@end

@interface MacLCWatchHeroLeadingScrimView : NSView
@end

@implementation MacLCWatchHeroLeadingScrimView

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
    }
    return self;
}

- (CALayer *)makeBackingLayer
{
    CAGradientLayer * const gradient = [CAGradientLayer layer];
    gradient.colors = @[
        (__bridge id)[NSColor colorWithWhite:0.0 alpha:0.45].CGColor,
        (__bridge id)[NSColor colorWithWhite:0.0 alpha:0.0].CGColor,
    ];
    gradient.startPoint = CGPointMake(0.0, 0.5);
    gradient.endPoint = CGPointMake(0.55, 0.5);
    return gradient;
}

- (NSView *)hitTest:(NSPoint)point
{
    return nil;
}

@end

@interface MacLCWatchHeroTopScrimView : NSView
@end

@implementation MacLCWatchHeroTopScrimView

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
    }
    return self;
}

- (CALayer *)makeBackingLayer
{
    return [CAGradientLayer layer];
}

- (BOOL)wantsUpdateLayer
{
    return YES;
}

- (void)updateLayer
{
    __block CGColorRef top = NULL;
    [self.effectiveAppearance performAsCurrentDrawingAppearance:^{
        top = CGColorRetain([NSColor.windowBackgroundColor colorWithAlphaComponent:0.55].CGColor);
    }];
    CAGradientLayer * const gradient = (CAGradientLayer *)self.layer;
    gradient.colors = @[(__bridge id)top, (__bridge_transfer id)CGColorCreateCopyWithAlpha(top, 0.0)];
    gradient.startPoint = CGPointMake(0.5, 1.0);
    gradient.endPoint = CGPointMake(0.5, 0.0);
    CGColorRelease(top);
}

- (void)viewDidChangeEffectiveAppearance
{
    [super viewDidChangeEffectiveAppearance];
    [self setNeedsDisplay:YES];
}

- (NSView *)hitTest:(NSPoint)point
{
    return nil;
}

@end

@interface MacLCWatchHeroDotButton : NSButton
@property (nonatomic, assign) BOOL active;
@property (nonatomic, strong) NSLayoutConstraint *widthConstraint;
- (void)setActive:(BOOL)active animated:(BOOL)animated;
@end

@implementation MacLCWatchHeroDotButton
{
    CALayer *_dotLayer;
}

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        self.bordered = NO;
        self.title = @"";
        self.wantsLayer = YES;
        self.translatesAutoresizingMaskIntoConstraints = NO;

        _dotLayer = [CALayer layer];
        _dotLayer.cornerRadius = 4.0;
        _dotLayer.backgroundColor = [NSColor colorWithWhite:1.0 alpha:0.40].CGColor;
        [self.layer addSublayer:_dotLayer];

        /* The dot is 8 pt, its hit region 20 pt at least (accessibility.md). */
        _widthConstraint = [self.widthAnchor constraintEqualToConstant:20.0];
        [NSLayoutConstraint activateConstraints:@[
            _widthConstraint,
            [self.heightAnchor constraintEqualToConstant:20.0],
        ]];
    }
    return self;
}

- (void)layout
{
    [super layout];
    const CGFloat dotW = _active ? 20.0 : 8.0;
    _dotLayer.frame = CGRectMake((self.bounds.size.width - dotW) / 2.0,
                                 (self.bounds.size.height - 8.0) / 2.0,
                                 dotW,
                                 8.0);
}

- (void)setActive:(BOOL)active animated:(BOOL)animated
{
    _active = active;
    const CGFloat targetW = active ? 28.0 : 20.0;
    CGColorRef const targetColor = active ? NSColor.whiteColor.CGColor : [NSColor colorWithWhite:1.0 alpha:0.40].CGColor;

    if (!animated || MacLCDesign.reducedMotion) {
        _widthConstraint.constant = targetW;
        _dotLayer.backgroundColor = targetColor;
        [self setNeedsLayout:YES];
        return;
    }

    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = MacLCDesign.motionStandardDuration;
        self->_widthConstraint.animator.constant = targetW;
    }];

    [CATransaction begin];
    [CATransaction setAnimationDuration:MacLCDesign.motionStandardDuration];
    _dotLayer.backgroundColor = targetColor;
    [CATransaction commit];
}

- (void)resetCursorRects
{
    [super resetCursorRects];
    [self addCursorRect:self.bounds cursor:NSCursor.pointingHandCursor];
}

- (NSView *)hitTest:(NSPoint)point
{
    const CGFloat dx = (self.bounds.size.width < 20.0) ? (self.bounds.size.width - 20.0) / 2.0 : 0.0;
    const CGFloat dy = (self.bounds.size.height < 20.0) ? (self.bounds.size.height - 20.0) / 2.0 : 0.0;
    const NSRect hitRect = NSInsetRect(self.bounds, dx, dy);
    return NSPointInRect(point, hitRect) ? self : nil;
}

- (BOOL)isAccessibilityElement
{
    return YES;
}

- (NSAccessibilityRole)accessibilityRole
{
    return NSAccessibilityButtonRole;
}

@end

@interface MacLCWatchHeroView ()
{
    NSBackgroundExtensionView *_extensionView;
    NSView *_pictureContainerView;
    MacLCWatchHeroPictureView *_pictureViewA;
    MacLCWatchHeroPictureView *_pictureViewB;
    MacLCWatchHeroPictureView *_activePictureView;
    MacLCWatchHeroPictureView *_inactivePictureView;

    MacLCWatchHeroLeadingScrimView *_leadingScrimView;
    MacLCWatchHeroBottomScrimView *_bottomScrimView;
    MacLCWatchHeroTopScrimView *_topScrimView;

    NSStackView *_textStackView;
    NSTextField *_eyebrowField;
    NSImageView *_titleLogoImageView;
    NSLayoutConstraint *_titleLogoWidthConstraint;
    NSLayoutConstraint *_titleLogoHeightConstraint;
    NSTextField *_titleField;
    NSTextField *_factsField;
    NSTextField *_descriptionField;
    NSButton *_playButton;
    NSButton *_detailsButton;

    NSStackView *_dotsStackView;
    NSMutableArray<MacLCWatchHeroDotButton *> *_dotButtons;

    NSButton *_leftChevronButton;
    NSButton *_rightChevronButton;

    NSTimer *_advanceTimer;
    MacLCWatchImageRequest *_preloadRequest;
    MacLCWatchImageRequest *_preloadLogoRequest;
    NSTrackingArea *_trackingArea;

    NSInteger _currentIndex;
    BOOL _isMouseOver;
    NSSize _lastRequestedSize;
}
@end

@implementation MacLCWatchHeroView

+ (CGFloat)heightForAvailableHeight:(CGFloat)height
{
    const CGFloat h = round(height * 0.62);
    return MAX(360.0, MIN(620.0, h));
}

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        _items = @[];
        _eyebrows = @[];
        _dotButtons = [NSMutableArray array];
        _currentIndex = 0;
        [self setUpViews];
    }
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (self) {
        _items = @[];
        _eyebrows = @[];
        _dotButtons = [NSMutableArray array];
        _currentIndex = 0;
        [self setUpViews];
    }
    return self;
}

- (void)dealloc
{
    [_advanceTimer invalidate];
    [_preloadRequest cancel];
    [_preloadLogoRequest cancel];
}

- (void)setUpViews
{
    self.wantsLayer = YES;

    _pictureContainerView = [[NSView alloc] initWithFrame:self.bounds];
    _pictureContainerView.translatesAutoresizingMaskIntoConstraints = NO;
    _pictureContainerView.wantsLayer = YES;

    _pictureViewA = [[MacLCWatchHeroPictureView alloc] initWithFrame:self.bounds];
    _pictureViewA.translatesAutoresizingMaskIntoConstraints = NO;
    _pictureViewA.alphaValue = 1.0;
    [_pictureContainerView addSubview:_pictureViewA];

    _pictureViewB = [[MacLCWatchHeroPictureView alloc] initWithFrame:self.bounds];
    _pictureViewB.translatesAutoresizingMaskIntoConstraints = NO;
    _pictureViewB.alphaValue = 0.0;
    [_pictureContainerView addSubview:_pictureViewB];

    _activePictureView = _pictureViewA;
    _inactivePictureView = _pictureViewB;

    _extensionView = [[NSBackgroundExtensionView alloc] initWithFrame:self.bounds];
    _extensionView.automaticallyPlacesContentView = NO;
    _extensionView.contentView = _pictureContainerView;
    _extensionView.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_extensionView];

    _topScrimView = [[MacLCWatchHeroTopScrimView alloc] initWithFrame:self.bounds];
    _topScrimView.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_topScrimView];

    _leadingScrimView = [[MacLCWatchHeroLeadingScrimView alloc] initWithFrame:self.bounds];
    _leadingScrimView.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_leadingScrimView];

    _bottomScrimView = [[MacLCWatchHeroBottomScrimView alloc] initWithFrame:self.bounds];
    _bottomScrimView.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_bottomScrimView];

    _eyebrowField = [NSTextField labelWithString:@""];
    _eyebrowField.translatesAutoresizingMaskIntoConstraints = NO;
    _eyebrowField.font = [NSFont systemFontOfSize:MacLCDesign.footnote.pointSize weight:NSFontWeightSemibold];
    _eyebrowField.textColor = [NSColor colorWithWhite:1.0 alpha:0.75];
    _eyebrowField.selectable = NO;

    _titleLogoImageView = [[NSImageView alloc] initWithFrame:NSZeroRect];
    _titleLogoImageView.translatesAutoresizingMaskIntoConstraints = NO;
    _titleLogoImageView.imageScaling = NSImageScaleProportionallyUpOrDown;
    _titleLogoImageView.imageAlignment = NSImageAlignLeft;
    _titleLogoImageView.hidden = YES;
    _titleLogoWidthConstraint = [_titleLogoImageView.widthAnchor constraintEqualToConstant:0.0];
    _titleLogoHeightConstraint = [_titleLogoImageView.heightAnchor constraintEqualToConstant:0.0];
    _titleLogoWidthConstraint.priority = NSLayoutPriorityDefaultHigh;
    _titleLogoHeightConstraint.priority = NSLayoutPriorityDefaultHigh;
    [NSLayoutConstraint activateConstraints:@[
        [_titleLogoImageView.widthAnchor constraintLessThanOrEqualToConstant:360.0],
        [_titleLogoImageView.heightAnchor constraintLessThanOrEqualToConstant:120.0],
        _titleLogoWidthConstraint,
        _titleLogoHeightConstraint,
    ]];

    _titleField = [NSTextField wrappingLabelWithString:@""];
    _titleField.translatesAutoresizingMaskIntoConstraints = NO;
    _titleField.font = [NSFont systemFontOfSize:MacLCDesign.largeTitle.pointSize weight:NSFontWeightBold];
    _titleField.textColor = NSColor.whiteColor;
    _titleField.maximumNumberOfLines = 2;
    /* Truncating line break modes turn wrapping off: wrap, and cut the last line. */
    _titleField.lineBreakMode = NSLineBreakByWordWrapping;
    _titleField.cell.truncatesLastVisibleLine = YES;
    _titleField.selectable = NO;

    _factsField = [NSTextField labelWithString:@""];
    _factsField.translatesAutoresizingMaskIntoConstraints = NO;
    _factsField.font = MacLCDesign.callout;
    _factsField.textColor = [NSColor colorWithWhite:1.0 alpha:0.85];
    _factsField.selectable = NO;

    _descriptionField = [NSTextField wrappingLabelWithString:@""];
    _descriptionField.translatesAutoresizingMaskIntoConstraints = NO;
    _descriptionField.font = MacLCDesign.body;
    _descriptionField.textColor = [NSColor colorWithWhite:1.0 alpha:0.85];
    _descriptionField.maximumNumberOfLines = 3;
    /* A wrapping label sizes itself on one line without it. */
    _descriptionField.preferredMaxLayoutWidth = 460.0;
    /* Truncating line break modes turn wrapping off: wrap, and cut the last line. */
    _descriptionField.lineBreakMode = NSLineBreakByWordWrapping;
    _descriptionField.cell.truncatesLastVisibleLine = YES;
    _descriptionField.selectable = NO;

    _playButton = [NSButton buttonWithTitle:_NS("Play") target:self action:@selector(playClicked:)];
    _playButton.image = [NSImage imageWithSystemSymbolName:@"play.fill" accessibilityDescription:nil];
    _playButton.imagePosition = NSImageLeading;
    _playButton.bezelStyle = NSBezelStyleGlass;
    _playButton.controlSize = NSControlSizeLarge;
    _playButton.tintProminence = NSTintProminencePrimary;
    _playButton.bezelColor = MacLCDesign.accent;
    _playButton.toolTip = _NS("Play");
    _playButton.accessibilityLabel = _NS("Play");

    _detailsButton = [NSButton buttonWithTitle:_NS("Details") target:self action:@selector(detailsClicked:)];
    _detailsButton.image = [NSImage imageWithSystemSymbolName:@"info.circle" accessibilityDescription:nil];
    _detailsButton.imagePosition = NSImageLeading;
    _detailsButton.bezelStyle = NSBezelStyleGlass;
    _detailsButton.controlSize = NSControlSizeLarge;
    _detailsButton.toolTip = _NS("Details");
    _detailsButton.accessibilityLabel = _NS("Details");

    NSStackView * const buttonsStack = [NSStackView stackViewWithViews:@[_playButton, _detailsButton]];
    buttonsStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    buttonsStack.spacing = 12.0;

    _textStackView = [NSStackView stackViewWithViews:@[
        _eyebrowField,
        _titleLogoImageView,
        _titleField,
        _factsField,
        _descriptionField,
        buttonsStack
    ]];
    _textStackView.orientation = NSUserInterfaceLayoutOrientationVertical;
    _textStackView.alignment = NSLayoutAttributeLeading;
    _textStackView.spacing = 4.0;
    [_textStackView setCustomSpacing:6.0 afterView:_titleLogoImageView];
    [_textStackView setCustomSpacing:6.0 afterView:_titleField];
    [_textStackView setCustomSpacing:16.0 afterView:_descriptionField];
    _textStackView.translatesAutoresizingMaskIntoConstraints = NO;
    _textStackView.wantsLayer = YES;
    [self addSubview:_textStackView];

    _dotsStackView = [[NSStackView alloc] initWithFrame:NSZeroRect];
    _dotsStackView.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    _dotsStackView.spacing = 0.0;
    _dotsStackView.alignment = NSLayoutAttributeCenterY;
    _dotsStackView.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_dotsStackView];

    _leftChevronButton = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"chevron.left" accessibilityDescription:_NS("Previous")]
                                            target:self
                                            action:@selector(previousClicked:)];
    _leftChevronButton.translatesAutoresizingMaskIntoConstraints = NO;
    _leftChevronButton.toolTip = _NS("Previous");
    _leftChevronButton.accessibilityLabel = _NS("Previous");
    _leftChevronButton.alphaValue = 0.0;
#if __MAC_OS_X_VERSION_MAX_ALLOWED >= 260000
    if (@available(macOS 26.0, *)) {
        _leftChevronButton.bordered = YES;
        _leftChevronButton.bezelStyle = NSBezelStyleGlass;
        _leftChevronButton.borderShape = NSControlBorderShapeCircle;
    } else {
#endif
        _leftChevronButton.bezelStyle = NSBezelStyleCircular;
#if __MAC_OS_X_VERSION_MAX_ALLOWED >= 260000
    }
#endif
    [self addSubview:_leftChevronButton];

    _rightChevronButton = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"chevron.right" accessibilityDescription:_NS("Next")]
                                             target:self
                                             action:@selector(nextClicked:)];
    _rightChevronButton.translatesAutoresizingMaskIntoConstraints = NO;
    _rightChevronButton.toolTip = _NS("Next");
    _rightChevronButton.accessibilityLabel = _NS("Next");
    _rightChevronButton.alphaValue = 0.0;
#if __MAC_OS_X_VERSION_MAX_ALLOWED >= 260000
    if (@available(macOS 26.0, *)) {
        _rightChevronButton.bordered = YES;
        _rightChevronButton.bezelStyle = NSBezelStyleGlass;
        _rightChevronButton.borderShape = NSControlBorderShapeCircle;
    } else {
#endif
        _rightChevronButton.bezelStyle = NSBezelStyleCircular;
#if __MAC_OS_X_VERSION_MAX_ALLOWED >= 260000
    }
#endif
    [self addSubview:_rightChevronButton];

    NSLayoutGuide * const safeArea = self.safeAreaLayoutGuide;
    NSLayoutConstraint * const dotsCenter = [_dotsStackView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor];
    dotsCenter.priority = NSLayoutPriorityDefaultLow;
    NSLayoutConstraint * const descriptionWidth = [_descriptionField.widthAnchor constraintEqualToConstant:460.0];
    descriptionWidth.priority = 700;

    [NSLayoutConstraint activateConstraints:@[
        [_extensionView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_extensionView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [_extensionView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_extensionView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],

        [_pictureContainerView.topAnchor constraintEqualToAnchor:_extensionView.topAnchor],
        [_pictureContainerView.bottomAnchor constraintEqualToAnchor:_extensionView.bottomAnchor],
        [_pictureContainerView.leadingAnchor constraintEqualToAnchor:_extensionView.leadingAnchor],
        [_pictureContainerView.trailingAnchor constraintEqualToAnchor:_extensionView.trailingAnchor],

        [_pictureViewA.topAnchor constraintEqualToAnchor:_pictureContainerView.topAnchor],
        [_pictureViewA.bottomAnchor constraintEqualToAnchor:_pictureContainerView.bottomAnchor],
        [_pictureViewA.leadingAnchor constraintEqualToAnchor:_pictureContainerView.leadingAnchor],
        [_pictureViewA.trailingAnchor constraintEqualToAnchor:_pictureContainerView.trailingAnchor],

        [_pictureViewB.topAnchor constraintEqualToAnchor:_pictureContainerView.topAnchor],
        [_pictureViewB.bottomAnchor constraintEqualToAnchor:_pictureContainerView.bottomAnchor],
        [_pictureViewB.leadingAnchor constraintEqualToAnchor:_pictureContainerView.leadingAnchor],
        [_pictureViewB.trailingAnchor constraintEqualToAnchor:_pictureContainerView.trailingAnchor],

        [_topScrimView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_topScrimView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_topScrimView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_topScrimView.heightAnchor constraintEqualToConstant:88.0],

        [_leadingScrimView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_leadingScrimView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [_leadingScrimView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_leadingScrimView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],

        [_bottomScrimView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_bottomScrimView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [_bottomScrimView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_bottomScrimView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],

        [_textStackView.leadingAnchor constraintEqualToAnchor:safeArea.leadingAnchor constant:40.0],
        [_textStackView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-40.0],
        [_textStackView.widthAnchor constraintLessThanOrEqualToConstant:460.0],
        [_titleField.widthAnchor constraintLessThanOrEqualToConstant:460.0],
        [_descriptionField.widthAnchor constraintLessThanOrEqualToConstant:460.0],
        [_descriptionField.trailingAnchor constraintLessThanOrEqualToAnchor:safeArea.trailingAnchor constant:-40.0],
        descriptionWidth,

        /* page-controls.md: "Center a page control at the bottom of the view";
         * it moves right rather than overlap the text. */
        dotsCenter,
        [_dotsStackView.leadingAnchor constraintGreaterThanOrEqualToAnchor:_textStackView.trailingAnchor constant:24.0],
        [_dotsStackView.trailingAnchor constraintLessThanOrEqualToAnchor:safeArea.trailingAnchor constant:-40.0],
        [_dotsStackView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-36.0],

        [_leftChevronButton.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16.0],
        [_leftChevronButton.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_leftChevronButton.widthAnchor constraintEqualToConstant:28.0],
        [_leftChevronButton.heightAnchor constraintEqualToConstant:28.0],

        [_rightChevronButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16.0],
        [_rightChevronButton.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_rightChevronButton.widthAnchor constraintEqualToConstant:28.0],
        [_rightChevronButton.heightAnchor constraintEqualToConstant:28.0],
    ]];
}

- (void)setItems:(NSArray<MacLCAddonItem *> *)items
{
    if (items.count > 8) {
        items = [items subarrayWithRange:NSMakeRange(0, 8)];
    }
    _items = [items copy];
    _currentIndex = 0;

    [self rebuildPageDots];
    [self showItemAtIndex:0 animated:NO];
    [self startTimer];
}

- (void)setEyebrows:(NSArray<NSString *> *)eyebrows
{
    _eyebrows = [eyebrows copy];
    if (_items.count > 0 && _currentIndex < (NSInteger)_items.count) {
        [self updateEyebrowForIndex:_currentIndex];
    }
}

- (void)rebuildPageDots
{
    for (NSView * const v in _dotsStackView.arrangedSubviews) {
        [_dotsStackView removeArrangedSubview:v];
        [v removeFromSuperview];
    }
    [_dotButtons removeAllObjects];

    for (NSInteger i = 0; i < (NSInteger)_items.count; i++) {
        MacLCWatchHeroDotButton * const dot = [[MacLCWatchHeroDotButton alloc] initWithFrame:NSZeroRect];
        dot.tag = i;
        dot.target = self;
        dot.action = @selector(dotClicked:);
        dot.accessibilityLabel = [NSString stringWithFormat:_NS("Show %@"), _items[i].name ?: @""];
        [dot setActive:(i == _currentIndex) animated:NO];
        [_dotsStackView addArrangedSubview:dot];
        [_dotButtons addObject:dot];
    }
}

- (void)updateEyebrowForIndex:(NSInteger)index
{
    NSString * const eyebrow = (index < (NSInteger)_eyebrows.count) ? _eyebrows[index] : nil;
    if (eyebrow.length > 0) {
        NSFont * const font = [NSFont systemFontOfSize:MacLCDesign.footnote.pointSize weight:NSFontWeightSemibold];
        NSDictionary * const attrs = @{
            NSFontAttributeName: font,
            NSKernAttributeName: @0.6,
            NSForegroundColorAttributeName: [NSColor colorWithWhite:1.0 alpha:0.75],
        };
        _eyebrowField.attributedStringValue = [[NSAttributedString alloc] initWithString:eyebrow.uppercaseString attributes:attrs];
        _eyebrowField.hidden = NO;
    } else {
        _eyebrowField.attributedStringValue = [[NSAttributedString alloc] initWithString:@""];
        _eyebrowField.hidden = YES;
    }
}

- (void)updateTextContentWithItem:(nullable MacLCAddonItem *)item logoImage:(nullable NSImage *)logoImage
{
    if (item == nil) {
        _eyebrowField.hidden = YES;
        _titleField.stringValue = @"";
        _titleLogoImageView.image = nil;
        _titleLogoImageView.hidden = YES;
        _factsField.stringValue = @"";
        _descriptionField.stringValue = @"";
        _playButton.enabled = NO;
        _detailsButton.enabled = NO;
        return;
    }

    [self updateEyebrowForIndex:_currentIndex];

    if (logoImage != nil) {
        const CGFloat maxW = 360.0;
        const CGFloat maxH = 120.0;
        const NSSize imgSize = logoImage.size;
        CGFloat fittedW = maxW;
        CGFloat fittedH = maxH;
        if (imgSize.width > 0.0 && imgSize.height > 0.0) {
            const CGFloat fitScale = MIN(maxW / imgSize.width, maxH / imgSize.height);
            fittedW = ceil(imgSize.width * fitScale);
            fittedH = ceil(imgSize.height * fitScale);
        }
        _titleLogoWidthConstraint.constant = fittedW;
        _titleLogoHeightConstraint.constant = fittedH;
        _titleLogoImageView.image = logoImage;
        _titleLogoImageView.hidden = NO;
        _titleField.hidden = YES;
    } else {
        _titleLogoImageView.image = nil;
        _titleLogoImageView.hidden = YES;
        _titleLogoWidthConstraint.constant = 0.0;
        _titleLogoHeightConstraint.constant = 0.0;
        _titleField.stringValue = item.name ?: @"";
        _titleField.hidden = NO;
    }

    _factsField.stringValue = MacLCWatchFactsLine(item.type, item.genres, item.releaseInfo, item.imdbRating);
    _descriptionField.stringValue = item.itemDescription ?: @"";

    _playButton.enabled = YES;
    _detailsButton.enabled = YES;
}

- (void)showItemAtIndex:(NSInteger)index animated:(BOOL)animated
{
    if (self.items.count == 0) {
        [self updateTextContentWithItem:nil logoImage:nil];
        _activePictureView.image = nil;
        return;
    }
    if (index < 0 || index >= (NSInteger)self.items.count) {
        return;
    }

    MacLCAddonItem * const item = self.items[index];
    NSURL * const bgURL = item.backgroundURL ?: item.posterURL;
    NSURL * const logoURL = item.logoURL;

    [_preloadRequest cancel];
    _preloadRequest = nil;
    [_preloadLogoRequest cancel];
    _preloadLogoRequest = nil;

    const NSSize viewSize = !NSIsEmptyRect(self.bounds) ? self.bounds.size : NSMakeSize(800.0, 480.0);
    const CGFloat scale = self.window.backingScaleFactor > 0.0 ? self.window.backingScaleFactor : 2.0;

    __weak typeof(self) weakSelf = self;
    __block NSImage *loadedBg = nil;
    __block NSImage *loadedLogo = nil;
    __block BOOL bgDone = (bgURL == nil);
    __block BOOL logoDone = (logoURL == nil);

    void (^checkComplete)(void) = ^{
        MacLCWatchHeroView * const strongSelf = weakSelf;
        if (strongSelf == nil || strongSelf.items.count <= (NSUInteger)index || strongSelf.items[index] != item) {
            return;
        }
        if (bgDone && logoDone) {
            [strongSelf applyTransitionToIndex:index backgroundImage:loadedBg logoImage:loadedLogo animated:animated];
        }
    };

    if (bgURL != nil) {
        MacLCWatchImageRequest *bgReq = nil;
        NSImage * const cachedBg = [MacLCWatchImageCache.sharedCache imageForURL:bgURL
                                                                      pointSize:viewSize
                                                                          scale:scale
                                                                        request:&bgReq
                                                                     completion:^(NSImage *image) {
            loadedBg = image;
            bgDone = YES;
            checkComplete();
        }];
        _preloadRequest = bgReq;
        if (cachedBg != nil) {
            loadedBg = cachedBg;
            bgDone = YES;
        }
    }

    if (logoURL != nil) {
        MacLCWatchImageRequest *logoReq = nil;
        NSImage * const cachedLogo = [MacLCWatchImageCache.sharedCache imageForURL:logoURL
                                                                        pointSize:NSMakeSize(360.0, 120.0)
                                                                            scale:scale
                                                                          request:&logoReq
                                                                       completion:^(NSImage *image) {
            loadedLogo = image;
            logoDone = YES;
            checkComplete();
        }];
        _preloadLogoRequest = logoReq;
        if (cachedLogo != nil) {
            loadedLogo = cachedLogo;
            logoDone = YES;
        }
    }

    if (bgDone && logoDone) {
        checkComplete();
    }
}

- (void)applyTransitionToIndex:(NSInteger)newIndex
               backgroundImage:(nullable NSImage *)bgImage
                     logoImage:(nullable NSImage *)logoImage
                      animated:(BOOL)animated
{
    _currentIndex = newIndex;
    MacLCAddonItem * const item = self.items[newIndex];
    const BOOL shouldAnimate = animated && !MacLCDesign.reducedMotion && _activePictureView.image != nil;

    for (NSInteger i = 0; i < (NSInteger)_dotButtons.count; i++) {
        [_dotButtons[i] setActive:(i == newIndex) animated:shouldAnimate];
    }

    if (!shouldAnimate) {
        _activePictureView.image = bgImage;
        _activePictureView.alphaValue = 1.0;
        _inactivePictureView.image = nil;
        _inactivePictureView.alphaValue = 0.0;
        [self updateTextContentWithItem:item logoImage:logoImage];
        _textStackView.alphaValue = 1.0;
    } else {
        _inactivePictureView.image = bgImage;
        _inactivePictureView.alphaValue = 0.0;

        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = 0.5;
            self->_inactivePictureView.animator.alphaValue = 1.0;
            self->_activePictureView.animator.alphaValue = 0.0;
        } completionHandler:^{
            MacLCWatchHeroPictureView * const temp = self->_activePictureView;
            self->_activePictureView = self->_inactivePictureView;
            self->_inactivePictureView = temp;
            self->_inactivePictureView.image = nil;
            self->_inactivePictureView.alphaValue = 0.0;
        }];

        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = 0.2;
            self->_textStackView.animator.alphaValue = 0.0;
        } completionHandler:^{
            [self updateTextContentWithItem:item logoImage:logoImage];
            [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx2) {
                ctx2.duration = 0.3;
                self->_textStackView.animator.alphaValue = 1.0;
            }];
        }];
    }

    NSAccessibilityPostNotification(self, NSAccessibilityLayoutChangedNotification);
}

- (void)startTimer
{
    [self stopTimer];
    if (self.items.count <= 1 || MacLCDesign.reducedMotion) {
        return;
    }
    __weak typeof(self) weakSelf = self;
    _advanceTimer = [NSTimer scheduledTimerWithTimeInterval:8.0 repeats:YES block:^(NSTimer *timer) {
        [weakSelf advanceTimerFired:timer];
    }];
}

- (void)stopTimer
{
    [_advanceTimer invalidate];
    _advanceTimer = nil;
}

- (void)restartTimer
{
    [self startTimer];
}

- (void)advanceTimerFired:(NSTimer *)timer
{
    if (self.items.count <= 1) {
        return;
    }
    if (MacLCDesign.reducedMotion) {
        return;
    }
    if (_isMouseOver) {
        return;
    }
    if (self.window == nil || !self.window.isVisible || !(self.window.occlusionState & NSWindowOcclusionStateVisible)) {
        return;
    }
    if (self.hiddenOrHasHiddenAncestor) {
        return;
    }

    const NSInteger nextIndex = (_currentIndex + 1) % self.items.count;
    [self showItemAtIndex:nextIndex animated:YES];
}

- (void)layout
{
    [super layout];

    const NSSize size = self.bounds.size;
    if (_items.count > 0 && !NSIsEmptyRect(self.bounds)) {
        if (fabs(size.width - _lastRequestedSize.width) > 64.0 || fabs(size.height - _lastRequestedSize.height) > 64.0) {
            _lastRequestedSize = size;
            if (_activePictureView.image == nil) {
                [self showItemAtIndex:_currentIndex animated:NO];
            }
        }
    }
}

- (void)viewDidMoveToWindow
{
    [super viewDidMoveToWindow];
    if (self.window != nil) {
        [self startTimer];
        if (_activePictureView.image == nil && _items.count > 0) {
            [self showItemAtIndex:_currentIndex animated:NO];
        }
    } else {
        [self stopTimer];
    }
}

- (void)updateTrackingAreas
{
    [super updateTrackingAreas];
    if (_trackingArea != nil) {
        [self removeTrackingArea:_trackingArea];
    }
    _trackingArea = [[NSTrackingArea alloc] initWithRect:self.bounds
                                                 options:(NSTrackingActiveInKeyWindow |
                                                          NSTrackingMouseEnteredAndExited |
                                                          NSTrackingInVisibleRect)
                                                   owner:self
                                                userInfo:nil];
    [self addTrackingArea:_trackingArea];
}

- (void)mouseEntered:(NSEvent *)event
{
    _isMouseOver = YES;
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = MacLCDesign.motionQuickDuration;
        self->_leftChevronButton.animator.alphaValue = 1.0;
        self->_rightChevronButton.animator.alphaValue = 1.0;
    }];
}

- (void)mouseExited:(NSEvent *)event
{
    _isMouseOver = NO;
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = MacLCDesign.motionQuickDuration;
        self->_leftChevronButton.animator.alphaValue = 0.0;
        self->_rightChevronButton.animator.alphaValue = 0.0;
    }];
}

- (void)playClicked:(id)sender
{
    if (_currentIndex < (NSInteger)_items.count && self.playHandler != nil) {
        self.playHandler(_items[_currentIndex]);
    }
}

- (void)detailsClicked:(id)sender
{
    if (_currentIndex < (NSInteger)_items.count && self.detailsHandler != nil) {
        self.detailsHandler(_items[_currentIndex]);
    }
}

- (void)previousClicked:(id)sender
{
    if (_items.count == 0) {
        return;
    }
    const NSInteger prevIndex = (_currentIndex - 1 + _items.count) % _items.count;
    [self showItemAtIndex:prevIndex animated:YES];
    [self restartTimer];
}

- (void)nextClicked:(id)sender
{
    if (_items.count == 0) {
        return;
    }
    const NSInteger nextIndex = (_currentIndex + 1) % _items.count;
    [self showItemAtIndex:nextIndex animated:YES];
    [self restartTimer];
}

- (void)dotClicked:(MacLCWatchHeroDotButton *)sender
{
    const NSInteger index = sender.tag;
    if (index >= 0 && index < (NSInteger)_items.count) {
        [self showItemAtIndex:index animated:YES];
        [self restartTimer];
    }
}

- (BOOL)acceptsFirstResponder
{
    return YES;
}

- (BOOL)canBecomeKeyView
{
    return YES;
}

- (void)keyDown:(NSEvent *)event
{
    if (event.keyCode == 123) { // Left arrow
        [self previousClicked:nil];
        return;
    }
    if (event.keyCode == 124) { // Right arrow
        [self nextClicked:nil];
        return;
    }
    if (event.keyCode == 36 || event.keyCode == 49) { // Return or Space
        [self playClicked:nil];
        return;
    }
    [super keyDown:event];
}

- (BOOL)isAccessibilityElement
{
    return YES;
}

- (NSAccessibilityRole)accessibilityRole
{
    return NSAccessibilityGroupRole;
}

- (nullable NSArray *)accessibilityChildren
{
    NSMutableArray * const children = [NSMutableArray array];
    if (!_playButton.hidden) {
        [children addObject:_playButton];
    }
    if (!_detailsButton.hidden) {
        [children addObject:_detailsButton];
    }
    [children addObjectsFromArray:_dotButtons];
    if (_leftChevronButton.alphaValue > 0.0) {
        [children addObject:_leftChevronButton];
    }
    if (_rightChevronButton.alphaValue > 0.0) {
        [children addObject:_rightChevronButton];
    }
    return children;
}

- (nullable NSString *)accessibilityLabel
{
    if (_items.count == 0 || _currentIndex >= (NSInteger)_items.count) {
        return _NS("Featured");
    }
    MacLCAddonItem * const item = _items[_currentIndex];
    NSString * const title = item.name ?: @"";
    NSString * const facts = MacLCWatchFactsLine(item.type, item.genres, item.releaseInfo, item.imdbRating);
    NSString * const desc = item.itemDescription ?: @"";
    return [NSString stringWithFormat:_NS("Featured, %@, %@, %@, page %ld of %lu"),
            title, facts, desc, (long)(_currentIndex + 1), (unsigned long)_items.count];
}

- (void)setScrollOffset:(CGFloat)offset
{
    if (MacLCDesign.reducedMotion) {
        offset = 0.0;
    }

    const CGFloat height = self.bounds.size.height;
    const CGFloat width = self.bounds.size.width;

    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    /* The picture lags behind while scrolling, so it must be cut at the
     * carousel's bottom edge (the shelves below would be covered); only that
     * edge: it still extends under the sidebar and the toolbar. */
    if (self.layer.mask == nil)
        self.layer.mask = [CALayer layer];
    self.layer.mask.backgroundColor = NSColor.blackColor.CGColor;
    const CGFloat far = 10000.0;
    self.layer.mask.frame = self.isFlipped ? CGRectMake(-far, -far, width + 2 * far, height + far)
                                           : CGRectMake(-far, 0.0, width + 2 * far, height + far);

    if (offset < 0.0 && height > 0.0) {
        /* Rubber-banding: picture grows from top edge, anchored at bottom centre. */
        const CGFloat scale = 1.0 + fabs(offset) / height;
        const CGFloat anchorY = self.isFlipped ? height : 0.0;
        CGAffineTransform t = CGAffineTransformMakeTranslation(width / 2.0, anchorY);
        t = CGAffineTransformScale(t, scale, scale);
        t = CGAffineTransformTranslate(t, -width / 2.0, -anchorY);
        _pictureContainerView.layer.transform = CATransform3DMakeAffineTransform(t);
        _textStackView.alphaValue = 1.0;
    } else if (offset > 0.0 && height > 0.0) {
        /* Scrolled up: parallax at half speed. */
        const CGFloat translateY = self.isFlipped ? (offset * 0.5) : (-offset * 0.5);
        _pictureContainerView.layer.transform = CATransform3DMakeTranslation(0.0, translateY, 0.0);

        /* Text block fades out over the first 60 % of carousel height. */
        const CGFloat fadeLimit = height * 0.60;
        const CGFloat alpha = (fadeLimit > 0.0) ? (1.0 - (offset / fadeLimit)) : 0.0;
        _textStackView.alphaValue = MAX(0.0, MIN(1.0, alpha));
    } else {
        _pictureContainerView.layer.transform = CATransform3DIdentity;
        _textStackView.alphaValue = 1.0;
    }

    [CATransaction commit];
}

@end
