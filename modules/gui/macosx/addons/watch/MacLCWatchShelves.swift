/*****************************************************************************
 * MacLCWatchShelves.swift: the Watch browse rows in SwiftUI (pilot)
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

/* The poster shelves of Home, Movies and TV Shows (MacLCWatchBrowse.m, rows 5
 * to 7 of MacLCWatchBrowseViewController: Top 10, the catalog shelves and the
 * genre shelves) drawn by SwiftUI, to measure scrolling against AppKit. Same
 * look as MacLCWatchPosterItem and MacLCWatchShelfHeaderView; same loading
 * (every shelf with the page, posters decoded ahead) through the Objective-C
 * MacLCAddonStore and MacLCWatchImageCache.
 * shortcut: pilot scope, behind MACLC_SWIFTUI_WATCH=1. Not here: the
 * carousel, services bar, Continue Watching, genre tiles, The Edit, search,
 * empty states, pull to refresh, poster context menus, favourite and watched
 * marks, keyboard selection; port them with the screen if the pilot wins. */

import AppKit
import Observation
import SwiftUI

/// Objective-C's way in (MacLCWatchBrowse.m). It passes what needs the core
/// (strings through vlc_gettext, the section's navigation) as blocks, so the
/// bridging header stays free of vlc_*.h.
@objc(MacLCWatchShelvesHost)
final class WatchShelvesHost: NSObject {
    /// MACLC_SWIFTUI_WATCH=1 in the environment: Watch shows these shelves.
    @objc nonisolated static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["MACLC_SWIFTUI_WATCH"] == "1"
    }

    /// The page for a section. catalogs: the section's title catalogs, in
    /// order, as MacLCWatchBrowseViewController shows them.
    @objc(controllerWithMediaType:catalogs:localize:openItem:seeAll:)
    static func controller(mediaType: String?,
                           catalogs: [MacLCAddonTitleCatalog],
                           localize: @escaping (String) -> String,
                           openItem: @escaping (MacLCAddonItem) -> Void,
                           seeAll: @escaping (MacLCAddonTitleCatalog, String?, String) -> Void) -> NSViewController {
        let model = WatchShelvesModel(mediaType: mediaType, catalogs: catalogs, localize: localize,
                                      openItem: openItem, seeAll: seeAll)
        let controller = NSHostingController(rootView: WatchShelvesPage(model: model))
        // The section pins the view to its edges: no size from SwiftUI.
        controller.sizingOptions = []
        return controller
    }
}

// MARK: - Model

/// One row. items nil while loading; failed rows disappear, as in AppKit.
@Observable
final class WatchShelf: Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let ranked: Bool
    let catalog: MacLCAddonTitleCatalog
    let genre: String?
    var items: [MacLCAddonItem]?
    var failed = false

    init(id: String, title: String, subtitle: String?, ranked: Bool,
         catalog: MacLCAddonTitleCatalog, genre: String?) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.ranked = ranked
        self.catalog = catalog
        self.genre = genre
    }
}

final class WatchShelvesModel {
    let shelves: [WatchShelf]
    let localize: (String) -> String
    let openItem: (MacLCAddonItem) -> Void
    let seeAll: (MacLCAddonTitleCatalog, String?, String) -> Void

    private var requests: [MacLCAddonRequest] = []
    private var warmedURLs = Set<URL>()
    private var furthestShelfShown = 0

