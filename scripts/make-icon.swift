// Generates Support/AppIcon.icns from Support/AppIcon.png.
// Run from the repository root: swift scripts/make-icon.swift
import Foundation
import ImageIO
import UniformTypeIdentifiers

let support = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Support", isDirectory: true)
let sourceURL = support.appendingPathComponent("AppIcon.png")
guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil) else {
    fatalError("Could not read Support/AppIcon.png")
}

func appendHeader(_ type: String, payloadLength: Int, to data: inout Data) {
    data.append(contentsOf: type.utf8)
    var length = UInt32(payloadLength + 8).bigEndian
    withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
}

// ICNS uses distinct types for 1× and 2× images even at the same pixel size.
let representations: [(type: String, pixels: Int)] = [
    ("icp4", 16), ("ic11", 32),
    ("icp5", 32), ("ic12", 64),
    ("ic07", 128), ("ic13", 256),
    ("ic08", 256), ("ic14", 512),
    ("ic09", 512), ("ic10", 1024),
]

var contents = Data()
for representation in representations {
    let pixels = representation.pixels
    let options = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceThumbnailMaxPixelSize: pixels,
    ] as CFDictionary
    let png = NSMutableData()
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options),
          image.width == pixels, image.height == pixels,
          let destination = CGImageDestinationCreateWithData(
              png, UTType.png.identifier as CFString, 1, nil
          ) else {
        fatalError("Could not generate the \(pixels) × \(pixels) icon")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        fatalError("Could not encode the \(pixels) × \(pixels) icon")
    }
    appendHeader(representation.type, payloadLength: png.length, to: &contents)
    contents.append(png as Data)
}

var icon = Data()
appendHeader("icns", payloadLength: contents.count, to: &icon)
icon.append(contents)
try icon.write(to: support.appendingPathComponent("AppIcon.icns"), options: .atomic)
