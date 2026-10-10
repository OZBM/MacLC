/*****************************************************************************
 * MacLCWatchLibrary.m: what the person watched, how far, and what they saved
 * for later (history, resume points, favorites) for movies and shows
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

#import "addons/watch/MacLCWatchLibrary.h"
#import "addons/MacLCAddons.h"

NSNotificationName const MacLCWatchLibraryDidChangeNotification = @"MacLCWatchLibraryDidChange";
NSString * const MacLCWatchLibraryChangedTitlesKey = @"MacLCWatchLibraryChangedTitles";
const double MacLCWatchedFraction = 0.92;
const NSTimeInterval MacLCWatchMinimumPosition = 15.0;

static const NSInteger kFileVersion = 1;
/// Nothing is written sooner than this after the first unsaved change.
static const NSTimeInterval kWriteDelay = 1.5;
/// Notifications are at least this far apart.
static const NSTimeInterval kNotifyInterval = 2.0;
static const NSUInteger kContinueWatchingLimit = 30;
/// Less than this left (and not yet 92 %): the video is finished for resume purposes.
static const NSTimeInterval kMinimumRemaining = 30.0;
static const NSUInteger kPendingEpisodeListsLimit = 50;

#pragma mark - Small helpers

static NSString *StringOf(id value)
{
    return [value isKindOfClass:[NSString class]] ? value : nil;
}

static NSTimeInterval NumberOf(id value)
{
    if (![value isKindOfClass:[NSNumber class]]) {
        return 0;
    }
    double d = [value doubleValue];
    return isfinite(d) ? d : 0;
}

static NSTimeInterval CleanSeconds(NSTimeInterval value)
{
    return (isfinite(value) && value > 0) ? value : 0;
}

/// "S1, E3"
static NSString *EpisodeCode(NSInteger season, NSInteger episode)
{
    return [NSString stringWithFormat:@"S%ld, E%ld", (long)season, (long)episode];
}

/// "23 min left", "1 h 12 min left", "2 h left"; rounded up to the minute.
static NSString *TimeLeftText(NSTimeInterval remaining)
{
    NSInteger minutes = (NSInteger)ceil(remaining / 60.0);
    if (minutes < 1) {
        minutes = 1;
    }
    if (minutes < 60) {
        return [NSString stringWithFormat:@"%ld min left", (long)minutes];
    }
    if (minutes % 60 == 0) {
        return [NSString stringWithFormat:@"%ld h left", (long)(minutes / 60)];
    }
    return [NSString stringWithFormat:@"%ld h %ld min left", (long)(minutes / 60), (long)(minutes % 60)];
}

static NSString *ProgressKey(NSString *title, NSString *video)
{
    return [NSString stringWithFormat:@"%@\n%@", title, video];
}

#pragma mark - Snapshots (private initialisers)

@interface MacLCWatchProgress ()
- (instancetype)initWithTitle:(NSString *)title dictionary:(NSDictionary *)dict;
@end

@interface MacLCWatchResumeTarget ()
- (instancetype)initWithKind:(MacLCWatchResumeKind)kind
             videoIdentifier:(NSString *)videoIdentifier
                      season:(NSInteger)season
                     episode:(NSInteger)episode
                 episodeName:(nullable NSString *)episodeName
                    progress:(nullable MacLCWatchProgress *)progress
                  detailText:(NSString *)detailText;
@end

@interface MacLCWatchEntry ()
- (instancetype)initWithItem:(MacLCAddonItem *)item
                  dictionary:(NSDictionary *)dict
                         now:(NSDate *)now;
@end

#pragma mark - MacLCWatchProgress

@implementation MacLCWatchProgress

- (instancetype)initWithTitle:(NSString *)title dictionary:(NSDictionary *)dict
{
    self = [super init];
    if (self) {
        _titleIdentifier = [title copy];
        _videoIdentifier = [StringOf(dict[@"video"]) ?: title copy];
        _season = (NSInteger)NumberOf(dict[@"s"]);
        _episode = (NSInteger)NumberOf(dict[@"e"]);
        NSString *name = StringOf(dict[@"n"]);
        _episodeName = name.length > 0 ? [name copy] : nil;
        _position = CleanSeconds(NumberOf(dict[@"pos"]));
        _duration = CleanSeconds(NumberOf(dict[@"dur"]));
        _watched = [dict[@"watched"] isKindOfClass:[NSNumber class]] && [dict[@"watched"] boolValue];
        _lastPlayed = [NSDate dateWithTimeIntervalSince1970:NumberOf(dict[@"last"])];
        NSString *mrl = StringOf(dict[@"mrl"]);
        _streamMRL = mrl.length > 0 ? [mrl copy] : nil;
        NSString *label = StringOf(dict[@"label"]);
        _streamLabel = label.length > 0 ? [label copy] : nil;
    }
    return self;
}

- (double)fraction
{
    if (_watched) {
        return 1.0;
    }
    if (_duration <= 0) {
        return 0.0;
    }
    return MIN(1.0, MAX(0.0, _position / _duration));
}

- (NSTimeInterval)remaining
{
    if (_watched || _duration <= 0) {
        return 0;
    }
    return MAX(0, _duration - _position);
}

- (BOOL)canResume
{
    if (_watched || _position < MacLCWatchMinimumPosition) {
        return NO;
    }
    return _duration <= 0 || (_duration - _position) >= kMinimumRemaining;
}

@end

#pragma mark - MacLCWatchResumeTarget

@implementation MacLCWatchResumeTarget

- (instancetype)initWithKind:(MacLCWatchResumeKind)kind
             videoIdentifier:(NSString *)videoIdentifier
                      season:(NSInteger)season
                     episode:(NSInteger)episode
                 episodeName:(nullable NSString *)episodeName
                    progress:(nullable MacLCWatchProgress *)progress
                  detailText:(NSString *)detailText
{
    self = [super init];
    if (self) {
        _kind = kind;
        _videoIdentifier = [videoIdentifier copy];
        _season = season;
        _episode = episode;
        _episodeName = [episodeName copy];
        _progress = progress;
        _detailText = [detailText copy];
    }
    return self;
}

@end

#pragma mark - MacLCWatchEntry

@implementation MacLCWatchEntry {
    NSArray<NSDictionary *> *_episodeList;
    BOOL _isSeries;
}

- (instancetype)initWithItem:(MacLCAddonItem *)item
                  dictionary:(NSDictionary *)dict
                         now:(NSDate *)now
{
    self = [super init];
    if (!self) {
        return nil;
    }
    _item = item;
    _identifier = [StringOf(dict[@"id"]) copy];
    _type = [(StringOf(dict[@"type"]) ?: item.type) copy];
    NSTimeInterval fav = NumberOf(dict[@"favorite"]);
    _favorite = fav > 0;
    _favoriteDate = _favorite ? [NSDate dateWithTimeIntervalSince1970:fav] : nil;

    NSMutableArray<MacLCWatchProgress *> *all = [NSMutableArray array];
    for (id raw in [dict[@"progress"] isKindOfClass:[NSArray class]] ? dict[@"progress"] : @[]) {
        if ([raw isKindOfClass:[NSDictionary class]]) {
            [all addObject:[[MacLCWatchProgress alloc] initWithTitle:_identifier dictionary:raw]];
        }
    }
    [all sortWithOptions:NSSortStable usingComparator:^NSComparisonResult(MacLCWatchProgress *a, MacLCWatchProgress *b) {
        return [b.lastPlayed compare:a.lastPlayed];
    }];
    _allProgress = [all copy];
    _latestProgress = all.firstObject;
    _lastPlayed = _latestProgress.lastPlayed;

    /* Released episodes of the numbered seasons, in order. An episode without
     * a date counts as released (add-ons that give none). */
    NSTimeInterval nowSeconds = now.timeIntervalSince1970;
    NSMutableArray<NSDictionary *> *episodes = [NSMutableArray array];
    for (id raw in [dict[@"episodes"] isKindOfClass:[NSArray class]] ? dict[@"episodes"] : @[]) {
        if (![raw isKindOfClass:[NSDictionary class]] || !StringOf(raw[@"id"]) || NumberOf(raw[@"s"]) < 1) {
            continue;
        }
        NSTimeInterval released = NumberOf(raw[@"released"]);
        if (released > nowSeconds) {
            continue;
        }
        [episodes addObject:raw];
    }
    [episodes sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSTimeInterval sa = NumberOf(a[@"s"]), sb = NumberOf(b[@"s"]);
        if (sa != sb) {
            return sa < sb ? NSOrderedAscending : NSOrderedDescending;
        }
        NSTimeInterval ea = NumberOf(a[@"e"]), eb = NumberOf(b[@"e"]);
        if (ea != eb) {
            return ea < eb ? NSOrderedAscending : NSOrderedDescending;
        }
        return NSOrderedSame;
    }];
    _episodeList = episodes;
    _isSeries = [_type isEqualToString:@"series"] || [dict[@"episodes"] isKindOfClass:[NSArray class]];

    NSUInteger watchedEpisodes = 0;
    for (MacLCWatchProgress *p in _allProgress) {
        if (p.watched && p.season >= 1) {
            watchedEpisodes++;
        }
    }
    _watchedEpisodeCount = watchedEpisodes;

    if (_isSeries) {
        BOOL all_ = _episodeList.count > 0;
        for (NSDictionary *ep in _episodeList) {
            if (![self progressForVideo:StringOf(ep[@"id"])].watched) {
                all_ = NO;
                break;
            }
        }
        _watched = all_;
        _fraction = 0;
    } else {
        MacLCWatchProgress *movie = [self progressForVideo:_identifier] ?: _latestProgress;
        _watched = movie.watched;
        _fraction = (movie && !movie.watched) ? movie.fraction : 0;
    }
    _resumeTarget = [self computeResumeTarget];
    return self;
}

