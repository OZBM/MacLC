/*****************************************************************************
 * MacLCWebVideoResolver.m: resolve a web page address into playable media
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

#import "MacLCWebVideoResolver.h"
#import "windows/VLCOpenInputMetadata.h"

NSErrorDomain const MacLCWebVideoErrorDomain = @"MacLCWebVideoErrorDomain";

@interface MacLCWebVideoItem ()
@property (readwrite, copy) NSString *pageAddress;
@property (readwrite, copy, nullable) NSString *title;
@property (readwrite, copy, nullable) NSString *author;
@property (readwrite, copy, nullable) NSString *siteName;
@property (readwrite) NSTimeInterval duration;
@property (readwrite, copy, nullable) NSString *thumbnailAddress;
@property (readwrite, copy, nullable) NSString *formatDescription;
@property (readwrite, getter=isLive) BOOL live;
@property (readwrite, getter=isTorrent) BOOL torrent;
@property (readwrite, copy) NSArray<MacLCWebVideoItem *> *children;
@property (readwrite, strong, nullable) VLCOpenInputMetadata *playQueueItem;
@end

@implementation MacLCWebVideoItem
- (instancetype)init {
    self = [super init];
    if (self) {
        _children = @[];
    }
    return self;
}
@end

@interface MacLCWebVideoResolver ()
@property (readwrite, copy, nullable) NSString *extractorPath;
@property (nonatomic, strong) NSLock *tasksLock;
@property (nonatomic, strong) NSMutableDictionary<NSUUID *, NSTask *> *activeTasks;
@property (nonatomic, strong) dispatch_queue_t resolveQueue;
@end

@implementation MacLCWebVideoResolver

+ (instancetype)sharedResolver {
    static MacLCWebVideoResolver *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[MacLCWebVideoResolver alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _tasksLock = [[NSLock alloc] init];
        _activeTasks = [NSMutableDictionary dictionary];
        _resolveQueue = dispatch_queue_create("com.hazenstudio.maclc.webvideoresolver", DISPATCH_QUEUE_SERIAL);
        [self refreshExtractorPath];
    }
    return self;
}

+ (BOOL)looksLikeWebVideoAddress:(NSString *)string {
    NSString *trimmed = [string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) return NO;
    if ([trimmed rangeOfString:@" "].location != NSNotFound) return NO;

    NSURL *url = [NSURL URLWithString:trimmed];
    if (url && url.scheme) {
        NSString *scheme = url.scheme.lowercaseString;
        if ([scheme isEqualToString:@"magnet"]) return YES;
        if (![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"]) return NO;
        if (url.host && [url.host rangeOfString:@"."].location != NSNotFound) return YES;
        return NO;
    }

    if ([trimmed hasPrefix:@"file:"] || [trimmed hasPrefix:@"javascript:"]) return NO;
    if ([trimmed rangeOfString:@"://"].location != NSNotFound) return NO;

    NSRange slashRange = [trimmed rangeOfString:@"/"];
    NSRange dotRange = [trimmed rangeOfString:@"."];
    if (dotRange.location != NSNotFound) {
        if (slashRange.location == NSNotFound || dotRange.location < slashRange.location) {
            return YES;
        }
    }
    return NO;
}

+ (nullable NSString *)normalisedAddressFromString:(NSString *)string {
    NSString *trimmed = [string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length >= 2) {
        if ([trimmed hasPrefix:@"\""] && [trimmed hasSuffix:@"\""]) {
            trimmed = [trimmed substringWithRange:NSMakeRange(1, trimmed.length - 2)];
        } else if ([trimmed hasPrefix:@"<"] && [trimmed hasSuffix:@">"]) {
            trimmed = [trimmed substringWithRange:NSMakeRange(1, trimmed.length - 2)];
        }
    }
    if (![self looksLikeWebVideoAddress:trimmed]) return nil;

    NSURL *url = [NSURL URLWithString:trimmed];
    if (!url || !url.scheme) {
        trimmed = [@"https://" stringByAppendingString:trimmed];
    }
    return trimmed;
}

- (void)refreshExtractorPath {
    NSArray *binaries = @[@"yt-dlp", @"youtube-dl"];
    NSMutableArray *pathsToTry = [NSMutableArray array];

    NSString *userPath = [[NSUserDefaults standardUserDefaults] stringForKey:@"MacLCWebVideoExtractorPath"];
    if (userPath && userPath.length > 0) {
        [pathsToTry addObject:userPath];
    }

    NSArray *bases = @[
        @"/opt/homebrew/bin/",
        @"/usr/local/bin/",
        @"/opt/local/bin/",
        [[NSString stringWithFormat:@"%@/.local/bin/", NSHomeDirectory()] stringByStandardizingPath],
        @"/usr/bin/"
    ];

    for (NSString *binary in binaries) {
        for (NSString *base in bases) {
            [pathsToTry addObject:[base stringByAppendingString:binary]];
        }
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *foundPath = nil;
    for (NSString *path in pathsToTry) {
        if ([fm isExecutableFileAtPath:path]) {
            foundPath = path;
            break;
        }
    }
    self.extractorPath = foundPath;
}

- (void)cancelResolution:(NSUUID *)token {
    [self.tasksLock lock];
    NSTask *task = self.activeTasks[token];
    [self.tasksLock unlock];
    /* -terminate on a task that is not running raises. */
    if (task.isRunning) {
        [task terminate];
    }
}

