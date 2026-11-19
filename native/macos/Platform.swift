import AppKit
import WebKit

@MainActor final class RustCore {
    private let pointer: UnsafeMutableRawPointer
    private(set) var ids:[Int]=[]
    private(set) var selected:Int?
    init() { pointer = sisu_core_create()! }
    deinit { sisu_core_destroy(pointer) }
    func call(_ command: [String: Any]) -> [String: Any] {
        guard let data = try? JSONSerialization.data(withJSONObject: command) else { return [:] }
        return data.withUnsafeBytes { bytes in
            guard let response = sisu_core_command(pointer, bytes.bindMemory(to: UInt8.self).baseAddress, data.count) else { return [:] }
            defer { sisu_core_free(response) }
            let result = Data(String(cString: response).utf8)
            let decoded=(try? JSONSerialization.jsonObject(with: result)) as? [String: Any] ?? [:]
            if let tabs=decoded["tabs"] as? [Int] { ids=tabs;selected=decoded["selected"] as? Int }
            return decoded
        }
    }
    var snapshot: [String: Any] { call(["op": "snapshot"]) }
    func destination(_ text: String, google: Bool) -> URL? {
        guard let string = call(["op": "resolve", "input": text, "google": google])["destination"] as? String else { return nil }
        return URL(string: string)
    }
}

struct Preferences: Codable {
    var placement = "top"
    var theme = "dark"
    var google = false
    var blocking = true
    var sidebarWidth = 216
    // Tabs and windows
    var lastTab = "newTab"            // newTab · closeWindow
    var downloads = "ask"             // ask · downloads
    // Web content (public WebKit API only)
    var javaScript = true
    var blockPopups = true
    var pageZoom = 100
    var minimumFontSize = 0
    var fullscreen = true
    var textInteraction = true
    var siteQuirks = true
    var tabFocusesLinks = false
    var printBackgrounds = false
    var incrementalRendering = true
    // Input and gestures
    var swipeNavigation = true
    var pinchZoom = false
    var linkPreview = true
    var inlinePredictions = false
    // Media
    var autoplay = "allow"            // allow · audio · none
    var airPlay = true
    var camera = "ask"                // ask · deny
    // Privacy and security
    var fraudWarning = true
    var lockdown = false
    // Developer
    var inspector = false
    var userAgent = ""

    enum CodingKeys: String, CodingKey {
        case placement,theme,google,blocking,sidebarWidth,lastTab,downloads
        case javaScript,blockPopups,pageZoom,minimumFontSize,fullscreen,textInteraction,siteQuirks,tabFocusesLinks,printBackgrounds,incrementalRendering
        case swipeNavigation,pinchZoom,linkPreview,inlinePredictions
        case autoplay,airPlay,camera,fraudWarning,lockdown,inspector,userAgent
    }
    init() {}
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Preferences()
        // A malformed entry falls back to its default instead of losing the whole profile.
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T { (try? values.decodeIfPresent(T.self, forKey: key)) ?? fallback }
        func choice(_ key: CodingKeys, _ fallback: String, _ allowed: [String]) -> String { let v: String = value(key, fallback); return allowed.contains(v) ? v : fallback }
        placement = choice(.placement, "top", ["top","left"])
        theme = choice(.theme, "dark", ["dark","light","system"])
        google = value(.google, false)
        blocking = value(.blocking, true)
        sidebarWidth = min(350,max(92,value(.sidebarWidth, 216)))
        lastTab = choice(.lastTab, defaults.lastTab, ["newTab","closeWindow"])
        downloads = choice(.downloads, defaults.downloads, ["ask","downloads"])
        javaScript = value(.javaScript, defaults.javaScript)
        blockPopups = value(.blockPopups, defaults.blockPopups)
        pageZoom = min(300,max(50,value(.pageZoom, defaults.pageZoom)))
        minimumFontSize = min(72,max(0,value(.minimumFontSize, defaults.minimumFontSize)))
        fullscreen = value(.fullscreen, defaults.fullscreen)
        textInteraction = value(.textInteraction, defaults.textInteraction)
        siteQuirks = value(.siteQuirks, defaults.siteQuirks)
        tabFocusesLinks = value(.tabFocusesLinks, defaults.tabFocusesLinks)
        printBackgrounds = value(.printBackgrounds, defaults.printBackgrounds)
        incrementalRendering = value(.incrementalRendering, defaults.incrementalRendering)
        swipeNavigation = value(.swipeNavigation, defaults.swipeNavigation)
        pinchZoom = value(.pinchZoom, defaults.pinchZoom)
        linkPreview = value(.linkPreview, defaults.linkPreview)
        inlinePredictions = value(.inlinePredictions, defaults.inlinePredictions)
        autoplay = choice(.autoplay, defaults.autoplay, ["allow","audio","none"])
        airPlay = value(.airPlay, defaults.airPlay)
        camera = choice(.camera, defaults.camera, ["ask","deny"])
        fraudWarning = value(.fraudWarning, defaults.fraudWarning)
        lockdown = value(.lockdown, defaults.lockdown)
        inspector = value(.inspector, defaults.inspector)
        userAgent = String(value(.userAgent, defaults.userAgent).prefix(512))
    }
}

