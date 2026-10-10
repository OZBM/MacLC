/*****************************************************************************
 * MacLCAddons.m: add-ons that speak the Stremio add-on protocol
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
#import "addons/MacLCAddons.h"

NSString * const MacLCAddonsDefaultsKey = @"MacLCAddons";
NSNotificationName const MacLCAddonsDidChangeNotification = @"MacLCAddonsDidChangeNotification";
NSErrorDomain const MacLCAddonsErrorDomain = @"MacLCAddonsErrorDomain";

NSString *MacLCAddonsUnresolvedHost(NSError *error)
{
    if (![error.domain isEqualToString:NSURLErrorDomain]
        || (error.code != NSURLErrorCannotFindHost && error.code != NSURLErrorDNSLookupFailed))
        return nil;
    NSURL * const url = error.userInfo[NSURLErrorFailingURLErrorKey];
    return [url isKindOfClass:[NSURL class]] ? url.host : nil;
}

#pragma mark - Helper Functions

static NSString *PercentEncodeQueryComponent(NSString *string)
{
    if (string.length == 0) {
        return @"";
    }
    NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) {
        return @"";
    }
    const unsigned char *bytes = (const unsigned char *)data.bytes;
    NSUInteger len = data.length;
    NSMutableString *result = [NSMutableString stringWithCapacity:len * 2];
    for (NSUInteger i = 0; i < len; i++) {
        unsigned char c = bytes[i];
        if ((c >= 'a' && c <= 'z') ||
            (c >= 'A' && c <= 'Z') ||
            (c >= '0' && c <= '9') ||
            c == '-' || c == '.' || c == '_' || c == '~') {
            [result appendFormat:@"%c", c];
        } else {
            [result appendFormat:@"%%%02X", c];
        }
    }
    return result;
}

static NSString *PercentEncodePathSegment(NSString *string)
{
    if (string.length == 0) {
        return @"";
    }
    NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) {
        return @"";
    }
    const unsigned char *bytes = (const unsigned char *)data.bytes;
    NSUInteger len = data.length;
    NSMutableString *result = [NSMutableString stringWithCapacity:len * 2];
    for (NSUInteger i = 0; i < len; i++) {
        unsigned char c = bytes[i];
        if ((c >= 'a' && c <= 'z') ||
            (c >= 'A' && c <= 'Z') ||
            (c >= '0' && c <= '9') ||
            c == '-' || c == '.' || c == '_' || c == '~' || c == ':') {
            [result appendFormat:@"%c", c];
        } else {
            [result appendFormat:@"%%%02X", c];
        }
    }
    return result;
}

static NSString *EscapeMRLFragment(NSString *string)
{
    if (string.length == 0) {
        return @"";
    }
    NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) {
        return @"";
    }
    const unsigned char *bytes = (const unsigned char *)data.bytes;
    NSUInteger len = data.length;
    NSMutableString *result = [NSMutableString stringWithCapacity:len * 2];
    for (NSUInteger i = 0; i < len; i++) {
        unsigned char c = bytes[i];
        if ((c >= 'a' && c <= 'z') ||
            (c >= 'A' && c <= 'Z') ||
            (c >= '0' && c <= '9') ||
            c == '-' || c == '.' || c == '_' || c == '~' ||
            c == '$' || c == '&' || c == '\'' || c == '(' || c == ')' ||
            c == '*' || c == '+' || c == ',' || c == ';' || c == '=' ||
            c == ':' || c == '@' || c == '/') {
            [result appendFormat:@"%c", c];
        } else {
            [result appendFormat:@"%%%02X", c];
        }
    }
    return result;
}

static NSArray<NSString *> *DefaultTrackers(void)
{
    return @[
        @"udp://tracker.opentrackr.org:1337/announce",
        @"udp://open.stealth.si:80/announce",
        @"udp://tracker.torrent.eu.org:451/announce",
        @"udp://exodus.desync.com:6969/announce",
        @"udp://open.demonii.com:1337/announce",
    ];
}

static NSDate * _Nullable ParseDate(NSString *str)
{
    if (str.length == 0) {
        return nil;
    }
    static NSISO8601DateFormatter *isoWithSecs = nil;
    static NSISO8601DateFormatter *isoBasic = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        isoWithSecs = [[NSISO8601DateFormatter alloc] init];
        isoWithSecs.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;
        isoBasic = [[NSISO8601DateFormatter alloc] init];
        isoBasic.formatOptions = NSISO8601DateFormatWithInternetDateTime;
    });

    NSDate *date = [isoWithSecs dateFromString:str];
    if (!date) {
        date = [isoBasic dateFromString:str];
    }
    if (!date && str.length >= 10) {
        static NSDateFormatter *dayFormatter = nil;
        static dispatch_once_t dayOnceToken;
        dispatch_once(&dayOnceToken, ^{
            dayFormatter = [[NSDateFormatter alloc] init];
            dayFormatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
            dayFormatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
            dayFormatter.dateFormat = @"yyyy-MM-dd";
        });
        date = [dayFormatter dateFromString:[str substringToIndex:10]];
    }
    return date;
}

static NSArray<NSString *> *CleanLines(NSString * _Nullable str)
{
    if (!str || str.length == 0) {
        return @[];
    }
    NSString *clean = [str stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"];
    clean = [clean stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];
    NSArray<NSString *> *raw = [clean componentsSeparatedByString:@"\n"];
    NSMutableArray<NSString *> *result = [NSMutableArray arrayWithCapacity:raw.count];
    for (NSString *line in raw) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (trimmed.length > 0) {
            [result addObject:trimmed];
        }
    }
    return result;
}

static NSArray<NSString *> *TokenizeQuality(NSArray<NSString *> *lines)
{
    NSMutableArray<NSString *> *tokens = [NSMutableArray array];
    NSCharacterSet *delimiters = [NSCharacterSet characterSetWithCharactersInString:@" \t|"];
    for (NSString *line in lines) {
        NSArray<NSString *> *parts = [line componentsSeparatedByCharactersInSet:delimiters];
        for (NSString *part in parts) {
            NSString *trimmed = [part stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if (trimmed.length > 0) {
                [tokens addObject:trimmed];
            }
        }
    }
    return [tokens copy];
}

static NSURL * _Nullable URLFromStringWithPipeSupport(NSString * _Nullable str)
{
    if (!str || str.length == 0) {
        return nil;
    }
    NSURL *url = [NSURL URLWithString:str];
    if (!url && [str containsString:@"|"]) {
        NSString *escaped = [str stringByReplacingOccurrencesOfString:@"|" withString:@"%7C"];
        url = [NSURL URLWithString:escaped];
    }
    return url;
}

static NSString * _Nullable ParseString(id strObj)
{
    if ([strObj isKindOfClass:[NSString class]] && [(NSString *)strObj length] > 0) {
        return (NSString *)strObj;
    }
    return nil;
}

static NSURL * _Nullable ParseURL(id urlObj)
{
    if ([urlObj isKindOfClass:[NSString class]] && [(NSString *)urlObj length] > 0) {
        return URLFromStringWithPipeSupport((NSString *)urlObj);
    }
    return nil;
}

static NSString * _Nullable ParseRating(id ratingObj)
{
    if ([ratingObj isKindOfClass:[NSString class]]) {
        return [(NSString *)ratingObj length] > 0 ? (NSString *)ratingObj : nil;
    }
    if ([ratingObj isKindOfClass:[NSNumber class]]) {
        return [(NSNumber *)ratingObj stringValue];
    }
    return nil;
}

static NSArray<NSString *> *ParseGenres(NSDictionary *dict)
{
    id genresObj = dict[@"genres"];
    if ([genresObj isKindOfClass:[NSArray class]]) {
        NSMutableArray<NSString *> *genres = [NSMutableArray array];
        for (id g in (NSArray *)genresObj) {
            if ([g isKindOfClass:[NSString class]] && [(NSString *)g length] > 0) {
                [genres addObject:(NSString *)g];
            }
        }
        if (genres.count > 0) {
            return [genres copy];
        }
    }

    id genreObj = dict[@"genre"];
    if ([genreObj isKindOfClass:[NSArray class]]) {
        NSMutableArray<NSString *> *genres = [NSMutableArray array];
        for (id g in (NSArray *)genreObj) {
            if ([g isKindOfClass:[NSString class]] && [(NSString *)g length] > 0) {
                [genres addObject:(NSString *)g];
            }
        }
        if (genres.count > 0) {
            return [genres copy];
        }
    } else if ([genreObj isKindOfClass:[NSString class]] && [(NSString *)genreObj length] > 0) {
        return @[(NSString *)genreObj];
    }

    return @[];
}

static NSArray<NSString *> *ParseCast(NSDictionary *dict)
{
    NSMutableArray<NSString *> *result = [NSMutableArray array];
    id castObj = dict[@"cast"];
    if ([castObj isKindOfClass:[NSArray class]]) {
        for (id c in (NSArray *)castObj) {
            if ([c isKindOfClass:[NSString class]] && [(NSString *)c length] > 0) {
                [result addObject:(NSString *)c];
            }
        }
    } else if ([castObj isKindOfClass:[NSString class]] && [(NSString *)castObj length] > 0) {
        [result addObject:(NSString *)castObj];
    }
    if (result.count == 0) {
        id linksObj = dict[@"links"];
        if ([linksObj isKindOfClass:[NSArray class]]) {
            for (id item in (NSArray *)linksObj) {
                if ([item isKindOfClass:[NSDictionary class]]) {
                    NSDictionary *link = (NSDictionary *)item;
                    id cat = link[@"category"];
                    if ([cat isKindOfClass:[NSString class]] && [cat isEqualToString:@"Cast"]) {
                        id name = link[@"name"];
                        if ([name isKindOfClass:[NSString class]] && [(NSString *)name length] > 0) {
                            [result addObject:(NSString *)name];
                        }
                    }
                }
            }
        }
    }
    if (result.count > 6) {
        return [result subarrayWithRange:NSMakeRange(0, 6)];
    }
    return [result copy];
}

static NSArray<NSString *> *ParseDirectors(NSDictionary *dict)
{
    NSMutableArray<NSString *> *result = [NSMutableArray array];
    id dirObj = dict[@"director"];
    if (!dirObj) {
        dirObj = dict[@"directors"];
    }
    if ([dirObj isKindOfClass:[NSArray class]]) {
        for (id d in (NSArray *)dirObj) {
            if ([d isKindOfClass:[NSString class]] && [(NSString *)d length] > 0) {
                [result addObject:(NSString *)d];
            }
        }
    } else if ([dirObj isKindOfClass:[NSString class]] && [(NSString *)dirObj length] > 0) {
        [result addObject:(NSString *)dirObj];
    }

    if (result.count == 0) {
        id linksObj = dict[@"links"];
        if ([linksObj isKindOfClass:[NSArray class]]) {
            for (id item in (NSArray *)linksObj) {
                if ([item isKindOfClass:[NSDictionary class]]) {
                    NSDictionary *link = (NSDictionary *)item;
                    id cat = link[@"category"];
                    if ([cat isKindOfClass:[NSString class]] &&
                        ([cat isEqualToString:@"Directors"] || [cat isEqualToString:@"Director"])) {
                        id name = link[@"name"];
                        if ([name isKindOfClass:[NSString class]] && [(NSString *)name length] > 0) {
                            [result addObject:(NSString *)name];
                        }
                    }
                }
            }
        }
    }
    return [result copy];
}

static NSString * _Nullable ParseTrailer(NSDictionary *dict)
{
    id streamsObj = dict[@"trailerStreams"];
    if ([streamsObj isKindOfClass:[NSArray class]]) {
        for (id s in (NSArray *)streamsObj) {
            if ([s isKindOfClass:[NSDictionary class]]) {
                id ytId = ((NSDictionary *)s)[@"ytId"];
                if ([ytId isKindOfClass:[NSString class]] && [(NSString *)ytId length] > 0) {
                    return (NSString *)ytId;
                }
            }
        }
    }

    id trailersObj = dict[@"trailers"];
    if ([trailersObj isKindOfClass:[NSArray class]]) {
        for (id t in (NSArray *)trailersObj) {
            if ([t isKindOfClass:[NSDictionary class]]) {
                id source = ((NSDictionary *)t)[@"source"];
                if ([source isKindOfClass:[NSString class]] && [(NSString *)source length] > 0) {
                    return (NSString *)source;
                }
            }
        }
    }

    return nil;
}

#pragma mark - Class Extensions

@interface MacLCAddonCatalog ()
@property MacLCAddon *addon;
@property (copy) NSString *type;
@property (copy) NSString *identifier;
@property (copy) NSString *name;
- (instancetype)initWithAddon:(MacLCAddon *)addon
                         type:(NSString *)type
                   identifier:(NSString *)identifier
                         name:(NSString *)name;
@end

@interface MacLCAddonItem ()
@property MacLCAddon *addon;
@property (copy) NSString *identifier;
@property (copy) NSString *type;
@property (copy) NSString *name;
@property (copy, nullable) NSString *releaseInfo;
@property (nullable) NSURL *posterURL;
@property (copy, nullable) NSString *itemDescription;
@property (nullable) NSURL *backgroundURL;
@property (nullable) NSURL *logoURL;
@property (copy) NSArray<NSString *> *genres;
@property (copy, nullable) NSString *imdbRating;
@property (copy, nullable) NSString *runtime;
@property (copy, nullable) NSDictionary *rawMeta;
- (instancetype)initWithAddon:(MacLCAddon *)addon
                   identifier:(NSString *)identifier
                         type:(NSString *)type
                         name:(NSString *)name
                  releaseInfo:(nullable NSString *)releaseInfo
                    posterURL:(nullable NSURL *)posterURL
              itemDescription:(nullable NSString *)itemDescription
                backgroundURL:(nullable NSURL *)backgroundURL
                      logoURL:(nullable NSURL *)logoURL
                       genres:(nullable NSArray<NSString *> *)genres
                   imdbRating:(nullable NSString *)imdbRating
                      runtime:(nullable NSString *)runtime;
- (instancetype)initWithAddon:(MacLCAddon *)addon
                   identifier:(NSString *)identifier
                         type:(NSString *)type
                         name:(NSString *)name
                  releaseInfo:(nullable NSString *)releaseInfo
                    posterURL:(nullable NSURL *)posterURL;
@end

@interface MacLCAddonSearchGroup ()
@property MacLCAddon *addon;
@property (copy) NSString *type;
@property (copy) NSString *catalogName;
@property (copy) NSArray<MacLCAddonItem *> *items;
@property (nullable) NSError *error;
- (instancetype)initWithAddon:(MacLCAddon *)addon
                         type:(NSString *)type
                  catalogName:(NSString *)catalogName
                        items:(NSArray<MacLCAddonItem *> *)items
                        error:(nullable NSError *)error;
@end

@interface MacLCAddonVideo ()
@property (copy) NSString *identifier;
@property NSInteger season;
@property NSInteger episode;
@property (copy, nullable) NSString *name;
@property (nullable) NSDate *released;
@property (nullable) NSURL *thumbnailURL;
@property (copy, nullable) NSString *overview;
- (instancetype)initWithIdentifier:(NSString *)identifier
                            season:(NSInteger)season
                           episode:(NSInteger)episode
                              name:(nullable NSString *)name
                          released:(nullable NSDate *)released
                      thumbnailURL:(nullable NSURL *)thumbnailURL
                          overview:(nullable NSString *)overview;
- (instancetype)initWithIdentifier:(NSString *)identifier
                            season:(NSInteger)season
                           episode:(NSInteger)episode
                              name:(nullable NSString *)name
                          released:(nullable NSDate *)released;
@end

@interface MacLCAddonMeta ()
@property (copy) NSArray<MacLCAddonVideo *> *videos;
@property (copy) NSString *defaultVideoIdentifier;
@property (copy, nullable) NSString *name;
@property (copy, nullable) NSString *itemDescription;
@property (copy, nullable) NSString *releaseInfo;
@property (nullable) NSURL *posterURL;
@property (nullable) NSURL *backgroundURL;
@property (nullable) NSURL *logoURL;
@property (copy) NSArray<NSString *> *genres;
@property (copy, nullable) NSString *imdbRating;
@property (copy, nullable) NSString *runtime;
@property (copy) NSArray<NSString *> *cast;
@property (copy) NSArray<NSString *> *directors;
@property (copy, nullable) NSString *trailerYouTubeIdentifier;
- (instancetype)initWithVideos:(NSArray<MacLCAddonVideo *> *)videos
        defaultVideoIdentifier:(NSString *)defaultVideoIdentifier
                          name:(nullable NSString *)name
               itemDescription:(nullable NSString *)itemDescription
                   releaseInfo:(nullable NSString *)releaseInfo
                     posterURL:(nullable NSURL *)posterURL
                 backgroundURL:(nullable NSURL *)backgroundURL
                       logoURL:(nullable NSURL *)logoURL
                        genres:(nullable NSArray<NSString *> *)genres
                    imdbRating:(nullable NSString *)imdbRating
                       runtime:(nullable NSString *)runtime
                          cast:(nullable NSArray<NSString *> *)cast
                     directors:(nullable NSArray<NSString *> *)directors
      trailerYouTubeIdentifier:(nullable NSString *)trailerYouTubeIdentifier;
- (instancetype)initWithVideos:(NSArray<MacLCAddonVideo *> *)videos
        defaultVideoIdentifier:(NSString *)defaultVideoIdentifier;
@end

@interface MacLCAddonTitleCatalog ()
@property MacLCAddon *addon;
@property (copy) NSString *type;
@property (copy) NSString *identifier;
@property (copy) NSString *name;
@property (copy) NSArray<NSString *> *genres;
@property BOOL requiresGenre;
@property BOOL supportsSkip;
- (instancetype)initWithAddon:(MacLCAddon *)addon
                         type:(NSString *)type
                   identifier:(NSString *)identifier
                         name:(NSString *)name
                       genres:(NSArray<NSString *> *)genres
                requiresGenre:(BOOL)requiresGenre
                 supportsSkip:(BOOL)supportsSkip;
@end

@interface MacLCAddonStream ()
@property MacLCAddon *addon;
@property (copy) NSString *label;
@property (copy) NSArray<NSString *> *qualityTokens;
@property (copy) NSString *headline;
@property (copy, nullable) NSString *details;
@property (copy, nullable) NSString *infoHash;
@property (copy, nullable) NSString *filename;
@property (copy) NSArray<NSString *> *trackers;
@property (nullable) NSURL *directURL;
@property (copy, nullable) NSString *youTubeIdentifier;
@property (copy) NSString *MRL;
- (instancetype)initWithAddon:(MacLCAddon *)addon
                        label:(NSString *)label
                qualityTokens:(NSArray<NSString *> *)qualityTokens
                     headline:(NSString *)headline
                      details:(nullable NSString *)details
                     infoHash:(nullable NSString *)infoHash
                     filename:(nullable NSString *)filename
                     trackers:(NSArray<NSString *> *)trackers
                    directURL:(nullable NSURL *)directURL
            youTubeIdentifier:(nullable NSString *)youTubeIdentifier
                          MRL:(NSString *)MRL;
@end

@interface MacLCAddonStreamGroup ()
@property MacLCAddon *addon;
@property (copy) NSArray<MacLCAddonStream *> *streams;
@property (nullable) NSError *error;
- (instancetype)initWithAddon:(MacLCAddon *)addon
                      streams:(NSArray<MacLCAddonStream *> *)streams
                        error:(nullable NSError *)error;
@end

@interface MacLCAddonRequest ()
@property (getter=isCancelled) BOOL cancelled;
@property (readonly) NSMutableArray<NSURLSessionTask *> *tasks;
- (void)addTask:(NSURLSessionTask *)task;
@end

@interface MacLCAddon ()
@property (copy) NSString *transportURL;
@property (copy) NSData *manifestData;
@property (copy) NSString *identifier;
@property (copy) NSString *name;
@property (copy) NSString *version;
@property (copy, nullable) NSString *addonDescription;
@property (nullable) NSURL *logoURL;
@property (copy) NSArray<NSString *> *types;
@property (nullable) NSURL *configureURL;
@property (getter=isRemovable) BOOL removable;
@property (copy) NSArray<NSString *> *resourceNames;
@property (copy) NSArray *resources;
@property (copy) NSArray<NSString *> *idPrefixes;
@property (copy) NSArray *catalogs;
@property (copy) NSArray *rawAddonCatalogs;
@property (copy) NSArray<NSString *> *manifestGenres;
- (BOOL)catalogSupportsSearch:(NSDictionary *)catalog;
- (NSArray<NSDictionary *> *)searchableCatalogs;
- (NSArray<MacLCAddonCatalog *> *)addonCatalogs;
@end

#pragma mark - MacLCAddon Implementation

@implementation MacLCAddon

+ (nullable instancetype)addonWithTransportURL:(NSString *)transportURL
                                  manifestData:(NSData *)data
                                         error:(NSError **)error
{
    if (!data) {
        if (error) {
            *error = [NSError errorWithDomain:MacLCAddonsErrorDomain
                                         code:MacLCAddonsErrorBadResponse
                                     userInfo:nil];
        }
        return nil;
    }

    /* Fragments allowed: "x" is JSON, just not a manifest (NotAnAddon). */
    NSError *jsonError = nil;
    id json = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingFragmentsAllowed error:&jsonError];
    if (!json) {
        if (error) {
            *error = [NSError errorWithDomain:MacLCAddonsErrorDomain
                                         code:MacLCAddonsErrorBadResponse
                                     userInfo:nil];
        }
        return nil;
    }

    if (![json isKindOfClass:[NSDictionary class]]) {
        if (error) {
            *error = [NSError errorWithDomain:MacLCAddonsErrorDomain
                                         code:MacLCAddonsErrorNotAnAddon
                                     userInfo:nil];
        }
        return nil;
    }

    id idObj = json[@"id"];
    if (![idObj isKindOfClass:[NSString class]] || [(NSString *)idObj length] == 0) {
        if (error) {
            *error = [NSError errorWithDomain:MacLCAddonsErrorDomain
                                         code:MacLCAddonsErrorNotAnAddon
                                     userInfo:nil];
        }
        return nil;
    }

    id nameObj = json[@"name"];
    if (![nameObj isKindOfClass:[NSString class]] || [(NSString *)nameObj length] == 0) {
        if (error) {
            *error = [NSError errorWithDomain:MacLCAddonsErrorDomain
                                         code:MacLCAddonsErrorNotAnAddon
                                     userInfo:nil];
        }
        return nil;
    }

    id verObj = json[@"version"];
    if (![verObj isKindOfClass:[NSString class]] || [(NSString *)verObj length] == 0) {
        if (error) {
            *error = [NSError errorWithDomain:MacLCAddonsErrorDomain
                                         code:MacLCAddonsErrorNotAnAddon
                                     userInfo:nil];
        }
        return nil;
    }

    id resObj = json[@"resources"];
    if (![resObj isKindOfClass:[NSArray class]] || [(NSArray *)resObj count] == 0) {
        if (error) {
            *error = [NSError errorWithDomain:MacLCAddonsErrorDomain
                                         code:MacLCAddonsErrorNotAnAddon
                                     userInfo:nil];
        }
        return nil;
    }

    NSMutableArray *validResources = [NSMutableArray array];
    NSMutableArray<NSString *> *rNames = [NSMutableArray array];
    NSMutableSet<NSString *> *seenRNames = [NSMutableSet set];
    for (id item in (NSArray *)resObj) {
        NSString *rName = nil;
        if ([item isKindOfClass:[NSString class]]) {
            if ([(NSString *)item length] == 0) {
                if (error) {
                    *error = [NSError errorWithDomain:MacLCAddonsErrorDomain
                                                 code:MacLCAddonsErrorNotAnAddon
                                             userInfo:nil];
                }
                return nil;
            }
            rName = (NSString *)item;
            [validResources addObject:item];
        } else if ([item isKindOfClass:[NSDictionary class]]) {
            id nameVal = ((NSDictionary *)item)[@"name"];
            if (![nameVal isKindOfClass:[NSString class]] || [(NSString *)nameVal length] == 0) {
                if (error) {
                    *error = [NSError errorWithDomain:MacLCAddonsErrorDomain
                                                 code:MacLCAddonsErrorNotAnAddon
                                             userInfo:nil];
                }
                return nil;
            }
            rName = (NSString *)nameVal;
            [validResources addObject:item];
        } else {
            if (error) {
                *error = [NSError errorWithDomain:MacLCAddonsErrorDomain
                                             code:MacLCAddonsErrorNotAnAddon
                                         userInfo:nil];
            }
            return nil;
        }

        if (rName.length > 0 && ![seenRNames containsObject:rName]) {
            [seenRNames addObject:rName];
            [rNames addObject:rName];
        }
    }

    if (validResources.count == 0) {
        if (error) {
            *error = [NSError errorWithDomain:MacLCAddonsErrorDomain
                                         code:MacLCAddonsErrorNotAnAddon
                                     userInfo:nil];
        }
        return nil;
    }

    NSMutableArray<NSString *> *types = [NSMutableArray array];
    id typesObj = json[@"types"];
    if ([typesObj isKindOfClass:[NSArray class]]) {
        for (id t in (NSArray *)typesObj) {
            if ([t isKindOfClass:[NSString class]]) {
                [types addObject:(NSString *)t];
            }
        }
    }

    NSURL *logoURL = nil;
    id logoObj = json[@"logo"];
    if ([logoObj isKindOfClass:[NSString class]] && [(NSString *)logoObj length] > 0) {
        NSURL *u = [NSURL URLWithString:(NSString *)logoObj];
        if (u && ([u.scheme.lowercaseString isEqualToString:@"http"] || [u.scheme.lowercaseString isEqualToString:@"https"])) {
            logoURL = u;
        }
    }

    NSString *addonDescription = nil;
    id descObj = json[@"description"];
    if ([descObj isKindOfClass:[NSString class]] && [(NSString *)descObj length] > 0) {
        addonDescription = (NSString *)descObj;
    }

    NSMutableArray<NSString *> *idPrefixes = [NSMutableArray array];
    id pfxObj = json[@"idPrefixes"];
    if ([pfxObj isKindOfClass:[NSArray class]]) {
        for (id p in (NSArray *)pfxObj) {
            if ([p isKindOfClass:[NSString class]]) {
                [idPrefixes addObject:(NSString *)p];
            }
        }
    }

    NSArray *catalogs = [json[@"catalogs"] isKindOfClass:[NSArray class]] ? json[@"catalogs"] : @[];
    NSArray *rawAddonCatalogs = [json[@"addonCatalogs"] isKindOfClass:[NSArray class]] ? json[@"addonCatalogs"] : @[];

    MacLCAddon *addon = [[MacLCAddon alloc] init];
    addon.transportURL = transportURL;
    addon.manifestData = data;
    addon.identifier = idObj;
    addon.name = nameObj;
    addon.version = verObj;
    addon.addonDescription = addonDescription;
    addon.logoURL = logoURL;
    addon.types = [types copy];
    addon.removable = ![addon.identifier isEqualToString:@"com.linvo.cinemeta"];
    addon.resourceNames = [rNames copy];
    addon.resources = [validResources copy];
    addon.idPrefixes = [idPrefixes copy];
    addon.catalogs = catalogs;
    addon.rawAddonCatalogs = rawAddonCatalogs;

    NSMutableArray<NSString *> *manifestGenres = [NSMutableArray array];
    id genresObj = json[@"genres"];
    if ([genresObj isKindOfClass:[NSArray class]]) {
        for (id g in (NSArray *)genresObj) {
            if ([g isKindOfClass:[NSString class]] && [(NSString *)g length] > 0) {
                [manifestGenres addObject:(NSString *)g];
            }
        }
    }
    addon.manifestGenres = [manifestGenres copy];

    id hints = json[@"behaviorHints"];
    if ([hints isKindOfClass:[NSDictionary class]]) {
        id conf = hints[@"configurable"];
        if ([conf isKindOfClass:[NSNumber class]] && [conf boolValue]) {
            NSString *confStr = [addon.baseURL.absoluteString stringByAppendingString:@"/configure"];
            addon.configureURL = URLFromStringWithPipeSupport(confStr);
        }
    }

    return addon;
}

