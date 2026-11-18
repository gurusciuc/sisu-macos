import AppKit
import WebKit

@available(macOS 15.4, *)
@MainActor final class ExtensionLibrary: NSObject, WKWebExtensionControllerDelegate {
    struct Receipt: Codable {
        let id: String
        let name: String
        let digest: String
        let storageID: UUID
    }
    struct Candidate {
        let id: String
        let data: Data
        let resources: StoreResources
        let ext: WKWebExtension
        let name: String
        @MainActor var hosts: Set<WKWebExtension.MatchPattern> {
            ext.requestedPermissionMatchPatterns.union(ext.allRequestedMatchPatterns)
        }
    }
    struct Loaded {
        let context: WKWebExtensionContext
        let resources: StoreResources
    }
    private static var libraries: [UUID:ExtensionLibrary] = [:]
    static func library(for profile: Profile) -> ExtensionLibrary? {
        guard !profile.isPrivate, let id = profile.store.identifier else { return nil }
        if let cached = libraries[id] { return cached }
        let library = ExtensionLibrary(profile:profile, id:id)
        libraries[id] = library
        library.restoreTask = Task { await library.restore() }
        return library
    }
    let controller: WKWebExtensionController
    private let root: URL
    private let profileID: UUID
    private(set) var records: [String:Receipt] = [:]
    private(set) var problems: [String:String] = [:]
    private(set) var loaded: [String:Loaded] = [:]
    private var restoreTask: Task<Void,Never>?
    private var busy: Set<String> = []
    private init(profile:Profile, id:UUID) {
        profileID = id
        root = profile.root.appendingPathComponent("Extensions",isDirectory:true)
        let config = WKWebExtensionController.Configuration(identifier:id)
        config.defaultWebsiteDataStore = profile.store
        controller = WKWebExtensionController(configuration:config)
        super.init()
        controller.delegate = self
    }
    func waitForRestore() async { await restoreTask?.value }
    func prepare(id:String, data:Data) async throws -> Candidate {
        let resources = try await Task.detached(priority:.userInitiated) { try StoreResources(package:data,id:id) }.value
        let ext = try await WKWebExtension(resourceBaseURL:resources.directory)
        if let error = ext.errors.first { throw ExtensionFailure("WebKit cannot load this extension: " + error.localizedDescription) }
        guard let name = ext.displayName, !name.isEmpty, name.count < 200, name.rangeOfCharacter(from:.controlCharacters) == nil else {
            throw ExtensionFailure("Invalid extension name.")
        }
        let manifest = ext.manifest
        let unsupported = ["theme","chrome_url_overrides","chrome_settings_overrides","side_panel","devtools_page","native_messaging","omnibox"]
        if let key = unsupported.first(where:{ manifest[$0] != nil }) { throw ExtensionFailure("This extension requires \(key), which Sisu does not support.") }
        // Reject required APIs the host does not provide, even when a WebKit version silently ignores them.
        let supported: Set<String> = ["activeTab","alarms","storage","tabs","scripting","webNavigation","webRequest","declarativeNetRequest","declarativeNetRequestWithHostAccess","declarativeNetRequestFeedback","unlimitedStorage","i18n"]
        let requested = Set(ext.requestedPermissions.map(\.rawValue))
        let missing = (manifest["permissions"] as? [String] ?? []).filter {
            $0 != "<all_urls>" && !$0.contains("://") && (!supported.contains($0) || !requested.contains($0))
        }
        if !missing.isEmpty {
            let features = missing.sorted().map { "chrome." + String($0.prefix(60)) }.joined(separator: ", ")
            throw ExtensionFailure("\(name) cannot run in this version of Sisu. It requires Chrome APIs that WebKit does not provide: \(features).")
        }
        return Candidate(id:id,data:data,resources:resources,ext:ext,name:name)
    }
    private func activate(_ candidate:Candidate, receipt:Receipt) throws {
        guard candidate.resources.digest == receipt.digest else { throw ExtensionFailure("The saved package changed. Remove it and install it again.") }
        let context = WKWebExtensionContext(for:candidate.ext)
        context.uniqueIdentifier = receipt.storageID.uuidString
        context.baseURL = URL(string:"webkit-extension://"+receipt.storageID.uuidString.lowercased()+"/")!
        context.hasAccessToPrivateData = false
        context.grantedPermissions = Dictionary(uniqueKeysWithValues:candidate.ext.requestedPermissions.map { ($0,Date.distantFuture) })
        context.grantedPermissionMatchPatterns = Dictionary(uniqueKeysWithValues:candidate.hosts.map { ($0,Date.distantFuture) })
        try controller.load(context)
        loaded[receipt.id] = Loaded(context:context,resources:candidate.resources)
    }
    private func restore() async {
        let manager = FileManager.default
        guard manager.fileExists(atPath:root.path) else { return }
        do {
            let dirs = try manager.contentsOfDirectory(at:root,includingPropertiesForKeys:nil)
            for dir in dirs where StoreListing.validID(dir.lastPathComponent) {
                let id = dir.lastPathComponent
                do {
                    let receipt = try JSONDecoder().decode(Receipt.self,from:Data(contentsOf:dir.appendingPathComponent("receipt.json")))
                    guard id == receipt.id else { throw ExtensionFailure("Invalid extension receipt.") }
                    records[id] = receipt
                    let package = try StoreListing.readPackage(dir.appendingPathComponent("package.crx"))
                    let candidate = try await prepare(id:id,data:package)
                    try activate(candidate,receipt:receipt)
                } catch { problems[id] = error.localizedDescription }
            }
        } catch { problems["Library"] = error.localizedDescription }
    }
    func install(id:String, in owner:BrowserWindow) async throws {
        await waitForRestore()
        guard records[id] == nil else { throw ExtensionFailure("This extension is already installed.") }
        guard busy.insert(id).inserted else { throw ExtensionFailure("This installation is already in progress.") }
        defer { busy.remove(id) }
        let candidate = try await prepare(id:id,data:try await StoreListing.download(id))
        guard let window = owner.window, window.isVisible else { return }
        let prompt = NSAlert()
        prompt.messageText = "Add “\(candidate.name)” to Sisu?"
        let permissions = candidate.ext.requestedPermissions.map(\.rawValue).sorted()
        let hosts = candidate.hosts.map(\.string).sorted()
        prompt.informativeText = "Chrome Web Store · " + (candidate.ext.displayVersion ?? candidate.ext.version ?? "") + "\n" + id
        let text = NSTextView(frame:NSRect(x:0,y:0,width:396,height:145))
        text.isEditable = false
        text.font = .systemFont(ofSize:13)
        text.string = "Permissions\n" + (permissions.isEmpty ? "None requested" : permissions.joined(separator:", ")) + "\n\nWebsite access\n" + (hosts.isEmpty ? "None requested" : hosts.joined(separator:"\n"))
        let scroll = NSScrollView(frame:text.frame)
        scroll.documentView = text; scroll.hasVerticalScroller = true
        text.isVerticallyResizable = true
        prompt.accessoryView = scroll
        prompt.addButton(withTitle:"Cancel"); prompt.addButton(withTitle:"Add Extension")
        guard await prompt.beginSheetModal(for:window) == .alertSecondButtonReturn else { return }
        try commit(candidate)
    }
    private func commit(_ candidate:Candidate) throws {
        let manager = FileManager.default, id = candidate.id
        try manager.createDirectory(at:root,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        let stage = root.appendingPathComponent(".install-"+UUID().uuidString)
        let final = root.appendingPathComponent(id)
        try manager.createDirectory(at:stage,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        defer { try? manager.removeItem(at:stage) }
        let receipt = Receipt(id:id,name:candidate.name,digest:candidate.resources.digest,storageID:UUID())
        try candidate.data.write(to:stage.appendingPathComponent("package.crx"))
        try JSONEncoder().encode(receipt).write(to:stage.appendingPathComponent("receipt.json"))
        try manager.moveItem(at:stage,to:final)
        do { try activate(candidate,receipt:receipt) }
        catch { try manager.removeItem(at:final); throw error }
        records[id] = receipt; problems[id] = nil
    }
    func remove(_ id:String) throws {
        guard StoreListing.validID(id) else { return }
        let manager = FileManager.default
        let dir = root.appendingPathComponent(id), trash = root.appendingPathComponent(".remove-"+UUID().uuidString)
        try manager.moveItem(at:dir,to:trash)
        do { if let item = loaded[id] { try controller.unload(item.context) } }
        catch { try manager.moveItem(at:trash,to:dir); throw error }
        loaded[id] = nil; records[id] = nil; problems[id] = nil
        try manager.removeItem(at:trash)
    }
    private var windows: [BrowserWindow] {
        ((NSApp.delegate as? AppDelegate)?.windows ?? []).filter { !$0.profile.isPrivate && $0.profile.store.identifier == profileID }
    }
    func webExtensionController(_ controller:WKWebExtensionController, openWindowsFor context:WKWebExtensionContext) -> [any WKWebExtensionWindow] { windows }
    func webExtensionController(_ controller:WKWebExtensionController, focusedWindowFor context:WKWebExtensionContext) -> (any WKWebExtensionWindow)? {
        windows.first(where:{$0.window?.isKeyWindow == true})
    }
    func webExtensionController(_ controller:WKWebExtensionController, presentActionPopup action:WKWebExtension.Action, for context:WKWebExtensionContext, completionHandler:@escaping (Error?) -> Void) {
        guard let owner = windows.first(where:{$0.window?.isKeyWindow == true}), let popover = action.popupPopover else {
            completionHandler(ExtensionFailure("Open an ordinary Sisu tab first.")); return
        }
        popover.behavior = .transient
        popover.show(relativeTo:owner.extensionButton.bounds,of:owner.extensionButton,preferredEdge:.maxY)
        completionHandler(nil)
    }
}

@available(macOS 15.4, *)
extension BrowserWindow: WKWebExtensionWindow {
    func tabs(for context: WKWebExtensionContext) -> [any WKWebExtensionTab] { core.ids.compactMap { tabs[$0] } }
    func activeTab(for context: WKWebExtensionContext) -> (any WKWebExtensionTab)? { current }
}
@available(macOS 15.4, *)
extension BrowserTab: WKWebExtensionTab {
    func webView(for context:WKWebExtensionContext) -> WKWebView? { web }
    func window(for context:WKWebExtensionContext) -> (any WKWebExtensionWindow)? { owner }
    func title(for context:WKWebExtensionContext) -> String? { title }
    func url(for context:WKWebExtensionContext) -> URL? { web?.url }
}
