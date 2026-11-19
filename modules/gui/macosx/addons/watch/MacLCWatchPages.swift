/*****************************************************************************
 * MacLCWatchPages.swift: Watch's See All and collection pages in SwiftUI
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

/* MacLCWatchCatalogViewController ("See All") and
 * MacLCWatchCollectionViewController (a collection of The Edit) from
 * MacLCWatchBrowse.m in SwiftUI, pushed by the SwiftUI browse page
 * (MACLC_SWIFTUI_WATCH=1); contracts in MacLCWatchSections.h. Each is a
 * vertical page with a poster grid (WatchPosterGrid, which the browse page's
 * search results use too), in an NSHostingController pushed on the section.
 * Same rules as the browse page: no SwiftUI animation while a scroll view
 * moves, plain button styles, lazy stacks, pictures from MacLCWatchImageCache. */

import AppKit
import Observation
import SwiftUI

// MARK: - Poster grid

/// MacLCWatchLayout posterGridSectionWithEnvironment:hasHeader:: as many
/// columns as fit at 150-200 wide, 20 apart, in the width less the margins.
func posterGridMetrics(width: CGFloat) -> (columns: Int, itemWidth: CGFloat) {
    let available = max(width - 2 * sideInset, 150)
    var columns = max(1, Int((available + itemSpacing) / (150 + itemSpacing)))
    var itemWidth = (available - CGFloat(columns - 1) * itemSpacing) / CGFloat(columns)
    while itemWidth > 200 {
        columns += 1
        itemWidth = (available - CGFloat(columns - 1) * itemSpacing) / CGFloat(columns)
    }
    return (columns, itemWidth.rounded(.down))
}

/// A poster grid: 32 between rows, 16 above, 36 below, 40 pt margins; nil
/// items: placeholders. The cells take the keyboard focus as (row, index);
/// the arrow keys move along a row or a row up or down.
struct WatchPosterGrid: View {
    let items: [MacLCAddonItem]?
    var placeholders = 8
    let row: String
    /// The page's width, from a GeometryReader round its scroll view: the
    /// scroll view itself takes the width of the grid inside, so measuring it
    /// kept a grid laid out for a wider window after the window shrank.
    let width: CGFloat
    let model: any WatchPageModel
    var focus: FocusState<WatchFocus?>.Binding
    /// The cell at index came into view (paging).
    var cellAppeared: (Int) -> Void = { _ in }

    var body: some View {
        let grid = posterGridMetrics(width: width)
        let count = items?.count ?? 0
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(grid.itemWidth), spacing: itemSpacing, alignment: .top),
                                 count: grid.columns),
                  alignment: .leading, spacing: 32) {
            // One ForEach: placeholder i becomes title i in place.
            ForEach(0..<(items?.count ?? placeholders), id: \.self) { index in
                let item = items?[index]
                PosterCell(item: item, rank: 0, width: grid.itemWidth, model: model)
                    .watchCell(WatchFocus(row: row, index: index), focus: focus, enabled: item != nil) {
                        if let item { model.open(item, showStreams: false) }
                    }
                    .onAppear { cellAppeared(index) }
            }
        }
        .padding(.top, 16)
        .padding(.horizontal, sideInset)
        .padding(.bottom, sectionSpacing)
        .onMoveCommand { direction in
            guard let current = focus.wrappedValue, current.row == row else { return }
            let step: Int
            switch direction {
            case .left: step = -1
            case .right: step = 1
            case .up: step = -grid.columns
            case .down: step = grid.columns
            @unknown default: step = 0
            }
            let index = current.index + step
            if index >= 0, index < count {
                focus.wrappedValue = WatchFocus(row: row, index: index)
            }
        }
    }
}

// MARK: - See All

