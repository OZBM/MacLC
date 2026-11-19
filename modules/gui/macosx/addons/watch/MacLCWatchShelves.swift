/*****************************************************************************
 * MacLCWatchShelves.swift: the Watch browse rows in SwiftUI
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

/* The horizontal rows of the SwiftUI Watch page (MacLCWatchBrowsePage.swift):
 * one row view for every kind (posters, Top 10, Continue Watching, The Edit,
 * genre tiles) with MacLCWatchShelfHeaderView's header, paging and keyboard;
 * the poster cell (MacLCWatchPosterItem, with MacLCWatchLibraryViews' marks);
 * the per-title marks; the actions menu (MacLCWatchActions) in SwiftUI. */

import AppKit
import Observation
import SwiftUI

/// MacLCWatchLayout's metrics (points).
let posterSize = NSSize(width: 168, height: 252)
let itemSpacing: CGFloat = 20
let sideInset: CGFloat = 40
let sectionSpacing: CGFloat = 36
/// Room above and below the items for a hovered one to grow into.
let hoverHeadroom: CGFloat = 12
let rankColumnWidth: CGFloat = 52

// MARK: - Row model

/// The filter pop-up of a catalog shelf: "All Genres" (unless the catalog
/// requires one) then its genres.
struct WatchRowFilter: Equatable {
    var titles: [String]
    var selected: Int
}

/// One row of the page. Its content changes in place (rebuildRows), so only
/// the row that changed draws again.
@Observable
final class WatchRow: Identifiable {
    enum Kind {
        case posters, ranked, continueWatching, edit, genres

        var itemWidth: CGFloat {
            switch self {
            case .posters: return posterSize.width
            case .ranked: return posterSize.width + rankColumnWidth
            case .continueWatching: return 300
            case .edit: return 340
            case .genres: return 196
            }
        }

        var spacing: CGFloat { self == .genres ? 16 : itemSpacing }
        /// What a page step snaps to (MacLCWatchBrowse.m itemPitchForSectionID:).
        var pitch: CGFloat { itemWidth + spacing }
    }

    let id: String
    let kind: Kind
    var title = ""
    var subtitle: String?
    var filter: WatchRowFilter?
    /// Posters and Top 10; nil while loading (8 placeholders).
    var items: [MacLCAddonItem]?
    var entries: [MacLCWatchEntry] = []
    var collections: [MacLCWatchCollection] = []
    var genres: [String] = []
    var genrePosters: [String: [MacLCAddonItem]] = [:]
    @ObservationIgnored var explainerTopic: MacLCExplainerTopic?
    @ObservationIgnored var seeAll: (() -> Void)?
    @ObservationIgnored var catalog: MacLCAddonTitleCatalog?
    /// How far the row is scrolled, for the arrow keys; written every frame.
    @ObservationIgnored var scrolled: CGFloat = 0

    init(id: String, kind: Kind) {
        self.id = id
        self.kind = kind
    }

    /// Sets a property only when it changes, so observers see real changes.
    func update<Value: Equatable>(_ keyPath: ReferenceWritableKeyPath<WatchRow, Value>, _ value: Value) {
        if self[keyPath: keyPath] != value {
            self[keyPath: keyPath] = value
        }
    }

    /// Cells that take the keyboard focus (placeholders do not).
    var itemCount: Int {
        switch kind {
        case .posters, .ranked: return items?.count ?? 0
        case .continueWatching: return entries.count
        case .edit: return collections.count
        case .genres: return genres.count
        }
    }
}

/// Whether the page or a shelf is moving. Cards do not lift then: a lift is
/// a SwiftUI animation, computed on the main thread for every frame, and its
/// text is drawn again at each scale; content moving under a resting pointer
/// lifts one card after another, and those redraws held scrolling at 60 Hz
/// (measured 2026-11-18: half the main thread waited on the render server).
@Observable
final class ScrollActivity {
    private(set) var page = false
    private(set) var shelves = Set<String>()
    var isScrolling: Bool { page || !shelves.isEmpty }
    /// Called when the last moving scroll view stops.
    @ObservationIgnored var onIdle: (() -> Void)?