- (NSURL *)baseURL
{
    NSString *baseStr = self.transportURL;
    if ([baseStr hasSuffix:@"/manifest.json"]) {
        baseStr = [baseStr substringToIndex:baseStr.length - 14];
    } else if ([baseStr hasSuffix:@"manifest.json"]) {
        baseStr = [baseStr substringToIndex:baseStr.length - 13];
    }
    while ([baseStr hasSuffix:@"/"]) {
        baseStr = [baseStr substringToIndex:baseStr.length - 1];
    }
    return URLFromStringWithPipeSupport(baseStr) ?: [NSURL URLWithString:@"about:blank"];
}

- (BOOL)providesStreams
{
    return [self.resourceNames containsObject:@"stream"];
}

- (BOOL)catalogSupportsSearch:(NSDictionary *)catalog
{
    id extra = catalog[@"extra"];
    if ([extra isKindOfClass:[NSArray class]]) {
        for (id item in (NSArray *)extra) {
            if ([item isKindOfClass:[NSDictionary class]]) {
                id name = item[@"name"];
                if ([name isKindOfClass:[NSString class]] && [name isEqualToString:@"search"]) {
                    return YES;
                }
            } else if ([item isKindOfClass:[NSString class]] && [item isEqualToString:@"search"]) {
                return YES;
            }
        }
    }
    id extraSupported = catalog[@"extraSupported"];
    if ([extraSupported isKindOfClass:[NSArray class]]) {
        for (id item in (NSArray *)extraSupported) {
            if ([item isKindOfClass:[NSString class]] && [item isEqualToString:@"search"]) {
                return YES;
            }
        }
    }
    return NO;
}

