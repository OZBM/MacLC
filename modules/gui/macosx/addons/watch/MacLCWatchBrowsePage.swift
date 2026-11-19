/*****************************************************************************
 * MacLCWatchBrowsePage.swift: Home, Movies and TV Shows in SwiftUI
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

/* MacLCWatchBrowseViewController (MacLCWatchBrowse.m) in SwiftUI, behind
 * MACLC_SWIFTUI_WATCH=1: the same page, sections, data and behaviour (see the
 * contract in MacLCWatchSections.h; where it and MacLCWatchBrowse.m differ,
 * this follows the code). All SwiftUI except the explainer's info button
 * (MacLCExplainer, hosted) and the menus built by MacLCWatchActions. Rows:
 * MacLCWatchShelves.swift; cards and the services bar: MacLCWatchCards.swift;
 * the carousel: MacLCWatchHero.swift.
 * Rules from the pilot (2026-11-18): no SwiftUI animation while a scroll view
 * moves, plain button styles, lazy stacks, per-row @Observable models, scroll
 * geometry mapped to small values, pictures from MacLCWatchImageCache. */

import AppKit
import Observation
import SwiftUI

// MARK: - Objective-C's way in

/// The root of a Watch section when MACLC_SWIFTUI_WATCH=1
/// (MacLCWatchSectionViewController makeRootViewControllerForViewMode:).
/// Answers what the section asks MacLCWatchBrowseViewController.
@objc(MacLCWatchBrowseHostController)
final class WatchBrowseHostController: NSViewController {
    /// MACLC_SWIFTUI_WATCH=1 in the environment: Watch shows this page.
    @objc nonisolated static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["MACLC_SWIFTUI_WATCH"] == "1"
    }

    private let model: WatchBrowseModel

    /// What needs the core comes as blocks: strings through vlc_gettext, the
    /// section's catalogs (SectionCatalogs), error texts, Watch ▸ Add-ons.
    @objc init(section: MacLCWatchSectionViewController,
               localize: @escaping (String) -> String,
               catalogs: @escaping () -> [MacLCAddonTitleCatalog],
               errorMessage: @escaping (Error?) -> String,
               openAddons: @escaping () -> Void) {
        model = WatchBrowseModel(section: section, localize: localize, catalogs: catalogs,
                                 errorMessage: errorMessage, openAddons: openAddons)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func loadView() {
        let host = NSHostingView(rootView: WatchBrowsePage(model: model))
        // The section pins the view to its edges: no size from SwiftUI.
        host.sizingOptions = []
        view = host
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // A pushed page takes this view out of the window: the carousel stops.
        model.isOnScreen = { [weak self] in
            guard let window = self?.view.window else { return false }
            return window.isVisible && window.occlusionState.contains(.visible)
        }
        model.start()
    }

    @objc func applySearchString(_ searchString: String) {
        model.applySearch(searchString)
    }

    /// The carousel is at the top (not searching, no empty state).
    @objc var showsPictureAtTop: Bool { model.showsPictureAtTop }

    /// The carousel's titles once loaded; for the debug hook.
    @objc var featuredItems: [MacLCAddonItem] { model.featured }

    /// Called once, on the main queue, when featuredItems is first non-empty.
    @objc var featuredItemsLoadedHandler: (() -> Void)? {
        get { model.featuredItemsLoadedHandler }
        set { model.featuredItemsLoadedHandler = newValue }
    }
}

// MARK: - Model

/// What replaces the page: no catalogs, every catalog failed, no results.
struct WatchEmptyState: Hashable {
    enum Action { case openAddons, retry }
    let symbol: String
    let title: String
    let message: String?
    let button: String?
    let prominent: Bool
    let action: Action?
}

struct WatchSearchGroup: Identifiable {
    let id: Int
    let title: String
    let subtitle: String?
    let items: [MacLCAddonItem]
}

/// Asks the page to scroll (scope changes); serial makes repeats distinct.
struct PageScrollRequest: Equatable {
    let y: CGFloat
    let serial: Int
}

/// Which cell has the keyboard focus: a row (or search group) and an index.
struct WatchFocus: Hashable {
    let row: String
    let index: Int
}

/// The page's data and state, the Swift side of MacLCWatchBrowseViewController.
/// Rows are rebuilt as AppKit rebuilds its snapshot (rebuildRows), held while
/// a scroll view moves; a row object keeps its identity while its id stays, so
/// SwiftUI updates only what changed in it.
@Observable
final class WatchBrowseModel {
    // MARK: Inputs

    @ObservationIgnored private(set) weak var section: MacLCWatchSectionViewController?
    @ObservationIgnored let mediaType: String?
    @ObservationIgnored let localize: (String) -> String
    @ObservationIgnored private let catalogsProvider: () -> [MacLCAddonTitleCatalog]
    @ObservationIgnored private let errorMessage: (Error?) -> String
    @ObservationIgnored private let openAddonsSettings: () -> Void
    @ObservationIgnored private let defaultsKey: String

    // MARK: What the page shows

    private(set) var rows: [WatchRow] = []
    private(set) var featured: [MacLCAddonItem] = []
    private(set) var services: [MacLCWatchService] = []
    private(set) var selectedServiceCode: String?
    private(set) var emptyState: WatchEmptyState?
    /// Non-nil while search results replace the shelves.
    private(set) var searchGroups: [WatchSearchGroup]?
    var scopeOpacity: Double = 1
    private(set) var pageScrollRequest: PageScrollRequest?

