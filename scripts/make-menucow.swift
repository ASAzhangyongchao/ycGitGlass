#!/usr/bin/env swift
// 生成菜单栏迷你小牛图标（单色模板 + 彩色两套），
// 模板版用于 MenuBarExtra（自动跟随菜单栏明暗），彩色版备用。
//
// 关键教训（2026-11-12 两次 oversized 修复总结）：
// MenuBarExtra(.menu style) 的 label 渲染不受 SwiftUI .frame 修饰约束，
// NSImage 运行时改 size 也可能被忽略——只有图片文件本身的像素尺寸可靠。
// 因此这里直接输出 18x18 像素的成品小图（Retina 下显示约 18pt），
// 不再依赖任何运行时缩放。
import AppKit
import Foundation

// 逻辑画布 128 用于绘制细节，最终缩到 36 像素输出（2x Retina 的 18pt）
let drawSize: CGFloat = 128
let outputPixel: Int = 24
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

func drawCow(template: Bool) -> NSImage {
    let image = NSImage(size: NSSize(width: drawSize, height: drawSize))
    image.lockFocus()
    defer { image.unlockFocus() }
    let size = drawSize

    let body = template ? NSColor.black : NSColor(calibratedRed: 0.76, green: 0.58, blue: 0.40, alpha: 1)
    let dark = template ? NSColor.black : NSColor(calibratedRed: 0.55, green: 0.38, blue: 0.24, alpha: 1)
    let muzzle = template ? NSColor.black : NSColor(calibratedRed: 0.92, green: 0.84, blue: 0.74, alpha: 1)
    let horn = template ? NSColor.black : NSColor(calibratedRed: 0.93, green: 0.88, blue: 0.76, alpha: 1)

    // 牛角
    let leftHorn = NSBezierPath(ovalIn: NSRect(x: 26, y: 86, width: 16, height: 26))
    horn.setFill()
    leftHorn.fill()
    let rightHorn = NSBezierPath(ovalIn: NSRect(x: size - 42, y: 86, width: 16, height: 26))
    rightHorn.fill()

    // 耳朵
    let earL = NSBezierPath(ovalIn: NSRect(x: 8, y: 66, width: 26, height: 16))
    body.setFill(); earL.fill()
    let earR = NSBezierPath(ovalIn: NSRect(x: size - 34, y: 66, width: 26, height: 16))
    body.setFill(); earR.fill()

    // 脸
    let face = NSBezierPath(roundedRect: NSRect(x: 18, y: 30, width: size - 36, height: 66), xRadius: 26, yRadius: 26)
    body.setFill(); face.fill()

    // 斑点
    let spot = NSBezierPath(ovalIn: NSRect(x: size - 52, y: 74, width: 20, height: 14))
    dark.setFill(); spot.fill()

    // 口鼻
    let snout = NSBezierPath(roundedRect: NSRect(x: 34, y: 36, width: size - 68, height: 34), xRadius: 16, yRadius: 16)
    muzzle.setFill(); snout.fill()
    // 鼻孔
    let nostrilL = NSBezierPath(ovalIn: NSRect(x: 50, y: 46, width: 8, height: 10))
    dark.setFill(); nostrilL.fill()
    let nostrilR = NSBezierPath(ovalIn: NSRect(x: size - 58, y: 46, width: 8, height: 10))
    dark.setFill(); nostrilR.fill()

    // 眼睛
    let eyeL = NSBezierPath(ovalIn: NSRect(x: 44, y: 76, width: 10, height: 12))
    eyeL.fill()
    let eyeR = NSBezierPath(ovalIn: NSRect(x: size - 54, y: 76, width: 10, height: 12))
    eyeR.fill()
    // 眼睛高光（模板模式下用背景色挖出）
    let glintColor = template ? NSColor.white : NSColor.white
    let glintL = NSBezierPath(ovalIn: NSRect(x: 47, y: 81, width: 4, height: 4))
    glintColor.setFill(); glintL.fill()
    let glintR = NSBezierPath(ovalIn: NSRect(x: size - 51, y: 81, width: 4, height: 4))
    glintColor.setFill(); glintR.fill()

    // 刘海（头顶一撮毛）
    let tuft = NSBezierPath()
    tuft.move(to: NSPoint(x: size / 2 - 12, y: 94))
    tuft.curve(to: NSPoint(x: size / 2, y: 104),
               controlPoint1: NSPoint(x: size / 2 - 14, y: 104),
               controlPoint2: NSPoint(x: size / 2 - 4, y: 108))
    tuft.curve(to: NSPoint(x: size / 2 + 12, y: 94),
               controlPoint1: NSPoint(x: size / 2 + 4, y: 108),
               controlPoint2: NSPoint(x: size / 2 + 14, y: 104))
    tuft.line(to: NSPoint(x: size / 2 + 8, y: 92))
    tuft.line(to: NSPoint(x: size / 2, y: 98))
    tuft.line(to: NSPoint(x: size / 2 - 8, y: 92))
    tuft.close()
    body.setFill(); tuft.fill()

    return image
}

/// 缩放到指定像素并写 PNG（物理像素，无 DPI 缩放戏法）
func writeSmallPNG(_ image: NSImage, pixel: Int, to url: URL, template: Bool) throws {
    let target = CGFloat(pixel)
    let newSize = NSSize(width: target, height: target)
    let small = NSImage(size: newSize)
    small.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(in: NSRect(origin: .zero, size: newSize),
               from: .zero, operation: .copy, fraction: 1)
    small.unlockFocus()
    small.isTemplate = template
    guard let tiff = small.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          rep.pixelsWide == pixel,  // 确认物理像素正确
          let data = rep.representation(using: .png, properties: [:]) else {
        print("ERROR: 缩放失败，实际像素 \(NSBitmapImageRep(data: small.tiffRepresentation ?? Data())?.pixelsWide ?? -1)")
        exit(1)
    }
    try data.write(to: url)
    print("  \(url.lastPathComponent): \(rep.pixelsWide)x\(rep.pixelsHigh) px, template=\(template)")
}

print("生成菜单栏牛图标（24px 成品（1x 屏菜单栏内显示约 22-24pt，macOS 会裁剪到栏内））…")
let templateCow = drawCow(template: true)
try writeSmallPNG(templateCow, pixel: outputPixel,
                  to: root.appendingPathComponent("Resources/MenuCowTemplate.png"), template: true)

let colorCow = drawCow(template: false)
try writeSmallPNG(colorCow, pixel: outputPixel,
                  to: root.appendingPathComponent("Resources/MenuCowColor.png"), template: false)

print("完成：24px 像素级小图，不依赖任何运行时缩放")