- (BOOL)providesSearch
{
    for (id item in _catalogs) {
        if ([item isKindOfClass:[NSDictionary class]] && [self catalogSupportsSearch:(NSDictionary *)item]) {
            return YES;
        }
    }
    return NO;
}

- (NSArray<NSDictionary *> *)searchableCatalogs
{
    NSMutableArray<NSDictionary *> *result = [NSMutableArray array];
    for (id item in _catalogs) {
        if ([item isKindOfClass:[NSDictionary class]] && [self catalogSupportsSearch:(NSDictionary *)item]) {
            [result addObject:(NSDictionary *)item];
        }
    }
    return [result copy];
}

- (BOOL)providesResource:(NSString *)resource
                 forType:(NSString *)type
              identifier:(nullable NSString *)identifier
{
    if (resource.length == 0 || type.length == 0) {
        return NO;
    }

    for (id entry in _resources) {
        NSString *entryName = nil;
        NSArray<NSString *> *effectiveTypes = nil;
        NSArray<NSString *> *effectiveIdPrefixes = nil;
        BOOL hasExplicitIdPrefixes = NO;

        if ([entry isKindOfClass:[NSString class]]) {
            entryName = (NSString *)entry;
            effectiveTypes = self.types;
            effectiveIdPrefixes = _idPrefixes;
            hasExplicitIdPrefixes = (_idPrefixes.count > 0);
        } else if ([entry isKindOfClass:[NSDictionary class]]) {
            NSDictionary *dict = (NSDictionary *)entry;
            entryName = dict[@"name"];
            if (![entryName isKindOfClass:[NSString class]]) {
                continue;
            }

            id entryTypes = dict[@"types"];
            if ([entryTypes isKindOfClass:[NSArray class]]) {
                NSMutableArray<NSString *> *tArr = [NSMutableArray array];
                for (id t in (NSArray *)entryTypes) {
                    if ([t isKindOfClass:[NSString class]]) {
                        [tArr addObject:(NSString *)t];
                    }
                }
                effectiveTypes = [tArr copy];
            } else {
                effectiveTypes = self.types;
            }

            id entryPrefixes = dict[@"idPrefixes"];
            if ([entryPrefixes isKindOfClass:[NSArray class]]) {
                NSMutableArray<NSString *> *pArr = [NSMutableArray array];
                for (id p in (NSArray *)entryPrefixes) {
                    if ([p isKindOfClass:[NSString class]]) {
                        [pArr addObject:(NSString *)p];
                    }
                }
                effectiveIdPrefixes = [pArr copy];
                hasExplicitIdPrefixes = YES;
            } else {
                effectiveIdPrefixes = _idPrefixes;
                hasExplicitIdPrefixes = (_idPrefixes.count > 0);
            }
        } else {
            continue;
        }

        if (![entryName isEqualToString:resource]) {
            continue;
        }

        if (effectiveTypes.count > 0 && ![effectiveTypes containsObject:type]) {
            continue;
        }

        if (identifier != nil && hasExplicitIdPrefixes && effectiveIdPrefixes.count > 0) {
            BOOL prefixMatch = NO;
            for (NSString *prefix in effectiveIdPrefixes) {
                if ([identifier hasPrefix:prefix]) {
                    prefixMatch = YES;
                    break;
                }
            }
            if (!prefixMatch) {
                continue;
            }
        }

        return YES;
    }

    return NO;
}

- (NSArray<MacLCAddonCatalog *> *)addonCatalogs
{
    NSMutableArray<NSDictionary *> *catalogDicts = [NSMutableArray array];
    BOOL hasAllType = NO;
    for (id item in _rawAddonCatalogs) {
        if ([item isKindOfClass:[NSDictionary class]]) {
            NSDictionary *d = (NSDictionary *)item;
            if ([d[@"type"] isKindOfClass:[NSString class]] && [d[@"type"] isEqualToString:@"all"]) {
                hasAllType = YES;
            }
            [catalogDicts addObject:d];
        }
    }

    NSMutableArray<MacLCAddonCatalog *> *result = [NSMutableArray array];
    for (NSDictionary *d in catalogDicts) {
        NSString *type = d[@"type"];
        NSString *catId = d[@"id"];
        NSString *catName = d[@"name"];
        if (![type isKindOfClass:[NSString class]] ||
            ![catId isKindOfClass:[NSString class]] ||
            ![catName isKindOfClass:[NSString class]]) {
            continue;
        }
        if (hasAllType && ![type isEqualToString:@"all"]) {
            continue;
        }
        MacLCAddonCatalog *cat = [[MacLCAddonCatalog alloc] initWithAddon:self
                                                                     type:type
                                                               identifier:catId
                                                                     name:catName];
        [result addObject:cat];
    }
    return [result copy];
}

@end

#pragma mark - MacLCAddonCatalog Implementation

@implementation MacLCAddonCatalog

- (instancetype)initWithAddon:(MacLCAddon *)addon
                         type:(NSString *)type
                   identifier:(NSString *)identifier
                         name:(NSString *)name
{
    self = [super init];
    if (self) {
        _addon = addon;
        _type = [type copy];
        _identifier = [identifier copy];
        _name = [name copy];
    }
    return self;
}

@end

#pragma mark - MacLCAddonItem Implementation

/* Defined further down with the rest of the store. */
@interface MacLCAddonStore ()
- (NSArray<MacLCAddon *> *)defaultAddons;
+ (nullable NSArray<MacLCAddonItem *> *)itemsFromCatalogData:(NSData *)data
                                                       addon:(MacLCAddon *)addon
                                                 defaultType:(NSString *)defaultType
                                                       error:(NSError **)error;
@end

@implementation MacLCAddonItem

- (instancetype)initWithAddon:(MacLCAddon *)addon
                   identifier:(NSString *)identifier
                         type:(NSString *)type
                         name:(NSString *)name
                  releaseInfo:(nullable NSString *)releaseInfo
                    posterURL:(nullable NSURL *)posterURL
              itemDescription:(nullable NSString *)itemDescription
                backgroundURL:(nullable NSURL *)backgroundURL
                      logoURL:(nullable NSURL *)logoURL
                       genres:(nullable NSArray<NSString *> *)genres
                   imdbRating:(nullable NSString *)imdbRating
                      runtime:(nullable NSString *)runtime
{
    self = [super init];
    if (self) {
        _addon = addon;
        _identifier = [identifier copy];
        _type = [type copy];
        _name = [name copy];
        _releaseInfo = [releaseInfo copy];
        _posterURL = posterURL;
        _itemDescription = [itemDescription copy];
        _backgroundURL = backgroundURL;
        _logoURL = logoURL;
        _genres = [genres copy] ?: @[];
        _imdbRating = [imdbRating copy];
        _runtime = [runtime copy];
    }
    return self;
}

- (instancetype)initWithAddon:(MacLCAddon *)addon
                   identifier:(NSString *)identifier
                         type:(NSString *)type
                         name:(NSString *)name
                  releaseInfo:(nullable NSString *)releaseInfo
                    posterURL:(nullable NSURL *)posterURL
{
    return [self initWithAddon:addon
                    identifier:identifier
                          type:type
                          name:name
                   releaseInfo:releaseInfo
                     posterURL:posterURL
               itemDescription:nil
                 backgroundURL:nil
                       logoURL:nil
                        genres:@[]
                    imdbRating:nil
                       runtime:nil];
}

+ (nullable MacLCAddonItem *)itemFromRawMeta:(NSDictionary *)meta addonTransportURL:(NSString *)transportURL
{
    if (![meta isKindOfClass:[NSDictionary class]] || ![NSJSONSerialization isValidJSONObject:meta]) {
        return nil;
    }
    MacLCAddonStore *store = [MacLCAddonStore sharedStore];
    MacLCAddon *addon = nil;
    for (MacLCAddon *candidate in store.installedAddons) {
        if ([candidate.transportURL isEqualToString:transportURL]) {
            addon = candidate;
            break;
        }
    }
    addon = addon ?: [store defaultAddons].firstObject;
    if (!addon) {
        return nil;
    }
    /* The catalog parser takes a catalog document, so wrap the entry in one. */
    NSData *data = [NSJSONSerialization dataWithJSONObject:@{@"metas": @[meta]} options:0 error:nil];
    return [[MacLCAddonStore itemsFromCatalogData:data addon:addon defaultType:@"" error:nil] firstObject];
}

@end

#pragma mark - MacLCAddonSearchGroup Implementation

@implementation MacLCAddonSearchGroup

- (instancetype)initWithAddon:(MacLCAddon *)addon
                         type:(NSString *)type
                  catalogName:(NSString *)catalogName
                        items:(NSArray<MacLCAddonItem *> *)items
                        error:(nullable NSError *)error
{
    self = [super init];
    if (self) {
        _addon = addon;
        _type = [type copy];
        _catalogName = [catalogName copy];
        _items = [items copy] ?: @[];
        _error = error;
    }
    return self;
}

@end

#pragma mark - MacLCAddonVideo Implementation

@implementation MacLCAddonVideo

- (instancetype)initWithIdentifier:(NSString *)identifier
                            season:(NSInteger)season
                           episode:(NSInteger)episode
                              name:(nullable NSString *)name
                          released:(nullable NSDate *)released
                      thumbnailURL:(nullable NSURL *)thumbnailURL
                          overview:(nullable NSString *)overview
{
    self = [super init];
    if (self) {
        _identifier = [identifier copy];
        _season = season;
        _episode = episode;
        _name = [name copy];
        _released = released;
        _thumbnailURL = thumbnailURL;
        _overview = [overview copy];
    }
    return self;
}

- (instancetype)initWithIdentifier:(NSString *)identifier
                            season:(NSInteger)season
                           episode:(NSInteger)episode
                              name:(nullable NSString *)name
                          released:(nullable NSDate *)released
{
    return [self initWithIdentifier:identifier
                             season:season
                            episode:episode
                               name:name
                           released:released
                       thumbnailURL:nil
                           overview:nil];
}

@end

#pragma mark - MacLCAddonMeta Implementation

@implementation MacLCAddonMeta

- (instancetype)initWithVideos:(NSArray<MacLCAddonVideo *> *)videos
        defaultVideoIdentifier:(NSString *)defaultVideoIdentifier
                          name:(nullable NSString *)name
               itemDescription:(nullable NSString *)itemDescription
                   releaseInfo:(nullable NSString *)releaseInfo
                     posterURL:(nullable NSURL *)posterURL
                 backgroundURL:(nullable NSURL *)backgroundURL
                       logoURL:(nullable NSURL *)logoURL
                        genres:(nullable NSArray<NSString *> *)genres
                    imdbRating:(nullable NSString *)imdbRating
                       runtime:(nullable NSString *)runtime
                          cast:(nullable NSArray<NSString *> *)cast
                     directors:(nullable NSArray<NSString *> *)directors
      trailerYouTubeIdentifier:(nullable NSString *)trailerYouTubeIdentifier
{
    self = [super init];
    if (self) {
        _videos = [videos copy] ?: @[];
        _defaultVideoIdentifier = [defaultVideoIdentifier copy];
        _name = [name copy];
        _itemDescription = [itemDescription copy];
        _releaseInfo = [releaseInfo copy];
        _posterURL = posterURL;
        _backgroundURL = backgroundURL;
        _logoURL = logoURL;
        _genres = [genres copy] ?: @[];
        _imdbRating = [imdbRating copy];
        _runtime = [runtime copy];
        _cast = [cast copy] ?: @[];
        _directors = [directors copy] ?: @[];
        _trailerYouTubeIdentifier = [trailerYouTubeIdentifier copy];
    }
    return self;
}

