/*****************************************************************************
 * MacLCWatchHero.swift: the Watch carousel in SwiftUI
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

/* MacLCWatchHeroView (MacLCWatchComponents.h/.m) in SwiftUI, for the
 * SwiftUI Watch page: one title at a time filling the top, picture and text
 * changing together once the new picture is loaded, a 0.5 s cross-fade every
 * 8 s (text and picture together: AppKit fades the text out in 0.2 s and in
 * in 0.3 s), dots, chevrons on hover, parallax and stretch with the page
 * scroll.
 * The scroll effects go through visualEffect, so a scroll frame evaluates no
 * body; the advance waits while anything scrolls (no SwiftUI animation on
 * the frames of a scroll). */

import AppKit
import Observation
import SwiftUI

/// The carousel's titles and the one shown, with its pictures.
@Observable
final class WatchHeroModel {
    /// At most 8 are shown.
    private(set) var items: [MacLCAddonItem] = []
    /// One eyebrow per item, same order; missing ones show nothing.
    private(set) var eyebrows: [String] = []
    private(set) var index = 0
    /// The shown title's pictures, loaded before it shows.
    private(set) var background: NSImage?
    private(set) var logo: NSImage?
    var hovered = false

    @ObservationIgnored var play: (MacLCAddonItem) -> Void = { _ in }
    @ObservationIgnored var details: (MacLCAddonItem) -> Void = { _ in }
    /// Its window visible and on screen, the page showing (not search or an
    /// empty state): otherwise the carousel does not advance.
    @ObservationIgnored var isVisible: () -> Bool = { false }
    @ObservationIgnored var isScrolling: () -> Bool = { false }

    @ObservationIgnored private var size = CGSize(width: 800, height: 480)
    @ObservationIgnored private var loadedSize = CGSize.zero
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var requests: [MacLCWatchImageRequest] = []
    @ObservationIgnored private var loadSerial = 0

    private static let logoSize = CGSize(width: 360, height: 120)

    isolated deinit {
        timer?.invalidate()
        requests.forEach { $0.cancel() }
    }

    var current: MacLCAddonItem? { items.indices.contains(index) ? items[index] : nil }

    /// 62 % of the page's height, 360 to 620 pt (MacLCWatchHeroView
    /// heightForAvailableHeight:).
    static func height(forAvailableHeight height: CGFloat) -> CGFloat {
        max(360, min(620, (height * 0.62).rounded()))
    }

    func set(items newItems: [MacLCAddonItem], eyebrows newEyebrows: [String]) {
        if newEyebrows != eyebrows {
            eyebrows = newEyebrows
        }
        let capped = Array(newItems.prefix(8))
        guard capped != items else { return }
        items = capped
        show(0, animated: false)
        startTimer()
    }

    /// The carousel's size: pictures are decoded at it. A much larger one
    /// loads the shown picture again.
    func resize(_ newSize: CGSize) {
        size = newSize
        guard !items.isEmpty,
              newSize.width > loadedSize.width + 64 || newSize.height > loadedSize.height + 64 else { return }
        show(index, animated: false)
    }

    func previous() {
        guard !items.isEmpty else { return }
        show((index - 1 + items.count) % items.count, animated: true)
        startTimer()
    }

    func next() {
        guard !items.isEmpty else { return }
        show((index + 1) % items.count, animated: true)
        startTimer()
    }

    func select(_ newIndex: Int) {
        show(newIndex, animated: true)
        startTimer()
    }

    func playCurrent() {
        if let current { play(current) }
    }

    func showDetails() {
        if let current { details(current) }
    }

    /// Loads the title's picture and logo, then shows it with them.
    private func show(_ newIndex: Int, animated: Bool) {
        guard items.indices.contains(newIndex) else { return }
        requests.forEach { $0.cancel() }
        requests.removeAll()
        loadSerial += 1
        let serial = loadSerial
        let item = items[newIndex]
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        let pictureSize = size
        var picture: NSImage?
        var logoImage: NSImage?
        var pending = 0
        func finish() {
            guard serial == loadSerial, pending == 0 else { return }
            loadedSize = pictureSize
            apply(newIndex, picture: picture, logo: logoImage, animated: animated)
        }
        // A cached picture comes back at once and its completion never runs.
        func load(_ url: URL?, size: CGSize, store: @escaping (NSImage?) -> Void) {
            guard let url else { return }
            pending += 1
            var request: MacLCWatchImageRequest?
            let cached = MacLCWatchImageCache.shared.image(for: url, pointSize: size, scale: scale, request: &request) {
                image in
                store(image)
                pending -= 1
                finish()
            }
            if let request { requests.append(request) }
            if let cached {
                store(cached)
                pending -= 1
            }
        }
        load(item.backgroundURL ?? item.posterURL, size: pictureSize) { picture = $0 }
        load(item.logoURL, size: Self.logoSize) { logoImage = $0 }
        finish()
    }

