/*****************************************************************************
 * MacLCWatchDiscovery.m: The Edit, streaming services, genres model
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

#import <Foundation/Foundation.h>
#import "addons/watch/MacLCWatchDiscovery.h"
#import "addons/MacLCAddons.h"

NSNotificationName const MacLCWatchDiscoveryDidChangeNotification = @"MacLCWatchDiscoveryDidChangeNotification";

extern NSData *MacLCWatchCollectionsPoolData(void);

#pragma mark - Helper Functions

static inline uint64_t SplitMix64(uint64_t *state)
{
    uint64_t z = (*state += 0x9e3779b97f4a7c15ULL);
    z = (z ^ (z >> 30)) * 0xbf58476d1ce4e5b9ULL;
    z = (z ^ (z >> 27)) * 0x94d049bb133111ebULL;
    return z ^ (z >> 31);
}

static NSString *NormalizeTitle(NSString *str)
{
    if (!str || str.length == 0) return @"";

    // 1. Fold case and diacritics
    NSString *folded = [str stringByFoldingWithOptions:(NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch)
                                                locale:[NSLocale currentLocale]];

    // 2. Drop punctuation
    NSCharacterSet *punct = [NSCharacterSet punctuationCharacterSet];
    NSMutableString *noPunct = [NSMutableString stringWithCapacity:folded.length];
    for (NSUInteger i = 0; i < folded.length; i++) {
        unichar c = [folded characterAtIndex:i];
        if (![punct characterIsMember:c]) {
            [noPunct appendFormat:@"%C", c];
        }
    }

    // 3. Trim whitespace
    NSString *trimmed = [noPunct stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    // 4. Drop leading "the "
    if ([trimmed hasPrefix:@"the "]) {
        trimmed = [[trimmed substringFromIndex:4] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    }

    return trimmed;
}

static NSString *CollectionsCachePath(void)
{
    NSArray<NSString *> *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *base = paths.firstObject ?: NSTemporaryDirectory();
    return [base stringByAppendingPathComponent:@"org.maclc.MacLC/Watch/collections.json"];
}

#pragma mark - Internal Request Class

@interface MacLCWatchDiscoveryRequest : MacLCAddonRequest
@property (getter=isCancelled) BOOL cancelled;
@property (readonly) NSMutableArray<MacLCAddonRequest *> *subrequests;
/// Starts the next searches; kept here so it lives as long as the request
/// (it only holds the request weakly), cleared when the work ends.
@property (copy, nullable) void (^scheduler)(void);
- (void)addSubrequest:(MacLCAddonRequest *)request;
@end

@implementation MacLCWatchDiscoveryRequest

- (instancetype)init
{
    self = [super init];
    if (self) {
        _subrequests = [NSMutableArray array];
    }
    return self;
}

- (void)addSubrequest:(MacLCAddonRequest *)request
{
    if (!request) return;
    @synchronized (self) {
        if (_cancelled) {
            [request cancel];
            return;
        }
        [_subrequests addObject:request];
    }
}

- (void)cancel
{
    @synchronized (self) {
        if (_cancelled) return;
        _cancelled = YES;
        _scheduler = nil;
        for (MacLCAddonRequest *req in _subrequests) {
            [req cancel];
        }
        [_subrequests removeAllObjects];
    }
}

@end

#pragma mark - MacLCWatchCollectionEntry

@interface MacLCWatchCollectionEntry ()
@property (copy) NSString *title;
@property NSInteger year;
@property (copy) NSString *type;
@end

@implementation MacLCWatchCollectionEntry

- (instancetype)initWithTitle:(NSString *)title year:(NSInteger)year type:(NSString *)type
{
    self = [super init];
    if (self) {
        _title = [title copy];
        _year = year;
        _type = [type copy];
    }
    return self;
}

@end

#pragma mark - MacLCWatchCollection

@interface MacLCWatchCollection ()
@property (copy) NSString *identifier;
@property (copy) NSString *title;
@property (copy) NSString *subtitle;
@property (copy) NSString *kind;
@property (copy) NSString *symbolName;
@property (copy) NSString *tintName;
@property (nullable) NSURL *sourceURL;
@property (copy) NSArray<MacLCWatchCollectionEntry *> *entries;
@property (copy, nullable) NSString *mediaType;
@end

@implementation MacLCWatchCollection

- (instancetype)initWithIdentifier:(NSString *)identifier
                             title:(NSString *)title
                          subtitle:(NSString *)subtitle
                              kind:(NSString *)kind
                        symbolName:(NSString *)symbolName
                          tintName:(NSString *)tintName
                         sourceURL:(nullable NSURL *)sourceURL
                           entries:(NSArray<MacLCWatchCollectionEntry *> *)entries
                         mediaType:(nullable NSString *)mediaType
{
    self = [super init];
    if (self) {
        _identifier = [identifier copy];
        _title = [title copy];
        _subtitle = [subtitle copy];
        _kind = [kind copy];
        _symbolName = [symbolName copy];
        _tintName = [tintName copy];
        _sourceURL = sourceURL;
        _entries = [entries copy] ?: @[];
        _mediaType = [mediaType copy];
    }
    return self;
}

@end

#pragma mark - MacLCWatchService

@interface MacLCWatchService ()
@property (copy) NSString *code;
@property (copy) NSString *name;
@property (copy) NSArray<NSString *> *types;
@end

@implementation MacLCWatchService

- (instancetype)initWithCode:(NSString *)code
                        name:(NSString *)name
                       types:(NSArray<NSString *> *)types
{
    self = [super init];
    if (self) {
        _code = [code copy];
        _name = [name copy];
        _types = [types copy] ?: @[];
    }
    return self;
}

@end

#pragma mark - MacLCWatchDiscovery

@interface MacLCWatchDiscovery ()
@property (nonatomic, copy, nullable) NSArray<MacLCWatchCollection *> *customPool;
@end

@implementation MacLCWatchDiscovery {
    NSMutableDictionary<NSString *, NSArray<MacLCAddonItem *> *> *_memoryCache;
}

+ (MacLCWatchDiscovery *)sharedDiscovery
{
    static MacLCWatchDiscovery *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[MacLCWatchDiscovery alloc] init];
    });
    return shared;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _memoryCache = [NSMutableDictionary dictionary];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handleAddonsDidChange:)
                                                     name:MacLCAddonsDidChangeNotification
                                                   object:nil];
    }
    return self;
}

- (instancetype)initWithPool:(NSArray<MacLCWatchCollection *> *)pool
{
    self = [self init];
    if (self) {
        _customPool = [pool copy];
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)handleAddonsDidChange:(NSNotification *)note
{
    if ([NSThread isMainThread]) {
        [[NSNotificationCenter defaultCenter] postNotificationName:MacLCWatchDiscoveryDidChangeNotification object:self];
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:MacLCWatchDiscoveryDidChangeNotification object:self];
        });
    }
}

#pragma mark - The Edit Pool & Parsing

- (NSArray<MacLCWatchCollection *> *)pool
{
    if (_customPool) {
        return _customPool;
    }
    static NSArray<MacLCWatchCollection *> *cachedPool = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSData *data = MacLCWatchCollectionsPoolData();
        if (data) {
            cachedPool = [self.class collectionsFromData:data] ?: @[];
        } else {
            cachedPool = @[];
        }
    });
    return cachedPool;
}

+ (nullable NSArray<MacLCWatchCollection *> *)collectionsFromData:(NSData *)data
{
    if (!data || data.length == 0) return nil;
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![json isKindOfClass:[NSDictionary class]]) return nil;

    id collectionsObj = json[@"collections"];
    if (![collectionsObj isKindOfClass:[NSArray class]]) return nil;

    NSMutableArray<MacLCWatchCollection *> *collections = [NSMutableArray array];
    for (id item in (NSArray *)collectionsObj) {
        if (![item isKindOfClass:[NSDictionary class]]) continue;
        NSDictionary *dict = (NSDictionary *)item;

        NSString *identifier = dict[@"id"] ?: dict[@"identifier"];
        NSString *title = dict[@"title"];
        if (![identifier isKindOfClass:[NSString class]] || identifier.length == 0) continue;
        if (![title isKindOfClass:[NSString class]] || title.length == 0) continue;

        NSString *subtitle = [dict[@"subtitle"] isKindOfClass:[NSString class]] ? dict[@"subtitle"] : @"";
        NSString *kind = [dict[@"kind"] isKindOfClass:[NSString class]] ? dict[@"kind"] : @"";
        NSString *symbolName = dict[@"symbolName"] ?: dict[@"symbol"];
        if (![symbolName isKindOfClass:[NSString class]] || symbolName.length == 0) {
            symbolName = @"film.fill";
        }
        NSString *tintName = dict[@"tintName"] ?: dict[@"tint"];
        if (![tintName isKindOfClass:[NSString class]] || tintName.length == 0) {
            tintName = @"blue";
        }
        NSURL *sourceURL = nil;
        NSString *sourceStr = dict[@"sourceURL"] ?: dict[@"source"];
        if ([sourceStr isKindOfClass:[NSString class]] && sourceStr.length > 0) {
            sourceURL = [NSURL URLWithString:sourceStr];
        }

        id entriesObj = dict[@"entries"] ?: dict[@"items"];
        NSMutableArray<MacLCWatchCollectionEntry *> *entries = [NSMutableArray array];
        if ([entriesObj isKindOfClass:[NSArray class]]) {
            for (id entryItem in (NSArray *)entriesObj) {
                if (![entryItem isKindOfClass:[NSDictionary class]]) continue;
                NSDictionary *entryDict = (NSDictionary *)entryItem;

                NSString *entryTitle = entryDict[@"title"] ?: entryDict[@"name"];
                if (![entryTitle isKindOfClass:[NSString class]] || entryTitle.length == 0) continue;

                NSInteger year = 0;
                id yearObj = entryDict[@"year"];
                if ([yearObj isKindOfClass:[NSNumber class]]) {
                    year = [yearObj integerValue];
                } else if ([yearObj isKindOfClass:[NSString class]]) {
                    year = [yearObj integerValue];
                }
                if (year <= 0) continue;

                NSString *type = entryDict[@"type"];
                if (![type isKindOfClass:[NSString class]]) continue;
                type = type.lowercaseString;
                if (![type isEqualToString:@"movie"] && ![type isEqualToString:@"series"]) continue;

                MacLCWatchCollectionEntry *entry = [[MacLCWatchCollectionEntry alloc] initWithTitle:entryTitle year:year type:type];
                [entries addObject:entry];
            }
        }

        NSString *mediaType = nil;
        if (entries.count > 0) {
            BOOL allMovies = YES;
            BOOL allSeries = YES;
            for (MacLCWatchCollectionEntry *e in entries) {
                if (![e.type isEqualToString:@"movie"]) allMovies = NO;
                if (![e.type isEqualToString:@"series"]) allSeries = NO;
            }
            if (allMovies) {
                mediaType = @"movie";
            } else if (allSeries) {
                mediaType = @"series";
            } else {
                mediaType = nil;
            }
        }

        MacLCWatchCollection *collection = [[MacLCWatchCollection alloc] initWithIdentifier:identifier
                                                                                      title:title
                                                                                   subtitle:subtitle
                                                                                       kind:kind
                                                                                 symbolName:symbolName
                                                                                   tintName:tintName
                                                                                  sourceURL:sourceURL
                                                                                    entries:[entries copy]
                                                                                  mediaType:mediaType];
        [collections addObject:collection];
    }

    return [collections copy];
}

#pragma mark - Rotation & Shuffle

- (NSArray<MacLCWatchCollection *> *)shuffleCandidates:(NSArray<MacLCWatchCollection *> *)candidates
                                              withSeed:(int64_t)seed
{
    NSMutableArray<MacLCWatchCollection *> *shuffled = [candidates mutableCopy];
    uint64_t state = (uint64_t)seed ^ 0x517cc1b727220a95ULL;
    for (NSUInteger i = shuffled.count - 1; i > 0; i--) {
        uint64_t r = SplitMix64(&state);
        NSUInteger j = (NSUInteger)(r % (i + 1));
        [shuffled exchangeObjectAtIndex:i withObjectAtIndex:j];
    }
    return [shuffled copy];
}

- (NSArray<MacLCWatchCollection *> *)pickFromCandidates:(NSArray<MacLCWatchCollection *> *)candidates
                                               avoiding:(NSArray<MacLCWatchCollection *> *)prevPicks
                                                   seed:(int64_t)seed
                                                  count:(NSUInteger)count
{
    if (candidates.count <= count) {
        return candidates;
    }

    NSMutableArray<MacLCWatchCollection *> *available = [NSMutableArray array];
    NSMutableSet<NSString *> *prevIds = [NSMutableSet set];
    for (MacLCWatchCollection *p in prevPicks) {
        [prevIds addObject:p.identifier];
    }

    for (MacLCWatchCollection *c in candidates) {
        if (![prevIds containsObject:c.identifier]) {
            [available addObject:c];
        }
    }

    if (available.count >= count) {
        NSArray<MacLCWatchCollection *> *shuffled = [self shuffleCandidates:available withSeed:seed];
        return [shuffled subarrayWithRange:NSMakeRange(0, count)];
    }

    NSMutableArray<MacLCWatchCollection *> *result = [NSMutableArray arrayWithArray:available];
    NSUInteger needed = count - available.count;
    NSArray<MacLCWatchCollection *> *shuffledPrev = [self shuffleCandidates:prevPicks withSeed:seed];
    NSUInteger takeFromPrev = MIN(needed, shuffledPrev.count);
    [result addObjectsFromArray:[shuffledPrev subarrayWithRange:NSMakeRange(0, takeFromPrev)]];
    return [result copy];
}

- (NSArray<MacLCWatchCollection *> *)picksFromCandidates:(NSArray<MacLCWatchCollection *> *)candidates
                                                   count:(NSUInteger)count
                                            targetPeriod:(NSInteger)targetPeriod
{
    if (candidates.count <= count) return candidates;

    if (targetPeriod >= 0) {
        NSArray<MacLCWatchCollection *> *picks = [self pickFromCandidates:candidates
                                                                 avoiding:@[]
                                                                     seed:0
                                                                    count:count];
        for (NSInteger p = 1; p <= targetPeriod; p++) {
            picks = [self pickFromCandidates:candidates
                                    avoiding:picks
                                        seed:p
                                       count:count];
        }
        return picks;
    } else {
        NSArray<MacLCWatchCollection *> *picks = [self pickFromCandidates:candidates
                                                                 avoiding:@[]
                                                                     seed:0
                                                                    count:count];
        for (NSInteger p = -1; p >= targetPeriod; p--) {
            picks = [self pickFromCandidates:candidates
                                    avoiding:picks
                                        seed:p
                                       count:count];
        }
        return picks;
    }
}

- (NSArray<MacLCWatchCollection *> *)editForDate:(NSDate *)date
                                       mediaType:(nullable NSString *)mediaType
                                           count:(NSUInteger)count
{
    if (count == 0) return @[];

    NSArray<MacLCWatchCollection *> *candidates = self.pool;
    if (mediaType.length > 0) {
        NSMutableArray<MacLCWatchCollection *> *filtered = [NSMutableArray array];
        for (MacLCWatchCollection *col in candidates) {
            if ([col.mediaType isEqualToString:mediaType]) {
                [filtered addObject:col];
            }
        }
        candidates = filtered;
    }

    if (candidates.count == 0) return @[];
    if (candidates.count <= count) return candidates;

    NSCalendar *calendar = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
    NSDateComponents *anchorComp = [[NSDateComponents alloc] init];
    anchorComp.year = 2026;
    anchorComp.month = 1;
    anchorComp.day = 5;
    anchorComp.hour = 0;
    anchorComp.minute = 0;
    anchorComp.second = 0;
    NSDate *anchor = [calendar dateFromComponents:anchorComp];

    NSDate *startOfDay = [calendar startOfDayForDate:date ?: [NSDate date]];
    NSDateComponents *diff = [calendar components:NSCalendarUnitDay fromDate:anchor toDate:startOfDay options:0];
    NSInteger days = diff.day;
    NSInteger periodIndex = (NSInteger)floor((double)days / 14.0);

    return [self picksFromCandidates:candidates count:count targetPeriod:periodIndex];
}

- (NSDate *)nextEditDateAfter:(NSDate *)date
{
    NSCalendar *calendar = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
    NSDateComponents *anchorComp = [[NSDateComponents alloc] init];
    anchorComp.year = 2026;
    anchorComp.month = 1;
    anchorComp.day = 5;
    anchorComp.hour = 0;
    anchorComp.minute = 0;
    anchorComp.second = 0;
    NSDate *anchor = [calendar dateFromComponents:anchorComp];

    NSDate *startOfDay = [calendar startOfDayForDate:date ?: [NSDate date]];
    NSDateComponents *diff = [calendar components:NSCalendarUnitDay fromDate:anchor toDate:startOfDay options:0];
    NSInteger days = diff.day;
    NSInteger periodIndex = (NSInteger)floor((double)days / 14.0);

    NSDateComponents *addComp = [[NSDateComponents alloc] init];
    addComp.day = (periodIndex + 1) * 14;
    return [calendar dateByAddingComponents:addComp toDate:anchor options:0];
}

#pragma mark - Matching

+ (nullable MacLCAddonItem *)matchEntry:(MacLCWatchCollectionEntry *)entry
                                inItems:(NSArray<MacLCAddonItem *> *)items
{
    if (!entry || items.count == 0) return nil;

    NSString *entryNorm = NormalizeTitle(entry.title);
    NSString *exactYearStr = [NSString stringWithFormat:@"%ld", (long)entry.year];
    NSString *prevYearStr = [NSString stringWithFormat:@"%ld", (long)(entry.year - 1)];
    NSString *nextYearStr = [NSString stringWithFormat:@"%ld", (long)(entry.year + 1)];

    MacLCAddonItem *bestItem = nil;
    NSInteger bestRank = NSIntegerMax;

    for (MacLCAddonItem *item in items) {
        if (![item.type isEqualToString:entry.type]) {
            continue;
        }

        NSString *itemNorm = NormalizeTitle(item.name);
        BOOL titleEqual = [itemNorm isEqualToString:entryNorm];
        BOOL titleContains = !titleEqual && (entryNorm.length > 0 && [itemNorm containsString:entryNorm]);
        if (!titleEqual && !titleContains) {
            continue;
        }

        BOOL exactYear = item.releaseInfo && [item.releaseInfo hasPrefix:exactYearStr];
        BOOL offByOne = !exactYear && item.releaseInfo && ([item.releaseInfo hasPrefix:prevYearStr] || [item.releaseInfo hasPrefix:nextYearStr]);
        if (!exactYear && !offByOne) {
            continue;
        }

        NSInteger rank = 3;
        if (titleEqual && exactYear) {
            rank = 0;
        } else if (titleEqual && offByOne) {
            rank = 1;
        } else if (titleContains && exactYear) {
            rank = 2;
        } else if (titleContains && offByOne) {
            rank = 3;
        }

        if (rank < bestRank) {
            bestRank = rank;
            bestItem = item;
            if (bestRank == 0) {
                break;
            }
        }
    }

    return bestItem;
}

#pragma mark - Resolving & Caching

- (void)saveCachedItems:(NSArray<MacLCAddonItem *> *)items forCollectionIdentifier:(NSString *)identifier
{
    if (!identifier || identifier.length == 0) return;

    NSString *filePath = CollectionsCachePath();
    NSString *dir = [filePath stringByDeletingLastPathComponent];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];

    NSMutableDictionary *allCached = nil;
    NSData *existingData = [NSData dataWithContentsOfFile:filePath];
    if (existingData) {
        id existingObj = [NSJSONSerialization JSONObjectWithData:existingData options:0 error:nil];
        if ([existingObj isKindOfClass:[NSDictionary class]]) {
            allCached = [existingObj mutableCopy];
        }
    }
    if (!allCached) {
        allCached = [NSMutableDictionary dictionary];
    }

    NSMutableArray<NSDictionary *> *metas = [NSMutableArray array];
    for (MacLCAddonItem *item in items) {
        NSMutableDictionary *m = [NSMutableDictionary dictionary];
        m[@"id"] = item.identifier ?: @"";
        m[@"name"] = item.name ?: @"";
        if (item.type) m[@"type"] = item.type;
        if (item.releaseInfo) m[@"releaseInfo"] = item.releaseInfo;
        if (item.posterURL.absoluteString) m[@"poster"] = item.posterURL.absoluteString;
        if (item.itemDescription) m[@"description"] = item.itemDescription;
        if (item.backgroundURL.absoluteString) m[@"background"] = item.backgroundURL.absoluteString;
        if (item.logoURL.absoluteString) m[@"logo"] = item.logoURL.absoluteString;
        if (item.genres.count > 0) m[@"genres"] = item.genres;
        if (item.imdbRating) m[@"imdbRating"] = item.imdbRating;
        if (item.runtime) m[@"runtime"] = item.runtime;
        [metas addObject:m];
    }

    allCached[identifier] = @{
        @"date": @([[NSDate date] timeIntervalSince1970]),
        @"metas": metas
    };

    NSData *outData = [NSJSONSerialization dataWithJSONObject:allCached options:0 error:nil];
    [outData writeToFile:filePath atomically:YES];
}

- (nullable NSArray<MacLCAddonItem *> *)loadCachedItemsForCollectionIdentifier:(NSString *)identifier
{
    if (!identifier || identifier.length == 0) return nil;

    NSString *filePath = CollectionsCachePath();
    NSData *data = [NSData dataWithContentsOfFile:filePath];
    if (!data) return nil;

    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![json isKindOfClass:[NSDictionary class]]) return nil;

    id entryObj = json[identifier];
    if (![entryObj isKindOfClass:[NSDictionary class]]) return nil;

    id dateObj = entryObj[@"date"];
    NSTimeInterval timestamp = 0;
    if ([dateObj isKindOfClass:[NSNumber class]]) {
        timestamp = [dateObj doubleValue];
    }
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (timestamp <= 0 || (now - timestamp > 30 * 86400) || (now < timestamp - 86400)) {
        return nil;
    }

    id metasObj = entryObj[@"metas"];
    if (![metasObj isKindOfClass:[NSArray class]]) return nil;

    MacLCAddon *addon = nil;
    for (MacLCAddon *a in [MacLCAddonStore sharedStore].installedAddons) {
        if ([a.identifier isEqualToString:@"com.linvo.cinemeta"]) {
            addon = a;
            break;
        }
    }
    if (!addon) {
        addon = [MacLCAddonStore sharedStore].installedAddons.firstObject;
    }
    if (!addon) {
        return nil;
    }

    NSDictionary *wrapper = @{ @"metas": metasObj };
    NSData *catalogData = [NSJSONSerialization dataWithJSONObject:wrapper options:0 error:nil];
    if (!catalogData) return nil;

    return [MacLCAddonStore itemsFromCatalogData:catalogData addon:addon error:nil];
}

- (nullable NSArray<MacLCAddonItem *> *)resolvedItemsForCollection:(MacLCWatchCollection *)collection
{
    if (!collection) return nil;
    NSArray<MacLCAddonItem *> *inMem = _memoryCache[collection.identifier];
    if (inMem) return inMem;

    NSArray<MacLCAddonItem *> *fromDisk = [self loadCachedItemsForCollectionIdentifier:collection.identifier];
    if (fromDisk) {
        _memoryCache[collection.identifier] = fromDisk;
        return fromDisk;
    }
    return nil;
}

- (MacLCAddonRequest *)resolveCollection:(MacLCWatchCollection *)collection
                              completion:(void (^)(NSArray<MacLCAddonItem *> *items))completion
{
    NSArray<MacLCAddonItem *> *cached = [self resolvedItemsForCollection:collection];
    if (cached) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(cached);
        });
        return [[MacLCAddonRequest alloc] init];
    }

    MacLCWatchDiscoveryRequest *overallRequest = [[MacLCWatchDiscoveryRequest alloc] init];
    NSArray<MacLCWatchCollectionEntry *> *entries = collection.entries;
    if (entries.count == 0) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(@[]);
        });
        return overallRequest;
    }

    NSUInteger count = entries.count;
    NSMutableArray *results = [NSMutableArray arrayWithCapacity:count];
    for (NSUInteger i = 0; i < count; i++) {
        [results addObject:[NSNull null]];
    }

    __block NSUInteger activeSearches = 0;
    __block NSUInteger nextIndex = 0;
    __block BOOL completed = NO;

    __weak typeof(self) weakSelf = self;
    __weak typeof(overallRequest) weakRequest = overallRequest;

    __block __weak void (^weakSchedule)(void) = nil;
    void (^scheduleBlock)(void) = ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        __strong typeof(weakRequest) strongRequest = weakRequest;
        if (!strongSelf || !strongRequest || strongRequest.isCancelled) return;

        while (activeSearches < 4 && nextIndex < entries.count) {
            NSUInteger idx = nextIndex++;
            activeSearches++;
            MacLCWatchCollectionEntry *entry = entries[idx];

            MacLCAddonRequest *subReq = [[MacLCAddonStore sharedStore] searchTitles:entry.title completion:^(NSArray<MacLCAddonSearchGroup *> *groups) {
                __strong typeof(weakSelf) innerSelf = weakSelf;
                __strong typeof(weakRequest) innerRequest = weakRequest;
                if (!innerSelf || !innerRequest || innerRequest.isCancelled) return;

                NSMutableArray<MacLCAddonItem *> *allItems = [NSMutableArray array];
                for (MacLCAddonSearchGroup *group in groups) {
                    if (group.items) {
                        [allItems addObjectsFromArray:group.items];
                    }
                }

                MacLCAddonItem *match = [MacLCWatchDiscovery matchEntry:entry inItems:allItems];
                if (match) {
                    results[idx] = match;
                }

                activeSearches--;
                if (activeSearches == 0 && nextIndex >= entries.count) {
                    if (!completed) {
                        completed = YES;
                        innerRequest.scheduler = nil;
                        NSMutableArray<MacLCAddonItem *> *matchedItems = [NSMutableArray array];
                        for (id obj in results) {
                            if (obj != [NSNull null]) {
                                [matchedItems addObject:(MacLCAddonItem *)obj];
                            }
                        }
                        NSArray<MacLCAddonItem *> *finalItems = [matchedItems copy];
                        innerSelf->_memoryCache[collection.identifier] = finalItems;
                        [innerSelf saveCachedItems:finalItems forCollectionIdentifier:collection.identifier];
                        [[NSNotificationCenter defaultCenter] postNotificationName:MacLCWatchDiscoveryDidChangeNotification object:innerSelf];
                        if (completion) {
                            completion(finalItems);
                        }
                    }
                } else {
                    void (^sched)(void) = weakSchedule;
                    if (sched) sched();
                }
            }];
            [strongRequest addSubrequest:subReq];
        }
    };

    weakSchedule = scheduleBlock;
    overallRequest.scheduler = scheduleBlock;
    scheduleBlock();

    return overallRequest;
}

#pragma mark - Services

+ (NSArray<MacLCWatchService *> *)knownServices
{
    static NSArray<MacLCWatchService *> *services = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        services = @[
            [[MacLCWatchService alloc] initWithCode:@"nfx" name:@"Netflix" types:@[@"movie", @"series"]],
            [[MacLCWatchService alloc] initWithCode:@"atp" name:@"Apple TV+" types:@[@"movie", @"series"]],
            [[MacLCWatchService alloc] initWithCode:@"dnp" name:@"Disney+" types:@[@"movie", @"series"]],
            [[MacLCWatchService alloc] initWithCode:@"amp" name:@"Prime Video" types:@[@"movie", @"series"]],
            [[MacLCWatchService alloc] initWithCode:@"hbm" name:@"HBO Max" types:@[@"movie", @"series"]],
            [[MacLCWatchService alloc] initWithCode:@"hlu" name:@"Hulu" types:@[@"movie", @"series"]],
            [[MacLCWatchService alloc] initWithCode:@"pmp" name:@"Paramount+" types:@[@"movie", @"series"]],
            [[MacLCWatchService alloc] initWithCode:@"pcp" name:@"Peacock" types:@[@"movie", @"series"]],
            [[MacLCWatchService alloc] initWithCode:@"cru" name:@"Crunchyroll" types:@[@"movie", @"series"]],
            [[MacLCWatchService alloc] initWithCode:@"mbi" name:@"MUBI" types:@[@"movie"]],
            [[MacLCWatchService alloc] initWithCode:@"crc" name:@"Criterion Channel" types:@[@"movie"]],
            [[MacLCWatchService alloc] initWithCode:@"cpd" name:@"Canal+" types:@[@"movie", @"series"]],
            [[MacLCWatchService alloc] initWithCode:@"sst" name:@"SkyShowtime" types:@[@"movie", @"series"]],
            [[MacLCWatchService alloc] initWithCode:@"bbc" name:@"BBC iPlayer" types:@[@"movie", @"series"]],
            [[MacLCWatchService alloc] initWithCode:@"stz" name:@"Starz" types:@[@"movie", @"series"]],
            [[MacLCWatchService alloc] initWithCode:@"shd" name:@"Shudder" types:@[@"movie", @"series"]],
            [[MacLCWatchService alloc] initWithCode:@"nfk" name:@"Netflix Kids" types:@[@"movie", @"series"]]
        ];
    });
    return services;
}

+ (nullable MacLCWatchService *)serviceForCode:(NSString *)code
{
    if (!code) return nil;
    for (MacLCWatchService *service in self.knownServices) {
        if ([service.code isEqualToString:code]) {
            return service;
        }
    }
    return nil;
}

- (nullable MacLCAddon *)servicesAddon
{
    for (MacLCAddon *addon in [MacLCAddonStore sharedStore].installedAddons) {
        if ([addon.identifier isEqualToString:@"pw.ers.netflix-catalog"]) {
            return addon;
        }
    }
    return nil;
}

- (nullable NSString *)decodedConfigurationString
{
    MacLCAddon *addon = self.servicesAddon;
    if (!addon) return nil;
    NSString *urlStr = addon.transportURL;
    if (!urlStr) return nil;

    NSRange manifestRange = [urlStr rangeOfString:@"/manifest.json" options:NSBackwardsSearch];
    if (manifestRange.location == NSNotFound) return nil;

    NSString *prefix = [urlStr substringToIndex:manifestRange.location];
    NSRange lastSlash = [prefix rangeOfString:@"/" options:NSBackwardsSearch];
    if (lastSlash.location == NSNotFound) return nil;

    NSString *segment = [prefix substringFromIndex:lastSlash.location + 1];
    if (segment.length == 0) return nil;

    segment = [segment stringByRemovingPercentEncoding] ?: segment;

    NSData *data = [[NSData alloc] initWithBase64EncodedString:segment options:NSDataBase64DecodingIgnoreUnknownCharacters];
    if (!data) return nil;

    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

- (nullable NSArray<NSString *> *)activeServiceCodes
{
    NSString *decoded = [self decodedConfigurationString];
    if (!decoded) {
        /* Installed from its plain address (no configuration): its default
         * catalogs are what it serves. */
        if (self.servicesAddon == nil)
            return nil;
        return [self.activeServices valueForKey:@"code"];
    }

    NSArray<NSString *> *parts = [decoded componentsSeparatedByString:@":"];
    if (parts.count == 0) return nil;

    NSString *providers = parts[0];
    if (providers.length == 0) return @[];

    NSArray<NSString *> *rawCodes = [providers componentsSeparatedByString:@","];
    NSMutableArray<NSString *> *codes = [NSMutableArray array];
    for (NSString *code in rawCodes) {
        NSString *trimmed = [code stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (trimmed.length > 0) {
            [codes addObject:trimmed];
        }
    }
    return [codes copy];
}

