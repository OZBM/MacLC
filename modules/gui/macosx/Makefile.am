actool_verbose = $(actool_verbose_$(V))
actool_verbose_ = $(actool_verbose__$(AM_DEFAULT_VERBOSITY))
actool_verbose_0 = @echo "  ACTOOL  " $@;
actool_verbose__0 = $(actool_verbose_0)

# All content of the asset catalog should be listed below
# so that it is properly rebuilt when its content changes.
ASSET_CATALOG_DEPS = \
	gui/macosx/Resources/Assets.xcassets/Contents.json \
	gui/macosx/Resources/Assets.xcassets/MacLCCardBackground.colorset/Contents.json \
	gui/macosx/Resources/Assets.xcassets/MacLCContentBackground.colorset/Contents.json \
	gui/macosx/Resources/Assets.xcassets/MacLCScrubberFill.colorset/Contents.json \
	gui/macosx/Resources/Assets.xcassets/MacLCScrubberTrack.colorset/Contents.json \
	gui/macosx/Resources/Assets.xcassets/VLCAccentColor.colorset/Contents.json \
	gui/macosx/Resources/Assets.xcassets/dropzone.imageset/Contents.json \
	gui/macosx/Resources/Assets.xcassets/dropzone.imageset/dropzone-dark.png \
	gui/macosx/Resources/Assets.xcassets/dropzone.imageset/dropzone-dark@2x.png \
	gui/macosx/Resources/Assets.xcassets/dropzone.imageset/dropzone.png \
	gui/macosx/Resources/Assets.xcassets/dropzone.imageset/dropzone@2x.png

gui/macosx/Resources/Assets.car: gui/macosx/Resources/Assets.xcassets $(ASSET_CATALOG_DEPS)
	$(AM_V_at)$(MKDIR_P) "gui/macosx/Resources"
	$(actool_verbose)$(ACTOOL) --errors --warnings --notices \
	  --platform macosx --target-device mac --skip-app-store-deployment \
	  --minimum-deployment-target 10.13 --output-format human-readable-text \
	  --compile $(@D) $<

if ENABLE_MACOSX_UI
BUILT_SOURCES += gui/macosx/Resources/Assets.car
endif

EXTRA_DIST += $(ASSET_CATALOG_DEPS)

SUFFIXES += .xib .nib

xib_verbose = $(xib_verbose_$(V))
xib_verbose_ = $(xib_verbose__$(AM_DEFAULT_VERBOSITY))
xib_verbose_0 = @echo "  XIB     " $@;
xib_verbose__0 = $(xib_verbose_0)

.xib.nib:
	$(AM_V_at)$(MKDIR_P) "gui/macosx/UI"
	$(xib_verbose)$(XIB) --errors --warnings --notices \
	  --module VLC --auto-activate-custom-fonts --target-device mac \
	  --minimum-deployment-target 10.13 --output-format human-readable-text \
	  --compile $@ $<

if ENABLE_MACOSX_UI_SHADERS
SUFFIXES += .air .metal

metal_verbose = $(metal_verbose_$(V))
metal_verbose_ = $(metal_verbose__$(AM_DEFAULT_VERBOSITY))
metal_verbose_0 = @echo "  METAL   " $@;
metal_verbose__0 = $(metal_verbose_0)

# Rule to compile .metal to .air
.metal.air:
	$(AM_V_at)$(MKDIR_P) "gui/macosx/shaders"
	$(metal_verbose)$(METAL) -c $< -o $@

metallib_verbose = $(metallib_verbose_$(V))
metallib_verbose_ = $(metallib_verbose__$(AM_DEFAULT_VERBOSITY))
metallib_verbose_0 = @echo " METALLIB " $@;
metallib_verbose__0 = $(metallib_verbose_0)

libmacosx_plugin_la_METAL_srcs = gui/macosx/shaders/VLCSnowShader.metal
libmacosx_plugin_la_METAL_AIR_FILES = $(libmacosx_plugin_la_METAL_srcs:.metal=.air)
libmacosx_plugin_la_METAL_LIBRARY = gui/macosx/Resources/Shaders.metallib

$(libmacosx_plugin_la_METAL_LIBRARY): $(libmacosx_plugin_la_METAL_AIR_FILES)
	$(AM_V_at)$(MKDIR_P) "gui/macosx/Resources"
	$(metallib_verbose)$(METALLIB) $(libmacosx_plugin_la_METAL_AIR_FILES) -o $@

EXTRA_DIST += $(libmacosx_plugin_la_METAL_srcs)
BUILT_SOURCES += $(libmacosx_plugin_la_METAL_LIBRARY)
CLEANFILES += $(libmacosx_plugin_la_METAL_AIR_FILES) $(libmacosx_plugin_la_METAL_LIBRARY)

endif

libmacosx_plugin_la_OBJCFLAGS = $(AM_OBJCFLAGS) -fobjc-exceptions -fobjc-arc -I$(srcdir)/gui/macosx
libmacosx_plugin_la_LDFLAGS = $(AM_LDFLAGS) $(gui_RPATH) \
	-Wl,-framework,AVKit \
	-Wl,-framework,AVFoundation \
	-Wl,-framework,Cocoa \
	-Wl,-framework,CoreAudio \
	-Wl,-framework,CoreGraphics \
	-Wl,-framework,CoreVideo \
	-Wl,-framework,IOKit \
	-Wl,-framework,QuartzCore \
	-Wl,-framework,ScriptingBridge \
	-Wl,-framework,WebKit \
	-Wl,-framework,QuickLook \
	-Wl,-framework,QuickLookThumbnailing \
	-Wl,-framework,Metal \
	-Wl,-framework,MetalKit \
	-Wl,-framework,UniformTypeIdentifiers \
	-Wl,-weak_framework,MediaPlayer

if HAVE_SPARKLE
libmacosx_plugin_la_LDFLAGS += -Wl,-framework,Sparkle
endif

