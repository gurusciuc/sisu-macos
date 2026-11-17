import AppKit
import WebKit

@MainActor final class BrowserTab {
    let id: Int
    var title = "New Tab"
    var web: WKWebView?
    var native: NSView?
    var observations: [NSKeyValueObservation] = []
    var edited = false
    init(id: Int) { self.id = id }
}

@MainActor final class TabChip: Surface {
    let select: NSButton
    let close: NSButton
    var active = false
    var middleClose: (() -> Void)?
    init(id: Int, target: BrowserWindow) {
        select = NSButton(title: "New Tab", target: target, action: #selector(BrowserWindow.selectTab(_:)))
        close = iconButton("xmark", label: "Close tab", target: target, action: #selector(BrowserWindow.closeTab(_:)))
        super.init(frame: .zero)
        select.tag = id; close.tag = id
        select.isBordered = false; select.alignment = .left
        select.font = NSFont(name: "Helvetica Neue", size: 12)
        select.lineBreakMode = .byTruncatingTail
        addSubview(select); addSubview(close)
        middleClose = { [weak target] in target?.requestClose(id) }
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() { super.layout(); select.frame = NSRect(x: 10, y: 0, width: max(0, bounds.width-43), height: bounds.height); close.frame = NSRect(x: bounds.width-31, y: 2, width: 28, height: bounds.height-4) }
    override func otherMouseDown(with event: NSEvent) { if event.buttonNumber == 2 { middleClose?() } else { super.otherMouseDown(with: event) } }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if active {
            let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 7, yRadius: 7)
            Palette.field(self).setFill(); shape.fill(); Palette.line(self).setStroke(); shape.lineWidth = 1; shape.stroke()
        }
        select.contentTintColor = active ? Palette.text(self) : Palette.muted(self)
        close.contentTintColor = Palette.muted(self)
    }
}

@MainActor final class BrowserWindow: NSWindowController, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler, WKDownloadDelegate {
    let core = RustCore()
    let profile: Profile
    var tabs: [Int: BrowserTab] = [:]
    private let root = Surface()
    private let tabScroll = NSScrollView()
    private let tabDocument = Surface()
    private let toolbar = Surface()
    private let pages = Surface()
    private let address = NSTextField()
    private var chips: [Int: TabChip] = [:]
    private var buttons: [NSButton] = []
    private var boundsObserver: NSObjectProtocol?
    private var downloads: [ObjectIdentifier: WKDownload] = [:]
    private var allowWindowClose = false
    var current: BrowserTab? { core.selected.flatMap { tabs[$0] } }