- (nullable NSString *)activeServicesCountry
{
    NSString *decoded = [self decodedConfigurationString];
    if (!decoded) return nil;

    NSArray<NSString *> *parts = [decoded componentsSeparatedByString:@":"];
    if (parts.count >= 3) {
        NSString *country = parts[2];
        if (country.length > 0) {
            return country;
        }
    }
    return nil;
}

- (NSArray<MacLCWatchService *> *)activeServices
{
    MacLCAddon *addon = self.servicesAddon;
    if (!addon) return @[];

    NSArray<MacLCAddonTitleCatalog *> *catalogs = [MacLCAddonStore titleCatalogsOfAddon:addon];
    NSMutableSet<NSString *> *catalogCodes = [NSMutableSet set];
    for (MacLCAddonTitleCatalog *cat in catalogs) {
        if (cat.identifier.length > 0) {
            [catalogCodes addObject:cat.identifier];
        }
    }

    /* The manifest's catalogs are the services (activeServiceCodes derives
     * from this list for an unconfigured add-on: never call it from here). */
    NSMutableArray<MacLCWatchService *> *result = [NSMutableArray array];
    for (MacLCWatchService *service in self.class.knownServices) {
        if ([catalogCodes containsObject:service.code]) {
            [result addObject:service];
        }
    }
    return [result copy];
}