- (nullable MacLCWatchProgress *)progressForVideo:(NSString *)video
{
    for (MacLCWatchProgress *p in _allProgress) {
        if ([p.videoIdentifier isEqualToString:video]) {
            return p;
        }
    }
    return nil;
}

- (MacLCWatchResumeTarget *)resumeTargetForProgress:(MacLCWatchProgress *)p
{
    NSString *left = p.duration > 0 ? TimeLeftText(p.remaining) : @"Resume";
    NSString *text = _isSeries && (p.season > 0 || p.episode > 0) ?[NSString stringWithFormat:@"%@ · %@", EpisodeCode(p.season, p.episode), left] : left;
    return [[MacLCWatchResumeTarget alloc] initWithKind:MacLCWatchResumeKindResume
                                        videoIdentifier:p.videoIdentifier
                                                 season:p.season
                                                episode:p.episode
                                            episodeName:p.episodeName
                                               progress:p
                                             detailText:text];
}

- (MacLCWatchResumeTarget *)nextUpTargetForEpisode:(NSDictionary *)ep
{
    NSInteger season = (NSInteger)NumberOf(ep[@"s"]);
    NSInteger episode = (NSInteger)NumberOf(ep[@"e"]);
    NSString *name = StringOf(ep[@"n"]);
    if (name.length == 0) {
        name = nil;
    }
    NSString *code = EpisodeCode(season, episode);
    NSString *text = name ? [NSString stringWithFormat:@"Next: %@ · %@", code, name] : [NSString stringWithFormat:@"Next: %@", code];
    return [[MacLCWatchResumeTarget alloc] initWithKind:MacLCWatchResumeKindNextUp
                                        videoIdentifier:StringOf(ep[@"id"])
                                                 season:season
                                                episode:episode
                                            episodeName:name
                                               progress:nil
                                             detailText:text];
}

