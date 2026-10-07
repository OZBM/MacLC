/*****************************************************************************
 * MacLCAddons.h: add-ons that speak the Stremio add-on protocol
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

/* MacLC ships no content source of its own. People install add-ons, remote
 * HTTP services described by a manifest.json, as in Stremio: catalogs list
 * titles, meta lists a title's episodes, streams say what to play. Protocol:
 * https://github.com/Stremio/stremio-addon-sdk/blob/master/docs/protocol.md
 *
 * Foundation only: the unit tests link this file on its own. */
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// NSUserDefaults key holding the installed add-ons, in order:
/// [{ "transportUrl": NSString, "manifest": NSData (the manifest JSON) }].
/// Absent: the default add-ons (Cinemeta).
extern NSString * const MacLCAddonsDefaultsKey;
/// Posted on the main queue whenever the installed add-ons change.
extern NSNotificationName const MacLCAddonsDidChangeNotification;

extern NSErrorDomain const MacLCAddonsErrorDomain;
typedef NS_ERROR_ENUM(MacLCAddonsErrorDomain, MacLCAddonsError) {
    /// The server answered with another status than 200; userInfo[@"status"].
    MacLCAddonsErrorHTTPStatus = 1,
    /// Not JSON, or not the expected shape.
    MacLCAddonsErrorBadResponse = 2,
    /// A manifest without id, name, version or resources.
    MacLCAddonsErrorNotAnAddon = 3,
    /// Not something an add-on address can be made of.
    MacLCAddonsErrorBadAddress = 4,
};

/// The server name a failed request could not look up (DNS), or nil: the
/// internet may work while lookups fail, so error messages name the server.
NSString * _Nullable MacLCAddonsUnresolvedHost(NSError * _Nullable error);

/// One add-on, installed or listed by an add-on catalog.
@interface MacLCAddon : NSObject
/// nil, and *error, when data is not an add-on manifest.
+ (nullable instancetype)addonWithTransportURL:(NSString *)transportURL
                                  manifestData:(NSData *)data
                                         error:(NSError **)error;
/// ".../manifest.json"
@property (readonly, copy) NSString *transportURL;
/// transportURL without "/manifest.json": resources hang below it.
@property (readonly) NSURL *baseURL;
@property (readonly, copy) NSData *manifestData;
@property (readonly, copy) NSString *identifier;
@property (readonly, copy) NSString *name;
@property (readonly, copy) NSString *version;
@property (readonly, copy, nullable) NSString *addonDescription;
@property (readonly, nullable) NSURL *logoURL;
@property (readonly, copy) NSArray<NSString *> *types;
/// baseURL + "/configure" when behaviorHints.configurable, else nil.
@property (readonly, nullable) NSURL *configureURL;
/// NO for the default catalog add-on (Cinemeta), as in Stremio.
@property (readonly, getter=isRemovable) BOOL removable;
/// The names of the resources it provides, e.g. @[@"catalog", @"meta"].
@property (readonly, copy) NSArray<NSString *> *resourceNames;
@property (readonly) BOOL providesStreams;
/// It has a catalog that accepts the "search" extra.
@property (readonly) BOOL providesSearch;
/// Resource given as a string applies to the manifest's types and idPrefixes;
/// as an object, to its own (missing idPrefixes: any id). nil identifier: any.
- (BOOL)providesResource:(NSString *)resource
                 forType:(NSString *)type
              identifier:(nullable NSString *)identifier;
@end

/// An add-on catalog (manifest.addonCatalogs) of an installed add-on.
@interface MacLCAddonCatalog : NSObject
@property (readonly) MacLCAddon *addon;
@property (readonly, copy) NSString *type;
@property (readonly, copy) NSString *identifier;
@property (readonly, copy) NSString *name;
@end