/// MacLCWatchCatalogViewController's data: pages of one catalog (and genre)
/// appended while the add-on keeps answering with new titles.
@Observable
final class WatchCatalogModel: WatchPageModel {
    @ObservationIgnored let localize: (String) -> String
    @ObservationIgnored let scrolling = ScrollActivity()
    @ObservationIgnored let marks = WatchMarks()
    @ObservationIgnored let title: String
    @ObservationIgnored private weak var section: MacLCWatchSectionViewController?
    @ObservationIgnored private let catalog: MacLCAddonTitleCatalog
    @ObservationIgnored private let genre: String?
    @ObservationIgnored private let errorMessage: (Error?) -> String

    /// nil until the first page answers (placeholders).
    private(set) var items: [MacLCAddonItem]?
    /// The first page failed.
    private(set) var emptyState: WatchEmptyState?

    @ObservationIgnored private var seen = Set<String>()
    @ObservationIgnored private var request: MacLCAddonRequest?
    @ObservationIgnored private var loading = false
    @ObservationIgnored private var reachedEnd = false

    /// The page to push on the section, titled for the window title.
    static func controller(section: MacLCWatchSectionViewController, catalog: MacLCAddonTitleCatalog,
                           genre: String?, title: String, localize: @escaping (String) -> String,
                           errorMessage: @escaping (Error?) -> String) -> NSViewController {
        let model = WatchCatalogModel(section: section, catalog: catalog, genre: genre, title: title,
                                      localize: localize, errorMessage: errorMessage)
        let controller = NSHostingController(rootView: WatchCatalogPage(model: model))
        // The section pins the view to its edges: no size from SwiftUI.
        controller.sizingOptions = []
        controller.title = title
        model.loadNextPage()
        return controller
    }

    private init(section: MacLCWatchSectionViewController, catalog: MacLCAddonTitleCatalog, genre: String?,
                 title: String, localize: @escaping (String) -> String,
                 errorMessage: @escaping (Error?) -> String) {
        self.section = section
        self.catalog = catalog
        self.genre = genre
        self.title = title
        self.localize = localize
        self.errorMessage = errorMessage
    }

    isolated deinit {
        request?.cancel()
    }

    /// The next page (skip = titles so far), unless one is loading, the end
    /// was reached or the catalog cannot skip.
    func loadNextPage() {
        guard !loading, !reachedEnd else { return }
        let count = items?.count ?? 0
        if count > 0 && !catalog.supportsSkip {
            reachedEnd = true
            return
        }
        loading = true
        request = MacLCAddonStore.shared.fetchTitleCatalog(catalog, genre: genre, skip: UInt(count)) {
            [weak self] newItems, error in
            self?.pageLoaded(newItems, error: error)
        }
    }

    /// Stops on a failure after the first page, an empty page or a page of
    /// titles already shown.
    private func pageLoaded(_ newItems: [MacLCAddonItem]?, error: Error?) {
        loading = false
        request = nil
        guard let newItems, error == nil else {
            if (items ?? []).isEmpty {
                emptyState = WatchEmptyState(symbol: "wifi.exclamationmark", title: localize("Can't Load Add-ons"),
                                             message: errorMessage(error), button: localize("Try Again"),
                                             prominent: false, action: .retry)
            } else {
                reachedEnd = true
            }
            return
        }
        var fresh: [MacLCAddonItem] = []
        for item in newItems where seen.insert(item.identifier).inserted {
            fresh.append(item)
        }
        emptyState = nil
        if fresh.isEmpty {
            reachedEnd = true
            if items == nil {
                items = []
            }
            return
        }
        items = (items ?? []) + fresh
    }

    /// Paging: the next page once one of the last 8 cells shows.
    func cellAppeared(_ index: Int) {
        if index >= (items?.count ?? 0) - 8 {
            loadNextPage()
        }
    }

    func retry() {
        emptyState = nil
        loadNextPage()
    }

    func open(_ item: MacLCAddonItem, showStreams: Bool) {
        section?.showDetail(for: item, showStreams: showStreams)
    }
}

