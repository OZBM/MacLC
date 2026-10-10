/*****************************************************************************
 * MacLCStreamFacts.h: what a stream offered by an add-on really is (picture,
 * sound, languages, size, people sharing it), read from its texts
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

/* Foundation only (unit tested in tests/MacLCStreamFactsTest.m).
 *
 * Add-ons describe a stream in free text. Torrentio, the most common one,
 * writes (real responses, .agents/reports/discovery-fixtures/):
 *   name  "Torrentio\n4k DV | HDR10"   ("[RD+] Torrentio\n1080p" when cached
 *                                        on a debrid service)
 *   title "<release name>\n[<file in the pack>\n]👤 39 💾 4.35 GB ⚙️ YTS
 *          [\nMulti Subs / 🇬🇧 / 🇷🇺]"
 *   behaviorHints.filename "Night.Of.The.Living.Dead.1968.2160p...mkv"
 * Other add-ons write less; every fact is optional and unknown stays unknown
 * (never guessed: a missing language is not "English"). */
#import <Foundation/Foundation.h>

@class MacLCAddonStream;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, MacLCStreamResolution) {
    MacLCStreamResolutionUnknown = 0,
    MacLCStreamResolutionSD,      /* 480p, 576p, DVD */
    MacLCStreamResolution720p,
    MacLCStreamResolution1080p,
    MacLCStreamResolution4K,      /* 2160p, UHD */
};

/// Best dynamic range the file carries (Dolby Vision files usually carry an
/// HDR10 base layer too: both flags are kept in hdrFormats).
typedef NS_ENUM(NSInteger, MacLCStreamDynamicRange) {
    MacLCStreamDynamicRangeUnknown = 0,   /* nothing said: almost always SDR */
    MacLCStreamDynamicRangeSDR,           /* said explicitly */
    MacLCStreamDynamicRangeHLG,
    MacLCStreamDynamicRangeHDR,           /* "HDR" without kind */
    MacLCStreamDynamicRangeHDR10,
    MacLCStreamDynamicRangeHDR10Plus,
    MacLCStreamDynamicRangeDolbyVision,
};

/// Where the copy comes from, best to worst.
typedef NS_ENUM(NSInteger, MacLCStreamSource) {
    MacLCStreamSourceUnknown = 0,
    MacLCStreamSourceRemux,       /* REMUX, BDREMUX: the disc, untouched */
    MacLCStreamSourceBluRay,      /* BluRay, BDRip, BRRip, UHD BluRay */
    MacLCStreamSourceWebDL,       /* WEB-DL, WEB (store download) */
    MacLCStreamSourceWebRip,      /* WEBRip (screen capture of a stream) */
    MacLCStreamSourceHDTV,        /* HDTV, PDTV, DSR */
    MacLCStreamSourceDVD,         /* DVDRip, DVD5/9 */
    MacLCStreamSourceScreener,    /* SCR, DVDSCR, R5 */
    MacLCStreamSourceTelesync,    /* TS, HDTS, TC, telecine */
    MacLCStreamSourceCam,         /* CAM, HDCAM, CAMRip */
};

typedef NS_ENUM(NSInteger, MacLCStreamVideoCodec) {
    MacLCStreamVideoCodecUnknown = 0,
    MacLCStreamVideoCodecH264,    /* x264, H.264, AVC */
    MacLCStreamVideoCodecHEVC,    /* x265, H.265, HEVC */
    MacLCStreamVideoCodecAV1,
    MacLCStreamVideoCodecOther,   /* XviD, DivX, VP9, MPEG-2 */
};

/// Overall verdict shown to people, from the facts (see -verdict).
typedef NS_ENUM(NSInteger, MacLCStreamVerdict) {
    MacLCStreamVerdictUnknown = 0, /* too little is known */
    MacLCStreamVerdictPoor,        /* recorded in a cinema, or nobody sharing */
    MacLCStreamVerdictOkay,
    MacLCStreamVerdictGood,
    MacLCStreamVerdictGreat,
};

