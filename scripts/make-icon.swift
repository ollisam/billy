// Builds Billy's app icon and writes Resources/Billy.icns.
// Run from the repo root: swift scripts/make-icon.swift [preview.png]
import AppKit

// Billy is the gradient sphere (Resources/Billy-sphere.png, from scripts/cut-sphere.py) on a black tile.
let billy = NSImage(contentsOfFile: "Resources/Billy-sphere.png")!
/// The sphere's width as a share of the tile's.
let billyScale: CGFloat = 0.64
let tileGray: CGFloat = 0 // black
let tileColor = CGColor(srgbRed: tileGray / 255, green: tileGray / 255, blue: tileGray / 255, alpha: 1)

/// A dark tile on the macOS icon grid (824/1024, centred, standard drop shadow) with Billy centred on it.
func draw(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    context.imageInterpolation = .high
    NSGraphicsContext.current = context
    let ctx = context.cgContext

    let inset = s * 100 / 1024
    let tile = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let radius = tile.width * 0.2265 // macOS icon corner rounding
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03, color: CGColor(gray: 0, alpha: 0.45))
    ctx.addPath(CGPath(roundedRect: tile, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.setFillColor(tileColor)
    ctx.fillPath()
    ctx.restoreGState()

    let w = tile.width * billyScale
    let h = w * billy.size.height / billy.size.width
    billy.draw(in: CGRect(x: tile.midX - w / 2, y: tile.midY - h / 2, width: w, height: h),
               from: .zero, operation: .sourceOver, fraction: 1)

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Billy.iconset")
try? fm.removeItem(at: iconset)
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! draw(base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try! draw(base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", "Resources/Billy.icns"]
try! p.run()
p.waitUntilExit()
if CommandLine.arguments.count > 1 {
    try! draw(1024).write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
}
print(p.terminationStatus == 0 ? "Wrote Resources/Billy.icns" : "iconutil failed")