    @ObservationIgnored let scrolling = ScrollActivity()
    @ObservationIgnored let marks = WatchMarks()
    @ObservationIgnored let hero = WatchHeroModel()
    /// The page's view is in a visible window (set by the host controller).
    @ObservationIgnored var isOnScreen: () -> Bool = { false }
    /// Changes with each set of search results, so they start at the top.
    private(set) var searchSerial = 0
    @ObservationIgnored private(set) var showsPictureAtTop = false
    @ObservationIgnored var featuredItemsLoadedHandler: (() -> Void)? {
        didSet { fireFeaturedLoadedHandler() }
    }

    // MARK: Data, as in MacLCWatchBrowseViewController

    @ObservationIgnored private var catalogs: [MacLCAddonTitleCatalog] = []
    @ObservationIgnored private var topCatalogs: [MacLCAddonTitleCatalog] = []
    @ObservationIgnored private(set) var topCatalog: MacLCAddonTitleCatalog?
    @ObservationIgnored private var catalogItems: [String: [MacLCAddonItem]] = [:]
    @ObservationIgnored private var catalogFailed = Set<String>()
    @ObservationIgnored private var topItems: [String: [MacLCAddonItem]] = [:]
    /// The filter chosen per catalog on its shelf (absent: everything).
    @ObservationIgnored private var catalogGenre: [String: String] = [:]
    @ObservationIgnored private var genreItems: [String: [MacLCAddonItem]] = [:]
    @ObservationIgnored private var genreRequested = Set<String>()
    @ObservationIgnored private var genreFailed = Set<String>()
    @ObservationIgnored private var requests: [MacLCAddonRequest] = []
    @ObservationIgnored private var completedCount = 0
    @ObservationIgnored private var failedCount = 0
    @ObservationIgnored private var lastError: Error?
    @ObservationIgnored private var rowCache: [String: WatchRow] = [:]
    @ObservationIgnored private var rebuildHeld = false
    @ObservationIgnored private var collectionStates: [String: WatchCollectionState] = [:]
    /// Kept apart from requests: a reload must not strand a card half resolved.
    @ObservationIgnored private var resolveRequests: [MacLCAddonRequest] = []
    @ObservationIgnored private var warmedURLs = Set<URL>()
    @ObservationIgnored private var hasFiredFeaturedLoadedHandler = false
    @ObservationIgnored private var servicesSheet: MacLCWatchServicesSheetController?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    /// Pull to refresh, on the page's scroll view (WatchRefreshHook).
    @ObservationIgnored private var refreshController: NSRefreshController?
    @ObservationIgnored private var refreshTarget: ActionTarget?

    @ObservationIgnored private var isSearching = false
    @ObservationIgnored private var pendingQuery = ""
    @ObservationIgnored private var searchGeneration = 0
    @ObservationIgnored private var searchRequest: MacLCAddonRequest?
    @ObservationIgnored private var searchTask: Task<Void, Never>?

    @ObservationIgnored private var pageOffset: CGFloat = 0
    @ObservationIgnored private var savedOffset: CGFloat = 0
    @ObservationIgnored private var scrollSerial = 0
    @ObservationIgnored private var heroHeight: CGFloat = 420
    @ObservationIgnored private var safeTop: CGFloat = 0

    /// Add-ons change their catalogs (Cinemeta adds a year every January):
    /// the manifests are fetched again once per launch.
    private static var manifestsRefreshed = false

    init(section: MacLCWatchSectionViewController,
         localize: @escaping (String) -> String,
         catalogs: @escaping () -> [MacLCAddonTitleCatalog],
         errorMessage: @escaping (Error?) -> String,
         openAddons: @escaping () -> Void) {
        self.section = section
        mediaType = section.mediaType
        self.localize = localize
        catalogsProvider = catalogs
        self.errorMessage = errorMessage
        openAddonsSettings = openAddons
        defaultsKey = "MacLCWatchService.\(section.sectionTitle)"
    }