libmacosx_plugin_la_SOURCES = \
	gui/macosx/coreinteraction/VLCHotkeysController.h \
	gui/macosx/coreinteraction/VLCHotkeysController.m \
	gui/macosx/coreinteraction/VLCVideoFilterHelper.h \
	gui/macosx/coreinteraction/VLCVideoFilterHelper.m \
	gui/macosx/coreinteraction/MacLCOSDController.h \
	gui/macosx/coreinteraction/MacLCOSDController.m \
	gui/macosx/extensions/NSAppearance+VLCAdditions.h \
	gui/macosx/extensions/NSAppearance+VLCAdditions.m \
	gui/macosx/extensions/NSAnimationContext+VLCAdditions.h \
	gui/macosx/extensions/NSAnimationContext+VLCAdditions.m \
	gui/macosx/extensions/NSArray+VLCAdditions.h \
	gui/macosx/extensions/NSArray+VLCAdditions.m \
	gui/macosx/extensions/NSColor+VLCAdditions.h \
	gui/macosx/extensions/NSColor+VLCAdditions.m \
	gui/macosx/extensions/NSFont+VLCAdditions.h \
	gui/macosx/extensions/NSFont+VLCAdditions.m \
	gui/macosx/extensions/NSImage+VLCAdditions.h \
	gui/macosx/extensions/NSImage+VLCAdditions.m \
	gui/macosx/extensions/NSIndexSet+VLCAdditions.h \
	gui/macosx/extensions/NSIndexSet+VLCAdditions.m \
	gui/macosx/extensions/MacLCVolumePath.h \
	gui/macosx/extensions/MacLCVolumePath.m \
	gui/macosx/extensions/NSMenu+VLCAdditions.h \
	gui/macosx/extensions/NSMenu+VLCAdditions.m \
	gui/macosx/extensions/NSMenuItem+VLCAdditions.h \
	gui/macosx/extensions/NSMenuItem+VLCAdditions.m \
	gui/macosx/extensions/NSScreen+VLCAdditions.h \
	gui/macosx/extensions/NSScreen+VLCAdditions.m \
	gui/macosx/extensions/NSScrollView+VLCAdditions.h \
	gui/macosx/extensions/NSScrollView+VLCAdditions.m \
	gui/macosx/extensions/NSString+Helpers.h \
	gui/macosx/extensions/NSString+Helpers.m \
	gui/macosx/extensions/NSView+VLCAdditions.h \
	gui/macosx/extensions/NSView+VLCAdditions.m \
	gui/macosx/extensions/NSWindow+VLCAdditions.h \
	gui/macosx/extensions/NSWindow+VLCAdditions.m \
	gui/macosx/extensions/NSPasteboardItem+VLCAdditions.h \
	gui/macosx/extensions/NSPasteboardItem+VLCAdditions.m \
	gui/macosx/extensions/NSTableCellView+VLCAdditions.h \
	gui/macosx/extensions/NSTableCellView+VLCAdditions.m \
	gui/macosx/extensions/NSTextField+VLCAdditions.h \
	gui/macosx/extensions/NSTextField+VLCAdditions.m \
	gui/macosx/extensions/VLCHexNumberFormatter.h \
	gui/macosx/extensions/VLCHexNumberFormatter.m \
	gui/macosx/extensions/VLCPositionFormatter.h \
	gui/macosx/extensions/VLCPositionFormatter.m \
	gui/macosx/imported/AppleRemote/AppleRemote.h \
	gui/macosx/imported/AppleRemote/AppleRemote.m \
	gui/macosx/imported/SPMediaKeyTap/SPMediaKeyTap.h \
	gui/macosx/imported/SPMediaKeyTap/SPMediaKeyTap.m \
	gui/macosx/library/VLCInputItem.h \
	gui/macosx/library/VLCInputItem.m \
	gui/macosx/library/VLCInputNode.h \
	gui/macosx/library/VLCInputNode.m \
	gui/macosx/library/VLCInputNodePathControl.h \
	gui/macosx/library/VLCInputNodePathControl.m \
	gui/macosx/library/VLCInputNodePathControlItem.h \
	gui/macosx/library/VLCInputNodePathControlItem.m \
	gui/macosx/library/VLCLibraryAbstractGroupingDataSource.h \
	gui/macosx/library/VLCLibraryAbstractGroupingDataSource.m \
	gui/macosx/library/VLCLibraryAbstractMediaLibrarySegmentViewController.h \
	gui/macosx/library/VLCLibraryAbstractMediaLibrarySegmentViewController.m \
	gui/macosx/library/VLCLibraryAbstractSegmentViewController.h \
	gui/macosx/library/VLCLibraryAbstractSegmentViewController.m \
	gui/macosx/library/VLCLibraryAddToPlaylistMenuController.h \
	gui/macosx/library/VLCLibraryAddToPlaylistMenuController.m \
	gui/macosx/library/VLCLibraryCarouselViewItemView.h \
	gui/macosx/library/VLCLibraryCarouselViewItemView.m \
	gui/macosx/library/VLCLibraryCollectionView.h \
	gui/macosx/library/VLCLibraryCollectionView.m \
	gui/macosx/library/VLCLibraryCollectionViewDataSource.h \
	gui/macosx/library/VLCLibraryCollectionViewDelegate.h \
	gui/macosx/library/VLCLibraryCollectionViewDelegate.m \
	gui/macosx/library/VLCLibraryCollectionViewFlowLayout.h \
	gui/macosx/library/VLCLibraryCollectionViewFlowLayout.m \
	gui/macosx/library/VLCLibraryCollectionViewItem.h \
	gui/macosx/library/VLCLibraryCollectionViewItem.m \
	gui/macosx/library/VLCLibraryCollectionViewMediaItemSupplementaryDetailView.h \
	gui/macosx/library/VLCLibraryCollectionViewMediaItemSupplementaryDetailView.m \
	gui/macosx/library/VLCLibraryCollectionViewMediaItemListSupplementaryDetailView.h \
	gui/macosx/library/VLCLibraryCollectionViewMediaItemListSupplementaryDetailView.m \
	gui/macosx/library/VLCLibraryCollectionViewSupplementaryDetailView.h \
	gui/macosx/library/VLCLibraryCollectionViewSupplementaryDetailView.m \
	gui/macosx/library/VLCLibraryCollectionViewSupplementaryElementView.h \
	gui/macosx/library/VLCLibraryCollectionViewSupplementaryElementView.m \
	gui/macosx/library/VLCLibraryController.h \
	gui/macosx/library/VLCLibraryController.m \
	gui/macosx/library/VLCLibraryConnectableDataSource.h \
	gui/macosx/library/VLCLibraryDataSource.h \
	gui/macosx/library/VLCLibraryDataTypes.h \
	gui/macosx/library/VLCLibraryDataTypes.m \
	gui/macosx/library/VLCLibraryDynamicToolbarFlagsCapable.h \
	gui/macosx/library/VLCLibraryDynamicViewModeCapable.h \
	gui/macosx/library/VLCLibraryNameCache.h \
	gui/macosx/library/VLCLibraryNameCache.m \
	gui/macosx/library/VLCLibraryGroupHeaderDelegate.h \
	gui/macosx/library/VLCLibraryHeroView.h \
	gui/macosx/library/VLCLibraryHeroView.m \
	gui/macosx/library/VLCLibraryImageCache.h \
	gui/macosx/library/VLCLibraryImageCache.m \
	gui/macosx/library/VLCThumbnailRequest.h \
	gui/macosx/library/VLCThumbnailRequest.m \
	gui/macosx/library/VLCLibraryItemInternalMediaItemsDataSource.h \
	gui/macosx/library/VLCLibraryItemInternalMediaItemsDataSource.m \
	gui/macosx/library/VLCLibraryItemPresentingCapable.h \
	gui/macosx/library/VLCLibraryMasterDetailViewTableViewDataSource.h \
	gui/macosx/library/VLCLibraryMasterDetailViewTableViewDelegate.h \
	gui/macosx/library/VLCLibraryMasterDetailViewTableViewDelegate.m \
	gui/macosx/library/VLCLibraryMenuController.h \
	gui/macosx/library/VLCLibraryMenuController.m \
	gui/macosx/library/VLCLibraryModel.h \
	gui/macosx/library/VLCLibraryModel.m \
	gui/macosx/library/VLCLibraryModelChangeDelegate.h \
	gui/macosx/library/VLCLibraryModelChangeDelegate.m \
	gui/macosx/library/VLCLibraryRepresentedItem.h \
	gui/macosx/library/VLCLibraryRepresentedItem.m \
	gui/macosx/library/VLCLibrarySegment.h \
	gui/macosx/library/VLCLibrarySegment.m \
	gui/macosx/library/VLCLibrarySegmentBookmarkedLocation.h \
	gui/macosx/library/VLCLibrarySegmentBookmarkedLocation.m \
	gui/macosx/library/VLCLibrarySortingMenuController.h \
	gui/macosx/library/VLCLibrarySortingMenuController.m \
	gui/macosx/library/VLCLibraryTableView.h \
	gui/macosx/library/VLCLibraryTableView.m \
	gui/macosx/library/VLCLibraryTableViewDataSource.h \
	gui/macosx/library/VLCLibrarySectionedTableViewDataSource.h \
	gui/macosx/library/VLCLibraryTableViewDelegate.h \
	gui/macosx/library/VLCLibraryTableViewDelegate.m \
	gui/macosx/library/VLCLibraryTableCellView.h \
	gui/macosx/library/VLCLibraryTableCellView.m \
	gui/macosx/library/VLCLibraryTableCellViewProtocol.h \
	gui/macosx/library/VLCLibraryTwoPaneSplitViewDelegate.h \
	gui/macosx/library/VLCLibraryTwoPaneSplitViewDelegate.m \
	gui/macosx/library/VLCLibraryWindow.h \
	gui/macosx/library/VLCLibraryWindow.m \
	gui/macosx/library/VLCLibraryWindowController.h \
	gui/macosx/library/VLCLibraryWindowController.m \
	gui/macosx/library/VLCLibraryWindowAbstractSidebarViewController.h \
	gui/macosx/library/VLCLibraryWindowAbstractSidebarViewController.m \
	gui/macosx/library/VLCLibraryWindowChaptersSidebarViewController.h \
	gui/macosx/library/VLCLibraryWindowChaptersSidebarViewController.m \
	gui/macosx/library/VLCLibraryWindowNavigationSidebarOutlineView.h \
	gui/macosx/library/VLCLibraryWindowNavigationSidebarOutlineView.m \
	gui/macosx/library/VLCLibraryWindowNavigationSidebarViewController.h \
	gui/macosx/library/VLCLibraryWindowNavigationSidebarViewController.m \
	gui/macosx/library/VLCLibraryWindowPersistentPreferences.h \
	gui/macosx/library/VLCLibraryWindowPersistentPreferences.m \
	gui/macosx/library/VLCLibraryWindowPlayQueueSidebarViewController.h \
	gui/macosx/library/VLCLibraryWindowPlayQueueSidebarViewController.m \
	gui/macosx/library/VLCLibraryWindowSidebarChildViewController.h \
	gui/macosx/library/VLCLibraryWindowSidebarRootViewController.h \
	gui/macosx/library/VLCLibraryWindowSidebarRootViewController.m \
	gui/macosx/library/VLCLibraryWindowSplitViewController.h \
	gui/macosx/library/VLCLibraryWindowSplitViewController.m \
	gui/macosx/library/VLCLibraryWindowTitlesSidebarViewController.h \
	gui/macosx/library/VLCLibraryWindowTitlesSidebarViewController.m \
	gui/macosx/library/VLCLibraryWindowToolbarDelegate.h \
	gui/macosx/library/VLCLibraryWindowToolbarDelegate.m \
	gui/macosx/library/VLCMediaLibraryFolderObserver.h \
	gui/macosx/library/VLCMediaLibraryFolderObserver.m \
	gui/macosx/library/groups-library/VLCLibraryGroupsDataSource.h \
	gui/macosx/library/groups-library/VLCLibraryGroupsDataSource.m \
	gui/macosx/library/groups-library/VLCLibraryGroupsViewController.h \
	gui/macosx/library/groups-library/VLCLibraryGroupsViewController.m \
	gui/macosx/library/home-library/VLCLibraryHomeViewActionButtonCell.h \
	gui/macosx/library/home-library/VLCLibraryHomeViewActionButtonCell.m \
	gui/macosx/library/home-library/VLCLibraryHomeViewActionsView.h \
	gui/macosx/library/home-library/VLCLibraryHomeViewActionsView.m \
	gui/macosx/library/home-library/VLCLibraryHomeViewAudioCarouselContainerView.h \
	gui/macosx/library/home-library/VLCLibraryHomeViewAudioCarouselContainerView.m \
	gui/macosx/library/home-library/VLCLibraryHomeViewBaseCarouselContainerView.h \
	gui/macosx/library/home-library/VLCLibraryHomeViewBaseCarouselContainerView.m \
	gui/macosx/library/home-library/VLCLibraryHomeViewStackViewController.h \
	gui/macosx/library/home-library/VLCLibraryHomeViewStackViewController.m \
	gui/macosx/library/home-library/VLCLibraryHomeViewContainerView.h \
	gui/macosx/library/home-library/VLCLibraryHomeViewController.h \
	gui/macosx/library/home-library/VLCLibraryHomeViewController.m \
	gui/macosx/library/home-library/VLCLibraryHomeViewVideoContainerView.h \
	gui/macosx/library/home-library/VLCLibraryHomeViewVideoCarouselContainerView.h \
	gui/macosx/library/home-library/VLCLibraryHomeViewVideoCarouselContainerView.m \
    gui/macosx/library/home-library/VLCLibraryHomeViewVideoContainerViewDataSource.h \
    gui/macosx/library/home-library/VLCLibraryHomeViewVideoContainerViewDataSource.m \
	gui/macosx/library/home-library/VLCLibraryHomeViewVideoGridContainerView.h \
    gui/macosx/library/home-library/VLCLibraryHomeViewVideoGridContainerView.m \
	gui/macosx/library/video-library/VLCLibraryMoviesDataSource.h \
	gui/macosx/library/video-library/VLCLibraryMoviesDataSource.m \
	gui/macosx/library/video-library/VLCLibraryShowsDataSource.h \
	gui/macosx/library/video-library/VLCLibraryShowsDataSource.m \
	gui/macosx/library/video-library/VLCLibraryVideoViewController.h \
	gui/macosx/library/video-library/VLCLibraryVideoViewController.m \
	gui/macosx/library/video-library/VLCLibraryVideoGroupDescriptor.h \
	gui/macosx/library/video-library/VLCLibraryVideoGroupDescriptor.m \
	gui/macosx/library/video-library/VLCLibraryVideoDataSource.h \
	gui/macosx/library/video-library/VLCLibraryVideoDataSource.m \
	gui/macosx/library/video-library/VLCLibraryVideoTableViewDelegate.h \
	gui/macosx/library/video-library/VLCLibraryVideoTableViewDelegate.m \
	gui/macosx/library/audio-library/VLCLibraryAlbumTableCellView.h \
	gui/macosx/library/audio-library/VLCLibraryAlbumTableCellView.m \
	gui/macosx/library/audio-library/VLCLibraryAlbumTracksTableViewDelegate.h \
	gui/macosx/library/audio-library/VLCLibraryAlbumTracksTableViewDelegate.m \
	gui/macosx/library/audio-library/VLCLibraryAllAudioGroupsMediaLibraryItem.h \
	gui/macosx/library/audio-library/VLCLibraryAllAudioGroupsMediaLibraryItem.m \
	gui/macosx/library/audio-library/VLCLibraryAudioDataSource.h \
	gui/macosx/library/audio-library/VLCLibraryAudioDataSource.m \
	gui/macosx/library/audio-library/VLCLibraryAudioGroupDataSource.h \
	gui/macosx/library/audio-library/VLCLibraryAudioGroupDataSource.m \
	gui/macosx/library/VLCLibraryHeaderCell.h \
	gui/macosx/library/VLCLibraryHeaderCell.m \
	gui/macosx/library/VLCLibraryHeaderView.h \
	gui/macosx/library/VLCLibraryHeaderView.m \
	gui/macosx/library/audio-library/VLCLibraryAudioGroupTableViewDelegate.h \
	gui/macosx/library/audio-library/VLCLibraryAudioGroupTableViewDelegate.m \
	gui/macosx/library/audio-library/VLCLibraryAudioTableViewDelegate.h \
	gui/macosx/library/audio-library/VLCLibraryAudioTableViewDelegate.m \
	gui/macosx/library/audio-library/VLCLibraryAudioViewController.h \
	gui/macosx/library/audio-library/VLCLibraryAudioViewController.m \
	gui/macosx/library/audio-library/VLCLibraryCollectionViewAudioGroupSupplementaryDetailView.h \
	gui/macosx/library/audio-library/VLCLibraryCollectionViewAudioGroupSupplementaryDetailView.m \
	gui/macosx/library/audio-library/VLCLibrarySongTableCellView.h \
	gui/macosx/library/audio-library/VLCLibrarySongTableCellView.m \
	gui/macosx/library/audio-library/VLCLibrarySongsTableViewSongPlayingTableCellView.h \
	gui/macosx/library/audio-library/VLCLibrarySongsTableViewSongPlayingTableCellView.m \
	gui/macosx/library/favorites-library/VLCLibraryFavoritesDataSource.h \
	gui/macosx/library/favorites-library/VLCLibraryFavoritesDataSource.m \
	gui/macosx/library/favorites-library/VLCLibraryFavoritesTableViewDelegate.h \
	gui/macosx/library/favorites-library/VLCLibraryFavoritesTableViewDelegate.m \
	gui/macosx/library/favorites-library/VLCLibraryFavoritesViewController.h \
	gui/macosx/library/favorites-library/VLCLibraryFavoritesViewController.m \
	gui/macosx/library/media-source/MacLCBrowseEmptyView.h \
	gui/macosx/library/media-source/MacLCBrowseEmptyView.m \
	gui/macosx/library/media-source/MacLCBrowseHeaderView.h \
	gui/macosx/library/media-source/MacLCBrowseHeaderView.m \
	gui/macosx/library/media-source/MacLCBrowseItemCollectionViewItem.h \
	gui/macosx/library/media-source/MacLCBrowseItemCollectionViewItem.m \
	gui/macosx/library/media-source/MacLCBrowseLocationCardItem.h \
	gui/macosx/library/media-source/MacLCBrowseLocationCardItem.m \
	gui/macosx/library/media-source/MacLCBrowseSectionHeaderView.h \
	gui/macosx/library/media-source/MacLCBrowseSectionHeaderView.m \
	gui/macosx/library/media-source/MacLCBrowseTableCellView.h \
	gui/macosx/library/media-source/MacLCBrowseTableCellView.m \
	gui/macosx/library/media-source/VLCLibraryMediaSourceViewController.h \
	gui/macosx/library/media-source/VLCLibraryMediaSourceViewController.m \
	gui/macosx/library/media-source/VLCMediaSource.h \
	gui/macosx/library/media-source/VLCMediaSource.m \
	gui/macosx/library/media-source/VLCLocalMediaSource.h \
	gui/macosx/library/media-source/VLCLocalMediaSource.m \
	gui/macosx/library/media-source/VLCLocalMediaSourceNodeObservation.h \
	gui/macosx/library/media-source/VLCLocalMediaSourceNodeObservation.m \
	gui/macosx/library/media-source/VLCMediaSourceNodeObservation.h \
	gui/macosx/library/media-source/VLCMediaSourceBaseDataSource.h \
	gui/macosx/library/media-source/VLCMediaSourceBaseDataSource.m \
	gui/macosx/library/media-source/VLCMediaSourceCollectionViewItem.h \
	gui/macosx/library/media-source/VLCMediaSourceCollectionViewItem.m \
	gui/macosx/library/media-source/VLCMediaSourceDataSource.h \
	gui/macosx/library/media-source/VLCMediaSourceDataSource.m \
	gui/macosx/library/media-source/VLCMediaSourceDeviceCollectionViewItem.h \
	gui/macosx/library/media-source/VLCMediaSourceDeviceCollectionViewItem.m \
	gui/macosx/library/media-source/VLCLibraryMediaSourceViewNavigationStack.h \
	gui/macosx/library/media-source/VLCLibraryMediaSourceViewNavigationStack.m \
	gui/macosx/library/media-source/VLCLibraryMediaSourceViewNavigationState.h \
	gui/macosx/library/media-source/VLCLibraryMediaSourceViewNavigationState.m \
	gui/macosx/library/media-source/VLCMediaSourceProvider.h \
	gui/macosx/library/media-source/VLCMediaSourceProvider.m \
	gui/macosx/library/playlist-library/VLCLibraryPlaylistDataSource.h \
	gui/macosx/library/playlist-library/VLCLibraryPlaylistDataSource.m \
	gui/macosx/library/playlist-library/VLCLibraryPlaylistViewController.h \
	gui/macosx/library/playlist-library/VLCLibraryPlaylistViewController.m \
	gui/macosx/library/VLCLibrarySectionedTableViewDelegate.h \
	gui/macosx/library/VLCLibrarySectionedTableViewDelegate.m \
	gui/macosx/library/search-library/VLCLibrarySearchDataSource.h \
	gui/macosx/library/search-library/VLCLibrarySearchDataSource.m \
	gui/macosx/library/search-library/VLCLibrarySearchProvider.h \
	gui/macosx/library/search-library/VLCLibrarySearchProvider.m \
	gui/macosx/library/search-library/VLCLibrarySearchViewController.h \
	gui/macosx/library/search-library/VLCLibrarySearchViewController.m \
	gui/macosx/main/CompatibilityFixes.h \
	gui/macosx/main/CompatibilityFixes.m \
	gui/macosx/main/VLCApplication.h \
	gui/macosx/main/VLCApplication.m \
	gui/macosx/main/VLCMain+Sparkle.h \
	gui/macosx/main/VLCMain+Sparkle.m \
	gui/macosx/main/VLCMain+OldPrefs.h \
	gui/macosx/main/VLCMain+OldPrefs.m \
	gui/macosx/main/VLCMain.h \
	gui/macosx/main/VLCMain.m \
	gui/macosx/main/macosx.m \
	gui/macosx/menus/VLCMainMenu.h \
	gui/macosx/menus/VLCMainMenu.m \
	gui/macosx/menus/VLCRecentStreamsMenuController.h \
	gui/macosx/menus/VLCRecentStreamsMenuController.m \
	gui/macosx/menus/VLCStatusBarIcon.h \
	gui/macosx/menus/VLCStatusBarIcon.m \
	gui/macosx/menus/renderers/VLCRendererDiscovery.h \
	gui/macosx/menus/renderers/VLCRendererDiscovery.m \
	gui/macosx/menus/renderers/VLCRendererItem.h \
	gui/macosx/menus/renderers/VLCRendererItem.m \
	gui/macosx/menus/renderers/VLCRendererMenuController.h \
	gui/macosx/menus/renderers/VLCRendererMenuController.m \
	gui/macosx/os-integration/Spotify.h \
	gui/macosx/os-integration/VLCClickerManager.h \
	gui/macosx/os-integration/VLCClickerManager.m \
	gui/macosx/os-integration/VLCSystemVolume.h \
	gui/macosx/os-integration/VLCSystemVolume.m \
	gui/macosx/os-integration/VLCDocumentController.h \
	gui/macosx/os-integration/VLCDocumentController.m \
	gui/macosx/os-integration/VLCKeyboardBacklightControl.h \
	gui/macosx/os-integration/VLCKeyboardBacklightControl.m \
	gui/macosx/os-integration/VLCRemoteControlService.h \
	gui/macosx/os-integration/VLCRemoteControlService.m \
	gui/macosx/os-integration/applescript.h \
	gui/macosx/os-integration/applescript.m \
	gui/macosx/os-integration/iTunes.h \
	gui/macosx/panels/VLCAudioEffectsWindowController.h \
	gui/macosx/panels/VLCAudioEffectsWindowController.m \
	gui/macosx/panels/VLCBookmarksWindowController.h \
	gui/macosx/panels/VLCBookmarksWindowController.m \
	gui/macosx/panels/VLCInformationWindowController.h \
	gui/macosx/panels/VLCInformationWindowController.m \
	gui/macosx/panels/VLCTimeSelectionPanelController.h \
	gui/macosx/panels/VLCTimeSelectionPanelController.m \
	gui/macosx/panels/VLCTrackSynchronizationWindowController.h \
	gui/macosx/panels/VLCTrackSynchronizationWindowController.m \
	gui/macosx/panels/VLCVideoEffectsWindowController.h \
	gui/macosx/panels/VLCVideoEffectsWindowController.m \
	gui/macosx/panels/bookmarks/VLCBookmark.h \
	gui/macosx/panels/bookmarks/VLCBookmark.m \
	gui/macosx/panels/bookmarks/VLCBookmarksTableViewDataSource.h \
	gui/macosx/panels/bookmarks/VLCBookmarksTableViewDataSource.m \
	gui/macosx/panels/bookmarks/VLCBookmarksTableViewDelegate.h \
	gui/macosx/panels/bookmarks/VLCBookmarksTableViewDelegate.m \
	gui/macosx/panels/dialogs/VLCCoreDialogProvider.h \
	gui/macosx/panels/dialogs/VLCCoreDialogProvider.m \
	gui/macosx/panels/dialogs/VLCCustomCropArWindowController.h \
	gui/macosx/panels/dialogs/VLCCustomCropArWindowController.m \
	gui/macosx/panels/dialogs/VLCPopupPanelController.h \
	gui/macosx/panels/dialogs/VLCPopupPanelController.m \
	gui/macosx/panels/dialogs/VLCResumeDialogController.h \
	gui/macosx/panels/dialogs/VLCResumeDialogController.m \
	gui/macosx/panels/dialogs/VLCTextfieldPanelController.h \
	gui/macosx/panels/dialogs/VLCTextfieldPanelController.m \
	gui/macosx/playqueue/VLCPlaybackContinuityController.h \
	gui/macosx/playqueue/VLCPlaybackContinuityController.m \
	gui/macosx/playqueue/VLCPlayerChapter.h \
	gui/macosx/playqueue/VLCPlayerChapter.m \
	gui/macosx/playqueue/VLCPlayerController.h \
	gui/macosx/playqueue/VLCPlayerController.m \
	gui/macosx/playqueue/VLCPlayerTitle.h \
	gui/macosx/playqueue/VLCPlayerTitle.m \
	gui/macosx/playqueue/VLCPlayQueueController.h \
	gui/macosx/playqueue/VLCPlayQueueController.m \
	gui/macosx/playqueue/VLCPlayQueueDataSource.h \
	gui/macosx/playqueue/VLCPlayQueueDataSource.m \
	gui/macosx/playqueue/VLCPlayQueueItem.h \
	gui/macosx/playqueue/VLCPlayQueueItem.m \
	gui/macosx/playqueue/VLCPlayQueueMenuController.h \
	gui/macosx/playqueue/VLCPlayQueueMenuController.m \
	gui/macosx/playqueue/VLCPlayQueueModel.h \
	gui/macosx/playqueue/VLCPlayQueueModel.m \
	gui/macosx/playqueue/VLCPlayQueueSortingMenuController.h \
	gui/macosx/playqueue/VLCPlayQueueSortingMenuController.m \
	gui/macosx/playqueue/VLCPlayQueueTableCellView.h \
	gui/macosx/playqueue/VLCPlayQueueTableCellView.m \
	gui/macosx/playqueue/VLCPlayQueueTableView.h \
	gui/macosx/playqueue/VLCPlayQueueTableView.m \
	gui/macosx/preferences/VLCHotkeyChangeWindow.h \
	gui/macosx/preferences/VLCHotkeyChangeWindow.m \
	gui/macosx/preferences/VLCSimplePrefsController.h \
	gui/macosx/preferences/VLCSimplePrefsController.m \
	gui/macosx/preferences/VLCSimplePrefsWindow.h \
	gui/macosx/preferences/VLCSimplePrefsWindow.m \
	gui/macosx/preferences/prefs.h \
	gui/macosx/preferences/prefs.m \
	gui/macosx/preferences/prefs_widgets.h \
	gui/macosx/preferences/prefs_widgets.m \
	gui/macosx/settings/MacLCConfigSafe.h \
	gui/macosx/settings/MacLCConfigSafe.m \
	gui/macosx/settings/MacLCSettingsPane.h \
	gui/macosx/settings/MacLCSettingsRow.h \
	gui/macosx/settings/MacLCSettingsRow.m \
	gui/macosx/settings/MacLCSettingsSelfTest.h \
	gui/macosx/settings/MacLCSettingsSelfTest.m \
	gui/macosx/settings/MacLCSettingsWindowController.h \
	gui/macosx/settings/MacLCSettingsWindowController.m \
	gui/macosx/settings/panes/MacLCAudioSettingsViewController.h \
	gui/macosx/settings/panes/MacLCAudioSettingsViewController.m \
	gui/macosx/settings/panes/MacLCGeneralSettingsViewController.h \
	gui/macosx/settings/panes/MacLCGeneralSettingsViewController.m \
	gui/macosx/settings/panes/MacLCHDRSettingsViewController.h \
	gui/macosx/settings/panes/MacLCHDRSettingsViewController.m \
	gui/macosx/settings/panes/MacLCInterfaceSettingsViewController.h \
	gui/macosx/settings/panes/MacLCInterfaceSettingsViewController.m \
	gui/macosx/settings/panes/MacLCPlaybackSettingsViewController.h \
	gui/macosx/settings/panes/MacLCPlaybackSettingsViewController.m \
	gui/macosx/settings/panes/MacLCShortcutsSettingsViewController.h \
	gui/macosx/settings/panes/MacLCShortcutsSettingsViewController.m \
	gui/macosx/settings/panes/MacLCSubtitlesSettingsViewController.h \
	gui/macosx/settings/panes/MacLCSubtitlesSettingsViewController.m \
	gui/macosx/settings/panes/MacLCVideoSettingsViewController.h \
	gui/macosx/settings/panes/MacLCVideoSettingsViewController.m \
	gui/macosx/shaders/VLCShaderTypes.h \
	gui/macosx/hdr/MacLCDisplayInfo.h \
	gui/macosx/hdr/MacLCDisplayInfo.m \
	gui/macosx/hdr/MacLCHDRAdvisor.h \
	gui/macosx/hdr/MacLCHDRAdvisor.m \
	gui/macosx/hdr/MacLCHDRCardView.h \
	gui/macosx/hdr/MacLCHDRCardView.m \
	gui/macosx/hdr/MacLCHDRController.h \
	gui/macosx/hdr/MacLCHDRController.m \
	gui/macosx/hdr/MacLCHDRMenuController.h \
	gui/macosx/hdr/MacLCHDRMenuController.m \
	gui/macosx/hdr/MacLCHDRPanelViewController.h \
	gui/macosx/hdr/MacLCHDRPanelViewController.m \
	gui/macosx/hdr/MacLCHDRStreamInfo.h \
	gui/macosx/hdr/MacLCHDRStreamInfo.m \
	gui/macosx/hdr/MacLCHDRTypes.h \
	gui/macosx/hdr/MacLCHDRTypes.m \
	gui/macosx/hdr/MacLCToneCurveView.h \
	gui/macosx/hdr/MacLCToneCurveView.m \
	gui/macosx/hdr/MacLCTradeoffMeterView.h \
	gui/macosx/hdr/MacLCTradeoffMeterView.m \
	gui/macosx/frameinterp/MacLCFrameInterpolation.h \
	gui/macosx/frameinterp/MacLCFrameInterpolation.m \
	gui/macosx/frameinterp/MacLCFrameInterpolationPanelViewController.h \
	gui/macosx/frameinterp/MacLCFrameInterpolationPanelViewController.m \
	video_filter/maclc_frc_geometry.h \
	video_filter/maclc_frc_geometry.c \
	gui/macosx/theme/MacLCCardView.h \
	gui/macosx/theme/MacLCCardView.m \
	gui/macosx/theme/MacLCDesign.h \
	gui/macosx/theme/MacLCDesign.m \
	gui/macosx/theme/MacLCFormatBadgeView.h \
	gui/macosx/theme/MacLCFormatBadgeView.m \
	gui/macosx/theme/MacLCGlassContainerView.h \
	gui/macosx/theme/MacLCGlassContainerView.m \
	gui/macosx/theme/MacLCGlassView.h \
	gui/macosx/theme/MacLCGlassView.m \
	gui/macosx/theme/MacLCOSDView.h \
	gui/macosx/theme/MacLCOSDView.m \
	gui/macosx/theme/MacLCSymbolButton.h \
	gui/macosx/theme/MacLCSymbolButton.m \
	gui/macosx/views/iCarousel/iCarousel.h \
	gui/macosx/views/iCarousel/iCarousel.m \
	gui/macosx/views/VLCBasicView.h \
	gui/macosx/views/VLCBasicView.m \
	gui/macosx/views/VLCBottomBarView.h \
	gui/macosx/views/VLCBottomBarView.m \
	gui/macosx/views/VLCDefaultValueSlider.h \
	gui/macosx/views/VLCDefaultValueSlider.m \
	gui/macosx/views/VLCDefaultValueSliderCell.h \
	gui/macosx/views/VLCDefaultValueSliderCell.m \
	gui/macosx/views/VLCDragDropView.h \
	gui/macosx/views/VLCDragDropView.m \
	gui/macosx/views/VLCFileDragRecognisingView.h \
	gui/macosx/views/VLCFileDragRecognisingView.m \
	gui/macosx/views/VLCImageButton.h \
	gui/macosx/views/VLCImageButton.m \
	gui/macosx/views/VLCImageView.h \
	gui/macosx/views/VLCImageView.m \
	gui/macosx/views/VLCLibraryRatingIndicator.h \
	gui/macosx/views/VLCLibraryRatingIndicator.m \
	gui/macosx/views/VLCLinearProgressIndicator.h \
	gui/macosx/views/VLCLinearProgressIndicator.m \
	gui/macosx/views/VLCLoadingOverlayView.h \
	gui/macosx/views/VLCLoadingOverlayView.m \
	gui/macosx/views/VLCMediaItemCollectionViewItem.h \
	gui/macosx/views/VLCMediaItemCollectionViewItem.m \
	gui/macosx/views/VLCNoResultsLabel.h \
	gui/macosx/views/VLCNoResultsLabel.m \
	gui/macosx/views/VLCPlaybackEndViewController.h \
	gui/macosx/views/VLCPlaybackEndViewController.m \
	gui/macosx/views/VLCPlaybackProgressSlider.h \
	gui/macosx/views/VLCPlaybackProgressSlider.m \
	gui/macosx/views/VLCPlaybackProgressSliderCell.h \
	gui/macosx/views/VLCPlaybackProgressSliderCell.m \
	gui/macosx/views/VLCRoundedCornerTextField.h \
	gui/macosx/views/VLCRoundedCornerTextField.m \
	gui/macosx/views/VLCScrollingClipView.h \
	gui/macosx/views/VLCScrollingClipView.m \
	gui/macosx/views/VLCSettingTextField.h \
	gui/macosx/views/VLCSettingTextField.m \
	gui/macosx/views/VLCSnowEffectView.h \
	gui/macosx/views/VLCSnowEffectView.m \
	gui/macosx/views/VLCSpacingConstraint.h \
	gui/macosx/views/VLCSpacingConstraint.m \
	gui/macosx/views/VLCStackView.h \
	gui/macosx/views/VLCStackView.m \
	gui/macosx/views/VLCStatusNotifierView.h \
	gui/macosx/views/VLCStatusNotifierView.m \
	gui/macosx/views/VLCSubScrollView.h \
	gui/macosx/views/VLCSubScrollView.m \
	gui/macosx/views/VLCTimeField.h \
	gui/macosx/views/VLCTimeField.m \
	gui/macosx/views/VLCTimeFormatter.h \
	gui/macosx/views/VLCTimeFormatter.m \
	gui/macosx/views/VLCTrackingView.h \
	gui/macosx/views/VLCTrackingView.m \
	gui/macosx/views/VLCUIUnits.h \
	gui/macosx/views/VLCUIUnits.m \
	gui/macosx/views/VLCVolumeSlider.h \
	gui/macosx/views/VLCVolumeSlider.m \
	gui/macosx/views/VLCVolumeSliderCell.h \
	gui/macosx/views/VLCVolumeSliderCell.m \
	gui/macosx/windows/VLCAboutWindowController.h \
	gui/macosx/windows/VLCAboutWindowController.m \
	gui/macosx/windows/VLCConnectToServerDialog.h \
	gui/macosx/windows/VLCConnectToServerDialog.m \
	gui/macosx/windows/VLCDetachedAudioWindow.h \
	gui/macosx/windows/VLCDetachedAudioWindow.m \
	gui/macosx/windows/VLCErrorWindowController.h \
	gui/macosx/windows/VLCErrorWindowController.m \
	gui/macosx/windows/VLCHelpWindowController.h \
	gui/macosx/windows/VLCHelpWindowController.m \
	gui/macosx/windows/VLCOpenInputMetadata.h \
	gui/macosx/windows/VLCOpenInputMetadata.m \
	gui/macosx/windows/VLCOpenWindowController.h \
	gui/macosx/windows/VLCOpenWindowController.m \
	gui/macosx/windows/addons/VLCAddonListItem.h \
	gui/macosx/windows/addons/VLCAddonListItem.m \
	gui/macosx/windows/addons/VLCAddonsWindowController.h \
	gui/macosx/windows/addons/VLCAddonsWindowController.m \
	gui/macosx/windows/convertandsave/VLCConvertAndSaveWindowController.h \
	gui/macosx/windows/convertandsave/VLCConvertAndSaveWindowController.m \
	gui/macosx/windows/convertandsave/VLCOutput.h \
	gui/macosx/windows/convertandsave/VLCOutput.m \
	gui/macosx/windows/extensions/VLCExtensionsDialogProvider.h \
	gui/macosx/windows/extensions/VLCExtensionsDialogProvider.m \
	gui/macosx/windows/extensions/VLCExtensionsManager.h \
	gui/macosx/windows/extensions/VLCExtensionsManager.m \
	gui/macosx/windows/extensions/VLCUIWidgets.h \
	gui/macosx/windows/extensions/VLCUIWidgets.m \
	gui/macosx/windows/logging/VLCLogMessage.h \
	gui/macosx/windows/logging/VLCLogMessage.m \
	gui/macosx/windows/logging/VLCLogWindowController.h \
	gui/macosx/windows/logging/VLCLogWindowController.m \
	gui/macosx/windows/controlsbar/VLCControlsBarCommon.h \
	gui/macosx/windows/controlsbar/VLCControlsBarCommon.m \
	gui/macosx/windows/controlsbar/VLCMainVideoViewControlsBar.h \
	gui/macosx/windows/controlsbar/VLCMainVideoViewControlsBar.m \
	gui/macosx/windows/controlsbar/VLCMainWindowControlsBar.h \
	gui/macosx/windows/controlsbar/VLCMainWindowControlsBar.m \
	gui/macosx/windows/video/MacLCVideoFitGeometry.h \
	gui/macosx/windows/video/MacLCVideoFitGeometry.m \
	gui/macosx/windows/video/VLCAspectRatioRetainingVideoWindow.h \
	gui/macosx/windows/video/VLCAspectRatioRetainingVideoWindow.m \
	gui/macosx/windows/video/VLCFullVideoViewWindow.h \
	gui/macosx/windows/video/VLCFullVideoViewWindow.m \
	gui/macosx/windows/video/VLCMainVideoViewAudioMediaDecorativeView.h \
	gui/macosx/windows/video/VLCMainVideoViewAudioMediaDecorativeView.m \
	gui/macosx/windows/video/VLCMainVideoViewController.h \
	gui/macosx/windows/video/VLCMainVideoViewController.m \
	gui/macosx/windows/video/VLCMainVideoViewOverlayView.h \
	gui/macosx/windows/video/VLCMainVideoViewOverlayView.m \
	gui/macosx/windows/video/VLCVideoOutputProvider.h \
	gui/macosx/windows/video/VLCVideoOutputProvider.m \
	gui/macosx/windows/video/VLCVideoWindowCommon.h \
	gui/macosx/windows/video/VLCVideoWindowCommon.m \
	gui/macosx/windows/video/VLCVoutView.h \
	gui/macosx/windows/video/VLCVoutView.m \
	gui/macosx/windows/video/VLCWindow.h \
	gui/macosx/windows/video/VLCWindow.m