    func setPage(_ scrolling: Bool) {
        guard scrolling != page else { return }
        page = scrolling
        if !isScrolling {
            onIdle?()
        }
    }

    func setShelf(_ id: String, scrolling: Bool) {
        guard scrolling != shelves.contains(id) else { return }
        if scrolling {
            shelves.insert(id)
        } else {
            shelves.remove(id)
            if !isScrolling {
                onIdle?()
            }
        }
    }
}

// MARK: - Marks

/// Favorite, watched and progress of one title (MacLCWatchLibraryViews).
@Observable
final class TitleMarks {
    var favorite = false
    var watched = false
    /// Shown as a bar when 0 < fraction < 1 and not watched.
    var fraction = 0.0
}

/// One TitleMarks per title shown, updated from MacLCWatchLibrary when its
/// title is in a change notification: only the cells of that title redraw.
final class WatchMarks {
    private var byTitle: [String: TitleMarks] = [:]
    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(forName: .MacLCWatchLibraryDidChange, object: nil,
                                                          queue: .main) { [weak self] note in
            let changed = note.userInfo?[MacLCWatchLibraryChangedTitlesKey] as? Set<String>
            MainActor.assumeIsolated {
                self?.refresh(changed)
            }
        }
    }

    isolated deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func marks(for item: MacLCAddonItem) -> TitleMarks {
        if let marks = byTitle[item.identifier] {
            return marks
        }
        let marks = TitleMarks()
        update(marks, title: item.identifier)
        byTitle[item.identifier] = marks
        return marks
    }

    private func refresh(_ changed: Set<String>?) {
        for (title, marks) in byTitle where changed?.contains(title) ?? true {
            update(marks, title: title)
        }
    }

    private func update(_ marks: TitleMarks, title: String) {
        let library = MacLCWatchLibrary.shared
        let entry = library.entry(forTitle: title)
        let watched = entry?.isWatched ?? false
        var fraction = entry?.fraction ?? 0
        if fraction <= 0 {
            fraction = entry?.resumeTarget?.progress?.fraction ?? 0
        }
        let favorite = library.isFavorite(title)
        if marks.watched != watched { marks.watched = watched }
        if marks.fraction != fraction { marks.fraction = fraction }
        if marks.favorite != favorite { marks.favorite = favorite }
    }
}

// MARK: - Row

/// Where a shelf is scrolled, for the paging buttons. Written on every
/// scroll frame, so it is not observed: only `PagingState` changes redraw.
private final class ShelfGeometry {
    /// From the first item's leading edge (0 at rest).
    var scrolled: CGFloat = 0
    var maxScroll: CGFloat = 0
    /// The width the items show in, insets excluded.
    var visibleWidth: CGFloat = 0
    /// Content offset at rest: the margins plus the sidebar's safe area.
    var leadingInset: CGFloat = sideInset
}

/// What a shelf's paging needs from its scroll geometry: containerSize
/// already leaves out the insets (the 40 pt margins and, under the floating
/// sidebar, its width), which contentOffset counts from.
private nonisolated struct ShelfScroll: Equatable {
    var offset: CGFloat
    var leadingInset: CGFloat
    var contentWidth: CGFloat
    var visibleWidth: CGFloat
}

struct PagingState: Equatable {
    var canBack = false
    var canForward = false
}

/// A horizontal row: MacLCWatchShelfHeaderView then the items, scrolling
/// without scroller, a flick settling on an item's leading edge.
struct WatchShelfRow: View {
    let row: WatchRow
    let model: WatchBrowseModel
    var focus: FocusState<WatchFocus?>.Binding