- (instancetype)initWithVideos:(NSArray<MacLCAddonVideo *> *)videos
        defaultVideoIdentifier:(NSString *)defaultVideoIdentifier
{
    return [self initWithVideos:videos
         defaultVideoIdentifier:defaultVideoIdentifier
                           name:nil
                itemDescription:nil
                    releaseInfo:nil
                      posterURL:nil
                  backgroundURL:nil
                        logoURL:nil
                         genres:@[]
                     imdbRating:nil
                        runtime:nil
                           cast:@[]
                      directors:@[]
       trailerYouTubeIdentifier:nil];
}

@end

#pragma mark - MacLCAddonTitleCatalog Implementation

@implementation MacLCAddonTitleCatalog

- (instancetype)initWithAddon:(MacLCAddon *)addon
                         type:(NSString *)type
                   identifier:(NSString *)identifier
                         name:(NSString *)name
                       genres:(NSArray<NSString *> *)genres
                requiresGenre:(BOOL)requiresGenre
                 supportsSkip:(BOOL)supportsSkip
{
    self = [super init];
    if (self) {
        _addon = addon;
        _type = [type copy] ?: @"";
        _identifier = [identifier copy] ?: @"";
        _name = [name copy] ?: @"";
        _genres = [genres copy] ?: @[];
        _requiresGenre = requiresGenre;
        _supportsSkip = supportsSkip;
    }
    return self;
}

@end

#pragma mark - MacLCAddonStream Implementation

@implementation MacLCAddonStream

- (instancetype)initWithAddon:(MacLCAddon *)addon
                        label:(NSString *)label
                qualityTokens:(NSArray<NSString *> *)qualityTokens
                     headline:(NSString *)headline
                      details:(nullable NSString *)details
                     infoHash:(nullable NSString *)infoHash
                     filename:(nullable NSString *)filename
                     trackers:(NSArray<NSString *> *)trackers
                    directURL:(nullable NSURL *)directURL
            youTubeIdentifier:(nullable NSString *)youTubeIdentifier
                          MRL:(NSString *)MRL
{
    self = [super init];
    if (self) {
        _addon = addon;
        _label = [label copy];
        _qualityTokens = [qualityTokens copy] ?: @[];
        _headline = [headline copy];
        _details = [details copy];
        _infoHash = [infoHash copy];
        _filename = [filename copy];
        _trackers = [trackers copy] ?: @[];
        _directURL = directURL;
        _youTubeIdentifier = [youTubeIdentifier copy];
        _MRL = [MRL copy];
    }
    return self;
}

@end

#pragma mark - MacLCAddonStreamGroup Implementation

@implementation MacLCAddonStreamGroup

- (instancetype)initWithAddon:(MacLCAddon *)addon
                      streams:(NSArray<MacLCAddonStream *> *)streams
                        error:(nullable NSError *)error
{
    self = [super init];
    if (self) {
        _addon = addon;
        _streams = [streams copy] ?: @[];
        _error = error;
    }
    return self;
}

@end

#pragma mark - MacLCAddonRequest Implementation

@implementation MacLCAddonRequest

- (instancetype)init
{
    self = [super init];
    if (self) {
        _tasks = [NSMutableArray array];
    }
    return self;
}

- (void)addTask:(NSURLSessionTask *)task
{
    if (!task) return;
    @synchronized (self) {
        if (_cancelled) {
            [task cancel];
            return;
        }
        [_tasks addObject:task];
    }
}

- (void)cancel
{
    NSArray<NSURLSessionTask *> *tasksToCancel = nil;
    @synchronized (self) {
        if (_cancelled) return;
        _cancelled = YES;
        tasksToCancel = [_tasks copy];
        [_tasks removeAllObjects];
    }
    for (NSURLSessionTask *task in tasksToCancel) {
        [task cancel];
    }
}

@end

#pragma mark - Network Execution Helper

static void ExecuteRequest(NSURL * _Nullable url,
                           MacLCAddonRequest *request,
                           void (^completion)(NSData * _Nullable data, NSError * _Nullable error))
{
    if (!url) {
        NSError *err = [NSError errorWithDomain:MacLCAddonsErrorDomain
                                           code:MacLCAddonsErrorBadResponse
                                       userInfo:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!request.isCancelled) {
                completion(nil, err);
            }
        });
        return;
    }

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.timeoutInterval = 20.0;

    __block NSURLSessionDataTask *task = nil;
    task = [NSURLSession.sharedSession dataTaskWithRequest:req completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        if (error) {
            if ([error.domain isEqualToString:NSURLErrorDomain] && error.code == NSURLErrorCancelled) {
                return;
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!request.isCancelled) {
                    completion(nil, error);
                }
            });
            return;
        }

        if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
            if (httpResponse.statusCode != 200) {
                NSError *statusError = [NSError errorWithDomain:MacLCAddonsErrorDomain
                                                           code:MacLCAddonsErrorHTTPStatus
                                                       userInfo:@{@"status": @(httpResponse.statusCode)}];
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (!request.isCancelled) {
                        completion(nil, statusError);
                    }
                });
                return;
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            if (!request.isCancelled) {
                completion(data, nil);
            }
        });
    }];

    [request addTask:task];
    [task resume];
}

#pragma mark - MacLCAddonStore

@interface MacLCAddonStore () {
    NSArray<MacLCAddon *> *_installedAddons;
}
- (void)loadInstalledAddons;
- (void)saveInstalledAddons;
- (void)notifyDidChange;
- (NSArray<MacLCAddon *> *)defaultAddons;
+ (nullable NSArray<MacLCAddonItem *> *)itemsFromCatalogData:(NSData *)data
                                                       addon:(MacLCAddon *)addon
                                                 defaultType:(NSString *)defaultType
                                                       error:(NSError **)error;
@end

@implementation MacLCAddonStore

+ (MacLCAddonStore *)sharedStore
{
    static MacLCAddonStore *store = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        store = [[MacLCAddonStore alloc] init];
    });
    return store;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        [self loadInstalledAddons];
    }
    return self;
}

- (NSArray<MacLCAddon *> *)defaultAddons
{
    NSString *transport = @"https://v3-cinemeta.strem.io/manifest.json";
    /* Cinemeta 3.0.14 as served on 2026-10-06, so its catalogs work before
     * the first refresh (refreshManifests keeps it current). */
    NSString *cinemetaJSON = @"{\"id\":\"com.linvo.cinemeta\",\"version\":\"3.0.14\",\"description\":\"The official addon for movie and series catalogs\",\"name\":\"Cinemeta\",\"resources\":[\"catalog\",\"meta\",\"addon_catalog\"],\"types\":[\"movie\",\"series\"],\"idPrefixes\":[\"tt\"],\"addonCatalogs\":[{\"type\":\"all\",\"id\":\"official\",\"name\":\"Official\"},{\"type\":\"movie\",\"id\":\"official\",\"name\":\"Official\"},{\"type\":\"series\",\"id\":\"official\",\"name\":\"Official\"},{\"type\":\"channel\",\"id\":\"official\",\"name\":\"Official\"},{\"type\":\"all\",\"id\":\"community\",\"name\":\"Community\"},{\"type\":\"movie\",\"id\":\"community\",\"name\":\"Community\"},{\"type\":\"series\",\"id\":\"community\",\"name\":\"Community\"},{\"type\":\"channel\",\"id\":\"community\",\"name\":\"Community\"},{\"type\":\"tv\",\"id\":\"community\",\"name\":\"Community\"},{\"type\":\"Podcasts\",\"id\":\"community\",\"name\":\"Community\"},{\"type\":\"other\",\"id\":\"community\",\"name\":\"Community\"}],\"catalogs\":[{\"type\":\"movie\",\"id\":\"top\",\"genres\":[\"Action\",\"Adventure\",\"Animation\",\"Biography\",\"Comedy\",\"Crime\",\"Documentary\",\"Drama\",\"Family\",\"Fantasy\",\"History\",\"Horror\",\"Mystery\",\"Romance\",\"Sci-Fi\",\"Sport\",\"Thriller\",\"War\",\"Western\"],\"extra\":[{\"name\":\"genre\",\"options\":[\"Action\",\"Adventure\",\"Animation\",\"Biography\",\"Comedy\",\"Crime\",\"Documentary\",\"Drama\",\"Family\",\"Fantasy\",\"History\",\"Horror\",\"Mystery\",\"Romance\",\"Sci-Fi\",\"Sport\",\"Thriller\",\"War\",\"Western\"]},{\"name\":\"search\"},{\"name\":\"skip\"}],\"extraSupported\":[\"search\",\"genre\",\"skip\"],\"name\":\"Popular\"},{\"type\":\"series\",\"id\":\"top\",\"genres\":[\"Action\",\"Adventure\",\"Animation\",\"Biography\",\"Comedy\",\"Crime\",\"Documentary\",\"Drama\",\"Family\",\"Fantasy\",\"History\",\"Horror\",\"Mystery\",\"Romance\",\"Sci-Fi\",\"Sport\",\"Thriller\",\"War\",\"Western\",\"Reality-TV\",\"Talk-Show\",\"Game-Show\"],\"extra\":[{\"name\":\"genre\",\"options\":[\"Action\",\"Adventure\",\"Animation\",\"Biography\",\"Comedy\",\"Crime\",\"Documentary\",\"Drama\",\"Family\",\"Fantasy\",\"History\",\"Horror\",\"Mystery\",\"Romance\",\"Sci-Fi\",\"Sport\",\"Thriller\",\"War\",\"Western\",\"Reality-TV\",\"Talk-Show\",\"Game-Show\"]},{\"name\":\"search\"},{\"name\":\"skip\"}],\"extraSupported\":[\"search\",\"genre\",\"skip\"],\"name\":\"Popular\"},{\"type\":\"movie\",\"id\":\"year\",\"genres\":[\"2026\",\"2025\",\"2024\",\"2023\",\"2022\",\"2021\",\"2020\",\"2019\",\"2018\",\"2017\",\"2016\",\"2015\",\"2014\",\"2013\",\"2012\",\"2011\",\"2010\",\"2009\",\"2008\",\"2007\",\"2006\",\"2005\",\"2004\",\"2003\",\"2002\",\"2001\",\"2000\",\"1999\",\"1998\",\"1997\",\"1996\",\"1995\",\"1994\",\"1993\",\"1992\",\"1991\",\"1990\",\"1989\",\"1988\",\"1987\",\"1986\",\"1985\",\"1984\",\"1983\",\"1982\",\"1981\",\"1980\",\"1979\",\"1978\",\"1977\",\"1976\",\"1975\",\"1974\",\"1973\",\"1972\",\"1971\",\"1970\",\"1969\",\"1968\",\"1967\",\"1966\",\"1965\",\"1964\",\"1963\",\"1962\",\"1961\",\"1960\",\"1959\",\"1958\",\"1957\",\"1956\",\"1955\",\"1954\",\"1953\",\"1952\",\"1951\",\"1950\",\"1949\",\"1948\",\"1947\",\"1946\",\"1945\",\"1944\",\"1943\",\"1942\",\"1941\",\"1940\",\"1939\",\"1938\",\"1937\",\"1936\",\"1935\",\"1934\",\"1933\",\"1932\",\"1931\",\"1930\",\"1929\",\"1928\",\"1927\",\"1926\",\"1925\",\"1924\",\"1923\",\"1922\",\"1921\",\"1920\"],\"extra\":[{\"name\":\"genre\",\"options\":[\"2026\",\"2025\",\"2024\",\"2023\",\"2022\",\"2021\",\"2020\",\"2019\",\"2018\",\"2017\",\"2016\",\"2015\",\"2014\",\"2013\",\"2012\",\"2011\",\"2010\",\"2009\",\"2008\",\"2007\",\"2006\",\"2005\",\"2004\",\"2003\",\"2002\",\"2001\",\"2000\",\"1999\",\"1998\",\"1997\",\"1996\",\"1995\",\"1994\",\"1993\",\"1992\",\"1991\",\"1990\",\"1989\",\"1988\",\"1987\",\"1986\",\"1985\",\"1984\",\"1983\",\"1982\",\"1981\",\"1980\",\"1979\",\"1978\",\"1977\",\"1976\",\"1975\",\"1974\",\"1973\",\"1972\",\"1971\",\"1970\",\"1969\",\"1968\",\"1967\",\"1966\",\"1965\",\"1964\",\"1963\",\"1962\",\"1961\",\"1960\",\"1959\",\"1958\",\"1957\",\"1956\",\"1955\",\"1954\",\"1953\",\"1952\",\"1951\",\"1950\",\"1949\",\"1948\",\"1947\",\"1946\",\"1945\",\"1944\",\"1943\",\"1942\",\"1941\",\"1940\",\"1939\",\"1938\",\"1937\",\"1936\",\"1935\",\"1934\",\"1933\",\"1932\",\"1931\",\"1930\",\"1929\",\"1928\",\"1927\",\"1926\",\"1925\",\"1924\",\"1923\",\"1922\",\"1921\",\"1920\"],\"isRequired\":true},{\"name\":\"skip\"}],\"extraSupported\":[\"genre\",\"skip\"],\"extraRequired\":[\"genre\"],\"name\":\"New\"},{\"type\":\"series\",\"id\":\"year\",\"genres\":[\"2026\",\"2025\",\"2024\",\"2023\",\"2022\",\"2021\",\"2020\",\"2019\",\"2018\",\"2017\",\"2016\",\"2015\",\"2014\",\"2013\",\"2012\",\"2011\",\"2010\",\"2009\",\"2008\",\"2007\",\"2006\",\"2005\",\"2004\",\"2003\",\"2002\",\"2001\",\"2000\",\"1999\",\"1998\",\"1997\",\"1996\",\"1995\",\"1994\",\"1993\",\"1992\",\"1991\",\"1990\",\"1989\",\"1988\",\"1987\",\"1986\",\"1985\",\"1984\",\"1983\",\"1982\",\"1981\",\"1980\",\"1979\",\"1978\",\"1977\",\"1976\",\"1975\",\"1974\",\"1973\",\"1972\",\"1971\",\"1970\",\"1969\",\"1968\",\"1967\",\"1966\",\"1965\",\"1964\",\"1963\",\"1962\",\"1961\",\"1960\"],\"extra\":[{\"name\":\"genre\",\"options\":[\"2026\",\"2025\",\"2024\",\"2023\",\"2022\",\"2021\",\"2020\",\"2019\",\"2018\",\"2017\",\"2016\",\"2015\",\"2014\",\"2013\",\"2012\",\"2011\",\"2010\",\"2009\",\"2008\",\"2007\",\"2006\",\"2005\",\"2004\",\"2003\",\"2002\",\"2001\",\"2000\",\"1999\",\"1998\",\"1997\",\"1996\",\"1995\",\"1994\",\"1993\",\"1992\",\"1991\",\"1990\",\"1989\",\"1988\",\"1987\",\"1986\",\"1985\",\"1984\",\"1983\",\"1982\",\"1981\",\"1980\",\"1979\",\"1978\",\"1977\",\"1976\",\"1975\",\"1974\",\"1973\",\"1972\",\"1971\",\"1970\",\"1969\",\"1968\",\"1967\",\"1966\",\"1965\",\"1964\",\"1963\",\"1962\",\"1961\",\"1960\"],\"isRequired\":true},{\"name\":\"skip\"}],\"extraSupported\":[\"genre\",\"skip\"],\"extraRequired\":[\"genre\"],\"name\":\"New\"},{\"type\":\"movie\",\"id\":\"imdbRating\",\"genres\":[\"Action\",\"Adventure\",\"Animation\",\"Biography\",\"Comedy\",\"Crime\",\"Documentary\",\"Drama\",\"Family\",\"Fantasy\",\"History\",\"Horror\",\"Mystery\",\"Romance\",\"Sci-Fi\",\"Sport\",\"Thriller\",\"War\",\"Western\"],\"extra\":[{\"name\":\"genre\",\"options\":[\"Action\",\"Adventure\",\"Animation\",\"Biography\",\"Comedy\",\"Crime\",\"Documentary\",\"Drama\",\"Family\",\"Fantasy\",\"History\",\"Horror\",\"Mystery\",\"Romance\",\"Sci-Fi\",\"Sport\",\"Thriller\",\"War\",\"Western\"]},{\"name\":\"skip\"}],\"extraSupported\":[\"genre\",\"skip\"],\"name\":\"Featured\"},{\"type\":\"series\",\"id\":\"imdbRating\",\"genres\":[\"Action\",\"Adventure\",\"Animation\",\"Biography\",\"Comedy\",\"Crime\",\"Documentary\",\"Drama\",\"Family\",\"Fantasy\",\"History\",\"Horror\",\"Mystery\",\"Romance\",\"Sci-Fi\",\"Sport\",\"Thriller\",\"War\",\"Western\",\"Reality-TV\",\"Talk-Show\",\"Game-Show\"],\"extra\":[{\"name\":\"genre\",\"options\":[\"Action\",\"Adventure\",\"Animation\",\"Biography\",\"Comedy\",\"Crime\",\"Documentary\",\"Drama\",\"Family\",\"Fantasy\",\"History\",\"Horror\",\"Mystery\",\"Romance\",\"Sci-Fi\",\"Sport\",\"Thriller\",\"War\",\"Western\",\"Reality-TV\",\"Talk-Show\",\"Game-Show\"]},{\"name\":\"skip\"}],\"extraSupported\":[\"genre\",\"skip\"],\"name\":\"Featured\"},{\"type\":\"series\",\"id\":\"last-videos\",\"extra\":[{\"name\":\"lastVideosIds\",\"isRequired\":true,\"optionsLimit\":100}],\"extraSupported\":[\"lastVideosIds\"],\"extraRequired\":[\"lastVideosIds\"],\"name\":\"Last videos\"},{\"type\":\"series\",\"id\":\"calendar-videos\",\"extra\":[{\"name\":\"calendarVideosIds\",\"isRequired\":true,\"optionsLimit\":100}],\"extraSupported\":[\"calendarVideosIds\"],\"extraRequired\":[\"calendarVideosIds\"],\"name\":\"Calendar videos\"}],\"behaviorHints\":{\"newEpisodeNotifications\":true}}";
    NSData *data = [cinemetaJSON dataUsingEncoding:NSUTF8StringEncoding];
    MacLCAddon *cinemeta = [MacLCAddon addonWithTransportURL:transport manifestData:data error:nil];
    if (cinemeta) {
        return @[cinemeta];
    }
    return @[];
}

