// Writes a JPEG with an ISO HDR gain map: SDR screens show base.png, HDR screens show hdr.raw.
import CoreImage
import Foundation
import ImageIO

let a = CommandLine.arguments
let (w, h) = (Int(a[3])!, Int(a[4])!)
// A float base (".raw") means both renditions are extended-linear Display P3 (MacLC captures);
// otherwise the base is an 8-bit sRGB picture and the HDR rendition extended-linear sRGB.
let p3 = a[1].hasSuffix(".raw")
let linear = CGColorSpace(name: p3 ? CGColorSpace.extendedLinearDisplayP3 : CGColorSpace.extendedLinearSRGB)!
func floats(_ path: String) -> CIImage {
    CIImage(bitmapData: try! Data(contentsOf: URL(fileURLWithPath: path)), bytesPerRow: w * 16,
            size: CGSize(width: w, height: h), format: .RGBAf, colorSpace: linear)
}
let hdr = floats(a[2])
let sdr = p3 ? floats(a[1]) : CIImage(contentsOf: URL(fileURLWithPath: a[1]))!
let ctx = CIContext()
let out = URL(fileURLWithPath: a[5])
try! ctx.writeJPEGRepresentation(of: sdr, to: out, colorSpace: CGColorSpace(name: p3 ? CGColorSpace.displayP3 : CGColorSpace.sRGB)!,
                                 options: [.hdrImage: hdr,
                                           CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): 0.86])
let src = CGImageSourceCreateWithURL(out as CFURL, nil)!
let iso = CGImageSourceCopyAuxiliaryDataInfoAtIndex(src, 0, kCGImageAuxiliaryDataTypeISOGainMap) != nil
let apple = CGImageSourceCopyAuxiliaryDataInfoAtIndex(src, 0, kCGImageAuxiliaryDataTypeHDRGainMap) != nil
print("ISO gain map:", iso, "Apple gain map:", apple)