/// Connection health of a torrent, from the number of people sharing it.
typedef NS_ENUM(NSInteger, MacLCStreamHealth) {
    MacLCStreamHealthUnknown = 0,  /* not a torrent, or not said */
    MacLCStreamHealthNone,         /* 0 */
    MacLCStreamHealthWeak,         /* 1-4: may stop and start */
    MacLCStreamHealthFair,         /* 5-19 */
    MacLCStreamHealthGood,         /* 20-99 */
    MacLCStreamHealthExcellent,    /* 100 and more */
};

/// One audio track family heard of in the texts.
@interface MacLCStreamAudio : NSObject
/// "Dolby Atmos", "Dolby TrueHD", "DTS:X", "DTS-HD MA", "DTS", "Dolby Digital
/// Plus", "Dolby Digital", "AAC", "FLAC", "Opus", "PCM" (LPCM), "MP3".
@property (readonly, copy) NSString *format;
/// "7.1", "5.1", "2.0", "1.0" or nil.
@property (readonly, copy, nullable) NSString *channels;
/// Atmos, TrueHD, DTS:X, DTS-HD MA, FLAC, PCM.
@property (readonly, getter=isLossless) BOOL lossless;
/// Atmos, DTS:X (sound above as well as around).
@property (readonly, getter=isImmersive) BOOL immersive;
- (instancetype)initWithFormat:(NSString *)format channels:(nullable NSString *)channels;
@end

@interface MacLCStreamFacts : NSObject

/// Reads every text of the stream: label (name), headline + details (title),
/// filename; the add-on name is not read.
+ (instancetype)factsForStream:(MacLCAddonStream *)stream;
/// The same from raw texts (tests): name, title (newlines kept), filename.
+ (instancetype)factsForName:(nullable NSString *)name
                       title:(nullable NSString *)title
                    filename:(nullable NSString *)filename;

@property (readonly) MacLCStreamResolution resolution;
@property (readonly) MacLCStreamDynamicRange dynamicRange;
/// Every HDR kind named, best first: @[@"Dolby Vision", @"HDR10"].
@property (readonly, copy) NSArray<NSString *> *hdrFormats;
@property (readonly) BOOL tenBit;
@property (readonly) MacLCStreamVideoCodec videoCodec;
@property (readonly) MacLCStreamSource source;
/// Best first (Atmos before TrueHD before DTS-HD MA ... before AAC);
/// "TrueHD Atmos 7.1" gives one entry, format "Dolby Atmos", channels "7.1".
@property (readonly, copy) NSArray<MacLCStreamAudio *> *audio;
/// ISO 639-1 codes of the spoken languages, in the order found, no
/// duplicates: from flags (🇬🇧 → en, 🇺🇸 → en, 🇫🇷 → fr, 🇪🇸/🇲🇽 → es, 🇮🇹 → it,
/// 🇩🇪 → de, 🇵🇹/🇧🇷 → pt, 🇷🇺 → ru, 🇯🇵 → ja, 🇰🇷 → ko, 🇨🇳/🇹🇼 → zh, 🇮🇳 → hi,
/// 🇳🇱 → nl, 🇵🇱 → pl, 🇹🇷 → tr, 🇸🇦 → ar, 🇸🇪 → sv, 🇩🇰 → da, 🇳🇴 → no,
/// 🇫🇮 → fi, 🇨🇿 → cs, 🇭🇺 → hu, 🇬🇷 → el, 🇮🇱 → he, 🇹🇭 → th, 🇺🇦 → uk,
/// 🇷🇴 → ro, 🇻🇳 → vi, 🇮🇩 → id) and words of the release name (ENG/English,
/// FRENCH/TRUEFRENCH/VFF/VFQ/VF2 → fr, ITA/Italian, SPA/Spanish/Castellano/
/// Latino → es, GER/German/Deutsch → de, RUS → ru, JAP/JPN/Japanese → ja,
/// KOR/Korean → ko, HIN/Hindi → hi, POR/Portuguese → pt, ...). Words that
/// are also ordinary words are only read in the release-name token stream
/// (separated by . _ - space [ ] ( )), never inside other words.
/// "VOSTFR" and "SUBFRENCH" mean French SUBTITLES: they add "fr" to
/// subtitleLanguages, not here.
@property (readonly, copy) NSArray<NSString *> *languages;
/// MULTI, "Multi Audio", "Dual Audio", DUAL: several languages, not all named.
@property (readonly, getter=isMultiLanguage) BOOL multiLanguage;
/// ISO 639-1 codes of subtitle languages named (VOSTFR → fr, "Sub Ita" → it,
/// "Eng Subs" → en); "Multi Subs" sets hasMultipleSubtitles.
@property (readonly, copy) NSArray<NSString *> *subtitleLanguages;
@property (readonly) BOOL hasMultipleSubtitles;
/// Bytes, from "💾 4.35 GB" (or "Size: ..."), 1 GB = 1024³ as Torrentio
/// prints; 0 when unknown.
@property (readonly) unsigned long long sizeBytes;
/// "👤 39": people sharing the whole file (seeders); -1 when unknown.
@property (readonly) NSInteger seeders;
/// "⚙️ YTS": the site the torrent was found on; nil when unknown.
@property (readonly, copy, nullable) NSString *provider;
/// "[RD+]" etc.: the stream is cached on a debrid service (plays at full
/// speed without peers); its name ("Real-Debrid") or nil.
@property (readonly, copy, nullable) NSString *debridService;
/// A torrent (the stream has an info hash or 👤), as opposed to a link.
@property (readonly, getter=isTorrent) BOOL torrent;
/// The release name: first line of the title (else the filename), without
/// the extension; never empty when any text exists.
@property (readonly, copy) NSString *releaseName;
/// A season pack or a collection (the title's second line names a file
/// inside it): the stream plays one file of several.
@property (readonly, getter=isPack) BOOL pack;
/// "REMASTERED", "CRITERION", "EXTENDED", "Director's Cut", "IMAX",
/// "UNRATED", "UPSCALED" (AI upscale: not a true 4K master), in that form.
@property (readonly, copy) NSArray<NSString *> *editionNotes;

