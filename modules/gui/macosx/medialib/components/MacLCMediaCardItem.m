/*****************************************************************************
 * MacLCMediaCardItem.m: artwork card of every library grid and shelf
 *****************************************************************************
 * Copyright (C) 2026 Hazen Studio
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/

#import "medialib/components/MacLCMediaCardItem.h"
#import "medialib/components/MacLCArtworkView.h"
#import "medialib/data/MacLCMediaFormat.h"
#import "medialib/data/MacLCLibraryActions.h"
#import "library/VLCLibraryDataTypes.h"
#import "theme/MacLCDesign.h"
#import "extensions/NSString+Helpers.h"

@interface MacLCMediaCardItem ()

@property (nonatomic, readwrite) MacLCArtworkView *artworkView;
@property (nonatomic, readwrite, nullable) id<VLCMediaLibraryItemProtocol> libraryItem;

@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSTextField *subtitleLabel;
@property (nonatomic, assign) MacLCCardSubtitleStyle currentSubtitleStyle;

- (void)playItem;
- (NSString *)subtitleString;

@end

@interface MacLCMediaCardView : NSView

@property (nonatomic, weak) MacLCMediaCardItem *item;

@end

@implementation MacLCMediaCardView

- (NSMenu *)menuForEvent:(NSEvent *)event
{
    if (self.item.libraryItem == nil) {
        return [super menuForEvent:event];
    }

    NSArray *itemsToUse = nil;
    NSCollectionView *collectionView = self.item.collectionView;
    if (collectionView && self.item.isSelected && collectionView.selectionIndexPaths.count > 1) {
        NSMutableArray *selected = [NSMutableArray array];
        for (NSIndexPath *indexPath in collectionView.selectionIndexPaths) {
            NSCollectionViewItem *ci = [collectionView itemAtIndexPath:indexPath];
            if ([ci isKindOfClass:[MacLCMediaCardItem class]]) {
                id<VLCMediaLibraryItemProtocol> libItem = ((MacLCMediaCardItem *)ci).libraryItem;
                if (libItem) {
                    [selected addObject:libItem];
                }
            }
        }
        if (selected.count > 0) {
            itemsToUse = selected;
        }
    }

    if (!itemsToUse) {
        itemsToUse = @[self.item.libraryItem];
    }

    return [MacLCLibraryActions contextMenuForItems:itemsToUse window:self.window];
}

- (void)mouseDown:(NSEvent *)event
{
    if (event.clickCount == 2) {
        id<VLCMediaLibraryItemProtocol> const libraryItem = self.item.libraryItem;
        if (libraryItem != nil && self.item.activationHandler != nil) {
            self.item.activationHandler(libraryItem);
        } else if (libraryItem != nil) {
            [MacLCLibraryActions playItems:@[libraryItem] startingAt:0];
        }
        return;
    }
    [super mouseDown:event];
}

- (BOOL)isAccessibilityElement
{
    return YES;
}

- (NSAccessibilityRole)accessibilityRole
{
    return NSAccessibilityGroupRole;
}

- (nullable NSString *)accessibilityLabel
{
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    MacLCMediaCardItem *cardItem = self.item;
    if (!cardItem) {
        return @"";
    }

    NSString *title = cardItem.libraryItem.displayString;
    if (title.length > 0) {
        [parts addObject:title];
    }

    NSString *subtitle = [cardItem subtitleString];
    if (subtitle.length > 0) {
        [parts addObject:subtitle];
    }

    if (cardItem.artworkView.badges.count > 0) {
        [parts addObject:[cardItem.artworkView.badges componentsJoinedByString:@", "]];
    }

    return [parts componentsJoinedByString:@", "];
}

@end

NSUserInterfaceItemIdentifier const MacLCMediaCardItemIdentifier = @"MacLCMediaCardItemIdentifier";

@implementation MacLCMediaCardItem

- (void)loadView
{
    MacLCMediaCardView *cardView = [[MacLCMediaCardView alloc] initWithFrame:NSZeroRect];
    cardView.item = self;
    cardView.wantsLayer = YES;
    self.view = cardView;

    _artworkView = [[MacLCArtworkView alloc] initWithShape:MacLCArtworkShapeSquare];
    _artworkView.translatesAutoresizingMaskIntoConstraints = NO;
    _artworkView.showsPlayAffordance = YES;
    __weak typeof(self) weakSelf = self;
    _artworkView.playAction = ^{
        [weakSelf playItem];
    };
    [self.view addSubview:_artworkView];

    _titleLabel = [NSTextField labelWithString:@""];
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _titleLabel.font = [NSFont systemFontOfSize:MacLCDesign.body.pointSize weight:NSFontWeightMedium];
    _titleLabel.textColor = MacLCDesign.primaryLabel;
    _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    _titleLabel.maximumNumberOfLines = 1;
    [self.view addSubview:_titleLabel];

    _subtitleLabel = [NSTextField labelWithString:@""];
    _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _subtitleLabel.font = MacLCDesign.subheadline;
    _subtitleLabel.textColor = MacLCDesign.secondaryLabel;
    _subtitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    _subtitleLabel.maximumNumberOfLines = 1;
    [self.view addSubview:_subtitleLabel];

    [NSLayoutConstraint activateConstraints:@[
        [_artworkView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_artworkView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_artworkView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],

        [_titleLabel.topAnchor constraintEqualToAnchor:_artworkView.bottomAnchor constant:8.0],
        [_titleLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_titleLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],

        [_subtitleLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:2.0],
        [_subtitleLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_subtitleLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    ]];
}

- (void)playItem
{
    if (self.libraryItem) {
        [MacLCLibraryActions playItems:@[self.libraryItem] startingAt:0];
    }
}

- (void)setSelected:(BOOL)selected
{
    [super setSelected:selected];
    _artworkView.selected = selected;
}

- (void)prepareForReuse
{
    [super prepareForReuse];
    _libraryItem = nil;
    [_artworkView setArtworkFromItem:nil];
    _artworkView.badges = @[];
    _artworkView.progress = 0.0;
    _artworkView.selected = NO;
    _titleLabel.stringValue = @"";
    _subtitleLabel.stringValue = @"";
}

#pragma mark - Configuration

- (void)configureWithItem:(id<VLCMediaLibraryItemProtocol>)item
                    shape:(MacLCArtworkShape)shape
            subtitleStyle:(MacLCCardSubtitleStyle)subtitleStyle
{
    _libraryItem = item;
    _currentSubtitleStyle = subtitleStyle;

    _artworkView.shape = shape;
    [_artworkView setArtworkFromItem:item];

    if (shape == MacLCArtworkShapeCircle) {
        _titleLabel.alignment = NSTextAlignmentCenter;
        _subtitleLabel.alignment = NSTextAlignmentCenter;
    } else {
        _titleLabel.alignment = NSTextAlignmentLeft;
        _subtitleLabel.alignment = NSTextAlignmentLeft;
    }

    _titleLabel.stringValue = item.displayString ?: @"";

    // Badges & progress for video items
    if ([item isKindOfClass:[VLCMediaLibraryMediaItem class]]) {
        VLCMediaLibraryMediaItem *mediaItem = (VLCMediaLibraryMediaItem *)item;
        if (mediaItem.mediaType == VLC_ML_MEDIA_TYPE_VIDEO) {
            MacLCMediaFormat *format = [MacLCMediaFormat formatForMediaItem:mediaItem];
            _artworkView.badges = format.badges ?: @[];
        } else {
            _artworkView.badges = @[];
        }
        _artworkView.progress = mediaItem.progress;
    } else {
        _artworkView.badges = @[];
        _artworkView.progress = 0.0;
    }

    NSString *subtitle = [self subtitleString];
    if (subtitle.length > 0) {
        _subtitleLabel.stringValue = subtitle;
        _subtitleLabel.hidden = NO;
    } else {
        _subtitleLabel.stringValue = @"";
        _subtitleLabel.hidden = YES;
    }
}

- (NSString *)subtitleString
{
    if (_currentSubtitleStyle == MacLCCardSubtitleStyleNone || !_libraryItem) {
        return @"";
    }

    if (_currentSubtitleStyle == MacLCCardSubtitleStyleTimeLeft) {
        if ([_libraryItem isKindOfClass:[VLCMediaLibraryMediaItem class]]) {
            VLCMediaLibraryMediaItem *mediaItem = (VLCMediaLibraryMediaItem *)_libraryItem;
            if (mediaItem.duration > 0 && mediaItem.progress > 0.0 && mediaItem.progress < 1.0) {
                NSTimeInterval remainingSeconds = (mediaItem.duration / 1000.0) * (1.0 - mediaItem.progress);
                if (remainingSeconds < 60.0) {
                    return _NS("Less than a minute left");
                }
                NSString *dur = [self formatDurationAbbreviated:remainingSeconds];
                return [NSString stringWithFormat:_NS("%@ left"), dur];
            }
        }
        return @"";
    }

    // MacLCCardSubtitleStyleDefault
    if ([_libraryItem isKindOfClass:[VLCMediaLibraryMediaItem class]]) {
        VLCMediaLibraryMediaItem *mediaItem = (VLCMediaLibraryMediaItem *)_libraryItem;
        NSString *dur = mediaItem.duration > 0 ? [self formatDurationAbbreviated:(mediaItem.duration / 1000.0)] : nil;
        if (mediaItem.year > 0) {
            if (dur.length > 0) {
                return [NSString stringWithFormat:@"%@ · %d", dur, mediaItem.year];
            }
            return [NSString stringWithFormat:@"%d", mediaItem.year];
        }
        return dur ?: @"";
    } else if ([_libraryItem isKindOfClass:[VLCMediaLibraryShow class]]) {
        VLCMediaLibraryShow *show = (VLCMediaLibraryShow *)_libraryItem;
        uint32_t seasons = show.seasonCount;
        uint32_t episodes = show.episodeCount;
        NSString *seasonsStr = (seasons == 1) ? _NS("1 season") : [NSString stringWithFormat:_NS("%u seasons"), seasons];
        NSString *episodesStr = (episodes == 1) ? _NS("1 episode") : [NSString stringWithFormat:_NS("%u episodes"), episodes];
        return [NSString stringWithFormat:@"%@ · %@", seasonsStr, episodesStr];
    } else if ([_libraryItem isKindOfClass:[VLCMediaLibraryAlbum class]]) {
        VLCMediaLibraryAlbum *album = (VLCMediaLibraryAlbum *)_libraryItem;
        if (album.artistName.length > 0) {
            return album.artistName;
        } else if (album.year > 0) {
            return [NSString stringWithFormat:@"%u", album.year];
        }
        return @"";
    } else if ([_libraryItem isKindOfClass:[VLCMediaLibraryArtist class]]) {
        VLCMediaLibraryArtist *artist = (VLCMediaLibraryArtist *)_libraryItem;
        unsigned int albums = artist.numberOfAlbums;
        return (albums == 1) ? _NS("1 album") : [NSString stringWithFormat:_NS("%u albums"), albums];
    } else if ([_libraryItem isKindOfClass:[VLCMediaLibraryPlaylist class]]) {
        VLCMediaLibraryPlaylist *playlist = (VLCMediaLibraryPlaylist *)_libraryItem;
        unsigned int count = playlist.numberOfMedia;
        NSString *countStr = (count == 1) ? _NS("1 item") : [NSString stringWithFormat:_NS("%u items"), count];
        if (playlist.duration > 0) {
            NSString *dur = [self formatDurationAbbreviated:(playlist.duration / 1000.0)];
            if (dur.length > 0) {
                return [NSString stringWithFormat:@"%@ · %@", countStr, dur];
            }
        }
        return countStr;
    } else if ([_libraryItem isKindOfClass:[VLCMediaLibraryGenre class]]) {
        VLCMediaLibraryGenre *genre = (VLCMediaLibraryGenre *)_libraryItem;
        NSUInteger albumsCount = genre.albums.count;
        return (albumsCount == 1) ? _NS("1 album") : [NSString stringWithFormat:_NS("%lu albums"), (unsigned long)albumsCount];
    }

    return _libraryItem.secondaryDetailString ?: @"";
}

- (NSString *)formatDurationAbbreviated:(NSTimeInterval)seconds
{
    static NSDateComponentsFormatter *formatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSDateComponentsFormatter alloc] init];
        formatter.unitsStyle = NSDateComponentsFormatterUnitsStyleAbbreviated;
        formatter.allowedUnits = NSCalendarUnitHour | NSCalendarUnitMinute;
        formatter.zeroFormattingBehavior = NSDateComponentsFormatterZeroFormattingBehaviorDropLeading;
    });
    return [formatter stringFromTimeInterval:seconds] ?: @"";
}

+ (CGFloat)textBlockHeightWithSubtitle:(BOOL)hasSubtitle
{
    NSFont *titleFont = [NSFont systemFontOfSize:MacLCDesign.body.pointSize weight:NSFontWeightMedium];
    CGFloat titleHeight = ceil(titleFont.ascender - titleFont.descender + titleFont.leading);
    if (!hasSubtitle) {
        return titleHeight;
    }
    NSFont *subtitleFont = MacLCDesign.subheadline;
    CGFloat subtitleHeight = ceil(subtitleFont.ascender - subtitleFont.descender + subtitleFont.leading);
    return titleHeight + 2.0 + subtitleHeight;
}

@end