    isolated deinit {
        requests.forEach { $0.cancel() }
        resolveRequests.forEach { $0.cancel() }
        searchRequest?.cancel()
        searchTask?.cancel()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    func start() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .MacLCAddonsDidChange, object: nil, queue: .main) {
            [weak self] _ in
            MainActor.assumeIsolated { self?.addonsDidChange() }
        })
        observers.append(center.addObserver(forName: .MacLCWatchDiscoveryDidChange, object: nil, queue: .main) {
            [weak self] _ in
            MainActor.assumeIsolated { self?.discoveryDidChange() }
        })
        observers.append(center.addObserver(forName: .MacLCWatchLibraryDidChange, object: nil, queue: .main) {
            [weak self] note in
            let changed = note.userInfo?[MacLCWatchLibraryChangedTitlesKey] as? Set<String>
            MainActor.assumeIsolated { self?.libraryDidChange(changed) }
        })
        scrolling.onIdle = { [weak self] in self?.scrollingDidEnd() }
        hero.play = { [weak self] item in self?.open(item, showStreams: true) }
        hero.details = { [weak self] item in self?.open(item, showStreams: false) }
        hero.isVisible = { [weak self] in
            guard let self else { return false }
            return isOnScreen() && searchGroups == nil && emptyState == nil
        }
        hero.isScrolling = { [weak self] in self?.scrolling.isScrolling ?? false }

        if !Self.manifestsRefreshed {
            Self.manifestsRefreshed = true
            MacLCAddonStore.shared.refreshManifests()
        }

        if let saved = UserDefaults.standard.string(forKey: defaultsKey), !saved.isEmpty {
            if MacLCWatchDiscovery.shared.activeServices.contains(where: { $0.code == saved }) {
                selectedServiceCode = saved
            } else {
                UserDefaults.standard.removeObject(forKey: defaultsKey)
            }
        }
        reloadData()
    }

    // MARK: Loading

    func reloadData() {
        requests.forEach { $0.cancel() }
        requests.removeAll()
        searchRequest?.cancel()
        searchRequest = nil

        catalogs = catalogsProvider()
        services = MacLCWatchDiscovery.shared.activeServices
        if catalogs.isEmpty {
            endRefreshing()
            showEmptyState(WatchEmptyState(symbol: "film.stack", title: localize("No Catalogs"),
                                           message: localize("Install an add-on with catalogs to see movies and shows here."),
                                           button: localize("Browse Add-ons…"), prominent: true, action: .openAddons))
            return
        }
        showEmptyState(nil)

        failedCount = 0
        completedCount = 0
        lastError = nil
        catalogItems.removeAll()
        catalogFailed.removeAll()
        topItems.removeAll()
        genreItems.removeAll()
        genreRequested.removeAll()
        genreFailed.removeAll()
        topCatalogs = catalogs.filter { $0.identifier == "top" }
        if topCatalogs.isEmpty, let first = catalogs.first {
            topCatalogs = [first]
        }
        topCatalog = topCatalogs.first

        if let code = selectedServiceCode, let service = MacLCWatchDiscovery.service(forCode: code) {
            ensureServiceCatalogsLoaded(service)
        }
        rebuildRows()

        for catalog in catalogs {
            // A filter chosen on the shelf stays chosen.
            let genre = catalogGenre[catalogKey(catalog)]
            let request = MacLCAddonStore.shared.fetchTitleCatalog(catalog, genre: genre, skip: 0) {
                [weak self] items, error in
                self?.catalogLoaded(catalog, items: items, error: error)
            }
            requests.append(request)
        }
        if mediaType != nil, topCatalog != nil, selectedServiceCode == nil {
            prefetchGenreShelves()
        }
    }

    private func catalogLoaded(_ catalog: MacLCAddonTitleCatalog, items: [MacLCAddonItem]?, error: Error?) {
        let key = catalogKey(catalog)
        completedCount += 1
        // A pull to refresh ends once every catalog answered, loaded or not.
        if completedCount >= catalogs.count {
            endRefreshing()
        }
        if let items, error == nil {
            catalogItems[key] = items
            if catalog.identifier == "top" || catalog === topCatalog {
                topItems[key] = items
                if selectedServiceCode == nil {
                    updateFeatured()
                }
            }
        } else {
            failedCount += 1
            lastError = error
            catalogFailed.insert(key)
            if failedCount == catalogs.count {
                showEmptyState(WatchEmptyState(symbol: "wifi.exclamationmark", title: localize("Can't Load Add-ons"),
                                               message: errorMessage(lastError), button: localize("Try Again"),
                                               prominent: false, action: .retry))
                return
            }
        }
        rebuildRows()
    }

    /// Every genre shelf loads with the page rather than as it nears the
    /// visible area, so that it has its titles when it scrolls into view.
    private func prefetchGenreShelves() {
        guard mediaType != nil, let top = topCatalog, selectedServiceCode == nil else { return }
        for genre in top.genres where genreRequested.insert(genre).inserted {
            let request = MacLCAddonStore.shared.fetchTitleCatalog(top, genre: genre, skip: 0) {
                [weak self] items, error in
                guard let self else { return }
                if let items, error == nil, !items.isEmpty {
                    genreItems[genre] = items
                } else {
                    genreFailed.insert(genre)
                }
                rebuildRows()
            }
            requests.append(request)
        }
    }

    /// An add-on filter chosen on a shelf: that catalog alone loads again.
    func chooseFilter(_ index: Int, of row: WatchRow) {
        guard let catalog = row.catalog, let filter = row.filter, filter.titles.indices.contains(index) else { return }
        let genre: String? = (!catalog.requiresGenre && index == 0) ? nil : filter.titles[index]
        let key = catalogKey(catalog)
        catalogGenre[key] = genre
        row.filter?.selected = index
        let request = MacLCAddonStore.shared.fetchTitleCatalog(catalog, genre: genre, skip: 0) {
            [weak self] items, _ in
            // A later choice wins over an answer that arrives late.
            guard let self, let items, catalogGenre[key] == genre else { return }
            catalogItems[key] = items
            rebuildRows()
        }
        requests.append(request)
    }

    /// Pull to refresh (trackpad or touch screen) loads the shelves again.
    /// SwiftUI's refreshable does nothing on a macOS ScrollView, so the
    /// AppKit controller goes on its HostingScrollView, an NSScrollView.
    /// shortcut: catalogs go through the shared URL cache, so a pull returns
    /// what the HTTP cache allows, as in AppKit.
    func installRefresh(on scrollView: NSScrollView) {
        guard refreshController == nil, scrollView.refreshController == nil else { return }
        let target = ActionTarget { [weak self] in self?.reloadData() }
        let controller = NSRefreshController()
        controller.target = target
        controller.action = #selector(ActionTarget.run(_:))
        scrollView.refreshController = controller
        refreshTarget = target
        refreshController = controller
    }

    private func endRefreshing() {
        refreshController?.endRefreshing()
    }

    func retry() {
        reloadData()
    }

    func openAddons() {
        openAddonsSettings()
    }

    // MARK: Carousel

    private func updateFeatured() {
        var items: [MacLCAddonItem] = []
        var eyebrows: [String] = []
        if let code = selectedServiceCode {
            if let service = MacLCWatchDiscovery.service(forCode: code) {
                let eyebrow = "POPULAR ON \(service.name.uppercased())"
                for item in self.items(for: service).prefix(6) {
                    items.append(item)
                    eyebrows.append(eyebrow)
                }
            }
        } else {
            // Six titles, taken in turn from each "top" catalog.
            for index in 0..<6 {
                for catalog in topCatalogs {
                    guard let list = topItems[catalogKey(catalog)], index < list.count, items.count < 6 else { continue }
                    items.append(list[index])
                    let type = upperSingularTypeName(catalog.type)
                    let name = catalog.name.uppercased()
                    eyebrows.append(name.contains(type) ? name : "\(name) \(type)")
                }
            }
        }
        if items != featured {
            featured = items
        }
        hero.set(items: items, eyebrows: eyebrows)
        updatePictureAtTop()
        fireFeaturedLoadedHandler()
    }

    private func fireFeaturedLoadedHandler() {
        guard !featured.isEmpty, !hasFiredFeaturedLoadedHandler, let handler = featuredItemsLoadedHandler else { return }
        hasFiredFeaturedLoadedHandler = true
        featuredItemsLoadedHandler = nil
        handler()
    }

    // MARK: Services scope

    private func items(for service: MacLCWatchService) -> [MacLCAddonItem] {
        let discovery = MacLCWatchDiscovery.shared
        func loaded(_ type: String) -> [MacLCAddonItem] {
            guard let catalog = discovery.catalog(for: service, type: type) else { return [] }
            return catalogItems[catalogKey(catalog)] ?? []
        }
        if let mediaType {
            return loaded(mediaType)
        }
        let movies = loaded("movie")
        let series = loaded("series")
        var combined: [MacLCAddonItem] = []
        for index in 0..<max(movies.count, series.count) {
            if index < movies.count { combined.append(movies[index]) }
            if index < series.count { combined.append(series[index]) }
        }
        return combined
    }

    private func serviceCatalogs(_ service: MacLCWatchService) -> [MacLCAddonTitleCatalog] {
        let discovery = MacLCWatchDiscovery.shared
        return (mediaType.map { [$0] } ?? ["movie", "series"]).compactMap { discovery.catalog(for: service, type: $0) }
    }

    private func isServiceLoaded(_ service: MacLCWatchService) -> Bool {
        serviceCatalogs(service).allSatisfy {
            catalogItems[catalogKey($0)] != nil || catalogFailed.contains(catalogKey($0))
        }
    }

    private func ensureServiceCatalogsLoaded(_ service: MacLCWatchService) {
        for catalog in serviceCatalogs(service) {
            let key = catalogKey(catalog)
            guard catalogItems[key] == nil, !catalogFailed.contains(key) else { continue }
            let request = MacLCAddonStore.shared.fetchTitleCatalog(catalog, genre: nil, skip: 0) {
                [weak self] items, error in
                guard let self else { return }
                if let items, error == nil {
                    catalogItems[key] = items
                } else {
                    catalogFailed.insert(key)
                }
                if selectedServiceCode == service.code {
                    updateFeatured()
                    rebuildRows()
                }
            }
            requests.append(request)
        }
    }

    /// The services bar re-scopes the whole page, in place: a 0.2 s fade (none
    /// under Reduce Motion); "All" brings back the page and its scroll position.
    func selectService(_ code: String?) {
        guard code != selectedServiceCode else { return }
        if selectedServiceCode == nil {
            savedOffset = pageOffset
        }
        selectedServiceCode = code
        if let code {
            UserDefaults.standard.set(code, forKey: defaultsKey)
            if let service = MacLCWatchDiscovery.service(forCode: code) {
                ensureServiceCatalogsLoaded(service)
            }
        } else {
            UserDefaults.standard.removeObject(forKey: defaultsKey)
        }
        updateFeatured()

        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            applyScopeChange()
        } else {
            withAnimation(.easeInOut(duration: 0.1)) {
                scopeOpacity = 0
            } completion: { [weak self] in
                self?.applyScopeChange()
                withAnimation(.easeInOut(duration: 0.1)) {
                    self?.scopeOpacity = 1
                }
            }
        }
    }

    private func applyScopeChange() {
        rebuildRows(force: true)
        if mediaType != nil, topCatalog != nil, selectedServiceCode == nil {
            prefetchGenreShelves()
        }
        scrollPage(to: selectedServiceCode == nil ? savedOffset : 0)
    }

    func chooseServices() {
        guard let window = section?.view.window else { return }
        let sheet = MacLCWatchServicesSheetController()
        servicesSheet = sheet
        sheet.beginSheetModal(for: window) { [weak self] saved in
            guard let self else { return }
            servicesSheet = nil
            if saved {
                reloadData()
            }
        }
    }

    // MARK: Rows

    /// MacLCWatchBrowseViewController rebuildBrowseSnapshotAnimated: as rows.
    /// Held while a scroll view of the page moves (a new row lays the page out
    /// again on the frames of that scroll), then done when the last one stops.
    func rebuildRows(force: Bool = false) {
        if scrolling.isScrolling && !force {
            rebuildHeld = true
            return
        }
        rebuildHeld = false

        let prefix = selectedServiceCode.map { "service_\($0):" } ?? "all:"
        let firstAddon = MacLCAddonStore.shared.installedAddons.first?.identifier
        func addonSubtitle(_ catalog: MacLCAddonTitleCatalog) -> String? {
            firstAddon != nil && catalog.addon.identifier != firstAddon ? catalog.addon.name : nil
        }
        var next: [WatchRow] = []
        func row(_ id: String, _ kind: WatchRow.Kind, title: String) -> WatchRow {
            let row = rowCache[id] ?? WatchRow(id: id, kind: kind)
            row.update(\.title, title)
            next.append(row)
            return row
        }

        // Continue Watching, shown even while scoped to a service.
        let entries = continueEntries()
        if !entries.isEmpty {
            row("\(prefix)continue_section", .continueWatching, title: localize("Continue Watching"))
                .update(\.entries, entries)
        }

        if let code = selectedServiceCode {
            if let service = MacLCWatchDiscovery.service(forCode: code) {
                let title = String(format: localize("Top on %@"), service.name)
                let top = row("\(prefix)top_service", .ranked, title: title)
                if let mediaType, let catalog = MacLCWatchDiscovery.shared.catalog(for: service, type: mediaType) {
                    top.seeAll = { [weak self] in self?.seeAll(catalog, genre: nil, title: title) }
                }
                let all = items(for: service)
                if !all.isEmpty {
                    top.update(\.items, Array(all.prefix(20)))
                } else if !isServiceLoaded(service) {
                    top.update(\.items, nil)
                } else {
                    top.update(\.items, [])
                }
                if !all.isEmpty {
                    for genre in MacLCWatchDiscovery.shared.genres(forMediaType: mediaType) {
                        let matched = MacLCWatchDiscovery.items(all, matchingGenre: genre)
                        guard matched.count >= 4 else { continue }
                        row("\(prefix)service_genre_\(genre)", .posters, title: "\(service.name) · \(genre)")
                            .update(\.items, matched)
                    }
                }
            }
        } else {
            // Browse by Genre, right under Continue Watching.
            let genres = MacLCWatchDiscovery.shared.genres(forMediaType: mediaType)
            if !genres.isEmpty {
                let tiles = row("\(prefix)genre_tiles_section", .genres, title: localize("Browse by Genre"))
                tiles.update(\.genres, genres)
                tiles.update(\.genrePosters, Dictionary(uniqueKeysWithValues: genres.map { ($0, posters(forGenre: $0)) }))
            }

            // The Edit.
            let discovery = MacLCWatchDiscovery.shared
            let now = Date()
            let collections = discovery.edit(for: now, mediaType: mediaType, count: 3)
            if !collections.isEmpty {
                let formatter = DateFormatter()
                formatter.setLocalizedDateFormatFromTemplate("MMM d")
                let edit = row("\(prefix)edit_section", .edit, title: localize("The Edit"))
                edit.update(\.subtitle, String(format: localize("New collections every two weeks · Next on %@"),
                                              formatter.string(from: discovery.nextEditDate(after: now))))
                edit.explainerTopic = .collections
                edit.update(\.collections, collections)
            }

            // More collections, two after every second shelf below; a larger
            // count is another pick for the same period, the top three dropped.
            let shown = Set(collections.map(\.identifier))
            var more = discovery.edit(for: now, mediaType: mediaType, count: 9).filter { !shown.contains($0.identifier) }
            var shelvesSinceEdit = 0
            func appendMoreEdit() {
                shelvesSinceEdit += 1
                guard shelvesSinceEdit >= 2, !more.isEmpty else { return }
                shelvesSinceEdit = 0
                let group = Array(more.prefix(2))
                more.removeFirst(group.count)
                row("\(prefix)edit_section_more_\(group[0].identifier)", .edit, title: localize("More from The Edit"))
                    .update(\.collections, group)
            }

            // Top 10.
            for catalog in topCatalogs {
                let key = catalogKey(catalog)
                guard !catalogFailed.contains(key) else { continue }
                let title = String(format: localize("Top 10 %@"), pluralTypeName(catalog.type))
                let top = row("\(prefix)top_\(key)", .ranked, title: title)
                top.update(\.subtitle, addonSubtitle(catalog))
                top.seeAll = { [weak self] in self?.seeAll(catalog, genre: nil, title: title) }
                top.update(\.items, catalogItems[key].map { Array($0.prefix(10)) })
            }

            // The other catalogs (the services add-on's are what the bar scopes to).
            let servicesAddon = discovery.servicesAddon?.identifier
            for catalog in catalogs where catalog.identifier != "top" {
                let key = catalogKey(catalog)
                guard catalog.addon.identifier != servicesAddon, catalog.addon.identifier != "pw.ers.netflix-catalog",
                      !catalogFailed.contains(key) else { continue }
                let plural = pluralTypeName(catalog.type)
                let title = !plural.isEmpty && !catalog.name.lowercased().contains(plural.lowercased())
                    ? "\(catalog.name) \(plural)" : catalog.name
                let shelf = row("\(prefix)catalog_\(key)", .posters, title: title)
                shelf.update(\.subtitle, addonSubtitle(catalog))
                shelf.seeAll = { [weak self] in self?.seeAll(catalog, genre: nil, title: title) }
                shelf.catalog = catalog
                if !catalog.genres.isEmpty {
                    let titles = (catalog.requiresGenre ? [] : [localize("All Genres")]) + catalog.genres
                    let chosen = catalogGenre[key].flatMap { titles.firstIndex(of: $0) } ?? 0
                    shelf.update(\.filter, WatchRowFilter(titles: titles, selected: chosen))
                }
                shelf.update(\.items, catalogItems[key])
                appendMoreEdit()
            }

            // Movies and TV Shows: one shelf per genre of the "top" catalog.
            if mediaType != nil, let top = topCatalog {
                for genre in top.genres where !genreFailed.contains(genre) {
                    let title = String(format: localize("Popular in %@"), genre)
                    let shelf = row("\(prefix)popular_genre_\(genre)", .posters, title: title)
                    shelf.update(\.subtitle, addonSubtitle(top))
                    shelf.seeAll = { [weak self] in self?.seeAll(top, genre: genre, title: title) }
                    shelf.update(\.items, genreItems[genre])
                    appendMoreEdit()
                }
            }
        }

        if next.map(\.id) != rows.map(\.id) {
            rows = next
        }
        rowCache = Dictionary(uniqueKeysWithValues: next.map { ($0.id, $0) })
    }

    private func scrollingDidEnd() {
        if rebuildHeld {
            rebuildRows()
        }
    }

    /// Titles whose genres contain genre, 2 at most, from shelves loaded.
    private func posters(forGenre genre: String) -> [MacLCAddonItem] {
        var found: [MacLCAddonItem] = []
        for catalog in catalogs {
            for item in catalogItems[catalogKey(catalog)] ?? []
            where item.genres.contains(where: { $0.caseInsensitiveCompare(genre) == .orderedSame }) {
                found.append(item)
                if found.count == 2 { return found }
            }
        }
        return found
    }

    private func continueEntries() -> [MacLCWatchEntry] {
        let all = MacLCWatchLibrary.shared.continueWatchingEntries
        guard let mediaType else { return all }
        return all.filter { $0.type == mediaType }
    }

    /// A collection card's resolved titles, shared by its card wherever shown.
    func collectionState(_ collection: MacLCWatchCollection) -> WatchCollectionState {
        if let state = collectionStates[collection.identifier] {
            return state
        }
        let state = WatchCollectionState(items: MacLCWatchDiscovery.shared.resolvedItems(for: collection))
        collectionStates[collection.identifier] = state
        return state
    }

    /// Cards resolve their collection when about to be shown.
    func resolve(_ collection: MacLCWatchCollection) {
        let state = collectionState(collection)
        guard state.items == nil, !state.requested else { return }
        state.requested = true
        let request = MacLCWatchDiscovery.shared.resolve(collection) { [weak state] items in
            state?.items = items
        }
        resolveRequests.append(request)
    }

    /// The first ten posters of the shelves from this one to ten below are
    /// decoded ahead at the cells' size (AppKit's warmPostersAhead), so cells
    /// scroll in with their picture.
    func rowDidAppear(_ row: WatchRow) {
        guard let index = rows.firstIndex(where: { $0 === row }) else { return }
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        for ahead in rows[index..<min(index + 11, rows.count)] {
            for url in (ahead.items ?? []).prefix(10).compactMap(\.posterURL) where warmedURLs.insert(url).inserted {
                _ = MacLCWatchImageCache.shared.image(for: url, pointSize: posterSize, scale: scale,
                                                      request: nil) { _ in }
            }
        }
    }

    // MARK: Keyboard

    /// Arrow keys between cells: along a row, or to the row above or below,
    /// onto the first cell it shows.
    func focus(after current: WatchFocus?, _ direction: MoveCommandDirection) -> WatchFocus? {
        guard let current, let rowIndex = rows.firstIndex(where: { $0.id == current.row }) else { return nil }
        let row = rows[rowIndex]
        switch direction {
        case .left:
            return current.index > 0 ? WatchFocus(row: row.id, index: current.index - 1) : nil
        case .right:
            return current.index + 1 < row.itemCount ? WatchFocus(row: row.id, index: current.index + 1) : nil
        case .up, .down:
            let step = direction == .up ? -1 : 1
            var target = rowIndex + step
            while rows.indices.contains(target), rows[target].itemCount == 0 {
                target += step
            }
            guard rows.indices.contains(target) else { return nil }
            let other = rows[target]
            let first = Int((other.scrolled / other.kind.pitch).rounded())
            return WatchFocus(row: other.id, index: min(max(0, first), other.itemCount - 1))
        @unknown default:
            return nil
        }
    }

    // MARK: Navigation

    func open(_ item: MacLCAddonItem, showStreams: Bool = false) {
        section?.showDetail(for: item, showStreams: showStreams)
    }

    func seeAll(_ catalog: MacLCAddonTitleCatalog, genre: String?, title: String) {
        guard let section else { return }
        section.push(MacLCWatchCatalogViewController(section: section, catalog: catalog, genre: genre, title: title))
    }

    func open(_ collection: MacLCWatchCollection) {
        guard let section else { return }
        section.push(MacLCWatchCollectionViewController(section: section, collection: collection))
    }

    func openGenre(_ genre: String) {
        guard let top = topCatalog else { return }
        let format = mediaType == "series" ? localize("%@ Shows") : localize("%@ Movies")
        seeAll(top, genre: genre, title: String(format: format, genre))
    }

    func resume(_ entry: MacLCWatchEntry) {
        guard let section else { return }
        MacLCWatchResumeEntry(entry, section)
    }

    // MARK: Search

    /// Two or more characters replace the shelves with the results of the
    /// section's type, 300 ms after the last keystroke; less brings them back.
    func applySearch(_ string: String) {
        pendingQuery = string
        searchTask?.cancel()
        if string.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 {
            executeSearch()
        } else {
            searchTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                self?.executeSearch()
            }
        }
    }

    private func executeSearch() {
        let query = pendingQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else {
            if isSearching {
                isSearching = false
                searchRequest?.cancel()
                searchRequest = nil
                searchGroups = nil
                showEmptyState(nil)
                rebuildRows()
            }
            return
        }
        isSearching = true
        updatePictureAtTop()
        searchRequest?.cancel()
        searchGeneration += 1
        let generation = searchGeneration
        searchRequest = MacLCAddonStore.shared.searchTitles(query) { [weak self] groups in
            guard let self, generation == searchGeneration, isSearching else { return }
            searchRequest = nil
            let firstAddon = MacLCAddonStore.shared.installedAddons.first?.identifier
            var results: [WatchSearchGroup] = []
            for group in groups where (mediaType == nil || group.type == mediaType) && !group.items.isEmpty {
                let title: String
                switch group.type {
                case "movie": title = localize("Movies")
                case "series": title = localize("TV Shows")
                default: title = group.catalogName.isEmpty ? pluralTypeName(group.type) : group.catalogName
                }
                let subtitle = firstAddon != nil && group.addon.identifier != firstAddon ? group.addon.name : nil
                results.append(WatchSearchGroup(id: results.count, title: title, subtitle: subtitle, items: group.items))
            }
            if results.isEmpty {
                showEmptyState(WatchEmptyState(symbol: "magnifyingglass",
                                               title: String(format: localize("No Results for “%@”"), query),
                                               message: localize("Check the spelling or try a new search."),
                                               button: nil, prominent: false, action: nil))
            } else {
                showEmptyState(nil)
                searchSerial += 1
                searchGroups = results
            }
        }
    }

    private func showEmptyState(_ state: WatchEmptyState?) {
        if emptyState != state {
            emptyState = state
        }
        updatePictureAtTop()
    }

    // MARK: Notifications

    private func addonsDidChange() {
        if isSearching {
            executeSearch()
        } else {
            reloadData()
        }
    }

    /// The services add-on changed: the page loads again. The notification
    /// also comes each time a collection resolves, which only its cards need
    /// (WatchCollectionState): AppKit reloads the page then too, this skips it.
    private func discoveryDidChange() {
        guard !isSearching else { return }
        let active = MacLCWatchDiscovery.shared.activeServices
        guard active.map(\.code) != services.map(\.code) else { return }
        if let code = selectedServiceCode, !active.contains(where: { $0.code == code }) {
            selectedServiceCode = nil
            UserDefaults.standard.removeObject(forKey: defaultsKey)
        }
        reloadData()
    }

    /// History or favorites changed: the Continue Watching row follows when
    /// one of its titles (or one that should join it) changed.
    private func libraryDidChange(_ changed: Set<String>?) {
        guard !isSearching else { return }
        if let changed {
            let shown = rows.first { $0.kind == .continueWatching }?.entries.map(\.identifier) ?? []
            let current = continueEntries().map(\.identifier)
            guard !changed.isDisjoint(with: shown) || !changed.isDisjoint(with: current) else { return }
        }
        rebuildRows()
    }

    // MARK: Scrolling

    func pageMetricsChanged(width: CGFloat, heroHeight: CGFloat, safeTop: CGFloat) {
        self.heroHeight = heroHeight
        self.safeTop = safeTop
        hero.resize(CGSize(width: width, height: heroHeight))
        updatePictureAtTop()
    }

    /// Every frame of a page scroll: whether the window title may show (the
    /// carousel's parallax runs in its own visualEffect).
    func pageScrolled(_ offset: CGFloat) {
        pageOffset = offset
        updatePictureAtTop()
    }

    private func scrollPage(to y: CGFloat) {
        scrollSerial += 1
        pageScrollRequest = PageScrollRequest(y: y, serial: scrollSerial)
    }

    /// The window title would sit on the picture: the section hides it until
    /// the carousel has scrolled out from under the toolbar.
    private func updatePictureAtTop() {
        let atTop = !featured.isEmpty && !isSearching && searchGroups == nil && emptyState == nil
            && pageOffset + safeTop < heroHeight
        if atTop != showsPictureAtTop {
            showsPictureAtTop = atTop
            section?.chromeDidChange()
        }
    }

    // MARK: Names

    private func catalogKey(_ catalog: MacLCAddonTitleCatalog) -> String {
        "\(catalog.addon.identifier)_\(catalog.type)_\(catalog.identifier)"
    }

    private func pluralTypeName(_ type: String) -> String {
        switch type {
        case "movie": return localize("Movies")
        case "series": return localize("TV Shows")
        default: return type.prefix(1).uppercased() + type.dropFirst()
        }
    }

    private func upperSingularTypeName(_ type: String) -> String {
        switch type {
        case "movie": return "MOVIE"
        case "series", "tv": return "TV SHOW"
        default: return type.uppercased()
        }
    }
}