- (void)_reportError:(NSError *)error item:(MacLCWebVideoItem *)item completion:(void (^)(MacLCWebVideoItem *_Nullable, NSError *_Nullable))completion {
    dispatch_async(dispatch_get_main_queue(), ^{
        completion(item, error);
    });
}

- (nullable NSUUID *)resolveAddress:(NSString *)address
                         completion:(void (^)(MacLCWebVideoItem *_Nullable item,
                                              NSError *_Nullable error))completion {
    NSString *normalised = [MacLCWebVideoResolver normalisedAddressFromString:address];
    if (!normalised) {
        NSError *err = [NSError errorWithDomain:MacLCWebVideoErrorDomain code:MacLCWebVideoErrorInvalidAddress userInfo:@{NSLocalizedDescriptionKey: @"The address is invalid."}];
        [self _reportError:err item:nil completion:completion];
        return nil;
    }

    if ([normalised.lowercaseString hasPrefix:@"magnet:"] || [normalised.lowercaseString hasSuffix:@".torrent"]) {
        MacLCWebVideoItem *item = [[MacLCWebVideoItem alloc] init];
        item.pageAddress = normalised;
        NSString *title = nil;
        if ([normalised.lowercaseString hasPrefix:@"magnet:"]) {
            NSURLComponents *components = [NSURLComponents componentsWithString:normalised];
            for (NSURLQueryItem *qi in components.queryItems) {
                if ([qi.name isEqualToString:@"dn"]) {
                    /* Form encoding: '+' stands for a space in dn. */
                    title = [qi.value stringByReplacingOccurrencesOfString:@"+" withString:@" "];
                    /* Some indexers put line breaks in it (Torrentio). */
                    title = [[title componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]
                             componentsJoinedByString:@" "];
                    break;
                }
            }
        } else {
            NSURL *url = [NSURL URLWithString:normalised];
            title = url.lastPathComponent;
        }
        item.title = title.length > 0 ? title : @"BitTorrent";
        item.siteName = @"BitTorrent";
        item.torrent = YES;
        VLCOpenInputMetadata *meta = [[VLCOpenInputMetadata alloc] init];
        meta.MRLString = normalised;
        meta.itemName = item.title;
        item.playQueueItem = meta;
        
        [self _reportError:nil item:item completion:completion];
        return nil;
    }

    NSString *extractor = self.extractorPath;
    if (!extractor) {
        NSError *err = [NSError errorWithDomain:MacLCWebVideoErrorDomain code:MacLCWebVideoErrorExtractorMissing userInfo:@{NSLocalizedDescriptionKey: @"The extractor is missing."}];
        [self _reportError:err item:nil completion:completion];
        return nil;
    }

    NSUUID *token = [NSUUID UUID];
    dispatch_async(self.resolveQueue, ^{
        [self _runExtractorWithToken:token address:normalised extractor:extractor completion:completion];
    });
    return token;
}

