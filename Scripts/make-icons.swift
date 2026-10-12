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
    let threshold: Int = 26 // out of 255; the emblem is a dark gradient but clearly above flat black

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
    return CGRect(x: centerX - side / 2, y: centerY - side / 2, width: side, height: side)
}

let bounds = emblemBounds(of: cgSource)
guard let emblem = cgSource.cropping(to: bounds) else {
    FileHandle.standardError.write(Data("error: cannot crop emblem\n".utf8))
    exit(1)
}

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
    context.draw(emblem, in: CGRect(x: inset, y: inset, width: contentSide, height: contentSide))

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

fputs("PlainX icons generated: emblem side \(side64)px, content fraction \(contentFraction)\n", stderr)
