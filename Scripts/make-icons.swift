#!/usr/bin/env swift
//
//  make-icons.swift
//  PlainX Editor
//
//  Generates the macOS app icon renditions for Assets.xcassets/AppIcon.appiconset
//  from the authoritative master logo (App/Resources/Branding/PlainX-Logo.png).
//
//  The master artwork is preserved byte-for-byte. This script only adjusts the
//  render pipeline: it trims the flat black canvas around the squircle emblem,
//  then composes each rendition on a transparent canvas using the standard
//  macOS icon-grid margin so the icon matches native macOS sizing.
//
//  Usage:  swift Scripts/make-icons.swift [path/to/logo.png]
//

import AppKit
import CoreGraphics
import Foundation

let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

let masterURL: URL = {
    if CommandLine.arguments.count > 1 {
        return URL(fileURLWithPath: CommandLine.arguments[1])
    }
    return repoRoot.appendingPathComponent("PlainX/Resources/Branding/PlainX-Logo.png")
}()

let outputDir = repoRoot.appendingPathComponent("PlainX/Assets.xcassets/AppIcon.appiconset")

guard let sourceImage = NSImage(contentsOf: masterURL),
      let sourceRep = sourceImage.representations.first as? NSBitmapImageRep ?? NSBitmapImageRep(data: sourceImage.tiffRepresentation!) else {
    FileHandle.standardError.write(Data("error: cannot read master logo at \(masterURL.path)\n".utf8))
    exit(1)
}

guard let cgSource = sourceRep.cgImage else {
    FileHandle.standardError.write(Data("error: cannot create CGImage from master logo\n".utf8))
    exit(1)
}

// MARK: - Detect the emblem bounds (non-black content) on the flat canvas.