- (void)loadInstalledAddons
{
    NSArray *stored = [[NSUserDefaults standardUserDefaults] arrayForKey:MacLCAddonsDefaultsKey];
    if (!stored || ![stored isKindOfClass:[NSArray class]]) {
        _installedAddons = [self defaultAddons];
        return;
    }

    NSMutableArray<MacLCAddon *> *addons = [NSMutableArray array];
    for (id item in stored) {
        if (![item isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        NSDictionary *dict = (NSDictionary *)item;
        id transportObj = dict[@"transportUrl"];
        id manifestObj = dict[@"manifest"];
        if ([transportObj isKindOfClass:[NSString class]] && [manifestObj isKindOfClass:[NSData class]]) {
            NSError *err = nil;
            MacLCAddon *addon = [MacLCAddon addonWithTransportURL:(NSString *)transportObj
                                                     manifestData:(NSData *)manifestObj
                                                            error:&err];
            if (addon) {
                [addons addObject:addon];
            }
        }
    }
    /* Cinemeta is not removable: an empty or unreadable list must not lose it. */
    BOOL hasDefault = NO;
    for (MacLCAddon *addon in addons)
        hasDefault = hasDefault || !addon.isRemovable;
    if (!hasDefault) {
        NSArray<MacLCAddon *> * const defaults = [self defaultAddons];
        [addons insertObjects:defaults atIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, defaults.count)]];
    }
    _installedAddons = [addons copy];
}

- (void)saveInstalledAddons
{
    NSMutableArray *array = [NSMutableArray arrayWithCapacity:_installedAddons.count];
    for (MacLCAddon *addon in _installedAddons) {
        [array addObject:@{
            @"transportUrl": addon.transportURL,
            @"manifest": addon.manifestData
        }];
    }
    [[NSUserDefaults standardUserDefaults] setObject:array forKey:MacLCAddonsDefaultsKey];
    [self notifyDidChange];
}

- (void)notifyDidChange
{
    if ([NSThread isMainThread]) {
        [[NSNotificationCenter defaultCenter] postNotificationName:MacLCAddonsDidChangeNotification object:self];
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:MacLCAddonsDidChangeNotification object:self];
        });
    }
}

- (NSArray<MacLCAddon *> *)installedAddons
{
    @synchronized (self) {
        return _installedAddons ?: @[];
    }
}

- (BOOL)hasStreamAddon
{
    for (MacLCAddon *addon in self.installedAddons) {
        if (addon.providesStreams) {
            return YES;
        }
    }
    return NO;
}

- (BOOL)isInstalled:(NSString *)identifier
{
    if (identifier.length == 0) {
        return NO;
    }
    for (MacLCAddon *addon in self.installedAddons) {
        if ([addon.identifier isEqualToString:identifier]) {
            return YES;
        }
    }
    return NO;
}

- (void)installAddon:(MacLCAddon *)addon
{
    if (!addon) return;
    @synchronized (self) {
        NSMutableArray<MacLCAddon *> *list = [_installedAddons mutableCopy];
        NSUInteger existingIndex = NSNotFound;
        for (NSUInteger i = 0; i < list.count; i++) {
            if ([list[i].identifier isEqualToString:addon.identifier]) {
                existingIndex = i;
                break;
            }
        }
        if (existingIndex != NSNotFound) {
            list[existingIndex] = addon;
        } else {
            [list addObject:addon];
        }
        _installedAddons = [list copy];
        [self saveInstalledAddons];
    }
}

- (void)removeAddon:(MacLCAddon *)addon
{
    if (!addon || !addon.isRemovable) return;
    @synchronized (self) {
        NSMutableArray<MacLCAddon *> *list = [_installedAddons mutableCopy];
        NSUInteger existingIndex = NSNotFound;
        for (NSUInteger i = 0; i < list.count; i++) {
            if ([list[i].identifier isEqualToString:addon.identifier]) {
                existingIndex = i;
                break;
            }
        }
        if (existingIndex != NSNotFound) {
            [list removeObjectAtIndex:existingIndex];
            _installedAddons = [list copy];
            [self saveInstalledAddons];
        }
    }
}

- (void)resetToDefaults
{
    @synchronized (self) {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:MacLCAddonsDefaultsKey];
        _installedAddons = [self defaultAddons];
        [self notifyDidChange];
    }
}

- (void)refreshManifests
{
    NSArray<MacLCAddon *> *currentAddons = self.installedAddons;
    if (currentAddons.count == 0) return;

    dispatch_group_t group = dispatch_group_create();
    NSMutableArray<MacLCAddon *> *updatedAddons = [currentAddons mutableCopy];
    __block BOOL changed = NO;

    for (NSUInteger i = 0; i < currentAddons.count; i++) {
        MacLCAddon *addon = currentAddons[i];
        NSURL *url = URLFromStringWithPipeSupport(addon.transportURL);
        if (!url) continue;

        dispatch_group_enter(group);
        NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
        req.timeoutInterval = 20.0;
        [[NSURLSession.sharedSession dataTaskWithRequest:req completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!error && [response isKindOfClass:[NSHTTPURLResponse class]] && ((NSHTTPURLResponse *)response).statusCode == 200 && data) {
                    NSError *valError = nil;
                    MacLCAddon *newAddon = [MacLCAddon addonWithTransportURL:addon.transportURL manifestData:data error:&valError];
                    if (newAddon && [newAddon.identifier isEqualToString:addon.identifier]) {
                        if (![newAddon.manifestData isEqualToData:addon.manifestData]) {
                            updatedAddons[i] = newAddon;
                            changed = YES;
                        }
                    }
                }
                dispatch_group_leave(group);
            });
        }] resume];
    }

    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        if (!changed)
            return;
        /* Merge into the list as it is now: an add-on may have been installed
         * or removed while the manifests were on their way. */
        @synchronized (self) {
            NSMutableArray<MacLCAddon *> *list = [self->_installedAddons mutableCopy];
            BOOL merged = NO;
            for (MacLCAddon *fresh in updatedAddons) {
                for (NSUInteger i = 0; i < list.count; i++) {
                    if ([list[i].identifier isEqualToString:fresh.identifier]
                        && [list[i].transportURL isEqualToString:fresh.transportURL]
                        && ![list[i].manifestData isEqualToData:fresh.manifestData]) {
                        list[i] = fresh;
                        merged = YES;
                    }
                }
            }
            if (merged) {
                self->_installedAddons = [list copy];
                [self saveInstalledAddons];
            }
        }
    });
}

- (MacLCAddonRequest *)installFromAddress:(NSString *)address
                               completion:(void (^)(MacLCAddon * _Nullable addon, BOOL replaced, NSError * _Nullable error))completion
{
    MacLCAddonRequest *request = [[MacLCAddonRequest alloc] init];
    NSString *transportURL = [MacLCAddonStore transportURLForAddress:address];
    if (!transportURL) {
        NSError *err = [NSError errorWithDomain:MacLCAddonsErrorDomain
                                           code:MacLCAddonsErrorBadAddress
                                       userInfo:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!request.isCancelled) {
                completion(nil, NO, err);
            }
        });
        return request;
    }

    NSURL *url = URLFromStringWithPipeSupport(transportURL);
    ExecuteRequest(url, request, ^(NSData * _Nullable data, NSError * _Nullable error) {
        if (error) {
            completion(nil, NO, error);
            return;
        }

        NSError *valError = nil;
        MacLCAddon *addon = [MacLCAddon addonWithTransportURL:transportURL manifestData:data error:&valError];
        if (!addon) {
            completion(nil, NO, valError);
            return;
        }

        BOOL replaced = NO;
        @synchronized (self) {
            NSMutableArray<MacLCAddon *> *list = [self->_installedAddons mutableCopy];
            NSUInteger existingIndex = NSNotFound;
            for (NSUInteger i = 0; i < list.count; i++) {
                if ([list[i].identifier isEqualToString:addon.identifier]) {
                    existingIndex = i;
                    break;
                }
            }
            replaced = (existingIndex != NSNotFound);
            if (replaced) {
                list[existingIndex] = addon;
            } else {
                [list addObject:addon];
            }
            self->_installedAddons = [list copy];
            [self saveInstalledAddons];
        }

        completion(addon, replaced, nil);
    });

    return request;
}

