#!/usr/bin/env swift
// 生成本地应用图标：不依赖任何第三方库、不联网，纯 AppKit 绘制 + 系统 iconutil。
// 用法：swift scripts/make-icon.swift
import AppKit
import Foundation

let canvas: CGFloat = 1024
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let iconset = root.appendingPathComponent("Resources/AppIcon.iconset", isDirectory: true)
let iconURL = root.appendingPathComponent("Resources/AppIcon.icns")

func roundedPath(_ rect: NSRect, _ radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

func drawBaseImage() -> NSImage {
    let image = NSImage(size: NSSize(width: canvas, height: canvas))
    image.lockFocus()
    defer { image.unlockFocus() }

    // macOS 现代图标：四周留白 + 圆角矩形主体
    let inset: CGFloat = 96
    let body = NSRect(x: inset, y: inset, width: canvas - inset * 2, height: canvas - inset * 2)
    let shape = roundedPath(body, 190)

    NSGraphicsContext.saveGraphicsState()
    shape.addClip()

    let top = NSColor(calibratedRed: 0.27, green: 0.49, blue: 0.98, alpha: 1)
    let bottom = NSColor(calibratedRed: 0.58, green: 0.36, blue: 0.95, alpha: 1)
    NSGradient(starting: top, ending: bottom)?.draw(in: body, angle: -55)

    // 高光与柔光都用径向渐变，避免线性渐变的硬边
    let highlight = NSGradient(
        colors: [NSColor.white.withAlphaComponent(0.26), NSColor.white.withAlphaComponent(0.0)]
    )
    highlight?.draw(in: shape, relativeCenterPosition: NSPoint(x: 0.28, y: 0.86))

    let glow = NSGradient(
        colors: [NSColor(calibratedRed: 0.35, green: 0.90, blue: 0.80, alpha: 0.26),
                 NSColor(calibratedRed: 0.35, green: 0.90, blue: 0.80, alpha: 0.0)]
    )
    glow?.draw(in: shape, relativeCenterPosition: NSPoint(x: 0.88, y: 0.10))

    // Git 分支图形：主线 + 分叉 + 三个节点
    guard let context = NSGraphicsContext.current?.cgContext else { return image }
    context.setStrokeColor(NSColor.white.withAlphaComponent(0.96).cgColor)
    context.setLineWidth(52)
    context.setLineCap(.round)
    context.setLineJoin(.round)

    context.move(to: CGPoint(x: 388, y: 300))
    context.addLine(to: CGPoint(x: 388, y: 792))
    context.strokePath()

    context.move(to: CGPoint(x: 388, y: 640))
    context.addCurve(to: CGPoint(x: 660, y: 430),
                     control1: CGPoint(x: 388, y: 510),
                     control2: CGPoint(x: 660, y: 570))
    context.addLine(to: CGPoint(x: 660, y: 250))
    context.strokePath()

    for point in [CGPoint(x: 388, y: 792), CGPoint(x: 388, y: 300), CGPoint(x: 660, y: 250)] {
        context.setFillColor(NSColor.white.cgColor)
        context.fillEllipse(in: CGRect(x: point.x - 62, y: point.y - 62, width: 124, height: 124))
        context.setFillColor(top.cgColor)
        context.fillEllipse(in: CGRect(x: point.x - 24, y: point.y - 24, width: 48, height: 48))
    }

    // 顶部细描边，增强玻璃质感
    context.setStrokeColor(NSColor.white.withAlphaComponent(0.40).cgColor)
    context.setLineWidth(6)
    shape.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return image
}

func writePNG(_ image: NSImage, dimension: CGFloat, to url: URL) throws {
    let target = NSImage(size: NSSize(width: dimension, height: dimension))
    target.lockFocus()
    image.draw(in: NSRect(origin: .zero, size: NSSize(width: dimension, height: dimension)),
               from: NSRect(origin: .zero, size: NSSize(width: canvas, height: canvas)),
               operation: .copy, fraction: 1)
    target.unlockFocus()
    guard let tiff = target.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "GitGlassIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "PNG 生成失败"])
    }
    try data.write(to: url)
}

let fm = FileManager.default
try? fm.removeItem(at: iconset)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
let base = drawBaseImage()

let entries: [(String, CGFloat)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]
for (name, dimension) in entries {
    try writePNG(base, dimension: dimension, to: iconset.appendingPathComponent(name))
}

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", iconURL.path]
try task.run()
task.waitUntilExit()
guard task.terminationStatus == 0 else {
    throw NSError(domain: "GitGlassIcon", code: 2, userInfo: [NSLocalizedDescriptionKey: "iconutil 失败"])
}

let size = (try? fm.attributesOfItem(atPath: iconURL.path)[.size] as? NSNumber)??.intValue ?? 0
print("图标已生成：\(iconURL.path)（\(size) bytes）")