/// A collection's titles once resolved (nil before), for its cards.
@Observable
final class WatchCollectionState {
    var items: [MacLCAddonItem]?
    @ObservationIgnored var requested = false

    init(items: [MacLCAddonItem]?) {
        self.items = items
    }
}

// MARK: - Page

private nonisolated struct PageMetrics: Equatable {
    var width: CGFloat = 800
    var height: CGFloat = 800
    var safeTop: CGFloat = 0
}

struct WatchBrowsePage: View {
    let model: WatchBrowseModel

    @State private var position = ScrollPosition(edge: .top)
    @State private var metrics = PageMetrics()
    @FocusState private var focus: WatchFocus?

    /// The carousel's height for the page's (the scroll view's, as AppKit's
    /// collection view sees it).
    private var heroHeight: CGFloat {
        WatchHeroModel.height(forAvailableHeight: metrics.height + metrics.safeTop)
    }

    var body: some View {
        let browseHidden = model.searchGroups != nil || model.emptyState != nil
        ZStack {
            browse
                .opacity(browseHidden ? 0 : 1)
                .allowsHitTesting(!browseHidden)
                .accessibilityHidden(browseHidden)
            if let groups = model.searchGroups, model.emptyState == nil {
                WatchSearchResults(groups: groups, model: model, focus: $focus)
                    .id(model.searchSerial)
            }
            if let state = model.emptyState {
                WatchEmptyStateView(state: state, model: model)
            }
        }
        .onGeometryChange(for: PageMetrics.self) { proxy in
            PageMetrics(width: proxy.size.width, height: proxy.size.height, safeTop: proxy.safeAreaInsets.top)
        } action: { value in
            metrics = value
            model.pageMetricsChanged(width: value.width, heroHeight: heroHeight, safeTop: value.safeTop)
        }
    }