/// Maps profile preferences onto public WebKit API. Creation-time options apply
/// to tabs opened afterwards; live options are pushed to every open tab.
@MainActor enum WebSettings {
    static func configure(_ config: WKWebViewConfiguration, _ p: Preferences, supplied: Bool) {
        apply(config.preferences, p)
        // A popup configuration from WebKit already carries its opener's options.
        guard !supplied else { return }
        config.suppressesIncrementalRendering = !p.incrementalRendering
        config.allowsAirPlayForMediaPlayback = p.airPlay
        config.mediaTypesRequiringUserActionForPlayback = p.autoplay == "none" ? .all : p.autoplay == "audio" ? .audio : []
        config.allowsInlinePredictions = p.inlinePredictions
        // JavaScript and Lockdown Mode are decided per navigation (see `navigation`), so a
        // later change takes effect on reload instead of sticking to the tab's defaults.
    }
    static func apply(_ prefs: WKPreferences, _ p: Preferences) {
        prefs.javaScriptCanOpenWindowsAutomatically = !p.blockPopups
        prefs.minimumFontSize = CGFloat(p.minimumFontSize)
        prefs.isElementFullscreenEnabled = p.fullscreen
        prefs.isTextInteractionEnabled = p.textInteraction
        prefs.isSiteSpecificQuirksModeEnabled = p.siteQuirks
        prefs.tabFocusesLinks = p.tabFocusesLinks
        prefs.shouldPrintBackgrounds = p.printBackgrounds
        prefs.isFraudulentWebsiteWarningEnabled = p.fraudWarning
    }
    static func apply(_ web: WKWebView, _ p: Preferences, zoom: Bool) {
        apply(web.configuration.preferences, p)
        web.allowsBackForwardNavigationGestures = p.swipeNavigation
        web.allowsMagnification = p.pinchZoom
        if !p.pinchZoom, web.magnification != 1 { web.magnification = 1 }
        web.allowsLinkPreview = p.linkPreview
        web.customUserAgent = p.userAgent.isEmpty ? nil : p.userAgent
        if p.inspector { web.isInspectable = true }
        if zoom { web.pageZoom = CGFloat(p.pageZoom) / 100 }
    }
    /// A fresh WKWebpagePreferences reports the system-wide Lockdown Mode state.
    private static var systemLockdown: Bool { WKWebpagePreferences().isLockdownModeEnabled }
    /// Per-navigation options, set both ways so turning an option off also applies.
    /// Never weakens a system-wide Lockdown Mode.
    static func navigation(_ page: WKWebpagePreferences, _ p: Preferences) {
        page.allowsContentJavaScript = p.javaScript
        page.isLockdownModeEnabled = p.lockdown || systemLockdown
    }
}