    @State private var position = ScrollPosition(edge: .leading)
    @State private var geometry = ShelfGeometry()
    @State private var paging = PagingState()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ShelfHeader(title: row.title, subtitle: row.subtitle, topic: row.explainerTopic, filter: row.filter,
                        model: model, seeAll: row.seeAll, paging: paging, page: page,
                        chooseFilter: { model.chooseFilter($0, of: row) })
                .padding(.horizontal, sideInset)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: row.kind.spacing) {
                    cells
                }
                .scrollTargetLayout()
                .padding(.vertical, hoverHeadroom)
            }
            .scrollIndicators(.never)
            .contentMargins(.horizontal, sideInset, for: .scrollContent)
            // A flick settles on an item's leading edge, never between two.
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition($position)
            .onScrollPhaseChange { _, phase in
                model.scrolling.setShelf(row.id, scrolling: phase.isScrolling)
            }
            .onDisappear { model.scrolling.setShelf(row.id, scrolling: false) }
            .onScrollGeometryChange(for: ShelfScroll.self) { scroll in
                ShelfScroll(offset: scroll.contentOffset.x, leadingInset: scroll.contentInsets.leading,
                            contentWidth: scroll.contentSize.width, visibleWidth: scroll.containerSize.width)
            } action: { _, value in
                geometry.scrolled = value.offset + value.leadingInset
                geometry.maxScroll = max(0, value.contentWidth - value.visibleWidth)
                geometry.visibleWidth = value.visibleWidth
                geometry.leadingInset = value.leadingInset
                row.scrolled = geometry.scrolled
                let state = PagingState(canBack: geometry.scrolled > 1,
                                        canForward: geometry.scrolled < geometry.maxScroll - 1)
                if state != paging {
                    paging = state
                }
            }
        }
        .padding(.bottom, sectionSpacing - hoverHeadroom)
    }

    @ViewBuilder private var cells: some View {
        switch row.kind {
        case .posters, .ranked:
            // One ForEach for placeholders and titles: placeholder i becomes
            // title i in place. (Two ForEach of Int ids in an if/else left the
            // placeholders on screen in a lazy stack.)
            let items = row.items
            ForEach(0..<(items?.count ?? 8), id: \.self) { index in
                let item = items?[index]
                let rank = row.kind != .ranked ? 0 : item == nil ? -1 : index < 10 ? index + 1 : 0
                PosterCell(item: item, rank: rank, width: posterSize.width, model: model, onFocus: { reveal(index) })
                    .frame(width: row.kind.itemWidth, alignment: .leading)
                    .watchCell(WatchFocus(row: row.id, index: index), focus: focus, enabled: item != nil) {
                        if let item { model.open(item) }
                    }
            }
        case .continueWatching:
            ForEach(Array(row.entries.enumerated()), id: \.element.identifier) { index, entry in
                ContinueCard(entry: entry, model: model, onFocus: { reveal(index) })
                    .watchCell(WatchFocus(row: row.id, index: index), focus: focus) { model.resume(entry) }
            }
        case .edit:
            ForEach(Array(row.collections.enumerated()), id: \.element.identifier) { index, collection in
                CollectionCard(collection: collection, model: model, onFocus: { reveal(index) })
                    .watchCell(WatchFocus(row: row.id, index: index), focus: focus) { model.open(collection) }
            }
        case .genres:
            ForEach(Array(row.genres.enumerated()), id: \.element) { index, genre in
                GenreTile(genre: genre, posters: row.genrePosters[genre] ?? [], model: model,
                          onFocus: { reveal(index) })
                    .watchCell(WatchFocus(row: row.id, index: index), focus: focus) { model.openGenre(genre) }
            }
        }
    }

    /// A page is the visible width less one item, so the last one stays partly
    /// in view; it ends on an item's leading edge (MacLCWatchShelfScrolling
    /// scrollShelf:direction:itemPitch:).
    private func page(_ direction: Int) {
        let pitch = row.kind.pitch
        // AppKit's visible width counts the 40 pt margins.
        let step = max(pitch, geometry.visibleWidth + 2 * sideInset - pitch)
        var target = geometry.scrolled + CGFloat(direction) * step
        target = (target / pitch).rounded() * pitch
        scroll(to: target, animation: .timingCurve(0.2, 1.0, 0.3, 1.0, duration: 0.45))
    }

    /// The arrow keys moved the focus to an item: bring it fully into view.
    private func reveal(_ index: Int) {
        let start = CGFloat(index) * row.kind.pitch
        let end = start + row.kind.itemWidth
        if start < geometry.scrolled {
            scroll(to: start, animation: .easeOut(duration: 0.2))
        } else if end > geometry.scrolled + geometry.visibleWidth {
            scroll(to: end - geometry.visibleWidth, animation: .easeOut(duration: 0.2))
        }
    }

    private func scroll(to offset: CGFloat, animation: Animation) {
        let target = min(max(0, offset), geometry.maxScroll)
        let move = { position.scrollTo(x: target - geometry.leadingInset) }
        if reduceMotion {
            move()
        } else {
            withAnimation(animation, move)
        }
    }
}