    private var browse: some View {
        let showsHero = !model.featured.isEmpty
        return ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                if showsHero {
                    WatchHeroView(hero: model.hero, height: heroHeight, localize: model.localize,
                                  scrolling: model.scrolling)
                }
                WatchServicesBar(model: model)
                    .padding(.horizontal, sideInset)
                    .padding(.top, 12)
                    .padding(.bottom, sectionSpacing)
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(model.rows) { row in
                        WatchShelfRow(row: row, model: model, focus: $focus)
                            .onAppear { model.rowDidAppear(row) }
                    }
                }
            }
            .opacity(model.scopeOpacity)
            .background(WatchRefreshHook(model: model))
        }
        // MacLC shows no scrollers (NSScrollView (MacLCHiddenScrollers)).
        .scrollIndicators(.never)
        .scrollPosition($position)
        // The carousel goes under the toolbar (AppKit: top content inset 0).
        .ignoresSafeArea(.container, edges: showsHero ? .top : [])
        .onScrollPhaseChange { _, phase in model.scrolling.setPage(phase.isScrolling) }
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { _, offset in
            model.pageScrolled(offset)
        }
        .onChange(of: model.pageScrollRequest) { _, request in
            if let request {
                position.scrollTo(y: request.y)
            }
        }
        .onMoveCommand { direction in
            if let next = model.focus(after: focus, direction) {
                focus = next
            }
        }
    }
}