/// A title listed by a catalog.
@interface MacLCAddonItem : NSObject
/// The add-on whose catalog listed it.
@property (readonly) MacLCAddon *addon;
@property (readonly, copy) NSString *identifier;
@property (readonly, copy) NSString *type;
@property (readonly, copy) NSString *name;
@property (readonly, copy, nullable) NSString *releaseInfo;
@property (readonly, nullable) NSURL *posterURL;
/* What a catalog may give besides (Cinemeta gives all of them); nil or
 * empty when absent. The meta resource gives the same, see MacLCAddonMeta. */
/// "description"
@property (readonly, copy, nullable) NSString *itemDescription;
/// "background": a wide picture (16:9 or wider).
@property (readonly, nullable) NSURL *backgroundURL;
/// "logo": the title drawn as a transparent picture.
@property (readonly, nullable) NSURL *logoURL;
/// "genres", else "genre".
@property (readonly, copy) NSArray<NSString *> *genres;
/// "imdbRating" ("7.8"); nil when absent or empty.
@property (readonly, copy, nullable) NSString *imdbRating;
/// "runtime" as given ("101 min", "1h 41min").
@property (readonly, copy, nullable) NSString *runtime;
@end

/// The results of one searchable catalog of one add-on.
@interface MacLCAddonSearchGroup : NSObject
@property (readonly) MacLCAddon *addon;
@property (readonly, copy) NSString *type;
@property (readonly, copy) NSString *catalogName;
@property (readonly, copy) NSArray<MacLCAddonItem *> *items;
@property (readonly, nullable) NSError *error;
@end

/// One video of a title (meta.videos): an episode, a channel's video.
@interface MacLCAddonVideo : NSObject
@property (readonly, copy) NSString *identifier;
/// 0 when the add-on gives none.
@property (readonly) NSInteger season;
/// 0 when the add-on gives none.
@property (readonly) NSInteger episode;
@property (readonly, copy, nullable) NSString *name;
@property (readonly, nullable) NSDate *released;
/// "thumbnail": a 16:9 still.
@property (readonly, nullable) NSURL *thumbnailURL;
/// "overview", else "description".
@property (readonly, copy, nullable) NSString *overview;
@end

@interface MacLCAddonMeta : NSObject
/// Sorted by season then episode; empty for a movie.
@property (readonly, copy) NSArray<MacLCAddonVideo *> *videos;
/// What to ask streams for when there is no list:
/// behaviorHints.defaultVideoId, else the title's id.
@property (readonly, copy) NSString *defaultVideoIdentifier;
/* The title's details, same keys as MacLCAddonItem; nil or empty when absent. */
@property (readonly, copy, nullable) NSString *name;
@property (readonly, copy, nullable) NSString *itemDescription;
@property (readonly, copy, nullable) NSString *releaseInfo;
@property (readonly, nullable) NSURL *posterURL;
@property (readonly, nullable) NSURL *backgroundURL;
@property (readonly, nullable) NSURL *logoURL;
@property (readonly, copy) NSArray<NSString *> *genres;
@property (readonly, copy, nullable) NSString *imdbRating;
@property (readonly, copy, nullable) NSString *runtime;
/// "cast", else the "links" of category "Cast"; at most 6.
@property (readonly, copy) NSArray<NSString *> *cast;
/// "director", else the "links" of category "Directors".
@property (readonly, copy) NSArray<NSString *> *directors;
/// First "trailerStreams" ytId, else first "trailers" source; nil when none.
@property (readonly, copy, nullable) NSString *trailerYouTubeIdentifier;
@end