/// From seeders (debrid: Excellent whatever the seeders).
@property (readonly) MacLCStreamHealth health;
/// Poor: CAM / Telesync / Screener source, or a torrent with 0 seeders.
/// Great: 1080p or 4K, Remux/BluRay/WEB-DL, health Good or better (or
/// debrid). Good: 1080p or better from a known good source with health
/// Fair+, or 720p+ with health Good+. Okay: the rest that plays. Unknown:
/// nothing known but a name.
@property (readonly) MacLCStreamVerdict verdict;
/// Ranking used to sort and to pick "Best Match": higher is better; health
/// weighs most (a beautiful file nobody shares will not play), then
/// verdict, resolution, dynamic range, audio, then smaller size at equal
/// quality. Deterministic: equal facts give equal scores.
@property (readonly) double score;
/// Short reasons for the verdict, plain words, most important first, at most
/// 3: @"Recorded in a cinema", @"Nobody is sharing it right now",
/// @"Upscaled, not a true 4K master", @"Very few people sharing: may pause".
@property (readonly, copy) NSArray<NSString *> *cautions;

/// Display names (English, as the rest of the UI): "4K", "1080p", "720p",
/// "SD"; "Dolby Vision", "HDR10+", "HDR10", "HDR", "HLG", "SDR";
/// "Blu-ray Remux", "Blu-ray", "Web Download", "Web Rip", "TV Recording",
/// "DVD", "Screener", "Telesync", "Cinema Recording"; "H.264", "HEVC", "AV1".
+ (NSString *)nameForResolution:(MacLCStreamResolution)resolution;
+ (NSString *)nameForDynamicRange:(MacLCStreamDynamicRange)dynamicRange;
+ (NSString *)nameForSource:(MacLCStreamSource)source;
+ (NSString *)nameForVideoCodec:(MacLCStreamVideoCodec)codec;
+ (NSString *)nameForVerdict:(MacLCStreamVerdict)verdict;   /* "Great", ... "Poor" */
+ (NSString *)nameForHealth:(MacLCStreamHealth)health;      /* "Excellent connection", ... "No connection" */
/// Localized language name in the current locale ("English", "Français"
/// shown as the system names it), from an ISO 639-1 code.
+ (NSString *)displayNameForLanguage:(NSString *)code;
/// "4.4 GB" (NSByteCountFormatter, file style).
+ (NSString *)displaySize:(unsigned long long)bytes;

