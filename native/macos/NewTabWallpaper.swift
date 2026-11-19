import AppKit
import QuartzCore

/// New-tab wallpaper: the Inner Citadel. A regular ring guards the quiet search area;
/// broken, offset contours surround it. Everything is drawn as an ordered-dither field
/// of small square pixels. A light travels round the ring and the outer contours turn
/// slowly in opposite directions. Rendering is a cheap per-cell pass on the CPU, only
/// while the page is visible in the active app; Reduce Motion shows one still frame.
@MainActor final class NewTabWallpaperView: NSView {
    private let pixels = CALayer()
    private let gaps = CAShapeLayer()
    private var citadel = DitherCitadel()
    private var context: CGContext?
    private var link: CADisplayLink?
    private var observations: [(NotificationCenter, NSObjectProtocol)] = []
    private var entered = false
    private let epoch = CACurrentMediaTime()
    override var isFlipped: Bool { true }
    override var wantsUpdateLayer: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        pixels.magnificationFilter = .nearest
        pixels.contentsGravity = .resize
        layer?.addSublayer(pixels)
        layer?.addSublayer(gaps)
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { for (center, token) in observations { center.removeObserver(token) } }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func updateLayer() {}

    override func layout() {
        super.layout()
        rebuild()
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        for (center, token) in observations { center.removeObserver(token) }
        observations.removeAll()
        link?.invalidate(); link = nil
        if let window {
            let changed: @Sendable (Notification) -> Void = { [weak self] _ in MainActor.assumeIsolated { self?.updateMotion() } }
            let local = NotificationCenter.default, workspace = NSWorkspace.shared.notificationCenter
            observations = [
                (local, local.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main, using: changed)),
                (local, local.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main, using: changed)),
                (local, local.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main, using: changed)),
                (workspace, workspace.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main, using: changed))
            ]
            let target = FrameTarget(); target.view = self
            let link = displayLink(target: target, selector: #selector(FrameTarget.tick(_:)))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 12, maximum: 24, preferred: 20)
            link.isPaused = true
            link.add(to: .main, forMode: .common)
            self.link = link
        }
        rebuild()
    }
    override func viewDidHide() { super.viewDidHide(); updateMotion() }
    override func viewDidUnhide() { super.viewDidUnhide(); updateMotion() }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); rebuild() }
    override func viewDidChangeBackingProperties() { super.viewDidChangeBackingProperties(); rebuild() }

    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    private var visible: Bool {
        guard let window else { return false }
        return window.occlusionState.contains(.visible) && !isHiddenOrHasHiddenAncestor && !bounds.isEmpty
    }

    private func rebuild() {
        CATransaction.begin(); CATransaction.setDisableActions(true); defer { CATransaction.commit() }
        let scale = window?.backingScaleFactor ?? 2
        citadel.resize(bounds.size)
        guard citadel.cols > 0 else { context = nil; pixels.contents = nil; gaps.path = nil; return }
        if context?.width != citadel.cols || context?.height != citadel.rows {
            context = CGContext(data: nil, width: citadel.cols, height: citadel.rows, bitsPerComponent: 8, bytesPerRow: citadel.cols * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        }
        let grid = citadel.gridFrame
        pixels.frame = grid
        gaps.frame = bounds
        gaps.contentsScale = scale
        gaps.fillColor = Palette.background(self).cgColor
        // Thin background-coloured lines turn the scaled image into separate squares.
        let path = CGMutablePath(), cell = DitherCitadel.cell, gap = DitherCitadel.gap
        for column in 0...citadel.cols { path.addRect(CGRect(x: grid.minX + CGFloat(column) * cell - gap, y: grid.minY, width: gap, height: grid.height)) }
        for row in 0...citadel.rows { path.addRect(CGRect(x: grid.minX, y: grid.minY + CGFloat(row) * cell - gap, width: grid.width, height: gap)) }
        gaps.path = path
        draw(at: CACurrentMediaTime())
        updateMotion()
    }

    private func draw(at time: CFTimeInterval) {
        guard let context, let data = context.data else { return }
        let dark = Palette.dark(self)
        citadel.render(time: reduceMotion ? 7 : time - epoch + 7,
                     into: data.bindMemory(to: UInt32.self, capacity: citadel.cols * citadel.rows),
                     ink: Self.rgba(Palette.neutral(dark ? 0.45 : 0.75)), glow: Self.rgba(Palette.neutral(dark ? 0.55 : 0.65)))
        CATransaction.begin(); CATransaction.setDisableActions(true)
        pixels.contents = context.makeImage()
        CATransaction.commit()
    }
    fileprivate func step(_ link: CADisplayLink) { draw(at: link.targetTimestamp) }

    private func updateMotion() {
        let animate = visible && NSApp.isActive && !reduceMotion
        link?.isPaused = !animate
        if !animate { layer?.removeAnimation(forKey: "wallpaperEntrance") }
        guard visible, !entered else { return }
        entered = true
        guard !reduceMotion else { return }
        let entrance = CABasicAnimation(keyPath: "opacity")
        entrance.fromValue = 0.15; entrance.toValue = 1.0; entrance.duration = 0.5
        entrance.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer?.add(entrance, forKey: "wallpaperEntrance")
    }

    private static func rgba(_ color: NSColor) -> UInt32 {
        let c = color.usingColorSpace(.sRGB) ?? color
        func byte(_ v: CGFloat) -> UInt32 { UInt32(max(0, min(255, (v * 255).rounded()))) }
        // premultipliedLast in memory order R, G, B, A on a little-endian host.
        return 0xFF00_0000 | byte(c.blueComponent) << 16 | byte(c.greenComponent) << 8 | byte(c.redComponent)
    }
}

