/*****************************************************************************
 * MacLCYouTubeService.m: YouTube lists and details through yt-dlp, with a
 * cache, and playback through MacLC's own player
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

#import "youtube/MacLCYouTubeService.h"

#import <CommonCrypto/CommonDigest.h>

#import "youtube/MacLCYouTubeAccount.h"
#import "webvideo/MacLCWebVideoResolver.h"
#import "windows/VLCOpenInputMetadata.h"
#import "main/VLCMain.h"
#import "playqueue/VLCPlayQueueController.h"
#import "playqueue/VLCPlayerController.h"
#import "library/VLCInputItem.h"

NSErrorDomain const MacLCYouTubeErrorDomain = @"MacLCYouTubeErrorDomain";

/* In MacLCYouTubeModel.m (Foundation only, so the unit tests reach them). */
extern MacLCYouTubePage *MacLCYouTubeMergedPage(NSString *title, NSArray<MacLCYouTubePage *> *pages, NSUInteger limit);
extern NSInteger MacLCYouTubeClassifyExtractorError(NSString *stderrText, NSString * _Nullable * _Nullable message);

static const NSTimeInterval kTTLFeed = 15 * 60;
static const NSTimeInterval kTTLCollection = 60 * 60;
static const NSTimeInterval kTTLDetails = 24 * 60 * 60;
static const NSUInteger kMaxRunning = 4;
static const NSTimeInterval kTaskTimeout = 60;

#pragma mark - Categories

@interface MacLCYouTubeCategory ()
@property (readwrite, copy) NSString *identifier;
@property (readwrite, copy) NSString *title;
@end

@implementation MacLCYouTubeCategory

+ (instancetype)categoryWithIdentifier:(NSString *)identifier title:(NSString *)title
{
    MacLCYouTubeCategory * const c = [[MacLCYouTubeCategory alloc] init];
    c.identifier = identifier;
    c.title = title;
    return c;
}

+ (NSArray<MacLCYouTubeCategory *> *)homeCategories
{
    static NSArray<MacLCYouTubeCategory *> *categories;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        categories = @[
            [self categoryWithIdentifier:@"all" title:@"All"],
            [self categoryWithIdentifier:@"music" title:@"Music"],
            [self categoryWithIdentifier:@"gaming" title:@"Gaming"],
            [self categoryWithIdentifier:@"news" title:@"News"],
            [self categoryWithIdentifier:@"sports" title:@"Sports"],
            [self categoryWithIdentifier:@"movies" title:@"Movies & Trailers"],
            [self categoryWithIdentifier:@"learning" title:@"Learning"],
            [self categoryWithIdentifier:@"technology" title:@"Technology"],
            [self categoryWithIdentifier:@"cooking" title:@"Cooking"],
            [self categoryWithIdentifier:@"travel" title:@"Travel"],
            [self categoryWithIdentifier:@"podcasts" title:@"Podcasts"],
            [self categoryWithIdentifier:@"live" title:@"Live"],
        ];
    });
    return categories;
}

@end

/* Signed-out Home: one search per topic, "this week" + "sort by view count"
 * (sp CAMSBAgDEAE%3D; live: CAMSAkAB, live streams by audience), worded in
 * the person's language. Measured live on 2026-10-09, see
 * .agents/reports/youtube-fixtures/README.md. Languages not listed use "en". */
static NSString * const kSortWeekViews = @"CAMSBAgDEAE%3D";
static NSString * const kSortLiveViews = @"CAMSAkAB";

static NSDictionary<NSString *, NSString *> *HomeQueries(NSString *language)
{
    static NSDictionary *tables;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        tables = @{
            @"en": @{@"music": @"official music video", @"gaming": @"gaming", @"news": @"world news",
                     @"sports": @"sports highlights", @"movies": @"official trailer", @"learning": @"tutorial",
                     @"technology": @"tech review", @"cooking": @"recipe", @"travel": @"travel vlog",
                     @"podcasts": @"full episode podcast", @"live": @"live"},
            @"fr": @{@"music": @"clip officiel", @"gaming": @"jeux vidéo", @"news": @"actualités",
                     @"sports": @"résumé match", @"movies": @"au cinéma", @"learning": @"documentaire",
                     @"technology": @"avis smartphone", @"cooking": @"recette facile et rapide",
                     @"travel": @"vlog voyage", @"podcasts": @"interview complète", @"live": @"en direct"},
        };
    });
    return tables[language] ?: tables[@"en"];
}

/* The topics "All" is made of when signed out. */
static NSArray<NSString *> *HomeMixTopics(void)
{
    return @[@"music", @"gaming", @"sports", @"movies"];
}

#pragma mark - Request