- (nullable MacLCAddonTitleCatalog *)catalogForService:(MacLCWatchService *)service
                                                  type:(NSString *)type
{
    if (!service || !type) return nil;
    MacLCAddon *addon = self.servicesAddon;
    if (!addon) return nil;

    NSArray<MacLCAddonTitleCatalog *> *catalogs = [MacLCAddonStore titleCatalogsOfAddon:addon];
    for (MacLCAddonTitleCatalog *cat in catalogs) {
        if ([cat.identifier isEqualToString:service.code] && [cat.type isEqualToString:type]) {
            return cat;
        }
    }
    return nil;
}

+ (NSString *)servicesAddonAddressForCodes:(NSArray<NSString *> *)codes country:(NSString *)country
{
    NSString *joinedCodes = [codes componentsJoinedByString:@","] ?: @"";
    NSString *countryCode = country ?: @"";
    NSString *rawString = [NSString stringWithFormat:@"%@::%@", joinedCodes, countryCode];
    NSData *data = [rawString dataUsingEncoding:NSUTF8StringEncoding];
    NSString *b64 = [data base64EncodedStringWithOptions:0];
    NSString *escaped = [b64 stringByReplacingOccurrencesOfString:@"/" withString:@"%2F"];
    return [NSString stringWithFormat:@"https://7a82163c306e-stremio-netflix-catalog-addon.baby-beamup.club/%@/manifest.json", escaped];
}