- (nullable MacLCWatchResumeTarget *)computeResumeTarget
{
    MacLCWatchProgress *latest = _latestProgress;
    if (!latest) {
        return nil;
    }
    if (!_isSeries) {
        MacLCWatchProgress *movie = [self progressForVideo:_identifier] ?: latest;
        return movie.canResume ? [self resumeTargetForProgress:movie] : nil;
    }
    if (latest.canResume) {
        return [self resumeTargetForProgress:latest];
    }
    NSUInteger index = NSNotFound;
    for (NSUInteger i = 0; i < _episodeList.count; i++) {
        if ([StringOf(_episodeList[i][@"id"]) isEqualToString:latest.videoIdentifier]) {
            index = i;
            break;
        }
    }
    if (index == NSNotFound) {
        return nil;
    }
    /* Started over (only a few seconds in): that same episode is next. */
    if (!latest.watched && latest.position < MacLCWatchMinimumPosition) {
        return [self nextUpTargetForEpisode:_episodeList[index]];
    }
    for (NSUInteger i = index + 1; i < _episodeList.count; i++) {
        NSDictionary *ep = _episodeList[i];
        MacLCWatchProgress *p = [self progressForVideo:StringOf(ep[@"id"])];
        if (p.watched) {
            continue;
        }
        if (p.canResume) {
            return [self resumeTargetForProgress:p];
        }
        return [self nextUpTargetForEpisode:ep];
    }
    return nil;
}

@end

#pragma mark - MacLCWatchLibrary

@interface MacLCWatchLibrary () {
    NSURL *_fileURL;
    NSRecursiveLock *_lock;          // guards everything below
    NSLock *_ioLock;                 // serialises serialize-and-write
    dispatch_queue_t _ioQueue;
    NSMutableDictionary<NSString *, NSMutableDictionary *> *_titles;
    NSMutableDictionary *_rootExtras;
    NSMutableArray *_orphans;        // entries of "titles" this version does not understand
    NSMutableDictionary<NSString *, MacLCWatchEntry *> *_entryCache;
    NSMutableDictionary<NSString *, NSArray *> *_pendingEpisodes;
    NSMutableSet<NSString *> *_unwatched; // ProgressKey of videos whose late saves are refused
    BOOL _readOnly;
    BOOL _dirty;
    BOOL _writeScheduled;
    NSUInteger _writeCount;
    NSMutableSet<NSString *> *_changedTitles;
    BOOL _changedEverything;
    BOOL _notifyScheduled;
    NSTimeInterval _lastNotify;
}
/// The clock; tests replace it.
@property (copy) NSDate * (^now)(void);
@property (readonly) NSUInteger writeCount;
@end