@interface MacLCYouTubeRequest ()
@property (nonatomic) BOOL cancelled;
@property (nonatomic) BOOL finished;
@property (nonatomic, strong, nullable) NSTask *task;
@property (nonatomic, copy, nullable) void (^cancelHandler)(MacLCYouTubeRequest *request);
@property (nonatomic, copy, nullable) NSArray<MacLCYouTubeRequest *> *children;
@end

@implementation MacLCYouTubeRequest

- (void)cancel
{
    if (self.cancelled || self.finished) {
        return;
    }
    self.cancelled = YES;
    NSTask * const task = self.task;
    /* -terminate on a task that is not running raises. */
    if (task != nil && task.isRunning) {
        [task terminate];
    }
    for (MacLCYouTubeRequest *child in self.children) {
        [child cancel];
    }
    void (^handler)(MacLCYouTubeRequest *) = self.cancelHandler;
    self.cancelHandler = nil;
    if (handler) {
        handler(self);
    }
}

@end

#pragma mark - Cache entry

@interface MacLCYouTubeCacheEntry : NSObject
@property (nonatomic, copy) NSData *data;
@property (nonatomic, copy) NSDate *date;
@end
@implementation MacLCYouTubeCacheEntry
@end

typedef void (^MacLCYouTubeDataCompletion)(NSData * _Nullable data, NSError * _Nullable error);

#pragma mark - Service

@interface MacLCYouTubeService ()
{
    NSCache<NSString *, MacLCYouTubeCacheEntry *> *_memoryCache;
    NSMutableArray<MacLCYouTubeRequest *> *_pending;   // newest last, started newest first
    NSMutableDictionary<NSValue *, NSDictionary *> *_jobs;
    NSUInteger _running;
    dispatch_queue_t _ioQueue;
}
@end

@implementation MacLCYouTubeService

+ (MacLCYouTubeService *)sharedService
{
    static MacLCYouTubeService *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        shared = [[MacLCYouTubeService alloc] init];
    });
    return shared;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _memoryCache = [[NSCache alloc] init];
        _memoryCache.countLimit = 80;
        _pending = [NSMutableArray array];
        _jobs = [NSMutableDictionary dictionary];
        _ioQueue = dispatch_queue_create("org.maclc.youtube.io", DISPATCH_QUEUE_SERIAL);
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(accountDidChange:)
                                                     name:MacLCYouTubeAccountDidChangeNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)accountDidChange:(NSNotification *)note
{
    [self invalidateCache];
}

- (BOOL)isExtractorAvailable
{
    MacLCWebVideoResolver * const resolver = MacLCWebVideoResolver.sharedResolver;
    if (resolver.extractorPath == nil) {
        [resolver refreshExtractorPath];
    }
    return resolver.extractorPath != nil;
}

#pragma mark Helpers

+ (NSString *)languageCode
{
    NSString * const first = NSLocale.preferredLanguages.firstObject ?: @"en";
    return [[first componentsSeparatedByString:@"-"].firstObject lowercaseString];
}

static NSError *ServiceError(MacLCYouTubeError code, NSString *description)
{
    return [NSError errorWithDomain:MacLCYouTubeErrorDomain code:code userInfo:@{NSLocalizedDescriptionKey: description}];
}

