// MakeIcon.swift — renders the MacLC application icon at every size the
// .iconset needs. Original artwork: a graphite squircle carrying a warm play
// mark with a highlight bloom, which is the app's one visual claim (HDR) said
// in the only language an icon has at 16 points.
//
//   swiftc -O MakeIcon.swift -o makeicon && ./makeicon <output-dir>

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// MARK: - Geometry

/// Apple's app-icon grid: the shape fills 824 of a 1024 canvas, leaving the
/// rest as the breathing room the Dock and Finder expect.
let shapeRatio: CGFloat = 824.0 / 1024.0
/// Superellipse exponent. 5 is close to the continuous corner macOS uses; a
/// plain rounded rectangle reads as visibly "wrong" beside system icons.
let squircleExponent: CGFloat = 5.0

func squirclePath(center: CGPoint, halfSide: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let steps = 720
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        // Superellipse in parametric form.
        let x = pow(abs(c), 2.0 / squircleExponent) * halfSide * (c < 0 ? -1 : 1)
        let y = pow(abs(s), 2.0 / squircleExponent) * halfSide * (s < 0 ? -1 : 1)
        let p = CGPoint(x: center.x + x, y: center.y + y)
        if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
    }
    path.closeSubpath()
    return path
}

/// A play triangle with softened corners, nudged right so it looks centred —
/// a geometrically centred triangle always reads as sitting too far left.
func playPath(center: CGPoint, radius r: CGFloat, corner: CGFloat) -> CGPath {
    let cx = center.x + r * 0.10
    let pts = [
        CGPoint(x: cx + r,                    y: center.y),
        CGPoint(x: cx - r * 0.5, y: center.y + r * 0.866),
        CGPoint(x: cx - r * 0.5, y: center.y - r * 0.866),
    ]
    let path = CGMutablePath()
    path.move(to: midpoint(pts[2], pts[0]))
    for i in 0..<3 {
        path.addArc(tangent1End: pts[i], tangent2End: pts[(i + 1) % 3], radius: corner)
    }
    path.closeSubpath()
    return path
}

func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
    CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
}

// MARK: - Colour

func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: a)
}

let space = CGColorSpaceCreateDeviceRGB()

func gradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locations)!
}

// MARK: - Drawing

func drawIcon(size: CGFloat) -> CGImage {
    let px = Int(size)
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8,
                        bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high

    let s = size / 1024.0              // everything below is authored at 1024
    let center = CGPoint(x: size / 2, y: size / 2)
    let half = size * shapeRatio / 2
    let shape = squirclePath(center: center, halfSide: half)

    // Contact shadow, so the icon sits on the Dock rather than floating on it.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10 * s), blur: 22 * s,
                  color: rgb(0, 0, 0, 0.34))
    ctx.addPath(shape)
    ctx.setFillColor(rgb(20, 22, 26))
    ctx.fillPath()
    ctx.restoreGState()

    // Graphite body. Kept deliberately dark and neutral: the warm mark and its
    // bloom are the only saturated things in the icon, which is what makes them
    // read as bright rather than merely orange.
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    ctx.drawLinearGradient(
        gradient([rgb(58, 63, 72), rgb(34, 37, 43), rgb(20, 22, 26)], [0, 0.55, 1]),
        start: CGPoint(x: 0, y: size), end: CGPoint(x: 0, y: 0), options: [])

    // Highlight bloom behind the mark.
    let bloomCenter = CGPoint(x: center.x + 30 * s, y: center.y)
    ctx.drawRadialGradient(
        gradient([rgb(255, 138, 43, 0.42), rgb(255, 110, 30, 0.14), rgb(255, 110, 30, 0)],
                 [0, 0.45, 1]),
        startCenter: bloomCenter, startRadius: 0,
        endCenter: bloomCenter, endRadius: 330 * s, options: [])

    // Top rim light — the cue that says "lit from above" in every system icon.
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.setLineWidth(3 * s)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    ctx.drawLinearGradient(
        gradient([rgb(255, 255, 255, 0.30), rgb(255, 255, 255, 0.04), rgb(255, 255, 255, 0)],
                 [0, 0.35, 1]),
        start: CGPoint(x: 0, y: size), end: CGPoint(x: 0, y: size * 0.45), options: [])
    ctx.restoreGState()

    // The play mark.
    let mark = playPath(center: center, radius: 232 * s, corner: 44 * s)
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 46 * s, color: rgb(255, 120, 40, 0.55))
    ctx.addPath(mark)
    ctx.setFillColor(rgb(255, 122, 32))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(mark)
    ctx.clip()
    ctx.drawLinearGradient(
        gradient([rgb(255, 209, 138), rgb(255, 138, 43), rgb(240, 84, 12)], [0, 0.5, 1]),
        start: CGPoint(x: 0, y: size * 0.78), end: CGPoint(x: 0, y: size * 0.22), options: [])

    // Specular edge along the upper-left face: the one detail that says the
    // mark is emitting light rather than painted on.
    ctx.setLineWidth(9 * s)
    ctx.setStrokeColor(rgb(255, 244, 226, 0.75))
    ctx.move(to: CGPoint(x: center.x - 92 * s, y: center.y + 188 * s))
    ctx.addLine(to: CGPoint(x: center.x + 236 * s, y: center.y + 8 * s))
    ctx.strokePath()
    ctx.restoreGState()

    ctx.restoreGState()
    return ctx.makeImage()!
}