- (NSArray<MacLCAddonCatalog *> *)addonCatalogs
{
    NSMutableArray<MacLCAddonCatalog *> *result = [NSMutableArray array];
    for (MacLCAddon *addon in self.installedAddons) {
        [result addObjectsFromArray:addon.addonCatalogs];
    }
    return [result copy];
}

- (MacLCAddonRequest *)fetchAddonCatalog:(MacLCAddonCatalog *)catalog
                              completion:(void (^)(NSArray<MacLCAddon *> * _Nullable addons, NSError * _Nullable error))completion
{
    MacLCAddonRequest *request = [[MacLCAddonRequest alloc] init];
    if (!catalog) {
        NSError *err = [NSError errorWithDomain:MacLCAddonsErrorDomain
                                           code:MacLCAddonsErrorBadResponse
                                       userInfo:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!request.isCancelled) {
                completion(nil, err);
            }
        });
        return request;
    }

    NSURL *url = [MacLCAddonStore URLForResource:@"addon_catalog"
                                           addon:catalog.addon
                                            type:catalog.type
                                      identifier:catalog.identifier
                                           extra:nil];

    ExecuteRequest(url, request, ^(NSData * _Nullable data, NSError * _Nullable error) {
        if (error) {
            completion(nil, error);
            return;
        }
        NSError *parseError = nil;
        NSArray<MacLCAddon *> *addons = [MacLCAddonStore addonsFromCatalogData:data error:&parseError];
        if (addons && [catalog.identifier isEqualToString:@"community"] &&
            [catalog.addon.identifier isEqualToString:@"com.linvo.cinemeta"]) {
            addons = [MacLCAddonStore communityAddons:addons forType:catalog.type];
        }
        completion(addons, parseError);
    });

    return request;
}

- (NSArray<MacLCAddonTitleCatalog *> *)titleCatalogs
{
    NSMutableArray<MacLCAddonTitleCatalog *> *result = [NSMutableArray array];
    for (MacLCAddon *addon in self.installedAddons) {
        NSArray<MacLCAddonTitleCatalog *> *cats = [MacLCAddonStore titleCatalogsOfAddon:addon];
        [result addObjectsFromArray:cats];
    }
    return [result copy];
}

- (MacLCAddonRequest *)fetchTitleCatalog:(MacLCAddonTitleCatalog *)catalog
                                   genre:(nullable NSString *)genre
                                    skip:(NSUInteger)skip
                              completion:(void (^)(NSArray<MacLCAddonItem *> * _Nullable items, NSError * _Nullable error))completion
{
    MacLCAddonRequest *request = [[MacLCAddonRequest alloc] init];
    if (!catalog) {
        NSError *err = [NSError errorWithDomain:MacLCAddonsErrorDomain
                                           code:MacLCAddonsErrorBadResponse
                                       userInfo:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!request.isCancelled) {
                completion(nil, err);
            }
        });
        return request;
    }

    NSString *extra = [MacLCAddonStore extraForTitleCatalog:catalog genre:genre skip:skip];
    NSURL *url = [MacLCAddonStore URLForResource:@"catalog"
                                           addon:catalog.addon
                                            type:catalog.type
                                      identifier:catalog.identifier
                                           extra:extra];

    ExecuteRequest(url, request, ^(NSData * _Nullable data, NSError * _Nullable error) {
        if (error) {
            completion(nil, error);
            return;
        }

        NSError *parseError = nil;
        NSArray<MacLCAddonItem *> *items = [MacLCAddonStore itemsFromCatalogData:data
                                                                           addon:catalog.addon
                                                                     defaultType:catalog.type
                                                                           error:&parseError];
        if (parseError) {
            completion(nil, parseError);
            return;
        }

        completion(items ?: @[], nil);
    });

    return request;
}

- (MacLCAddonRequest *)searchTitles:(NSString *)query
                         completion:(void (^)(NSArray<MacLCAddonSearchGroup *> *groups))completion
{
    MacLCAddonRequest *request = [[MacLCAddonRequest alloc] init];
    NSString *trimmed = [query stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!trimmed || trimmed.length < 2) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!request.isCancelled) {
                completion(@[]);
            }
        });
        return request;
    }

    NSMutableArray<MacLCAddon *> *addons = [NSMutableArray array];
    NSMutableArray<NSDictionary *> *catalogs = [NSMutableArray array];

    for (MacLCAddon *addon in self.installedAddons) {
        for (NSDictionary *cat in addon.searchableCatalogs) {
            [addons addObject:addon];
            [catalogs addObject:cat];
        }
    }

    NSUInteger count = addons.count;
    if (count == 0) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!request.isCancelled) {
                completion(@[]);
            }
        });
        return request;
    }

    NSMutableArray<MacLCAddonSearchGroup *> *groups = [NSMutableArray arrayWithCapacity:count];
    for (NSUInteger i = 0; i < count; i++) {
        [groups addObject:(id)[NSNull null]];
    }

    NSString *encodedQuery = PercentEncodeQueryComponent(trimmed);
    NSString *extra = [@"search=" stringByAppendingString:encodedQuery];
    __block NSUInteger pending = count;

    for (NSUInteger i = 0; i < count; i++) {
        MacLCAddon *addon = addons[i];
        NSDictionary *cat = catalogs[i];
        NSString *type = [cat[@"type"] isKindOfClass:[NSString class]] ? cat[@"type"] : @"";
        NSString *catId = [cat[@"id"] isKindOfClass:[NSString class]] ? cat[@"id"] : @"";
        NSString *catName = [cat[@"name"] isKindOfClass:[NSString class]] ? cat[@"name"] : catId;

        NSURL *url = [MacLCAddonStore URLForResource:@"catalog"
                                               addon:addon
                                                type:type
                                          identifier:catId
                                               extra:extra];

        ExecuteRequest(url, request, ^(NSData * _Nullable data, NSError * _Nullable error) {
            MacLCAddonSearchGroup *group = nil;
            if (error) {
                group = [[MacLCAddonSearchGroup alloc] initWithAddon:addon
                                                                type:type
                                                         catalogName:catName
                                                               items:@[]
                                                               error:error];
            } else {
                NSError *parseError = nil;
                NSArray<MacLCAddonItem *> *items = [MacLCAddonStore itemsFromCatalogData:data
                                                                                   addon:addon
                                                                             defaultType:type
                                                                                   error:&parseError];
                group = [[MacLCAddonSearchGroup alloc] initWithAddon:addon
                                                                type:type
                                                         catalogName:catName
                                                               items:items ?: @[]
                                                               error:parseError];
            }
            groups[i] = group;
            pending--;
            if (pending == 0) {
                completion([groups copy]);
            }
        });
    }

    return request;
}

- (MacLCAddonRequest *)fetchMetaForItem:(MacLCAddonItem *)item
                             completion:(void (^)(MacLCAddonMeta * _Nullable meta, NSError * _Nullable error))completion
{
    MacLCAddonRequest *request = [[MacLCAddonRequest alloc] init];
    if (!item) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!request.isCancelled) {
                completion(nil, nil);
            }
        });
        return request;
    }

    MacLCAddon *selectedAddon = nil;
    if (item.addon && [item.addon providesResource:@"meta" forType:item.type identifier:item.identifier]) {
        selectedAddon = item.addon;
    } else {
        for (MacLCAddon *addon in self.installedAddons) {
            if ([addon providesResource:@"meta" forType:item.type identifier:item.identifier]) {
                selectedAddon = addon;
                break;
            }
        }
    }

    if (!selectedAddon) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!request.isCancelled) {
                completion(nil, nil);
            }
        });
        return request;
    }

    NSURL *url = [MacLCAddonStore URLForResource:@"meta"
                                           addon:selectedAddon
                                            type:item.type
                                      identifier:item.identifier
                                           extra:nil];

    ExecuteRequest(url, request, ^(NSData * _Nullable data, NSError * _Nullable error) {
        if (error) {
            completion(nil, error);
            return;
        }
        NSError *parseError = nil;
        MacLCAddonMeta *meta = [MacLCAddonStore metaFromData:data itemIdentifier:item.identifier error:&parseError];
        completion(meta, parseError);
    });

    return request;
}

- (MacLCAddonRequest *)fetchStreamsForType:(NSString *)type
                            videoIdentifier:(NSString *)identifier
                                  eachGroup:(void (^)(MacLCAddonStreamGroup *group))eachGroup
                                 completion:(void (^)(void))completion
{
    MacLCAddonRequest *request = [[MacLCAddonRequest alloc] init];
    if (type.length == 0 || identifier.length == 0) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!request.isCancelled) {
                completion();
            }
        });
        return request;
    }

    NSMutableArray<MacLCAddon *> *addons = [NSMutableArray array];
    for (MacLCAddon *addon in self.installedAddons) {
        if ([addon providesResource:@"stream" forType:type identifier:identifier]) {
            [addons addObject:addon];
        }
    }

    if (addons.count == 0) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!request.isCancelled) {
                completion();
            }
        });
        return request;
    }

    __block NSUInteger pending = addons.count;

    for (MacLCAddon *addon in addons) {
        NSURL *url = [MacLCAddonStore URLForResource:@"stream"
                                               addon:addon
                                                type:type
                                          identifier:identifier
                                               extra:nil];

        ExecuteRequest(url, request, ^(NSData * _Nullable data, NSError * _Nullable error) {
            MacLCAddonStreamGroup *group = nil;
            if (error) {
                group = [[MacLCAddonStreamGroup alloc] initWithAddon:addon streams:@[] error:error];
            } else {
                NSError *parseError = nil;
                NSArray<MacLCAddonStream *> *streams = [MacLCAddonStore streamsFromData:data addon:addon error:&parseError];
                group = [[MacLCAddonStreamGroup alloc] initWithAddon:addon streams:streams ?: @[] error:parseError];
            }
            eachGroup(group);

            pending--;
            if (pending == 0) {
                completion();
            }
        });
    }

    return request;
}

#pragma mark - Pure Functions