/// A catalog of titles of an installed add-on (manifest.catalogs) that MacLC
/// can browse without a query: every catalog except those that require an
/// extra other than "genre", and those that require "genre" without listing
/// its options (Cinemeta: Popular, New, Featured for movies and series; not
/// "last-videos" nor "calendar-videos"). A catalog requiring "genre" is
/// fetched with its first option when no genre is given (Cinemeta's "New"
/// requires a year: "2026").
@interface MacLCAddonTitleCatalog : NSObject
@property (readonly) MacLCAddon *addon;
@property (readonly, copy) NSString *type;
@property (readonly, copy) NSString *identifier;
/// The catalog's name ("Popular"), else its identifier.
@property (readonly, copy) NSString *name;
/// The options of its "genre" extra (or manifest "genres"), in order; empty
/// when it has none.
@property (readonly, copy) NSArray<NSString *> *genres;
@property (readonly) BOOL requiresGenre;
/// It accepts the "skip" extra (more pages).
@property (readonly) BOOL supportsSkip;
@end

/// One stream, whatever the add-on.
@interface MacLCAddonStream : NSObject
@property (readonly) MacLCAddon *addon;
/// First line of "name".
@property (readonly, copy) NSString *label;
/// The other lines of "name", split on spaces and "|", empty ones dropped.
@property (readonly, copy) NSArray<NSString *> *qualityTokens;
/// First line of "title" (or "description"), else the file name, else label.
@property (readonly, copy) NSString *headline;
/// The other lines, joined with " · "; nil when none.
@property (readonly, copy, nullable) NSString *details;
@property (readonly, copy, nullable) NSString *infoHash;
/// behaviorHints.filename: the basename of the file to play in the torrent.
@property (readonly, copy, nullable) NSString *filename;
@property (readonly, copy) NSArray<NSString *> *trackers;
/// "url"
@property (readonly, nullable) NSURL *directURL;
/// "ytId"
@property (readonly, copy, nullable) NSString *youTubeIdentifier;
/// What MacLC plays.
@property (readonly, copy) NSString *MRL;
@end

/// The streams of one add-on for one video.
@interface MacLCAddonStreamGroup : NSObject
@property (readonly) MacLCAddon *addon;
/// The ones MacLC can play, in the add-on's order.
@property (readonly, copy) NSArray<MacLCAddonStream *> *streams;
@property (readonly, nullable) NSError *error;
@end

/// Cancels every request behind one call; a cancelled call's blocks never run.
@interface MacLCAddonRequest : NSObject
- (void)cancel;
@end

@interface MacLCAddonStore : NSObject

@property (class, readonly) MacLCAddonStore *sharedStore;

/// In order. The default add-ons when nothing was ever installed.
@property (readonly, copy) NSArray<MacLCAddon *> *installedAddons;
/// Some installed add-on provides streams (File ▸ Search Add-ons… shows).
@property (readonly) BOOL hasStreamAddon;
- (BOOL)isInstalled:(NSString *)identifier;

/// Fetches the manifest and installs it; an installed add-on with the same id
/// is replaced where it stands (replaced = YES). Main queue.
- (MacLCAddonRequest *)installFromAddress:(NSString *)address
                               completion:(void (^)(MacLCAddon * _Nullable addon, BOOL replaced, NSError * _Nullable error))completion;
/// Installs (or replaces) an add-on listed by an add-on catalog.
- (void)installAddon:(MacLCAddon *)addon;
/// Does nothing for an add-on that is not removable.
- (void)removeAddon:(MacLCAddon *)addon;
- (void)resetToDefaults;
/// Fetches every installed manifest again; keeps the ones still valid.
- (void)refreshManifests;

/// The add-on catalogs of the installed add-ons ("Official", "Community"...).
@property (readonly, copy) NSArray<MacLCAddonCatalog *> *addonCatalogs;
/// Only add-ons MacLC can use: http(s) manifest addresses, not on this Mac,
/// providing a catalog, meta or streams. Main queue.
- (MacLCAddonRequest *)fetchAddonCatalog:(MacLCAddonCatalog *)catalog
                              completion:(void (^)(NSArray<MacLCAddon *> * _Nullable addons, NSError * _Nullable error))completion;

