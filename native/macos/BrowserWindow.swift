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
    let select: ChromeButton
    let close: ChromeButton
    private let icon = NSImageView()
    var onSelect: (() -> Void)?
    var active = false {
        didSet {
            guard oldValue != active else { return }
            close.isHidden = !active
            updateSelection()
        }
    }
    private var selectionAmount: CGFloat = 0
    private var selectionFade: ChromeFade?
    var middleClose: (() -> Void)?
    init(id: Int, target: BrowserWindow) {
        select = ChromeButton(title: "New Tab", target: target, action: #selector(BrowserWindow.selectTab(_:)))
        close = ChromeButton(symbol: .close, target: target, action: #selector(BrowserWindow.closeTab(_:)))
        super.init(frame: .zero)
        select.tag = id; close.tag = id
        select.alignment = .left; select.font = NSFont(name: "Arial", size: 13); select.hoverEnabled = false
        select.lineBreakMode = .byTruncatingTail
        close.setAccessibilityLabel("Close tab"); close.toolTip = "Close tab"
        close.isHidden = true
        icon.image = chromeImage(.page); icon.imageScaling = .scaleNone
        addSubview(icon); addSubview(select); addSubview(close)
        onSelect = { [weak target] in target?.select(id) }
        middleClose = { [weak target] in target?.requestClose(id) }
        select.onMiddleClick = middleClose; close.onMiddleClick = middleClose
    }
    required init?(coder: NSCoder) { fatalError() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === icon ? self : hit
    }
    override func mouseDown(with event: NSEvent) { onSelect?() }
    override func layout() {
        super.layout()
        icon.frame = NSRect(x: 10, y: 8, width: 16, height: 18)
        select.frame = NSRect(x: 32, y: 0, width: max(0, bounds.width-63), height: bounds.height)
        close.frame = NSRect(x: bounds.width-30, y: 5, width: 24, height: 24)
    }
    override func otherMouseDown(with event: NSEvent) { if event.buttonNumber == 2 { middleClose?() } else { super.otherMouseDown(with: event) } }
    private func updateSelection() {
        selectionFade?.stop()
        let amount: CGFloat = active ? 1 : 0
        if window == nil || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            selectionAmount = amount
            needsDisplay = true
            return
        }
        let fade = ChromeFade(from: selectionAmount, to: amount, seconds: 0.15) { [weak self] value in
            self?.selectionAmount = value
            self?.needsDisplay = true
        }
        selectionFade = fade
        fade.start()
    }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if selectionAmount > 0 {
            let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 7, yRadius: 7)
            Palette.tab(self).withAlphaComponent(selectionAmount).setFill()
            shape.fill()
            Palette.tabBorder(self).withAlphaComponent(selectionAmount).setStroke()
            shape.lineWidth = 1
            shape.stroke()
        }
        icon.contentTintColor = active ? Palette.text(self) : Palette.muted(self)
    }
}

@MainActor final class BrowserWindow: NSWindowController, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler, WKDownloadDelegate {
    let core = RustCore()
    let profile: Profile
    var tabs: [Int: BrowserTab] = [:]
    private let root = Surface()
    private let tabHeader = DragSurface()
    private let tabScroll = NSScrollView()
    private let tabDocument = Surface()
    private let toolbar = Surface()
    private let pages = Surface()
    private let address = RoundedField()
    private var chips: [Int: TabChip] = [:]
    private var buttons: [ChromeButton] = []
    private var blockingButton: ChromeButton!
    private let headerWordmark = NSTextField(labelWithString: "sisu")
    private var frameObservers: [NSObjectProtocol] = []
    private var downloads: [ObjectIdentifier: WKDownload] = [:]
    private var allowWindowClose = false
    var current: BrowserTab? { core.selected.flatMap { tabs[$0] } }