- (void)setServiceCodes:(NSArray<NSString *> *)codes
                country:(NSString *)country
             completion:(void (^)(NSError * _Nullable error))completion
{
    MacLCAddon *existing = self.servicesAddon;

    if (codes.count == 0) {
        if (existing)
            [[MacLCAddonStore sharedStore] removeAddon:existing];
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:MacLCWatchDiscoveryDidChangeNotification object:self];
            if (completion) {
                completion(nil);
            }
        });
        return;
    }

    NSString *address = [self.class servicesAddonAddressForCodes:codes country:country];
    __weak typeof(self) weakSelf = self;
    [[MacLCAddonStore sharedStore] installFromAddress:address completion:^(MacLCAddon * _Nullable addon, BOOL replaced, NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (error) {
            if (completion) {
                completion(error);
            }
            return;
        }

        if (addon) {
            /* Only now: a failed fetch must leave the working add-on in place. */
            if (existing)
                [[MacLCAddonStore sharedStore] removeAddon:existing];
            [[MacLCAddonStore sharedStore] installAddon:addon];
        }

        [[NSNotificationCenter defaultCenter] postNotificationName:MacLCWatchDiscoveryDidChangeNotification object:strongSelf];
        if (completion) {
            completion(nil);
        }
    }];
}

#pragma mark - Genres

