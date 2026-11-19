import AppKit
import WebKit

@MainActor final class Hairline: NSView {
    override func draw(_ dirtyRect: NSRect) { Palette.line(self).setFill(); bounds.fill() }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
}

/// Native settings page. Every option maps to public WebKit API or to Sisu's own
/// browser behaviour; nothing here is exposed to web content.
@MainActor final class SettingsView: Surface {
    weak var controller: BrowserWindow?
    private let scroll = NSScrollView()
    private let content = Surface()
    private enum Entry {
        case heading(NSTextField, Hairline?)
        case row(label: NSTextField, note: NSTextField?, controls: [NSView], field: RoundedField?)
        case caption(NSTextField)
    }
    private var entries: [Entry] = []
    private let title = NSTextField(labelWithString: "Settings")
    private let subtitle = NSTextField(labelWithString: "")
    private var refreshers: [(Preferences) -> Void] = []
    private var handlers: [ObjectIdentifier: () -> Void] = [:]
    private let widthField = RoundedField()
    private let agentField = RoundedField()

    init(controller: BrowserWindow) {
        self.controller = controller
        super.init(frame: .zero)
        scroll.documentView = content; scroll.drawsBackground = false
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        addSubview(scroll)
        title.font = NSFont(name: "Arial", size: 37); content.addSubview(title)
        subtitle.stringValue = controller.profile.isPrivate ? "Changes last for this private window." : "Preferences for this profile"
        subtitle.font = NSFont(name: "Arial", size: 14); subtitle.textColor = .secondaryLabelColor; content.addSubview(subtitle)
        build(controller)
        refreshChoices()
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: Content

    private func build(_ c: BrowserWindow) {
        let p = c.profile.preferences
        let onOff = ["On", "Off"]
        func toggle(_ name: String, _ note: String? = nil, _ key: WritableKeyPath<Preferences, Bool>) {
            choice(name, note, onOff, { $0[keyPath: key] ? 0 : 1 }) { [weak c] i in c?.update { $0[keyPath: key] = i == 0 } }
        }

        section("Appearance", first: true)
        choice("Color mode", nil, ["Dark", "Light", "System"], { ["dark", "light", "system"].firstIndex(of: $0.theme) }) { [weak c] i in
            c?.setTheme(["dark", "light", "system"][i])
        }
        choice("Tab placement", nil, ["Top", "Left"], { $0.placement == "left" ? 1 : 0 }) { [weak c] i in c?.setPlacement(i == 0 ? "top" : "left") }
        widthField.stringValue = String(p.sidebarWidth); widthField.alignment = .center
        widthField.font = NSFont(name: "Arial", size: 14)
        widthField.setAccessibilityLabel("Sidebar width in pixels")
        widthField.target = self; widthField.action = #selector(applyWidth)
        field("Sidebar width", "Left tabs, 92–350 px", widthField, fixedWidth: 100, [("Apply", { [weak self] in self?.applyWidth() })])
        let zooms = [75, 90, 100, 110, 125, 150]
        choice("Page zoom", "Default for every tab. ⌘+ and ⌘− still adjust one tab.", zooms.map { "\($0)%" }, { zooms.firstIndex(of: $0.pageZoom) }) { [weak c] i in
            c?.update(zoom: true) { $0.pageZoom = zooms[i] }
        }
        let fonts = [0, 9, 12, 14, 18, 24]
        choice("Minimum font size", "Never draw text smaller than this.", fonts.map { $0 == 0 ? "None" : "\($0)" }, { fonts.firstIndex(of: $0.minimumFontSize) }) { [weak c] i in
            c?.update { $0.minimumFontSize = fonts[i] }
        }

        section("Tabs and navigation")
        choice("Closing the last tab", nil, ["Opens a new tab", "Closes window"], { $0.lastTab == "closeWindow" ? 1 : 0 }) { [weak c] i in
            c?.update { $0.lastTab = i == 0 ? "newTab" : "closeWindow" }
        }
        choice("Search engine", nil, ["DuckDuckGo", "Google"], { $0.google ? 1 : 0 }) { [weak c] i in c?.setProvider(i == 1) }
        choice("Downloads", nil, ["Ask where to save", "Save to Downloads"], { $0.downloads == "downloads" ? 1 : 0 }) { [weak c] i in
            c?.update { $0.downloads = i == 0 ? "ask" : "downloads" }
        }
        toggle("Block pop-up windows", "Pop-ups opened by a click are still allowed.", \.blockPopups)
        toggle("Swipe between pages", "Two-finger swipe goes back and forward.", \.swipeNavigation)
        toggle("Pinch to zoom", nil, \.pinchZoom)
        toggle("Force Click previews", "Preview a link with a firm click.", \.linkPreview)
        toggle("Tab highlights each item", "Press Tab to move through links as well as fields.", \.tabFocusesLinks)

        section("Web content")
        toggle("JavaScript", "Takes effect when a page loads.", \.javaScript)
        toggle("Full-screen elements", "Lets videos and pages fill the screen.", \.fullscreen)
        toggle("Text selection", "Select and copy text on webpages.", \.textInteraction)
        toggle("Site compatibility fixes", "WebKit’s built-in fixes for known broken sites.", \.siteQuirks)
        toggle("Draw pages while loading", "Off waits until a page is ready. New tabs.", \.incrementalRendering)
        toggle("Print backgrounds", "Include page colours and images when printing.", \.printBackgrounds)

        section("Media")
        choice("Autoplay", "New tabs.", ["Allow all", "Stop sound", "Never"], { ["allow", "audio", "none"].firstIndex(of: $0.autoplay) }) { [weak c] i in
            c?.update { $0.autoplay = ["allow", "audio", "none"][i] }
        }
        toggle("AirPlay", "Send video to AirPlay devices. New tabs.", \.airPlay)
        choice("Camera and microphone", c.profile.isPrivate ? "Private windows always deny." : nil, ["Ask", "Deny"], { $0.camera == "deny" ? 1 : 0 }) { [weak c] i in
            c?.update { $0.camera = i == 0 ? "ask" : "deny" }
        }

        section("Writing")
        toggle("Inline predictions", "Suggested words while typing. New tabs.", \.inlinePredictions)

        section("Privacy and security")
        choice("Native blocking", "Reload open pages after changing blocking.", onOff, { $0.blocking ? 0 : 1 }) { [weak c] i in c?.setBlocking(i == 0) }
        toggle("Fraudulent website warning", "Warn before opening a suspected phishing or malware site.", \.fraudWarning)
        toggle("Lockdown Mode for websites", "Stricter WebKit protections; some sites may break. Takes effect when a page loads.", \.lockdown)
        actions("Website data", c.profile.isPrivate ? "Private data disappears when the window closes." : "Clearing all data signs you out of websites.",
                [("Clear cache", { [weak c] in c?.clearCache() }), ("Clear all data…", { [weak c] in c?.clearWebsiteData() })])
        if !c.profile.isPrivate {
            actions("Import", nil, [
                ("Cookies…", { [weak c] in c?.importCookies() }),
                ("Site shortcuts…", { (NSApp.delegate as? AppDelegate)?.importShortcuts() })
            ])
        }

        section("Extensions")
        actions("Chrome Web Store extensions", "macOS 15.4 or later, ordinary windows.", [("Manage Extensions…", { [weak c] in c?.manageExtensions() })])

        section("Developer")
        toggle("Web Inspector for every tab", "Inspect from Safari’s Develop menu. When off, allow it per tab from the ⋯ menu.", \.inspector)
        agentField.stringValue = p.userAgent
        agentField.placeholderString = "Default"
        agentField.font = NSFont(name: "Arial", size: 13)
        agentField.setAccessibilityLabel("Custom user agent")
        agentField.target = self; agentField.action = #selector(applyAgent)
        field("Custom user agent", "Leave empty for Sisu’s Safari-compatible identity.", agentField, fixedWidth: nil, [
            ("Apply", { [weak self] in self?.applyAgent() }),
            ("Reset", { [weak self] in self?.agentField.stringValue = ""; self?.applyAgent() })
        ])

        section("Sisu")
        actions("Browser tools", nil, [
            ("New private window", { (NSApp.delegate as? AppDelegate)?.newPrivateWindow() }),
            ("About Sisu", { (NSApp.delegate as? AppDelegate)?.about() })
        ])
        caption("Sisu \(Bundle.main.object(forInfoDictionaryKey: "SisuVersion") as? String ?? "alpha") · WebKit \(BrowserIdentity.webKitBuild) · Apache 2.0")
    }

    // MARK: Builders

    private func text(_ string: String, _ size: CGFloat, muted: Bool) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: string)
        field.font = NSFont(name: "Arial", size: size)
        field.textColor = muted ? .secondaryLabelColor : .labelColor
        field.isSelectable = false
        content.addSubview(field)
        return field
    }
    private func button(_ title: String, _ action: @escaping () -> Void) -> ChromeButton {
        let value = ChromeButton(title: title, target: self, action: #selector(run(_:)))
        value.outlined = true
        value.font = NSFont(name: "Arial", size: 13)
        value.lineBreakMode = .byTruncatingTail
        value.setAccessibilityLabel(title)
        handlers[ObjectIdentifier(value)] = action
        content.addSubview(value)
        return value
    }
    private func section(_ name: String, first: Bool = false) {
        let line = first ? nil : Hairline()
        if let line { content.addSubview(line) }
        entries.append(.heading(text(name, 14, muted: true), line))
    }
    private func choice(_ name: String, _ note: String?, _ options: [String], _ selected: @escaping (Preferences) -> Int?, _ apply: @escaping (Int) -> Void) {
        let buttons = options.enumerated().map { index, title in
            button(title) { [weak self] in apply(index); self?.refreshChoices() }
        }
        // Each option reads as a radio button so VoiceOver reports which one is chosen.
        for button in buttons { button.setAccessibilityLabel("\(name): \(button.title)"); button.setAccessibilityRole(.radioButton) }
        refreshers.append { prefs in
            let index = selected(prefs)
            for (i, button) in buttons.enumerated() {
                button.selectedStyle = i == index
                button.setAccessibilityValue(NSNumber(value: i == index ? 1 : 0))
            }
        }
        entries.append(.row(label: text(name, 14, muted: false), note: note.map { text($0, 12, muted: true) }, controls: buttons, field: nil))
    }
    private func actions(_ name: String, _ note: String?, _ items: [(String, () -> Void)]) {
        let buttons = items.map { button($0.0, $0.1) }
        entries.append(.row(label: text(name, 14, muted: false), note: note.map { text($0, 12, muted: true) }, controls: buttons, field: nil))
    }
    private func field(_ name: String, _ note: String?, _ field: RoundedField, fixedWidth: CGFloat?, _ items: [(String, () -> Void)]) {
        content.addSubview(field)
        let buttons = items.map { button($0.0, $0.1) }
        if let fixedWidth { field.frame.size.width = fixedWidth }
        field.tag = fixedWidth == nil ? 0 : 1
        entries.append(.row(label: text(name, 14, muted: false), note: note.map { text($0, 12, muted: true) }, controls: buttons, field: field))
    }
    private func caption(_ string: String) { entries.append(.caption(text(string, 13, muted: true))) }

    // MARK: Behaviour

    func refreshChoices() {
        guard let prefs = controller?.profile.preferences else { return }
        refreshers.forEach { $0(prefs) }
        if window?.firstResponder !== widthField.currentEditor() { widthField.stringValue = String(prefs.sidebarWidth) }
        if window?.firstResponder !== agentField.currentEditor() { agentField.stringValue = prefs.userAgent }
    }
    @objc private func run(_ sender: NSButton) { handlers[ObjectIdentifier(sender)]?() }
    @objc private func applyWidth() {
        guard let controller else { return }
        guard let width = Int(widthField.stringValue.trimmingCharacters(in: .whitespaces)), (92...350).contains(width) else {
            NSSound.beep(); widthField.stringValue = String(controller.profile.preferences.sidebarWidth); return
        }
        controller.setSidebarWidth(width)
    }
    @objc private func applyAgent() {
        let value = agentField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count <= 512, !value.contains(where: { $0.isNewline }) else { NSSound.beep(); return }
        agentField.stringValue = value
        controller?.update { $0.userAgent = value }
    }

    // MARK: Layout

    override func layout() {
        super.layout()
        scroll.frame = bounds
        let width = min(720, max(180, bounds.width - 48)), x = (bounds.width - width) / 2
        let stacked = width < 520
        let labelWidth = stacked ? width : width / 2 - 16
        let controlX = stacked ? x : x + width / 2
        let controlWidth = stacked ? width : width / 2
        var y: CGFloat = 28
        title.frame = NSRect(x: x, y: y, width: width, height: 48); y += 51
        subtitle.frame = NSRect(x: x, y: y, width: width, height: 22); y += 34
        func height(_ field: NSTextField, _ w: CGFloat) -> CGFloat {
            ceil(field.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: w, height: 1000)).height ?? 18)
        }
        for entry in entries {
            switch entry {
            case let .heading(label, line):
                if let line { y += 10; line.frame = NSRect(x: x, y: y, width: width, height: 1); y += 18 }
                label.frame = NSRect(x: x, y: y, width: width, height: 20); y += 30
            case let .caption(label):
                y += 12
                label.frame = NSRect(x: x, y: y, width: width, height: height(label, width)); y += label.frame.height
            case let .row(label, note, controls, field):
                let top = y
                label.frame = NSRect(x: x, y: y + (stacked ? 0 : 7), width: labelWidth, height: height(label, labelWidth))
                var labelBottom = label.frame.maxY
                if let note {
                    note.frame = NSRect(x: x, y: labelBottom + 2, width: labelWidth, height: height(note, labelWidth))
                    labelBottom = note.frame.maxY
                }
                var cy = stacked ? labelBottom + 8 : top
                var cx = controlX
                if let field {
                    let buttonsWidth = CGFloat(controls.count) * 94
                    let fieldWidth = field.tag == 1 ? 100 : max(80, controlWidth - buttonsWidth)
                    field.frame = NSRect(x: cx, y: cy, width: fieldWidth, height: 33)
                    cx += fieldWidth + 8
                    for button in controls { button.frame = NSRect(x: cx, y: cy, width: 86, height: 33); cx += 94 }
                    cy += 33
                } else if !controls.isEmpty {
                    let widest = controls.compactMap { ($0 as? NSButton)?.attributedTitle.size().width }.max() ?? 40
                    let fit = max(1, Int((controlWidth + 8) / (max(44, widest + 20) + 8)))
                    // When options wrap, balance the lines (3 + 3 rather than 5 + 1).
                    let lines = (controls.count + fit - 1) / fit
                    let columns = (controls.count + lines - 1) / lines
                    let buttonWidth = (controlWidth - CGFloat(columns - 1) * 8) / CGFloat(columns)
                    for (i, control) in controls.enumerated() {
                        let column = i % columns, line = i / columns
                        control.frame = NSRect(x: (controlX + CGFloat(column) * (buttonWidth + 8)).rounded(),
                                               y: cy + CGFloat(line) * 41, width: buttonWidth.rounded(.down), height: 33)
                    }
                    cy += CGFloat((controls.count + columns - 1) / columns) * 41 - 8
                }
                y = max(labelBottom, cy) + 16
            }
        }
        content.frame = NSRect(x: 0, y: 0, width: bounds.width, height: max(bounds.height, y + 28))
    }
}