    init(profile: Profile) {
        self.profile = profile
        let window = BrowserChromeWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 820), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = profile.isPrivate ? "Sisu · Private" : "Sisu"
        window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = false
        window.tabbingMode = .disallowed
        window.minSize = NSSize(width: 680, height: 460)
        window.delegate = self; window.contentView = root
        window.isReleasedWhenClosed = false
        tabScroll.documentView = tabDocument; tabScroll.drawsBackground = false
        tabScroll.hasVerticalScroller = false; tabScroll.hasHorizontalScroller = false
        tabScroll.autohidesScrollers = true
        // Keep browser controls in the content view below AppKit's title bar.
        tabHeader.addSubview(tabScroll)
        root.addSubview(tabHeader); root.addSubview(toolbar); root.addSubview(pages)
        address.placeholderString = "Search or enter address"
        address.font = NSFont(name: "Arial", size: 15)
        address.focusRingType = .none
        address.target = self; address.action = #selector(commitAddress)
        address.setAccessibilityLabel("Address and search")
        toolbar.addSubview(address)
        func button(_ symbol: ChromeSymbol, _ label: String, _ action: Selector) -> ChromeButton {
            let value = ChromeButton(symbol: symbol, target: self, action: action)
            value.toolTip = label; value.setAccessibilityLabel(label); return value
        }
        buttons = [
            button(.back, "Back", #selector(back)),
            button(.forward, "Forward", #selector(forward)),
            button(.reload, "Reload", #selector(reload)),
            button(.plus, "New tab", #selector(newTab)),
            button(.placement, "Toggle left tabs", #selector(togglePlacement)),
            button(.more, "Browser menu", #selector(showMore))
        ]
        buttons.forEach { toolbar.addSubview($0) }
        toolbar.toolbarSurface = true
        blockingButton = ChromeButton(title: "Blocking on", symbol: .shield, target: self, action: #selector(toggleBlocking))
        blockingButton.toolTip = "Native blocking for this profile"
        toolbar.addSubview(blockingButton)
        headerWordmark.font = NSFont(name: "Arial", size: 14)
        tabHeader.addSubview(headerWordmark)
        root.postsFrameChangedNotifications = true
        frameObservers.append(NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: root, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.layout() } })
        applyTheme(); window.center()
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { for observer in frameObservers { NotificationCenter.default.removeObserver(observer) } }

    func start(urls: [String]) {
        if urls.isEmpty { _ = addTab() }
        else { for url in urls { _ = addTab(url: URL(string: url)) } }
        showWindow(nil); window?.makeKeyAndOrderFront(nil)
        applyTheme()
        NSApp.activate(ignoringOtherApps: true)
    }

    @discardableResult func addTab(url: URL? = nil, configuration: WKWebViewConfiguration? = nil) -> BrowserTab? {
        window?.makeFirstResponder(nil)
        let result = core.call(["op": "new"])
        guard let id = result["selected"] as? Int else { showError("The tab limit has been reached."); return nil }
        let tab = BrowserTab(id: id); tabs[id] = tab
        if let configuration { attachWeb(to: tab, configuration: configuration) }
        else if let url { attachWeb(to: tab); tab.web?.load(URLRequest(url: url)) }
        else { tab.native = newTabView(); pages.addSubview(tab.native!) }
        refresh()
        revealTab(id)
        return tab
    }

    private func attachWeb(to tab: BrowserTab, configuration supplied: WKWebViewConfiguration? = nil) {
        tab.native?.removeFromSuperview(); tab.native = nil
        let config = supplied ?? WKWebViewConfiguration()
        // Popup configuration is supplied by WebKit, preserving opener context.
        if supplied == nil { config.websiteDataStore = profile.store;config.applicationNameForUserAgent=BrowserIdentity.applicationName }
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

    private func newTabView() -> NSView { NewTabView(controller: self) }

    func layout() {
        let size = root.bounds.size
        let headerHeight: CGFloat = 47
        let toolbarHeight: CGFloat = 52
        let left = profile.preferences.placement == "left"
        let side: CGFloat = left ? min(CGFloat(profile.preferences.sidebarWidth), size.width/2) : 0
        let ids = core.ids
        tabHeader.frame = NSRect(x: 0, y: 0, width: size.width, height: headerHeight)
        let owner: NSView = left ? root : tabHeader
        if tabScroll.superview !== owner { tabScroll.removeFromSuperview(); owner.addSubview(tabScroll) }
        let headerWidth = tabHeader.bounds.width
        let tabRowWidth = max(1, headerWidth-100)
        let availablePerTab = tabRowWidth / CGFloat(max(1, ids.count)) - 4
        let width = left ? max(1, side-18) : min(200, max(112, availablePerTab))
        let tabExtent = CGFloat(ids.count) * (left ? 37 : width+4)
        let tabScrollTop = headerHeight + 8
        tabScroll.frame = left
            ? NSRect(x: 8, y: tabScrollTop, width: max(1, side-18), height: max(1, size.height-tabScrollTop-46))
            : NSRect(x: 12, y: 7, width: max(1, min(tabRowWidth, tabExtent)), height: 34)
        headerWordmark.isHidden = !left
        headerWordmark.frame = NSRect(x: 12,y: 11,width: 160,height: 26)
        toolbar.frame = NSRect(x: side, y: headerHeight, width: size.width-side, height: toolbarHeight)
        for i in 0..<3 { buttons[i].frame = NSRect(x: 10+CGFloat(i)*34,y: 9,width: 31,height: 32) }
        let navWidth=toolbar.bounds.width,protectWidth:CGFloat=navWidth>630 ? 124:36
        buttons[5].frame=NSRect(x:navWidth-43,y:9,width:32,height:32)
        blockingButton.frame=NSRect(x:navWidth-50-protectWidth,y:9,width:protectWidth,height:32)
        blockingButton.imagePosition=protectWidth>40 ? .imageLeading:.imageOnly
        address.frame=NSRect(x:122,y:8,width:max(55,navWidth-61-protectWidth-122),height:35)
        let contentTop = headerHeight + toolbarHeight
        pages.frame = NSRect(x: side, y: contentTop, width: size.width-side, height: max(1, size.height-contentTop))
        tabDocument.frame = NSRect(x: 0, y: 0,
            width: left ? width : max(tabScroll.bounds.width, tabExtent),
            height: left ? max(tabScroll.bounds.height, tabExtent) : 34)
        for (i,id) in ids.enumerated() {
            guard let chip=chips[id] else { continue }
            let frame=NSRect(x:left ? 0:CGFloat(i)*(width+4),y:left ? CGFloat(i)*37:0,width:width,height:34)
            if chip.frame != frame { chip.frame=frame;chip.needsLayout=true;chip.layoutSubtreeIfNeeded() }
        }
        let plusOwner:NSView=left ? root:tabHeader
        if buttons[3].superview !== plusOwner { buttons[3].removeFromSuperview();plusOwner.addSubview(buttons[3]) }
        if buttons[4].superview !== tabHeader { buttons[4].removeFromSuperview();tabHeader.addSubview(buttons[4]) }
        buttons[3].frame = NSRect(
            x: left ? 9 : min(tabScroll.frame.maxX,12+tabExtent),
            y: left ? min(tabScroll.frame.maxY,tabScrollTop+tabExtent) : 8,
            width: 32, height: 32)
        buttons[4].frame=NSRect(x:headerWidth-43,y:8,width:34,height:32)
        for tab in tabs.values {
            for view in [tab.web as NSView?,tab.native].compactMap({$0}) {
                if view.frame != pages.bounds { view.frame=pages.bounds;view.needsLayout=true;view.layoutSubtreeIfNeeded() }
            }
        }
    }

    func refresh() {
        let ids = core.ids
        for id in chips.keys where !ids.contains(id) { chips.removeValue(forKey: id)?.removeFromSuperview() }
        for id in ids where chips[id] == nil { let chip = TabChip(id: id, target: self); chips[id] = chip; tabDocument.addSubview(chip) }
        for tab in tabs.values { tab.web?.isHidden = tab.id != core.selected; tab.native?.isHidden = tab.id != core.selected }
        refreshTitles(); refreshAddress(); refreshBlocking(); layout()
    }
    private func refreshTitles() {
        for (id, tab) in tabs {
            guard let chip = chips[id] else { continue }
            chip.select.title = (tab.edited ? "• " : "") + tab.title
            chip.select.setAccessibilityLabel(tab.edited ? "\(tab.title), unsaved edits" : tab.title)
            chip.active = id == core.selected
            chip.needsDisplay = true
        }
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
    private func revealTab(_ id: Int) {
        if let chip = chips[id] { chip.scrollToVisible(chip.bounds) }
    }
    func select(_ id: Int) {
        guard tabs[id] != nil else { return }
        if id != core.selected { window?.makeFirstResponder(nil) }
        _ = core.call(["op": "select", "id": id])
        refresh()
        revealTab(id)
        if let web = current?.web { window?.makeFirstResponder(web) }
    }
    @objc func closeTab(_ sender: NSButton) { requestClose(sender.tag) }
    @objc func closeCurrent() { if let id = core.selected { requestClose(id) } }
    @objc func focusAddress() { window?.makeFirstResponder(address); address.selectText(nil) }
    @objc func commitAddress() { navigate(address.stringValue) }
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
    @objc func togglePlacement() { setPlacement(profile.preferences.placement == "top" ? "left" : "top") }
    func setPlacement(_ value: String) {
        profile.preferences.placement = value
        savePreferences()
        layout()
        if let id = core.selected { revealTab(id) }
    }
    func setTheme(_ value: String) { profile.preferences.theme = value; savePreferences(); applyTheme() }
    func setSidebarWidth(_ value: Int) { profile.preferences.sidebarWidth=min(350,max(92,value));savePreferences();layout() }
    func setProvider(_ google: Bool) {
        profile.preferences.google=google;savePreferences()
        for tab in tabs.values { (tab.native as? NewTabView)?.updateProvider() }
    }
    func setBlocking(_ enabled: Bool) {
        profile.preferences.blocking=enabled
        for tab in tabs.values {
            if let user=tab.web?.configuration.userContentController {
                user.removeAllContentRuleLists()
                if enabled,let list=Blocker.shared.ruleList { user.add(list) }
            }
        }
        savePreferences();refreshBlocking()
    }
    private func refreshBlocking() {
        guard blockingButton != nil else { return }
        blockingButton.title=current?.web == nil ? "Local page":(profile.preferences.blocking ? "Blocking on":"Blocking off")
        blockingButton.isEnabled=current?.web != nil
        blockingButton.setAccessibilityLabel(blockingButton.title)
    }
    @objc private func toggleBlocking() { setBlocking(!profile.preferences.blocking) }
    @objc private func showMore() {
        let menu=NSMenu()
        for (title,action) in [("New tab",#selector(newTab)),("New window",#selector(openOtherWindow)),("New private window",#selector(openPrivateWindow)),("Settings",#selector(openSettings)),("Top / left tabs",#selector(togglePlacement)),("About Sisu",#selector(showAbout))] {
            let item=NSMenuItem(title:title,action:action,keyEquivalent:"");item.target=self;menu.addItem(item)
        }
        menu.popUp(positioning:nil,at:NSPoint(x:0,y:buttons[5].bounds.height),in:buttons[5])
    }
    @objc private func openOtherWindow() { (NSApp.delegate as? AppDelegate)?.newWindow() }
    @objc private func openPrivateWindow() { (NSApp.delegate as? AppDelegate)?.newPrivateWindow() }
    @objc func importCookies() {
        if let window { CookieImporter.choose(in: window, profile: profile) }
    }
    @objc private func showAbout() { (NSApp.delegate as? AppDelegate)?.about() }
    private func applyTheme() {
        window?.appearance = profile.preferences.theme == "system" ? nil : NSAppearance(named: profile.preferences.theme == "dark" ? .darkAqua : .aqua)
        window?.backgroundColor = Palette.background(root)
        root.needsDisplay = true; root.subviews.forEach { $0.needsDisplay = true }
        headerWordmark.textColor=Palette.text(tabHeader)
        tabHeader.needsDisplay=true;tabDocument.needsDisplay=true
        for tab in tabs.values { tab.native?.needsDisplay=true;tab.native?.needsLayout=true }
        refreshTitles()
    }
    func savePreferences() { do { try profile.save() } catch { showError(error.localizedDescription) } }

    func confirmClose(_ tab: BrowserTab) -> Bool {
        guard tab.edited else { return true }
        let alert = NSAlert(); alert.messageText = "Close a tab with edits?"
        alert.informativeText = "Changes in “\(tab.title)” may not have been saved."
        alert.addButton(withTitle: "Keep Tab"); alert.addButton(withTitle: "Close Tab")
        return alert.runModal() == .alertSecondButtonReturn
    }
    func requestClose(_ id: Int, confirmed: Bool = false) {
        guard let tab = tabs[id], confirmed || confirmClose(tab) else { return }
        if id == core.selected { window?.makeFirstResponder(nil) }
        tab.observations.removeAll(); tab.web?.stopLoading()
        // Popups can share this controller with the opener. Its handler
        // holds a weak reference and stays active until the controller dies.
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
