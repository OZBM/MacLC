/*****************************************************************************
 * MacLCWatchDetailPage.swift: Watch's title page in SwiftUI
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

/* MacLCWatchDetailViewController (MacLCWatchDetail.m) in SwiftUI, behind
 * MACLC_SWIFTUI_WATCH=1: the header picture, logo, facts, description, Play
 * and its companions, the credits; a show's season pop-up and episodes; About;
 * More Like This (contract in MacLCWatchSections.h; where it and the .m
 * differ, this follows the code). The stream picker stays AppKit
 * (MacLCStreamPickerController, a sheet); the trailer and runtime text come
 * from MacLCWatchDetail.m (MacLCWatchPlayTrailer, MacLCFormatRuntime).
 * Same rules as the browse page: no SwiftUI animation while a scroll view
 * moves, plain button styles in cells, lazy stacks, per-title marks. */

import AppKit
import Observation
import SwiftUI

// MARK: - Objective-C's way in

/// The title page when MACLC_SWIFTUI_WATCH=1: MacLCWatchSectionViewController
/// showDetailForItem:showStreams: pushes it instead of
/// MacLCWatchDetailViewController.
@objc(MacLCWatchDetailHostController)
final class WatchDetailHostController: NSViewController {
    private let model: WatchDetailModel

    /// showStreams: open the stream picker once the meta is known (the
    /// carousel's Play). localize: vlc_gettext.
    @objc init(item: MacLCAddonItem, showStreams: Bool, section: MacLCWatchSectionViewController,
               localize: @escaping (String) -> String) {
        model = WatchDetailModel(item: item, showStreams: showStreams, section: section, localize: localize)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    @objc var item: MacLCAddonItem { model.item }

    override func loadView() {
        let host = NSHostingView(rootView: WatchDetailPage(model: model))
        // The section pins the view to its edges: no size from SwiftUI.
        host.sizingOptions = []
        view = host
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        model.window = { [weak self] in self?.view.window }
        model.start()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        model.didAppear()
    }
}

// MARK: - Model

/// What Play does and says, from the watch history (updatePlayButtonAndStates).
struct DetailPlayState: Equatable {
    var title = ""
    var symbol = "play.fill"
    var startOver = false
    /// The "Watched" pill (movies).
    var watched = false
    /// "1 h 20 min left" under the facts, and the bar's fraction, while a
    /// movie can resume.
    var resumeText: String?
    var fraction: Double?
}

/// The title page's data: the item's own fields at once, the meta when it
/// arrives, the history's state for Play, the episodes and More Like This.
@Observable
final class WatchDetailModel: WatchPageModel {
    @ObservationIgnored let item: MacLCAddonItem
    @ObservationIgnored let localize: (String) -> String
    @ObservationIgnored let scrolling = ScrollActivity()
    @ObservationIgnored let marks = WatchMarks()
    @ObservationIgnored private weak var section: MacLCWatchSectionViewController?
    /// The page's window, for the stream picker and the trailer's alert.
    @ObservationIgnored var window: () -> NSWindow? = { nil }

    private(set) var meta: MacLCAddonMeta?
    /// A show's meta failed: "Can't load episodes" and Try Again.
    private(set) var episodesFailed = false
    private(set) var seasons: [Int] = []
    private(set) var season = 1
    private(set) var episodes: [MacLCAddonVideo] = []
    private(set) var similar: [MacLCAddonItem] = []
    private(set) var play = DetailPlayState()
    private(set) var favorite = false
    private(set) var trailerLoading = false
    /// The meta request answered (episode placeholders until then).
    private(set) var metaAnswered = false

    @ObservationIgnored private var showStreams: Bool
    @ObservationIgnored private var appeared = false
    @ObservationIgnored private var metaRequest: MacLCAddonRequest?
    @ObservationIgnored private var similarRequest: MacLCAddonRequest?
    @ObservationIgnored private var picker: MacLCStreamPickerController?
    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private var episodeMarks: [String: TitleMarks] = [:]

    init(item: MacLCAddonItem, showStreams: Bool, section: MacLCWatchSectionViewController,
         localize: @escaping (String) -> String) {
        self.item = item
        self.showStreams = showStreams
        self.section = section
        self.localize = localize
    }