/// The title as a shelf header (MacLCWatchShelfHeaderView, no buttons), then
/// the grid; the failed state replaces both.
struct WatchCatalogPage: View {
    let model: WatchCatalogModel

    @FocusState private var focus: WatchFocus?

    var body: some View {
        let failed = model.emptyState != nil
        ZStack {
            GeometryReader { proxy in
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 0) {
                        ShelfHeader(title: model.title, subtitle: nil, topic: nil, filter: nil, model: model,
                                    seeAll: nil, paging: nil, page: { _ in }, chooseFilter: { _ in })
                            .padding(.horizontal, sideInset)
                        WatchPosterGrid(items: model.items, row: "catalog", width: proxy.size.width, model: model,
                                        focus: $focus, cellAppeared: { model.cellAppeared($0) })
                    }
                }
                .scrollIndicators(.never)
                .onScrollPhaseChange { _, phase in model.scrolling.setPage(phase.isScrolling) }
                // Cleared while still moving: the page must not stay "scrolling".
                .onDisappear { model.scrolling.setPage(false) }
            }
            .opacity(failed ? 0 : 1)
            .allowsHitTesting(!failed)
            .accessibilityHidden(failed)
            if let state = model.emptyState {
                WatchEmptyStateView(state: state) { _ in model.retry() }
            }
        }
    }
}

// MARK: - Collection

/// MacLCWatchCollectionViewController's data: the collection's titles once
/// resolved, in the pool's order.
@Observable
final class WatchCollectionModel: WatchPageModel {
    @ObservationIgnored let localize: (String) -> String
    @ObservationIgnored let scrolling = ScrollActivity()
    @ObservationIgnored let marks = WatchMarks()
    @ObservationIgnored let collection: MacLCWatchCollection
    /// "THE EDIT · UNTIL OCT 19": the last day of the collection's period.
    @ObservationIgnored let eyebrow: String
    @ObservationIgnored private weak var section: MacLCWatchSectionViewController?

    /// nil while resolving (placeholders); empty: nothing matched.
    private(set) var items: [MacLCAddonItem]?

    @ObservationIgnored private var request: MacLCAddonRequest?

    /// The page to push on the section, titled for the window title.
    static func controller(section: MacLCWatchSectionViewController, collection: MacLCWatchCollection,
                           localize: @escaping (String) -> String) -> NSViewController {
        let model = WatchCollectionModel(section: section, collection: collection, localize: localize)
        let controller = NSHostingController(rootView: WatchCollectionPage(model: model))
        controller.sizingOptions = []
        controller.title = collection.title
        model.resolve()
        return controller
    }

    private init(section: MacLCWatchSectionViewController, collection: MacLCWatchCollection,
                 localize: @escaping (String) -> String) {
        self.section = section
        self.collection = collection
        self.localize = localize
        let discovery = MacLCWatchDiscovery.shared
        let lastDay = discovery.nextEditDate(after: Date()).addingTimeInterval(-86_400)
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        eyebrow = "THE EDIT · UNTIL \(formatter.string(from: lastDay).uppercased())"
    }

    isolated deinit {
        request?.cancel()
    }

    private func resolve() {
        if let resolved = MacLCWatchDiscovery.shared.resolvedItems(for: collection) {
            items = resolved
            return
        }
        request = MacLCWatchDiscovery.shared.resolve(collection) { [weak self] items in
            self?.request = nil
            self?.items = items
        }
    }

    func open(_ item: MacLCAddonItem, showStreams: Bool) {
        section?.showDetail(for: item, showStreams: showStreams)
    }
}

/// The header, then the grid: one placeholder per entry while resolving;
/// nothing matched: "Nothing to Show Yet" under the header.
struct WatchCollectionPage: View {
    let model: WatchCollectionModel

    @FocusState private var focus: WatchFocus?

