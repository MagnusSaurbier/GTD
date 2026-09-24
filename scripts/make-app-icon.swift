#!/usr/bin/env swift
// Regenerates App/Assets.xcassets/AppIcon.appiconset from Artwork/logo.png.
// Run: swift scripts/make-app-icon.swift
//
// The source mark is a transparent-background landscape glyph, so each icon is
// composed here: an opaque background (iOS is masked by the system and must not
// be transparent) with the mark centred on it. macOS icons are not masked by the
// system, so the rounded-square shape is drawn into the canvas on Apple's grid
// (824pt artwork inside a 1024pt canvas).

import AppKit

let repoRoot = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : FileManager.default.currentDirectoryPath)
let sourceURL = repoRoot.appendingPathComponent("Artwork/logo.png")
let iconSetURL = repoRoot.appendingPathComponent("App/Assets.xcassets/AppIcon.appiconset")

// Background the mark sits on. The mark itself is blue on transparency.
let background = CGColor(red: 1, green: 1, blue: 1, alpha: 1)

/// Fraction of the artwork square the mark's longest edge spans.
let markScale: CGFloat = 0.80
/// macOS artwork occupies 824/1024 of the canvas; iOS art is full-bleed.
let macArtworkRatio: CGFloat = 824.0 / 1024.0
/// macOS corner radius is ~22.5% of the artwork square's side.
let macCornerRatio: CGFloat = 185.4 / 824.0

guard let src = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
      let mark = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
    fatalError("Could not read \(sourceURL.path)")
}

/// Tight bounding box of the mark's non-transparent pixels, in image coordinates.
func contentBounds(of image: CGImage) -> CGRect {
    let w = image.width, h = image.height
    var buf = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8,
                        bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    var minX = w, minY = h, maxX = 0, maxY = 0
    for y in 0..<h {
        for x in 0..<w where buf[(y * w + x) * 4 + 3] > 20 {
            if x < minX { minX = x }; if x > maxX { maxX = x }
            if y < minY { minY = y }; if y > maxY { maxY = y }
        }
    }
    return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
}

let bounds = contentBounds(of: mark)
let cropped = mark.cropping(to: bounds)!

func render(pixels: Int, rounded: Bool) -> Data {
    let size = CGFloat(pixels)
    let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
                        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high

    let artwork: CGRect
    if rounded {
        let side = (size * macArtworkRatio).rounded()
        artwork = CGRect(x: ((size - side) / 2).rounded(), y: ((size - side) / 2).rounded(),
                         width: side, height: side)
        let path = CGPath(roundedRect: artwork,
                          cornerWidth: side * macCornerRatio,
                          cornerHeight: side * macCornerRatio, transform: nil)
        ctx.addPath(path)
        ctx.clip()
    } else {
        artwork = CGRect(x: 0, y: 0, width: size, height: size)
    }
    ctx.setFillColor(background)
    ctx.fill(artwork)

    // Fit the mark inside the artwork square, preserving its aspect ratio.
    let target = artwork.width * markScale
    let scale = min(target / bounds.width, target / bounds.height)
    let drawn = CGSize(width: bounds.width * scale, height: bounds.height * scale)
    ctx.draw(cropped, in: CGRect(x: artwork.midX - drawn.width / 2,
                                 y: artwork.midY - drawn.height / 2,
                                 width: drawn.width, height: drawn.height))

    let out = ctx.makeImage()!
    let data = NSMutableData()
    let dest = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, out, nil)
    CGImageDestinationFinalize(dest)
    return data as Data
}

struct Entry { let size: Int; let scale: Int }
let macEntries = [Entry(size: 16, scale: 1), Entry(size: 16, scale: 2),
                  Entry(size: 32, scale: 1), Entry(size: 32, scale: 2),
                  Entry(size: 128, scale: 1), Entry(size: 128, scale: 2),
                  Entry(size: 256, scale: 1), Entry(size: 256, scale: 2),
                  Entry(size: 512, scale: 1), Entry(size: 512, scale: 2)]

var images: [[String: String]] = []

let iosName = "icon-ios-1024.png"
try render(pixels: 1024, rounded: false)
    .write(to: iconSetURL.appendingPathComponent(iosName))
images.append(["idiom": "universal", "platform": "ios", "size": "1024x1024", "filename": iosName])

for entry in macEntries {
    let pixels = entry.size * entry.scale
    let suffix = entry.scale == 1 ? "" : "@\(entry.scale)x"
    let name = "icon-mac-\(entry.size)x\(entry.size)\(suffix).png"
    try render(pixels: pixels, rounded: true)
        .write(to: iconSetURL.appendingPathComponent(name))
    images.append(["idiom": "mac", "scale": "\(entry.scale)x",
                   "size": "\(entry.size)x\(entry.size)", "filename": name])
}

let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let json = try JSONSerialization.data(withJSONObject: contents,
                                      options: [.prettyPrinted, .sortedKeys])
try json.write(to: iconSetURL.appendingPathComponent("Contents.json"))

print("Wrote \(images.count) icons to \(iconSetURL.path)")