    isolated deinit {
        metaRequest?.cancel()
        similarRequest?.cancel()
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func start() {
        observer = NotificationCenter.default.addObserver(forName: .MacLCWatchLibraryDidChange, object: nil,
                                                          queue: .main) { [weak self] note in
            let changed = note.userInfo?[MacLCWatchLibraryChangedTitlesKey] as? Set<String>
            MainActor.assumeIsolated { self?.libraryDidChange(changed) }
        }
        updatePlayState()
        loadMeta()
    }

    func didAppear() {
        appeared = true
        playIfAsked()
    }

    // MARK: What the page shows (meta first, then the item)

    var name: String { meta?.name ?? item.name }
    var descriptionText: String { meta?.itemDescription ?? item.itemDescription ?? "" }
    var genres: [String] {
        if let genres = meta?.genres, !genres.isEmpty { return genres }
        return item.genres
    }
    var releaseInfo: String? { meta?.releaseInfo ?? item.releaseInfo }
    var runtime: String? { meta?.runtime ?? item.runtime }
    /// "★ 7.8 IMDb" (as the add-on wrote it when it says IMDb).
    var ratingText: String? {
        guard let rating = meta?.imdbRating ?? item.imdbRating, !rating.isEmpty else { return nil }
        return rating.contains("IMDb") ? rating : "★ \(rating) IMDb"
    }
    var backgroundURL: URL? { meta?.backgroundURL ?? item.backgroundURL ?? meta?.posterURL ?? item.posterURL }
    var logoURL: URL? { meta?.logoURL ?? item.logoURL }
    var trailer: String? {
        guard let trailer = meta?.trailerYouTubeIdentifier, !trailer.isEmpty else { return nil }
        return trailer
    }
    var cast: [String] { Array((meta?.cast ?? []).prefix(3)) }
    var directors: [String] { meta?.directors ?? [] }
    /// "Movie · Drama · Crime": type and genres (the year and rating are on
    /// the details line).
    var factsLine: String { MacLCWatchFactsLine(item.type, genres, nil, nil) }
    /// "2026 · 1 h 41 min · ★ 7.8 IMDb".
    var detailsLine: String {
        var parts: [String] = []
        if let release = releaseInfo, !release.isEmpty { parts.append(release) }
        if let runtime, !runtime.isEmpty {
            let formatted = MacLCFormatRuntime(runtime)
            if !formatted.isEmpty { parts.append(formatted) }
        }
        if let ratingText { parts.append(ratingText) }
        return parts.joined(separator: " · ")
    }

    var isSeries: Bool {
        item.type == "series" || item.type == "tv" || !(meta?.videos.isEmpty ?? true)
    }

    // MARK: Loading

    func loadMeta() {
        metaRequest?.cancel()
        episodesFailed = false
        metaAnswered = false
        metaRequest = MacLCAddonStore.shared.fetchMeta(for: item) { [weak self] meta, error in
            self?.metaLoaded(meta, error: error)
        }
    }

    private func metaLoaded(_ newMeta: MacLCAddonMeta?, error: Error?) {
        metaRequest = nil
        metaAnswered = true
        if error != nil && isSeries {
            episodesFailed = true
        } else if let newMeta {
            meta = newMeta
            if !newMeta.videos.isEmpty {
                MacLCWatchLibrary.shared.updateEpisodes(newMeta.videos, for: item)
            }
            loadSimilar()
            if isSeries {
                populateSeasons()
            }
            updatePlayState()
        }
        playIfAsked()
    }

    /// The "top" catalog of the item's type, for the first of its genres that
    /// catalog offers; the item left out, 20 at most.
    private func loadSimilar() {
        guard similarRequest == nil, similar.isEmpty else { return }
        let genres = self.genres
        for catalog in MacLCAddonStore.shared.titleCatalogs where catalog.identifier == "top" && catalog.type == item.type {
            guard let genre = genres.first(where: { catalog.genres.contains($0) }) else { continue }
            similarRequest = MacLCAddonStore.shared.fetchTitleCatalog(catalog, genre: genre, skip: 0) {
                [weak self] items, _ in
                guard let self else { return }
                similarRequest = nil
                let others = (items ?? []).filter { $0.identifier != item.identifier }
                if !others.isEmpty {
                    similar = Array(others.prefix(20))
                }
            }
            return
        }
    }

    // MARK: Seasons and episodes

    /// The seasons in order, Specials (0) last; the first one shown.
    private func populateSeasons() {
        let all = Set((meta?.videos ?? []).map(\.season))
        seasons = all.sorted { a, b in a == 0 ? false : b == 0 ? true : a < b }
        selectSeason(seasons.first ?? 1)
    }

    func selectSeason(_ newSeason: Int) {
        season = newSeason
        episodes = (meta?.videos ?? []).filter { $0.season == newSeason }.sorted { $0.episode < $1.episode }
    }

    func seasonTitle(_ season: Int) -> String {
        season == 0 ? localize("Specials") : String(format: localize("Season %ld"), season)
    }

    /// An episode's watched state and progress, updated with the history.
    func marks(for video: MacLCAddonVideo) -> TitleMarks {
        if let marks = episodeMarks[video.identifier] {
            return marks
        }
        let marks = TitleMarks()
        update(marks, video: video.identifier)
        episodeMarks[video.identifier] = marks
        return marks
    }

    private func update(_ marks: TitleMarks, video: String) {
        let progress = MacLCWatchLibrary.shared.progress(forTitle: item.identifier, video: video)
        let watched = progress?.isWatched ?? false
        let fraction = !watched && progress?.canResume == true ? progress?.fraction ?? 0 : 0
        if marks.watched != watched { marks.watched = watched }
        if marks.fraction != fraction { marks.fraction = fraction }
    }

    /// Released episodes of the season shown (no date counts as released).
    private var releasedEpisodes: [MacLCAddonVideo] {
        let now = Date()
        return episodes.filter { $0.released.map { $0 <= now } ?? true }
    }

    /// The "…" button: MacLCWatchActions' menu, then for a show "Mark Season 2
    /// as Watched" (or "…as Unwatched" when all its released episodes are).
    /// Pops at the pointer and returns once it closed, its action run.
    func showActionsMenu() {
        let menu = MacLCWatchActions.menu(for: item, video: nil, inHistory: false)
        let released = isSeries ? releasedEpisodes : []
        var target: ActionTarget?
        if !released.isEmpty {
            let library = MacLCWatchLibrary.shared
            let allWatched = released.allSatisfy {
                library.progress(forTitle: item.identifier, video: $0.identifier)?.isWatched == true
            }
            let title: String
            if allWatched {
                title = season == 0 ? localize("Mark Specials as Unwatched")
                    : String(format: localize("Mark Season %ld as Unwatched"), season)
            } else {
                title = season == 0 ? localize("Mark Specials as Watched")
                    : String(format: localize("Mark Season %ld as Watched"), season)
            }
            target = ActionTarget { [item] in
                library.markWatched(!allWatched, for: item, videos: released)
            }
            let entry = NSMenuItem(title: title, action: #selector(ActionTarget.run(_:)), keyEquivalent: "")
            entry.target = target
            entry.image = NSImage(systemSymbolName: allWatched ? "arrow.counterclockwise.circle" : "checkmark.circle",
                                  accessibilityDescription: title)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .regular))
            if !menu.items.isEmpty {
                menu.addItem(.separator())
            }
            menu.addItem(entry)
        }
        withExtendedLifetime(target) {
            _ = menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        }
    }