static NSString *EncodedQuery(NSString *query)
{
    NSMutableCharacterSet * const allowed = [NSCharacterSet.URLQueryAllowedCharacterSet mutableCopy];
    [allowed removeCharactersInString:@"&+=#?/%"];
    return [query stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: @"";
}

static NSString *FixtureSafe(NSString *s)
{
    NSString *r = [[s lowercaseString] stringByReplacingOccurrencesOfString:@" " withString:@"_"];
    r = [r stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    return r;
}

static NSString *SearchURLString(NSString *query, MacLCYouTubeSearchFilter filter, NSString *explicitSP)
{
    NSString *sp = explicitSP;
    switch (filter) {
        case MacLCYouTubeSearchFilterVideos: sp = sp ?: @"EgIQAQ%3D%3D"; break;
        case MacLCYouTubeSearchFilterChannels: sp = sp ?: @"EgIQAg%3D%3D"; break;
        case MacLCYouTubeSearchFilterPlaylists: sp = sp ?: @"EgIQAw%3D%3D"; break;
        case MacLCYouTubeSearchFilterAll: break;
    }
    NSString * const base = [@"https://www.youtube.com/results?search_query=" stringByAppendingString:EncodedQuery(query)];
    return sp != nil ? [base stringByAppendingFormat:@"&sp=%@", sp] : base;
}

static NSString *FilterName(MacLCYouTubeSearchFilter filter)
{
    switch (filter) {
        case MacLCYouTubeSearchFilterAll: return @"all";
        case MacLCYouTubeSearchFilterVideos: return @"videos";
        case MacLCYouTubeSearchFilterChannels: return @"channels";
        case MacLCYouTubeSearchFilterPlaylists: return @"playlists";
    }
    return @"all";
}

static NSString *ChannelKeyPart(NSURL *url)
{
    NSArray<NSString *> * const parts = [url.path componentsSeparatedByString:@"/"];
    if (parts.count > 2 && [@[@"channel", @"c", @"user"] containsObject:parts[1]]) {
        return parts[2];
    }
    if (parts.count > 1 && [parts[1] hasPrefix:@"@"]) {
        return [parts[1] substringFromIndex:1];
    }
    return FixtureSafe(url.path.lastPathComponent);
}

/* The channel address without any tab, plus the tab. */
static NSString *ChannelTabURLString(NSURL *url, MacLCYouTubeChannelTab tab)
{
    NSMutableArray<NSString *> *parts = [[url.path componentsSeparatedByString:@"/"] mutableCopy];
    while (parts.count > 1 && [@[@"", @"videos", @"streams", @"live", @"playlists", @"featured", @"shorts", @"about", @"community", @"releases"] containsObject:parts.lastObject]
           && !([parts.lastObject length] == 0 && parts.count <= 2)) {
        [parts removeLastObject];
    }
    NSString *path = [parts componentsJoinedByString:@"/"];
    NSString * const name = tab == MacLCYouTubeChannelTabLive ? @"streams" : tab == MacLCYouTubeChannelTabPlaylists ? @"playlists" : @"videos";
    return [NSString stringWithFormat:@"https://www.youtube.com%@/%@", path, name];
}

static NSString *TabName(MacLCYouTubeChannelTab tab)
{
    return tab == MacLCYouTubeChannelTabLive ? @"live" : tab == MacLCYouTubeChannelTabPlaylists ? @"playlists" : @"videos";
}

static NSString *PlaylistIdentifierFromURL(NSURL *url)
{
    NSURLComponents * const comps = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    for (NSURLQueryItem *q in comps.queryItems) {
        if ([q.name isEqualToString:@"list"] && q.value.length > 0) {
            return q.value;
        }
    }
    return nil;
}

- (NSString *)cachePath:(NSString *)cacheKey
{
    NSString * const base = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    NSData * const keyData = [cacheKey dataUsingEncoding:NSUTF8StringEncoding];
    CC_SHA256(keyData.bytes, (CC_LONG)keyData.length, digest);
    NSMutableString * const hash = [NSMutableString string];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) {
        [hash appendFormat:@"%02x", digest[i]];
    }
    return [[[base stringByAppendingPathComponent:@"org.maclc.MacLC"] stringByAppendingPathComponent:@"YouTube"]
            stringByAppendingPathComponent:[hash stringByAppendingString:@".json"]];
}

- (void)invalidateCache
{
    [_memoryCache removeAllObjects];
    NSString * const dir = [[self cachePath:@"x"] stringByDeletingLastPathComponent];
    dispatch_async(_ioQueue, ^{
        [[NSFileManager defaultManager] removeItemAtPath:dir error:NULL];
    });
}

#pragma mark Fetching

/* One yt-dlp document. fixtureKey: the replay name; cacheKey: includes
 * everything that changes the answer (target, limit, account). */
- (MacLCYouTubeRequest *)fetchTarget:(NSString *)target
                                flat:(BOOL)flat
                               limit:(NSUInteger)limit
                          fixtureKey:(NSString *)fixtureKey
                                 ttl:(NSTimeInterval)ttl
                       needsAccount:(BOOL)needsAccount
                          completion:(MacLCYouTubeDataCompletion)completion
{
    MacLCYouTubeRequest * const request = [[MacLCYouTubeRequest alloc] init];
    MacLCYouTubeDataCompletion done = ^(NSData *data, NSError *error) {
        if (request.cancelled || request.finished) {
            return;
        }
        request.finished = YES;
        completion(data, error);
    };

    NSString * const fixtures = NSProcessInfo.processInfo.environment[@"MACLC_DEBUG_YOUTUBE_FIXTURES"];
    if (fixtures.length > 0) {
        NSString * const path = [[fixtures stringByAppendingPathComponent:fixtureKey] stringByAppendingPathExtension:@"json"];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NSData * const data = [NSData dataWithContentsOfFile:path];
            done(data, data != nil ? nil : ServiceError(MacLCYouTubeErrorNetwork, [NSString stringWithFormat:@"No recorded answer for %@.", fixtureKey]));
        });
        return request;
    }

    MacLCYouTubeAccount * const account = MacLCYouTubeAccount.sharedAccount;
    if (needsAccount && !account.signedIn) {
        dispatch_async(dispatch_get_main_queue(), ^{
            done(nil, ServiceError(MacLCYouTubeErrorSignInRequired, @"Sign in to see this."));
        });
        return request;
    }
    if (!self.extractorAvailable) {
        dispatch_async(dispatch_get_main_queue(), ^{
            done(nil, ServiceError(MacLCYouTubeErrorExtractorMissing, @"yt-dlp is not installed."));
        });
        return request;
    }

    NSString * const cacheKey = [NSString stringWithFormat:@"%@|%@|%d|%lu", account.signedIn ? @"in" : @"out", target, flat, (unsigned long)limit];
    NSDate * const now = [NSDate date];
    MacLCYouTubeCacheEntry *entry = [_memoryCache objectForKey:cacheKey];
    if (entry == nil) {
        NSString * const path = [self cachePath:cacheKey];
        NSDictionary * const attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:NULL];
        NSData * const data = attributes != nil ? [NSData dataWithContentsOfFile:path] : nil;
        if (data != nil) {
            entry = [[MacLCYouTubeCacheEntry alloc] init];
            entry.data = data;
            entry.date = attributes.fileModificationDate ?: [NSDate distantPast];
            [_memoryCache setObject:entry forKey:cacheKey];
        }
    }
    if (entry != nil && [now timeIntervalSinceDate:entry.date] < ttl) {
        NSData * const data = entry.data;
        dispatch_async(dispatch_get_main_queue(), ^{
            done(data, nil);
        });
        return request;
    }

    NSMutableArray<NSString *> * const arguments = [@[@"--ignore-config", @"--no-warnings", @"--no-progress",
                                                       @"--socket-timeout", @"15", @"-J"] mutableCopy];
    if (flat) {
        [arguments addObject:@"--flat-playlist"];
        if (limit > 0) {
            [arguments addObjectsFromArray:@[@"--playlist-end", [NSString stringWithFormat:@"%lu", (unsigned long)limit]]];
        }
    }
    /* No "--extractor-args youtube:lang=…": with a language other than English
     * the flat lists' view_count is the number before the abbreviation
     * ("847 k vues" -> 847). Measured with yt-dlp 2025.11.12. */
    [arguments addObjectsFromArray:account.extractorArguments];
    [arguments addObject:@"--"];
    [arguments addObject:target];

    __weak MacLCYouTubeService *weakSelf = self;
    MacLCYouTubeDataCompletion finish = ^(NSData *data, NSError *error) {
        if (data != nil && error == nil) {
            MacLCYouTubeCacheEntry * const fresh = [[MacLCYouTubeCacheEntry alloc] init];
            fresh.data = data;
            fresh.date = [NSDate date];
            [weakSelf storeEntry:fresh forKey:cacheKey];
        }
        done(data, error);
    };
    [self enqueueRequest:request arguments:arguments completion:finish];
    return request;
}