- (NSArray<NSString *> *)genresForMediaType:(nullable NSString *)mediaType
{
    NSString *targetType = mediaType ?: @"movie";
    for (MacLCAddonTitleCatalog *cat in [MacLCAddonStore sharedStore].titleCatalogs) {
        if ([cat.type isEqualToString:targetType] && [cat.identifier isEqualToString:@"top"]) {
            return cat.genres ?: @[];
        }
    }
    return @[];
}

+ (NSString *)symbolNameForGenre:(NSString *)genre
{
    static NSDictionary<NSString *, NSString *> *symbols = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        symbols = @{
            @"action": @"bolt.fill",
            @"adventure": @"map.fill",
            @"animation": @"paintpalette.fill",
            @"biography": @"person.text.rectangle.fill",
            @"comedy": @"face.smiling.inverse",
            @"crime": @"magnifyingglass",
            @"documentary": @"video.fill",
            @"drama": @"theatermasks.fill",
            @"family": @"figure.2.and.child.holdinghands",
            @"fantasy": @"wand.and.stars",
            @"history": @"building.columns.fill",
            @"horror": @"moon.haze.fill",
            @"music": @"music.note",
            @"mystery": @"questionmark.circle.fill",
            @"romance": @"heart.fill",
            @"sci-fi": @"sparkles",
            @"sport": @"sportscourt.fill",
            @"thriller": @"eye.fill",
            @"war": @"shield.fill",
            @"western": @"sun.dust.fill",
            @"reality-tv": @"camera.fill",
            @"talk show": @"mic.fill",
            @"game-show": @"gamecontroller.fill",
            @"news": @"newspaper.fill"
        };
    });
    NSString *key = genre.lowercaseString;
    return (key ? symbols[key] : nil) ?: @"film.fill";
}