// MARK: - Focus

extension View {
    /// A cell that takes the keyboard focus (arrow keys between cells, the
    /// page handles them) and opens on Return or Enter, as the AppKit
    /// collection view's selection does. The cell draws its own ring.
    func watchCell(_ id: WatchFocus, focus: FocusState<WatchFocus?>.Binding, enabled: Bool = true,
                   activate: @escaping () -> Void) -> some View {
        self
            .focusable(enabled)
            .focused(focus, equals: id)
            .focusEffectDisabled()
            .onKeyPress(keys: [.return, KeyEquivalent("\u{3}")]) { _ in
                activate()
                return .handled
            }
    }
}

/// The selection ring of the AppKit cells: 3 pt of accent, centred 4.5 pt
/// outside the picture, corner radius + 3. Calls onFocus when it appears.
struct FocusRing: View {
    let cornerRadius: CGFloat
    var onFocus: () -> Void = {}
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius + 3, style: .continuous)
            .stroke(Color.accentColor, lineWidth: 3)
            .padding(-4.5)
            .opacity(isFocused ? 1 : 0)
            .allowsHitTesting(false)
            .onChange(of: isFocused) { _, focused in
                if focused {
                    onFocus()
                }
            }
    }
}

// MARK: - Header

/// MacLCWatchShelfHeaderView: title (title2, bold) with an optional info
/// button and subtitle, then trailing the filter pop-up, "See All" and the
/// two paging buttons (hidden on a single page, their room kept). 44 pt tall,
/// 58 with a subtitle.
struct ShelfHeader: View {
    let title: String
    let subtitle: String?
    let topic: MacLCExplainerTopic?
    let filter: WatchRowFilter?
    let model: WatchBrowseModel
    let seeAll: (() -> Void)?
    /// nil: no paging buttons (search results).
    let paging: PagingState?
    let page: (Int) -> Void
    let chooseFilter: @MainActor (Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.title2.bold())
                        .lineLimit(1)
                        .accessibilityAddTraits(.isHeader)
                    if let topic {
                        ExplainerInfoButton(topic: topic)
                            .frame(width: 22, height: 22)
                    }
                }
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.top, subtitle == nil ? 0 : 6)
            .frame(maxHeight: .infinity, alignment: subtitle == nil ? .center : .top)
            Spacer(minLength: 16)
            if let filter {
                Picker(String(format: model.localize("Filter %@"), title),
                       selection: Binding(get: { filter.selected }, set: chooseFilter)) {
                    ForEach(Array(filter.titles.enumerated()), id: \.offset) { index, name in
                        Text(name).tag(index)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .controlSize(.small)
                .fixedSize()
                .padding(.trailing, 12)
            }
            if let seeAll {
                SeeAllButton(title: model.localize("See All"), action: seeAll)
                    .padding(.trailing, 12)
            }
            if let paging {
                let visible = paging.canBack || paging.canForward
                Group {
                    PagingButton(symbol: "chevron.left", enabled: paging.canBack,
                                 label: String(format: model.localize("Previous %@"), title)) { page(-1) }
                        .padding(.trailing, 6)
                    PagingButton(symbol: "chevron.right", enabled: paging.canForward,
                                 label: String(format: model.localize("Next %@"), title)) { page(1) }
                }
                .opacity(visible ? 1 : 0)
                .allowsHitTesting(visible)
                .accessibilityHidden(!visible)
            }
        }
        .frame(height: subtitle == nil ? 44 : 58)
    }
}

/// MacLCExplainer's info button (its tip on hover and click), hosted.
struct ExplainerInfoButton: NSViewRepresentable {
    let topic: MacLCExplainerTopic

    func makeNSView(context: Context) -> NSButton {
        MacLCExplainer.infoButton(forTopic: topic)
    }