    // MARK: History

    private func libraryDidChange(_ changed: Set<String>?) {
        guard changed?.contains(item.identifier) ?? true else { return }
        updatePlayState()
        for (video, marks) in episodeMarks {
            update(marks, video: video)
        }
    }

    private func updatePlayState() {
        let library = MacLCWatchLibrary.shared
        let entry = library.entry(forTitle: item.identifier)
        var state = DetailPlayState()
        if !isSeries {
            let progress = library.progress(forTitle: item.identifier, video: nil)
            let canResume = progress?.canResume == true || entry?.resumeTarget?.kind == .resume
            state.watched = progress?.isWatched == true || entry?.isWatched == true
            if canResume {
                state.title = localize("Resume")
                state.startOver = true
                state.resumeText = resumeText(entry: entry, progress: progress)
                state.fraction = progress?.fraction ?? entry?.fraction ?? 0
            } else if state.watched {
                state.title = localize("Play Again")
                state.symbol = "arrow.counterclockwise"
            } else {
                state.title = localize("Play")
            }
        } else if let target = entry?.resumeTarget, video(for: target) != nil {
            state.title = String(format: localize(target.kind == .resume ? "Resume S%ld, E%ld" : "Play S%ld, E%ld"),
                                 target.season, target.episode)
        } else if let first = firstPlayableEpisode(), first.season >= 1, first.episode >= 1 {
            state.title = String(format: localize("Play S%ld, E%ld"), first.season, first.episode)
        } else {
            state.title = localize("Play S1, E1")
        }
        if state != play {
            play = state
        }
        let isFavorite = library.isFavorite(item.identifier)
        if isFavorite != favorite {
            favorite = isFavorite
        }
    }