- (MacLCWebVideoErrorCode)_codeForStdErr:(NSString *)errString {
    NSString * const lower = errString.lowercaseString;
    
    if ([lower containsString:@"is not a valid url"] || [lower containsString:@"rejected"]) {
        return MacLCWebVideoErrorInvalidAddress;
    }
    if (([lower containsString:@"unable to download"] && [lower containsString:@"getaddrinfo"])
        || [lower containsString:@"temporary failure in name resolution"]
        || [lower containsString:@"network is unreachable"]
        || [lower containsString:@"failed to resolve"]) {
        return MacLCWebVideoErrorNoNetwork;
    }
    /* "a page" contains "age": the age gate has to be matched on its own
     * wording, not on three letters. */
    if ([lower containsString:@"private video"] || [lower containsString:@"sign in"]
        || [lower containsString:@"members-only"] || [lower containsString:@"members only"]
        || [lower containsString:@"not available in your country"]
        || [lower containsString:@"age-restricted"] || [lower containsString:@"age restricted"]
        || [lower containsString:@"confirm your age"]
        || [lower containsString:@"requested format is not available"]) {
        return MacLCWebVideoErrorUnavailable;
    }
    if ([lower containsString:@"unsupported url"] || [lower containsString:@"no video"]
        || [lower containsString:@"there is no video"]) {
        return MacLCWebVideoErrorNotAVideo;
    }
    if ([lower containsString:@"update"] && [lower containsString:@"yt-dlp"]) {
        return MacLCWebVideoErrorExtractorOutdated;
    }
    return MacLCWebVideoErrorExtractorFailed;
}

- (void)_runExtractorWithToken:(NSUUID *)token address:(NSString *)address extractor:(NSString *)extractor completion:(void (^)(MacLCWebVideoItem *_Nullable item, NSError *_Nullable error))completion {
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:extractor];
    task.arguments = @[@"--ignore-config", @"--no-warnings", @"--no-progress", @"--socket-timeout", @"15", @"-J", @"--", address];

    NSPipe *outPipe = [NSPipe pipe];
    NSPipe *errPipe = [NSPipe pipe];
    task.standardOutput = outPipe;
    task.standardError = errPipe;

    NSMutableData *outData = [NSMutableData data];
    NSMutableData *errData = [NSMutableData data];
    NSLock *dataLock = [[NSLock alloc] init];

    /* The extractor's answer is often a megabyte of JSON, and the pipe keeps
     * delivering it after the process has gone. Each side signals when it has
     * read its end of file, and nothing is parsed before both have. */
    dispatch_semaphore_t outDone = dispatch_semaphore_create(0);
    dispatch_semaphore_t errDone = dispatch_semaphore_create(0);

    outPipe.fileHandleForReading.readabilityHandler = ^(NSFileHandle *handle) {
        NSData * const d = handle.availableData;
        if (d.length == 0) {
            handle.readabilityHandler = nil;
            dispatch_semaphore_signal(outDone);
            return;
        }
        [dataLock lock];
        [outData appendData:d];
        [dataLock unlock];
    };
    errPipe.fileHandleForReading.readabilityHandler = ^(NSFileHandle *handle) {
        NSData * const d = handle.availableData;
        if (d.length == 0) {
            handle.readabilityHandler = nil;
            dispatch_semaphore_signal(errDone);
            return;
        }
        [dataLock lock];
        [errData appendData:d];
        [dataLock unlock];
    };

    [self.tasksLock lock];
    self.activeTasks[token] = task;
    [self.tasksLock unlock];

    __block BOOL cancelled = NO;
    __block BOOL timedOut = NO;
    
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    task.terminationHandler = ^(NSTask *t) {
        if (t.terminationReason == NSTaskTerminationReasonUncaughtSignal) {
            cancelled = YES; // assumed from terminate
        }
        dispatch_semaphore_signal(sem);
    };

    NSError *launchError = nil;
    if (![task launchAndReturnError:&launchError]) {
        outPipe.fileHandleForReading.readabilityHandler = nil;
        errPipe.fileHandleForReading.readabilityHandler = nil;
        [self.tasksLock lock];
        [self.activeTasks removeObjectForKey:token];
        [self.tasksLock unlock];
        NSError *err = [NSError errorWithDomain:MacLCWebVideoErrorDomain code:MacLCWebVideoErrorExtractorFailed userInfo:@{NSLocalizedDescriptionKey: @"Failed to launch extractor.", NSLocalizedFailureReasonErrorKey: launchError.localizedDescription ?: @""}];
        [self _reportError:err item:nil completion:completion];
        return;
    }

    if (dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 45 * NSEC_PER_SEC)) != 0) {
        timedOut = YES;
        if (task.isRunning) {
            [task terminate];
        }
        dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
    }

    /* The process is gone; give both pipes a moment to hand over what is left,
     * then stop reading whatever happens. */
    const dispatch_time_t drainDeadline =
        dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC);
    dispatch_semaphore_wait(outDone, drainDeadline);
    dispatch_semaphore_wait(errDone, drainDeadline);
    outPipe.fileHandleForReading.readabilityHandler = nil;
    errPipe.fileHandleForReading.readabilityHandler = nil;

    [self.tasksLock lock];
    [self.activeTasks removeObjectForKey:token];
    [self.tasksLock unlock];

    [dataLock lock];
    NSData *finalOut = [outData copy];
    NSData *finalErr = [errData copy];
    [dataLock unlock];

    if (cancelled && !timedOut) {
        NSError *err = [NSError errorWithDomain:MacLCWebVideoErrorDomain code:MacLCWebVideoErrorCancelled userInfo:@{NSLocalizedDescriptionKey: @"The resolution was cancelled."}];
        [self _reportError:err item:nil completion:completion];
        return;
    }
    
    NSString *errString = [[NSString alloc] initWithData:finalErr encoding:NSUTF8StringEncoding];
    NSArray *errLines = [errString componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    NSString *lastErrLine = @"";
    for (NSString *line in errLines.reverseObjectEnumerator) {
        NSString *t = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (t.length > 0) {
            lastErrLine = t;
            break;
        }
    }

    if (timedOut) {
        NSError *err = [NSError errorWithDomain:MacLCWebVideoErrorDomain code:MacLCWebVideoErrorExtractorFailed userInfo:@{NSLocalizedDescriptionKey: @"The extractor failed.", NSLocalizedFailureReasonErrorKey: @"The extractor took too long."}];
        [self _reportError:err item:nil completion:completion];
        return;
    }

    NSError *jsonError = nil;
    NSDictionary *json = nil;
    if (finalOut.length > 0) {
        json = [NSJSONSerialization JSONObjectWithData:finalOut options:0 error:&jsonError];
    }

    if (!json || ![json isKindOfClass:[NSDictionary class]] || task.terminationStatus != 0) {
        MacLCWebVideoErrorCode code = [self _codeForStdErr:errString];
        NSError *err = [NSError errorWithDomain:MacLCWebVideoErrorDomain code:code userInfo:@{NSLocalizedDescriptionKey: @"The extractor failed.", NSLocalizedFailureReasonErrorKey: lastErrLine}];
        [self _reportError:err item:nil completion:completion];
        return;
    }
    
    NSString *type = json[@"_type"];
    if ([type isEqualToString:@"playlist"]) {
        [self _processPlaylist:json token:token extractor:extractor completion:completion];
    } else {
        [self _processSingleVideo:json completion:completion];
    }
}