/// The browsable title catalogs of the installed add-ons, in add-on then
/// manifest order.
@property (readonly, copy) NSArray<MacLCAddonTitleCatalog *> *titleCatalogs;
/// One page of a title catalog: <base>/catalog/<type>/<id>[/genre=<g>&skip=<n>].json
/// (extras in that order, values percent-encoded, skip only when > 0 and
/// supported; genre defaults to the first option when required). Main queue.
- (MacLCAddonRequest *)fetchTitleCatalog:(MacLCAddonTitleCatalog *)catalog
                                   genre:(nullable NSString *)genre
                                    skip:(NSUInteger)skip
                              completion:(void (^)(NSArray<MacLCAddonItem *> * _Nullable items, NSError * _Nullable error))completion;

/// Every catalog that accepts "search", of every installed add-on; one group
/// per catalog, in add-on then catalog order; completion runs once. Main queue.
- (MacLCAddonRequest *)searchTitles:(NSString *)query
                         completion:(void (^)(NSArray<MacLCAddonSearchGroup *> *groups))completion;
/// From the item's add-on when it provides meta for it, else from the first
/// installed add-on that does; meta and error both nil when none does.
- (MacLCAddonRequest *)fetchMetaForItem:(MacLCAddonItem *)item
                             completion:(void (^)(MacLCAddonMeta * _Nullable meta, NSError * _Nullable error))completion;
/// Every installed add-on providing streams for type and identifier; each
/// group as soon as its add-on answers, then completion. Main queue.
- (MacLCAddonRequest *)fetchStreamsForType:(NSString *)type
                           videoIdentifier:(NSString *)identifier
                                 eachGroup:(void (^)(MacLCAddonStreamGroup *group))eachGroup
                                completion:(void (^)(void))completion;

/* Pure functions, for the tests. */
/// stremio:// links, ".../configure" pages and base addresses become a
/// manifest address; nil when no http(s) address can be made.
+ (nullable NSString *)transportURLForAddress:(NSString *)address;
/// <base>/<resource>/<type>/<id>[/<extra>].json, with ":" kept in ids.
+ (NSURL *)URLForResource:(NSString *)resource
                    addon:(MacLCAddon *)addon
                     type:(NSString *)type
               identifier:(NSString *)identifier
                    extra:(nullable NSString *)extra;
+ (nullable NSArray<MacLCAddonItem *> *)itemsFromCatalogData:(NSData *)data addon:(MacLCAddon *)addon error:(NSError **)error;
+ (nullable MacLCAddonMeta *)metaFromData:(NSData *)data itemIdentifier:(NSString *)identifier error:(NSError **)error;
/// The browsable title catalogs of one add-on (see MacLCAddonTitleCatalog).
+ (NSArray<MacLCAddonTitleCatalog *> *)titleCatalogsOfAddon:(MacLCAddon *)addon;
/// "genre=Sci-Fi&skip=100", "skip=100", "genre=2026", or nil.
+ (nullable NSString *)extraForTitleCatalog:(MacLCAddonTitleCatalog *)catalog
                                      genre:(nullable NSString *)genre
                                       skip:(NSUInteger)skip;
+ (nullable NSArray<MacLCAddonStream *> *)streamsFromData:(NSData *)data addon:(MacLCAddon *)addon error:(NSError **)error;
+ (nullable NSArray<MacLCAddon *> *)addonsFromCatalogData:(NSData *)data error:(NSError **)error;
/// The add-ons of Cinemeta's "community" add-on catalog, after the community
/// add-ons Stremio's list leaves out (Torrentio) that serve type ("all": any);
/// one the list already has is not added again.
+ (NSArray<MacLCAddon *> *)communityAddons:(NSArray<MacLCAddon *> *)addons forType:(NSString *)type;
/// "His Girl Friday (1940)", "Dragnet — S1E2 · The Big Ruckus",
/// "A Channel — A Video".
+ (NSString *)itemNameForItem:(MacLCAddonItem *)item video:(nullable MacLCAddonVideo *)video;

@end

NS_ASSUME_NONNULL_END