# User interface compilation

libmacosx_plugin_la_XIB_SOURCES = \
	gui/macosx/UI/About.xib \
	gui/macosx/UI/AddonManager.xib \
	gui/macosx/UI/AudioEffects.xib \
	gui/macosx/UI/Bookmarks.xib \
	gui/macosx/UI/ConvertAndSave.xib \
	gui/macosx/UI/CoreDialogs.xib \
	gui/macosx/UI/ErrorPanel.xib \
	gui/macosx/UI/Help.xib \
	gui/macosx/UI/LogMessageWindow.xib \
	gui/macosx/UI/MainMenu.xib \
	gui/macosx/UI/VLCCustomCropARPanel.xib \
	gui/macosx/UI/VLCDetachedAudioWindow.xib \
	gui/macosx/UI/VLCLibraryAlbumTableCellView.xib \
	gui/macosx/UI/VLCLibraryWindow.xib \
	gui/macosx/UI/VLCLibraryWindowChaptersView.xib \
	gui/macosx/UI/VLCLibraryWindowNavigationSidebarView.xib \
	gui/macosx/UI/VLCLibraryWindowPlayQueueView.xib \
	gui/macosx/UI/VLCLibraryWindowSidebarRootView.xib \
	gui/macosx/UI/VLCLibraryWindowTitlesView.xib \
	gui/macosx/UI/VLCLibraryTableCellView.xib \
	gui/macosx/UI/VLCLibraryVideoTableCellView.xib \
	gui/macosx/UI/VLCPlayQueueTableCellView.xib \
	gui/macosx/UI/VLCLibraryCarouselViewItemView.xib \
	gui/macosx/UI/VLCLibraryCollectionViewMediaItemListSupplementaryDetailView.xib \
	gui/macosx/UI/VLCLibraryCollectionViewAudioGroupSupplementaryDetailView.xib \
	gui/macosx/UI/VLCLibraryCollectionViewMediaItemSupplementaryDetailView.xib \
	gui/macosx/UI/VLCLibraryHeroView.xib \
	gui/macosx/UI/VLCLibraryHomeViewActionsView.xib \
	gui/macosx/UI/VLCLibrarySongTableCellView.xib \
	gui/macosx/UI/VLCClassicMainVideoView.xib \
	gui/macosx/UI/VLCMainVideoView.xib \
	gui/macosx/UI/VLCMainVideoViewAudioMediaDecorativeView.xib \
	gui/macosx/UI/VLCMediaItemCollectionViewItem.xib \
	gui/macosx/UI/VLCMediaSourceDeviceCollectionViewItem.xib \
	gui/macosx/UI/VLCInformationWindow.xib \
	gui/macosx/UI/VLCPlaybackEndView.xib \
	gui/macosx/UI/Open.xib \
	gui/macosx/UI/PlaylistAccessoryView.xib \
	gui/macosx/UI/PopupPanel.xib \
	gui/macosx/UI/Preferences.xib \
	gui/macosx/UI/ResumeDialog.xib \
	gui/macosx/UI/SimplePreferences.xib \
	gui/macosx/UI/StreamOutput.xib \
	gui/macosx/UI/SyncTracks.xib \
	gui/macosx/UI/TextfieldPanel.xib \
	gui/macosx/UI/TimeSelectionPanel.xib \
	gui/macosx/UI/VideoEffects.xib \
	gui/macosx/UI/VLCFullScreenPanel.xib \
	gui/macosx/UI/VLCStatusBarIconMainMenu.xib