- (BOOL)_isValidAddressForOptions:(NSString *)addr {
    if (!addr) return NO;
    if ([addr rangeOfCharacterFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].location != NSNotFound) return NO;
    if ([addr rangeOfString:@"\0"].location != NSNotFound) return NO;
    /* '#' opens a stream output chain in an MRL: an address carrying one
     * could append instructions of its own to the option it lands in. */
    if ([addr rangeOfString:@"#"].location != NSNotFound) return NO;
    NSURL *u = [NSURL URLWithString:addr];
    if (!u || !u.scheme) return NO;
    NSString *s = u.scheme.lowercaseString;
    return [s isEqualToString:@"http"] || [s isEqualToString:@"https"];
}

- (void)_processPlaylist:(NSDictionary *)json token:(NSUUID *)token extractor:(NSString *)extractor completion:(void (^)(MacLCWebVideoItem *_Nullable item, NSError *_Nullable error))completion {
    MacLCWebVideoItem *node = [[MacLCWebVideoItem alloc] init];
    node.title = json[@"title"];
    node.pageAddress = json[@"webpage_url"];
    
    NSArray *entries = json[@"entries"];
    if (![entries isKindOfClass:[NSArray class]]) entries = @[];
    
    NSMutableArray *children = [NSMutableArray array];
    NSUInteger max = MIN(entries.count, 200);
    
    NSDictionary *firstFull = nil;
    for (NSUInteger i = 0; i < max; i++) {
        NSDictionary *e = entries[i];
        if (![e isKindOfClass:[NSDictionary class]]) continue;
        if (i == 0) {
            if (e[@"formats"]) {
                firstFull = e;
            } else {
                NSString *firstUrl = e[@"url"];
                if (!firstUrl) firstUrl = e[@"webpage_url"];
                if (firstUrl) {
                    NSTask *task = [[NSTask alloc] init];
                    task.executableURL = [NSURL fileURLWithPath:extractor];
                    task.arguments = @[@"--ignore-config", @"--no-warnings", @"--no-progress", @"--socket-timeout", @"15", @"-J", @"--", firstUrl];
                    
                    [self.tasksLock lock];
                    self.activeTasks[token] = task;
                    [self.tasksLock unlock];
                    
                    NSPipe *outPipe = [NSPipe pipe];
                    task.standardOutput = outPipe;
                    NSMutableData *outData = [NSMutableData data];
                    NSLock *dataLock = [[NSLock alloc] init];
                    outPipe.fileHandleForReading.readabilityHandler = ^(NSFileHandle *handle) {
                        NSData *d = handle.availableData;
                        if (d.length > 0) {
                            [dataLock lock];
                            [outData appendData:d];
                            [dataLock unlock];
                        }
                    };
                    
                    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
                    __block BOOL cancelled = NO;
                    task.terminationHandler = ^(NSTask *t) {
                        outPipe.fileHandleForReading.readabilityHandler = nil;
                        if (t.terminationReason == NSTaskTerminationReasonUncaughtSignal) cancelled = YES;
                        dispatch_semaphore_signal(sem);
                    };
                    
                    if ([task launchAndReturnError:nil]) {
                        dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 45 * NSEC_PER_SEC));
                    }
                    
                    [self.tasksLock lock];
                    [self.activeTasks removeObjectForKey:token];
                    [self.tasksLock unlock];
                    
                    [dataLock lock];
                    NSData *finalOut = [outData copy];
                    [dataLock unlock];
                    
                    if (!cancelled && finalOut.length > 0) {
                        NSDictionary *fj = [NSJSONSerialization JSONObjectWithData:finalOut options:0 error:nil];
                        if ([fj isKindOfClass:[NSDictionary class]]) {
                            firstFull = fj;
                        }
                    }
                }
            }
        }
        
        MacLCWebVideoItem *child = [[MacLCWebVideoItem alloc] init];
        child.title = e[@"title"];
        NSString *url = e[@"url"] ?: e[@"webpage_url"];
        child.pageAddress = url;
        
        if (i == 0 && firstFull) {
            [self _populateItem:child withJSON:firstFull];
        } else {
            if (url) {
                VLCOpenInputMetadata *meta = [[VLCOpenInputMetadata alloc] initWithPath:url];
                child.playQueueItem = meta;
            }
        }
        [children addObject:child];
    }
    
    node.children = children;
    [self _reportError:nil item:node completion:completion];
}