    private func apply(_ newIndex: Int, picture: NSImage?, logo newLogo: NSImage?, animated: Bool) {
        let animate = animated && background != nil && !isScrolling()
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        var transaction = Transaction(animation: animate ? .easeInOut(duration: 0.5) : nil)
        transaction.disablesAnimations = !animate
        withTransaction(transaction) {
            index = newIndex
            background = picture
            logo = newLogo
        }
    }

    /// Every 8 s, unless there is one title, under Reduce Motion (the dots
    /// and chevrons still work), while hovered, hidden or scrolling.
    func startTimer() {
        timer?.invalidate()
        timer = nil
        guard items.count > 1, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.advance() }
        }
    }

    private func advance() {
        guard items.count > 1, !hovered, !isScrolling(), isVisible(),
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        show((index + 1) % items.count, animated: true)
    }
}

/// Keeps what is drawn above the carousel's bottom edge only: the picture
/// lags behind while scrolling and must not cover the shelves below.
private nonisolated struct BottomEdgeClip: Shape {
    func path(in rect: CGRect) -> Path {
        Path(CGRect(x: rect.minX - 10_000, y: rect.minY - 10_000, width: rect.width + 20_000,
                    height: rect.height + 10_000))
    }
}

/// The scrims of the carousel and the title page's header. Top: window
/// background 55 % → 0 over 88 pt under the toolbar; leading: black 45 % → 0
/// over 55 % of the width; bottom: black 0 → 70 % over the lower 60 %. White
/// text reads on any picture.
struct WatchPictureScrims: View {
    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [.black.opacity(0.45), .clear], startPoint: .leading,
                           endPoint: UnitPoint(x: 0.55, y: 0.5))
            LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: UnitPoint(x: 0.5, y: 0.4),
                           endPoint: .bottom)
            LinearGradient(colors: [Color(nsColor: .windowBackgroundColor).opacity(0.55),
                                    Color(nsColor: .windowBackgroundColor).opacity(0)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 88)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The view (MacLCWatchHeroView's contract): the picture aspect-filled, the
/// scrims, bottom-leading the eyebrow, logo or title, facts, description and
/// Play / Details; the dots bottom-centre, the chevrons on hover.
struct WatchHeroView: View {
    let hero: WatchHeroModel
    let height: CGFloat
    let localize: (String) -> String
    let scrolling: ScrollActivity

    @State private var width: CGFloat = 800
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let item = hero.current
        ZStack(alignment: .bottomLeading) {
            picture
            WatchPictureScrims()
            if let item {
                text(item)
                    .id(hero.index)
                    .transition(.opacity)
            }
            dots
            if hero.hovered && !scrolling.isScrolling {
                chevrons
                    .transition(.opacity.animation(.easeInOut(duration: 0.15)))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .contentShape(Rectangle())
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .onHover { hero.hovered = $0 }
        .focusable()
        .focusEffectDisabled()
        .onMoveCommand { direction in
            switch direction {
            case .left: hero.previous()
            case .right: hero.next()
            default: break
            }
        }
        .onKeyPress(keys: [.return, .space]) { _ in
            hero.playCurrent()
            return .handled
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityText(item))
    }

    /// Scrolled up, the picture moves at half speed; rubber-banding, it grows
    /// from its bottom edge to fill the gap. Not under Reduce Motion.
    private var picture: some View {
        let height = self.height
        let still = reduceMotion
        // The colour takes the carousel's size; the aspect-filled picture,
        // larger, overlays it and is cropped to it (a flexible frame round the
        // picture would grow to the picture and push the carousel's content).
        return Color(nsColor: .quaternarySystemFill)
            .opacity(hero.background == nil ? 1 : 0)
            .overlay {
                if let image = hero.background {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .id(ObjectIdentifier(image))
                        .transition(.opacity)
                }
            }
            .clipped()
            .visualEffect { content, proxy in
            let offset = still ? 0 : -proxy.frame(in: .scrollView(axis: .vertical)).minY
            return content
                .offset(y: offset > 0 ? offset * 0.5 : 0)
                .scaleEffect(offset < 0 && height > 0 ? 1 + -offset / height : 1, anchor: .bottom)
        }
        .clipShape(BottomEdgeClip())
        .accessibilityHidden(true)
    }

    /// 40 pt from the leading and bottom edges, at most 460 wide; fades out
    /// over the first 60 % of the carousel's height as the page scrolls.
    private func text(_ item: MacLCAddonItem) -> some View {
        let eyebrow = hero.eyebrows.indices.contains(hero.index) ? hero.eyebrows[hero.index] : ""
        let fadeLimit = height * 0.6
        let still = reduceMotion
        return VStack(alignment: .leading, spacing: 4) {
            if !eyebrow.isEmpty {
                Text(eyebrow.uppercased())
                    .font(.footnote.weight(.semibold))
                    .kerning(0.6)
                    .foregroundStyle(.white.opacity(0.75))
            }
            Group {
                if let logo = hero.logo {
                    Image(nsImage: logo)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 360, maxHeight: 120, alignment: .leading)
                        .accessibilityLabel(item.name)
                } else {
                    Text(item.name)
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)
                        .lineLimit(2)
                }
            }
            .padding(.bottom, 2)
            Text(MacLCWatchFactsLine(item.type, item.genres, item.releaseInfo, item.imdbRating))
                .font(.callout)
                .foregroundStyle(.white.opacity(0.85))
            Text(item.itemDescription ?? "")
                .font(.body)
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(3)
                .padding(.bottom, 12)
            HStack(spacing: 12) {
                Button(action: hero.playCurrent) {
                    Label(localize("Play"), systemImage: "play.fill")
                }
                .buttonStyle(.glassProminent)
                .help(localize("Play"))
                Button(action: hero.showDetails) {
                    Label(localize("Details"), systemImage: "info.circle")
                }
                .buttonStyle(.glass)
                .help(localize("Details"))
            }
            .controlSize(.large)
        }
        .frame(maxWidth: 460, alignment: .leading)
        .padding(.leading, 40)
        .padding(.bottom, 40)
        .visualEffect { content, proxy in
            let offset = still ? 0 : -proxy.frame(in: .scrollView(axis: .vertical)).minY
            return content.opacity(offset > 0 && fadeLimit > 0 ? max(0, 1 - offset / fadeLimit) : 1)
        }
    }

    /// One 8 pt dot per title (the current one a 20 pt capsule), 20 pt hit
    /// targets; centred, moved right rather than over the text.
    private var dots: some View {
        let count = hero.items.count
        let dotsWidth = CGFloat(max(0, count - 1)) * 20 + 28
        let centred = (width - dotsWidth) / 2
        let x = min(max(centred, 40 + 460 + 24), width - 40 - dotsWidth)
        return HStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { index in
                let active = index == hero.index
                Button {
                    hero.select(index)
                } label: {
                    Capsule()
                        .fill(.white.opacity(active ? 1 : 0.4))
                        .frame(width: active ? 20 : 8, height: 8)
                        .frame(width: active ? 28 : 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .accessibilityLabel(String(format: localize("Show %@"), hero.items[index].name))
            }
        }
        .offset(x: max(0, x))
        .padding(.bottom, 36)
        .opacity(count > 0 ? 1 : 0)
    }

    /// 28 pt glass circles at mid-height, 16 pt from the edges.
    private var chevrons: some View {
        HStack {
            chevron("chevron.left", label: localize("Previous"), action: hero.previous)
            Spacer()
            chevron("chevron.right", label: localize("Next"), action: hero.next)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func chevron(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: Circle())
        .help(label)
        .accessibilityLabel(label)
    }

    /// "Featured, <title>, <facts>, <description>, page 2 of 6".
    private func accessibilityText(_ item: MacLCAddonItem?) -> String {
        guard let item else { return localize("Featured") }
        return String(format: localize("Featured, %@, %@, %@, page %ld of %lu"), item.name,
                      MacLCWatchFactsLine(item.type, item.genres, item.releaseInfo, item.imdbRating),
                      item.itemDescription ?? "", hero.index + 1, hero.items.count)
    }
}