@implementation MacLCWatchLibrary

+ (MacLCWatchLibrary *)sharedLibrary
{
    static MacLCWatchLibrary *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *override = NSProcessInfo.processInfo.environment[@"MACLC_WATCH_DATA_DIR"];
        NSURL *directory;
        if (override.length > 0) {
            directory = [NSURL fileURLWithPath:override isDirectory:YES];
        } else {
            NSURL *support = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory
                                                                  inDomains:NSUserDomainMask].firstObject
                ?: [NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES];
            directory = [[support URLByAppendingPathComponent:@"org.maclc.MacLC" isDirectory:YES]
                         URLByAppendingPathComponent:@"Watch" isDirectory:YES];
        }
        shared = [[MacLCWatchLibrary alloc] initWithFileURL:[directory URLByAppendingPathComponent:@"library.json"]];
    });
    return shared;
}

- (instancetype)initWithFileURL:(NSURL *)fileURL
{
    self = [super init];
    if (self) {
        _fileURL = fileURL;
        _lock = [[NSRecursiveLock alloc] init];
        _ioLock = [[NSLock alloc] init];
        _ioQueue = dispatch_queue_create("org.maclc.watch-library", DISPATCH_QUEUE_SERIAL);
        _titles = [NSMutableDictionary dictionary];
        _rootExtras = [NSMutableDictionary dictionary];
        _orphans = [NSMutableArray array];
        _entryCache = [NSMutableDictionary dictionary];
        _pendingEpisodes = [NSMutableDictionary dictionary];
        _unwatched = [NSMutableSet set];
        _changedTitles = [NSMutableSet set];
        _now = ^NSDate * { return [NSDate date]; };
        [self load];
    }
    return self;
}

#pragma mark Loading

- (void)load
{
    NSData *data = [NSData dataWithContentsOfURL:_fileURL options:0 error:nil];
    if (data.length == 0) {
        return; // missing or empty: an empty library
    }
    id root = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil];
    id titles = [root isKindOfClass:[NSDictionary class]] ? root[@"titles"] : nil;
    if (![root isKindOfClass:[NSDictionary class]] || (titles && ![titles isKindOfClass:[NSArray class]])) {
        NSURL *bad = [_fileURL URLByAppendingPathExtension:@"bad"];
        [NSFileManager.defaultManager removeItemAtURL:bad error:nil];
        [NSFileManager.defaultManager moveItemAtURL:_fileURL toURL:bad error:nil];
        return;
    }
    NSMutableDictionary *dict = root;
    id version = dict[@"version"];
    if ([version isKindOfClass:[NSNumber class]] && [version integerValue] > kFileVersion) {
        _readOnly = YES; // a newer MacLC wrote it: look, never touch
    }
    for (NSString *key in dict) {
        if (![key isEqualToString:@"titles"]) {
            _rootExtras[key] = dict[key];
        }
    }
    for (id raw in titles ?: @[]) {
        NSString *identifier = [raw isKindOfClass:[NSDictionary class]] ? StringOf(raw[@"id"]) : nil;
        if (identifier.length == 0 || _titles[identifier]) {
            [_orphans addObject:raw];
        } else {
            /* Later code walks these as arrays of dictionaries. */
            for (NSString *listKey in @[@"progress", @"episodes"]) {
                id list = raw[listKey];
                if (list && ![list isKindOfClass:[NSArray class]]) {
                    [raw removeObjectForKey:listKey];
                } else if (list) {
                    [list filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id element, NSDictionary *bindings) {
                        return [element isKindOfClass:[NSDictionary class]];
                    }]];
                }
            }
            _titles[identifier] = raw;
        }
    }
}

#pragma mark Persistence

