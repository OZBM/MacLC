/*****************************************************************************
 * MacLCStreamFacts.m: what a stream offered by an add-on really is
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

#import "addons/MacLCStreamFacts.h"
#import "addons/MacLCAddons.h"

#pragma mark - MacLCStreamAudio Implementation

@implementation MacLCStreamAudio

- (instancetype)initWithFormat:(NSString *)format channels:(nullable NSString *)channels
{
    self = [super init];
    if (self) {
        _format = [format copy] ?: @"";
        _channels = [channels copy];
    }
    return self;
}

- (BOOL)isLossless
{
    /* Atmos, TrueHD, DTS:X, DTS-HD MA, FLAC, PCM */
    if ([_format isEqualToString:@"Dolby Atmos"] ||
        [_format isEqualToString:@"Dolby TrueHD"] ||
        [_format isEqualToString:@"DTS:X"] ||
        [_format isEqualToString:@"DTS-HD MA"] ||
        [_format isEqualToString:@"FLAC"] ||
        [_format isEqualToString:@"PCM"]) {
        return YES;
    }
    return NO;
}

- (BOOL)isImmersive
{
    /* Atmos, DTS:X */
    if ([_format isEqualToString:@"Dolby Atmos"] ||
        [_format isEqualToString:@"DTS:X"]) {
        return YES;
    }
    return NO;
}

- (BOOL)isEqual:(id)object
{
    if (self == object) return YES;
    if (![object isKindOfClass:[MacLCStreamAudio class]]) return NO;
    MacLCStreamAudio *other = (MacLCStreamAudio *)object;
    if (![_format isEqualToString:other.format]) return NO;
    if (_channels == nil && other.channels == nil) return YES;
    return [_channels isEqualToString:other.channels];
}

- (NSUInteger)hash
{
    return _format.hash ^ _channels.hash;
}

- (NSString *)description
{
    if (_channels.length > 0) {
        return [NSString stringWithFormat:@"%@ %@", _format, _channels];
    }
    return _format;
}

@end

#pragma mark - MacLCStreamFacts Private Interface & Parsing Helpers

@interface MacLCStreamFacts ()

@property (nonatomic) MacLCStreamResolution resolution;
@property (nonatomic) MacLCStreamDynamicRange dynamicRange;
@property (nonatomic, copy) NSArray<NSString *> *hdrFormats;
@property (nonatomic) BOOL tenBit;
@property (nonatomic) MacLCStreamVideoCodec videoCodec;
@property (nonatomic) MacLCStreamSource source;
@property (nonatomic, copy) NSArray<MacLCStreamAudio *> *audio;
@property (nonatomic, copy) NSArray<NSString *> *languages;
@property (nonatomic, getter=isMultiLanguage) BOOL multiLanguage;
@property (nonatomic, copy) NSArray<NSString *> *subtitleLanguages;
@property (nonatomic) BOOL hasMultipleSubtitles;
@property (nonatomic) unsigned long long sizeBytes;
@property (nonatomic) NSInteger seeders;
@property (nonatomic, copy, nullable) NSString *provider;
@property (nonatomic, copy, nullable) NSString *debridService;
@property (nonatomic, getter=isTorrent) BOOL torrent;
@property (nonatomic, copy) NSString *releaseName;
@property (nonatomic, getter=isPack) BOOL pack;
@property (nonatomic, copy) NSArray<NSString *> *editionNotes;
@property (nonatomic) MacLCStreamHealth health;
@property (nonatomic) MacLCStreamVerdict verdict;
@property (nonatomic) double score;
@property (nonatomic, copy) NSArray<NSString *> *cautions;

@end

static NSDictionary<NSString *, NSString *> *FlagToLanguageCode(void)
{
    static NSDictionary<NSString *, NSString *> *map = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        map = @{
            @"🇬🇧": @"en", @"🇺🇸": @"en",
            @"🇫🇷": @"fr",
            @"🇪🇸": @"es", @"🇲🇽": @"es",
            @"🇮🇹": @"it",
            @"🇩🇪": @"de",
            @"🇵🇹": @"pt", @"🇧🇷": @"pt",
            @"🇷🇺": @"ru",
            @"🇯🇵": @"ja",
            @"🇰🇷": @"ko",
            @"🇨🇳": @"zh", @"🇹🇼": @"zh",
            @"🇮🇳": @"hi",
            @"🇳🇱": @"nl",
            @"🇵🇱": @"pl",
            @"🇹🇷": @"tr",
            @"🇸🇦": @"ar",
            @"🇸🇪": @"sv",
            @"🇩🇰": @"da",
            @"🇳🇴": @"no",
            @"🇫🇮": @"fi",
            @"🇨🇿": @"cs",
            @"🇭🇺": @"hu",
            @"🇬🇷": @"el",
            @"🇮🇱": @"he",
            @"🇹🇭": @"th",
            @"🇺🇦": @"uk",
            @"🇷🇴": @"ro",
            @"🇻🇳": @"vi",
            @"🇮🇩": @"id"
        };
    });
    return map;
}

static NSArray<NSString *> *TokenizeReleaseString(NSString *str)
{
    if (str.length == 0) return @[];
    NSCharacterSet *delims = [NSCharacterSet characterSetWithCharactersInString:@". _-[]()/\\+,"];
    NSArray<NSString *> *raw = [str componentsSeparatedByCharactersInSet:delims];
    NSMutableArray<NSString *> *tokens = [NSMutableArray array];
    for (NSString *tok in raw) {
        if (tok.length > 0) {
            [tokens addObject:tok];
        }
    }
    return tokens;
}

static BOOL IsYearToken(NSString *token)
{
    if (token.length != 4) return NO;
    unichar c0 = [token characterAtIndex:0];
    unichar c1 = [token characterAtIndex:1];
    if (c0 == '1' && c1 == '9') {
        unichar c2 = [token characterAtIndex:2];
        unichar c3 = [token characterAtIndex:3];
        return (c2 >= '0' && c2 <= '9' && c3 >= '0' && c3 <= '9');
    }
    if (c0 == '2' && c1 == '0') {
        unichar c2 = [token characterAtIndex:2];
        unichar c3 = [token characterAtIndex:3];
        return (c2 >= '0' && c2 <= '9' && c3 >= '0' && c3 <= '9');
    }
    return NO;
}

static BOOL IsSeasonToken(NSString *token)
{
    if (token.length < 2) return NO;
    NSString *lower = token.lowercaseString;
    if (![lower hasPrefix:@"s"]) return NO;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"^s\\d{1,2}(e\\d{1,2})?$"
                                                                           options:NSRegularExpressionCaseInsensitive
                                                                             error:nil];
    return [regex numberOfMatchesInString:lower options:0 range:NSMakeRange(0, lower.length)] > 0;
}

static NSInteger FindBoundaryIndex(NSArray<NSString *> *tokens)
{
    for (NSUInteger i = 0; i < tokens.count; i++) {
        NSString *tok = tokens[i];
        if (i > 0 && IsYearToken(tok)) {
            return (NSInteger)i;
        }
        if (IsSeasonToken(tok)) {
            return (NSInteger)i;
        }
    }
    return -1;
}

#pragma mark - MacLCStreamFacts Implementation

@implementation MacLCStreamFacts

+ (instancetype)factsForStream:(MacLCAddonStream *)stream
{
    if (!stream) {
        return [self factsForName:nil title:nil filename:nil];
    }

    NSString *name = stream.label;
    if (stream.qualityTokens.count > 0) {
        NSString *joinedTokens = [stream.qualityTokens componentsJoinedByString:@" "];
        if (name.length > 0) {
            name = [NSString stringWithFormat:@"%@\n%@", name, joinedTokens];
        } else {
            name = joinedTokens;
        }
    }

    NSString *title = stream.headline;
    if (stream.details.length > 0) {
        NSString *restoredDetails = [stream.details stringByReplacingOccurrencesOfString:@" · " withString:@"\n"];
        if (title.length > 0) {
            title = [NSString stringWithFormat:@"%@\n%@", title, restoredDetails];
        } else {
            title = restoredDetails;
        }
    }

    BOOL forceTorrent = (stream.infoHash.length > 0);
    return [[self alloc] initWithName:name
                                title:title
                             filename:stream.filename
                         forceTorrent:forceTorrent];
}

+ (instancetype)factsForName:(nullable NSString *)name
                       title:(nullable NSString *)title
                    filename:(nullable NSString *)filename
{
    return [[self alloc] initWithName:name title:title filename:filename forceTorrent:NO];
}

- (instancetype)initWithName:(nullable NSString *)name
                       title:(nullable NSString *)title
                    filename:(nullable NSString *)filename
                forceTorrent:(BOOL)forceTorrent
{
    self = [super init];
    if (self) {
        [self parseWithName:name title:title filename:filename forceTorrent:forceTorrent];
    }
    return self;
}

