import AppKit
import SwiftUI

/// 16 × 16 格坐标里的一组笔画与实心点。标志、菜单栏图标、行内状态图形和控件图标都用这一种描述，
/// 出自同一套几何：默认 1.5 线宽、圆头圆角，随绘制尺寸等比缩放。
struct GlyphGeometry {
    struct Stroke {
        var path = Path()
        /// 线宽，16 格单位。
        var width: CGFloat = 1.5
        var dash: [CGFloat] = []
        var cap: CGLineCap = .round
    }

    var strokes: [Stroke] = []
    var fill = Path()

    static let grid: CGFloat = 16

    init(strokes: [Stroke] = [], fill: Path = Path()) {
        self.strokes = strokes
        self.fill = fill
    }

    /// 一条默认线宽的笔画。
    init(_ build: (inout Path) -> Void) {
        var path = Path()
        build(&path)
        strokes = [Stroke(path: path)]
    }
}

/// 按尺寸绘制一个 GlyphGeometry，颜色取 foregroundStyle。
struct GlyphView: View {
    let geometry: GlyphGeometry
    let size: CGFloat

    var body: some View {
        let scale = size / GlyphGeometry.grid
        let transform = CGAffineTransform(scaleX: scale, y: scale)
        ZStack {
            ForEach(geometry.strokes.indices, id: \.self) { i in
                let s = geometry.strokes[i]
                s.path.applying(transform).stroke(style: StrokeStyle(
                    lineWidth: s.width * scale, lineCap: s.cap, lineJoin: .round, dash: s.dash.map { $0 * scale }
                ))
            }
            geometry.fill.applying(transform).fill()
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - 标志：字母 H

/// 两根立柱加一道横梁。菜单栏里有四种状态，只靠形状区分：空闲是完整的 H；运行时横梁变成一串移动的点；
/// 需要处理时右柱变成叹号；已暂停只剩两根立柱。弹窗里的标志固定用空闲态，不随状态变。
enum HMark {
    static func geometry(_ state: OverallState, phase: Double = 0, weight: CGFloat = 2) -> GlyphGeometry {
        var p = Path()
        p.addLines([CGPoint(x: 4.5, y: 3), CGPoint(x: 4.5, y: 13)])
        p.addLines([CGPoint(x: 11.5, y: 3), CGPoint(x: 11.5, y: state == .attention ? 9 : 13)])
        if state == .idle || state == .attention {
            p.addLines([CGPoint(x: 4.5, y: 8), CGPoint(x: 11.5, y: 8)])
        }
        var fill = Path()
        if state == .running {
            // 横梁上每隔 3.5 格一个点，phase 从 0 到 1 时整串点向右走一格；点的直径等于线宽。
            let step: CGFloat = 3.5
            var x = 4.5 + step * CGFloat(phase - phase.rounded(.down))
            while x <= 11.5 {
                fill.addEllipse(in: CGRect(x: x - weight / 2, y: 8 - weight / 2, width: weight, height: weight))
                x += step
            }
        }
        if state == .attention {
            fill.addEllipse(in: CGRect(x: 11.5 - 1.15, y: 12.6 - 1.15, width: 2.3, height: 2.3))
        }
        return GlyphGeometry(strokes: [.init(path: p, width: weight)], fill: fill)
    }

    /// 菜单栏用的模板图：黑色加透明定义形状，由系统着色。
    @MainActor
    static func menuBarImage(_ state: OverallState, phase: Double = 0) -> NSImage {
        let size = Theme.Metric.menuBarMark
        let geometry = geometry(state, phase: phase)
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let scale = size / GlyphGeometry.grid
            ctx.scaleBy(x: scale, y: scale)
            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.setLineJoin(.round)
            for s in geometry.strokes {
                ctx.setLineWidth(s.width)
                ctx.setLineCap(s.cap)
                ctx.setLineDash(phase: 0, lengths: s.dash)
                ctx.addPath(s.path.cgPath)
                ctx.strokePath()
            }
            ctx.addPath(geometry.fill.cgPath)
            ctx.fillPath()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = state.accessibilityLabel
        return image
    }
}

extension OverallState {
    var accessibilityLabel: String {
        switch self {
        case .idle: "Horae：空闲"
        case .running: "Horae：正在更新"
        case .attention: "Horae：需要处理"
        case .paused: "Horae：自动更新已暂停"
        }
    }
}

/// 弹窗头部的标志：淡蓝底上的蓝色 H，任何状态下都不变。
struct BrandTile: View {
    var body: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
            .fill(Theme.Palette.accentTint)
            .frame(width: Theme.Metric.tile, height: Theme.Metric.tile)
            .overlay {
                GlyphView(geometry: HMark.geometry(.idle, weight: Theme.Metric.tileMarkWeight), size: Theme.Metric.tileMark)
                    .foregroundStyle(Theme.Palette.accent)
            }
            .accessibilityHidden(true)
    }
}

// MARK: - 状态图形

/// 行尾的状态图形。成功不放图形；运行是底环上一段转动的蓝弧，排队是虚线环，未成功是一个小红点。
enum StatusGlyph {
    static var runningTrack: GlyphGeometry {
        GlyphGeometry { $0.addEllipse(in: CGRect(x: 2.5, y: 2.5, width: 11, height: 11)) }
    }

    /// 从正上方顺时针到正右方的四分之一圆。
    static var runningArc: GlyphGeometry {
        GlyphGeometry {
            $0.addArc(center: CGPoint(x: 8, y: 8), radius: 5.5, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        }
    }

    static var queued: GlyphGeometry {
        var ring = Path()
        ring.addEllipse(in: CGRect(x: 2.5, y: 2.5, width: 11, height: 11))
        return GlyphGeometry(strokes: [.init(path: ring, dash: [2.1, 2.3])])
    }
}

struct RunningGlyph: View {
    var body: some View {
        ZStack {
            GlyphView(geometry: StatusGlyph.runningTrack, size: Theme.Metric.glyph)
                .foregroundStyle(Theme.Palette.line)
            Spinning(period: Theme.Motion.Duration.spin) {
                GlyphView(geometry: StatusGlyph.runningArc, size: Theme.Metric.glyph)
                    .foregroundStyle(Theme.Palette.accent)
            }
        }
    }
}

struct QueuedGlyph: View {
    var body: some View {
        GlyphView(geometry: StatusGlyph.queued, size: Theme.Metric.glyph)
            .foregroundStyle(Theme.Palette.faint)
    }
}

struct BadDot: View {
    var body: some View {
        Circle()
            .fill(Theme.Palette.bad)
            .frame(width: Theme.Metric.badDot, height: Theme.Metric.badDot)
            .padding(.horizontal, Theme.Space.dotMargin)
            .accessibilityHidden(true)
    }
}

/// 匀速旋转；减少动态效果时静止。
struct Spinning<Content: View>: View {
    let period: Double
    @ViewBuilder let content: Content

    var body: some View {
        if Theme.Motion.reduce {
            content
        } else {
            TimelineView(.animation) { ctx in
                let turns = ctx.date.timeIntervalSinceReferenceDate / period
                content.rotationEffect(.degrees((turns - turns.rounded(.down)) * 360))
            }
        }
    }
}

// MARK: - 控件图标

/// 控件图标：16 格、1.5 线宽、圆头，几何照抄原型 shared.js 的 ICONS。
enum Icon {
    case chevronRight, chevronLeft, chevronDown, updown, more, folder, external
    case pause, play, log, gear, stack, bell, power, download, check

    var geometry: GlyphGeometry {
        switch self {
        case .chevronRight:
            GlyphGeometry { $0.addLines([CGPoint(x: 6, y: 3.5), CGPoint(x: 10.5, y: 8), CGPoint(x: 6, y: 12.5)]) }
        case .chevronLeft:
            GlyphGeometry { $0.addLines([CGPoint(x: 10, y: 3.5), CGPoint(x: 5.5, y: 8), CGPoint(x: 10, y: 12.5)]) }
        case .chevronDown:
            GlyphGeometry { $0.addLines([CGPoint(x: 3.5, y: 6), CGPoint(x: 8, y: 10.5), CGPoint(x: 12.5, y: 6)]) }
        case .updown:
            GlyphGeometry {
                $0.addLines([CGPoint(x: 5.2, y: 6.3), CGPoint(x: 8, y: 3.5), CGPoint(x: 10.8, y: 6.3)])
                $0.addLines([CGPoint(x: 5.2, y: 9.7), CGPoint(x: 8, y: 12.5), CGPoint(x: 10.8, y: 9.7)])
            }
        case .more:
            GlyphGeometry(fill: Self.dots([CGPoint(x: 3.5, y: 8), CGPoint(x: 8, y: 8), CGPoint(x: 12.5, y: 8)], radius: 1.1))
        case .folder:
            GlyphGeometry {
                $0.move(to: CGPoint(x: 2, y: 8))
                $0.addArc(tangent1End: CGPoint(x: 2, y: 3.5), tangent2End: CGPoint(x: 5.9, y: 3.5), radius: 1.1)
                $0.addLine(to: CGPoint(x: 5.9, y: 3.5))
                $0.addLine(to: CGPoint(x: 7.4, y: 5))
                $0.addArc(tangent1End: CGPoint(x: 14, y: 5), tangent2End: CGPoint(x: 14, y: 13), radius: 1.1)
                $0.addArc(tangent1End: CGPoint(x: 14, y: 13), tangent2End: CGPoint(x: 2, y: 13), radius: 1.1)
                $0.addArc(tangent1End: CGPoint(x: 2, y: 13), tangent2End: CGPoint(x: 2, y: 3.5), radius: 1.1)
                $0.closeSubpath()
            }
        case .external:
            GlyphGeometry {
                $0.addLines([CGPoint(x: 6.5, y: 4), CGPoint(x: 12, y: 4), CGPoint(x: 12, y: 9.5)])
                $0.addLines([CGPoint(x: 12, y: 4), CGPoint(x: 4.5, y: 11.5)])
            }
        case .pause:
            GlyphGeometry {
                $0.addLines([CGPoint(x: 6, y: 4), CGPoint(x: 6, y: 12)])
                $0.addLines([CGPoint(x: 10, y: 4), CGPoint(x: 10, y: 12)])
            }
        case .play:
            GlyphGeometry {
                $0.addLines([CGPoint(x: 5.5, y: 3.8), CGPoint(x: 5.5, y: 12.2), CGPoint(x: 12.5, y: 8)])
                $0.closeSubpath()
            }
        case .log:
            GlyphGeometry {
                $0.addLines([CGPoint(x: 4, y: 2.5), CGPoint(x: 9.5, y: 2.5), CGPoint(x: 12, y: 5), CGPoint(x: 12, y: 13.5), CGPoint(x: 4, y: 13.5)])
                $0.closeSubpath()
                $0.addLines([CGPoint(x: 9.5, y: 2.5), CGPoint(x: 9.5, y: 5), CGPoint(x: 12, y: 5)])
                $0.addLines([CGPoint(x: 6, y: 8), CGPoint(x: 10, y: 8)])
                $0.addLines([CGPoint(x: 6, y: 10.5), CGPoint(x: 10, y: 10.5)])
            }
        case .gear:
            // 齿轮：一圈粗虚线做齿，里面一个环。
            GlyphGeometry(strokes: [
                .init(path: Self.circle(radius: 5.3), width: 2.2, dash: [2.08, 2.08], cap: .butt),
                .init(path: Self.circle(radius: 3.4)),
            ])
        case .stack:
            GlyphGeometry {
                $0.addLines([CGPoint(x: 8, y: 2.5), CGPoint(x: 13.5, y: 5.2), CGPoint(x: 8, y: 8), CGPoint(x: 2.5, y: 5.2)])
                $0.closeSubpath()
                $0.addLines([CGPoint(x: 2.5, y: 8), CGPoint(x: 8, y: 10.8), CGPoint(x: 13.5, y: 8)])
                $0.addLines([CGPoint(x: 2.5, y: 10.8), CGPoint(x: 8, y: 13.5), CGPoint(x: 13.5, y: 10.8)])
            }
        case .bell:
            GlyphGeometry {
                $0.move(to: CGPoint(x: 8, y: 2.5))
                $0.addArc(tangent1End: CGPoint(x: 4.5, y: 2.5), tangent2End: CGPoint(x: 4.5, y: 6), radius: 3.5)
                for point in [CGPoint(x: 4.5, y: 8.3), CGPoint(x: 3.3, y: 10.5), CGPoint(x: 12.7, y: 10.5), CGPoint(x: 11.5, y: 8.3), CGPoint(x: 11.5, y: 6)] {
                    $0.addLine(to: point)
                }
                $0.addArc(tangent1End: CGPoint(x: 11.5, y: 2.5), tangent2End: CGPoint(x: 8, y: 2.5), radius: 3.5)
                $0.closeSubpath()
                $0.move(to: CGPoint(x: 6.6, y: 12.6))
                $0.addQuadCurve(to: CGPoint(x: 9.4, y: 12.6), control: CGPoint(x: 8, y: 14.5))
            }
        case .power:
            GlyphGeometry {
                $0.addLines([CGPoint(x: 8, y: 2.5), CGPoint(x: 8, y: 7.5)])
                $0.move(to: CGPoint(x: 11.1, y: 4.4))
                $0.addArc(center: CGPoint(x: 8, y: 7.8), radius: 4.6, startAngle: .degrees(-47.6), endAngle: .degrees(227.6), clockwise: false)
            }
        case .download:
            GlyphGeometry {
                $0.addLines([CGPoint(x: 8, y: 3), CGPoint(x: 8, y: 10)])
                $0.addLines([CGPoint(x: 5, y: 7.5), CGPoint(x: 8, y: 10.5), CGPoint(x: 11, y: 7.5)])
                $0.addLines([CGPoint(x: 3.5, y: 13), CGPoint(x: 12.5, y: 13)])
            }
        case .check:
            GlyphGeometry { $0.addLines([CGPoint(x: 3.5, y: 8.5), CGPoint(x: 6.5, y: 11.5), CGPoint(x: 12.5, y: 4.5)]) }
        }
    }

    func view(size: CGFloat) -> GlyphView {
        GlyphView(geometry: geometry, size: size)
    }

    private static func circle(radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: 8 - radius, y: 8 - radius, width: radius * 2, height: radius * 2))
    }

    private static func dots(_ centers: [CGPoint], radius: CGFloat) -> Path {
        var p = Path()
        for c in centers {
            p.addEllipse(in: CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2))
        }
        return p
    }
}