    init(mediaType: String?, catalogs: [MacLCAddonTitleCatalog],
         localize: @escaping (String) -> String,
         openItem: @escaping (MacLCAddonItem) -> Void,
         seeAll: @escaping (MacLCAddonTitleCatalog, String?, String) -> Void) {
        self.localize = localize
        self.openItem = openItem
        self.seeAll = seeAll

        func plural(_ type: String) -> String {
            switch type {
            case "movie": return localize("Movies")
            case "series": return localize("TV Shows")
            default: return type.prefix(1).uppercased() + type.dropFirst()
            }
        }
        // Titles from another add-on than the first name it, as in AppKit.
        let firstAddon = MacLCAddonStore.shared.installedAddons.first?.identifier
        func subtitle(_ catalog: MacLCAddonTitleCatalog) -> String? {
            firstAddon != nil && catalog.addon.identifier != firstAddon ? catalog.addon.name : nil
        }
        func key(_ catalog: MacLCAddonTitleCatalog) -> String {
            "\(catalog.addon.identifier)_\(catalog.type)_\(catalog.identifier)"
        }

        var topCatalogs = catalogs.filter { $0.identifier == "top" }
        if topCatalogs.isEmpty, let first = catalogs.first {
            topCatalogs = [first]
        }
        var rows: [WatchShelf] = []
        for catalog in topCatalogs {
            rows.append(WatchShelf(id: "top_" + key(catalog),
                                   title: String(format: localize("Top 10 %@"), plural(catalog.type)),
                                   subtitle: subtitle(catalog), ranked: true, catalog: catalog, genre: nil))
        }
        for catalog in catalogs where catalog.identifier != "top" {
            let typeName = plural(catalog.type)
            let title = !typeName.isEmpty && !catalog.name.lowercased().contains(typeName.lowercased())
                ? "\(catalog.name) \(typeName)" : catalog.name
            rows.append(WatchShelf(id: "catalog_" + key(catalog), title: title,
                                   subtitle: subtitle(catalog), ranked: false, catalog: catalog, genre: nil))
        }
        if mediaType != nil, let top = topCatalogs.first {
            for genre in top.genres {
                rows.append(WatchShelf(id: "popular_genre_" + genre,
                                       title: String(format: localize("Popular in %@"), genre),
                                       subtitle: subtitle(top), ranked: false, catalog: top, genre: genre))
            }
        }
        shelves = rows
        // Every shelf loads with the page (AppKit since 2026-11-18).
        for shelf in shelves {
            load(shelf)
        }
    }

    isolated deinit {
        requests.forEach { $0.cancel() }
    }

    private func load(_ shelf: WatchShelf) {
        let request = MacLCAddonStore.shared.fetchTitleCatalog(shelf.catalog, genre: shelf.genre, skip: 0) {
            [weak self, weak shelf] items, error in
            guard let self, let shelf else { return }
            // Genre shelves without titles disappear too.
            guard let items, error == nil, !(shelf.genre != nil && items.isEmpty) else {
                shelf.failed = true
                return
            }
            shelf.items = shelf.ranked ? Array(items.prefix(10)) : items
            if let index = shelves.firstIndex(where: { $0 === shelf }), index <= furthestShelfShown + 10 {
                warmPosters(of: shelf)
            }
        }
        requests.append(request)
    }

    /// The first ten posters of the shelves from this one to ten below are
    /// decoded ahead at the cells' size (AppKit's warmPostersAhead), so cells
    /// scroll in with their picture.
    func shelfDidAppear(_ shelf: WatchShelf) {
        guard let index = shelves.firstIndex(where: { $0 === shelf }) else { return }
        furthestShelfShown = max(furthestShelfShown, index)
        for ahead in shelves[index..<min(index + 11, shelves.count)] {
            warmPosters(of: ahead)
        }
    }

    private func warmPosters(of shelf: WatchShelf) {
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        for url in (shelf.items ?? []).prefix(10).compactMap(\.posterURL) where warmedURLs.insert(url).inserted {
            _ = MacLCWatchImageCache.shared.image(for: url, pointSize: posterSize, scale: scale,
                                                  request: nil) { _ in }
        }
    }
}

private let posterSize = NSSize(width: 168, height: 252)
private let itemSpacing: CGFloat = 20
private let sideInset: CGFloat = 40
/// Room above and below the posters for a hovered one to grow into.
private let hoverHeadroom: CGFloat = 12
private let rankColumnWidth: CGFloat = 52

// MARK: - Page

struct WatchShelvesPage: View {
    let model: WatchShelvesModel

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(model.shelves) { shelf in
                    if !shelf.failed {
                        ShelfRow(shelf: shelf, model: model)
                            .onAppear { model.shelfDidAppear(shelf) }
                    }
                }
            }
        }
    }
}

/// Where a shelf is scrolled, for the paging buttons. Written on every
/// scroll frame, so it is not observed: only `PagingState` changes redraw.
private final class ShelfGeometry {
    var scrolled: CGFloat = 0
    var maxScroll: CGFloat = 0
    var visibleWidth: CGFloat = 0
}

private struct PagingState: Equatable {
    var canBack = false
    var canForward = false
}

struct ShelfRow: View {
    let shelf: WatchShelf
    let model: WatchShelvesModel