- (void)_processSingleVideo:(NSDictionary *)json completion:(void (^)(MacLCWebVideoItem *_Nullable item, NSError *_Nullable error))completion {
    MacLCWebVideoItem *item = [[MacLCWebVideoItem alloc] init];
    NSError *err = [self _populateItem:item withJSON:json];
    if (err) {
        [self _reportError:err item:nil completion:completion];
    } else {
        [self _reportError:nil item:item completion:completion];
    }
}

- (NSError *)_populateItem:(MacLCWebVideoItem *)item withJSON:(NSDictionary *)json {
    item.title = json[@"title"];
    item.author = json[@"uploader"];
    item.siteName = json[@"extractor_key"];
    item.duration = [json[@"duration"] doubleValue];
    item.pageAddress = json[@"webpage_url"];
    item.live = [json[@"is_live"] boolValue];
    
    NSArray *thumbnails = json[@"thumbnails"];
    if ([thumbnails isKindOfClass:[NSArray class]] && thumbnails.count > 0) {
        item.thumbnailAddress = thumbnails.lastObject[@"url"];
    }

    NSArray *formats = json[@"formats"];
    if (![formats isKindOfClass:[NSArray class]]) formats = @[];
    
    NSMutableArray *validFormats = [NSMutableArray array];
    for (NSDictionary *f in formats) {
        if (![f isKindOfClass:[NSDictionary class]]) continue;
        NSString *proto = f[@"protocol"];
        NSString *url = f[@"url"];
        if (!proto || !url || url.length == 0) continue;
        if (![proto hasPrefix:@"http"]) continue;
        if ([proto isEqualToString:@"mhtml"] || [proto isEqualToString:@"http_dash_segments"]) continue;
        
        NSString *acodec = f[@"acodec"];
        NSString *vcodec = f[@"vcodec"];
        BOOL hasA = acodec && ![acodec isEqualToString:@"none"];
        BOOL hasV = vcodec && ![vcodec isEqualToString:@"none"];
        if (!hasA && !hasV) continue;
        
        [validFormats addObject:f];
    }
    
    if (validFormats.count == 0) {
        NSString *url = json[@"url"];
        if (url && url.length > 0) {
            item.playQueueItem = [self _createMetaWithVideoUrl:url audioUrl:nil userAgent:nil referer:item.pageAddress title:item.title isAdaptive:NO];
            return nil;
        }
        // Check for m3u8 as fallback
        for (NSDictionary *f in formats) {
            if (![f isKindOfClass:[NSDictionary class]]) continue;
            NSString *proto = f[@"protocol"];
            NSString *url = f[@"url"];
            if (url.length > 0 && ([proto isEqualToString:@"m3u8"] || [proto isEqualToString:@"m3u8_native"])) {
                NSDictionary *headers = f[@"http_headers"];
                NSString *ua = headers[@"User-Agent"];
                item.playQueueItem = [self _createMetaWithVideoUrl:url audioUrl:nil userAgent:ua referer:item.pageAddress title:item.title isAdaptive:NO];
                return nil;
            }
        }
        
        BOOL allEmpty = formats.count > 0 && validFormats.count == 0;
        if (allEmpty) {
            return [NSError errorWithDomain:MacLCWebVideoErrorDomain code:MacLCWebVideoErrorExtractorOutdated userInfo:@{NSLocalizedDescriptionKey: @"The extractor failed.", NSLocalizedFailureReasonErrorKey: @"The extractor might be outdated."}];
        }
        return [NSError errorWithDomain:MacLCWebVideoErrorDomain code:MacLCWebVideoErrorNotAVideo userInfo:@{NSLocalizedDescriptionKey: @"The extractor failed.", NSLocalizedFailureReasonErrorKey: @"No usable formats found."}];
    }
    
    NSNumber *maxHeightNum = [[NSUserDefaults standardUserDefaults] objectForKey:@"MacLCWebVideoMaximumHeight"];
    NSInteger maxHeight = maxHeightNum ? [maxHeightNum integerValue] : 2160;
    
    NSDictionary *bestVideo = nil;
    for (NSDictionary *f in validFormats) {
        NSString *vcodec = f[@"vcodec"];
        if (!vcodec || [vcodec isEqualToString:@"none"]) continue;
        NSInteger height = [f[@"height"] integerValue];
        if (height > maxHeight) continue;
        
        if (!bestVideo) {
            bestVideo = f;
            continue;
        }
        
        NSInteger bestHeight = [bestVideo[@"height"] integerValue];
        if (height > bestHeight) {
            bestVideo = f;
        } else if (height == bestHeight) {
            /* At the same size, the codec this machine decodes in hardware
             * beats a higher bitrate the processor would have to chew on. */
            NSInteger score = [self _codecScore:f[@"vcodec"]];
            NSInteger bestScore = [self _codecScore:bestVideo[@"vcodec"]];
            if (score > bestScore) {
                bestVideo = f;
            } else if (score == bestScore) {
                double tbr = [f[@"tbr"] doubleValue];
                double bestTbr = [bestVideo[@"tbr"] doubleValue];
                if (tbr > bestTbr) {
                    bestVideo = f;
                }
            }
        }
    }
    
    NSDictionary *bestAudio = nil;
    for (NSDictionary *f in validFormats) {
        NSString *acodec = f[@"acodec"];
        NSString *vcodec = f[@"vcodec"];
        if (!acodec || [acodec isEqualToString:@"none"]) continue;
        if (vcodec && ![vcodec isEqualToString:@"none"]) continue; // must have NO video
        
        if (!bestAudio) {
            bestAudio = f;
            continue;
        }
        
        double abr1 = [f[@"abr"] doubleValue] ?: [f[@"tbr"] doubleValue];
        double abr2 = [bestAudio[@"abr"] doubleValue] ?: [bestAudio[@"tbr"] doubleValue];
        if (abr1 > abr2) {
            bestAudio = f;
        }
    }
    
    if (!bestVideo && !bestAudio) {
        NSString *url = json[@"url"];
        if (url && url.length > 0) {
            item.playQueueItem = [self _createMetaWithVideoUrl:url audioUrl:nil userAgent:nil referer:item.pageAddress title:item.title isAdaptive:NO];
            return nil;
        }
        return [NSError errorWithDomain:MacLCWebVideoErrorDomain code:MacLCWebVideoErrorNotAVideo userInfo:@{NSLocalizedDescriptionKey: @"The extractor failed.", NSLocalizedFailureReasonErrorKey: @"No usable formats found."}];
    }
    
    if (bestVideo) {
        NSString *vurl = bestVideo[@"url"];
        NSString *acodec = bestVideo[@"acodec"];
        BOOL hasAudio = acodec && ![acodec isEqualToString:@"none"];
        NSDictionary *headers = bestVideo[@"http_headers"];
        NSString *ua = headers[@"User-Agent"];
        
        if (hasAudio) {
            item.playQueueItem = [self _createMetaWithVideoUrl:vurl audioUrl:nil userAgent:ua referer:item.pageAddress title:item.title isAdaptive:NO];
        } else {
            NSString *aurl = bestAudio ? bestAudio[@"url"] : nil;
            item.playQueueItem = [self _createMetaWithVideoUrl:vurl audioUrl:aurl userAgent:ua referer:item.pageAddress title:item.title isAdaptive:YES];
        }
    } else {
        // audio only
        NSString *aurl = bestAudio[@"url"];
        NSDictionary *headers = bestAudio[@"http_headers"];
        NSString *ua = headers[@"User-Agent"];
        item.playQueueItem = [self _createMetaWithVideoUrl:aurl audioUrl:nil userAgent:ua referer:item.pageAddress title:item.title isAdaptive:NO];
    }
    
    return nil;
}