- (NSData *)serializedLocked
{
    NSMutableDictionary *root = [_rootExtras mutableCopy];
    root[@"version"] = @(kFileVersion);
    NSMutableArray *titles = [NSMutableArray array];
    for (NSString *identifier in [_titles.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        [titles addObject:_titles[identifier]];
    }
    [titles addObjectsFromArray:_orphans];
    root[@"titles"] = titles;
    if (![NSJSONSerialization isValidJSONObject:root]) {
        return nil;
    }
    return [NSJSONSerialization dataWithJSONObject:root options:NSJSONWritingSortedKeys error:nil];
}

- (NSUInteger)writeCount
{
    [_ioLock lock];
    NSUInteger count = _writeCount;
    [_ioLock unlock];
    return count;
}

- (void)flush
{
    [_ioLock lock];
    NSData *data = nil;
    [_lock lock];
    if (_dirty && !_readOnly) {
        data = [self serializedLocked];
    }
    _dirty = NO;
    [_lock unlock];
    if (data) {
        NSFileManager *fm = NSFileManager.defaultManager;
        [fm createDirectoryAtURL:[_fileURL URLByDeletingLastPathComponent]
     withIntermediateDirectories:YES
                      attributes:nil
                           error:nil];
        if ([data writeToURL:_fileURL options:NSDataWritingAtomic error:nil]) {
            _writeCount++;
        } else {
            [_lock lock];
            _dirty = YES; // the next change or flush tries again
            [_lock unlock];
        }
    }
    [_ioLock unlock];
}

/// Lock held. Something changed in the file's content.
- (void)setDirtyLocked
{
    _dirty = YES;
    if (_readOnly || _writeScheduled) {
        return;
    }
    _writeScheduled = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kWriteDelay * NSEC_PER_SEC)), _ioQueue, ^{
        [self->_lock lock];
        self->_writeScheduled = NO;
        [self->_lock unlock];
        [self flush];
    });
}

#pragma mark Notifications

/// Lock held. titles nil: everything changed.
- (void)noteChangedLocked:(nullable NSArray<NSString *> *)titles
{
    for (NSString *identifier in titles ?: @[]) {
        [_entryCache removeObjectForKey:identifier];
    }
    if (titles) {
        [_changedTitles addObjectsFromArray:titles];
    } else {
        [_entryCache removeAllObjects];
        _changedEverything = YES;
    }
    [self setDirtyLocked];
    if (_notifyScheduled) {
        return;
    }
    _notifyScheduled = YES;
    NSTimeInterval wait = MAX(0, _lastNotify + kNotifyInterval - [NSDate timeIntervalSinceReferenceDate]);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(wait * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self postNotification];
    });
}

- (void)postNotification
{
    [_lock lock];
    NSSet *changed = _changedEverything ? nil : [_changedTitles copy];
    [_changedTitles removeAllObjects];
    _changedEverything = NO;
    _notifyScheduled = NO;
    _lastNotify = [NSDate timeIntervalSinceReferenceDate];
    [_lock unlock];
    [NSNotificationCenter.defaultCenter postNotificationName:MacLCWatchLibraryDidChangeNotification
                                                      object:self
                                                    userInfo:changed ? @{MacLCWatchLibraryChangedTitlesKey: changed} : nil];
}

#pragma mark Entries