    /// The resume target's text, else the time left ("1 h 20 min left").
    private func resumeText(entry: MacLCWatchEntry?, progress: MacLCWatchProgress?) -> String {
        if let text = entry?.resumeTarget?.detailText, !text.isEmpty {
            return text
        }
        var remaining = progress?.remaining ?? 0
        if remaining <= 0, let progress, progress.duration > 0, progress.position > 0 {
            remaining = progress.duration - progress.position
        }
        guard remaining > 0 else { return localize("Resume") }
        let minutes = Int((remaining / 60).rounded(.up))
        guard minutes >= 60 else { return String(format: localize("%ld min left"), minutes) }
        return minutes % 60 > 0 ? String(format: localize("%ld h %ld min left"), minutes / 60, minutes % 60)
            : String(format: localize("%ld h left"), minutes / 60)
    }

    private func video(for target: MacLCWatchResumeTarget) -> MacLCAddonVideo? {
        meta?.videos.first {
            $0.identifier == target.videoIdentifier || ($0.season == target.season && $0.episode == target.episode)
        }
    }

    /// The first episode of the lowest numbered season.
    private func firstPlayableEpisode() -> MacLCAddonVideo? {
        (meta?.videos ?? []).filter { $0.season >= 1 }.min { ($0.season, $0.episode) < ($1.season, $1.episode) }
    }

    // MARK: Actions

    /// Resume, Play Again, Play, or a show's episode to resume or play next.
    func playPressed() {
        let library = MacLCWatchLibrary.shared
        let playback = MacLCWatchPlayback.shared
        let entry = library.entry(forTitle: item.identifier)
        if !isSeries {
            let progress = library.progress(forTitle: item.identifier, video: nil)
            if progress?.canResume == true || entry?.resumeTarget?.kind == .resume {
                if let saved = progress ?? entry?.resumeTarget?.progress, playback.resumeProgress(saved, item: item) {
                    return
                }
                showStreamPicker(nil)
            } else if progress?.isWatched == true || entry?.isWatched == true {
                playFromStart()
            } else {
                showStreamPicker(nil)
            }
            return
        }
        if let target = entry?.resumeTarget, let video = video(for: target) {
            if target.kind == .resume,
               let saved = target.progress ?? library.progress(forTitle: item.identifier, video: video.identifier),
               playback.resumeProgress(saved, item: item) {
                return
            }
            showStreamPicker(video)
            return
        }
        showStreamPicker(firstPlayableEpisode())
    }

    /// Start Over and Play Again: the saved address from the start, else the
    /// stream picker.
    func playFromStart() {
        let progress = MacLCWatchLibrary.shared.progress(forTitle: item.identifier, video: nil)
        guard let progress, let address = progress.streamMRL, !address.isEmpty else {
            showStreamPicker(nil)
            return
        }
        MacLCWatchPlayback.shared.playMRL(address, streamLabel: progress.streamLabel, item: item, videoIdentifier: nil,
                                          season: 0, episode: 0, episodeName: nil, startPosition: 0)
    }

    /// An episode: resumes where it stopped, else the stream picker.
    func activate(_ video: MacLCAddonVideo) {
        if let progress = MacLCWatchLibrary.shared.progress(forTitle: item.identifier, video: video.identifier),
           progress.canResume, MacLCWatchPlayback.shared.resumeProgress(progress, item: item) {
            return
        }
        showStreamPicker(video)
    }

    func playTrailer() {
        guard let trailer, !trailerLoading else { return }
        trailerLoading = true
        MacLCWatchPlayTrailer(trailer, name, window()) { [weak self] in
            self?.trailerLoading = false
        }
    }

    func toggleFavorite() {
        MacLCWatchLibrary.shared.setFavorite(!MacLCWatchLibrary.shared.isFavorite(item.identifier), for: item)
        updatePlayState()
    }

    /// "Choose a Version", the sheet, for the title or an episode.
    private func showStreamPicker(_ video: MacLCAddonVideo?) {
        guard let window = window() else { return }
        let picker = MacLCStreamPickerController(item: item, video: video)
        self.picker = picker
        picker.completionHandler = { [weak self, weak picker] _ in
            if let self, self.picker === picker {
                self.picker = nil
            }
        }
        picker.beginSheetModal(for: window)
    }