@MainActor private final class FrameTarget: NSObject {
    weak var view: NewTabWallpaperView?
    @objc func tick(_ link: CADisplayLink) {
        guard let view else { link.invalidate(); return }
        view.step(link)
    }
}

/// The citadel field, evaluated per screen cell and thresholded with an 8×8 Bayer
/// matrix, like an early 1-bit renderer. Geometry matches the original dot drawing.
private struct DitherCitadel {
    static let cell: CGFloat = 4
    static let gap: CGFloat = 1
    private static let bayer: [Float] = {
        let m: [Int] = [0,32,8,40,2,34,10,42, 48,16,56,24,50,18,58,26, 12,44,4,36,14,46,6,38, 60,28,52,20,62,30,54,22,
                        3,35,11,43,1,33,9,41, 51,19,59,27,49,17,57,25, 15,47,7,39,13,45,5,37, 63,31,55,23,61,29,53,21]
        return m.map { (Float($0) + 0.5) / 64 }
    }()
    private(set) var cols = 0, rows = 0
    private(set) var gridFrame = CGRect.zero
    // Ring centre and inverse radii in grid units.
    private var cx: Float = 0, cy: Float = 0, invRX: Float = 1, invRY: Float = 1

    mutating func resize(_ size: CGSize) {
        let c = Self.cell
        cols = max(0, Int(ceil(size.width / c))); rows = max(0, Int(ceil(size.height / c)))
        gridFrame = CGRect(x: ((size.width - CGFloat(cols) * c) / 2).rounded(.down), y: ((size.height - CGFloat(rows) * c) / 2).rounded(.down),
                           width: CGFloat(cols) * c, height: CGFloat(rows) * c)
        guard size.width > 0, size.height > 0 else { cols = 0; rows = 0; return }
        let searchWidth = min(584, size.width * 0.84)
        let radiusX = max(size.width * 0.36, searchWidth * 0.62)
        let radiusY = max(124, size.height * 0.33)
        cx = Float((size.width / 2 - gridFrame.minX) / c); cy = Float((size.height * 0.46 - gridFrame.minY) / c)
        invRX = Float(c / radiusX); invRY = Float(c / radiusY)
    }

    func render(time: Double, into out: UnsafeMutablePointer<UInt32>, ink: UInt32, glow: UInt32) {
        guard cols > 0, rows > 0 else { return }
        let t = Float(time.truncatingRemainder(dividingBy: 3600))
        // Phases change once per frame; per cell only multiplications remain.
        func turn(_ period: Float, _ offset: Float = 0) -> (Float, Float) { let a = offset + t * 2 * .pi / period; return (cos(a), sin(a)) }
        let (cDrift3, sDrift3) = turn(70, 0.4)        // contour wobble
        let (cDrift5, sDrift5) = turn(-95)
        let (cNear, sNear) = turn(90, 0.6)            // inner broken arcs turn one way…
        let (cFar, sFar) = turn(-120, -0.3)           // …outer arcs the other
        let (cLight, sLight) = turn(24, -1.2)         // light travelling round the ring
        let breathe = 0.92 + 0.08 * sin(t * 2 * .pi / 7)
        let cols = cols, rows = rows, cx = cx, cy = cy, invRX = invRX, invRY = invRY
        Self.bayer.withUnsafeBufferPointer { bayer in
            for gy in 0..<rows {
                let dy = (Float(gy) + 0.5 - cy) * invRY, row = gy * cols, br = (gy & 7) * 8
                for gx in 0..<cols {
                    let dx = (Float(gx) + 0.5 - cx) * invRX
                    let d = (dx * dx + dy * dy).squareRoot()
                    // The inner citadel stays quiet for search.
                    guard d > 0.91 else { out[row + gx] = 0; continue }
                    let ca = dx / d, sa = dy / d
                    let c2 = ca * ca - sa * sa, s2 = 2 * sa * ca
                    let c3 = c2 * ca - s2 * sa, s3 = s2 * ca + c2 * sa
                    let c5 = c3 * c2 - s3 * s2, s5 = s3 * c2 + c3 * s2
                    var lit = max(0, ca * cLight + sa * sLight); lit *= lit; lit *= lit * lit
                    let ring = Self.band(d, 1, 0.075) * breathe * (0.6 + 0.4 * lit)
                    let drift = 0.07 * (s3 * cDrift3 + c3 * sDrift3) + 0.035 * (c5 * cDrift5 - s5 * sDrift5)
                    let outer = d + drift
                    let near = max(0, s2 * cNear + c2 * sNear) * Self.band(outer, 1.27, 0.11)
                    let far = max(0, c3 * cFar - s3 * sFar) * Self.band(outer, 1.56, 0.14)
                    let field = 0.1 * min(1, max(0, d - 1.08) / 0.38)
                    let v = min(1, 1.2 * max(ring, 0.6 * near * (0.85 + 0.3 * lit), 0.45 * far, field))
                    let threshold = bayer[br + (gx & 7)]
                    out[row + gx] = v > threshold ? (v > 0.8 && threshold < 0.3 ? glow : ink) : 0
                }
            }
        }
    }

    private static func band(_ distance: Float, _ center: Float, _ width: Float) -> Float {
        max(0, 1 - abs(distance - center) / width)
    }
}