/// Lock held.
- (nullable MacLCWatchEntry *)entryLocked:(NSString *)identifier
{
    MacLCWatchEntry *cached = _entryCache[identifier];
    if (cached) {
        return cached;
    }
    NSDictionary *dict = _titles[identifier];
    NSDictionary *meta = dict[@"meta"];
    if (!dict || ![meta isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    MacLCAddonItem *item = [MacLCAddonItem itemFromRawMeta:meta addonTransportURL:StringOf(dict[@"addon"]) ?: @""];
    if (!item) {
        return nil;
    }
    MacLCWatchEntry *entry = [[MacLCWatchEntry alloc] initWithItem:item dictionary:dict now:_now()];
    _entryCache[identifier] = entry;
    return entry;
}

- (NSArray<MacLCWatchEntry *> *)entriesLocked:(BOOL (^)(MacLCWatchEntry *))filter
                                      sortedBy:(NSComparisonResult (^)(MacLCWatchEntry *, MacLCWatchEntry *))comparator
{
    NSMutableArray<MacLCWatchEntry *> *result = [NSMutableArray array];
    for (NSString *identifier in [_titles.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        MacLCWatchEntry *entry = [self entryLocked:identifier];
        if (entry && filter(entry)) {
            [result addObject:entry];
        }
    }
    [result sortWithOptions:NSSortStable usingComparator:comparator];
    return result;
}

- (nullable MacLCWatchEntry *)entryForTitle:(NSString *)titleIdentifier
{
    [_lock lock];
    MacLCWatchEntry *entry = [self entryLocked:titleIdentifier];
    [_lock unlock];
    return entry;
}

- (nullable MacLCWatchProgress *)progressForTitle:(NSString *)titleIdentifier video:(nullable NSString *)videoIdentifier
{
    MacLCWatchEntry *entry = [self entryForTitle:titleIdentifier];
    if (!videoIdentifier) {
        return entry.latestProgress;
    }
    return [entry progressForVideo:videoIdentifier];
}

- (NSArray<MacLCWatchEntry *> *)historyEntries
{
    [_lock lock];
    NSArray *result = [self entriesLocked:^BOOL(MacLCWatchEntry *e) { return e.latestProgress != nil; }
                                 sortedBy:^NSComparisonResult(MacLCWatchEntry *a, MacLCWatchEntry *b) {
        return [b.lastPlayed compare:a.lastPlayed];
    }];
    [_lock unlock];
    return result;
}

- (NSArray<MacLCWatchEntry *> *)continueWatchingEntries
{
    [_lock lock];
    NSArray *result = [self entriesLocked:^BOOL(MacLCWatchEntry *e) { return e.resumeTarget != nil; }
                                 sortedBy:^NSComparisonResult(MacLCWatchEntry *a, MacLCWatchEntry *b) {
        return [b.lastPlayed compare:a.lastPlayed];
    }];
    [_lock unlock];
    return result.count > kContinueWatchingLimit ? [result subarrayWithRange:NSMakeRange(0, kContinueWatchingLimit)] : result;
}

- (NSArray<MacLCWatchEntry *> *)favoriteEntries
{
    [_lock lock];
    NSArray *result = [self entriesLocked:^BOOL(MacLCWatchEntry *e) { return e.isFavorite; }
                                 sortedBy:^NSComparisonResult(MacLCWatchEntry *a, MacLCWatchEntry *b) {
        return [b.favoriteDate compare:a.favoriteDate];
    }];
    [_lock unlock];
    return result;
}

- (BOOL)isFavorite:(NSString *)titleIdentifier
{
    [_lock lock];
    BOOL favorite = NumberOf(_titles[titleIdentifier][@"favorite"]) > 0;
    [_lock unlock];
    return favorite;
}

#pragma mark Mutation helpers (lock held)

/// The stored meta of an item: its rawMeta, else one made from its properties.
static NSDictionary *MetaOfItem(MacLCAddonItem *item)
{
    NSMutableDictionary *meta = [item.rawMeta mutableCopy];
    if (!meta) {
        meta = [NSMutableDictionary dictionary];
        meta[@"id"] = item.identifier;
        meta[@"name"] = item.name;
        meta[@"releaseInfo"] = item.releaseInfo;
        meta[@"poster"] = item.posterURL.absoluteString;
        meta[@"description"] = item.itemDescription;
        meta[@"background"] = item.backgroundURL.absoluteString;
        meta[@"logo"] = item.logoURL.absoluteString;
        meta[@"genres"] = item.genres.count > 0 ? item.genres : nil;
        meta[@"imdbRating"] = item.imdbRating;
        meta[@"runtime"] = item.runtime;
    }
    if (!StringOf(meta[@"type"]).length) {
        meta[@"type"] = item.type; // the parser reads the type from the entry
    }
    return meta;
}

/// The title's dictionary, created (item stored in full) when new.
- (NSMutableDictionary *)titleLockedForItem:(MacLCAddonItem *)item create:(BOOL)create
{
    NSMutableDictionary *title = _titles[item.identifier];
    if (!title && !create) {
        return nil;
    }
    if (!title) {
        title = [NSMutableDictionary dictionary];
        title[@"id"] = item.identifier;
        _titles[item.identifier] = title;
        NSArray *episodes = _pendingEpisodes[item.identifier];
        if (episodes) {
            title[@"episodes"] = episodes;
            [_pendingEpisodes removeObjectForKey:item.identifier];
        }
        title[@"meta"] = MetaOfItem(item);
    } else if (item.rawMeta) {
        title[@"meta"] = MetaOfItem(item);
    }
    title[@"type"] = item.type;
    title[@"addon"] = item.addon.transportURL ?: @"";
    return title;
}

/// Drops a title with neither progress nor favorite.
- (void)pruneLocked:(NSString *)identifier
{
    NSDictionary *title = _titles[identifier];
    if (title && [title[@"progress"] count] == 0 && NumberOf(title[@"favorite"]) <= 0) {
        [_titles removeObjectForKey:identifier];
    }
}

+ (nullable NSMutableDictionary *)progressIn:(NSDictionary *)title video:(NSString *)video
{
    for (NSMutableDictionary *p in title[@"progress"]) {
        if ([StringOf(p[@"video"]) isEqualToString:video]) {
            return p;
        }
    }
    return nil;
}

- (void)removeProgressLocked:(NSString *)video title:(NSMutableDictionary *)title
{
    NSMutableDictionary *existing = [MacLCWatchLibrary progressIn:title video:video];
    if (existing) {
        [title[@"progress"] removeObject:existing];
    }
}

#pragma mark Recording

- (void)recordPosition:(NSTimeInterval)position
              duration:(NSTimeInterval)duration
               forItem:(MacLCAddonItem *)item
       videoIdentifier:(nullable NSString *)videoIdentifier
                season:(NSInteger)season
               episode:(NSInteger)episode
           episodeName:(nullable NSString *)episodeName
             streamMRL:(nullable NSString *)streamMRL
           streamLabel:(nullable NSString *)streamLabel
{
    position = CleanSeconds(position);
    duration = CleanSeconds(duration);
    NSString *video = videoIdentifier.length > 0 ? videoIdentifier : item.identifier;
    NSString *key = ProgressKey(item.identifier, video);

    [_lock lock];
    NSMutableDictionary *title = _titles[item.identifier];
    NSMutableDictionary *existing = title ? [MacLCWatchLibrary progressIn:title video:video] : nil;

    if ([_unwatched containsObject:key]) {
        /* The person forgot this video; a late save of the playback that was
         * running must not bring it back, but playing it again from the
         * start does. */
        if (position >= MacLCWatchMinimumPosition) {
            [_lock unlock];
            return;
        }
        [_unwatched removeObject:key];
    }
    if (!existing && position < MacLCWatchMinimumPosition) {
        [_lock unlock];
        return;
    }

    title = [self titleLockedForItem:item create:YES];
    if (!title[@"progress"]) {
        title[@"progress"] = [NSMutableArray array];
    }
    if (!existing) {
        existing = [NSMutableDictionary dictionary];
        existing[@"video"] = video;
        [title[@"progress"] addObject:existing];
    }
    existing[@"s"] = @(season);
    existing[@"e"] = @(episode);
    if (episodeName.length > 0) {
        existing[@"n"] = episodeName;
    }
    if (duration > 0) {
        existing[@"dur"] = @(duration);
    }
    existing[@"last"] = @(_now().timeIntervalSince1970);
    if (streamMRL.length > 0) {
        existing[@"mrl"] = streamMRL;
    }
    if (streamLabel.length > 0) {
        existing[@"label"] = streamLabel;
    }
    /* Watched stays watched while it plays on (only lastPlayed, stream and label
     * move); a save near the start is a restart, tracked normally again. */
    if ([existing[@"watched"] boolValue] && position < MacLCWatchMinimumPosition) {
        [existing removeObjectForKey:@"watched"];
    }
    if (![existing[@"watched"] boolValue]) {
        existing[@"pos"] = @(position);
        double knownDuration = NumberOf(existing[@"dur"]);
        if (knownDuration > 0 && position >= MacLCWatchedFraction * knownDuration) {
            existing[@"watched"] = @YES;
        }
    }
    [self noteChangedLocked:@[item.identifier]];
    [_lock unlock];
}

- (void)recordPosition:(NSTimeInterval)position
              duration:(NSTimeInterval)duration
               forItem:(MacLCAddonItem *)item
                 video:(nullable MacLCAddonVideo *)video
             streamMRL:(nullable NSString *)streamMRL
           streamLabel:(nullable NSString *)streamLabel
{
    [self recordPosition:position
                duration:duration
                 forItem:item
         videoIdentifier:video.identifier
                  season:video.season
                 episode:video.episode
             episodeName:video.name
               streamMRL:streamMRL
             streamLabel:streamLabel];
}

- (void)markWatched:(BOOL)watched forItem:(MacLCAddonItem *)item video:(nullable MacLCAddonVideo *)video
{
    [self markWatched:watched forItem:item targets:@[video ?: (id)NSNull.null]];
}

- (void)markWatched:(BOOL)watched forItem:(MacLCAddonItem *)item videos:(NSArray<MacLCAddonVideo *> *)videos
{
    [self markWatched:watched forItem:item targets:videos];
}

/// targets: MacLCAddonVideo, or NSNull for the movie itself.
- (void)markWatched:(BOOL)watched forItem:(MacLCAddonItem *)item targets:(NSArray *)targets
{
    [_lock lock];
    BOOL changed = NO;
    for (id target in targets) {
        MacLCAddonVideo *video = [target isKindOfClass:[MacLCAddonVideo class]] ? target : nil;
        NSString *videoId = video.identifier.length > 0 ? video.identifier : item.identifier;
        NSString *key = ProgressKey(item.identifier, videoId);
        if (watched) {
            [_unwatched removeObject:key];
            NSMutableDictionary *title = [self titleLockedForItem:item create:YES];
            if (!title[@"progress"]) {
                title[@"progress"] = [NSMutableArray array];
            }
            NSMutableDictionary *p = [MacLCWatchLibrary progressIn:title video:videoId];
            if (!p) {
                p = [NSMutableDictionary dictionary];
                p[@"video"] = videoId;
                [title[@"progress"] addObject:p];
            }
            p[@"s"] = @(video.season);
            p[@"e"] = @(video.episode);
            if (video.name.length > 0) {
                p[@"n"] = video.name;
            }
            double duration = NumberOf(p[@"dur"]);
            p[@"pos"] = @(duration > 0 ? duration : NumberOf(p[@"pos"]));
            p[@"watched"] = @YES;
            p[@"last"] = @(_now().timeIntervalSince1970);
            changed = YES;
        } else {
            NSMutableDictionary *title = _titles[item.identifier];
            if (title && [MacLCWatchLibrary progressIn:title video:videoId]) {
                [self removeProgressLocked:videoId title:title];
                [_unwatched addObject:key];
                changed = YES;
            }
        }
    }
    if (changed) {
        [self pruneLocked:item.identifier];
        [self noteChangedLocked:@[item.identifier]];
    }
    [_lock unlock];
}

- (void)updateEpisodes:(NSArray<MacLCAddonVideo *> *)videos forItem:(MacLCAddonItem *)item
{
    if (videos.count == 0 || [item.type isEqualToString:@"movie"]) {
        return;
    }
    NSMutableArray *episodes = [NSMutableArray arrayWithCapacity:videos.count];
    for (MacLCAddonVideo *video in videos) {
        NSMutableDictionary *ep = [NSMutableDictionary dictionary];
        ep[@"id"] = video.identifier;
        ep[@"s"] = @(video.season);
        ep[@"e"] = @(video.episode);
        if (video.name.length > 0) {
            ep[@"n"] = video.name;
        }
        if (video.released) {
            ep[@"released"] = @(video.released.timeIntervalSince1970);
        }
        [episodes addObject:ep];
    }
    [_lock lock];
    NSMutableDictionary *title = _titles[item.identifier];
    if (!title) {
        /* Not watched yet: keep the list until the title is. */
        if (_pendingEpisodes.count >= kPendingEpisodeListsLimit) {
            [_pendingEpisodes removeAllObjects];
        }
        _pendingEpisodes[item.identifier] = episodes;
    } else if (![title[@"episodes"] isEqual:episodes]) {
        title[@"episodes"] = episodes;
        [self noteChangedLocked:@[item.identifier]];
    }
    [_lock unlock];
}

- (void)removeFromHistory:(NSString *)titleIdentifier
{
    [_lock lock];
    NSMutableDictionary *title = _titles[titleIdentifier];
    if ([title[@"progress"] count] > 0) {
        for (NSDictionary *p in title[@"progress"]) {
            [_unwatched addObject:ProgressKey(titleIdentifier, StringOf(p[@"video"]) ?: titleIdentifier)];
        }
        [title removeObjectForKey:@"progress"];
        [self pruneLocked:titleIdentifier];
        [self noteChangedLocked:@[titleIdentifier]];
    }
    [_lock unlock];
}

- (void)clearHistory
{
    [_lock lock];
    BOOL changed = NO;
    for (NSString *identifier in _titles.allKeys) {
        NSMutableDictionary *title = _titles[identifier];
        if ([title[@"progress"] count] > 0) {
            for (NSDictionary *p in title[@"progress"]) {
                [_unwatched addObject:ProgressKey(identifier, StringOf(p[@"video"]) ?: identifier)];
            }
            [title removeObjectForKey:@"progress"];
            [self pruneLocked:identifier];
            changed = YES;
        }
    }
    if (changed) {
        [self noteChangedLocked:nil];
    }
    [_lock unlock];
}

#pragma mark Favorites

- (void)setFavorite:(BOOL)favorite forItem:(MacLCAddonItem *)item
{
    [_lock lock];
    BOOL already = NumberOf(_titles[item.identifier][@"favorite"]) > 0;
    if (favorite && !already) {
        NSMutableDictionary *title = [self titleLockedForItem:item create:YES];
        title[@"favorite"] = @(_now().timeIntervalSince1970);
        [self noteChangedLocked:@[item.identifier]];
    } else if (!favorite && already) {
        [_titles[item.identifier] removeObjectForKey:@"favorite"];
        [self pruneLocked:item.identifier];
        [self noteChangedLocked:@[item.identifier]];
    }
    [_lock unlock];
}

- (void)clearFavorites
{
    [_lock lock];
    BOOL changed = NO;
    for (NSString *identifier in _titles.allKeys) {
        if (NumberOf(_titles[identifier][@"favorite"]) > 0) {
            [_titles[identifier] removeObjectForKey:@"favorite"];
            [self pruneLocked:identifier];
            changed = YES;
        }
    }
    if (changed) {
        [self noteChangedLocked:nil];
    }
    [_lock unlock];
}

@end