@MainActor final class Profile {
    let isPrivate: Bool
    let root: URL
    let store: WKWebsiteDataStore
    var preferences: Preferences
    private let preferencesURL: URL
    init(isPrivate: Bool) throws {
        self.isPrivate = isPrivate
        let manager = FileManager.default
        let base = ProcessInfo.processInfo.environment["BROWSER_TEST_HOME"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? manager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Sisu WebKit", isDirectory: true)
        root = base.appendingPathComponent("sisu-webkit", isDirectory: true)
        preferencesURL = root.appendingPathComponent("preferences.json")
        if isPrivate {
            // Private launches do not read or create ordinary preferences/profile IDs.
            store = .nonPersistent()
            preferences = Preferences()
        } else {
            try manager.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let identifierURL = root.appendingPathComponent("profile-id")
            let identifier: UUID
            if manager.fileExists(atPath: identifierURL.path) {
                guard let value = UUID(uuidString: try String(contentsOf: identifierURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)) else {
                    throw NSError(domain: "Sisu", code: 1, userInfo: [NSLocalizedDescriptionKey: "The profile identifier cannot be read. Existing data was preserved."])
                }
                identifier = value
            } else {
                identifier = UUID()
                try Data(identifier.uuidString.utf8).write(to: identifierURL, options: .atomic)
            }
            store = WKWebsiteDataStore(forIdentifier: identifier)
            if manager.fileExists(atPath: preferencesURL.path) {
                preferences = try JSONDecoder().decode(Preferences.self, from: Data(contentsOf: preferencesURL))
            } else { preferences = Preferences() }
        }
    }
    func save() throws {
        guard !isPrivate else { return }
        try JSONEncoder().encode(preferences).write(to: preferencesURL, options: .atomic)
    }
}

@MainActor enum Palette {
    static func neutral(_ lightness: Double) -> NSColor {
        let linear = pow(lightness, 3)
        let value = linear <= 0.0031308 ? 12.92 * linear : 1.055 * pow(linear, 1 / 2.4) - 0.055
        return NSColor(srgbRed: value, green: value, blue: value, alpha: 1)
    }
    static func dark(_ view: NSView) -> Bool { view.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }
    static func background(_ view: NSView) -> NSColor { neutral(dark(view) ? 0.25 : 0.95) }
    static func field(_ view: NSView) -> NSColor { neutral(dark(view) ? 0.30 : 1.0) }
    static func address(_ view: NSView) -> NSColor { neutral(dark(view) ? 0.35 : 1.0) }
    static func tab(_ view: NSView) -> NSColor { neutral(dark(view) ? 0.35 : 1.0) }
    static func tabBorder(_ view: NSView) -> NSColor { neutral(dark(view) ? 0.50 : 0.70) }
    static func hover(_ view: NSView) -> NSColor { neutral(dark(view) ? 0.40 : 0.90) }
    static func line(_ view: NSView) -> NSColor { neutral(dark(view) ? 0.45 : 0.80) }
    static func text(_ view: NSView) -> NSColor { neutral(dark(view) ? 0.95 : 0.15) }
    static func muted(_ view: NSView) -> NSColor { neutral(dark(view) ? 0.70 : 0.50) }
}

@MainActor class Surface: NSView {
    var toolbarSurface = false
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) { (toolbarSurface ? Palette.field(self) : Palette.background(self)).setFill(); bounds.fill() }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true; subviews.forEach { $0.needsDisplay = true } }
}

@MainActor final class BrowserChromeWindow: NSWindow {
    private var frameBeforeFill: NSRect?

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, event.clickCount == 2,
           let contentView, !styleMask.contains(.fullScreen) {
            let pt = event.locationInWindow
            let contentTop = contentView.convert(contentView.bounds, to: nil).maxY
            // Leave the macOS window controls at the edges to AppKit.
            if pt.y >= contentTop, pt.x >= 96, pt.x <= frame.width - 24 {
                toggleFill()
                return
            }
        }
        super.sendEvent(event)
    }

    func toggleFill() {
        guard let screen, !styleMask.contains(.fullScreen) else { return }
        if let previous = frameBeforeFill, frame == screen.visibleFrame {
            frameBeforeFill = nil
            setFrame(constrainFrameRect(previous, to: screen), display: true)
            return
        }
        frameBeforeFill = frame
        setFrame(screen.visibleFrame, display: true)
    }
}