    func updateNSView(_ nsView: NSButton, context: Context) {}

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSButton, context: Context) -> CGSize? {
        CGSize(width: 22, height: 22)
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

// MARK: - Pictures

/// One picture of a cell, from MacLCWatchImageCache at the drawn size: cached
/// pictures show at once, others when decoded; leaving the screen cancels.
@Observable
final class PosterArtwork {
    private(set) var image: NSImage?
    @ObservationIgnored private var url: URL?
    @ObservationIgnored private var request: MacLCWatchImageRequest?

    func show(_ newURL: URL?, size: CGSize, scale: CGFloat) {
        guard newURL != url || (image == nil && request == nil) else { return }
        request?.cancel()
        request = nil
        url = newURL
        guard let newURL else {
            image = nil
            return
        }
        var pending: MacLCWatchImageRequest?
        let cached = MacLCWatchImageCache.shared.image(for: newURL, pointSize: size, scale: scale,
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

/// The spring of the AppKit hover lifts; nil (no motion) under Reduce Motion
/// and when a scroll starts under the pointer, which drops the lift at once.
func liftAnimation(_ hovered: Bool, _ lifted: Bool, reduceMotion: Bool,
                   stiffness: Double = 260, damping: Double = 15) -> Animation? {
    reduceMotion || (hovered && !lifted) ? nil
        : .interpolatingSpring(mass: 1, stiffness: stiffness, damping: damping)
}

// MARK: - Poster

/// MacLCWatchPosterItem: the 2:3 poster (corner radius 8, quaternary fill and
/// "film" while loading, 1 pt separator border, rating badge top leading),
/// 8 pt, title (body, medium), subtitle (subheadline, secondary) "2026 ·
/// Drama". Ranked: the rank beside the poster, which overlaps it a little.
/// Marks: progress bar at the bottom, watched badge (and the picture dimmed),
/// favorite heart top trailing (on hover an outlined one adds it).
/// Hover: 5 % larger about the centre and a soft shadow, with a spring.
struct PosterCell: View {
    let item: MacLCAddonItem?
    /// 0: unranked; < 0: placeholder in a ranked shelf (rank column empty).
    let rank: Int
    let width: CGFloat
    let model: WatchBrowseModel
    var onFocus: () -> Void = {}

    @State private var artwork = PosterArtwork()
    @State private var hovered = false
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var size: CGSize { CGSize(width: width, height: (width * 1.5).rounded()) }

    var body: some View {
        // Only a hovered cell reads (and so observes) the scroll activity.
        let lifted = hovered && !model.scrolling.isScrolling
        let marks = item.map { model.marks.marks(for: $0) }
        ZStack(alignment: .topLeading) {
            if rank > 0 {
                Text("\(rank)")
                    .font(.system(size: 80, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(nsColor: .labelColor))
                    .fixedSize()
                    .frame(width: rankColumnWidth + 10, height: size.height, alignment: .bottomTrailing)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 0) {
                poster(lifted: lifted, marks: marks)
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
            .frame(width: size.width, alignment: .leading)
            .padding(.leading, rank != 0 ? rankColumnWidth : 0)
        }
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .pointerStyle(.link)
        .onTapGesture {
            if let item { model.open(item) }
        }
        .onAppear { artwork.show(item?.posterURL, size: size, scale: displayScale) }
        .onChange(of: item?.posterURL) { _, url in artwork.show(url, size: size, scale: displayScale) }
        .onDisappear { artwork.stop() }
        .contextMenu {
            if let item {
                WatchActionsMenu(item: item)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityValue(marks.map { accessibilityValue($0) } ?? "")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            if let item { model.open(item) }
        }
        // Loading placeholders are not buttons yet.
        .accessibilityHidden(item == nil)
    }

    private func poster(lifted: Bool, marks: TitleMarks?) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        let watched = marks?.watched ?? false
        let fraction = marks?.fraction ?? 0
        return ZStack(alignment: .topLeading) {
            shape.fill(Color(nsColor: .quaternarySystemFill))
            Group {
                if let image = artwork.image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: fitted ? .fit : .fill)
                } else {
                    Image(systemName: "film")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: size.width, height: size.height)
            .opacity(watched ? 0.6 : 1)
            if let rating {
                Text("★ \(rating)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .frame(minWidth: 40, minHeight: 20)
                    .background(.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .padding(6)
            }
            if !watched, fraction > 0, fraction < 1 {
                WatchProgressBar(fraction: fraction)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
            if watched {
                WatchedBadge()
                    .padding(8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
            if let item, let marks, marks.favorite || lifted {
                FavoriteHeart(item: item, favorite: marks.favorite, model: model)
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .topTrailing)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
        .overlay(FocusRing(cornerRadius: 8, onFocus: onFocus))
        .scaleEffect(lifted && !reduceMotion ? 1.05 : 1)
        .shadow(color: .black.opacity(lifted ? 0.3 : 0), radius: lifted ? 14 : 0, y: lifted ? 6 : 0)
        .animation(liftAnimation(hovered, lifted, reduceMotion: reduceMotion), value: lifted)
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

    /// "Watched" or "In progress, 40 %", then "Favorite".
    private func accessibilityValue(_ marks: TitleMarks) -> String {
        var parts: [String] = []
        if marks.watched {
            parts.append(model.localize("Watched"))
        } else if marks.fraction > 0, marks.fraction < 1 {
            parts.append(String(format: model.localize("In progress, %ld %%"), Int((marks.fraction * 100).rounded())))
        }
        if marks.favorite {
            parts.append(model.localize("Favorite"))
        }
        return parts.joined(separator: ", ")
    }
}

/// MacLCWatchProgressBar: 4 pt, round ends, track white 30 %, fill white.
struct WatchProgressBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.3))
                Capsule().fill(.white).frame(width: proxy.size.width * fraction)
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }
}

/// MacLCWatchedBadge: a checkmark in a 24 pt dark circle.
struct WatchedBadge: View {
    var body: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(Circle().fill(.black.opacity(0.45)))
            .accessibilityHidden(true)
    }
}

/// MacLCWatchFavoriteButton on a picture: a heart in a 28 pt dark circle,
/// filled pink for a favorite; a click toggles it.
private struct FavoriteHeart: View {
    let item: MacLCAddonItem
    let favorite: Bool
    let model: WatchBrowseModel

    var body: some View {
        Button {
            MacLCWatchLibrary.shared.setFavorite(!favorite, for: item)
        } label: {
            Image(systemName: favorite ? "heart.fill" : "heart")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(favorite ? Color(nsColor: .systemPink) : .white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(.black.opacity(0.45)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(model.localize(favorite ? "Remove from Favorites" : "Add to Favorites"))
    }
}

// MARK: - Actions menu

/// MacLCWatchActions menuForItem:video:inHistory:NO as a SwiftUI context
/// menu, built when it opens (so it shows the title's current state);
/// details adds "Show Details" after a separator, as the resume cards do.
struct WatchActionsMenu: View {
    let item: MacLCAddonItem
    var details: (title: String, action: () -> Void)?

    var body: some View {
        let menu = MacLCWatchActions.menu(for: item, video: nil, inHistory: false)
        ForEach(Array(menu.items.enumerated()), id: \.offset) { _, entry in
            if entry.isSeparatorItem {
                Divider()
            } else {
                Button {
                    // The menu holds the items' targets: keep it until the click.
                    withExtendedLifetime(menu) {
                        if let action = entry.action {
                            NSApp.sendAction(action, to: entry.target, from: entry)
                        }
                    }
                } label: {
                    if let image = entry.image {
                        Label { Text(entry.title) } icon: { Image(nsImage: image) }
                    } else {
                        Text(entry.title)
                    }
                }
            }
        }
        if let details {
            Divider()
            Button(action: details.action) {
                Label(details.title, systemImage: "info.circle")
            }
        }
    }
}

/// A target that runs a closure (the "…" button's "Show Details", pull to
/// refresh); its owner keeps it alive.
final class ActionTarget: NSObject {
    private let handler: () -> Void

    init(_ handler: @escaping () -> Void) {
        self.handler = handler
    }

    @objc func run(_ sender: Any?) {
        handler()
    }
}