/* Apple silicon decodes H.264, HEVC and AV1 in hardware; VP9 it does not, and
 * a 4K VP9 stream eats the time the video filters need. */
- (NSInteger)_codecScore:(NSString *)codec {
    if ([codec hasPrefix:@"avc1"] || [codec hasPrefix:@"h264"]) return 4;
    if ([codec hasPrefix:@"hev1"] || [codec hasPrefix:@"hvc1"]) return 3;
    if ([codec hasPrefix:@"av01"]) return 2;
    if ([codec hasPrefix:@"vp9"] || [codec hasPrefix:@"vp09"]) return 1;
    return 0;
}

/* An option value carrying a line break would be split by the option parser,
 * and a user agent carrying one would be a header injection. */
static NSString *MacLCWebVideoSingleLine(NSString *string)
{
    if (string == nil) {
        return nil;
    }

    NSArray<NSString *> * const lines =
        [string componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];
    return [lines componentsJoinedByString:@" "];
}

- (VLCOpenInputMetadata *)_createMetaWithVideoUrl:(NSString *)vurl audioUrl:(NSString *)aurl userAgent:(NSString *)ua referer:(NSString *)ref title:(NSString *)title isAdaptive:(BOOL)isAdaptive {
    ua = MacLCWebVideoSingleLine(ua);
    title = MacLCWebVideoSingleLine(title);
    /* -initWithPath: runs the string through vlc_path2uri, which turns a web
     * address into a file:// URL. A media address is already an MRL. */
    VLCOpenInputMetadata *meta = [[VLCOpenInputMetadata alloc] init];
    meta.MRLString = vurl;
    meta.itemName = title ?: vurl;
    
    NSMutableArray *opts = [NSMutableArray array];
    
    if (aurl && [self _isValidAddressForOptions:aurl]) {
        [opts addObject:[NSString stringWithFormat:@":input-slave=%@", aurl]];
    }
    if (ua) {
        [opts addObject:[NSString stringWithFormat:@":http-user-agent=%@", ua]];
    }
    if (ref && [self _isValidAddressForOptions:ref]) {
        [opts addObject:[NSString stringWithFormat:@":http-referrer=%@", ref]];
    }
    if (title) {
        [opts addObject:[NSString stringWithFormat:@":meta-title=%@", title]];
    }
    
    NSURL *u = [NSURL URLWithString:vurl];
    if ((u && [u.host hasSuffix:@".googlevideo.com"]) || isAdaptive) {
        [opts addObject:@":http-chunk-size=1048576"];
    }
    
    meta.playbackOptions = opts;
    return meta;
}

@end