    @State private var position = ScrollPosition(edge: .leading)
    @State private var geometry = ShelfGeometry()
    @State private var paging = PagingState()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ShelfHeader(title: shelf.title, subtitle: shelf.subtitle,
                        seeAllTitle: model.localize("See All"),
                        previousLabel: model.localize("Previous"), nextLabel: model.localize("Next"),
                        paging: paging,
                        seeAll: { model.seeAll(shelf.catalog, shelf.genre, shelf.title) },
                        page: page)
                .padding(.horizontal, sideInset)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: itemSpacing) {
                    if let items = shelf.items {
                        ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                            PosterCell(item: item, rank: shelf.ranked ? index + 1 : 0, open: model.openItem)
                        }
                    } else {
                        ForEach(0..<8, id: \.self) { _ in
                            PosterCell(item: nil, rank: shelf.ranked ? -1 : 0, open: model.openItem)
                        }
                    }
                }
                .scrollTargetLayout()
                .padding(.vertical, hoverHeadroom)
            }
            .scrollIndicators(.never)
            .contentMargins(.horizontal, sideInset, for: .scrollContent)
            // A flick settles on a poster's leading edge, never between two.
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition($position)
            .onScrollGeometryChange(for: CGRect.self) { scroll in
                CGRect(x: scroll.contentOffset.x + scroll.contentInsets.leading,
                       y: scroll.contentSize.width + scroll.contentInsets.leading + scroll.contentInsets.trailing,
                       width: scroll.containerSize.width, height: 0)
            } action: { _, value in
                geometry.scrolled = value.minX
                geometry.maxScroll = max(0, value.minY - value.width)
                geometry.visibleWidth = value.width
                let state = PagingState(canBack: geometry.scrolled > 1,
                                        canForward: geometry.scrolled < geometry.maxScroll - 1)
                if state != paging {
                    paging = state
                }
            }
        }
        .padding(.bottom, 36 - hoverHeadroom)
    }

    /// A page is the visible width less one poster, so the last one stays
    /// partly in view; it ends on a poster's leading edge (as
    /// MacLCWatchShelfScrolling scrollShelf:direction:itemPitch:).
    private func page(_ direction: Int) {
        let pitch = (shelf.ranked ? posterSize.width + rankColumnWidth : posterSize.width) + itemSpacing
        let step = max(pitch, geometry.visibleWidth - 2 * sideInset - pitch)
        var target = geometry.scrolled + CGFloat(direction) * step
        target = (target / pitch).rounded() * pitch
        target = min(max(0, target), geometry.maxScroll)
        let move = { position.scrollTo(x: target - sideInset) }
        if reduceMotion {
            move()
        } else {
            withAnimation(.timingCurve(0.2, 1.0, 0.3, 1.0, duration: 0.45), move)
        }
    }
}

// MARK: - Header

/// MacLCWatchShelfHeaderView: title (title2, bold), optional subtitle, then
/// "See All" and the two paging buttons trailing. 44 pt tall, 58 with a
/// subtitle.
private struct ShelfHeader: View {
    let title: String
    let subtitle: String?
    let seeAllTitle: String
    let previousLabel: String
    let nextLabel: String
    let paging: PagingState
    let seeAll: () -> Void
    let page: (Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title2.bold())
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 16)
            SeeAllButton(title: seeAllTitle, action: seeAll)
                .padding(.trailing, 12)
            PagingButton(symbol: "chevron.left", enabled: paging.canBack,
                         label: "\(previousLabel) \(title)") { page(-1) }
                .padding(.trailing, 6)
            PagingButton(symbol: "chevron.right", enabled: paging.canForward,
                         label: "\(nextLabel) \(title)") { page(1) }
        }
        .frame(height: subtitle == nil ? 44 : 58)
    }
}

private struct SeeAllButton: View {
    let title: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.subheadline)
            .foregroundStyle(hovered ? Color.accentColor : Color.secondary)
            .onHover { hovered = $0 }
            .pointerStyle(.link)
    }
}

private struct PagingButton: View {
    let symbol: String
    let enabled: Bool
    let label: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(nsColor: .labelColor))
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color(nsColor: hovered && enabled ? .tertiarySystemFill
                                                                            : .quaternarySystemFill)))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .onHover { hovered = $0 }
        .accessibilityLabel(label)
    }
}

// MARK: - Poster

/// One cell's picture, from MacLCWatchImageCache at the drawn size: cached
/// pictures show at once, others when decoded; leaving the screen cancels.
@Observable
private final class PosterArtwork {
    private(set) var image: NSImage?
    @ObservationIgnored private var url: URL?
    @ObservationIgnored private var request: MacLCWatchImageRequest?