- (void)storeEntry:(MacLCYouTubeCacheEntry *)entry forKey:(NSString *)cacheKey
{
    [_memoryCache setObject:entry forKey:cacheKey];
    NSString * const path = [self cachePath:cacheKey];
    NSData * const data = entry.data;
    dispatch_async(_ioQueue, ^{
        NSFileManager * const fm = [NSFileManager defaultManager];
        [fm createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:NULL];
        [data writeToFile:path atomically:YES];
    });
}

- (void)enqueueRequest:(MacLCYouTubeRequest *)request arguments:(NSArray<NSString *> *)arguments completion:(MacLCYouTubeDataCompletion)completion
{
    NSValue * const key = [NSValue valueWithNonretainedObject:request];
    _jobs[key] = @{@"arguments": arguments, @"completion": [completion copy]};
    [_pending addObject:request];
    __weak MacLCYouTubeService *weakSelf = self;
    request.cancelHandler = ^(MacLCYouTubeRequest *r) {
        MacLCYouTubeService * const strongSelf = weakSelf;
        if (strongSelf != nil && [strongSelf->_pending containsObject:r]) {
            [strongSelf->_pending removeObject:r];
            [strongSelf->_jobs removeObjectForKey:[NSValue valueWithNonretainedObject:r]];
        }
    };
    [self pump];
}

/* Main thread. Newest first: what the person is looking at now. */
- (void)pump
{
    while (_running < kMaxRunning && _pending.count > 0) {
        MacLCYouTubeRequest * const request = _pending.lastObject;
        [_pending removeLastObject];
        NSValue * const key = [NSValue valueWithNonretainedObject:request];
        NSDictionary * const job = _jobs[key];
        [_jobs removeObjectForKey:key];
        if (job == nil || request.cancelled) {
            continue;
        }
        _running++;
        [self launchRequest:request arguments:job[@"arguments"] completion:job[@"completion"]];
    }
}

