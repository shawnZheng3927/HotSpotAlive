import AppKit

// Package the bitmap artwork inside a clean, native rounded icon silhouette.
// Clipping during rendering avoids background pixels and matte fringes at every size.
guard CommandLine.arguments.count == 3,
      let artwork = NSImage(contentsOfFile: CommandLine.arguments[1]) else {
    fatalError("Usage: make-icon.swift artwork.png output.iconset")
}
let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func render(size: Int, filename: String) throws {
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                       bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                       isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0,
                                       bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        fatalError("Cannot create icon bitmap")
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    let side = CGFloat(size)
    let bounds = NSRect(x: 0, y: 0, width: side, height: side)
    context.cgContext.clear(bounds)
    let silhouette = NSBezierPath(roundedRect: bounds.insetBy(dx: side * 0.063, dy: side * 0.063),
                                  xRadius: side * 0.23, yRadius: side * 0.23)
    silhouette.addClip()
    NSColor.white.setFill()
    silhouette.fill()
    artwork.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Cannot encode icon bitmap")
    }
    try png.write(to: output.appendingPathComponent(filename))
}

for size in [16, 32, 128, 256, 512] {
    try render(size: size, filename: "icon_\(size)x\(size).png")
    try render(size: size * 2, filename: "icon_\(size)x\(size)@2x.png")
}
