// swiftc maclc_pref_icons.swift -o /tmp/maclc_pref_icons && /tmp/maclc_pref_icons modules/gui/macosx/Resources/Pref-Icons
import AppKit
// Renders the basic-preferences toolbar icons as MacLC-orange SF Symbols,
// replacing the traffic cones they used to be.
let outDir = CommandLine.arguments[1]
let icons = ["VLCInterfaceCone": "macwindow", "VLCAudioCone": "speaker.wave.2.fill",
             "VLCVideoCone": "film", "VLCSubtitleCone": "captions.bubble.fill",
             "VLCInputCone": "square.and.arrow.down.on.square", "VLCHotkeysCone": "keyboard"]
let orange = NSColor(calibratedRed: 1.0, green: 0.56, blue: 0.16, alpha: 1)
for (name, symbol) in icons {
    let px = 64
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let config = NSImage.SymbolConfiguration(pointSize: 40, weight: .regular)
        .applying(NSImage.SymbolConfiguration(paletteColors: [orange]))
    let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)!.withSymbolConfiguration(config)!
    let s = img.size
    let scale = min(52 / s.width, 52 / s.height)
    let w = s.width * scale, h = s.height * scale
    img.draw(in: NSRect(x: (64 - w) / 2, y: (64 - h) / 2, width: w, height: h))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(outDir)/\(name).png"))
}