    var body: some View {
        let entries = model.collection.entries.count
        GeometryReader { proxy in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    WatchCollectionHeader(collection: model.collection, items: model.items ?? [],
                                          eyebrow: model.eyebrow, localize: model.localize)
                    WatchPosterGrid(items: model.items, placeholders: entries > 0 ? entries : 8, row: "collection",
                                    width: proxy.size.width, model: model, focus: $focus)
                }
            }
            .scrollIndicators(.never)
            .onScrollPhaseChange { _, phase in model.scrolling.setPage(phase.isScrolling) }
            .onDisappear { model.scrolling.setPage(false) }
        }
        .overlay {
            if model.items?.isEmpty == true {
                WatchEmptyStateView(state: WatchEmptyState(
                    symbol: "film.stack", title: model.localize("Nothing to Show Yet"),
                    message: model.localize("None of these titles were found in your catalog add-ons."),
                    button: nil, prominent: false, action: nil)) { _ in }
                    .offset(y: 100)
            }
        }
    }
}

/// MacLCWatchCollectionHeaderView: full width, 300 pt high, the card's tint
/// gradient over the window background, 1 pt border; the symbol (34 pt) and
/// eyebrow, the title (largeTitle, bold, 2 lines), the subtitle (title3,
/// secondary, 2 lines, at most 620 wide), the count and "Source: <host>",
/// 380 pt clear of the trailing edge for the fan of 5 posters (110 × 165,
/// -14° … +14°, outer ones lower, the middle one in front).
struct WatchCollectionHeader: View {
    let collection: MacLCWatchCollection
    let items: [MacLCAddonItem]
    let eyebrow: String
    let localize: (String) -> String

    private static let angles: [Double] = [-14, -7, 0, 7, 14]
    private static let drops: [CGFloat] = [14, 4, 0, 4, 14]

    var body: some View {
        let tint = Color(nsColor: MacLCWatchColorNamed(collection.tintName))
        ZStack(alignment: .topLeading) {
            Color(nsColor: .windowBackgroundColor)
            LinearGradient(colors: [tint.opacity(0.32), tint.opacity(0.12)], startPoint: .bottomLeading,
                           endPoint: .topTrailing)
            text(tint: tint)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 300)
        .overlay(alignment: .bottomTrailing) {
            // Back to front: the outer cards, their neighbours, the middle one.
            ZStack(alignment: .bottomTrailing) {
                ForEach([0, 4, 1, 3, 2], id: \.self) { index in
                    FanPoster(item: index < items.count ? items[index] : nil,
                              size: CGSize(width: 110, height: 165), shadowRadius: 10, shadowY: 4)
                        .rotationEffect(.degrees(Self.angles[index]))
                        .offset(x: -(230 - CGFloat(index - 2) * 62 - 55), y: -(28 - Self.drops[index]))
                }
            }
            .accessibilityHidden(true)
        }
        .clipped()
        .overlay(Rectangle().strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
    }

    private func text(tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: collection.symbolName)
                    .resizable()
                    .scaledToFit()
                    .fontWeight(.bold)
                    .foregroundStyle(tint)
                    .frame(width: 34, height: 34)
                    .accessibilityHidden(true)
                Text(eyebrow.uppercased())
                    .font(.footnote.weight(.semibold))
                    .kerning(0.6)
                    .foregroundStyle(tint)
            }
            Text(collection.title)
                .font(.largeTitle.bold())
                .lineLimit(2)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 12)
            Text(collection.subtitle)
                .font(.title3)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: 620, alignment: .leading)
                .padding(.top, 8)
            HStack(spacing: 16) {
                Text(collectionCountText(collection, localize: localize))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(tint)
                if let url = collection.sourceURL {
                    Button(String(format: localize("Source: %@"), url.host ?? localize("Web"))) {
                        NSWorkspace.shared.open(url)
                    }
                    .buttonStyle(.link)
                    .font(.footnote)
                }
            }
            .padding(.top, 12)
        }
        .padding(.top, 40)
        .padding(.leading, sideInset)
        .padding(.trailing, 380)
    }
}
