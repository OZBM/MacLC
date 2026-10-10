/*****************************************************************************
 * MacLCWatchDiscovery.h: what Watch offers beyond the add-ons' own shelves —
 * The Edit (collections renewed every two weeks), streaming services as
 * filters, genres
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

/* Foundation only (no AppKit: colors are names the views map), unit tested in
 * tests/MacLCWatchDiscoveryTest.m.
 *
 * MacLC stays a host: titles still come from add-ons. The Edit's lists are
 * MacLC's own editorial choice (title + year), matched against the installed
 * catalog add-ons (Cinemeta by default) with their search; the services
 * filter reads the catalogs of the community "Streaming Catalogs" add-on,
 * which people install from the services sheet (MacLC builds its configured
 * address: the add-on is still theirs, removable in Settings ▸ Add-ons). */
#import <Foundation/Foundation.h>

@class MacLCAddon;
@class MacLCAddonItem;
@class MacLCAddonRequest;
@class MacLCAddonTitleCatalog;

NS_ASSUME_NONNULL_BEGIN

#pragma mark - The Edit

/// One title of a collection as written in the pool.
@interface MacLCWatchCollectionEntry : NSObject
@property (readonly, copy) NSString *title;
@property (readonly) NSInteger year;
/// "movie" or "series".
@property (readonly, copy) NSString *type;
@end

@interface MacLCWatchCollection : NSObject
@property (readonly, copy) NSString *identifier;
@property (readonly, copy) NSString *title;
@property (readonly, copy) NSString *subtitle;
/// "award", "director", "studio", "theme".
@property (readonly, copy) NSString *kind;
/// SF Symbol name.
@property (readonly, copy) NSString *symbolName;
/// "red" … "brown" (system color names, mapped by the views).
@property (readonly, copy) NSString *tintName;
@property (readonly, nullable) NSURL *sourceURL;
@property (readonly, copy) NSArray<MacLCWatchCollectionEntry *> *entries;
/// "movie" when every entry is a movie, "series" when every one is a
/// series, nil when mixed.
@property (readonly, copy, nullable) NSString *mediaType;
@end

#pragma mark - Services

/// A streaming service the Streaming Catalogs add-on knows.
@interface MacLCWatchService : NSObject
/// The add-on's code: "nfx", "atp", "dnp", "amp", "hbm", "hlu", "pmp",
/// "pcp", "cru", "mbi", "crc", "cpd", "sst", "bbc", "stz", "shd", "nfk"…
@property (readonly, copy) NSString *code;
/// "Netflix", "Apple TV+", "Disney+", "Prime Video", "HBO Max", "Hulu",
/// "Paramount+", "Peacock", "Crunchyroll", "MUBI", "Criterion Channel",
/// "Canal+", "SkyShowtime", "BBC iPlayer", "Starz", "Shudder", "Netflix Kids".
@property (readonly, copy) NSString *name;
/// "movie", "series" or both.
@property (readonly, copy) NSArray<NSString *> *types;
@end

#pragma mark - Discovery

/// Posted on the main queue when the services add-on is installed, changed
/// or removed, or when a collection finished resolving.
extern NSNotificationName const MacLCWatchDiscoveryDidChangeNotification;

@interface MacLCWatchDiscovery : NSObject
@property (class, readonly) MacLCWatchDiscovery *sharedDiscovery;

/// The built-in pool (MacLCWatchCollectionsPool.m, generated from
/// .agents/reports/discovery-fixtures/edit-pool.json), parsed once.
@property (readonly, copy) NSArray<MacLCWatchCollection *> *pool;
/// Parses a pool JSON ({"version":1,"collections":[...]}); invalid entries
/// are skipped, nil only when the data is not such a JSON (tests).
+ (nullable NSArray<MacLCWatchCollection *> *)collectionsFromData:(NSData *)data;

/// The Edit for a date: count collections of mediaType (nil: any, mixed
/// included; "movie"/"series": that type only, mixed ones excluded),
/// chosen deterministically for the two-week period containing date
/// (periods start on Mondays, 00:00 local time, the first on 2026-01-05);
/// consecutive periods share no collection while the pool allows it.
- (NSArray<MacLCWatchCollection *> *)editForDate:(NSDate *)date
                                       mediaType:(nullable NSString *)mediaType
                                           count:(NSUInteger)count;
/// Start of the next period after date (for "New collections on Oct 20").
- (NSDate *)nextEditDateAfter:(NSDate *)date;