- (void)launchRequest:(MacLCYouTubeRequest *)request arguments:(NSArray<NSString *> *)arguments completion:(MacLCYouTubeDataCompletion)completion
{
    NSString * const extractor = MacLCWebVideoResolver.sharedResolver.extractorPath;
    NSTask * const task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:extractor ?: @"/usr/bin/false"];
    task.arguments = arguments;
    NSPipe * const out = [NSPipe pipe];
    NSPipe * const err = [NSPipe pipe];
    task.standardOutput = out;
    task.standardError = err;
    request.task = task;

    __weak MacLCYouTubeService *weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSMutableData * const outData = [NSMutableData data];
        NSMutableData * const errData = [NSMutableData data];
        NSLock * const lock = [[NSLock alloc] init];
        dispatch_semaphore_t outDone = dispatch_semaphore_create(0);
        dispatch_semaphore_t errDone = dispatch_semaphore_create(0);
        dispatch_semaphore_t exited = dispatch_semaphore_create(0);
        void (^reader)(NSFileHandle *, NSMutableData *, dispatch_semaphore_t) = ^(NSFileHandle *handle, NSMutableData *sink, dispatch_semaphore_t eof) {
            handle.readabilityHandler = ^(NSFileHandle *h) {
                NSData * const chunk = h.availableData;
                if (chunk.length == 0) {
                    h.readabilityHandler = nil;
                    dispatch_semaphore_signal(eof);
                    return;
                }
                [lock lock];
                [sink appendData:chunk];
                [lock unlock];
            };
        };
        reader(out.fileHandleForReading, outData, outDone);
        reader(err.fileHandleForReading, errData, errDone);
        task.terminationHandler = ^(NSTask *t) {
            dispatch_semaphore_signal(exited);
        };

        NSError *launchError = nil;
        BOOL launched = !request.cancelled && [task launchAndReturnError:&launchError];
        if (launched) {
            if (dispatch_semaphore_wait(exited, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kTaskTimeout * NSEC_PER_SEC))) != 0) {
                if (task.isRunning) {
                    [task terminate];
                }
                dispatch_semaphore_wait(exited, DISPATCH_TIME_FOREVER);
            }
            /* The pipes deliver what is left after the process is gone. */
            const dispatch_time_t drain = dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC);
            dispatch_semaphore_wait(outDone, drain);
            dispatch_semaphore_wait(errDone, drain);
        }
        out.fileHandleForReading.readabilityHandler = nil;
        err.fileHandleForReading.readabilityHandler = nil;

        [lock lock];
        NSData * const outCopy = [outData copy];
        NSData * const errCopy = [errData copy];
        [lock unlock];
        const int status = launched ? task.terminationStatus : -1;

        dispatch_async(dispatch_get_main_queue(), ^{
            MacLCYouTubeService * const strongSelf = weakSelf;
            request.task = nil;
            if (strongSelf != nil) {
                strongSelf->_running--;
                [strongSelf pump];
            }
            if (request.cancelled) {
                return;
            }
            if (!launched) {
                completion(nil, ServiceError(MacLCYouTubeErrorExtractorFailed, launchError.localizedDescription ?: @"yt-dlp could not start."));
            } else if (status == 0 && outCopy.length > 0) {
                completion(outCopy, nil);
            } else {
                NSString * const text = [[NSString alloc] initWithData:errCopy encoding:NSUTF8StringEncoding] ?: @"";
                NSString *message = nil;
                const NSInteger code = MacLCYouTubeClassifyExtractorError(text, &message);
                completion(nil, ServiceError((MacLCYouTubeError)code, message ?: @"yt-dlp failed."));
            }
        });
    });
}

