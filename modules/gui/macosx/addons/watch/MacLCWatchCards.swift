/*****************************************************************************
 * MacLCWatchCards.swift: the services bar and the Watch cards in SwiftUI
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

/* SwiftUI versions of MacLCWatchServiceBar, MacLCWatchContinueItem,
 * MacLCWatchCollectionCard and MacLCWatchGenreTile (their contracts are in
 * MacLCWatchDiscoveryViews.h and MacLCWatchLibraryViews.h; sizes and
 * transforms follow the .m files). Content layer: no glass except the resume
 * card's play glyph, shown on hover only. Hover motion waits until nothing
 * scrolls (ScrollActivity) and never runs under Reduce Motion. */

import AppKit
import SwiftUI

// MARK: - Services bar

/// "All", one capsule per active service, "Choose Services…" and the info
/// button; with no service, "Add Your Streaming Services…". Selecting one
/// re-scopes the page. Scrolls sideways when it overflows; left and right
/// arrows move the selection when it has the focus.
struct WatchServicesBar: View {
    let model: WatchBrowseModel

    var body: some View {
        let services = model.services
        let selected = model.selectedServiceCode
        let codes: [String?] = [nil] + services.map(\.code)
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                if services.isEmpty {
                    ServiceCapsule(title: model.localize("Add Your Streaming Services…"), symbol: "plus.circle",
                                   selected: false, model: model) { model.chooseServices() }
                } else {
                    HStack(spacing: 8) {
                        ServiceCapsule(title: model.localize("All"), symbol: nil, selected: selected == nil,
                                       model: model) { model.selectService(nil) }
                        ForEach(services, id: \.code) { service in
                            ServiceCapsule(title: service.name, symbol: nil, selected: selected == service.code,
                                           model: model) { model.selectService(service.code) }
                        }
                    }
                    // VoiceOver: a radio group, as AppKit's bar.
                    .accessibilityRepresentation {
                        Picker(model.localize("Streaming service"),
                               selection: Binding<String?>(get: { selected },
                                                           set: { @MainActor code in model.selectService(code) })) {
                            Text(model.localize("All")).tag(String?.none)
                            ForEach(services, id: \.code) { service in
                                Text(service.name).tag(Optional(service.code))
                            }
                        }
                        .pickerStyle(.radioGroup)
                    }
                    ServiceCapsule(title: model.localize("Choose Services…"), symbol: "slider.horizontal.3",
                                   selected: false, model: model) { model.chooseServices() }
                }
                ExplainerInfoButton(topic: .services)
                    .frame(width: 22, height: 22)
            }
            .frame(height: 44)
        }
        .scrollIndicators(.never)
        .frame(height: 44)
        .focusable(!services.isEmpty)
        // The selected capsule shows where the arrows are; no ring round the bar.
        .focusEffectDisabled()
        .onMoveCommand { direction in
            guard let index = codes.firstIndex(of: selected) else { return }
            // Wraps around at both ends, as AppKit's bar.
            switch direction {
            case .left: model.selectService(codes[index > 0 ? index - 1 : codes.count - 1])
            case .right: model.selectService(codes[(index + 1) % codes.count])
            default: break
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(model.localize("Streaming service"))
    }
}