    /// The carousel's Play: the picker once the page shows and the meta answered.
    private func playIfAsked() {
        guard showStreams, appeared, metaAnswered else { return }
        showStreams = false
        playPressed()
    }

    func open(_ item: MacLCAddonItem, showStreams: Bool) {
        section?.showDetail(for: item, showStreams: showStreams)
    }
}

// MARK: - Page

private nonisolated struct DetailMetrics: Equatable {
    var height: CGFloat = 720
}

/// One vertical scroll: the header (under the toolbar), then a show's
/// episodes, About and More Like This.
struct WatchDetailPage: View {
    let model: WatchDetailModel

    @State private var metrics = DetailMetrics()
    @FocusState private var focus: WatchFocus?

    /// 75 % of the page's height, 420 to 720 pt.
    private var headerHeight: CGFloat { min(720, max(420, (metrics.height * 0.75).rounded())) }

    var body: some View {
        ZStack {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    WatchDetailHeader(model: model, height: headerHeight)
                    if model.isSeries {
                        episodes
                            .padding(.top, sectionSpacing)
                    }
                    about
                        .padding(.top, sectionSpacing)
                        .padding(.horizontal, sideInset)
                    if !model.similar.isEmpty {
                        similar
                    }
                }
                .padding(.bottom, 48)
            }
            .scrollIndicators(.never)
            // The picture goes under the toolbar, as on the Apple TV app.
            .ignoresSafeArea(.container, edges: .top)
            .onScrollPhaseChange { _, phase in model.scrolling.setPage(phase.isScrolling) }
            .onMoveCommand { direction in
                // Along the episodes or More Like This; Tab goes between them.
                guard let current = focus else { return }
                let count = current.row == "episodes" ? model.episodes.count : model.similar.count
                if direction == .left, current.index > 0 {
                    focus = WatchFocus(row: current.row, index: current.index - 1)
                } else if direction == .right, current.index + 1 < count {
                    focus = WatchFocus(row: current.row, index: current.index + 1)
                }
            }
        }
        // The whole height, toolbar included, as AppKit's view bounds.
        .onGeometryChange(for: DetailMetrics.self) { proxy in
            DetailMetrics(height: proxy.size.height + proxy.safeAreaInsets.top)
        } action: { metrics = $0 }
    }

    /// The season pop-up over the season's episodes; a failed meta: "Can't
    /// load episodes" and Try Again.
    @ViewBuilder private var episodes: some View {
        if model.episodesFailed {
            HStack(spacing: 12) {
                Text(model.localize("Can't load episodes"))
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Button(model.localize("Try Again")) { model.loadMeta() }
            }
            .frame(minHeight: 60)
            .padding(.horizontal, sideInset)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Picker(model.localize("Season"),
                       selection: Binding(get: { model.season }, set: { @MainActor in model.selectSeason($0) })) {
                    ForEach(model.seasons, id: \.self) { season in
                        Text(model.seasonTitle(season)).tag(season)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .font(.headline)
                .fixedSize()
                .padding(.leading, sideInset)
                // Placeholders until the meta answers, then a new shelf with
                // the episodes, one per season, each starting at its first.
                let videos = model.episodes
                let count = videos.isEmpty && !model.metaAnswered ? 4 : videos.count
                WatchShelf(id: "episodes", itemWidth: EpisodeCard.size.width, spacing: itemSpacing,
                           scrolling: model.scrolling) { _, _ in
                    EmptyView()
                } cells: { reveal in
                    ForEach(0..<count, id: \.self) { index in
                        let video = index < videos.count ? videos[index] : nil
                        EpisodeCard(video: video, marks: video.map { model.marks(for: $0) }, model: model,
                                    onFocus: { reveal(index) })
                            .watchCell(WatchFocus(row: "episodes", index: index), focus: $focus,
                                       enabled: video != nil) {
                                if let video { model.activate(video) }
                            }
                    }
                }
                .id(model.metaAnswered ? "season \(model.season)" : "loading")
                // 12 pt under the pop-up, 36 under the cards (headroom included).
                .padding(.top, 12)
                .padding(.bottom, sectionSpacing - hoverHeadroom)
            }
        }
    }

    /// The description in full, then Genres, Released, Runtime and Rating in
    /// two columns.
    private var about: some View {
        let runtime = model.runtime.flatMap { $0.isEmpty ? nil : MacLCFormatRuntime($0) }
        return VStack(alignment: .leading, spacing: 0) {
            Text(model.localize("About"))
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            if !model.descriptionText.isEmpty {
                Text(model.descriptionText)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 12)
            }
            HStack(alignment: .top, spacing: 40) {
                VStack(alignment: .leading, spacing: 12) {
                    fact("Genres", model.genres.isEmpty ? nil : model.genres.joined(separator: ", "))
                    fact("Released", model.releaseInfo)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 12) {
                    fact("Runtime", runtime)
                    fact("Rating", model.ratingText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, 16)
        }
    }

    private func fact(_ key: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(model.localize(key))
                .foregroundStyle(.secondary)
            Text(value.flatMap { $0.isEmpty ? nil : $0 } ?? "—")
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }

    /// A poster shelf; a poster opens its page on the section.
    private var similar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(model.localize("More Like This"))
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
                .padding(.leading, sideInset)
                .padding(.top, sectionSpacing)
            // 12 pt under the title, the headroom being the shelf's own.
            WatchShelf(id: "similar", itemWidth: posterSize.width, spacing: itemSpacing,
                       scrolling: model.scrolling) { _, _ in
                EmptyView()
            } cells: { reveal in
                ForEach(Array(model.similar.enumerated()), id: \.offset) { index, item in
                    PosterCell(item: item, rank: 0, width: posterSize.width, model: model,
                               onFocus: { reveal(index) })
                        .watchCell(WatchFocus(row: "similar", index: index), focus: $focus) {
                            model.open(item, showStreams: false)
                        }
                }
            }
        }
    }
}