/* Fetch + parse (off the main thread) + complete on the main queue. */
- (MacLCYouTubeRequest *)pageForTarget:(NSString *)target
                                  flat:(BOOL)flat
                                 limit:(NSUInteger)limit
                            fixtureKey:(NSString *)fixtureKey
                                   ttl:(NSTimeInterval)ttl
                         needsAccount:(BOOL)needsAccount
                          emptyMeansSignIn:(BOOL)emptyMeansSignIn
                            completion:(MacLCYouTubePageCompletion)completion
{
    return [self fetchTarget:target flat:flat limit:limit fixtureKey:fixtureKey ttl:ttl needsAccount:needsAccount
                  completion:^(NSData *data, NSError *error) {
        if (data == nil) {
            completion(nil, error);
            return;
        }
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSError *parseError = nil;
            MacLCYouTubePage * const page = [MacLCYouTubeParser pageFromJSONData:data limit:limit error:&parseError];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (page == nil) {
                    completion(nil, ServiceError(MacLCYouTubeErrorBadResponse, parseError.localizedDescription ?: @"Unexpected answer."));
                } else if (emptyMeansSignIn && page.results.count == 0 && MacLCYouTubeAccount.sharedAccount.signedIn) {
                    /* A real account always has recommendations: an empty list
                     * means YouTube refused the cookies. */
                    completion(nil, ServiceError(MacLCYouTubeErrorSignInRequired, @"Sign in again to see your recommendations."));
                } else {
                    completion(page, nil);
                }
            });
        });
    }];
}

#pragma mark Public: lists

- (MacLCYouTubeRequest *)homeForCategory:(MacLCYouTubeCategory *)category
                                   limit:(NSUInteger)limit
                              completion:(MacLCYouTubePageCompletion)completion
{
    NSString * const identifier = category.identifier ?: @"all";
    const BOOL all = [identifier isEqualToString:@"all"];
    if (all && MacLCYouTubeAccount.sharedAccount.signedIn) {
        return [self feed:MacLCYouTubeFeedRecommended limit:limit completion:completion];
    }

    NSDictionary<NSString *, NSString *> * const queries = HomeQueries([MacLCYouTubeService languageCode]);
    NSString * const fixtureKey = [@"home-" stringByAppendingString:identifier];
    if (!all) {
        NSString * const query = queries[identifier];
        if (query == nil) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil, ServiceError(MacLCYouTubeErrorBadResponse, @"Unknown topic."));
            });
            return [[MacLCYouTubeRequest alloc] init];
        }
        NSString * const sp = [identifier isEqualToString:@"live"] ? kSortLiveViews : kSortWeekViews;
        return [self pageForTarget:SearchURLString(query, MacLCYouTubeSearchFilterAll, sp) flat:YES limit:limit
                        fixtureKey:fixtureKey ttl:kTTLFeed needsAccount:NO emptyMeansSignIn:NO completion:completion];
    }

    /* All, signed out: four searches together, interleaved. */
    if (NSProcessInfo.processInfo.environment[@"MACLC_DEBUG_YOUTUBE_FIXTURES"].length > 0) {
        return [self pageForTarget:@"" flat:YES limit:limit fixtureKey:fixtureKey ttl:kTTLFeed needsAccount:NO
                  emptyMeansSignIn:NO completion:completion];
    }
    MacLCYouTubeRequest * const parent = [[MacLCYouTubeRequest alloc] init];
    NSMutableArray<MacLCYouTubeRequest *> * const children = [NSMutableArray array];
    NSMutableArray * const pages = [NSMutableArray array];
    NSMutableArray<NSError *> * const errors = [NSMutableArray array];
    const NSUInteger each = MAX((NSUInteger)12, (limit + 3) / 4);
    NSArray<NSString *> * const topics = HomeMixTopics();
    __block NSUInteger remaining = topics.count;
    for (NSUInteger i = 0; i < topics.count; i++) {
        [pages addObject:[NSNull null]];
        NSString * const query = queries[topics[i]];
        MacLCYouTubeRequest * const child = [self pageForTarget:SearchURLString(query, MacLCYouTubeSearchFilterAll, kSortWeekViews)
                                                           flat:YES limit:each fixtureKey:fixtureKey ttl:kTTLFeed
                                                   needsAccount:NO emptyMeansSignIn:NO
                                                     completion:^(MacLCYouTubePage *page, NSError *error) {
            if (page != nil) {
                pages[i] = page;
            } else if (error != nil) {
                [errors addObject:error];
            }
            if (--remaining > 0 || parent.cancelled) {
                return;
            }
            NSMutableArray<MacLCYouTubePage *> * const got = [NSMutableArray array];
            for (id p in pages) {
                if ([p isKindOfClass:[MacLCYouTubePage class]]) {
                    [got addObject:p];
                }
            }
            parent.finished = YES;
            if (got.count == 0) {
                completion(nil, errors.firstObject ?: ServiceError(MacLCYouTubeErrorBadResponse, @"Nothing to show."));
            } else {
                completion(MacLCYouTubeMergedPage(@"Home", got, limit), nil);
            }
        }];
        [children addObject:child];
    }
    parent.children = children;
    return parent;
}

