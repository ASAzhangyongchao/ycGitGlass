import SwiftUI
import AppKit
import GitCore

/// 品牌常量：工程标识仍为 GitGlass，面向用户的产品名是「码牛 MooGit」。
enum Brand {
    static let name = "码牛"
    static let englishName = "MooGit"
    static let fullName = "码牛 MooGit"
    static let tagline = "轻量 Git 工作台 · 看清每一次改动"
    static var version: String { AppConfig.appVersion }
    static var repoSlug: String { AppConfig.repoSlug }
    static var repoURL: URL { AppConfig.repoURL }
    static var releasesURL: URL { AppConfig.releasesURL }

    /// .app bundle 里由 make-brand-assets.swift 生成；swift run 调试时回退到系统符号。
    static var headerImage: NSImage {
        if let url = Bundle.main.url(forResource: "BrandHeader", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return NSImage(systemSymbolName: "chevron.left.forwardslash.chevron.right",
                       accessibilityDescription: nil) ?? NSImage()
    }

    /// 菜单栏迷你小牛（模板图：自动跟随菜单栏明暗，单色镂空）。
    /// 注意：源图 128×128，必须把逻辑尺寸压到菜单栏标准（约 18pt），
    /// 否则 Image(nsImage:) 按原始尺寸渲染会把菜单栏图标撑成巨块。
    static var menuCowImage: NSImage {
        if let url = Bundle.main.url(forResource: "MenuCowTemplate", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            image.isTemplate = true
            let menuSize = NSSize(width: 18, height: 18)
            image.size = menuSize
            for rep in image.representations { rep.size = menuSize }
            return image
        }
        // 兜底：SF Symbol（非 .app 环境运行时）
        return NSImage(systemSymbolName: "chevron.left.forwardslash.chevron.right",
                       accessibilityDescription: nil) ?? NSImage()
    }
}


