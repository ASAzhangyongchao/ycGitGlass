#!/usr/bin/env swift
// 用 Resources/LogoSource.jpg 生成应用图标与页头品牌图。
// 裁掉右下角水印区域（取左上 900x900 正方形），做 macOS 风格圆角，不联网、不依赖第三方库。
import AppKit
import Foundation

let fm = FileManager.default
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let sourceURL = root.appendingPathComponent("Resources/LogoSource.jpg")
let iconset = root.appendingPathComponent("Resources/AppIcon.iconset", isDirectory: true)
let iconURL = root.appendingPathComponent("Resources/AppIcon.icns")
let headerURL = root.appendingPathComponent("Resources/BrandHeader.png")
let fallbackScript = root.appendingPathComponent("scripts/make-icon.swift")

func roundedLogo(from source: NSImage, dimension: CGFloat) -> NSImage {
    let output = NSImage(size: NSSize(width: dimension, height: dimension))
    output.lockFocus()
    defer { output.unlockFocus() }

    let inset = dimension * 0.08
    let body = NSRect(x: inset, y: inset,
                      width: dimension - inset * 2, height: dimension - inset * 2)
    let shape = NSBezierPath(roundedRect: body,
                             xRadius: dimension * 0.22, yRadius: dimension * 0.22)

    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    // 源图 1024x1024。NSImage 坐标原点在左下：
    // 取左上方向 (40, 0) ~ (940, 900) 的区域，正好避开右下角水印。
    let crop = NSRect(x: 40, y: 1024 - 900, width: 900, height: 900)
    source.draw(in: body, from: crop, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()

    // 细白描边，玻璃质感
    shape.lineWidth = max(1.5, dimension * 0.006)
    NSColor.white.withAlphaComponent(0.55).setStroke()
    shape.stroke()
    return output
}

func writePNG(_ image: NSImage, to url: URL) throws {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "GitGlassBrand", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "PNG 生成失败"])
    }
    try data.write(to: url)
}

// 无源图时退回程序化图标，保证 clone 后也能构建
guard fm.fileExists(atPath: sourceURL.path),
      let source = NSImage(contentsOf: sourceURL) else {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
    task.arguments = [fallbackScript.path]
    try task.run()
    task.waitUntilExit()
    if let fallback = NSImage(contentsOf: iconURL) {
        try? writePNG(roundedLogo(from: fallback, dimension: 256), to: headerURL)
    }
    print("未找到 LogoSource.jpg，已使用程序化图标兜底")
    exit(0)
}

try? fm.removeItem(at: iconset)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)

let entries: [(String, CGFloat)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]
for (name, dimension) in entries {
    try writePNG(roundedLogo(from: source, dimension: dimension),
                 to: iconset.appendingPathComponent(name))
}

// 页头用的品牌小图
try writePNG(roundedLogo(from: source, dimension: 256), to: headerURL)

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", iconURL.path]
try task.run()
task.waitUntilExit()
guard task.terminationStatus == 0 else {
    throw NSError(domain: "GitGlassBrand", code: 2,
                  userInfo: [NSLocalizedDescriptionKey: "iconutil 失败"])
}

let iconSize = (try? fm.attributesOfItem(atPath: iconURL.path)[.size] as? NSNumber)??.intValue ?? 0
print("品牌资源已生成：AppIcon.icns（\(iconSize) bytes）、BrandHeader.png")