- (MacLCYouTubeRequest *)feed:(MacLCYouTubeFeed)feed limit:(NSUInteger)limit completion:(MacLCYouTubePageCompletion)completion
{
    NSString *target = nil, *name = nil;
    switch (feed) {
        case MacLCYouTubeFeedRecommended: target = @":ytrec"; name = @"recommended"; break;
        case MacLCYouTubeFeedSubscriptions: target = @":ytsubs"; name = @"subscriptions"; break;
        case MacLCYouTubeFeedHistory: target = @":ythis"; name = @"history"; break;
        case MacLCYouTubeFeedWatchLater: target = @":ytwatchlater"; name = @"watchlater"; break;
        case MacLCYouTubeFeedLiked: target = @"https://www.youtube.com/playlist?list=LL"; name = @"liked"; break;
        case MacLCYouTubeFeedPlaylists: target = @"https://www.youtube.com/feed/playlists"; name = @"playlists"; break;
    }
    return [self pageForTarget:target flat:YES limit:limit fixtureKey:[@"feed-" stringByAppendingString:name] ttl:kTTLFeed
                  needsAccount:YES emptyMeansSignIn:feed == MacLCYouTubeFeedRecommended completion:completion];
}

- (MacLCYouTubeRequest *)search:(NSString *)query
                         filter:(MacLCYouTubeSearchFilter)filter
                          limit:(NSUInteger)limit
                     completion:(MacLCYouTubePageCompletion)completion
{
    NSString * const trimmed = [query stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString * const key = [NSString stringWithFormat:@"search-%@-%@", FilterName(filter), FixtureSafe(trimmed)];
    return [self pageForTarget:SearchURLString(trimmed, filter, nil) flat:YES limit:limit fixtureKey:key ttl:kTTLFeed
                  needsAccount:NO emptyMeansSignIn:NO completion:completion];
}

- (MacLCYouTubeRequest *)channel:(NSURL *)channelURL
                             tab:(MacLCYouTubeChannelTab)tab
                           limit:(NSUInteger)limit
                      completion:(MacLCYouTubePageCompletion)completion
{
    NSString * const key = [NSString stringWithFormat:@"channel-%@-%@", ChannelKeyPart(channelURL), TabName(tab)];
    return [self pageForTarget:ChannelTabURLString(channelURL, tab) flat:YES limit:limit fixtureKey:key ttl:kTTLCollection
                  needsAccount:NO emptyMeansSignIn:NO completion:completion];
}

- (MacLCYouTubeRequest *)playlist:(NSURL *)playlistURL limit:(NSUInteger)limit completion:(MacLCYouTubePageCompletion)completion
{
    NSString * const identifier = PlaylistIdentifierFromURL(playlistURL);
    NSString * const target = identifier != nil
        ? [@"https://www.youtube.com/playlist?list=" stringByAppendingString:identifier]
        : playlistURL.absoluteString;
    return [self pageForTarget:target flat:YES limit:limit fixtureKey:[@"playlist-" stringByAppendingString:identifier ?: @"unknown"]
                           ttl:kTTLCollection needsAccount:NO emptyMeansSignIn:NO completion:completion];
}

- (MacLCYouTubeRequest *)detailsForVideo:(MacLCYouTubeVideo *)video
                              completion:(void (^)(MacLCYouTubeVideo * _Nullable, NSError * _Nullable))completion
{
    return [self fetchTarget:video.watchURL.absoluteString flat:NO limit:0
                  fixtureKey:[@"video-" stringByAppendingString:video.identifier] ttl:kTTLDetails needsAccount:NO
                  completion:^(NSData *data, NSError *error) {
        if (data == nil) {
            completion(nil, error);
            return;
        }
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSError *parseError = nil;
            MacLCYouTubeVideo * const details = [MacLCYouTubeParser videoFromJSONData:data error:&parseError];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (details == nil) {
                    completion(nil, ServiceError(MacLCYouTubeErrorBadResponse, parseError.localizedDescription ?: @"Unexpected answer."));
                } else {
                    completion(details, nil);
                }
            });
        });
    }];
}

#pragma mark Public: playback

- (VLCOpenInputMetadata *)enqueueItemForVideo:(MacLCYouTubeVideo *)video
{
    /* An MRL, not a path: -initWithPath: would turn the address into file://. */
    VLCOpenInputMetadata * const meta = [[VLCOpenInputMetadata alloc] init];
    meta.MRLString = video.watchURL.absoluteString;
    meta.itemName = video.title;
    return meta;
}

/* The "start-time" input option clips the media timeline (length becomes
 * total - start, times start at 0): seek instead, once the item is the
 * player's current media (20 s at most). Main thread. */