func emblemBounds(of image: CGImage) -> CGRect {
    let width = image.width
    let height = image.height
    let sampleWidth = min(width, 512)
    let sampleHeight = min(height, 512)

    guard let context = CGContext(data: nil,
                                  width: sampleWidth,
                                  height: sampleHeight,
                                  bitsPerComponent: 8,
                                  bytesPerRow: sampleWidth * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        return CGRect(x: 0, y: 0, width: width, height: height)
    }

    context.interpolationQuality = .medium
    context.draw(image, in: CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight))

    guard let data = context.data else {
        return CGRect(x: 0, y: 0, width: width, height: height)
    }

    let pixels = data.bindMemory(to: UInt8.self, capacity: sampleWidth * sampleHeight * 4)
    // The emblem's squircle has a bright rim highlight against a flat black
    // canvas. Detecting bright pixels (rim + letters, both inside the rim)
    // gives the true squircle bounds; a low threshold would pick up the dark
    // glow around the artwork and keep the canvas.
    let threshold: Int = 96

    var minX = sampleWidth
    var minY = sampleHeight
    var maxX = 0
    var maxY = 0

    for y in 0..<sampleHeight {
        for x in 0..<sampleWidth {
            let offset = (y * sampleWidth + x) * 4
            let r = Int(pixels[offset])
            let g = Int(pixels[offset + 1])
            let b = Int(pixels[offset + 2])
            let luminance = (r * 299 + g * 587 + b * 114) / 1000
            if luminance > threshold {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
    }

    guard minX <= maxX, minY <= maxY else {
        return CGRect(x: 0, y: 0, width: width, height: height)
    }

    let scaleX = CGFloat(width) / CGFloat(sampleWidth)
    let scaleY = CGFloat(height) / CGFloat(sampleHeight)

    // CGContext origin is bottom-left; convert to CGImage (top-left origin) space.
    let boxInSample = CGRect(x: minX, y: minY,
                             width: maxX - minX + 1,
                             height: maxY - minY + 1)
    let boxInTopLeft = CGRect(x: boxInSample.minX * scaleX,
                              y: CGFloat(sampleHeight - 1 - maxY) * scaleY,
                              width: boxInSample.width * scaleX,
                              height: boxInSample.height * scaleY)

    // Square it up around the center so the emblem keeps its proportions.
    let side = max(boxInTopLeft.width, boxInTopLeft.height)
    let centerX = boxInTopLeft.midX
    let centerY = boxInTopLeft.midY
    // Tiny outward margin so the rim highlight is never clipped.
    let margin = side * 0.005
    return CGRect(x: centerX - side / 2 - margin,
                  y: centerY - side / 2 - margin,
                  width: side + margin * 2,
                  height: side + margin * 2)
}

let bounds = emblemBounds(of: cgSource)
guard let emblem = cgSource.cropping(to: bounds) else {
    FileHandle.standardError.write(Data("error: cannot crop emblem\n".utf8))
    exit(1)
}

// The master artwork draws its squircle on a flat black canvas, so a square
// crop keeps black wedges in the four corners. Measure the squircle's corner
// radius from the artwork itself and mask the crop to that rounded shape so
// the canvas becomes transparent.
func measuredCornerRadiusFraction(of image: CGImage) -> CGFloat {
    let sample = 256
    guard let context = CGContext(data: nil, width: sample, height: sample,
                                  bitsPerComponent: 8, bytesPerRow: sample * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        return 0.2237
    }
    context.interpolationQuality = .medium
    context.draw(image, in: CGRect(x: 0, y: 0, width: sample, height: sample))
    guard let data = context.data else { return 0.2237 }
    let pixels = data.bindMemory(to: UInt8.self, capacity: sample * sample * 4)
    // Scan a row slightly below the top edge for the first non-black pixel.
    let y = 2
    for x in 0..<sample {
        let offset = (y * sample + x) * 4
        let luminance = (Int(pixels[offset]) * 299 + Int(pixels[offset + 1]) * 587 + Int(pixels[offset + 2]) * 114) / 1000
        if luminance > 40 {
            return min(0.3, max(0.12, CGFloat(x) / CGFloat(sample)))
        }
    }
    return 0.2237
}

// Slightly overshoot the measured radius: the artwork uses a continuous
// (squircle) corner, and a circular mask with the exact straight-edge radius
// would leave thin black wedges at the extreme corners.
let cornerRadiusFraction = min(0.30, measuredCornerRadiusFraction(of: emblem) * 1.18)

// MARK: - Compose renditions.

let contentFraction: CGFloat = 0.815 // macOS icon grid: emblem occupies ~81.5% of canvas

struct Rendition {
    let fileName: String
    let pixelSize: Int
}

let renditions: [Rendition] = [
    .init(fileName: "icon_16x16.png", pixelSize: 16),
    .init(fileName: "icon_16x16@2x.png", pixelSize: 32),
    .init(fileName: "icon_32x32.png", pixelSize: 32),
    .init(fileName: "icon_32x32@2x.png", pixelSize: 64),
    .init(fileName: "icon_128x128.png", pixelSize: 128),
    .init(fileName: "icon_128x128@2x.png", pixelSize: 256),
    .init(fileName: "icon_256x256.png", pixelSize: 256),
    .init(fileName: "icon_256x256@2x.png", pixelSize: 512),
    .init(fileName: "icon_512x512.png", pixelSize: 512),
    .init(fileName: "icon_512x512@2x.png", pixelSize: 1024)
]

try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

let side64 = Float(bounds.width)

for rendition in renditions {
    let size = rendition.pixelSize
    guard let context = CGContext(data: nil,
                                  width: size,
                                  height: size,
                                  bitsPerComponent: 8,
                                  bytesPerRow: size * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        FileHandle.standardError.write(Data("error: cannot create context for \(rendition.fileName)\n".utf8))
        exit(1)
    }

    context.interpolationQuality = .high
    let contentSide = CGFloat(size) * contentFraction
    let inset = (CGFloat(size) - contentSide) / 2
    let rect = CGRect(x: inset, y: inset, width: contentSide, height: contentSide)
    // Mask to the artwork's squircle so the black canvas corners become
    // transparent instead of showing as wedges behind the icon. The emblem is
    // drawn ~1.5% larger than the mask so the dark border ring that surrounds
    // the artwork's rim is clipped away as well.
    let radius = contentSide * cornerRadiusFraction
    let overscan = contentSide * 0.015
    let drawRect = rect.insetBy(dx: -overscan, dy: -overscan)
    context.saveGState()
    context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    context.clip()
    context.draw(emblem, in: drawRect)
    context.restoreGState()

    guard let output = context.makeImage() else {
        FileHandle.standardError.write(Data("error: cannot render \(rendition.fileName)\n".utf8))
        exit(1)
    }

    let rep = NSBitmapImageRep(cgImage: output)
    guard let png = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write(Data("error: cannot encode \(rendition.fileName)\n".utf8))
        exit(1)
    }

    let destination = outputDir.appendingPathComponent(rendition.fileName)
    try png.write(to: destination)
}

// Keep the asset catalog manifest in sync so the app icon actually compiles.
let contentsJSON = """
{
  "images" : [
    { "idiom" : "mac", "scale" : "1x", "size" : "16x16", "filename" : "icon_16x16.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "16x16", "filename" : "icon_16x16@2x.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "32x32", "filename" : "icon_32x32.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "32x32", "filename" : "icon_32x32@2x.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "128x128", "filename" : "icon_128x128.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "128x128", "filename" : "icon_128x128@2x.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "256x256", "filename" : "icon_256x256.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "256x256", "filename" : "icon_256x256@2x.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "512x512", "filename" : "icon_512x512.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "512x512", "filename" : "icon_512x512@2x.png" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
"""
try contentsJSON.write(to: outputDir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

fputs("PlainX icons generated: emblem side \(side64)px, content fraction \(contentFraction), corner radius fraction \(cornerRadiusFraction)\n", stderr)