libmacosx_plugin_la_SOURCES += $(libmacosx_plugin_la_XIB_SOURCES)

if ENABLE_MACOSX_UI
gui_PLUGINS += libmacosx_plugin.la
BUILT_SOURCES += $(libmacosx_plugin_la_XIB_SOURCES:.xib=.nib)
endif

libmacosx_plugin_la_RES = \
	gui/macosx/Resources/App-Icons/MacLC.icns \
	gui/macosx/Resources/browsewindow/bw-Music.png \
	gui/macosx/Resources/browsewindow/bw-Music@2x.png \
	gui/macosx/Resources/browsewindow/bw-Music@3x.png \
	gui/macosx/Resources/browsewindow/bw-Server1.png \
	gui/macosx/Resources/browsewindow/bw-Server1@2x.png \
	gui/macosx/Resources/browsewindow/bw-Server1@3x.png \
	gui/macosx/Resources/browsewindow/bw-home.png \
	gui/macosx/Resources/browsewindow/bw-home@2x.png \
	gui/macosx/Resources/browsewindow/bw-home@3x.png \
	gui/macosx/Resources/browsewindow/bw-server2.png \
	gui/macosx/Resources/browsewindow/bw-server2@2x.png \
	gui/macosx/Resources/browsewindow/bw-server2@3x.png \
	gui/macosx/Resources/browsewindow/bw-usb1.png \
	gui/macosx/Resources/browsewindow/bw-usb1@2x.png \
	gui/macosx/Resources/browsewindow/bw-usb1@3x.png \
	gui/macosx/Resources/browsewindow/bw-usb2.png \
	gui/macosx/Resources/browsewindow/bw-usb2@2x.png \
	gui/macosx/Resources/browsewindow/bw-usb2@3x.png \
	gui/macosx/Resources/librarywindow/ellipsis.png \
	gui/macosx/Resources/librarywindow/ellipsis@2x.png \
	gui/macosx/Resources/librarywindow/libraryPlay.png \
	gui/macosx/Resources/librarywindow/libraryPlay@2x.png \
	gui/macosx/Resources/librarywindow/repeatAll.png \
	gui/macosx/Resources/librarywindow/repeatAll@2x.png \
	gui/macosx/Resources/librarywindow/repeatOff.png \
	gui/macosx/Resources/librarywindow/repeatOff@2x.png \
	gui/macosx/Resources/librarywindow/repeatOne.png \
	gui/macosx/Resources/librarywindow/repeatOne@2x.png \
	gui/macosx/Resources/librarywindow/shuffleOff.png \
	gui/macosx/Resources/librarywindow/shuffleOff@2x.png \
	gui/macosx/Resources/librarywindow/shuffleOn.png \
	gui/macosx/Resources/librarywindow/shuffleOn@2x.png \
	gui/macosx/Resources/mainwindow/placeholder-group2.pdf \
	gui/macosx/Resources/mainwindow/placeholder-group2.png \
	gui/macosx/Resources/mainwindow/placeholder-group2.svg \
	gui/macosx/Resources/mainwindow/placeholder-group2@2x.png \
	gui/macosx/Resources/mainwindow/placeholder-music.pdf \
	gui/macosx/Resources/mainwindow/placeholder-music.png \
	gui/macosx/Resources/mainwindow/placeholder-music.svg \
	gui/macosx/Resources/mainwindow/placeholder-music@2x.png \
	gui/macosx/Resources/mainwindow/placeholder-video.pdf \
	gui/macosx/Resources/mainwindow/placeholder-video.png \
	gui/macosx/Resources/mainwindow/placeholder-video.svg \
	gui/macosx/Resources/mainwindow/placeholder-video@2x.png \
	gui/macosx/Resources/noart.png \
	gui/macosx/Resources/sidebar-icons/sidebar-movie.png \
	gui/macosx/Resources/sidebar-icons/sidebar-movie@2x.png \
	gui/macosx/Resources/sidebar-icons/sidebar-music.png \
	gui/macosx/Resources/sidebar-icons/sidebar-music@2x.png \
	gui/macosx/Resources/Button-Icons/MacLCStatusBarIcon.pdf