    init(profile: Profile) {
        self.profile = profile
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 820), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = profile.isPrivate ? "Sisu · Private" : "Sisu"
        window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = false
        window.minSize = NSSize(width: 680, height: 460)
        window.delegate = self; window.contentView = root
        window.isReleasedWhenClosed = false
        tabScroll.documentView = tabDocument; tabScroll.drawsBackground = false
        tabScroll.hasVerticalScroller = false; tabScroll.hasHorizontalScroller = false
        tabScroll.autohidesScrollers = true
        root.addSubview(tabScroll); root.addSubview(toolbar); root.addSubview(pages)
        address.placeholderString = "Search or enter address"
        address.font = NSFont(name: "Helvetica Neue", size: 14)
        address.focusRingType = .none; address.bezelStyle = .roundedBezel
        address.target = self; address.action = #selector(commitAddress)
        address.setAccessibilityLabel("Address and search")
        toolbar.addSubview(address)
        buttons = [
            iconButton("chevron.left", label: "Back", target: self, action: #selector(back)),
            iconButton("chevron.right", label: "Forward", target: self, action: #selector(forward)),
            iconButton("arrow.clockwise", label: "Reload", target: self, action: #selector(reload)),
            iconButton("plus", label: "New tab", target: self, action: #selector(newTab)),
            iconButton("sidebar.left", label: "Toggle left tabs", target: self, action: #selector(togglePlacement)),
            iconButton("slider.horizontal.3", label: "Settings", target: self, action: #selector(openSettings))
        ]
        buttons.forEach { toolbar.addSubview($0) }
        root.postsFrameChangedNotifications = true
        boundsObserver = NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: root, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.layout() } }
        applyTheme(); window.center()
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { if let boundsObserver { NotificationCenter.default.removeObserver(boundsObserver) } }

    func start(urls: [String]) {
        if urls.isEmpty { _ = addTab() }
        else { for url in urls { _ = addTab(url: URL(string: url)) } }
        showWindow(nil); window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @discardableResult func addTab(url: URL? = nil, configuration: WKWebViewConfiguration? = nil) -> BrowserTab? {
        let result = core.call(["op": "new"])
        guard let id = result["selected"] as? Int else { showError("The tab limit has been reached."); return nil }
        let tab = BrowserTab(id: id); tabs[id] = tab
        if let configuration { attachWeb(to: tab, configuration: configuration) }
        else if let url { attachWeb(to: tab); tab.web?.load(URLRequest(url: url)) }
        else { tab.native = newTabView(); pages.addSubview(tab.native!) }
        refresh(); return tab
    }

    private func attachWeb(to tab: BrowserTab, configuration supplied: WKWebViewConfiguration? = nil) {
        tab.native?.removeFromSuperview(); tab.native = nil
        let config = supplied ?? WKWebViewConfiguration()
        // Popup configuration is supplied by WebKit, preserving opener context.
        if supplied == nil { config.websiteDataStore = profile.store }
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        config.preferences.isElementFullscreenEnabled = true
        let user = config.userContentController
        if supplied == nil {
        if profile.preferences.blocking, let rules = Blocker.shared.ruleList { user.add(rules) }
        let monitor = """
        (() => { const dirty = e => { if (e.isTrusted) webkit.messageHandlers.sisuWorkState.postMessage(true); };
        document.addEventListener('input', dirty, true); document.addEventListener('change', dirty, true); })();
        """
        user.addUserScript(WKUserScript(source: monitor, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: .defaultClient))
        // An isolated world reports edit state only. It exposes no native commands.
        user.add(WeakWorkHandler(self), contentWorld: .defaultClient, name: "sisuWorkState")
        }
        let web = WKWebView(frame: pages.bounds, configuration: config)
        web.navigationDelegate = self; web.uiDelegate = self
        web.allowsBackForwardNavigationGestures = true
        web.isInspectable = false
        tab.web = web; pages.addSubview(web)
        for path in [\WKWebView.title, \WKWebView.url] as [PartialKeyPath<WKWebView>] {
            if path == \WKWebView.title { tab.observations.append(web.observe(\.title, options: [.new]) { [weak self, weak tab] web, _ in
                MainActor.assumeIsolated { tab?.title = web.title?.isEmpty == false ? web.title! : web.url?.host ?? "Loading…"; self?.refreshTitles() }
            }) }
            else { tab.observations.append(web.observe(\.url, options: [.new]) { [weak self] _, _ in MainActor.assumeIsolated { self?.refreshAddress() } }) }
        }
        tab.observations.append(web.observe(\.isLoading, options: [.new]) { [weak self] _, _ in MainActor.assumeIsolated { self?.refreshAddress() } })
    }

    private func newTabView() -> NSView {
        let view = Surface()
        let title = NSTextField(labelWithString: "sisu")
        title.font = NSFont(name: "Helvetica Neue", size: 58)
        title.alignment = .center
        title.translatesAutoresizingMaskIntoConstraints = false
        let search = NSSearchField()
        search.placeholderString = "Search or enter an address"
        search.font = NSFont(name: "Helvetica Neue", size: 16)
        search.target = self; search.action = #selector(searchFromNewTab(_:))
        search.sendsWholeSearchString = true; search.sendsSearchStringImmediately = false
        search.translatesAutoresizingMaskIntoConstraints = false
        search.setAccessibilityLabel("New tab search")
        view.addSubview(title); view.addSubview(search)
        NSLayoutConstraint.activate([
            title.centerXAnchor.constraint(equalTo: view.centerXAnchor), title.bottomAnchor.constraint(equalTo: search.topAnchor, constant: -24),
            search.centerXAnchor.constraint(equalTo: view.centerXAnchor), search.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -10),
            search.widthAnchor.constraint(equalToConstant: 460), search.heightAnchor.constraint(equalToConstant: 42)
        ])
        return view
    }

    func layout() {
        let size = root.bounds.size
        let left = profile.preferences.placement == "left"
        let barHeight: CGFloat = 48
        let tabHeight: CGFloat = left ? size.height-96 : 38
        tabScroll.frame = left ? NSRect(x: 8, y: 96, width: 200, height: tabHeight) : NSRect(x: 88, y: 5, width: max(1,size.width-100), height: tabHeight)
        toolbar.frame = NSRect(x: 8, y: 46, width: size.width-16, height: barHeight)
        for (i, button) in buttons.enumerated() { button.frame = NSRect(x: i < 3 ? CGFloat(i)*36 : toolbar.bounds.width-CGFloat(6-i)*36, y: 7, width: 32, height: 32) }
        address.frame = NSRect(x: 112, y: 7, width: max(180,toolbar.bounds.width-228), height: 32)
        pages.frame = NSRect(x: left ? 216 : 0, y: 96, width: size.width-(left ? 216 : 0), height: max(1,size.height-96))
        let ids = core.ids
        let width = left ? 200 : min(208,max(120,(tabScroll.bounds.width-8)/CGFloat(max(1,ids.count))))
        tabDocument.frame = NSRect(x: 0, y: 0, width: left ? 200 : max(tabScroll.bounds.width,CGFloat(ids.count)*(width+4)), height: left ? max(tabScroll.bounds.height, CGFloat(ids.count)*40) : 38)
        for (i,id) in ids.enumerated() { chips[id]?.frame = NSRect(x: left ? 0 : CGFloat(i)*(width+4), y: left ? CGFloat(i)*40 : 0, width: width, height: 36) }
        for tab in tabs.values {
            for view in [tab.web as NSView?,tab.native].compactMap({$0}) {
                if view.frame != pages.bounds { view.frame = pages.bounds }
            }
        }
    }

    func refresh() {
        let ids = core.ids
        for id in chips.keys where !ids.contains(id) { chips.removeValue(forKey: id)?.removeFromSuperview() }
        for id in ids where chips[id] == nil { let chip = TabChip(id: id, target: self); chips[id] = chip; tabDocument.addSubview(chip) }
        for tab in tabs.values { tab.web?.isHidden = tab.id != core.selected; tab.native?.isHidden = tab.id != core.selected }
        refreshTitles(); refreshAddress(); layout()
    }
    private func refreshTitles() {
        for (id,tab) in tabs { chips[id]?.select.title = (tab.edited ? "• " : "") + tab.title; chips[id]?.active = id == core.selected; chips[id]?.needsDisplay = true }
        window?.title = (current?.title ?? "Sisu") + (profile.isPrivate ? " · Private · Sisu" : " · Sisu")
    }
    private func refreshAddress() {
        guard window?.firstResponder !== address.currentEditor() else { return }
        address.stringValue = current?.web?.url?.absoluteString ?? (current?.title == "Settings" ? "browser://settings" : "")
        buttons.first?.isEnabled = current?.web?.canGoBack == true
        if buttons.count > 1 { buttons[1].isEnabled = current?.web?.canGoForward == true }
    }

    @objc func newTab() { _ = addTab(); focusAddress() }
    @objc func selectTab(_ sender: NSButton) { select(sender.tag) }
    func select(_ id: Int) { _ = core.call(["op": "select", "id": id]); refresh(); if let web = current?.web { window?.makeFirstResponder(web) } }
    @objc func closeTab(_ sender: NSButton) { requestClose(sender.tag) }
    @objc func closeCurrent() { if let id = core.selected { requestClose(id) } }
    @objc func focusAddress() { window?.makeFirstResponder(address); address.selectText(nil) }
    @objc func commitAddress() { navigate(address.stringValue) }
    @objc func searchFromNewTab(_ sender: NSSearchField) { navigate(sender.stringValue) }
    func navigate(_ text: String) {
        if text == "browser://settings" { openSettings(); return }
        guard let url = core.destination(text, google: profile.preferences.google), let tab = current else { NSSound.beep(); return }
        if tab.web == nil { attachWeb(to: tab) }
        tab.web?.load(URLRequest(url: url)); refresh(); window?.makeFirstResponder(tab.web)
    }
    @objc func back() { current?.web?.goBack() }
    @objc func forward() { current?.web?.goForward() }
    @objc func reload() { current?.web?.reload() }
    @objc func zoomIn() { if let web = current?.web { web.pageZoom = min(3,web.pageZoom+0.1) } }
    @objc func zoomOut() { if let web = current?.web { web.pageZoom = max(0.5,web.pageZoom-0.1) } }
    @objc func zoomReset() { current?.web?.pageZoom = 1 }
    @objc func togglePlacement() { profile.preferences.placement = profile.preferences.placement == "top" ? "left" : "top"; savePreferences(); layout() }
    func setPlacement(_ value: String) { profile.preferences.placement = value; savePreferences(); layout() }
    func setTheme(_ value: String) { profile.preferences.theme = value; savePreferences(); applyTheme() }
    private func applyTheme() {
        window?.appearance = profile.preferences.theme == "system" ? nil : NSAppearance(named: profile.preferences.theme == "dark" ? .darkAqua : .aqua)
        root.needsDisplay = true; root.subviews.forEach { $0.needsDisplay = true }
    }
    private func savePreferences() { do { try profile.save() } catch { showError(error.localizedDescription) } }

    func confirmClose(_ tab: BrowserTab) -> Bool {
        guard tab.edited else { return true }
        let alert = NSAlert(); alert.messageText = "Close a tab with edits?"
        alert.informativeText = "Changes in “\(tab.title)” may not have been saved."
        alert.addButton(withTitle: "Keep Tab"); alert.addButton(withTitle: "Close Tab")
        return alert.runModal() == .alertSecondButtonReturn
    }
    func requestClose(_ id: Int, confirmed: Bool = false) {
        guard let tab = tabs[id], confirmed || confirmClose(tab) else { return }
        tab.observations.removeAll(); tab.web?.stopLoading()
        tab.web?.configuration.userContentController.removeScriptMessageHandler(forName: "sisuWorkState", contentWorld: .defaultClient)
        tab.web?.navigationDelegate = nil; tab.web?.uiDelegate = nil
        tab.web?.removeFromSuperview(); tab.native?.removeFromSuperview(); tabs.removeValue(forKey: id)
        _ = core.call(["op": "close", "id": id])
        if core.ids.isEmpty { allowWindowClose = true; window?.close() } else { refresh() }
    }
    func canCloseWindow() -> Bool { tabs.values.filter(\.edited).allSatisfy { confirmClose($0) } }
    func windowShouldClose(_ sender: NSWindow) -> Bool { allowWindowClose || canCloseWindow() }
    func windowWillClose(_ notification: Notification) { (NSApp.delegate as? AppDelegate)?.remove(self) }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.world == .defaultClient, message.body as? Bool == true,
              let tab = tabs.values.first(where: { $0.web === message.webView }) else { return }
        tab.edited = true; refreshTitles()
    }
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        tabs.values.first(where: {$0.web === webView})?.edited = false; refreshTitles()
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url, ["http","https","about"].contains(url.scheme?.lowercased() ?? "") else { decisionHandler(.cancel); return }
        decisionHandler(navigationAction.shouldPerformDownload ? .download : .allow)
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        decisionHandler(navigationResponse.canShowMIMEType ? .allow : .download)
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? { addTab(configuration: configuration)?.web }
    func webViewDidClose(_ webView: WKWebView) { if let tab = tabs.values.first(where: {$0.web === webView}) { requestClose(tab.id) } }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { showError("This page's process stopped. Reload it when you are ready; unsaved edits may be unavailable.") }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { if (error as NSError).code != NSURLErrorCancelled { showError(error.localizedDescription) } }
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = siteAlert(frame, message); alert.addButton(withTitle: "OK"); alert.runModal(); completionHandler()
    }
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = siteAlert(frame, message); alert.addButton(withTitle: "OK"); alert.addButton(withTitle: "Cancel"); completionHandler(alert.runModal() == .alertFirstButtonReturn)
    }
    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        let alert = siteAlert(frame, prompt); let field = NSTextField(string: defaultText ?? ""); field.frame = NSRect(x: 0, y: 0, width: 320, height: 26); alert.accessoryView = field
        alert.addButton(withTitle: "OK"); alert.addButton(withTitle: "Cancel"); completionHandler(alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil)
    }
    private func siteAlert(_ frame: WKFrameInfo, _ text: String) -> NSAlert { let alert = NSAlert(); alert.messageText = frame.request.url?.host ?? "Web page"; alert.informativeText = String(text.prefix(4000)); return alert }
    func showError(_ text: String) { let alert = NSAlert(); alert.messageText = "Sisu"; alert.informativeText = text; alert.runModal() }
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = parameters.allowsMultipleSelection; panel.canChooseDirectories = parameters.allowsDirectories
        panel.beginSheetModal(for: window!) { response in completionHandler(response == .OK ? panel.urls : nil) }
    }
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) { decisionHandler(profile.isPrivate ? .deny : .prompt) }
    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) { register(download) }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) { register(download) }
    private func register(_ download: WKDownload) { downloads[ObjectIdentifier(download)] = download; download.delegate = self }
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        let panel = NSSavePanel(); panel.nameFieldStringValue = URL(fileURLWithPath: suggestedFilename).lastPathComponent
        panel.beginSheetModal(for: window!) { answer in completionHandler(answer == .OK ? panel.url : nil); if answer != .OK { self.downloads.removeValue(forKey: ObjectIdentifier(download)) } }
    }
    func downloadDidFinish(_ download: WKDownload) { downloads.removeValue(forKey: ObjectIdentifier(download)) }
    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) { downloads.removeValue(forKey: ObjectIdentifier(download)); showError(error.localizedDescription) }

    @objc func openSettings() {
        if let tab = tabs.values.first(where: {$0.title == "Settings" && $0.web == nil}) { select(tab.id); return }
        guard let tab = addTab() else { return }
        tab.native?.removeFromSuperview(); tab.title = "Settings"
        let settings = SettingsView(controller: self); tab.native = settings; pages.addSubview(settings); refresh()
    }
    func snapshot() -> [String: Any] {
        ["tabs": core.ids, "selected": core.selected.map { $0 as Any } ?? NSNull(), "private": profile.isPrivate, "persistent": profile.store.isPersistent,
         "profileID": profile.store.identifier?.uuidString ?? "", "placement": profile.preferences.placement,
         "theme": profile.preferences.theme, "blocking": profile.preferences.blocking, "compiledRules": Blocker.shared.ruleList != nil,
         "viewport": ["width": pages.bounds.width,"height":pages.bounds.height], "edited":current?.edited ?? false,
         "webViews": tabs.values.filter({$0.web != nil}).count]
    }
}