+ (nullable NSString *)transportURLForAddress:(NSString *)address
{
    if (!address) {
        return nil;
    }
    NSString *trimmed = [address stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) {
        return nil;
    }
    if ([trimmed hasPrefix:@"stremio://"]) {
        trimmed = [@"https://" stringByAppendingString:[trimmed substringFromIndex:10]];
    }
    while ([trimmed hasSuffix:@"/"]) {
        trimmed = [trimmed substringToIndex:trimmed.length - 1];
    }
    if ([trimmed hasSuffix:@"/configure"]) {
        trimmed = [[trimmed substringToIndex:trimmed.length - 10] stringByAppendingString:@"/manifest.json"];
    } else if (![trimmed hasSuffix:@"manifest.json"]) {
        trimmed = [trimmed stringByAppendingString:@"/manifest.json"];
    }

    NSURL *url = URLFromStringWithPipeSupport(trimmed);
    if (!url) {
        return nil;
    }
    NSString *scheme = url.scheme.lowercaseString;
    if (![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"]) {
        return nil;
    }
    if (url.host.length == 0) {
        return nil;
    }
    return trimmed;
}

+ (NSURL *)URLForResource:(NSString *)resource
                    addon:(MacLCAddon *)addon
                     type:(NSString *)type
               identifier:(NSString *)identifier
                    extra:(nullable NSString *)extra
{
    NSString *base = addon.baseURL.absoluteString;
    while ([base hasSuffix:@"/"]) {
        base = [base substringToIndex:base.length - 1];
    }
    NSString *encType = PercentEncodePathSegment(type);
    NSString *encId = PercentEncodePathSegment(identifier);
    NSString *urlString = nil;
    if (extra && extra.length > 0) {
        urlString = [NSString stringWithFormat:@"%@/%@/%@/%@/%@.json",
                     base, resource, encType, encId, extra];
    } else {
        urlString = [NSString stringWithFormat:@"%@/%@/%@/%@.json",
                     base, resource, encType, encId];
    }
    return URLFromStringWithPipeSupport(urlString) ?: [NSURL URLWithString:@"about:blank"];
}

+ (nullable NSArray<MacLCAddonItem *> *)itemsFromCatalogData:(NSData *)data
                                                       addon:(MacLCAddon *)addon
                                                       error:(NSError **)error
{
    return [self itemsFromCatalogData:data addon:addon defaultType:@"" error:error];
}

+ (nullable NSArray<MacLCAddonItem *> *)itemsFromCatalogData:(NSData *)data
                                                       addon:(MacLCAddon *)addon
                                                 defaultType:(NSString *)defaultType
                                                       error:(NSError **)error
{
    if (!data) {
        if (error) {
            *error = [NSError errorWithDomain:MacLCAddonsErrorDomain
                                         code:MacLCAddonsErrorBadResponse
                                     userInfo:nil];
        }
        return nil;
    }

    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![json isKindOfClass:[NSDictionary class]]) {
        if (error) {
            *error = [NSError errorWithDomain:MacLCAddonsErrorDomain
                                         code:MacLCAddonsErrorBadResponse
                                     userInfo:nil];
        }
        return nil;
    }

    id metasObj = json[@"metas"];
    if (![metasObj isKindOfClass:[NSArray class]]) {
        if (error) {
            *error = [NSError errorWithDomain:MacLCAddonsErrorDomain
                                         code:MacLCAddonsErrorBadResponse
                                     userInfo:nil];
        }
        return nil;
    }

    NSMutableArray<MacLCAddonItem *> *results = [NSMutableArray array];
    for (id item in (NSArray *)metasObj) {
        if (![item isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        NSDictionary *dict = (NSDictionary *)item;
        id identifier = dict[@"id"];
        id name = dict[@"name"];
        if (![identifier isKindOfClass:[NSString class]] || [(NSString *)identifier length] == 0) {
            continue;
        }
        if (![name isKindOfClass:[NSString class]] || [(NSString *)name length] == 0) {
            continue;
        }

        NSString *itemType = nil;
        id typeObj = dict[@"type"];
        if ([typeObj isKindOfClass:[NSString class]] && [(NSString *)typeObj length] > 0) {
            itemType = (NSString *)typeObj;
        } else {
            itemType = defaultType ?: @"";
        }

        NSString *releaseInfo = nil;
        id rel = dict[@"releaseInfo"];
        if ([rel isKindOfClass:[NSString class]] && [(NSString *)rel length] > 0) {
            releaseInfo = rel;
        } else {
            id yr = dict[@"year"];
            if ([yr isKindOfClass:[NSString class]] && [(NSString *)yr length] > 0) {
                releaseInfo = (NSString *)yr;
            } else if ([yr isKindOfClass:[NSNumber class]]) {
                releaseInfo = [(NSNumber *)yr stringValue];
            }
        }

        NSURL *posterURL = ParseURL(dict[@"poster"]);
        NSString *itemDescription = ParseString(dict[@"description"]);
        NSURL *backgroundURL = ParseURL(dict[@"background"]);
        NSURL *logoURL = ParseURL(dict[@"logo"]);
        NSArray<NSString *> *genres = ParseGenres(dict);
        NSString *imdbRating = ParseRating(dict[@"imdbRating"]);
        NSString *runtime = ParseString(dict[@"runtime"]);
        if (!runtime && [dict[@"runtime"] isKindOfClass:[NSNumber class]]) {
            runtime = [(NSNumber *)dict[@"runtime"] stringValue];
        }

        MacLCAddonItem *addonItem = [[MacLCAddonItem alloc] initWithAddon:addon
                                                               identifier:identifier
                                                                     type:itemType
                                                                     name:name
                                                              releaseInfo:releaseInfo
                                                                posterURL:posterURL
                                                          itemDescription:itemDescription
                                                            backgroundURL:backgroundURL
                                                                  logoURL:logoURL
                                                                   genres:genres
                                                               imdbRating:imdbRating
                                                                  runtime:runtime];
        addonItem.rawMeta = dict;
        [results addObject:addonItem];
    }

    return results;
}

+ (nullable MacLCAddonMeta *)metaFromData:(NSData *)data itemIdentifier:(NSString *)identifier error:(NSError **)error
{
    if (!data) {
        if (error) {
            *error = [NSError errorWithDomain:MacLCAddonsErrorDomain
                                         code:MacLCAddonsErrorBadResponse
                                     userInfo:nil];
        }
        return nil;
    }

    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![json isKindOfClass:[NSDictionary class]]) {
        if (error) {
            *error = [NSError errorWithDomain:MacLCAddonsErrorDomain
                                         code:MacLCAddonsErrorBadResponse
                                     userInfo:nil];
        }
        return nil;
    }

    id metaObj = json[@"meta"];
    if (![metaObj isKindOfClass:[NSDictionary class]]) {
        if (error) {
            *error = [NSError errorWithDomain:MacLCAddonsErrorDomain
                                         code:MacLCAddonsErrorBadResponse
                                     userInfo:nil];
        }
        return nil;
    }

    NSDictionary *metaDict = (NSDictionary *)metaObj;

    NSString *defaultVideoId = identifier ?: @"";
    id hints = metaDict[@"behaviorHints"];
    if ([hints isKindOfClass:[NSDictionary class]]) {
        id hintId = hints[@"defaultVideoId"];
        if ([hintId isKindOfClass:[NSString class]] && [(NSString *)hintId length] > 0) {
            defaultVideoId = (NSString *)hintId;
        }
    }

    id videosObj = metaDict[@"videos"];
    NSMutableArray<MacLCAddonVideo *> *videos = [NSMutableArray array];
    if ([videosObj isKindOfClass:[NSArray class]]) {
        for (id v in (NSArray *)videosObj) {
            if (![v isKindOfClass:[NSDictionary class]]) {
                continue;
            }
            NSDictionary *vDict = (NSDictionary *)v;
            id vidId = vDict[@"id"];
            if (![vidId isKindOfClass:[NSString class]] || [(NSString *)vidId length] == 0) {
                continue;
            }

            NSInteger season = 0;
            id sObj = vDict[@"season"];
            if (sObj != nil && ([sObj isKindOfClass:[NSNumber class]] || [sObj isKindOfClass:[NSString class]])) {
                season = [sObj integerValue];
            }

            NSInteger episode = 0;
            id epObj = vDict[@"episode"];
            if (epObj != nil && ([epObj isKindOfClass:[NSNumber class]] || [epObj isKindOfClass:[NSString class]])) {
                episode = [epObj integerValue];
            } else {
                id numObj = vDict[@"number"];
                if (numObj != nil && ([numObj isKindOfClass:[NSNumber class]] || [numObj isKindOfClass:[NSString class]])) {
                    episode = [numObj integerValue];
                }
            }

            NSString *name = nil;
            id nameObj = vDict[@"name"];
            if ([nameObj isKindOfClass:[NSString class]] && [(NSString *)nameObj length] > 0) {
                name = nameObj;
            } else {
                id titleObj = vDict[@"title"];
                if ([titleObj isKindOfClass:[NSString class]] && [(NSString *)titleObj length] > 0) {
                    name = titleObj;
                }
            }

            NSDate *released = nil;
            id relObj = vDict[@"released"];
            if ([relObj isKindOfClass:[NSString class]] && [(NSString *)relObj length] > 0) {
                released = ParseDate(relObj);
            }

            NSURL *thumbnailURL = ParseURL(vDict[@"thumbnail"]);
            NSString *overview = ParseString(vDict[@"overview"]);
            if (!overview) {
                overview = ParseString(vDict[@"description"]);
            }

            MacLCAddonVideo *video = [[MacLCAddonVideo alloc] initWithIdentifier:vidId
                                                                          season:season
                                                                         episode:episode
                                                                            name:name
                                                                        released:released
                                                                    thumbnailURL:thumbnailURL
                                                                        overview:overview];
            [videos addObject:video];
        }

        [videos sortWithOptions:NSSortStable usingComparator:^NSComparisonResult(MacLCAddonVideo *v1, MacLCAddonVideo *v2) {
            if (v1.season < v2.season) return NSOrderedAscending;
            if (v1.season > v2.season) return NSOrderedDescending;
            if (v1.episode < v2.episode) return NSOrderedAscending;
            if (v1.episode > v2.episode) return NSOrderedDescending;
            return NSOrderedSame;
        }];
    }

    NSString *metaName = ParseString(metaDict[@"name"]);
    NSString *itemDescription = ParseString(metaDict[@"description"]);
    NSString *releaseInfo = nil;
    id rel = metaDict[@"releaseInfo"];
    if ([rel isKindOfClass:[NSString class]] && [(NSString *)rel length] > 0) {
        releaseInfo = (NSString *)rel;
    } else {
        id yr = metaDict[@"year"];
        if ([yr isKindOfClass:[NSString class]] && [(NSString *)yr length] > 0) {
            releaseInfo = (NSString *)yr;
        } else if ([yr isKindOfClass:[NSNumber class]]) {
            releaseInfo = [(NSNumber *)yr stringValue];
        }
    }
    NSURL *posterURL = ParseURL(metaDict[@"poster"]);
    NSURL *backgroundURL = ParseURL(metaDict[@"background"]);
    NSURL *logoURL = ParseURL(metaDict[@"logo"]);
    NSArray<NSString *> *genres = ParseGenres(metaDict);
    NSString *imdbRating = ParseRating(metaDict[@"imdbRating"]);
    NSString *runtime = ParseString(metaDict[@"runtime"]);
    if (!runtime && [metaDict[@"runtime"] isKindOfClass:[NSNumber class]]) {
        runtime = [(NSNumber *)metaDict[@"runtime"] stringValue];
    }
    NSArray<NSString *> *cast = ParseCast(metaDict);
    NSArray<NSString *> *directors = ParseDirectors(metaDict);
    NSString *trailerYT = ParseTrailer(metaDict);

    MacLCAddonMeta *result = [[MacLCAddonMeta alloc] initWithVideos:videos
                                             defaultVideoIdentifier:defaultVideoId
                                                               name:metaName
                                                    itemDescription:itemDescription
                                                        releaseInfo:releaseInfo
                                                          posterURL:posterURL
                                                      backgroundURL:backgroundURL
                                                            logoURL:logoURL
                                                             genres:genres
                                                         imdbRating:imdbRating
                                                            runtime:runtime
                                                               cast:cast
                                                          directors:directors
                                           trailerYouTubeIdentifier:trailerYT];
    return result;
}

+ (NSArray<MacLCAddonTitleCatalog *> *)titleCatalogsOfAddon:(MacLCAddon *)addon
{
    if (!addon) {
        return @[];
    }

    NSMutableArray<MacLCAddonTitleCatalog *> *result = [NSMutableArray array];
    for (id item in addon.catalogs) {
        if (![item isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        NSDictionary *catDict = (NSDictionary *)item;
        id typeObj = catDict[@"type"];
        id idObj = catDict[@"id"];
        if (![typeObj isKindOfClass:[NSString class]] || [(NSString *)typeObj length] == 0) {
            continue;
        }
        if (![idObj isKindOfClass:[NSString class]] || [(NSString *)idObj length] == 0) {
            continue;
        }
        NSString *type = (NSString *)typeObj;
        NSString *catId = (NSString *)idObj;

        NSString *name = catId;
        id nameObj = catDict[@"name"];
        if ([nameObj isKindOfClass:[NSString class]] && [(NSString *)nameObj length] > 0) {
            name = (NSString *)nameObj;
        }

        BOOL requiresExtraOtherThanGenre = NO;
        BOOL requiresGenre = NO;
        id extraReq = catDict[@"extraRequired"];
        if ([extraReq isKindOfClass:[NSArray class]]) {
            for (id req in (NSArray *)extraReq) {
                if ([req isKindOfClass:[NSString class]]) {
                    if ([req isEqualToString:@"genre"]) {
                        requiresGenre = YES;
                    } else {
                        requiresExtraOtherThanGenre = YES;
                    }
                }
            }
        }

        BOOL supportsSkip = NO;
        NSMutableArray<NSString *> *genreOptions = [NSMutableArray array];
        id extraArr = catDict[@"extra"];
        if ([extraArr isKindOfClass:[NSArray class]]) {
            for (id extraItem in (NSArray *)extraArr) {
                if ([extraItem isKindOfClass:[NSString class]]) {
                    NSString *extraName = (NSString *)extraItem;
                    if ([extraName isEqualToString:@"skip"]) {
                        supportsSkip = YES;
                    }
                } else if ([extraItem isKindOfClass:[NSDictionary class]]) {
                    NSDictionary *eDict = (NSDictionary *)extraItem;
                    id extraNameObj = eDict[@"name"];
                    if (![extraNameObj isKindOfClass:[NSString class]]) {
                        continue;
                    }
                    NSString *extraName = (NSString *)extraNameObj;
                    BOOL isReq = NO;
                    id reqVal = eDict[@"isRequired"];
                    if ([reqVal isKindOfClass:[NSNumber class]] && [reqVal boolValue]) {
                        isReq = YES;
                    }

                    if ([extraName isEqualToString:@"genre"]) {
                        if (isReq) {
                            requiresGenre = YES;
                        }
                        id opts = eDict[@"options"];
                        if ([opts isKindOfClass:[NSArray class]]) {
                            for (id opt in (NSArray *)opts) {
                                if ([opt isKindOfClass:[NSString class]] && [(NSString *)opt length] > 0) {
                                    [genreOptions addObject:(NSString *)opt];
                                }
                            }
                        }
                    } else {
                        if (isReq) {
                            requiresExtraOtherThanGenre = YES;
                        }
                        if ([extraName isEqualToString:@"skip"]) {
                            supportsSkip = YES;
                        }
                    }
                }
            }
        }

        id extraSupp = catDict[@"extraSupported"];
        if ([extraSupp isKindOfClass:[NSArray class]]) {
            for (id s in (NSArray *)extraSupp) {
                if ([s isKindOfClass:[NSString class]] && [s isEqualToString:@"skip"]) {
                    supportsSkip = YES;
                }
            }
        }

        if (requiresExtraOtherThanGenre) {
            continue;
        }

        if (genreOptions.count == 0) {
            id catGenres = catDict[@"genres"];
            if ([catGenres isKindOfClass:[NSArray class]]) {
                for (id g in (NSArray *)catGenres) {
                    if ([g isKindOfClass:[NSString class]] && [(NSString *)g length] > 0) {
                        [genreOptions addObject:(NSString *)g];
                    }
                }
            }
        }

        if (genreOptions.count == 0 && addon.manifestGenres.count > 0) {
            [genreOptions addObjectsFromArray:addon.manifestGenres];
        }

        if (requiresGenre && genreOptions.count == 0) {
            continue;
        }

        MacLCAddonTitleCatalog *titleCat = [[MacLCAddonTitleCatalog alloc] initWithAddon:addon
                                                                                   type:type
                                                                             identifier:catId
                                                                                   name:name
                                                                                 genres:genreOptions
                                                                          requiresGenre:requiresGenre
                                                                           supportsSkip:supportsSkip];
        [result addObject:titleCat];
    }

    return [result copy];
}

+ (nullable NSString *)extraForTitleCatalog:(MacLCAddonTitleCatalog *)catalog
                                      genre:(nullable NSString *)genre
                                       skip:(NSUInteger)skip
{
    if (!catalog) {
        return nil;
    }

    NSString *effectiveGenre = nil;
    if (genre != nil && genre.length > 0) {
        effectiveGenre = genre;
    } else if (catalog.requiresGenre && catalog.genres.count > 0) {
        effectiveGenre = catalog.genres[0];
    }

    NSString *genrePart = nil;
    if (effectiveGenre != nil && effectiveGenre.length > 0) {
        NSString *encodedGenre = PercentEncodeQueryComponent(effectiveGenre);
        genrePart = [NSString stringWithFormat:@"genre=%@", encodedGenre];
    }

    NSString *skipPart = nil;
    if (skip > 0 && catalog.supportsSkip) {
        skipPart = [NSString stringWithFormat:@"skip=%lu", (unsigned long)skip];
    }

    if (genrePart && skipPart) {
        return [NSString stringWithFormat:@"%@&%@", genrePart, skipPart];
    } else if (genrePart) {
        return genrePart;
    } else if (skipPart) {
        return skipPart;
    } else {
        return nil;
    }
}

+ (nullable NSArray<MacLCAddonStream *> *)streamsFromData:(NSData *)data addon:(MacLCAddon *)addon error:(NSError **)error
{
    if (!data) {
        if (error) {
            *error = [NSError errorWithDomain:MacLCAddonsErrorDomain
                                         code:MacLCAddonsErrorBadResponse
                                     userInfo:nil];
        }
        return nil;
    }

    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![json isKindOfClass:[NSDictionary class]]) {
        if (error) {
            *error = [NSError errorWithDomain:MacLCAddonsErrorDomain
                                         code:MacLCAddonsErrorBadResponse
                                     userInfo:nil];
        }
        return nil;
    }

    id streamsObj = json[@"streams"];
    if (![streamsObj isKindOfClass:[NSArray class]]) {
        if (error) {
            *error = [NSError errorWithDomain:MacLCAddonsErrorDomain
                                         code:MacLCAddonsErrorBadResponse
                                     userInfo:nil];
        }
        return nil;
    }

    NSMutableArray<MacLCAddonStream *> *results = [NSMutableArray array];
    for (id item in (NSArray *)streamsObj) {
        if (![item isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        NSDictionary *dict = (NSDictionary *)item;

        NSString *nameStr = [dict[@"name"] isKindOfClass:[NSString class]] ? dict[@"name"] : @"";
        NSArray<NSString *> *nameLines = CleanLines(nameStr);

        NSString *label = nil;
        if (nameLines.count > 0) {
            label = nameLines[0];
        } else {
            label = addon.name ?: @"";
        }

        NSArray<NSString *> *qualityTokens = @[];
        if (nameLines.count > 1) {
            qualityTokens = TokenizeQuality([nameLines subarrayWithRange:NSMakeRange(1, nameLines.count - 1)]);
        } else if (nameLines.count == 1) {
            if ([nameLines[0] caseInsensitiveCompare:(addon.name ?: @"")] != NSOrderedSame) {
                qualityTokens = TokenizeQuality(@[nameLines[0]]);
            }
        }

        NSString *textStr = nil;
        id tObj = dict[@"title"];
        if ([tObj isKindOfClass:[NSString class]] && [(NSString *)tObj length] > 0) {
            textStr = (NSString *)tObj;
        } else {
            id dObj = dict[@"description"];
            if ([dObj isKindOfClass:[NSString class]] && [(NSString *)dObj length] > 0) {
                textStr = (NSString *)dObj;
            }
        }
        NSArray<NSString *> *textLines = CleanLines(textStr);

        NSString *filename = nil;
        id hints = dict[@"behaviorHints"];
        if ([hints isKindOfClass:[NSDictionary class]]) {
            id fn = hints[@"filename"];
            if ([fn isKindOfClass:[NSString class]] && [(NSString *)fn length] > 0) {
                filename = (NSString *)fn;
            }
        }

        NSString *headline = nil;
        if (textLines.count > 0) {
            headline = textLines[0];
        } else if (filename.length > 0) {
            headline = filename;
        } else {
            headline = label;
        }

        NSString *details = nil;
        if (textLines.count > 1) {
            NSArray<NSString *> *rest = [textLines subarrayWithRange:NSMakeRange(1, textLines.count - 1)];
            details = [rest componentsJoinedByString:@" · "];
        }

        NSMutableArray<NSString *> *trackers = [NSMutableArray array];
        NSMutableSet<NSString *> *seenTrackers = [NSMutableSet set];
        id sourcesObj = dict[@"sources"];
        if ([sourcesObj isKindOfClass:[NSArray class]]) {
            for (id s in (NSArray *)sourcesObj) {
                if (![s isKindOfClass:[NSString class]]) {
                    continue;
                }
                NSString *src = (NSString *)s;
                if ([src hasPrefix:@"tracker:"]) {
                    NSString *tr = [src substringFromIndex:8];
                    if (tr.length > 0 && ![seenTrackers containsObject:tr]) {
                        [seenTrackers addObject:tr];
                        [trackers addObject:tr];
                        if (trackers.count == 20) {
                            break;
                        }
                    }
                }
            }
        }

        NSURL *directURL = nil;
        NSString *infoHash = nil;
        NSString *youTubeIdentifier = nil;
        NSString *MRL = nil;

        id urlObj = dict[@"url"];
        if ([urlObj isKindOfClass:[NSString class]] && [(NSString *)urlObj length] > 0) {
            NSString *urlStr = (NSString *)urlObj;
            if (![urlStr.lowercaseString hasPrefix:@"javascript:"]) {
                directURL = [NSURL URLWithString:urlStr];
                MRL = urlStr;
            }
        }

        if (!MRL) {
            id hashObj = dict[@"infoHash"];
            if ([hashObj isKindOfClass:[NSString class]] && [(NSString *)hashObj length] > 0) {
                infoHash = (NSString *)hashObj;
                NSMutableString *magnet = [NSMutableString stringWithFormat:@"magnet:?xt=urn:btih:%@&dn=%@",
                                           infoHash, PercentEncodeQueryComponent(headline)];
                NSArray<NSString *> *effectiveTrackers = trackers.count > 0 ? trackers : DefaultTrackers();
                for (NSString *tr in effectiveTrackers) {
                    [magnet appendFormat:@"&tr=%@", PercentEncodeQueryComponent(tr)];
                }
                // ponytail: a basename that is not unique in the torrent makes the extractor fail ("no file … in torrent"); fileIdx is the upgrade path if it ever matters.
                if (filename.length > 0) {
                    [magnet appendFormat:@"#!/%@", EscapeMRLFragment(filename)];
                }
                MRL = [magnet copy];
            }
        }

        if (!MRL) {
            id ytObj = dict[@"ytId"];
            if ([ytObj isKindOfClass:[NSString class]] && [(NSString *)ytObj length] > 0) {
                youTubeIdentifier = (NSString *)ytObj;
                MRL = [NSString stringWithFormat:@"https://www.youtube.com/watch?v=%@", youTubeIdentifier];
            }
        }

        if (!MRL) {
            continue;
        }

        MacLCAddonStream *stream = [[MacLCAddonStream alloc] initWithAddon:addon
                                                                     label:label
                                                             qualityTokens:qualityTokens
                                                                  headline:headline
                                                                   details:details
                                                                  infoHash:infoHash
                                                                  filename:filename
                                                                  trackers:trackers
                                                                 directURL:directURL
                                                         youTubeIdentifier:youTubeIdentifier
                                                                       MRL:MRL];
        [results addObject:stream];
    }

    return results;
}

+ (nullable NSArray<MacLCAddon *> *)addonsFromCatalogData:(NSData *)data error:(NSError **)error
{
    if (!data) {
        if (error) {
            *error = [NSError errorWithDomain:MacLCAddonsErrorDomain
                                         code:MacLCAddonsErrorBadResponse
                                     userInfo:nil];
        }
        return nil;
    }

    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![json isKindOfClass:[NSDictionary class]]) {
        if (error) {
            *error = [NSError errorWithDomain:MacLCAddonsErrorDomain
                                         code:MacLCAddonsErrorBadResponse
                                     userInfo:nil];
        }
        return nil;
    }

    id addonsObj = json[@"addons"];
    if (![addonsObj isKindOfClass:[NSArray class]]) {
        if (error) {
            *error = [NSError errorWithDomain:MacLCAddonsErrorDomain
                                         code:MacLCAddonsErrorBadResponse
                                     userInfo:nil];
        }
        return nil;
    }

    NSMutableArray<MacLCAddon *> *result = [NSMutableArray array];
    NSMutableSet<NSString *> *seenIds = [NSMutableSet set];

    for (id item in (NSArray *)addonsObj) {
        if (![item isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        NSDictionary *dict = (NSDictionary *)item;
        id transportObj = dict[@"transportUrl"];
        if (![transportObj isKindOfClass:[NSString class]]) {
            continue;
        }
        NSString *transportUrl = (NSString *)transportObj;
        if (![transportUrl hasSuffix:@"manifest.json"]) {
            continue;
        }
        NSURL *url = URLFromStringWithPipeSupport(transportUrl);
        if (!url) {
            continue;
        }
        NSString *scheme = url.scheme.lowercaseString;
        if (![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"]) {
            continue;
        }
        NSString *host = url.host.lowercaseString;
        if (!host || [host isEqualToString:@"localhost"] || [host isEqualToString:@"127.0.0.1"] || [host isEqualToString:@"::1"]) {
            continue;
        }

        id manifestObj = dict[@"manifest"];
        if (![manifestObj isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        NSData *manifestData = [NSJSONSerialization dataWithJSONObject:manifestObj options:0 error:nil];
        if (!manifestData) {
            continue;
        }

        NSError *valError = nil;
        MacLCAddon *addon = [MacLCAddon addonWithTransportURL:transportUrl manifestData:manifestData error:&valError];
        if (!addon) {
            continue;
        }

        if (![addon.resourceNames containsObject:@"catalog"] &&
            ![addon.resourceNames containsObject:@"meta"] &&
            ![addon.resourceNames containsObject:@"stream"]) {
            continue;
        }

        if ([seenIds containsObject:addon.identifier]) {
            continue;
        }
        [seenIds addObject:addon.identifier];
        [result addObject:addon];
    }

    return result;
}

+ (NSArray<MacLCAddon *> *)communityAddons:(NSArray<MacLCAddon *> *)addons forType:(NSString *)type
{
    /* Torrentio 0.0.15 as served on 2026-10-07; refreshManifests keeps an
     * installed copy current. */
    NSString *torrentio = @"{\"id\":\"com.stremio.torrentio.addon\",\"version\":\"0.0.15\",\"name\":\"Torrentio\",\"description\":\"Provides torrent streams from scraped torrent providers. Currently supports YTS(+), EZTV(+), RARBG(+), 1337x(+), EXT(+), ThePirateBay(+), KickassTorrents(+), TorrentGalaxy(+), MagnetDL(+), HorribleSubs(+), NyaaSi(+), TokyoTosho(+), AniDex(+), nekoBT(+), Rutor(+), Rutracker(+), Comando(+), BluDV(+), MicoLeaoDublado(+), Torrent9(+), ilCorSaRoNeRo(+), MejorTorrent(+), Wolfmax4k(+), Cinecalidad(+), BestTorrents(+). To configure providers, RealDebrid/Premiumize/AllDebrid/DebridLink/EasyDebrid/Offcloud/TorBox/Put.io/HighWay support and other settings visit https://torrentio.strem.fun\",\"catalogs\":[],\"resources\":[{\"name\":\"stream\",\"types\":[\"movie\",\"series\",\"anime\"],\"idPrefixes\":[\"tt\",\"kitsu\"]}],\"types\":[\"movie\",\"series\",\"anime\",\"other\"],\"background\":\"https://torrentio.strem.fun/images/background_v1.jpg\",\"logo\":\"https://torrentio.strem.fun/images/logo_v1.png\",\"behaviorHints\":{\"configurable\":true,\"configurationRequired\":false}}";
    MacLCAddon *extra = [MacLCAddon addonWithTransportURL:@"https://torrentio.strem.fun/manifest.json"
                                             manifestData:[torrentio dataUsingEncoding:NSUTF8StringEncoding]
                                                    error:nil];
    if (!extra || !([type isEqualToString:@"all"] || [extra.types containsObject:type])) {
        return addons;
    }
    for (MacLCAddon *addon in addons) {
        if ([addon.identifier isEqualToString:extra.identifier]) {
            return addons;
        }
    }
    return [@[extra] arrayByAddingObjectsFromArray:addons];
}

+ (NSString *)itemNameForItem:(MacLCAddonItem *)item video:(nullable MacLCAddonVideo *)video
{
    if (!item) {
        return @"";
    }
    NSString *name = item.name ?: @"";
    if (!video) {
        if (item.releaseInfo.length > 0) {
            return [NSString stringWithFormat:@"%@ (%@)", name, item.releaseInfo];
        }
        return name;
    }

    if (video.season > 0 || video.episode > 0) {
        if (video.name.length > 0) {
            return [NSString stringWithFormat:@"%@ — S%ldE%ld · %@",
                    name, (long)video.season, (long)video.episode, video.name];
        }
        return [NSString stringWithFormat:@"%@ — S%ldE%ld",
                name, (long)video.season, (long)video.episode];
    }

    if (video.name.length > 0) {
        return [NSString stringWithFormat:@"%@ — %@", name, video.name];
    }
    return name;
}

@end