libmacosx_plugin_la_RES += \
	gui/macosx/Resources/dsa_pub.pem \
	gui/macosx/Resources/README \
	gui/macosx/Resources/vlc.scriptSuite \
	gui/macosx/Resources/vlc.scriptTerminology

EXTRA_DIST += \
	gui/macosx/Resources/Base.lproj/InfoPlist.strings \
	gui/macosx/Resources/ar.lproj/InfoPlist.strings \
	gui/macosx/Resources/bg.lproj/InfoPlist.strings \
	gui/macosx/Resources/ca.lproj/InfoPlist.strings \
	gui/macosx/Resources/cs.lproj/InfoPlist.strings \
	gui/macosx/Resources/de.lproj/InfoPlist.strings \
	gui/macosx/Resources/el.lproj/InfoPlist.strings \
	gui/macosx/Resources/es.lproj/InfoPlist.strings \
	gui/macosx/Resources/fr.lproj/InfoPlist.strings \
	gui/macosx/Resources/gl.lproj/InfoPlist.strings \
	gui/macosx/Resources/he.lproj/InfoPlist.strings \
	gui/macosx/Resources/hu.lproj/InfoPlist.strings \
	gui/macosx/Resources/it.lproj/InfoPlist.strings \
	gui/macosx/Resources/ja.lproj/InfoPlist.strings \
	gui/macosx/Resources/lv.lproj/InfoPlist.strings \
	gui/macosx/Resources/nl.lproj/InfoPlist.strings \
	gui/macosx/Resources/pl.lproj/InfoPlist.strings \
	gui/macosx/Resources/pt-BR.lproj/InfoPlist.strings \
	gui/macosx/Resources/pt-PT.lproj/InfoPlist.strings \
	gui/macosx/Resources/sk.lproj/InfoPlist.strings \
	gui/macosx/Resources/sl.lproj/InfoPlist.strings \
	gui/macosx/Resources/sv.lproj/InfoPlist.strings \
	gui/macosx/Resources/tr.lproj/InfoPlist.strings \
	gui/macosx/Resources/uk.lproj/InfoPlist.strings \
	gui/macosx/Resources/zh-Hans.lproj/InfoPlist.strings

if ENABLE_MACOSX_UI
dist_libmacosx_plugin_la_DATA = $(libmacosx_plugin_la_RES)
endif

libmacosx_plugin_ladir = $(prefix)/share/macosx/Contents/Resources

include gui/macosx/tests/Makefile.am