/// Finds the page's scroll view once in a window and gives it the pull to
/// refresh controller.
private struct WatchRefreshHook: NSViewRepresentable {
    let model: WatchBrowseModel

    final class HookView: NSView {
        var install: ((NSScrollView) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil, let scrollView = enclosingScrollView {
                install?(scrollView)
            }
        }
    }

    func makeNSView(context: Context) -> HookView {
        let view = HookView()
        view.install = { [weak model] in model?.installRefresh(on: $0) }
        return view
    }

    func updateNSView(_ nsView: HookView, context: Context) {}
}

/// MacLCEmptyStateView: centred, at most 420 wide: the symbol (48 pt, light,
/// tertiary), 16 pt, the title (title2, semibold), 6 pt, the message (body,
/// secondary), 20 pt, the button (glass and prominent when recommended).
/// VoiceOver: a group "title. message".
private struct WatchEmptyStateView: View {
    let state: WatchEmptyState
    let model: WatchBrowseModel

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: state.symbol)
                .font(.system(size: 48, weight: .light))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Text(state.title)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
                .padding(.top, 16)
            if let message = state.message {
                Text(message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 6)
            }
            if let title = state.button, let action = state.action {
                Group {
                    if state.prominent {
                        Button(title) { perform(action) }
                            .buttonStyle(.glassProminent)
                    } else {
                        Button(title) { perform(action) }
                    }
                }
                .padding(.top, 20)
            }
        }
        .frame(maxWidth: 420)
        .accessibilityElement(children: .contain)
        .accessibilityLabel([state.title, state.message ?? ""].filter { !$0.isEmpty }.joined(separator: ". "))
    }

    private func perform(_ action: WatchEmptyState.Action) {
        switch action {
        case .openAddons: model.openAddons()
        case .retry: model.retry()
        }
    }
}