// MARK: - Header

/// The picture (aspect fill, extended under the sidebar) with the carousel's
/// scrims; bottom-leading, 40 pt in, at most 560 wide: logo or name, facts,
/// description with "More", details, the resume bar, the buttons;
/// bottom-trailing, at most 320 wide, the credits.
private struct WatchDetailHeader: View {
    let model: WatchDetailModel
    let height: CGFloat

    @State private var background = PosterArtwork()
    @State private var logo = PosterArtwork()
    @State private var shownHeight: CGFloat = 0
    @State private var fullHeight: CGFloat = 0
    @State private var showsMore = false
    @Environment(\.displayScale) private var displayScale

    /// Decoded once, for the screen's width and the tallest header: the
    /// header's own size is not known yet when the page opens.
    private static var pictureSize: CGSize {
        CGSize(width: NSScreen.main?.frame.width ?? 1728, height: 720)
    }
    private static let logoSize = CGSize(width: 360, height: 120)

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            picture
            WatchPictureScrims()
            HStack(alignment: .bottom, spacing: 24) {
                leading
                Spacer(minLength: 0)
                credits
            }
            .padding(sideInset)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .onAppear { loadPictures() }
        .onChange(of: model.backgroundURL) { loadPictures() }
        .onChange(of: model.logoURL) { loadPictures() }
        .onDisappear {
            background.stop()
            logo.stop()
        }
    }

    private func loadPictures() {
        background.show(model.backgroundURL, size: Self.pictureSize, scale: displayScale)
        logo.show(model.logoURL, size: Self.logoSize, scale: displayScale)
    }

    /// The colour takes the header's size; the picture, larger, overlays it
    /// and is cropped (a flexible frame round it would grow to the picture).
    private var picture: some View {
        Color(nsColor: .quaternarySystemFill)
            .opacity(background.image == nil ? 1 : 0)
            .overlay {
                if let image = background.image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
            }
            .clipped()
            // NSBackgroundExtensionView's SwiftUI counterpart.
            .backgroundExtensionEffect()
            .accessibilityHidden(true)
    }

    private var leading: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if let image = logo.image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 360, maxHeight: 120, alignment: .leading)
                        .accessibilityLabel(model.name)
                } else {
                    Text(model.name)
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)
                        .lineLimit(2)
                }
            }
            .accessibilityAddTraits(.isHeader)
            facts
                .padding(.top, 6)
            description
                .padding(.top, 12)
            if !model.detailsLine.isEmpty {
                Text(model.detailsLine)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.top, 12)
            }
            if let fraction = model.play.fraction {
                WatchProgressBar(fraction: fraction)
                    .frame(width: 200)
                    .padding(.top, 8)
            }
            buttons
                .padding(.top, 16)
        }
        .frame(maxWidth: 560, alignment: .leading)
    }

    /// The facts line and the "Watched" pill, then the time left.
    private var facts: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if !model.factsLine.isEmpty {
                    Text(model.factsLine)
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.85))
                }
                if model.play.watched {
                    WatchedPill(title: model.localize("Watched"))
                }
            }
            if let text = model.play.resumeText {
                Text(text)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
    }

    /// Four lines; "More" when they cut it, opening the whole text in a popover.
    private var description: some View {
        let text = model.descriptionText
        return VStack(alignment: .leading, spacing: 2) {
            Text(text)
                .font(.body)
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(4)
                .frame(maxWidth: 560, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { shownHeight = $0 }
                .background(alignment: .topLeading) {
                    Text(text)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                        .hidden()
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fullHeight = $0 }
                }
            if !text.isEmpty && fullHeight > shownHeight + 1 {
                Button(model.localize("More")) { showsMore = true }
                    .buttonStyle(.plain)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.75))
                    .help(model.localize("Show Full Description"))
                    .accessibilityLabel(model.localize("More description"))
                    .popover(isPresented: $showsMore, arrowEdge: .top) {
                        ScrollView {
                            Text(text)
                                .font(.body)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(16)
                        .frame(width: 380, height: 240)
                    }
            }
        }
    }

    /// Play (prominent), Start Over, Trailer, the favorite and the "…" menu,
    /// glass, 12 apart.
    private var buttons: some View {
        let favoriteLabel = model.localize(model.favorite ? "Remove from Favorites" : "Add to Favorites")
        return HStack(spacing: 12) {
            Button(action: model.playPressed) {
                Label(model.play.title, systemImage: model.play.symbol)
            }
            .buttonStyle(.glassProminent)
            .help(model.play.title)
            if model.play.startOver {
                Button(action: model.playFromStart) {
                    Label(model.localize("Start Over"), systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.glass)
                .help(model.localize("Start Over"))
            }
            if model.trailer != nil {
                Button(action: model.playTrailer) {
                    Label(model.localize("Trailer"), systemImage: "film")
                }
                .buttonStyle(.glass)
                .disabled(model.trailerLoading)
                .help(model.localize("Play Trailer"))
                .accessibilityLabel(model.localize("Play Trailer"))
            }
            Button(action: model.toggleFavorite) {
                Label(favoriteLabel, systemImage: model.favorite ? "heart.fill" : "heart")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(model.favorite ? Color.accentColor : Color.primary)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .help(favoriteLabel)
            // A glass Menu draws nothing on macOS 27: a button pops the menu.
            Button(action: model.showActionsMenu) {
                Label(model.localize("More Options"), systemImage: "ellipsis")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .help(model.localize("More Options"))
        }
        .controlSize(.large)
    }

    /// "Starring <3 names>", "Director <name>": white 75 % labels, white names.
    @ViewBuilder private var credits: some View {
        let cast = model.cast
        let directors = model.directors
        if !cast.isEmpty || !directors.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                if !cast.isEmpty {
                    credit(model.localize("Starring "), cast.joined(separator: ", "))
                }
                if !directors.isEmpty {
                    credit(model.localize(directors.count > 1 ? "Directors " : "Director "),
                           directors.joined(separator: ", "))
                }
            }
            // The lines keep their width; the block ends 40 pt from the edge.
            .frame(maxWidth: 320, alignment: .trailing)
        }
    }

    private func credit(_ label: String, _ names: String) -> some View {
        var text = AttributedString(label)
        text.swiftUI.foregroundColor = .white.opacity(0.75)
        var namesText = AttributedString(names)
        namesText.swiftUI.foregroundColor = .white
        return Text(text + namesText)
            .font(.subheadline)
            .lineLimit(3)
    }
}

