// make-app-icon.swift: 生成 app/AppIcon.icns。用法：swift scripts/make-app-icon.swift app/AppIcon.icns
//
// 图标是弹窗头部标志的放大版：淡蓝底上的蓝色 H。H 的几何与线宽照 app 里的 HMark.geometry(.idle)
// 和 Theme.Metric.tile / tileMark / tileMarkWeight（16 格坐标，立柱在 x = 4.5 与 11.5、y 从 3 到 13，
// 横梁在 y = 8，线宽 2.2，标志占底块的 12/18）；颜色取浅色外观的 accent 与 accentTint。
// 底块按 macOS 图标网格放：1024 画布里 824 见方、圆角 185 的连续圆角矩形，下方一层柔和投影。
// 每个尺寸单独绘制，不从大图缩小，小尺寸也清晰。
import AppKit
import SwiftUI

let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "app/AppIcon.icns")

/// 1024 画布上的设计值。
enum Design {
    static let canvas: CGFloat = 1024
    static let plate = CGRect(x: 100, y: 100, width: 824, height: 824)
    static let plateRadius: CGFloat = 185
    /// 标志占底块的比例与线宽，与弹窗头部的标志相同：12 / 18，线宽 2.2 格。
    static let markRatio: CGFloat = 12.0 / 18.0
    static let markWeight: CGFloat = 2.2
    static let grid: CGFloat = 16

    /// 淡蓝底：accentTint（0, 104, 224, 12%）压在白色上约为 #E0EDFB，上浅下深一点做出体积。
    static let plateTop = NSColor(srgbRed: 0xEE / 255, green: 0xF5 / 255, blue: 0xFE / 255, alpha: 1)
    static let plateBottom = NSColor(srgbRed: 0xD4 / 255, green: 0xE5 / 255, blue: 0xFA / 255, alpha: 1)
    /// 蓝色 H：accent #005FD1，上亮下暗一点。
    static let markTop = NSColor(srgbRed: 0x1A / 255, green: 0x72 / 255, blue: 0xE0 / 255, alpha: 1)
    static let markBottom = NSColor(srgbRed: 0x00 / 255, green: 0x56 / 255, blue: 0xC2 / 255, alpha: 1)
    static let shadow = NSColor(white: 0, alpha: 0.22)
    static let shadowBlur: CGFloat = 24
    static let shadowOffset: CGFloat = 10
}

func render(pixels: Int) -> Data {
    let size = CGFloat(pixels)
    let scale = size / Design.canvas
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: rep) else { fatalError("bitmap \(pixels)") }
    let ctx = context.cgContext
    ctx.scaleBy(x: scale, y: scale)
    // 设计坐标 y 向下，与 16 格坐标一致。
    ctx.translateBy(x: 0, y: Design.canvas)
    ctx.scaleBy(x: 1, y: -1)

    let plate = RoundedRectangle(cornerRadius: Design.plateRadius, style: .continuous).path(in: Design.plate).cgPath
    let space = CGColorSpace(name: CGColorSpace.sRGB)!

    // 底块与投影。
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -Design.shadowOffset * scale), blur: Design.shadowBlur * scale, color: Design.shadow.cgColor)
    ctx.addPath(plate)
    ctx.setFillColor(Design.plateBottom.cgColor)
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(plate)
    ctx.clip()
    let plateGradient = CGGradient(colorsSpace: space, colors: [Design.plateTop.cgColor, Design.plateBottom.cgColor] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(plateGradient, start: CGPoint(x: 0, y: Design.plate.minY), end: CGPoint(x: 0, y: Design.plate.maxY), options: [])
    ctx.restoreGState()

    // H：16 格坐标居中放进底块，标志框占底块的 12/18。
    let markSize = Design.plate.width * Design.markRatio
    let unit = markSize / Design.grid
    let origin = CGPoint(x: Design.plate.midX - markSize / 2, y: Design.plate.midY - markSize / 2)
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: origin.x + x * unit, y: origin.y + y * unit) }
    let h = CGMutablePath()
    h.addLines(between: [p(4.5, 3), p(4.5, 13)])
    h.addLines(between: [p(11.5, 3), p(11.5, 13)])
    h.addLines(between: [p(4.5, 8), p(11.5, 8)])
    let stroked = h.copy(strokingWithWidth: Design.markWeight * unit, lineCap: .round, lineJoin: .round, miterLimit: 10)
    ctx.saveGState()
    ctx.addPath(stroked)
    ctx.clip()
    let markGradient = CGGradient(colorsSpace: space, colors: [Design.markTop.cgColor, Design.markBottom.cgColor] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(markGradient, start: p(0, 3), end: p(0, 13), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()

    context.flushGraphics()
    guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("png \(pixels)") }
    return png
}

let iconset = FileManager.default.temporaryDirectory.appending(path: "AppIcon-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: iconset) }
for base in [16, 32, 128, 256, 512] {
    try render(pixels: base).write(to: iconset.appending(path: "icon_\(base)x\(base).png"))
    try render(pixels: base * 2).write(to: iconset.appending(path: "icon_\(base)x\(base)@2x.png"))
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", "-o", output.path, iconset.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil exited \(iconutil.terminationStatus)") }
print("wrote \(output.path)")