@MainActor final class WeakWorkHandler: NSObject, WKScriptMessageHandler {
    weak var owner: BrowserWindow?
    init(_ owner: BrowserWindow) { self.owner = owner }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) { owner?.userContentController(userContentController, didReceive: message) }
}

@MainActor final class SettingsView: Surface {
    weak var controller: BrowserWindow?
    init(controller: BrowserWindow) {
        self.controller = controller; super.init(frame: .zero)
        let title = NSTextField(labelWithString: "Settings"); title.font = NSFont(name: "Helvetica Neue", size: 28); title.frame = NSRect(x: 48,y: 40,width: 600,height: 40); addSubview(title)
        let labels = ["Tabs", "Appearance", "Search engine", "Blocking"]
        for (i,text) in labels.enumerated() { let label = NSTextField(labelWithString:text); label.frame = NSRect(x:48,y:116+CGFloat(i)*64,width:180,height:26); addSubview(label) }
        for (i,values) in [["Top","Left"],["Dark","Light","System"],["DuckDuckGo","Google"]].enumerated() {
            let popup = NSPopUpButton(frame: NSRect(x:240,y:110+CGFloat(i)*64,width:220,height:32), pullsDown:false)
            popup.addItems(withTitles:values); popup.tag = i; popup.target=self; popup.action = #selector(change(_:)); popup.setAccessibilityLabel(labels[i])
            popup.selectItem(at:i == 0 ? (controller.profile.preferences.placement == "left" ? 1:0) : i == 1 ? (["dark","light","system"].firstIndex(of:controller.profile.preferences.theme) ?? 0) : (controller.profile.preferences.google ? 1:0)); addSubview(popup)
        }
        let block = NSButton(checkboxWithTitle:"Block ads and trackers", target:self, action:#selector(toggleBlocking(_:))); block.state = controller.profile.preferences.blocking ? .on : .off; block.frame = NSRect(x:240,y:302,width:260,height:30); addSubview(block)
        let note = NSTextField(wrappingLabelWithString:"WebKit preview uses a converted subset of the pinned blocking lists. Chrome extensions are not installed in this candidate.")
        note.textColor = .secondaryLabelColor; note.font = .systemFont(ofSize:12); note.frame = NSRect(x:48,y:390,width:540,height:60); addSubview(note)
        if controller.profile.isPrivate { let note = NSTextField(labelWithString:"Changes in this private window are temporary."); note.frame=NSRect(x:48,y:466,width:600,height:30); addSubview(note) }
    }
    required init?(coder:NSCoder){fatalError()}
    @objc func change(_ sender:NSPopUpButton){ guard let controller else{return}; switch sender.tag {
        case 0:controller.setPlacement(sender.indexOfSelectedItem == 1 ? "left":"top")
        case 1:controller.setTheme(["dark","light","system"][sender.indexOfSelectedItem])
        default:controller.profile.preferences.google=sender.indexOfSelectedItem == 1; try? controller.profile.save()
    }}
    @objc func toggleBlocking(_ sender:NSButton){ guard let controller else{return}; controller.profile.preferences.blocking=sender.state == .on
        for tab in controller.tabs.values { if let user=tab.web?.configuration.userContentController { user.removeAllContentRuleLists(); if sender.state == .on,let list=Blocker.shared.ruleList{user.add(list)} } }
        do{try controller.profile.save()}catch{controller.showError(error.localizedDescription)}
    }
}
