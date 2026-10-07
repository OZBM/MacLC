/*****************************************************************************
 * MacLCMenuSymbols.m: MacOS X interface module
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

#import "MacLCMenuSymbols.h"
#import "extensions/NSString+Helpers.h"

@interface MacLCMenuSymbols ()

+ (nullable NSString *)symbolNameForMenuItem:(NSMenuItem *)item;
+ (void)applySymbolsToMenu:(NSMenu *)menu visitedMenus:(NSHashTable<NSMenu *> *)visitedMenus;

@end

@implementation MacLCMenuSymbols

+ (nullable NSString *)symbolNameForMenuItem:(NSMenuItem *)item
{
    if (item == nil) {
        return nil;
    }

    SEL action = item.action;
    if (action != NULL) {
        NSString *actionString = NSStringFromSelector(action);

        // Ambiguous selectors disambiguated by tag
        if ([actionString isEqualToString:@"unselectTrackCategory:"]) {
            switch (item.tag) {
                case 1: // AUDIO_ES
                    return @"waveform";
                case 2: // VIDEO_ES
                    return @"video";
                case 3: // SPU_ES
                    return @"captions.bubble";
                default:
                    return nil;
            }
        }

        // File menu
        if ([actionString isEqualToString:@"intfOpenFile:"] ||
            [actionString isEqualToString:@"intfOpenFileGeneric:"]) {
            return @"doc";
        }
        if ([actionString isEqualToString:@"revealItemInFinder:"] ||
            [actionString isEqualToString:@"revealInFinder:"]) {
            return @"folder";
        }
        if ([actionString isEqualToString:@"intfOpenDisc:"]) {
            return @"opticaldisc";
        }
        if ([actionString isEqualToString:@"intfOpenNet:"] ||
            [actionString isEqualToString:@"intfOpenWebVideo:"]) {
            return @"link";
        }
        if ([actionString isEqualToString:@"intfOpenAddonSearch:"]) {
            return @"magnifyingglass";
        }
        if ([actionString isEqualToString:@"intfOpenCapture:"]) {
            return @"web.camera";
        }
        if ([actionString isEqualToString:@"intfConnectToServer:"]) {
            return @"server.rack";
        }
        if ([actionString isEqualToString:@"openRecentStreamItem:"]) {
            return @"clock.arrow.circlepath";
        }
        if ([actionString isEqualToString:@"showConvertAndSave:"]) {
            return @"arrow.triangle.2.circlepath";
        }
        if ([actionString isEqualToString:@"savePlaylist:"] ||
            [actionString isEqualToString:@"savePlayQueueToLibrary:"]) {
            return @"square.and.arrow.down";
        }

        // Media Library (File & View)
        if ([actionString isEqualToString:@"newLibraryPlaylist:"]) {
            return @"music.note.list";
        }
        if ([actionString isEqualToString:@"addFolderToLibrary:"]) {
            return @"folder.badge.plus";
        }
        if ([actionString isEqualToString:@"showLibraryFolders:"]) {
            return @"folder";
        }
        if ([actionString isEqualToString:@"goBackInLibrary:"]) {
            return @"chevron.backward";
        }
        if ([actionString isEqualToString:@"goForwardInLibrary:"]) {
            return @"chevron.forward";
        }
        if ([actionString isEqualToString:@"toggleSidebar:"]) {
            return @"sidebar.left";
        }
        if ([actionString isEqualToString:@"toggleUpNext:"]) {
            return @"list.bullet.indent";
        }
        if ([actionString isEqualToString:@"toggleToolbarShown:"]) {
            return @"menubar.rectangle";
        }
        if ([actionString isEqualToString:@"showLibraryAsGrid:"]) {
            return @"square.grid.2x2";
        }
        if ([actionString isEqualToString:@"showLibraryAsList:"]) {
            return @"list.bullet";
        }

        // Playback menu
        if ([actionString isEqualToString:@"play:"]) {
            return @"playpause";
        }
        if ([actionString isEqualToString:@"stop:"]) {
            return @"stop";
        }
        if ([actionString isEqualToString:@"toggleRecord:"]) {
            return @"record.circle";
        }
        if ([actionString isEqualToString:@"prev:"]) {
            return @"backward.end";
        }
        if ([actionString isEqualToString:@"next:"]) {
            return @"forward.end";
        }
        if ([actionString isEqualToString:@"backward:"]) {
            return @"gobackward.10";
        }
        if ([actionString isEqualToString:@"forward:"]) {
            return @"goforward.10";
        }
        if ([actionString isEqualToString:@"goToSpecificTime:"]) {
            return @"timer";
        }
        if ([actionString isEqualToString:@"toggleLyrics:"]) {
            return @"text.quote";
        }
        if ([actionString isEqualToString:@"faster:"] ||
            [actionString isEqualToString:@"speedUp:"] ||
            [actionString isEqualToString:@"fastForward:"]) {
            return @"hare";
        }
        if ([actionString isEqualToString:@"slower:"] ||
            [actionString isEqualToString:@"slowDown:"]) {
            return @"tortoise";
        }
        if ([actionString isEqualToString:@"normalSpeed:"] ||
            [actionString isEqualToString:@"normalRate:"] ||
            [actionString isEqualToString:@"resetRate:"]) {
            return @"gauge.with.dots.needle.50percent";
        }
        if ([actionString isEqualToString:@"random:"]) {
            return @"shuffle";
        }
        if ([actionString isEqualToString:@"repeat:"]) {
            return @"repeat";
        }
        if ([actionString isEqualToString:@"toggleAtoBloop:"]) {
            return @"repeat.1";
        }
        if ([actionString isEqualToString:@"toggleLibraryPlayQueueMode:"]) {
            return @"books.vertical";
        }
        if ([actionString isEqualToString:@"sortPlayQueue:"]) {
            return @"arrow.up.arrow.down";
        }

        // Audio menu
        if ([actionString isEqualToString:@"volumeUp:"]) {
            return @"speaker.plus";
        }
        if ([actionString isEqualToString:@"volumeDown:"]) {
            return @"speaker.minus";
        }
        if ([actionString isEqualToString:@"mute:"]) {
            return @"speaker.slash";
        }
        if ([actionString isEqualToString:@"toggleAudioDevice:"]) {
            return @"hifispeaker";
        }
        if ([actionString isEqualToString:@"selectAudioTrack:"] ||
            [actionString isEqualToString:@"audiotrack:"]) {
            return @"waveform";
        }

        // Video menu
        if ([actionString isEqualToString:@"toggleFullscreen:"]) {
            return @"arrow.up.left.and.arrow.down.right";
        }
        if ([actionString isEqualToString:@"floatOnTop:"]) {
            return @"pin";
        }
        if ([actionString isEqualToString:@"createVideoSnapshot:"]) {
            return @"camera";
        }
        if ([actionString isEqualToString:@"performCustomAspectRatio:"] ||
            [actionString isEqualToString:@"lockVideosAspectRatio:"]) {
            return @"aspectratio";
        }
        if ([actionString isEqualToString:@"performCustomCrop:"]) {
            return @"crop";
        }
        if ([actionString isEqualToString:@"togglePip:"] ||
            [actionString isEqualToString:@"pip:"] ||
            [actionString isEqualToString:@"pictureInPicture:"]) {
            return @"pip.enter";
        }
        if ([actionString isEqualToString:@"selectVideoTrack:"] ||
            [actionString isEqualToString:@"videotrack:"]) {
            return @"video";
        }

        // Subtitles menu
        if ([actionString isEqualToString:@"addSubtitleFile:"]) {
            return @"plus.bubble";
        }
        if ([actionString isEqualToString:@"selectSubtitleTrack:"] ||
            [actionString isEqualToString:@"subtitlestrack:"]) {
            return @"captions.bubble";
        }

        // Window & panels
        if ([actionString isEqualToString:@"showInformationPanel:"]) {
            return @"info.circle";
        }
        if ([actionString isEqualToString:@"showAudioEffects:"]) {
            return @"slider.horizontal.3";
        }
        if ([actionString isEqualToString:@"showSoundPanel:"]) {
            return @"slider.vertical.3";
        }
        if ([actionString isEqualToString:@"showVideoEffects:"]) {
            return @"camera.filters";
        }
        if ([actionString isEqualToString:@"showTrackSynchronization:"]) {
            return @"arrow.left.arrow.right";
        }
        if ([actionString isEqualToString:@"showBookmarks:"]) {
            return @"bookmark";
        }
        if ([actionString isEqualToString:@"showMessagesPanel:"]) {
            return @"text.alignleft";
        }
        if ([actionString isEqualToString:@"showErrorsAndWarnings:"]) {
            return @"exclamationmark.triangle";
        }
        if ([actionString isEqualToString:@"showMainWindow:"]) {
            return @"books.vertical";
        }
        if ([actionString isEqualToString:@"showPlayQueue:"]) {
            return @"list.bullet";
        }
        if ([actionString isEqualToString:@"showDetachedAudioWindow:"]) {
            return @"headphones";
        }

        // Help menu
        if ([actionString isEqualToString:@"showHelp:"]) {
            return @"questionmark.circle";
        }
        if ([actionString isEqualToString:@"showLicense:"]) {
            return @"doc.text";
        }
        if ([actionString isEqualToString:@"showPreferences:"]) {
            return @"gearshape";
        }
        if ([actionString isEqualToString:@"openWebsite:"]) {
            return @"safari";
        }
    } else if (item.submenu != nil) {
        // Items with a submenu that do not have an explicit action in the nib
        NSString *title = item.title;
        if ([title isEqualToString:_NS("Subtitle Track")] ||
            [title caseInsensitiveCompare:@"Subtitle Track"] == NSOrderedSame) {
            return @"captions.bubble";
        }
        if ([title isEqualToString:_NS("Audio Track")] ||
            [title caseInsensitiveCompare:@"Audio Track"] == NSOrderedSame) {
            return @"waveform";
        }
        if ([title isEqualToString:_NS("Video Track")] ||
            [title caseInsensitiveCompare:@"Video Track"] == NSOrderedSame) {
            return @"video";
        }
        if ([title isEqualToString:_NS("Output Device")] ||
            [title caseInsensitiveCompare:@"Output Device"] == NSOrderedSame ||
            [title caseInsensitiveCompare:@"Audio Device"] == NSOrderedSame) {
            return @"hifispeaker";
        }
        if ([title isEqualToString:_NS("Aspect Ratio")] ||
            [title caseInsensitiveCompare:@"Aspect Ratio"] == NSOrderedSame ||
            [title caseInsensitiveCompare:@"Aspect-ratio"] == NSOrderedSame) {
            return @"aspectratio";
        }
        if ([title isEqualToString:_NS("Crop")] ||
            [title caseInsensitiveCompare:@"Crop"] == NSOrderedSame) {
            return @"crop";
        }
        if ([title isEqualToString:_NS("Open Recent")] ||
            [title caseInsensitiveCompare:@"Open Recent"] == NSOrderedSame ||
            [title isEqualToString:_NS("Recent Streams")] ||
            [title caseInsensitiveCompare:@"Recent Streams"] == NSOrderedSame) {
            return @"clock.arrow.circlepath";
        }
        if ([title isEqualToString:_NS("Stereo Mode")] ||
            [title caseInsensitiveCompare:@"Stereo Mode"] == NSOrderedSame ||
            [title caseInsensitiveCompare:@"Stereo audio mode"] == NSOrderedSame) {
            return @"speaker.2";
        }
        if ([title isEqualToString:_NS("Visualizations")] ||
            [title caseInsensitiveCompare:@"Visualizations"] == NSOrderedSame) {
            return @"music.note.tv";
        }
    }

    return nil;
}

+ (void)applySymbolsToMenu:(NSMenu *)menu
{
    [self applySymbolsToMenu:menu visitedMenus:[NSHashTable weakObjectsHashTable]];
}

+ (void)applySymbolsToMenu:(NSMenu *)menu visitedMenus:(NSHashTable<NSMenu *> *)visitedMenus
{
    if (menu == nil || [visitedMenus containsObject:menu]) {
        return;
    }
    [visitedMenus addObject:menu];

    if (@available(macOS 11.0, *)) {
        NSNumber * const enabled = [NSUserDefaults.standardUserDefaults objectForKey:@"NSMenuEnableActionImages"];
        if (enabled != nil && !enabled.boolValue) {
            return;
        }

        // Divide menu items into groups delimited by separator items
        NSMutableArray<NSArray<NSMenuItem *> *> *groups = [NSMutableArray array];
        NSMutableArray<NSMenuItem *> *currentGroup = [NSMutableArray array];

        for (NSMenuItem *item in menu.itemArray) {
            if (item.isSeparatorItem) {
                if (currentGroup.count > 0) {
                    [groups addObject:[currentGroup copy]];
                    [currentGroup removeAllObjects];
                }
            } else {
                [currentGroup addObject:item];
            }
        }
        if (currentGroup.count > 0) {
            [groups addObject:[currentGroup copy]];
        }

        for (NSArray<NSMenuItem *> *group in groups) {
            BOOL groupQualifies = YES;
            NSMutableArray *resolvedImages = [NSMutableArray arrayWithCapacity:group.count];

            for (NSMenuItem *item in group) {
                // Hidden items and custom view items are excluded from group icon requirement.
                // A hidden item still gets its symbol, if it has one: it may be shown later
                // (Search Add-ons… appears once an add-on provides streams).
                if (item.isHidden || item.view != nil) {
                    NSString * const hiddenSymbol = item.view == nil && item.image == nil ? [self symbolNameForMenuItem:item] : nil;
                    NSImage * const hiddenImage = hiddenSymbol != nil ? [NSImage imageWithSystemSymbolName:hiddenSymbol accessibilityDescription:nil] : nil;
                    [resolvedImages addObject:hiddenImage ?: (id)[NSNull null]];
                    continue;
                }

                if (item.image != nil) {
                    [resolvedImages addObject:item.image];
                    continue;
                }

                NSString *symbolName = [self symbolNameForMenuItem:item];
                NSImage *image = nil;
                if (symbolName != nil) {
                    image = [NSImage imageWithSystemSymbolName:symbolName accessibilityDescription:nil];
                }

                if (image == nil) {
                    groupQualifies = NO;
                    break;
                }
                [resolvedImages addObject:image];
            }

            if (groupQualifies) {
                for (NSUInteger i = 0; i < group.count; i++) {
                    NSMenuItem *item = group[i];
                    id resolved = resolvedImages[i];
                    if (resolved != [NSNull null] && item.image == nil) {
                        item.image = (NSImage *)resolved;
                    }
                }
            }
        }

        // Recurse into submenus
        for (NSMenuItem *item in menu.itemArray) {
            if (item.submenu != nil) {
                [self applySymbolsToMenu:item.submenu visitedMenus:visitedMenus];
            }
        }
    }
}

@end