- (void)parseWithName:(nullable NSString *)rawName
                title:(nullable NSString *)rawTitle
             filename:(nullable NSString *)rawFilename
         forceTorrent:(BOOL)forceTorrent
{
    NSString *name = rawName ?: @"";
    NSString *title = rawTitle ?: @"";
    NSString *filename = rawFilename ?: @"";

    // Split title into lines
    NSMutableArray<NSString *> *titleLines = [NSMutableArray array];
    for (NSString *line in [title componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (trimmed.length > 0) {
            [titleLines addObject:trimmed];
        }
    }

    // 1. Release name & pack detection
    NSString *firstLine = titleLines.count > 0 ? titleLines[0] : (filename.length > 0 ? filename : name);
    // Strip common video extensions from releaseName
    NSString *cleanedRelease = firstLine;
    NSArray<NSString *> *videoExts = @[@".mkv", @".mp4", @".avi", @".ts", @".m4v", @".mov", @".wmv", @".flv", @".iso"];
    for (NSString *ext in videoExts) {
        if ([cleanedRelease.lowercaseString hasSuffix:ext]) {
            cleanedRelease = [cleanedRelease substringToIndex:cleanedRelease.length - ext.length];
            break;
        }
    }
    _releaseName = [cleanedRelease copy];

    // Determine stats line and file line for pack
    BOOL hasPack = NO;
    NSInteger statsLineIndex = -1;
    for (NSUInteger i = 0; i < titleLines.count; i++) {
        NSString *l = titleLines[i];
        if ([l containsString:@"👤"] || [l containsString:@"💾"] || [l containsString:@"⚙️"]) {
            statsLineIndex = (NSInteger)i;
            break;
        }
    }

    if (statsLineIndex > 1) {
        // Line 1 is between line 0 and stats line -> names a file inside a pack
        hasPack = YES;
    } else if (statsLineIndex == -1 && titleLines.count > 1) {
        // No stats line, but multiple lines; line 1 could be a file line
        NSString *l1 = titleLines[1];
        if (![l1 containsString:@"👤"] && ![l1 containsString:@"💾"] && ![l1 containsString:@"⚙️"]) {
            // Check if line 1 looks like a file or path or language line
            BOOL hasFlag = NO;
            for (NSString *flag in FlagToLanguageCode().allKeys) {
                if ([l1 containsString:flag]) { hasFlag = YES; break; }
            }
            if (!hasFlag && ![l1.lowercaseString containsString:@"multi subs"] && ![l1.lowercaseString containsString:@"dual audio"]) {
                hasPack = YES;
            }
        }
    }
    _pack = hasPack;

    // Combined texts for global searches
    NSMutableString *allText = [NSMutableString string];
    if (name.length > 0) [allText appendFormat:@"%@\n", name];
    if (title.length > 0) [allText appendFormat:@"%@\n", title];
    if (filename.length > 0) [allText appendFormat:@"%@\n", filename];

    // 2. Debrid service
    NSString *allTextUpper = allText.uppercaseString;
    if ([allTextUpper containsString:@"[RD+]"] || [allTextUpper containsString:@"[RD]"]) {
        _debridService = @"Real-Debrid";
    } else if ([allTextUpper containsString:@"[AD+]"] || [allTextUpper containsString:@"[AD]"]) {
        _debridService = @"AllDebrid";
    } else if ([allTextUpper containsString:@"[PM+]"] || [allTextUpper containsString:@"[PM]"]) {
        _debridService = @"Premiumize";
    } else if ([allTextUpper containsString:@"[TB+]"] || [allTextUpper containsString:@"[TB]"]) {
        _debridService = @"TorBox";
    } else if ([allTextUpper containsString:@"[DL+]"] || [allTextUpper containsString:@"[DL]"]) {
        _debridService = @"Debrid-Link";
    } else if ([allTextUpper containsString:@"[ED+]"] || [allTextUpper containsString:@"[ED]"]) {
        _debridService = @"EasyDebrid";
    } else if ([allTextUpper containsString:@"[OC+]"] || [allTextUpper containsString:@"[OC]"]) {
        _debridService = @"Offcloud";
    } else if ([allTextUpper containsString:@"[PK+]"] || [allTextUpper containsString:@"[PIKPAK+]"]) {
        _debridService = @"PikPak";
    } else {
        _debridService = nil;
    }

    // 3. Torrent flag
    _torrent = forceTorrent || ([allText containsString:@"👤"]);

    // 4. Seeders
    _seeders = -1;
    NSRegularExpression *seedRegex = [NSRegularExpression regularExpressionWithPattern:@"👤\\s*([0-9]+)" options:0 error:nil];
    NSTextCheckingResult *seedMatch = [seedRegex firstMatchInString:allText options:0 range:NSMakeRange(0, allText.length)];
    if (seedMatch) {
        NSString *seedStr = [allText substringWithRange:[seedMatch rangeAtIndex:1]];
        _seeders = [seedStr integerValue];
    }

    // 5. Size
    _sizeBytes = 0;
    NSRegularExpression *sizeRegex = [NSRegularExpression regularExpressionWithPattern:@"(?:💾|Size:\\s*)\\s*([0-9]+(?:[.,][0-9]+)?)\\s*(TB|GB|MB|KB|B|GiB|MiB|KiB|TiB)"
                                                                               options:NSRegularExpressionCaseInsensitive
                                                                                 error:nil];
    NSTextCheckingResult *sizeMatch = [sizeRegex firstMatchInString:allText options:0 range:NSMakeRange(0, allText.length)];
    if (!sizeMatch) {
        // Fallback: search for numbers followed by GB / MB
        NSRegularExpression *fallbackSizeRegex = [NSRegularExpression regularExpressionWithPattern:@"\\b([0-9]+(?:[.,][0-9]+)?)\\s*(TB|GB|MB|KB|GiB|MiB|KiB|TiB)\\b"
                                                                                           options:NSRegularExpressionCaseInsensitive
                                                                                             error:nil];
        sizeMatch = [fallbackSizeRegex firstMatchInString:allText options:0 range:NSMakeRange(0, allText.length)];
    }
    if (sizeMatch) {
        NSString *numStr = [allText substringWithRange:[sizeMatch rangeAtIndex:1]];
        NSString *unit = [[allText substringWithRange:[sizeMatch rangeAtIndex:2]] uppercaseString];
        numStr = [numStr stringByReplacingOccurrencesOfString:@"," withString:@"."];
        double num = [numStr doubleValue];
        unsigned long long mult = 1;
        if ([unit hasPrefix:@"T"]) {
            mult = 1024ULL * 1024ULL * 1024ULL * 1024ULL;
        } else if ([unit hasPrefix:@"G"]) {
            mult = 1024ULL * 1024ULL * 1024ULL;
        } else if ([unit hasPrefix:@"M"]) {
            mult = 1024ULL * 1024ULL;
        } else if ([unit hasPrefix:@"K"]) {
            mult = 1024ULL;
        }
        _sizeBytes = (unsigned long long)llround(num * mult);
    }

    // 6. Provider
    _provider = nil;
    NSRegularExpression *provRegex = [NSRegularExpression regularExpressionWithPattern:@"⚙️\\s*([^\\n\\r]+)" options:0 error:nil];
    NSTextCheckingResult *provMatch = [provRegex firstMatchInString:allText options:0 range:NSMakeRange(0, allText.length)];
    if (provMatch) {
        NSString *prov = [[allText substringWithRange:[provMatch rangeAtIndex:1]] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        // Drop any following emoji or extra fields
        NSArray<NSString *> *parts = [prov componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (parts.count > 0 && parts[0].length > 0) {
            _provider = parts[0];
        }
    }

    // 7. Health
    if (_debridService != nil) {
        _health = MacLCStreamHealthExcellent;
    } else if (!_torrent || _seeders < 0) {
        _health = MacLCStreamHealthUnknown;
    } else if (_seeders == 0) {
        _health = MacLCStreamHealthNone;
    } else if (_seeders <= 4) {
        _health = MacLCStreamHealthWeak;
    } else if (_seeders <= 19) {
        _health = MacLCStreamHealthFair;
    } else if (_seeders <= 99) {
        _health = MacLCStreamHealthGood;
    } else {
        _health = MacLCStreamHealthExcellent;
    }

    // 8. Resolution
    /* Whole tokens only, and never from the stats line: a site called
     * "Wolfmax4k" is not a 4K picture. The add-on's name line decides first
     * (Torrentio writes the resolution there), then the title, then the file. */
    _resolution = MacLCStreamResolutionUnknown;
    static NSRegularExpression *resolutionRegex;
    static dispatch_once_t resolutionOnce;
    dispatch_once(&resolutionOnce, ^{
        resolutionRegex = [NSRegularExpression regularExpressionWithPattern:
            @"(?<![a-z0-9])(2160p|4k|uhd|1080p|1080i|fhd|720p|576p|480p|sd|dvdrip)(?![a-z0-9])"
                                                                    options:NSRegularExpressionCaseInsensitive
                                                                      error:nil];
    });
    NSMutableArray<NSString *> *resolutionSources = [NSMutableArray array];
    if (name.length > 0)
        [resolutionSources addObject:name];
    NSMutableString *titleWithoutStats = [NSMutableString string];
    for (NSString *line in titleLines)
        if (![line containsString:@"👤"] && ![line containsString:@"💾"] && ![line containsString:@"⚙️"])
            [titleWithoutStats appendFormat:@"%@\n", line];
    [resolutionSources addObject:titleWithoutStats];
    if (filename.length > 0)
        [resolutionSources addObject:filename];
    for (NSString *source in resolutionSources) {
        NSTextCheckingResult *match = [resolutionRegex firstMatchInString:source options:0 range:NSMakeRange(0, source.length)];
        if (match == nil)
            continue;
        NSString *token = [source substringWithRange:[match rangeAtIndex:1]].lowercaseString;
        if ([token isEqualToString:@"2160p"] || [token isEqualToString:@"4k"] || [token isEqualToString:@"uhd"])
            _resolution = MacLCStreamResolution4K;
        else if ([token hasPrefix:@"1080"] || [token isEqualToString:@"fhd"])
            _resolution = MacLCStreamResolution1080p;
        else if ([token isEqualToString:@"720p"])
            _resolution = MacLCStreamResolution720p;
        else
            _resolution = MacLCStreamResolutionSD;
        break;
    }

    // 9. Dynamic range & HDR formats
    NSMutableArray<NSString *> *hdrs = [NSMutableArray array];
    BOOL hasDV = NO, hasHDR10Plus = NO, hasHDR10 = NO, hasHDR = NO, hasHLG = NO, hasSDR = NO;
    if ([allText rangeOfString:@"\\b(DV|DoVi|Dolby Vision|DolbyVision)\\b" options:NSRegularExpressionSearch | NSCaseInsensitiveSearch].location != NSNotFound) {
        hasDV = YES;
    }
    if ([allText rangeOfString:@"\\b(HDR10\\+|HDR10Plus|HDR10 Plus)\\b" options:NSRegularExpressionSearch | NSCaseInsensitiveSearch].location != NSNotFound) {
        hasHDR10Plus = YES;
    }
    if ([allText rangeOfString:@"\\bHDR10\\b" options:NSRegularExpressionSearch | NSCaseInsensitiveSearch].location != NSNotFound && !hasHDR10Plus) {
        hasHDR10 = YES;
    }
    if ([allText rangeOfString:@"\\bHLG\\b" options:NSRegularExpressionSearch | NSCaseInsensitiveSearch].location != NSNotFound) {
        hasHLG = YES;
    }
    if ([allText rangeOfString:@"\\bHDR\\b" options:NSRegularExpressionSearch | NSCaseInsensitiveSearch].location != NSNotFound) {
        if (!hasHDR10 && !hasHDR10Plus) {
            hasHDR = YES;
        }
    }
    if ([allText rangeOfString:@"\\bSDR\\b" options:NSRegularExpressionSearch | NSCaseInsensitiveSearch].location != NSNotFound) {
        hasSDR = YES;
    }

    if (hasDV) [hdrs addObject:@"Dolby Vision"];
    if (hasHDR10Plus) [hdrs addObject:@"HDR10+"];
    if (hasHDR10) [hdrs addObject:@"HDR10"];
    if (hasHDR) [hdrs addObject:@"HDR"];
    if (hasHLG) [hdrs addObject:@"HLG"];
    _hdrFormats = [hdrs copy];

    if (hasDV) {
        _dynamicRange = MacLCStreamDynamicRangeDolbyVision;
    } else if (hasHDR10Plus) {
        _dynamicRange = MacLCStreamDynamicRangeHDR10Plus;
    } else if (hasHDR10) {
        _dynamicRange = MacLCStreamDynamicRangeHDR10;
    } else if (hasHDR) {
        _dynamicRange = MacLCStreamDynamicRangeHDR;
    } else if (hasHLG) {
        _dynamicRange = MacLCStreamDynamicRangeHLG;
    } else if (hasSDR) {
        _dynamicRange = MacLCStreamDynamicRangeSDR;
    } else {
        _dynamicRange = MacLCStreamDynamicRangeUnknown;
    }

    NSString *allLower = allText.lowercaseString;
    _tenBit = (hasDV || hasHDR10Plus || hasHDR10 || hasHDR || hasHLG ||
               [allLower containsString:@"10bit"] || [allLower containsString:@"10-bit"] || [allLower containsString:@"hi10p"]);

    // 10. Video Codec
    _videoCodec = MacLCStreamVideoCodecUnknown;
    if ([allText rangeOfString:@"\\b(AV1|AV01)\\b" options:NSRegularExpressionSearch | NSCaseInsensitiveSearch].location != NSNotFound) {
        _videoCodec = MacLCStreamVideoCodecAV1;
    } else if ([allText rangeOfString:@"\\b(x265|h265|h\\.265|hevc)\\b" options:NSRegularExpressionSearch | NSCaseInsensitiveSearch].location != NSNotFound) {
        _videoCodec = MacLCStreamVideoCodecHEVC;
    } else if ([allText rangeOfString:@"\\b(x264|h264|h\\.264|avc)\\b" options:NSRegularExpressionSearch | NSCaseInsensitiveSearch].location != NSNotFound) {
        _videoCodec = MacLCStreamVideoCodecH264;
    } else if ([allText rangeOfString:@"\\b(xvid|divx|vp9|mpeg2|mpeg-2|vc-1|vc1)\\b" options:NSRegularExpressionSearch | NSCaseInsensitiveSearch].location != NSNotFound) {
        _videoCodec = MacLCStreamVideoCodecOther;
    }

    // 11. Token boundary analysis for Release Name tokens (Title Line 0 + Filename)
    NSArray<NSString *> *releaseTokens = TokenizeReleaseString(firstLine);
    NSInteger boundaryIdx = FindBoundaryIndex(releaseTokens);
    NSSet<NSString *> *postBoundaryTokenSet = nil;
    if (boundaryIdx >= 0) {
        NSMutableSet<NSString *> *set = [NSMutableSet set];
        for (NSUInteger i = (NSUInteger)(boundaryIdx + 1); i < releaseTokens.count; i++) {
            [set addObject:releaseTokens[i].uppercaseString];
        }
        postBoundaryTokenSet = [set copy];
    } else {
        postBoundaryTokenSet = [NSSet set];
    }

    // If there is a file line inside pack or filename, also analyze its tokens after year/season
    if (titleLines.count > 1 && hasPack) {
        NSArray<NSString *> *fileTokens = TokenizeReleaseString(titleLines[1]);
        NSInteger fBoundary = FindBoundaryIndex(fileTokens);
        if (fBoundary >= 0) {
            NSMutableSet<NSString *> *set = [postBoundaryTokenSet mutableCopy];
            for (NSUInteger i = (NSUInteger)(fBoundary + 1); i < fileTokens.count; i++) {
                [set addObject:fileTokens[i].uppercaseString];
            }
            postBoundaryTokenSet = [set copy];
        }
    }
    if (filename.length > 0) {
        NSArray<NSString *> *fnTokens = TokenizeReleaseString(filename);
        NSInteger fnBoundary = FindBoundaryIndex(fnTokens);
        if (fnBoundary >= 0) {
            NSMutableSet<NSString *> *set = [postBoundaryTokenSet mutableCopy];
            for (NSUInteger i = (NSUInteger)(fnBoundary + 1); i < fnTokens.count; i++) {
                [set addObject:fnTokens[i].uppercaseString];
            }
            postBoundaryTokenSet = [set copy];
        }
    }

    // 12. Source detection
    // "Language words (and source/edition words that are also English words) are read ONLY in the release-name tokens AFTER the first year token... or the first SxxEyy/Sxx token"
    _source = MacLCStreamSourceUnknown;
    if ([allText rangeOfString:@"\\b(REMUX|BDREMUX)\\b" options:NSRegularExpressionSearch | NSCaseInsensitiveSearch].location != NSNotFound) {
        _source = MacLCStreamSourceRemux;
    } else if ([allText rangeOfString:@"\\b(BluRay|Blu-Ray|BDRip|BRRip|BD50|BD25)\\b" options:NSRegularExpressionSearch | NSCaseInsensitiveSearch].location != NSNotFound) {
        _source = MacLCStreamSourceBluRay;
    } else if ([allText rangeOfString:@"\\b(WEB-DL|WEBDL|WEB)\\b" options:NSRegularExpressionSearch | NSCaseInsensitiveSearch].location != NSNotFound &&
               [allText rangeOfString:@"\\b(WEBRip|WEB-Rip)\\b" options:NSRegularExpressionSearch | NSCaseInsensitiveSearch].location == NSNotFound) {
        _source = MacLCStreamSourceWebDL;
    } else if ([allText rangeOfString:@"\\b(WEBRip|WEB-Rip)\\b" options:NSRegularExpressionSearch | NSCaseInsensitiveSearch].location != NSNotFound) {
        _source = MacLCStreamSourceWebRip;
    } else if ([allText rangeOfString:@"\\b(HDTV|PDTV|DSR|TVRip)\\b" options:NSRegularExpressionSearch | NSCaseInsensitiveSearch].location != NSNotFound) {
        _source = MacLCStreamSourceHDTV;
    } else if ([allText rangeOfString:@"\\b(DVDRip|DVD|DVD5|DVD9|DVD-Rip)\\b" options:NSRegularExpressionSearch | NSCaseInsensitiveSearch].location != NSNotFound) {
        _source = MacLCStreamSourceDVD;
    }

    // Cam / Screener / Telesync
    // CAM is an ordinary English word: check only in postBoundaryTokenSet or compound forms like HDCAM/CAMRip
    BOOL hasCam = [postBoundaryTokenSet containsObject:@"CAM"] ||
                  [postBoundaryTokenSet containsObject:@"HDCAM"] ||
                  [postBoundaryTokenSet containsObject:@"CAMRIP"] ||
                  ([allText rangeOfString:@"\\b(HDCAM|CAMRip)\\b" options:NSRegularExpressionSearch | NSCaseInsensitiveSearch].location != NSNotFound && boundaryIdx >= 0);
    BOOL hasTelesync = [postBoundaryTokenSet containsObject:@"TELESYNC"] ||
                       [postBoundaryTokenSet containsObject:@"HDTS"] ||
                       [postBoundaryTokenSet containsObject:@"TS"] ||
                       [postBoundaryTokenSet containsObject:@"TELECINE"] ||
                       [postBoundaryTokenSet containsObject:@"TC"];
    BOOL hasScreener = [postBoundaryTokenSet containsObject:@"SCREENER"] ||
                       [postBoundaryTokenSet containsObject:@"SCR"] ||
                       [postBoundaryTokenSet containsObject:@"DVDSCR"] ||
                       [postBoundaryTokenSet containsObject:@"R5"];

    if (hasCam) {
        _source = MacLCStreamSourceCam;
    } else if (hasTelesync && _source == MacLCStreamSourceUnknown) {
        _source = MacLCStreamSourceTelesync;
    } else if (hasScreener && _source == MacLCStreamSourceUnknown) {
        _source = MacLCStreamSourceScreener;
    }

    // 13. Audio detection
    // Formats: Dolby Atmos, DTS:X, Dolby TrueHD, DTS-HD MA, DTS, Dolby Digital Plus, Dolby Digital, AAC, FLAC, Opus, PCM, MP3
    NSString *foundChannels = nil;
    NSRegularExpression *chanRegex = [NSRegularExpression regularExpressionWithPattern:@"(?:^|[^0-9])(7[._]1|5[._]1|2[._]0|1[._]0)(?:$|[^0-9])" options:0 error:nil];
    NSArray<NSTextCheckingResult *> *chanMatches = [chanRegex matchesInString:allText options:0 range:NSMakeRange(0, allText.length)];
    for (NSTextCheckingResult *m in chanMatches) {
        NSString *c = [[allText substringWithRange:[m rangeAtIndex:1]] stringByReplacingOccurrencesOfString:@"_" withString:@"."];
        if ([c isEqualToString:@"7.1"]) {
            foundChannels = @"7.1";
            break;
        } else if ([c isEqualToString:@"5.1"]) {
            foundChannels = @"5.1";
        } else if ([c isEqualToString:@"2.0"] && (!foundChannels || [foundChannels isEqualToString:@"1.0"])) {
            foundChannels = @"2.0";
        } else if (!foundChannels) {
            foundChannels = c;
        }
    }

    BOOL hasAtmos = [allText rangeOfString:@"\\bAtmos\\b" options:NSRegularExpressionSearch | NSCaseInsensitiveSearch].location != NSNotFound;
    BOOL hasDTSX = [allText rangeOfString:@"\\b(DTS:X|DTS-X|DTSX)\\b" options:NSRegularExpressionSearch | NSCaseInsensitiveSearch].location != NSNotFound;
    BOOL hasTrueHD = [allText rangeOfString:@"\\bTrueHD\\b" options:NSRegularExpressionSearch | NSCaseInsensitiveSearch].location != NSNotFound;
    BOOL hasDTSHD = [allText rangeOfString:@"\\b(DTS-HD|DTSHD|DTS-HD MA|DTS-HD.MA)\\b" options:NSRegularExpressionSearch | NSCaseInsensitiveSearch].location != NSNotFound;
    BOOL hasDTS = [allText rangeOfString:@"\\bDTS\\b" options:NSRegularExpressionSearch | NSCaseInsensitiveSearch].location != NSNotFound && !hasDTSX && !hasDTSHD;
    BOOL hasDDP = [allText rangeOfString:@"\\b(DDP|DD\\+|E-AC-3|EAC3|Dolby Digital Plus)(?:\\b|(?=[0-9]))" options:NSRegularExpressionSearch | NSCaseInsensitiveSearch].location != NSNotFound;
    BOOL hasDD = [allText rangeOfString:@"\\b(AC-3|AC3|DD|Dolby Digital)(?:\\b|(?=[0-9]))" options:NSRegularExpressionSearch | NSCaseInsensitiveSearch].location != NSNotFound && !hasDDP;
    BOOL hasAAC = [allText rangeOfString:@"\\bAAC(?:\\b|(?=[0-9]))" options:NSRegularExpressionSearch | NSCaseInsensitiveSearch].location != NSNotFound;
    BOOL hasFLAC = [allText rangeOfString:@"\\bFLAC\\b" options:NSRegularExpressionSearch | NSCaseInsensitiveSearch].location != NSNotFound;
    BOOL hasPCM = [allText rangeOfString:@"\\b(LPCM|PCM)\\b" options:NSRegularExpressionSearch | NSCaseInsensitiveSearch].location != NSNotFound;
    BOOL hasOpus = [allText rangeOfString:@"\\bOpus\\b" options:NSRegularExpressionSearch | NSCaseInsensitiveSearch].location != NSNotFound;
    BOOL hasMP3 = [allText rangeOfString:@"\\bMP3\\b" options:NSRegularExpressionSearch | NSCaseInsensitiveSearch].location != NSNotFound;

    NSMutableArray<MacLCStreamAudio *> *audios = [NSMutableArray array];
    // "TrueHD Atmos 7.1 gives one entry, format Dolby Atmos, channels 7.1"
    if (hasAtmos) {
        [audios addObject:[[MacLCStreamAudio alloc] initWithFormat:@"Dolby Atmos" channels:foundChannels]];
    } else if (hasDTSX) {
        [audios addObject:[[MacLCStreamAudio alloc] initWithFormat:@"DTS:X" channels:foundChannels]];
    } else if (hasTrueHD) {
        [audios addObject:[[MacLCStreamAudio alloc] initWithFormat:@"Dolby TrueHD" channels:foundChannels]];
    } else if (hasDTSHD) {
        [audios addObject:[[MacLCStreamAudio alloc] initWithFormat:@"DTS-HD MA" channels:foundChannels]];
    }

    if (hasFLAC) {
        [audios addObject:[[MacLCStreamAudio alloc] initWithFormat:@"FLAC" channels:foundChannels]];
    }
    if (hasPCM) {
        [audios addObject:[[MacLCStreamAudio alloc] initWithFormat:@"PCM" channels:foundChannels]];
    }
    if (hasDTS && !hasDTSX && !hasDTSHD) {
        [audios addObject:[[MacLCStreamAudio alloc] initWithFormat:@"DTS" channels:foundChannels]];
    }
    if (hasDDP && !hasAtmos) {
        [audios addObject:[[MacLCStreamAudio alloc] initWithFormat:@"Dolby Digital Plus" channels:foundChannels]];
    }
    if (hasDD && !hasAtmos && !hasDDP) {
        [audios addObject:[[MacLCStreamAudio alloc] initWithFormat:@"Dolby Digital" channels:foundChannels]];
    }
    if (hasAAC) {
        [audios addObject:[[MacLCStreamAudio alloc] initWithFormat:@"AAC" channels:foundChannels]];
    }
    if (hasOpus) {
        [audios addObject:[[MacLCStreamAudio alloc] initWithFormat:@"Opus" channels:foundChannels]];
    }
    if (hasMP3) {
        [audios addObject:[[MacLCStreamAudio alloc] initWithFormat:@"MP3" channels:foundChannels]];
    }
    _audio = [audios copy];

    // 14. Edition Notes
    // "REMASTERED", "CRITERION", "EXTENDED", "Director's Cut", "IMAX", "UNRATED", "UPSCALED"
    NSMutableArray<NSString *> *editions = [NSMutableArray array];
    if ([postBoundaryTokenSet containsObject:@"REMASTERED"] || [postBoundaryTokenSet containsObject:@"REMASTER"]) {
        [editions addObject:@"REMASTERED"];
    }
    if ([postBoundaryTokenSet containsObject:@"CRITERION"]) {
        [editions addObject:@"CRITERION"];
    }
    if ([postBoundaryTokenSet containsObject:@"EXTENDED"]) {
        [editions addObject:@"EXTENDED"];
    }
    if ([postBoundaryTokenSet containsObject:@"DIRECTOR'S"] || [allText rangeOfString:@"\\bDirector'?s Cut\\b" options:NSRegularExpressionSearch | NSCaseInsensitiveSearch].location != NSNotFound) {
        if (boundaryIdx >= 0) [editions addObject:@"Director's Cut"];
    }
    if ([postBoundaryTokenSet containsObject:@"IMAX"]) {
        [editions addObject:@"IMAX"];
    }
    if ([postBoundaryTokenSet containsObject:@"UNRATED"]) {
        [editions addObject:@"UNRATED"];
    }
    if ([postBoundaryTokenSet containsObject:@"UPSCALED"] || [postBoundaryTokenSet containsObject:@"UPSCALE"]) {
        [editions addObject:@"UPSCALED"];
    }
    _editionNotes = [editions copy];

    // 15. Subtitles & Languages
    // Multi language
    BOOL isMulti = [postBoundaryTokenSet containsObject:@"MULTI"] ||
                   [postBoundaryTokenSet containsObject:@"MULTi"] ||
                   [postBoundaryTokenSet containsObject:@"DUAL"] ||
                   [allText rangeOfString:@"\\b(Multi Audio|Dual Audio|Multi-Audio|Dual-Audio)\\b" options:NSRegularExpressionSearch | NSCaseInsensitiveSearch].location != NSNotFound;
    _multiLanguage = isMulti;

    // Multiple subtitles
    _hasMultipleSubtitles = ([allText rangeOfString:@"\\b(Multi Subs|Multi-Subs|Multisub|Multisubs)\\b" options:NSRegularExpressionSearch | NSCaseInsensitiveSearch].location != NSNotFound);

    // Subtitle languages
    NSMutableArray<NSString *> *subLangs = [NSMutableArray array];
    NSMutableSet<NSString *> *seenSubLangs = [NSMutableSet set];
    void (^addSubLang)(NSString *) = ^(NSString *code) {
        if (code.length > 0 && ![seenSubLangs containsObject:code]) {
            [seenSubLangs addObject:code];
            [subLangs addObject:code];
        }
    };

    if ([postBoundaryTokenSet containsObject:@"VOSTFR"] || [postBoundaryTokenSet containsObject:@"SUBFRENCH"]) {
        addSubLang(@"fr");
    }
    if ([postBoundaryTokenSet containsObject:@"SUBITA"] || [allText rangeOfString:@"\\bSub Ita\\b" options:NSRegularExpressionSearch | NSCaseInsensitiveSearch].location != NSNotFound) {
        addSubLang(@"it");
    }
    if ([postBoundaryTokenSet containsObject:@"SUBENG"] || [allText rangeOfString:@"\\bEng Subs?\\b" options:NSRegularExpressionSearch | NSCaseInsensitiveSearch].location != NSNotFound) {
        addSubLang(@"en");
    }
    if ([postBoundaryTokenSet containsObject:@"SUBESP"] || [allText rangeOfString:@"\\bSub Esp\\b" options:NSRegularExpressionSearch | NSCaseInsensitiveSearch].location != NSNotFound) {
        addSubLang(@"es");
    }
    if ([allText rangeOfString:@"\\bNapisy PL\\b" options:NSRegularExpressionSearch | NSCaseInsensitiveSearch].location != NSNotFound) {
        addSubLang(@"pl");
    }
    _subtitleLanguages = [subLangs copy];

    // Spoken languages
    NSMutableArray<NSString *> *langs = [NSMutableArray array];
    NSMutableSet<NSString *> *seenLangs = [NSMutableSet set];
    void (^addLang)(NSString *) = ^(NSString *code) {
        if (code.length > 0 && ![seenLangs containsObject:code]) {
            [seenLangs addObject:code];
            [langs addObject:code];
        }
    };

    // Scan for flag emojis across allText in the exact order they appear
    NSDictionary<NSString *, NSString *> *flagMap = FlagToLanguageCode();
    NSMutableArray<NSValue *> *flagRanges = [NSMutableArray array];
    for (NSString *flag in flagMap.allKeys) {
        NSRange searchRange = NSMakeRange(0, allText.length);
        while (searchRange.location < allText.length) {
            NSRange r = [allText rangeOfString:flag options:0 range:searchRange];
            if (r.location == NSNotFound) break;
            [flagRanges addObject:[NSValue valueWithRange:r]];
            searchRange.location = r.location + r.length;
            searchRange.length = allText.length - searchRange.location;
        }
    }
    [flagRanges sortUsingComparator:^NSComparisonResult(NSValue *a, NSValue *b) {
        return [@(a.rangeValue.location) compare:@(b.rangeValue.location)];
    }];
    for (NSValue *val in flagRanges) {
        NSString *flagStr = [allText substringWithRange:val.rangeValue];
        NSString *code = flagMap[flagStr];
        if (code) {
            addLang(code);
        }
    }

    // Explicit language line: lines after stats line or lines with flags or 'Multi Subs'/'Dual Audio'
    for (NSString *line in titleLines) {
        BOOL isExplicitLine = NO;
        for (NSString *flag in flagMap.allKeys) {
            if ([line containsString:flag]) { isExplicitLine = YES; break; }
        }
        if (!isExplicitLine && ([line.lowercaseString containsString:@"multi subs"] || [line.lowercaseString containsString:@"dual audio"])) {
            isExplicitLine = YES;
        }
        if (isExplicitLine) {
            NSArray<NSString *> *lineTokens = TokenizeReleaseString(line);
            for (NSString *t in lineTokens) {
                NSString *u = t.uppercaseString;
                if ([u isEqualToString:@"TURKO"] || [u isEqualToString:@"TUR"]) addLang(@"tr");
                else if ([u isEqualToString:@"ESP"] || [u isEqualToString:@"ESPANOL"]) addLang(@"es");
                else if ([u isEqualToString:@"ITA"] || [u isEqualToString:@"ITALIANO"]) addLang(@"it");
                else if ([u isEqualToString:@"FRA"] || [u isEqualToString:@"FRANCAIS"]) addLang(@"fr");
                else if ([u isEqualToString:@"GER"] || [u isEqualToString:@"DEUTSCH"]) addLang(@"de");
                else if ([u isEqualToString:@"RUS"]) addLang(@"ru");
                else if ([u isEqualToString:@"ENG"] || [u isEqualToString:@"ENGLISH"]) addLang(@"en");
            }
        }
    }

    // Language words in release-name tokens AFTER year or season boundary
    // "Language words (and source/edition words that are also English words) are read ONLY in the release-name tokens AFTER the first year token... or the first SxxEyy/Sxx token"
    for (NSUInteger i = (boundaryIdx >= 0 ? (NSUInteger)(boundaryIdx + 1) : releaseTokens.count); i < releaseTokens.count; i++) {
        NSString *t = releaseTokens[i].uppercaseString;
        if ([t isEqualToString:@"ENG"] || [t isEqualToString:@"ENGLISH"]) {
            addLang(@"en");
        } else if ([t isEqualToString:@"FRENCH"] || [t isEqualToString:@"TRUEFRENCH"] ||
                   [t isEqualToString:@"VFF"] || [t isEqualToString:@"VFQ"] || [t isEqualToString:@"VF2"]) {
            addLang(@"fr");
        } else if ([t isEqualToString:@"ITA"] || [t isEqualToString:@"ITALIAN"]) {
            addLang(@"it");
        } else if ([t isEqualToString:@"SPA"] || [t isEqualToString:@"SPANISH"] ||
                   [t isEqualToString:@"CASTELLANO"] || [t isEqualToString:@"LATINO"]) {
            addLang(@"es");
        } else if ([t isEqualToString:@"GER"] || [t isEqualToString:@"GERMAN"] || [t isEqualToString:@"DEUTSCH"]) {
            addLang(@"de");
        } else if ([t isEqualToString:@"RUS"] || [t isEqualToString:@"RUSSIAN"]) {
            addLang(@"ru");
        } else if ([t isEqualToString:@"JAP"] || [t isEqualToString:@"JPN"] || [t isEqualToString:@"JAPANESE"]) {
            addLang(@"ja");
        } else if ([t isEqualToString:@"KOR"] || [t isEqualToString:@"KOREAN"]) {
            addLang(@"ko");
        } else if ([t isEqualToString:@"HIN"] || [t isEqualToString:@"HINDI"]) {
            addLang(@"hi");
        } else if ([t isEqualToString:@"POR"] || [t isEqualToString:@"PORTUGUESE"]) {
            addLang(@"pt");
        } else if ([t isEqualToString:@"POL"] || [t isEqualToString:@"POLISH"]) {
            addLang(@"pl");
        } else if ([t isEqualToString:@"TUR"] || [t isEqualToString:@"TURKISH"] || [t isEqualToString:@"TURKO"]) {
            addLang(@"tr");
        } else if ([t isEqualToString:@"DUTCH"]) {
            addLang(@"nl");
        } else if ([t isEqualToString:@"SWEDISH"]) {
            addLang(@"sv");
        } else if ([t isEqualToString:@"DANISH"]) {
            addLang(@"da");
        } else if ([t isEqualToString:@"NORWEGIAN"]) {
            addLang(@"no");
        } else if ([t isEqualToString:@"FINNISH"]) {
            addLang(@"fi");
        } else if ([t isEqualToString:@"CZECH"]) {
            addLang(@"cs");
        } else if ([t isEqualToString:@"HUNGARIAN"]) {
            addLang(@"hu");
        } else if ([t isEqualToString:@"GREEK"]) {
            addLang(@"el");
        } else if ([t isEqualToString:@"HEBREW"]) {
            addLang(@"he");
        } else if ([t isEqualToString:@"THAI"]) {
            addLang(@"th");
        } else if ([t isEqualToString:@"UKRAINIAN"]) {
            addLang(@"uk");
        } else if ([t isEqualToString:@"ROMANIAN"]) {
            addLang(@"ro");
        } else if ([t isEqualToString:@"VIETNAMESE"]) {
            addLang(@"vi");
        } else if ([t isEqualToString:@"INDONESIAN"]) {
            addLang(@"id");
        }
    }
    _languages = [langs copy];

    // 16. Verdict
    // Poor: CAM / Telesync / Screener source, or a torrent with 0 seeders.
    // Great: 1080p or 4K, Remux/BluRay/WEB-DL, health Good or better (or debrid).
    // Good: 1080p or better from a known good source with health Fair+, or 720p+ with health Good+.
    // Okay: the rest that plays.
    // Unknown: nothing known but a name.
    if (_source == MacLCStreamSourceCam ||
        _source == MacLCStreamSourceTelesync ||
        _source == MacLCStreamSourceScreener ||
        (_torrent && _seeders == 0)) {
        _verdict = MacLCStreamVerdictPoor;
    } else {
        BOOL isGoodSource = (_source == MacLCStreamSourceRemux || _source == MacLCStreamSourceBluRay ||
                             _source == MacLCStreamSourceWebDL || _source == MacLCStreamSourceWebRip ||
                             _source == MacLCStreamSourceHDTV);
        BOOL isTopSource = (_source == MacLCStreamSourceRemux || _source == MacLCStreamSourceBluRay ||
                            _source == MacLCStreamSourceWebDL);
        BOOL isHealthGoodOrBetter = (_health == MacLCStreamHealthGood || _health == MacLCStreamHealthExcellent || _debridService != nil);
        BOOL isHealthFairOrBetter = (_health == MacLCStreamHealthFair || isHealthGoodOrBetter);

        if ((_resolution == MacLCStreamResolution1080p || _resolution == MacLCStreamResolution4K) &&
            isTopSource && isHealthGoodOrBetter) {
            _verdict = MacLCStreamVerdictGreat;
        } else if ((_resolution >= MacLCStreamResolution1080p && isGoodSource && isHealthFairOrBetter) ||
                   (_resolution >= MacLCStreamResolution720p && isHealthGoodOrBetter)) {
            _verdict = MacLCStreamVerdictGood;
        } else if (_resolution == MacLCStreamResolutionUnknown &&
                   _source == MacLCStreamSourceUnknown &&
                   _health == MacLCStreamHealthUnknown &&
                   _audio.count == 0 &&
                   _sizeBytes == 0) {
            _verdict = MacLCStreamVerdictUnknown;
        } else {
            _verdict = MacLCStreamVerdictOkay;
        }
    }

    // 17. Cautions
    // Most important first, at most 3:
    // @"Recorded in a cinema", @"Nobody is sharing it right now",
    // @"Upscaled, not a true 4K master", @"Very few people sharing: may pause"
    NSMutableArray<NSString *> *cauts = [NSMutableArray array];
    if (_source == MacLCStreamSourceCam || _source == MacLCStreamSourceTelesync) {
        [cauts addObject:@"Recorded in a cinema"];
    }
    if (_torrent && _seeders == 0) {
        [cauts addObject:@"Nobody is sharing it right now"];
    }
    if ([_editionNotes containsObject:@"UPSCALED"]) {
        [cauts addObject:@"Upscaled, not a true 4K master"];
    }
    if (_torrent && _health == MacLCStreamHealthWeak && _debridService == nil) {
        [cauts addObject:@"Very few people sharing: may pause"];
    }
    if (cauts.count > 3) {
        _cautions = [cauts subarrayWithRange:NSMakeRange(0, 3)];
    } else {
        _cautions = [cauts copy];
    }

    // 18. Score
    // Ranking used to sort and to pick "Best Match": higher is better; health weighs most,
    // then verdict, resolution, dynamic range, audio, then smaller size at equal quality.
    double sc = 0.0;
    if (_debridService != nil) {
        sc += 5000.0;
    } else {
        switch (_health) {
            case MacLCStreamHealthExcellent: sc += 5000.0; break;
            case MacLCStreamHealthGood:      sc += 4000.0; break;
            case MacLCStreamHealthFair:      sc += 3000.0; break;
            case MacLCStreamHealthWeak:      sc += 1000.0; break;
            case MacLCStreamHealthNone:      sc += 0.0; break;
            case MacLCStreamHealthUnknown:   sc += 500.0; break;
        }
    }

    switch (_verdict) {
        case MacLCStreamVerdictGreat:   sc += 2000.0; break;
        case MacLCStreamVerdictGood:    sc += 1500.0; break;
        case MacLCStreamVerdictOkay:    sc += 1000.0; break;
        case MacLCStreamVerdictUnknown: sc += 500.0; break;
        case MacLCStreamVerdictPoor:    sc += -5000.0; break;
    }

    switch (_resolution) {
        case MacLCStreamResolution4K:      sc += 400.0; break;
        case MacLCStreamResolution1080p:   sc += 300.0; break;
        case MacLCStreamResolution720p:    sc += 200.0; break;
        case MacLCStreamResolutionSD:      sc += 100.0; break;
        case MacLCStreamResolutionUnknown: sc += 0.0; break;
    }

    switch (_dynamicRange) {
        case MacLCStreamDynamicRangeDolbyVision: sc += 60.0; break;
        case MacLCStreamDynamicRangeHDR10Plus:   sc += 50.0; break;
        case MacLCStreamDynamicRangeHDR10:       sc += 40.0; break;
        case MacLCStreamDynamicRangeHDR:         sc += 30.0; break;
        case MacLCStreamDynamicRangeHLG:         sc += 20.0; break;
        case MacLCStreamDynamicRangeSDR:         sc += 10.0; break;
        case MacLCStreamDynamicRangeUnknown:     sc += 0.0; break;
    }

    if (_audio.count > 0) {
        MacLCStreamAudio *first = _audio.firstObject;
        if (first.isImmersive) {
            sc += 30.0;
        } else if (first.isLossless) {
            sc += 20.0;
        } else {
            sc += 10.0;
        }
        if ([first.channels isEqualToString:@"7.1"]) {
            sc += 5.0;
        } else if ([first.channels isEqualToString:@"5.1"]) {
            sc += 3.0;
        }
    }

    switch (_source) {
        case MacLCStreamSourceRemux:     sc += 25.0; break;
        case MacLCStreamSourceBluRay:    sc += 20.0; break;
        case MacLCStreamSourceWebDL:     sc += 15.0; break;
        case MacLCStreamSourceWebRip:    sc += 10.0; break;
        case MacLCStreamSourceHDTV:      sc += 8.0; break;
        case MacLCStreamSourceDVD:       sc += 5.0; break;
        case MacLCStreamSourceScreener:  sc += 1.0; break;
        case MacLCStreamSourceTelesync:  sc += 1.0; break;
        case MacLCStreamSourceCam:       sc += 0.0; break;
        case MacLCStreamSourceUnknown:   sc += 0.0; break;
    }

    if (_sizeBytes > 0) {
        double gb = (double)_sizeBytes / (1024.0 * 1024.0 * 1024.0);
        sc += 1.0 / (1.0 + gb);
    }
    _score = sc;
}

#pragma mark - Display Names & Formatter Class Methods

+ (NSString *)nameForResolution:(MacLCStreamResolution)resolution
{
    switch (resolution) {
        case MacLCStreamResolution4K:      return @"4K";
        case MacLCStreamResolution1080p:   return @"1080p";
        case MacLCStreamResolution720p:    return @"720p";
        case MacLCStreamResolutionSD:      return @"SD";
        case MacLCStreamResolutionUnknown: return @"Unknown";
    }
}

+ (NSString *)nameForDynamicRange:(MacLCStreamDynamicRange)dynamicRange
{
    switch (dynamicRange) {
        case MacLCStreamDynamicRangeDolbyVision: return @"Dolby Vision";
        case MacLCStreamDynamicRangeHDR10Plus:   return @"HDR10+";
        case MacLCStreamDynamicRangeHDR10:       return @"HDR10";
        case MacLCStreamDynamicRangeHDR:         return @"HDR";
        case MacLCStreamDynamicRangeHLG:         return @"HLG";
        case MacLCStreamDynamicRangeSDR:         return @"SDR";
        case MacLCStreamDynamicRangeUnknown:     return @"Unknown";
    }
}

+ (NSString *)nameForSource:(MacLCStreamSource)source
{
    switch (source) {
        case MacLCStreamSourceRemux:     return @"Blu-ray Remux";
        case MacLCStreamSourceBluRay:    return @"Blu-ray";
        case MacLCStreamSourceWebDL:     return @"Web Download";
        case MacLCStreamSourceWebRip:    return @"Web Rip";
        case MacLCStreamSourceHDTV:      return @"TV Recording";
        case MacLCStreamSourceDVD:       return @"DVD";
        case MacLCStreamSourceScreener:  return @"Screener";
        case MacLCStreamSourceTelesync:  return @"Telesync";
        case MacLCStreamSourceCam:       return @"Cinema Recording";
        case MacLCStreamSourceUnknown:   return @"Unknown";
    }
}

+ (NSString *)nameForVideoCodec:(MacLCStreamVideoCodec)codec
{
    switch (codec) {
        case MacLCStreamVideoCodecH264:    return @"H.264";
        case MacLCStreamVideoCodecHEVC:    return @"HEVC";
        case MacLCStreamVideoCodecAV1:     return @"AV1";
        case MacLCStreamVideoCodecOther:   return @"Other";
        case MacLCStreamVideoCodecUnknown: return @"Unknown";
    }
}

+ (NSString *)nameForVerdict:(MacLCStreamVerdict)verdict
{
    switch (verdict) {
        case MacLCStreamVerdictGreat:   return @"Great";
        case MacLCStreamVerdictGood:    return @"Good";
        case MacLCStreamVerdictOkay:    return @"Okay";
        case MacLCStreamVerdictPoor:    return @"Poor";
        case MacLCStreamVerdictUnknown: return @"Unknown";
    }
}

+ (NSString *)nameForHealth:(MacLCStreamHealth)health
{
    switch (health) {
        case MacLCStreamHealthExcellent: return @"Excellent connection";
        case MacLCStreamHealthGood:      return @"Good connection";
        case MacLCStreamHealthFair:      return @"Fair connection";
        case MacLCStreamHealthWeak:      return @"Weak connection";
        case MacLCStreamHealthNone:      return @"No connection";
        case MacLCStreamHealthUnknown:   return @"Unknown connection";
    }
}

+ (NSString *)displayNameForLanguage:(NSString *)code
{
    if (code.length == 0) return @"";
    NSString *name = [[NSLocale currentLocale] localizedStringForLanguageCode:code];
    if (name.length > 0) {
        return [name capitalizedStringWithLocale:[NSLocale currentLocale]];
    }
    return [code uppercaseString];
}

+ (NSString *)displaySize:(unsigned long long)bytes
{
    if (bytes == 0) return @"0 B";
    return [NSByteCountFormatter stringFromByteCount:(long long)bytes
                                          countStyle:NSByteCountFormatterCountStyleFile];
}

@end

#pragma mark - MacLCStreamChoice Implementation

@implementation MacLCStreamChoice

- (instancetype)initWithStream:(MacLCAddonStream *)stream
{
    self = [super init];
    if (self) {
        _stream = stream;
        _facts = [MacLCStreamFacts factsForStream:stream];
        _identifier = [stream.MRL copy] ?: @"";
    }
    return self;
}

- (instancetype)initWithFacts:(MacLCStreamFacts *)facts identifier:(NSString *)identifier
{
    self = [super init];
    if (self) {
        _stream = nil;
        _facts = facts;
        _identifier = [identifier copy] ?: @"";
    }
    return self;
}

@end

#pragma mark - MacLCStreamFilter Implementation

@implementation MacLCStreamFilter

- (instancetype)init
{
    self = [super init];
    if (self) {
        _language = nil;
        _minimumResolution = MacLCStreamResolutionUnknown;
        _picture = MacLCStreamPictureAny;
        _bestSoundOnly = NO;
        _hidePoor = YES;
        _sortOrder = MacLCStreamSortRecommended;
    }
    return self;
}

- (id)copyWithZone:(nullable NSZone *)zone
{
    MacLCStreamFilter *copy = [[[self class] allocWithZone:zone] init];
    copy.language = self.language;
    copy.minimumResolution = self.minimumResolution;
    copy.picture = self.picture;
    copy.bestSoundOnly = self.bestSoundOnly;
    copy.hidePoor = self.hidePoor;
    copy.sortOrder = self.sortOrder;
    return copy;
}

- (NSArray<MacLCStreamChoice *> *)apply:(NSArray<MacLCStreamChoice *> *)choices
{
    NSMutableArray<MacLCStreamChoice *> *filtered = [NSMutableArray array];
    for (MacLCStreamChoice *choice in choices) {
        MacLCStreamFacts *facts = choice.facts;

        if (self.hidePoor && facts.verdict == MacLCStreamVerdictPoor) {
            continue;
        }

        if (self.minimumResolution != MacLCStreamResolutionUnknown) {
            if (facts.resolution < self.minimumResolution) {
                continue;
            }
        }

        if (self.picture != MacLCStreamPictureAny) {
            switch (self.picture) {
                case MacLCStreamPictureHDR:
                    if (facts.dynamicRange < MacLCStreamDynamicRangeHLG) {
                        continue;
                    }
                    break;
                case MacLCStreamPictureDolbyVision:
                    if (facts.dynamicRange != MacLCStreamDynamicRangeDolbyVision &&
                        ![facts.hdrFormats containsObject:@"Dolby Vision"]) {
                        continue;
                    }
                    break;
                case MacLCStreamPictureSDR:
                    if (facts.dynamicRange != MacLCStreamDynamicRangeSDR &&
                        facts.dynamicRange != MacLCStreamDynamicRangeUnknown) {
                        continue;
                    }
                    break;
                case MacLCStreamPictureAny:
                    break;
            }
        }

        if (self.bestSoundOnly) {
            BOOL hasBest = NO;
            for (MacLCStreamAudio *aud in facts.audio) {
                if (aud.isLossless || aud.isImmersive) {
                    hasBest = YES;
                    break;
                }
            }
            if (!hasBest) {
                continue;
            }
        }

        if (self.language != nil) {
            BOOL hasNamed = [facts.languages containsObject:self.language];
            BOOL isMulti = facts.isMultiLanguage;
            if (!hasNamed && !isMulti) {
                continue;
            }
        }

        [filtered addObject:choice];
    }

    [filtered sortWithOptions:NSSortStable usingComparator:^NSComparisonResult(MacLCStreamChoice *a, MacLCStreamChoice *b) {
        if (self.language != nil) {
            BOOL aNamed = [a.facts.languages containsObject:self.language];
            BOOL bNamed = [b.facts.languages containsObject:self.language];
            if (aNamed && !bNamed) return NSOrderedAscending;
            if (!aNamed && bNamed) return NSOrderedDescending;
        }

        switch (self.sortOrder) {
            case MacLCStreamSortRecommended: {
                if (a.facts.score > b.facts.score) return NSOrderedAscending;
                if (a.facts.score < b.facts.score) return NSOrderedDescending;
                return NSOrderedSame;
            }
            case MacLCStreamSortMostShared: {
                BOOL aDebrid = (a.facts.debridService != nil);
                BOOL bDebrid = (b.facts.debridService != nil);
                if (aDebrid && !bDebrid) return NSOrderedAscending;
                if (!aDebrid && bDebrid) return NSOrderedDescending;
                if (aDebrid && bDebrid) return NSOrderedSame;

                NSInteger aSeeds = a.facts.seeders;
                NSInteger bSeeds = b.facts.seeders;
                BOOL aKnown = (aSeeds >= 0);
                BOOL bKnown = (bSeeds >= 0);
                if (aKnown && !bKnown) return NSOrderedAscending;
                if (!aKnown && bKnown) return NSOrderedDescending;
                if (!aKnown && !bKnown) return NSOrderedSame;

                if (aSeeds > bSeeds) return NSOrderedAscending;
                if (aSeeds < bSeeds) return NSOrderedDescending;
                return NSOrderedSame;
            }
            case MacLCStreamSortHighestQuality: {
                if (a.facts.resolution > b.facts.resolution) return NSOrderedAscending;
                if (a.facts.resolution < b.facts.resolution) return NSOrderedDescending;

                if (a.facts.dynamicRange > b.facts.dynamicRange) return NSOrderedAscending;
                if (a.facts.dynamicRange < b.facts.dynamicRange) return NSOrderedDescending;

                NSInteger aSourceRank = a.facts.source == MacLCStreamSourceUnknown ? 100 : a.facts.source;
                NSInteger bSourceRank = b.facts.source == MacLCStreamSourceUnknown ? 100 : b.facts.source;
                if (aSourceRank < bSourceRank) return NSOrderedAscending;
                if (aSourceRank > bSourceRank) return NSOrderedDescending;

                BOOL aBestAudio = NO, bBestAudio = NO;
                for (MacLCStreamAudio *aud in a.facts.audio) {
                    if (aud.isLossless || aud.isImmersive) { aBestAudio = YES; break; }
                }
                for (MacLCStreamAudio *aud in b.facts.audio) {
                    if (aud.isLossless || aud.isImmersive) { bBestAudio = YES; break; }
                }
                if (aBestAudio && !bBestAudio) return NSOrderedAscending;
                if (!aBestAudio && bBestAudio) return NSOrderedDescending;

                if (a.facts.score > b.facts.score) return NSOrderedAscending;
                if (a.facts.score < b.facts.score) return NSOrderedDescending;
                return NSOrderedSame;
            }
            case MacLCStreamSortSmallest: {
                unsigned long long aSize = a.facts.sizeBytes;
                unsigned long long bSize = b.facts.sizeBytes;
                BOOL aKnown = (aSize > 0);
                BOOL bKnown = (bSize > 0);
                if (aKnown && !bKnown) return NSOrderedAscending;
                if (!aKnown && bKnown) return NSOrderedDescending;
                if (!aKnown && !bKnown) return NSOrderedSame;

                if (aSize < bSize) return NSOrderedAscending;
                if (aSize > bSize) return NSOrderedDescending;
                return NSOrderedSame;
            }
        }
        return NSOrderedSame;
    }];

    return [filtered copy];
}

- (NSUInteger)hiddenCountIn:(NSArray<MacLCStreamChoice *> *)choices
{
    NSArray<MacLCStreamChoice *> *visible = [self apply:choices];
    return choices.count >= visible.count ? (choices.count - visible.count) : 0;
}

+ (NSArray<NSString *> *)languagesIn:(NSArray<MacLCStreamChoice *> *)choices
                              counts:(NSDictionary<NSString *, NSNumber *> * _Nullable * _Nullable)counts
{
    NSMutableDictionary<NSString *, NSNumber *> *dict = [NSMutableDictionary dictionary];
    for (MacLCStreamChoice *choice in choices) {
        NSSet<NSString *> *choiceLangs = [NSSet setWithArray:choice.facts.languages];
        for (NSString *lang in choiceLangs) {
            dict[lang] = @(dict[lang].unsignedIntegerValue + 1);
        }
    }
    if (counts != NULL) {
        *counts = [dict copy];
    }
    NSArray<NSString *> *allKeys = dict.allKeys;
    NSArray<NSString *> *sorted = [allKeys sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        NSUInteger countA = dict[a].unsignedIntegerValue;
        NSUInteger countB = dict[b].unsignedIntegerValue;
        if (countA > countB) return NSOrderedAscending;
        if (countA < countB) return NSOrderedDescending;
        NSString *nameA = [MacLCStreamFacts displayNameForLanguage:a];
        NSString *nameB = [MacLCStreamFacts displayNameForLanguage:b];
        return [nameA localizedCaseInsensitiveCompare:nameB];
    }];
    return sorted;
}

+ (NSArray<NSNumber *> *)resolutionsIn:(NSArray<MacLCStreamChoice *> *)choices
{
    NSMutableSet<NSNumber *> *set = [NSMutableSet set];
    for (MacLCStreamChoice *choice in choices) {
        if (choice.facts.resolution != MacLCStreamResolutionUnknown) {
            [set addObject:@(choice.facts.resolution)];
        }
    }
    NSArray<NSNumber *> *all = set.allObjects;
    return [all sortedArrayUsingComparator:^NSComparisonResult(NSNumber *a, NSNumber *b) {
        return [b compare:a];
    }];
}

+ (nullable NSString *)preferredLanguageIn:(NSArray<MacLCStreamChoice *> *)choices
{
    NSMutableSet<NSString *> *present = [NSMutableSet set];
    for (MacLCStreamChoice *choice in choices) {
        [present addObjectsFromArray:choice.facts.languages];
    }
    for (NSString *pref in [NSLocale preferredLanguages]) {
        NSString *code = [[NSLocale localeWithLocaleIdentifier:pref] objectForKey:NSLocaleLanguageCode];
        if (code.length == 0) {
            NSArray<NSString *> *parts = [pref componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"-_"]];
            code = parts.firstObject.lowercaseString;
        }
        if (code.length > 0 && [present containsObject:code]) {
            return code;
        }
    }
    return nil;
}

+ (nullable MacLCStreamChoice *)bestMatchIn:(NSArray<MacLCStreamChoice *> *)choices
{
    if (choices.count < 2) {
        return nil;
    }
    MacLCStreamChoice *best = nil;
    double highestScore = -INFINITY;
    for (MacLCStreamChoice *choice in choices) {
        MacLCStreamFacts *facts = choice.facts;
        if (facts.verdict < MacLCStreamVerdictOkay) {
            continue;
        }
        if (facts.score > highestScore) {
            highestScore = facts.score;
            best = choice;
        }
    }
    return best;
}

+ (NSArray<NSString *> *)reasonsForBestMatch:(MacLCStreamChoice *)choice
                                    language:(nullable NSString *)language
{
    if (!choice) {
        return @[];
    }
    NSMutableArray<NSString *> *reasons = [NSMutableArray array];
    MacLCStreamFacts *facts = choice.facts;

    // 1. Picture reason
    if (facts.resolution == MacLCStreamResolution4K) {
        if (facts.dynamicRange == MacLCStreamDynamicRangeDolbyVision) {
            [reasons addObject:@"Sharp 4K picture with Dolby Vision"];
        } else if (facts.dynamicRange == MacLCStreamDynamicRangeHDR10Plus) {
            [reasons addObject:@"Sharp 4K picture with HDR10+"];
        } else if (facts.dynamicRange == MacLCStreamDynamicRangeHDR10) {
            [reasons addObject:@"Sharp 4K picture with HDR10"];
        } else if (facts.dynamicRange == MacLCStreamDynamicRangeHDR) {
            [reasons addObject:@"Sharp 4K picture with HDR"];
        } else {
            [reasons addObject:@"Sharp 4K picture"];
        }
    } else if (facts.resolution == MacLCStreamResolution1080p) {
        if (facts.dynamicRange == MacLCStreamDynamicRangeDolbyVision) {
            [reasons addObject:@"1080p HD picture with Dolby Vision"];
        } else if (facts.dynamicRange >= MacLCStreamDynamicRangeHDR) {
            [reasons addObject:@"1080p HD picture with HDR"];
        } else {
            [reasons addObject:@"Clear 1080p HD picture"];
        }
    }

    // 2. Sound reason
    if (facts.audio.count > 0) {
        MacLCStreamAudio *first = facts.audio.firstObject;
        if ([first.format isEqualToString:@"Dolby Atmos"]) {
            [reasons addObject:@"Dolby Atmos sound"];
        } else if ([first.format isEqualToString:@"DTS:X"]) {
            [reasons addObject:@"DTS:X immersive sound"];
        } else if ([first.format isEqualToString:@"Dolby TrueHD"]) {
            [reasons addObject:@"Dolby TrueHD lossless sound"];
        } else if ([first.format isEqualToString:@"DTS-HD MA"]) {
            [reasons addObject:@"DTS-HD Master Audio sound"];
        } else if (first.isLossless) {
            [reasons addObject:@"Lossless audio"];
        }
    }

    // 3. Sharing / Health reason
    if (facts.debridService != nil) {
        [reasons addObject:@"Plays instantly from debrid cloud"];
    } else if (facts.health == MacLCStreamHealthExcellent) {
        [reasons addObject:@"Many people sharing: starts quickly"];
    } else if (facts.health == MacLCStreamHealthGood) {
        [reasons addObject:@"Healthy connection with plenty of seeders"];
    }

    // 4. Language reason
    if (language.length > 0 && [facts.languages containsObject:language]) {
        NSString *langName = [MacLCStreamFacts displayNameForLanguage:language];
        [reasons addObject:[NSString stringWithFormat:@"In %@", langName]];
    }

    if (reasons.count > 3) {
        return [reasons subarrayWithRange:NSMakeRange(0, 3)];
    }
    return [reasons copy];
}

@end