@MainActor final class DragSurface: Surface {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            (window as? BrowserChromeWindow)?.toggleFill()
        } else {
            window?.performDrag(with: event)
        }
    }
}

@MainActor final class RoundedField: NSTextField {
    var rightPadding: CGFloat = 12 { didSet { (cell as? PaddedFieldCell)?.rightPadding = rightPadding } }
    var isSearchField = false
    override init(frame: NSRect) {
        super.init(frame: frame)
        cell = PaddedFieldCell(textCell: "")
        isBordered = false; isBezeled = false; drawsBackground = false
        isEditable = true; isSelectable = true
        focusRingType = .none
        cell?.isScrollable = true
    }
    required init?(coder: NSCoder) { fatalError() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        let radius: CGFloat = isSearchField ? 12 : 6
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
        (isSearchField ? Palette.field(self) : Palette.address(self)).setFill(); shape.fill()
        let focused = currentEditor() != nil && window?.firstResponder === currentEditor()
        (focused ? Palette.neutral(Palette.dark(self) ? 0.80 : 0.30) : Palette.line(self)).setStroke(); shape.lineWidth = 1; shape.stroke()
        super.draw(dirtyRect)
    }
    override func viewDidMoveToWindow(){super.viewDidMoveToWindow();textColor=Palette.text(self)}
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance();textColor=Palette.text(self); needsDisplay = true }
}

@MainActor enum BrowserIdentity {
    static var version:String { Bundle.main.object(forInfoDictionaryKey:"SisuVersion") as? String ?? "alpha" }
    static var webKitBuild:String { Bundle(for:WKWebView.self).object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "system" }
    static var safariVersion:String? { Bundle(url:URL(fileURLWithPath:"/Applications/Safari.app"))?.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String }
    static var applicationName:String {
        // WKWebView's default identity omits Safari's browser-version tokens.
        // Use the installed Safari/WebKit compatibility version, retaining Sisu's
        // product identity. This does not claim Chrome APIs or provider support.
        if let safariVersion { return "Version/\(safariVersion) Safari/605.1.15 Sisu/\(version)" }
        return "Sisu/\(version)"
    }
}

@MainActor final class PaddedFieldCell: NSTextFieldCell {
    var rightPadding: CGFloat = 12
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        let height = min(rect.height,ceil((font?.ascender ?? 12) - (font?.descender ?? -3) + 2))
        return NSRect(x:rect.minX+12,y:rect.minY+(rect.height-height)/2,width:max(0,rect.width-12-rightPadding),height:height)
    }
    override func edit(withFrame rect:NSRect,in control:NSView,editor:NSText,delegate:Any?,event:NSEvent?) { super.edit(withFrame:drawingRect(forBounds:rect),in:control,editor:editor,delegate:delegate,event:event) }
    override func select(withFrame rect:NSRect,in control:NSView,editor:NSText,delegate:Any?,start:Int,length:Int) { super.select(withFrame:drawingRect(forBounds:rect),in:control,editor:editor,delegate:delegate,start:start,length:length) }
}

@MainActor final class Blocker {
    static let shared = Blocker()
    private(set) var ruleList: WKContentRuleList?
    private(set) var failure: String?
    private(set) var report: [String: Any] = [:]
    func prepare(_ completion: @escaping () -> Void) {
        guard let resources = Bundle.main.resourceURL,
              let bytes = try? Data(contentsOf: resources.appendingPathComponent("webkit-rules-report.json")),
              let report = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any],
              let hash = report["sha256"] as? String,
              let source = try? String(contentsOf: resources.appendingPathComponent("webkit-rules.json"), encoding: .utf8) else {
            failure = "The bundled blocking rules could not be read."
            completion(); return
        }
        self.report = report
        let id = "sisu-" + String(hash.prefix(24))
        let store = WKContentRuleListStore.default()!
        store.lookUpContentRuleList(forIdentifier: id) { [weak self] list, _ in
            if let list { self?.ruleList = list; completion(); return }
            store.compileContentRuleList(forIdentifier: id, encodedContentRuleList: source) { list, error in
                self?.ruleList = list
                self?.failure = error?.localizedDescription
                completion()
            }
        }
    }
}