/// Matches every entry against the installed catalog add-ons' search
/// (MacLCAddonStore searchTitles:), at most 4 searches at a time: a result
/// matches when its type is the entry's, its name equals the title ignoring
/// case, diacritics and punctuation (else contains it), and its releaseInfo
/// starts with the year (±1 accepted when nothing exact). Unmatched entries
/// are dropped. Results keep the pool's order and are cached in memory and
/// in ~/Library/Caches/org.maclc.MacLC/Watch/collections.json (meta JSON of
/// each matched item, 30 days); a cached collection completes at once.
/// completion: main queue.
- (MacLCAddonRequest *)resolveCollection:(MacLCWatchCollection *)collection
                              completion:(void (^)(NSArray<MacLCAddonItem *> *items))completion;
/// The matching rule of resolveCollection:, on one search's results
/// (exposed for the tests): nil when nothing matches.
+ (nullable MacLCAddonItem *)matchEntry:(MacLCWatchCollectionEntry *)entry
                                inItems:(NSArray<MacLCAddonItem *> *)items;
/// What resolveCollection: has, without fetching (nil: not resolved yet).
- (nullable NSArray<MacLCAddonItem *> *)resolvedItemsForCollection:(MacLCWatchCollection *)collection;

/// Every service known, in the order above.
@property (class, readonly, copy) NSArray<MacLCWatchService *> *knownServices;
+ (nullable MacLCWatchService *)serviceForCode:(NSString *)code;
/// The installed Streaming Catalogs add-on (manifest id
/// "pw.ers.netflix-catalog"), or nil.
@property (readonly, nullable) MacLCAddon *servicesAddon;
/// Services whose catalogs the installed add-on exposes, in knownServices
/// order (empty without the add-on).
@property (readonly, copy) NSArray<MacLCWatchService *> *activeServices;
/// The add-on's catalog for a service and type ("movie"/"series"), or nil.
- (nullable MacLCAddonTitleCatalog *)catalogForService:(MacLCWatchService *)service
                                                  type:(NSString *)type;
/// The address MacLC installs for codes and a country (ISO 3166 alpha-2):
/// https://7a82163c306e-stremio-netflix-catalog-addon.baby-beamup.club/
/// <base64("nfx,atp::FR")>/manifest.json (the add-on's own format:
/// providers ":" rpdbKey ":" country, base64 of ASCII).
+ (NSString *)servicesAddonAddressForCodes:(NSArray<NSString *> *)codes country:(NSString *)country;
/// The codes and country of the installed add-on's address (decoded), or
/// nil without it.
- (nullable NSArray<NSString *> *)activeServiceCodes;
- (nullable NSString *)activeServicesCountry;
/// Installs (or replaces) the services add-on for codes and country; empty
/// codes removes it. completion: main queue, error nil on success.
- (void)setServiceCodes:(NSArray<NSString *> *)codes
                country:(NSString *)country
             completion:(void (^)(NSError * _Nullable error))completion;

#pragma mark Genres

/// The genres offered: the "top" catalog's genre options of the first
/// catalog add-on for mediaType ("movie" when nil), in its order (Cinemeta:
/// Action … Western); empty when none.
- (NSArray<NSString *> *)genresForMediaType:(nullable NSString *)mediaType;
/// Filled SF Symbol per genre (Action "bolt.fill", Adventure "map.fill",
/// Animation "paintpalette.fill", Biography "person.text.rectangle.fill",
/// Comedy "face.smiling.inverse", Crime "magnifyingglass", Documentary
/// "video.fill", Drama "theatermasks.fill", Family "figure.2.and.child.holdinghands",
/// Fantasy "wand.and.stars", History "building.columns.fill", Horror
/// "moon.haze.fill", Music "music.note", Mystery "questionmark.circle.fill",
/// Romance "heart.fill", Sci-Fi "sparkles", Sport "sportscourt.fill",
/// Thriller "eye.fill", War "shield.fill", Western "sun.dust.fill",
/// Reality-TV "camera.fill", Talk Show "mic.fill", Game-Show
/// "gamecontroller.fill", News "newspaper.fill"; else "film.fill").
+ (NSString *)symbolNameForGenre:(NSString *)genre;
/// System color name per genre (Action "orange", Comedy "yellow", Horror
/// "indigo", Romance "pink", Sci-Fi "cyan", Drama "purple", Documentary
/// "green", Thriller "red", Animation "mint", Family "teal", Fantasy
/// "purple", Crime "brown", War "brown", Western "orange", History "brown",
/// Mystery "indigo", Adventure "green", Biography "blue", Sport "blue",
/// Music "pink"; else "blue").
+ (NSString *)tintNameForGenre:(NSString *)genre;
/// items whose genres contain genre (case-insensitive), order kept.
+ (NSArray<MacLCAddonItem *> *)items:(NSArray<MacLCAddonItem *> *)items matchingGenre:(NSString *)genre;
@end

NS_ASSUME_NONNULL_END