/// 28 pt high, 14 pt padding (16 here), callout medium; selected: accent fill, white
/// text; others: quaternary fill (tertiary on hover), label colour. The fill
/// cross-fades in 0.25 s when the selection moves.
private struct ServiceCapsule: View {
    let title: String
    let symbol: String?
    let selected: Bool
    let model: WatchBrowseModel
    let action: () -> Void

    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let hot = hovered && !model.scrolling.isScrolling
        Button(action: action) {
            Group {
                if let symbol {
                    Label(title, systemImage: symbol)
                        .labelStyle(.titleAndIcon)
                } else {
                    Text(title)
                }
            }
            .font(.callout.weight(.medium))
            .foregroundStyle(selected ? Color.white : Color(nsColor: .labelColor))
            // 14 pt plus NSButton's own title margins (measured against AppKit).
            .padding(.horizontal, 16)
            .frame(height: 28)
            .background(Capsule().fill(selected ? Color.accentColor
                                       : Color(nsColor: hot ? .tertiarySystemFill : .quaternarySystemFill)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hovered = $0 }
        .pointerStyle(.link)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Continue Watching

/// MacLCWatchContinueItem: the 16:9 picture (background, else the poster),
/// a bottom scrim, the progress bar on its bottom edge; on hover a play
/// glyph in a glass circle and the "…" button (the actions menu); under it
/// the title and the resume text ("S1, E3 · 23 min left"). Hover: 4 %
/// larger with the posters' spring. Activation resumes.
struct ContinueCard: View {
    let entry: MacLCWatchEntry
    let model: WatchBrowseModel
    var onFocus: () -> Void = {}

    @State private var artwork = PosterArtwork()
    @State private var hovered = false
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let size = CGSize(width: 300, height: 300 * 9 / 16)

    var body: some View {
        let lifted = hovered && !model.scrolling.isScrolling
        VStack(alignment: .leading, spacing: 0) {
            picture(lifted: lifted)
            Text(entry.item.name)
                .font(.body.weight(.medium))
                .lineLimit(1)
                .padding(.top, 8)
            Text(entry.resumeTarget?.detailText ?? " ")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.top, 2)
        }
        .frame(width: Self.size.width, alignment: .leading)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .pointerStyle(.link)
        .onTapGesture { model.resume(entry) }
        .onAppear {
            artwork.show(entry.item.backgroundURL ?? entry.item.posterURL, size: Self.size, scale: displayScale)
        }
        .onChange(of: entry.item.backgroundURL ?? entry.item.posterURL) { _, url in
            artwork.show(url, size: Self.size, scale: displayScale)
        }
        .onDisappear { artwork.stop() }
        .contextMenu {
            WatchActionsMenu(item: entry.item,
                             details: (model.localize("Show Details"), { model.open(entry.item) }))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([entry.item.name, entry.resumeTarget?.detailText ?? ""]
            .filter { !$0.isEmpty }.joined(separator: ", "))
        .accessibilityValue(fraction > 0 && fraction < 1
            ? String(format: model.localize("In progress, %ld %%"), Int((fraction * 100).rounded())) : "")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.resume(entry) }
    }

    /// The resume point, when there is one to show.
    private var fraction: Double {
        guard let progress = entry.resumeTarget?.progress, progress.canResume else { return 0 }
        return progress.fraction
    }

    private func picture(lifted: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        let size = Self.size
        return ZStack {
            shape.fill(Color(nsColor: .quaternarySystemFill))
            if let image = artwork.image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size.width, height: size.height)
            } else {
                Image(systemName: "play.tv")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(.tertiary)
            }
            LinearGradient(colors: [.black.opacity(0), .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
                .frame(height: (size.height * 0.45).rounded(.up))
                .frame(maxHeight: .infinity, alignment: .bottom)
            if fraction > 0, fraction < 1 {
                WatchProgressBar(fraction: fraction)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
            if lifted {
                Image(systemName: "play.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .offset(x: 1)
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular, in: Circle())
                optionsButton
                    .padding(8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
        .overlay(FocusRing(cornerRadius: 8, onFocus: onFocus))
        .scaleEffect(lifted && !reduceMotion ? 1.04 : 1)
        .shadow(color: .black.opacity(lifted ? 0.3 : 0), radius: lifted ? 14 : 0, y: lifted ? 6 : 0)
        .animation(liftAnimation(hovered, lifted, reduceMotion: reduceMotion), value: lifted)
    }

    /// "…": the actions menu, as a right-click shows it.
    private var optionsButton: some View {
        Button {
            let menu = MacLCWatchActions.menu(for: entry.item, video: nil, inHistory: false)
            let details = ActionTarget { [model, entry] in model.open(entry.item) }
            let item = NSMenuItem(title: model.localize("Show Details"), action: #selector(ActionTarget.run(_:)),
                                  keyEquivalent: "")
            item.target = details
            item.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .regular))
            menu.addItem(.separator())
            menu.addItem(item)
            // Modal: returns once the menu closes, its action run.
            withExtendedLifetime(details) {
                _ = menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(.black.opacity(0.45)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(model.localize("More Options"))
        .accessibilityLabel(model.localize("More Options"))
    }
}

// MARK: - The Edit

/// MacLCWatchCollectionCard: 340 × 216, corner radius 12, the collection's
/// tint as a diagonal gradient over the window background, 1 pt border. The
/// text column (symbol, title, subtitle, count) on the leading side; up to 3
/// posters fanned on the trailing side, the middle one in front. Hover: the
/// fan opens and the middle poster rises. Activation pushes the collection.
struct CollectionCard: View {
    let collection: MacLCWatchCollection
    let model: WatchBrowseModel
    var onFocus: () -> Void = {}

    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let lifted = hovered && !model.scrolling.isScrolling
        let open = lifted && !reduceMotion
        let state = model.collectionState(collection)
        let tint = Color(nsColor: MacLCWatchColorNamed(collection.tintName))
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        ZStack(alignment: .topLeading) {
            shape.fill(Color(nsColor: .windowBackgroundColor))
            shape.fill(LinearGradient(colors: [tint.opacity(0.32), tint.opacity(0.12)],
                                      startPoint: .bottomLeading, endPoint: .topTrailing))
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: collection.symbolName)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 24, height: 24)
                Text(collection.title)
                    .font(.title2.bold())
                    .lineLimit(3)
                    .padding(.top, 10)
                Text(collection.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .padding(.top, 6)
                Spacer(minLength: 0)
                Text(countText)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(tint)
            }
            .frame(maxWidth: 144, maxHeight: .infinity, alignment: .topLeading)
            .padding(18)
            // Back to front: the first, the third, then the middle one.
            ForEach([0, 2, 1], id: \.self) { index in
                FanPoster(item: (state.items?.count ?? 0) > index ? state.items?[index] : nil)
                    .rotationEffect(.degrees(index == 0 ? (open ? 14 : 8) : index == 2 ? (open ? -14 : -8) : 0))
                    .offset(x: 246 - 41 + CGFloat(index - 1) * 36 + (open ? CGFloat(index - 1) * 8 : 0),
                            y: 216 - 18 - 123 - (open && index == 1 ? 6 : 0))
            }
        }
        .frame(width: 340, height: 216)
        .overlay(shape.strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
        .overlay(FocusRing(cornerRadius: 12, onFocus: onFocus))
        .contentShape(shape)
        .animation(liftAnimation(hovered, lifted, reduceMotion: reduceMotion, stiffness: 220, damping: 14),
                   value: lifted)
        .onHover { hovered = $0 }
        .pointerStyle(.link)
        .onTapGesture { model.open(collection) }
        .onAppear { model.resolve(collection) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(collection.title), \(collection.subtitle), \(countText)")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.open(collection) }
    }

    private var countText: String {
        collectionCountText(collection, localize: model.localize)
    }
}

/// "16 Films", "12 Shows", "14 Titles".
func collectionCountText(_ collection: MacLCWatchCollection, localize: (String) -> String) -> String {
    let format: String
    switch collection.mediaType {
    case "movie": format = "%lu Films"
    case "series": format = "%lu Shows"
    default: format = "%lu Titles"
    }
    return String(format: localize(format), collection.entries.count)
}

/// A poster of a fan: 82 × 123 on the card (110 × 165 in the collection
/// page's header), corner radius 6, a soft shadow; quaternary fill until its
/// collection resolves.
struct FanPoster: View {
    let item: MacLCAddonItem?
    var size = CGSize(width: 82, height: 123)
    var shadowRadius: CGFloat = 8
    var shadowY: CGFloat = 3

    @State private var artwork = PosterArtwork()
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        ZStack {
            shape.fill(Color(nsColor: .quaternarySystemFill))
            if let image = artwork.image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shape)
        .shadow(color: .black.opacity(0.25), radius: shadowRadius, y: shadowY)
        .onAppear { artwork.show(item?.posterURL, size: size, scale: displayScale) }
        .onChange(of: item?.posterURL) { _, url in artwork.show(url, size: size, scale: displayScale) }
        .onDisappear { artwork.stop() }
    }
}

// MARK: - Genre tile

/// MacLCWatchGenreTile: 196 × 110, corner radius 12, the genre's tint
/// darkening downwards, its symbol as a large watermark, the name bottom
/// leading (title3, bold, white); up to 2 posters of the genre peek from the
/// trailing edge. Hover: 3 % larger and the posters slide 8 pt in.
struct GenreTile: View {
    let genre: String
    let posters: [MacLCAddonItem]
    let model: WatchBrowseModel
    var onFocus: () -> Void = {}

    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let lifted = hovered && !model.scrolling.isScrolling
        let open = lifted && !reduceMotion
        let tint = MacLCWatchColorNamed(MacLCWatchDiscovery.tintName(forGenre: genre))
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [Color(nsColor: tint.blended(withFraction: 0.10, of: .black) ?? tint),
                                    Color(nsColor: tint.blended(withFraction: 0.50, of: .black) ?? tint)],
                           startPoint: .top, endPoint: .bottom)
            Image(systemName: MacLCWatchDiscovery.symbolName(forGenre: genre))
                .resizable()
                .scaledToFit()
                .fontWeight(.bold)
                .foregroundStyle(.white.opacity(0.18))
                .frame(width: 110, height: 110)
                .rotationEffect(.degrees(12), anchor: .bottomLeading)
                .offset(x: 196 - 110 + 16, y: 16)
            ForEach(Array(posters.prefix(2).enumerated()), id: \.offset) { index, item in
                PeekPoster(item: item)
                    .rotationEffect(.degrees(-10), anchor: .bottomLeading)
                    .offset(x: (index == 0 ? 196 - 50 : 196 - 32) + (open ? -8 : 0), y: index == 0 ? 10 : 2)
            }
            Text(genre)
                .font(.title3.bold())
                .foregroundStyle(.white)
                .lineLimit(2)
                .padding(14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .frame(width: 196, height: 110)
        .clipShape(shape)
        .overlay(FocusRing(cornerRadius: 12, onFocus: onFocus))
        .contentShape(shape)
        .scaleEffect(open ? 1.03 : 1)
        .animation(liftAnimation(hovered, lifted, reduceMotion: reduceMotion, stiffness: 220, damping: 14),
                   value: lifted)
        .onHover { hovered = $0 }
        .pointerStyle(.link)
        .onTapGesture { model.openGenre(genre) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(genre)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.openGenre(genre) }
    }
}

/// 60 × 90, corner radius 6, a 1 pt white border.
private struct PeekPoster: View {
    let item: MacLCAddonItem

    @State private var artwork = PosterArtwork()
    @Environment(\.displayScale) private var displayScale

    private static let size = CGSize(width: 60, height: 90)

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        Group {
            if let image = artwork.image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color.clear
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipShape(shape)
        .overlay(shape.strokeBorder(.white, lineWidth: 1))
        .onAppear { artwork.show(item.posterURL, size: Self.size, scale: displayScale) }
        .onChange(of: item.posterURL) { _, url in artwork.show(url, size: Self.size, scale: displayScale) }
        .onDisappear { artwork.stop() }
    }
}