+ (NSString *)tintNameForGenre:(NSString *)genre
{
    static NSDictionary<NSString *, NSString *> *tints = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        tints = @{
            @"action": @"orange",
            @"comedy": @"yellow",
            @"horror": @"indigo",
            @"romance": @"pink",
            @"sci-fi": @"cyan",
            @"drama": @"purple",
            @"documentary": @"green",
            @"thriller": @"red",
            @"animation": @"mint",
            @"family": @"teal",
            @"fantasy": @"purple",
            @"crime": @"brown",
            @"war": @"brown",
            @"western": @"orange",
            @"history": @"brown",
            @"mystery": @"indigo",
            @"adventure": @"green",
            @"biography": @"blue",
            @"sport": @"blue",
            @"music": @"pink"
        };
    });
    NSString *key = genre.lowercaseString;
    return (key ? tints[key] : nil) ?: @"blue";
}

+ (NSArray<MacLCAddonItem *> *)items:(NSArray<MacLCAddonItem *> *)items matchingGenre:(NSString *)genre
{
    if (!genre || genre.length == 0 || items.count == 0) return items ?: @[];
    NSMutableArray<MacLCAddonItem *> *matched = [NSMutableArray array];
    for (MacLCAddonItem *item in items) {
        for (NSString *g in item.genres) {
            if ([g caseInsensitiveCompare:genre] == NSOrderedSame) {
                [matched addObject:item];
                break;
            }
        }
    }
    return [matched copy];
}

@end