// MARK: - Menu bar mark

/// The status item is a template image: macOS throws the colour away and tints
/// the alpha channel to match the menu bar. So the mark has to survive as pure
/// silhouette - a solid squircle with the play triangle knocked out of it,
/// which stays unmistakable at 18 points where an outline would not.
func writeStatusBarPDF(to path: String) {
    let w: CGFloat = 18, h: CGFloat = 18
    var box = CGRect(x: 0, y: 0, width: w, height: h)
    guard let dest = CGDataConsumer(url: URL(fileURLWithPath: path) as CFURL),
          let ctx = CGContext(consumer: dest, mediaBox: &box, nil) else {
        FileHandle.standardError.write("cannot write \(path)\n".data(using: .utf8)!)
        exit(1)
    }
    ctx.beginPDFPage(nil)
    let center = CGPoint(x: w / 2, y: h / 2)

    let body = CGMutablePath()
    body.addPath(squirclePath(center: center, halfSide: w / 2 - 0.5))
    // Reversed winding knocks the triangle out of the solid shape.
    let cut = playPath(center: center, radius: 4.6, corner: 1.1)
    body.addPath(cut)

    ctx.addPath(body)
    ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
    ctx.fillPath(using: .evenOdd)

    ctx.endPDFPage()
    ctx.closePDF()
    print("wrote \(path)")
}

// MARK: - Output

if CommandLine.arguments.count > 2, CommandLine.arguments[1] == "--statusbar" {
    writeStatusBarPDF(to: CommandLine.arguments[2])
    exit(0)
}

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let sizes: [(String, CGFloat)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

for (name, size) in sizes {
    let image = drawIcon(size: size)
    let url = URL(fileURLWithPath: "\(outDir)/\(name).png")
    guard let dest = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        FileHandle.standardError.write("cannot write \(url.path)\n".data(using: .utf8)!)
        exit(1)
    }
    CGImageDestinationAddImage(dest, image, nil)
    if !CGImageDestinationFinalize(dest) {
        FileHandle.standardError.write("finalize failed for \(url.path)\n".data(using: .utf8)!)
        exit(1)
    }
    print("wrote \(name).png (\(Int(size))px)")
}

// Regenerate the shipped icon with:
//
//   swiftc -O maclc_app_icon.swift -o makeicon
//   mkdir MacLC.iconset && ./makeicon MacLC.iconset
//   iconutil -c icns MacLC.iconset -o \
//       ../../../../modules/gui/macosx/Resources/App-Icons/MacLC.icns
//   ./makeicon --statusbar \
//       ../../../../modules/gui/macosx/Resources/Button-Icons/MacLCStatusBarIcon.pdf