@end

#pragma mark - Filtering and ranking

typedef NS_ENUM(NSInteger, MacLCStreamSortOrder) {
    MacLCStreamSortRecommended = 0, /* score, high first */
    MacLCStreamSortMostShared,      /* seeders high first (debrid first, unknown last) */
    MacLCStreamSortHighestQuality,  /* resolution, dynamic range, source, audio, then score */
    MacLCStreamSortSmallest,        /* size small first, unknown last */
};

typedef NS_ENUM(NSInteger, MacLCStreamPictureFilter) {
    MacLCStreamPictureAny = 0,
    MacLCStreamPictureHDR,          /* HLG and better */
    MacLCStreamPictureDolbyVision,
    MacLCStreamPictureSDR,          /* SDR or nothing said */
};

/// One stream with its facts, the unit the picker shows.
@interface MacLCStreamChoice : NSObject
- (instancetype)initWithStream:(MacLCAddonStream *)stream;
/// For tests: facts without a stream object.
- (instancetype)initWithFacts:(MacLCStreamFacts *)facts identifier:(NSString *)identifier;
@property (readonly, nullable) MacLCAddonStream *stream;
@property (readonly) MacLCStreamFacts *facts;
/// stream.MRL, or the test identifier.
@property (readonly, copy) NSString *identifier;
@end

/// What people chose in the picker's filter bar; plain values, copied.
@interface MacLCStreamFilter : NSObject <NSCopying>
/// ISO 639-1; nil = any. A choice matches when facts.languages contains it,
/// or facts.multiLanguage is set (it may contain it: kept, ranked after).
@property (nonatomic, copy, nullable) NSString *language;
/// Unknown = any; else at least this resolution.
@property (nonatomic) MacLCStreamResolution minimumResolution;
@property (nonatomic) MacLCStreamPictureFilter picture;
/// Only choices with lossless or immersive audio.
@property (nonatomic) BOOL bestSoundOnly;
/// Hide verdict Poor (default YES).
@property (nonatomic) BOOL hidePoor;
@property (nonatomic) MacLCStreamSortOrder sortOrder;

/// Filtered and sorted; stable for equal keys (keeps input order).
- (NSArray<MacLCStreamChoice *> *)apply:(NSArray<MacLCStreamChoice *> *)choices;
/// How many of choices the filter hides (for "3 hidden").
- (NSUInteger)hiddenCountIn:(NSArray<MacLCStreamChoice *> *)choices;

/// Languages present, most frequent first then by name: code → count. A
/// multi-language choice counts for none (it has no named language).
+ (NSArray<NSString *> *)languagesIn:(NSArray<MacLCStreamChoice *> *)choices
                              counts:(NSDictionary<NSString *, NSNumber *> * _Nullable * _Nullable)counts;
/// Resolutions present, best first.
+ (NSArray<NSNumber *> *)resolutionsIn:(NSArray<MacLCStreamChoice *> *)choices;
/// The language to preselect: the first of NSLocale.preferredLanguages
/// (639-1 part) present in choices, else nil (any).
+ (nullable NSString *)preferredLanguageIn:(NSArray<MacLCStreamChoice *> *)choices;
/// The choice "Best Match" names: the highest score among choices whose
/// verdict is Okay or better; nil when there are fewer than 2 choices or
/// none qualifies.
+ (nullable MacLCStreamChoice *)bestMatchIn:(NSArray<MacLCStreamChoice *> *)choices;
/// Plain reasons the best match was chosen, at most 3, e.g. "Sharp 4K
/// picture with Dolby Vision", "Dolby Atmos sound", "Many people sharing:
/// starts quickly", "In English".
+ (NSArray<NSString *> *)reasonsForBestMatch:(MacLCStreamChoice *)choice
                                    language:(nullable NSString *)language;
@end

NS_ASSUME_NONNULL_END