    func show(_ newURL: URL?, scale: CGFloat) {
        guard newURL != url || (image == nil && request == nil) else { return }
        request?.cancel()
        request = nil
        url = newURL
        guard let newURL else {
            image = nil
            return
        }
        var pending: MacLCWatchImageRequest?
        let cached = MacLCWatchImageCache.shared.image(for: newURL, pointSize: posterSize, scale: scale,
                                                       request: &pending) { [weak self] image in
            guard let self, self.url == newURL else { return }
            self.request = nil
            self.image = image
        }
        request = pending
        if cached !== image {
            image = cached
        }
    }

    func stop() {
        request?.cancel()
        request = nil
    }

    isolated deinit {
        request?.cancel()
    }
}

/// MacLCWatchPosterItem: the 2:3 poster (corner radius 8, quaternary fill and
/// "film" while loading, 1 pt separator border, rating badge top leading),
/// 8 pt, title (body, medium), subtitle (subheadline, secondary) "2026 ·
/// Drama". Ranked: the rank beside the poster, which overlaps it a little.
/// Hover: 5 % larger about the centre and a soft shadow, with a spring.
private struct PosterCell: View {
    let item: MacLCAddonItem?
    /// 0: unranked; < 0: placeholder in a ranked shelf (rank column empty).
    let rank: Int
    let open: (MacLCAddonItem) -> Void

    @State private var artwork = PosterArtwork()
    @State private var hovered = false
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topLeading) {
            if rank > 0 {
                Text("\(rank)")
                    .font(.system(size: 80, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(nsColor: .labelColor))
                    .fixedSize()
                    .alignmentGuide(.bottom) { $0[.lastTextBaseline] }
                    .frame(width: rankColumnWidth + 10, height: posterSize.height, alignment: .bottomTrailing)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 0) {
                poster
                // A space keeps the line's height for placeholders.
                Text(item?.name ?? " ")
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .padding(.top, 8)
                Text(subtitle ?? " ")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.top, 2)
            }
            .frame(width: posterSize.width, alignment: .leading)
            .padding(.leading, rank != 0 ? rankColumnWidth : 0)
        }
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .pointerStyle(.link)
        .onTapGesture {
            if let item { open(item) }
        }
        .onAppear { artwork.show(item?.posterURL, scale: displayScale) }
        .onChange(of: item?.posterURL) { _, url in artwork.show(url, scale: displayScale) }
        .onDisappear { artwork.stop() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            if let item { open(item) }
        }
    }

    private var poster: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        return ZStack(alignment: .topLeading) {
            shape.fill(Color(nsColor: .quaternarySystemFill))
            if let image = artwork.image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: fitted ? .fit : .fill)
                    .frame(width: posterSize.width, height: posterSize.height)
            } else {
                Image(systemName: "film")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(.tertiary)
                    .frame(width: posterSize.width, height: posterSize.height)
            }
            if let rating {
                Text("★ \(rating)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .frame(minWidth: 40, minHeight: 20)
                    .background(.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .padding(6)
            }
        }
        .frame(width: posterSize.width, height: posterSize.height)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
        .scaleEffect(hovered && !reduceMotion ? 1.05 : 1)
        .shadow(color: .black.opacity(hovered ? 0.3 : 0), radius: hovered ? 14 : 0, y: hovered ? 6 : 0)
        .animation(reduceMotion ? nil : .interpolatingSpring(mass: 1, stiffness: 260, damping: 15), value: hovered)
    }

    /// Landscape and square art is fitted rather than cropped.
    private var fitted: Bool {
        let shape = item?.rawMeta?["posterShape"] as? String
        return shape == "landscape" || shape == "square"
    }

    /// "7.8" from the add-on, nil for none, zero or "N/A".
    private var rating: String? {
        let text = (item?.imdbRating ?? "").replacingOccurrences(of: "★", with: "")
            .trimmingCharacters(in: .whitespaces)
        return (text as NSString).doubleValue > 0 ? text : nil
    }

    /// "2026 · Drama", else the type.
    private var subtitle: String? {
        guard let item else { return nil }
        var parts: [String] = []
        if let release = item.releaseInfo, !release.isEmpty { parts.append(release) }
        if let genre = item.genres.first, !genre.isEmpty { parts.append(genre) }
        if parts.isEmpty, !item.type.isEmpty { parts.append(item.type.capitalized) }
        return parts.joined(separator: " · ")
    }

    private var accessibilityText: String {
        var parts: [String] = []
        if rank > 0 { parts.append("\(rank)") }
        if let name = item?.name, !name.isEmpty { parts.append(name) }
        if let subtitle, !subtitle.isEmpty { parts.append(subtitle) }
        return parts.joined(separator: ", ")
    }
}
