// Writes a JPEG with an ISO HDR gain map: SDR screens show base.png, HDR screens show hdr.raw.
import CoreImage
import Foundation
import ImageIO

let a = CommandLine.arguments
let (w, h) = (Int(a[3])!, Int(a[4])!)
let raw = try! Data(contentsOf: URL(fileURLWithPath: a[2]))
let linear = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
let hdr = CIImage(bitmapData: raw, bytesPerRow: w * 16, size: CGSize(width: w, height: h),
                  format: .RGBAf, colorSpace: linear)
let sdr = CIImage(contentsOf: URL(fileURLWithPath: a[1]))!
let ctx = CIContext()
let out = URL(fileURLWithPath: a[5])
try! ctx.writeJPEGRepresentation(of: sdr, to: out, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                                 options: [.hdrImage: hdr,
                                           CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): 0.86])
let src = CGImageSourceCreateWithURL(out as CFURL, nil)!
let iso = CGImageSourceCopyAuxiliaryDataInfoAtIndex(src, 0, kCGImageAuxiliaryDataTypeISOGainMap) != nil
let apple = CGImageSourceCopyAuxiliaryDataInfoAtIndex(src, 0, kCGImageAuxiliaryDataTypeHDRGainMap) != nil
print("ISO gain map:", iso, "Apple gain map:", apple)
