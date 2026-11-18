import AppKit
import QuartzCore

@MainActor final class NewTabWallpaperView: NSView {
    private var entered = false
    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .duringViewResize
    }

    required init?(coder: NSCoder) { fatalError() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, !entered else { return }
        entered = true
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let entrance = CABasicAnimation(keyPath: "opacity")
        entrance.fromValue = 0.15
        entrance.toValue = 1.0
        entrance.duration = 0.5
        entrance.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer?.add(entrance, forKey: "wallpaperEntrance")
    }

    override func viewDidHide() {
        super.viewDidHide()
        layer?.removeAnimation(forKey: "wallpaperEntrance")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NewTabWallpaper.draw(in: bounds, dirtyRect: dirtyRect, dark: Palette.dark(self))
    }
}

@MainActor enum NewTabWallpaper {
    static func draw(in bounds: NSRect, dirtyRect: NSRect, dark: Bool) {
        guard bounds.width > 0, bounds.height > 0 else { return }

        let grid = max(14, bounds.width / 160, bounds.height / 90)
        let paths = [NSBezierPath(), NSBezierPath(), NSBezierPath()]
        let lightness = dark ? [0.20, 0.25, 0.30] : [0.90, 0.85, 0.80]
        let firstColumn = max(0, Int(floor(dirtyRect.minX / grid)))
        let firstRow = max(0, Int(floor(dirtyRect.minY / grid)))
        let lastColumn = Int(ceil(dirtyRect.maxX / grid))
        let lastRow = Int(ceil(dirtyRect.maxY / grid))
        guard firstColumn < lastColumn, firstRow < lastRow else { return }

        // The inner citadel stays regular. The surrounding contours are broken
        // and offset, leaving the area inside the ring quiet for search.
        let searchWidth = min(584, bounds.width * 0.84)
        let radiusX = max(bounds.width * 0.36, searchWidth * 0.62)
        let radiusY = max(124, bounds.height * 0.33)
        for column in firstColumn..<lastColumn {
            let x = (CGFloat(column) + 0.5) * grid
            let dx = (x - bounds.midX) / radiusX
            for row in firstRow..<lastRow {
                let y = (CGFloat(row) + 0.5) * grid
                let dy = (y - bounds.height * 0.46) / radiusY
                let distance = hypot(dx, dy)
                guard distance > 0.91 else { continue }
                let angle = atan2(dy, dx)
                let ring = 0.70 * band(distance, around: 1, width: 0.075)
                let drift = 0.07 * sin(3 * angle + 0.4) + 0.035 * cos(5 * angle)
                let outerDistance = distance + drift
                let nearArc = max(0, sin(2 * angle + 0.6)) * band(outerDistance, around: 1.27, width: 0.11)
                let farArc = max(0, cos(3 * angle - 0.3)) * band(outerDistance, around: 1.56, width: 0.14)
                let strength = max(ring, 0.60 * nearArc, 0.45 * farArc, 0.12 * min(1, max(0, distance - 1.08) / 0.38))
                guard strength >= 0.055 else { continue }

                let tone = strength > 0.48 ? 2 : strength > 0.24 ? 1 : 0
                let radius = 0.38 + 1.25 * strength
                let dot = NSRect(x: x - radius, y: y - radius, width: 2 * radius, height: 2 * radius)
                paths[tone].appendOval(in: dot)
            }
        }

        for (path, tone) in zip(paths, lightness) {
            Palette.neutral(tone).setFill()
            path.fill()
        }
    }

    private static func band(_ distance: CGFloat, around center: CGFloat, width: CGFloat) -> CGFloat {
        max(0, 1 - abs(distance - center) / width)
    }
}
