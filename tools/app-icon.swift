import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Compile the square brand artwork onto a transparent macOS icon canvas.
let artworkURL = URL(fileURLWithPath: CommandLine.arguments[1])
let iconset = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
guard let source = CGImageSourceCreateWithURL(artworkURL as CFURL, nil),
      let artwork = CGImageSourceCreateImageAtIndex(source, 0, nil),
      let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
    fatalError("Could not read the Sisu icon artwork.")
}
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        guard let context = CGContext(data: nil, width: pixels, height: pixels,
            bitsPerComponent: 8, bytesPerRow: pixels * 4, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            fatalError("Could not create the icon canvas.")
        }
        let ratio = CGFloat(pixels) / 1024
        context.scaleBy(x: ratio, y: ratio)
        context.interpolationQuality = .high
        let face = CGRect(x: 100, y: 100, width: 824, height: 824)
        context.addPath(CGPath(roundedRect: face, cornerWidth: 184, cornerHeight: 184, transform: nil))
        context.clip()
        context.draw(artwork, in: face)
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        let url = iconset.appendingPathComponent(name)
        guard let output = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil),
              let image = context.makeImage() else { fatalError("Could not create \(name).") }
        CGImageDestinationAddImage(output, image, nil)
        guard CGImageDestinationFinalize(output) else { fatalError("Could not write \(name).") }
    }
}