/// "Watched" with a checkmark, white on black 35 %, a 24 pt capsule.
private struct WatchedPill: View {
    let title: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .frame(width: 14, height: 14)
            Text(title)
                .font(.callout)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(.black.opacity(0.35), in: Capsule())
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }
}

// MARK: - Episode

/// MacLCWatchEpisodeItem: the 16:9 still (corner radius 8, "tv" while
/// loading, 1 pt border; the progress bar, the watched badge and a dimmed
/// still from the history), "EPISODE 3" (footnote, semibold, +0.6 tracking,
/// secondary), the title (body, semibold, 1 line), the overview
/// (subheadline, secondary, 2 lines) and the air date (footnote, tertiary;
/// "Upcoming"). Hover, focus and activation as the poster's; placeholders
/// (no video) while the meta loads.
struct EpisodeCard: View {
    /// nil: a placeholder.
    let video: MacLCAddonVideo?
    let marks: TitleMarks?
    let model: WatchDetailModel
    var onFocus: () -> Void = {}

    @State private var artwork = PosterArtwork()
    @State private var hovered = false
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let size = CGSize(width: 300, height: (300.0 * 9 / 16).rounded(.up))

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    var body: some View {
        let lifted = hovered && !model.scrolling.isScrolling
        // Spaces keep the lines' height when a text is missing.
        VStack(alignment: .leading, spacing: 0) {
            still(lifted: lifted)
            Text(eyebrow.isEmpty ? " " : eyebrow)
                .font(.footnote.weight(.semibold))
                .kerning(0.6)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.top, 8)
            Text(title.isEmpty ? " " : title)
                .font(.body.weight(.semibold))
                .lineLimit(1)
                .padding(.top, 2)
            // Two lines always, as AppKit's fixed cell height.
            Text(overview)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2, reservesSpace: true)
                .padding(.top, 4)
            Text(airDate.isEmpty ? " " : airDate)
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .padding(.top, 4)
        }
        .frame(width: Self.size.width, alignment: .leading)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .pointerStyle(.link)
        .onTapGesture {
            if let video { model.activate(video) }
        }
        .onAppear { artwork.show(video?.thumbnailURL, size: Self.size, scale: displayScale) }
        .onChange(of: video?.thumbnailURL) { _, url in artwork.show(url, size: Self.size, scale: displayScale) }
        .onDisappear { artwork.stop() }
        .contextMenu {
            if let video {
                WatchActionsMenu(item: model.item, video: video)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([eyebrow, title, overview, airDate].filter { !$0.isEmpty }.joined(separator: ", "))
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            if let video { model.activate(video) }
        }
        // Placeholders are not buttons yet.
        .accessibilityHidden(video == nil)
    }

    private func still(lifted: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        let watched = marks?.watched ?? false
        let fraction = marks?.fraction ?? 0
        return ZStack {
            shape.fill(Color(nsColor: .quaternarySystemFill))
            Group {
                if let image = artwork.image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: Self.size.width, height: Self.size.height)
                } else {
                    Image(systemName: "tv")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(.tertiary)
                }
            }
            .opacity(watched ? 0.6 : 1)
            if !watched, fraction > 0, fraction < 1 {
                WatchProgressBar(fraction: fraction)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
            if watched {
                WatchedBadge()
                    .padding(8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
        .overlay(FocusRing(cornerRadius: 8, onFocus: onFocus))
        .scaleEffect(lifted && !reduceMotion ? 1.05 : 1)
        .shadow(color: .black.opacity(lifted ? 0.3 : 0), radius: lifted ? 14 : 0, y: lifted ? 6 : 0)
        .animation(liftAnimation(hovered, lifted, reduceMotion: reduceMotion), value: lifted)
    }

    /// "EPISODE 3", else "SEASON 2".
    private var eyebrow: String {
        guard let video else { return "" }
        if video.episode > 0 {
            return String(format: model.localize("EPISODE %ld"), video.episode).uppercased()
        }
        if video.season > 0 {
            return String(format: model.localize("SEASON %ld"), video.season).uppercased()
        }
        return ""
    }

    private var title: String {
        guard let video else { return "" }
        if let name = video.name, !name.isEmpty { return name }
        return video.episode > 0 ? String(format: model.localize("Episode %ld"), video.episode) : ""
    }

    private var overview: String { video?.overview ?? "" }

    private var airDate: String {
        guard let released = video?.released else { return "" }
        return released > Date() ? model.localize("Upcoming") : Self.dateFormatter.string(from: released)
    }

    /// "Watched" or "In progress, 40 %".
    private var accessibilityValue: String {
        guard let marks else { return "" }
        if marks.watched {
            return model.localize("Watched")
        }
        if marks.fraction > 0, marks.fraction < 1 {
            return String(format: model.localize("In progress, %ld %%"), Int((marks.fraction * 100).rounded()))
        }
        return ""
    }
}
