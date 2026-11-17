import AppKit
import WebKit

@MainActor final class RustCore {
    private let pointer: UnsafeMutableRawPointer
    init() { pointer = sisu_core_create()! }
    deinit { sisu_core_destroy(pointer) }
    func call(_ command: [String: Any]) -> [String: Any] {
        guard let data = try? JSONSerialization.data(withJSONObject: command) else { return [:] }
        return data.withUnsafeBytes { bytes in
            guard let response = sisu_core_command(pointer, bytes.bindMemory(to: UInt8.self).baseAddress, data.count) else { return [:] }
            defer { sisu_core_free(response) }
            let result = Data(String(cString: response).utf8)
            return (try? JSONSerialization.jsonObject(with: result)) as? [String: Any] ?? [:]
        }
    }
    var snapshot: [String: Any] { call(["op": "snapshot"]) }
    var ids: [Int] { snapshot["tabs"] as? [Int] ?? [] }
    var selected: Int? { snapshot["selected"] as? Int }
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
    static func background(_ view: NSView) -> NSColor { neutral(dark(view) ? 0.15 : 0.95) }
    static func field(_ view: NSView) -> NSColor { neutral(dark(view) ? 0.20 : 1.0) }
    static func line(_ view: NSView) -> NSColor { neutral(dark(view) ? 0.35 : 0.80) }
    static func text(_ view: NSView) -> NSColor { neutral(dark(view) ? 0.95 : 0.15) }
    static func muted(_ view: NSView) -> NSColor { neutral(dark(view) ? 0.70 : 0.50) }
}

@MainActor class Surface: NSView {
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) { Palette.background(self).setFill(); bounds.fill() }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true; subviews.forEach { $0.needsDisplay = true } }
}

@MainActor func iconButton(_ symbol: String, label: String, target: AnyObject, action: Selector) -> NSButton {
    let button = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: label)!, target: target, action: action)
    button.bezelStyle = .inline
    button.isBordered = false
    button.toolTip = label
    button.setAccessibilityLabel(label)
    button.contentTintColor = .labelColor
    return button
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