- (void)seekWhenCurrent:(NSString *)MRL toTime:(NSTimeInterval)seconds
{
    VLCPlayerController * const player = VLCMain.sharedInstance.playQueueController.playerController;
    if (player == nil || MRL.length == 0) {
        return;
    }
    NSString * const decoded = MRL.stringByRemovingPercentEncoding ?: MRL;
    __block id token = nil;
    __block BOOL done = NO;
    __weak VLCPlayerController *weakPlayer = player;
    void (^finish)(BOOL) = ^(BOOL seek) {
        if (done) {
            return;
        }
        done = YES;
        if (token != nil) {
            [[NSNotificationCenter defaultCenter] removeObserver:token];
            token = nil;
        }
        VLCPlayerController * const p = weakPlayer;
        if (seek && p != nil) {
            [p setTimePrecise:(vlc_tick_t)(seconds * CLOCK_FREQ)];
        }
    };
    token = [[NSNotificationCenter defaultCenter] addObserverForName:VLCPlayerCurrentMediaItemChanged
                                                              object:player
                                                               queue:NSOperationQueue.mainQueue
                                                          usingBlock:^(NSNotification *note) {
        VLCInputItem * const current = weakPlayer.currentMedia;
        if (current == nil) {
            return;
        }
        NSString * const mrl = current.MRL;
        if ([mrl isEqualToString:MRL] || [mrl isEqualToString:decoded] || [current.decodedMRL isEqualToString:decoded]) {
            finish(YES);
        }
    }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(20 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        finish(NO);
    });
}

/* Resolves one video with the account's cookies and hands it to the queue to
 * play now (startTime > 0: from there). completion: main queue. */
- (void)resolveAndPlay:(MacLCYouTubeVideo *)video
             startTime:(NSTimeInterval)startTime
            completion:(void (^)(NSError * _Nullable error))completion
{
    MacLCWebVideoResolver * const resolver = MacLCWebVideoResolver.sharedResolver;
    NSArray<NSString *> * const cookies = MacLCYouTubeAccount.sharedAccount.extractorArguments;
    resolver.extraArguments = cookies;
    [resolver resolveAddress:video.watchURL.absoluteString completion:^(MacLCWebVideoItem *item, NSError *error) {
        /* Only ours: Open Web Video does not carry the account around. */
        if ([resolver.extraArguments isEqualToArray:cookies]) {
            resolver.extraArguments = @[];
        }
        VLCOpenInputMetadata * const meta = item.playQueueItem;
        if (meta == nil) {
            completion(error ?: ServiceError(MacLCYouTubeErrorExtractorFailed, @"This video can't be played."));
            return;
        }
        [VLCMain.sharedInstance.playQueueController addPlayQueueItems:@[meta] atPosition:(size_t)-1 startPlayback:YES];
        if (startTime >= 1) {
            [self seekWhenCurrent:meta.MRLString toTime:startTime];
        }
        completion(nil);
    }];
}

- (void)playVideo:(MacLCYouTubeVideo *)video enqueue:(BOOL)enqueue completion:(void (^)(NSError * _Nullable))completion
{
    if (enqueue) {
        [VLCMain.sharedInstance.playQueueController addPlayQueueItems:@[[self enqueueItemForVideo:video]]];
        if (completion) completion(nil);
        return;
    }
    [self resolveAndPlay:video startTime:0 completion:^(NSError *error) {
        if (completion) completion(error);
    }];
}

- (void)playVideo:(MacLCYouTubeVideo *)video startTime:(NSTimeInterval)startTime completion:(void (^)(NSError * _Nullable))completion
{
    [self resolveAndPlay:video startTime:startTime completion:^(NSError *error) {
        if (completion) completion(error);
    }];
}

- (void)playVideos:(NSArray<MacLCYouTubeVideo *> *)videos startingAtIndex:(NSUInteger)index completion:(void (^)(NSError * _Nullable))completion
{
    if (index >= videos.count) {
        if (completion) completion(ServiceError(MacLCYouTubeErrorBadResponse, @"Nothing to play."));
        return;
    }
    /* The ones before index are skipped, as on YouTube. They are queued after
     * the first one has been, so the order in the queue is the order shown. */
    NSArray<MacLCYouTubeVideo *> * const rest = [videos subarrayWithRange:NSMakeRange(index + 1, videos.count - index - 1)];
    [self resolveAndPlay:videos[index] startTime:0 completion:^(NSError *error) {
        if (error == nil && rest.count > 0) {
            NSMutableArray<VLCOpenInputMetadata *> * const items = [NSMutableArray array];
            for (MacLCYouTubeVideo *v in rest) {
                [items addObject:[self enqueueItemForVideo:v]];
            }
            [VLCMain.sharedInstance.playQueueController addPlayQueueItems:items];
        }
        if (completion) completion(error);
    }];
}

@end