// MARK: - Search results

/// Results headed per catalog, each a poster grid: as many columns as fit at
/// 150-200 wide, 20 apart, 32 between rows (MacLCWatchLayout
/// posterGridSectionWithEnvironment:hasHeader:YES).
private struct WatchSearchResults: View {
    let groups: [WatchSearchGroup]
    let model: WatchBrowseModel
    var focus: FocusState<WatchFocus?>.Binding

    @State private var width: CGFloat = 800

    private var grid: (columns: Int, itemWidth: CGFloat) {
        let available = max(width - 2 * sideInset, 150)
        var columns = max(1, Int((available + itemSpacing) / (150 + itemSpacing)))
        var itemWidth = (available - CGFloat(columns - 1) * itemSpacing) / CGFloat(columns)
        while itemWidth > 200 {
            columns += 1
            itemWidth = (available - CGFloat(columns - 1) * itemSpacing) / CGFloat(columns)
        }
        return (columns, itemWidth.rounded(.down))
    }

    var body: some View {
        let grid = self.grid
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(groups) { group in
                    ShelfHeader(title: group.title, subtitle: group.subtitle, topic: nil, filter: nil,
                                model: model, seeAll: nil, paging: nil, page: { _ in }, chooseFilter: { _ in })
                        .padding(.horizontal, sideInset)
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(grid.itemWidth), spacing: itemSpacing,
                                                                 alignment: .top), count: grid.columns),
                              alignment: .leading, spacing: 32) {
                        ForEach(Array(group.items.enumerated()), id: \.offset) { index, item in
                            PosterCell(item: item, rank: 0, width: grid.itemWidth, model: model)
                                .watchCell(WatchFocus(row: "search_\(group.id)", index: index), focus: focus) {
                                    model.open(item)
                                }
                        }
                    }
                    .padding(.top, 16)
                    .padding(.horizontal, sideInset)
                    .padding(.bottom, sectionSpacing)
                }
            }
        }
        .scrollIndicators(.never)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .onScrollPhaseChange { _, phase in model.scrolling.setPage(phase.isScrolling) }
        // Cleared while still moving: the page must not stay "scrolling".
        .onDisappear { model.scrolling.setPage(false) }
        .onMoveCommand { direction in
            guard let current = focus.wrappedValue, current.row.hasPrefix("search_"),
                  let group = groups.first(where: { "search_\($0.id)" == current.row }) else { return }
            let step: Int
            switch direction {
            case .left: step = -1
            case .right: step = 1
            case .up: step = -grid.columns
            case .down: step = grid.columns
            @unknown default: step = 0
            }
            let index = current.index + step
            if group.items.indices.contains(index) {
                focus.wrappedValue = WatchFocus(row: current.row, index: index)
            }
        }
    }
}
