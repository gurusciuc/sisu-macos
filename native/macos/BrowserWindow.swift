import AppKit
import WebKit

@MainActor final class BrowserTab: NSObject {
    weak var owner: BrowserWindow?
    var committedURL: URL?
    var allowedCleartextOrigin: String?
    var secureProvisionalLoad = false
    let id: Int
    var title = "New Tab"
    var web: WKWebView?
    var native: NSView?
    var observations: [NSKeyValueObservation] = []
    var edited = false
    init(id: Int) { self.id = id }
}

@MainActor final class TabSelectionButton: ChromeButton {
    var tabOutline: NSBezierPath {
        NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 7, yRadius: 7)
    }

    override func draw(_ dirtyRect: NSRect) {
        if isHighlighted {
            Palette.hover(self).setFill()
            tabOutline.fill()
        }
        guard let cell = cell as? NSButtonCell else { return }
        var labelFrame = cell.titleRect(forBounds: bounds)
        labelFrame.origin.x = 32
        labelFrame.size.width = max(0, bounds.width - labelFrame.minX - 31)
        cell.drawTitle(attributedTitle, withFrame: labelFrame, in: self)
    }
}

@MainActor final class TabChip: Surface {
    let select: TabSelectionButton
    let close: ChromeButton
    private let icon = NSImageView()
    var active = false {
        didSet {
            guard oldValue != active else { return }
            close.isHidden = !active
            updateSelection()
        }
    }
    private var selectionAmount: CGFloat = 0
    private var selectionFade: ChromeFade?
    init(id: Int, target: BrowserWindow) {
        select = TabSelectionButton(title: "New Tab", target: target, action: #selector(BrowserWindow.selectTab(_:)))
        close = ChromeButton(symbol: .close, target: target, action: #selector(BrowserWindow.closeTab(_:)))
        super.init(frame: .zero)
        select.tag = id; close.tag = id
        select.alignment = .left; select.font = NSFont(name: "Arial", size: 13); select.hoverEnabled = false
        select.lineBreakMode = .byTruncatingTail
        close.setAccessibilityLabel("Close tab"); close.toolTip = "Close tab"
        close.isHidden = true
        icon.image = chromeImage(.page); icon.imageScaling = .scaleNone
        addSubview(select); addSubview(icon); addSubview(close)
        select.onMiddleClick = { [weak target] in target?.requestClose(id) }
        close.onMiddleClick = select.onMiddleClick
    }
    required init?(coder: NSCoder) { fatalError() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === icon ? select : hit
    }
    override func layout() {
        super.layout()
        icon.frame = NSRect(x: 10, y: 8, width: 16, height: 18)
        select.frame = bounds
        close.frame = NSRect(x: bounds.width-30, y: 5, width: 24, height: 24)
    }
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
            let shape = select.tabOutline
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
    private let cleartextLabel = NSTextField(labelWithString: "Not Secure")
    private var chips: [Int: TabChip] = [:]
    private var buttons: [ChromeButton] = []
    lazy var extensionButton = ChromeButton(title: "", symbol: nil, target: self, action: #selector(extensionButtonPressed))
    var isInstallingExtension = false
    private var blockingButton: ChromeButton!
    private let headerWordmark = NSTextField(labelWithString: "sisu")
    private var frameObservers: [NSObjectProtocol] = []
    private var downloads: [ObjectIdentifier: WKDownload] = [:]
    private var downloadDestinations: [ObjectIdentifier: URL] = [:]
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
        cleartextLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        cleartextLabel.alignment = .center
        cleartextLabel.isHidden = true
        cleartextLabel.toolTip = "This page uses unencrypted HTTP."
        cleartextLabel.setAccessibilityLabel("Not secure, unencrypted HTTP")
        toolbar.addSubview(cleartextLabel)
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
        extensionButton.image = NSImage(systemSymbolName:"puzzlepiece.extension",accessibilityDescription:"Extensions")
        extensionButton.imagePosition = .imageOnly; extensionButton.isHidden = profile.isPrivate
        if #unavailable(macOS 15.4) { extensionButton.isHidden = true }
        toolbar.addSubview(extensionButton)
        headerWordmark.font = NSFont(name: "Arial", size: 14)
        tabHeader.addSubview(headerWordmark)
        root.postsFrameChangedNotifications = true
        frameObservers.append(NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: root, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.layout() } })
        applyTheme(); window.center()
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { for observer in frameObservers { NotificationCenter.default.removeObserver(observer) } }

    func start(urls: [String]) {
        if #available(macOS 15.4,*) { ExtensionLibrary.library(for:profile)?.controller.didOpenWindow(self) }
        if urls.isEmpty { _ = addTab() }
        else { for url in urls { _ = addTab(url: URL(string: url)) } }
        showWindow(nil); window?.makeKeyAndOrderFront(nil)
        applyTheme()
        NSApp.activate(ignoringOtherApps: true)
    }

    @discardableResult func addTab(url: URL? = nil, configuration: WKWebViewConfiguration? = nil) -> BrowserTab? {
        window?.makeFirstResponder(nil)
        let previous = current
        let result = core.call(["op": "new"])
        guard let id = result["selected"] as? Int else { showError("The tab limit has been reached."); return nil }
        let tab = BrowserTab(id: id); tab.owner = self; tabs[id] = tab
        if let configuration { attachWeb(to: tab, configuration: configuration) }
        else if let url { attachWeb(to: tab); loadAddress(url, in: tab) }
        else { tab.native = newTabView(); pages.addSubview(tab.native!) }
        refresh()
        revealTab(id)
        if #available(macOS 15.4,*), let library = ExtensionLibrary.library(for:profile) {
            library.controller.didOpenTab(tab); library.controller.didActivateTab(tab,previousActiveTab:previous)
        }
        return tab
    }

    private func attachWeb(to tab: BrowserTab, configuration supplied: WKWebViewConfiguration? = nil) {
        tab.native?.removeFromSuperview(); tab.native = nil
        let config = supplied ?? WKWebViewConfiguration()
        // Popup configuration is supplied by WebKit, preserving opener context.
        if supplied == nil { config.websiteDataStore = profile.store;config.applicationNameForUserAgent=BrowserIdentity.applicationName }
        if #available(macOS 15.4,*), supplied == nil {
            config.webExtensionController = ExtensionLibrary.library(for:profile)?.controller
        }
        WebSettings.configure(config, profile.preferences, supplied: supplied != nil)
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
        web.isInspectable = false
        WebSettings.apply(web, profile.preferences, zoom: true)
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
        let extensionWidth:CGFloat = extensionButton.isHidden ? 0 : extensionButton.title.isEmpty ? 34 : 100
        extensionButton.frame = NSRect(x:blockingButton.frame.minX-extensionWidth-4,y:9,width:extensionWidth,height:32)
        let warningWidth: CGFloat = cleartextLabel.isHidden ? 0 : 82
        cleartextLabel.frame = NSRect(x:122,y:17,width:warningWidth,height:16)
        let addressStart = 122 + warningWidth
        address.frame = NSRect(x:addressStart,y:8,width:max(55,navWidth-61-protectWidth-extensionWidth-addressStart),height:35)
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
        updateExtensionButton()
        let isHTTP = current?.committedURL?.scheme?.lowercased() == "http"
        if cleartextLabel.isHidden == isHTTP {
            cleartextLabel.isHidden = !isHTTP
            layout()
        }
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
        let previous = current
        _ = core.call(["op": "select", "id": id])
        if #available(macOS 15.4,*), let tab = current, tab !== previous {
            ExtensionLibrary.library(for:profile)?.controller.didActivateTab(tab,previousActiveTab:previous)
        }
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
        loadAddress(url, in: tab); refresh(); window?.makeFirstResponder(tab.web)
    }
    private func loadAddress(_ url: URL, in tab: BrowserTab) {
        tab.allowedCleartextOrigin = NavigationSecurity.cleartextOrigin(url)
        tab.secureProvisionalLoad = url.scheme?.lowercased() == "https"
        tab.web?.load(URLRequest(url: url))
    }
    @objc func allowPageInspection() {
        guard let web = current?.web else { return }
        web.isInspectable.toggle()
        if web.isInspectable {
            let alert = NSAlert()
            alert.messageText = "Web Inspector is available for this tab"
            alert.informativeText = "In Safari, enable developer features in Settings → Advanced. Then choose this Sisu page from Safari’s Develop menu."
            alert.addButton(withTitle: "OK")
            if let window { alert.beginSheetModal(for: window) }
        }
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
    /// Changes preferences, saves them and pushes the live options to every open tab.
    func update(zoom: Bool = false, _ change: (inout Preferences) -> Void) {
        let previous = profile.preferences
        change(&profile.preferences)
        applyLive(from: previous, zoom: zoom)
        savePreferences()
    }
    /// Another window of the same profile saved new preferences.
    func adopt(_ preferences: Preferences) {
        let previous = profile.preferences
        profile.preferences = preferences
        if previous.blocking != preferences.blocking { setBlocking(preferences.blocking, save: false) }
        applyLive(from: previous, zoom: previous.pageZoom != preferences.pageZoom)
        for tab in tabs.values {
            (tab.native as? NewTabView)?.updateProvider()
            (tab.native as? SettingsView)?.refreshChoices()
        }
        applyTheme(); layout(); refreshBlocking()
    }
    private func applyLive(from previous: Preferences, zoom: Bool) {
        let p = profile.preferences
        for web in tabs.values.compactMap(\.web) {
            WebSettings.apply(web, p, zoom: zoom)
            if previous.inspector, !p.inspector { web.isInspectable = false }
            // A page may already hold a grant; stop live capture when access is denied.
            if previous.camera != "deny", p.camera == "deny" {
                web.setCameraCaptureState(.none); web.setMicrophoneCaptureState(.none)
            }
        }
    }
    @objc func clearCache() {
        let types: Set<String> = [WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache, WKWebsiteDataTypeFetchCache, WKWebsiteDataTypeOfflineWebApplicationCache]
        profile.store.removeData(ofTypes: types, modifiedSince: .distantPast) { [weak self] in
            self?.showNotice("Cache cleared", "Pages will load fresh copies from the network.")
        }
    }
    @objc func clearWebsiteData() {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = "Clear all website data?"
        alert.informativeText = "Cookies, caches, local storage and other website data for this profile will be removed. You will be signed out of websites. This can’t be undone."
        alert.addButton(withTitle: "Clear All Data"); alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            self.profile.store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) { [weak self] in
                self?.showNotice("Website data cleared", "Reload open pages to start fresh.")
            }
        }
    }
    @objc func printPage() {
        guard let web = current?.web, let window else { NSSound.beep(); return }
        let operation = web.printOperation(with: NSPrintInfo.shared)
        operation.view?.frame = web.bounds
        operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }
    private func showNotice(_ title: String, _ text: String) {
        guard let window, window.attachedSheet == nil else { return }
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = text
        alert.addButton(withTitle: "OK"); alert.beginSheetModal(for: window)
    }
    func setSidebarWidth(_ value: Int) { profile.preferences.sidebarWidth=min(350,max(92,value));savePreferences();layout() }
    func setProvider(_ google: Bool) {
        profile.preferences.google=google;savePreferences()
        for tab in tabs.values { (tab.native as? NewTabView)?.updateProvider() }
    }
    func setBlocking(_ enabled: Bool, save: Bool = true) {
        profile.preferences.blocking=enabled
        for tab in tabs.values {
            if let user=tab.web?.configuration.userContentController {
                user.removeAllContentRuleLists()
                if enabled,let list=Blocker.shared.ruleList { user.add(list) }
            }
        }
        if save { savePreferences() }
        refreshBlocking()
    }
    private func refreshBlocking() {
        guard blockingButton != nil else { return }
        blockingButton.title=current?.web == nil ? "Local page":(profile.preferences.blocking ? "Blocking on":"Blocking off")
        blockingButton.isEnabled=current?.web != nil
        blockingButton.toolTip=current?.web == nil ? "Blocking applies to webpages, not Sisu’s own pages" : "Native blocking for this profile"
        blockingButton.setAccessibilityLabel(blockingButton.title)
    }
    @objc private func toggleBlocking() { setBlocking(!profile.preferences.blocking) }
    @objc private func showMore() {
        let menu=NSMenu()
        for (title,action) in [("New tab",#selector(newTab)),("New window",#selector(openOtherWindow)),("New private window",#selector(openPrivateWindow)),("Settings",#selector(openSettings)),("Top / left tabs",#selector(togglePlacement)),(current?.web?.isInspectable == true ? "Disable Web Inspector" : "Allow Web Inspector",#selector(allowPageInspection)),("About Sisu",#selector(showAbout))] {
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
    func savePreferences() {
        do { try profile.save() } catch { showError(error.localizedDescription) }
        for tab in tabs.values { (tab.native as? SettingsView)?.refreshChoices() }
        // Ordinary windows share one preferences file; keep their copies in step.
        guard !profile.isPrivate else { return }
        for other in (NSApp.delegate as? AppDelegate)?.windows ?? [] where other !== self && !other.profile.isPrivate {
            other.adopt(profile.preferences)
        }
    }

    var editedTabCount: Int { tabs.values.filter(\.edited).count }

    func requestClose(_ id: Int) {
        guard let tab = tabs[id] else { return }
        if tab.edited && !confirmDiscard(count: 1, action: "Close Tab") { return }
        let previous = current
        if id == core.selected { window?.makeFirstResponder(nil) }
        if #available(macOS 15.4,*) { ExtensionLibrary.library(for:profile)?.controller.didCloseTab(tab) }
        detach(tab)
        tabs.removeValue(forKey: id)
        _ = core.call(["op": "close", "id": id])
        if core.ids.isEmpty {
            if profile.preferences.lastTab == "closeWindow" {
                allowWindowClose = true
                window?.close()
            } else {
                // Keep the browser open: the last closed tab becomes a fresh new tab page.
                newTab()
            }
        } else {
            if #available(macOS 15.4,*), let current, previous !== current {
                ExtensionLibrary.library(for:profile)?.controller.didActivateTab(current,previousActiveTab:previous)
            }
            refresh()
        }
    }

    private func detach(_ tab: BrowserTab) {
        tab.observations.removeAll()
        tab.web?.stopLoading()
        tab.web?.navigationDelegate = nil
        tab.web?.uiDelegate = nil
        tab.web?.removeFromSuperview()
        tab.web = nil
        tab.native?.removeFromSuperview()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        allowWindowClose || confirmDiscard(count: editedTabCount, action: "Close Window")
    }
    func windowWillClose(_ notification: Notification) {
        if #available(macOS 15.4,*) { ExtensionLibrary.library(for:profile)?.controller.didCloseWindow(self) }
        for tab in tabs.values { detach(tab) }
        (NSApp.delegate as? AppDelegate)?.remove(self)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.world == .defaultClient, message.body as? Bool == true,
              let tab = tabs.values.first(where: { $0.web === message.webView }) else { return }
        tab.edited = true; refreshTitles()
    }
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        if let tab = tabs.values.first(where: {$0.web === webView}) {
            tab.edited = false
            tab.committedURL = webView.url
        }
        refreshTitles()
        refreshAddress()
    }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 preferences: WKWebpagePreferences,
                 decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
        guard let url = action.request.url,
              ["http","https","about"].contains(url.scheme?.lowercased() ?? "") else {
            decisionHandler(.cancel, preferences); return
        }
        if action.targetFrame?.isMainFrame == true, let tab = tabs.values.first(where: {$0.web === webView}) {
            let cleartext = NavigationSecurity.cleartextOrigin(url)
            let explicitlyAllowed = cleartext != nil && cleartext == tab.allowedCleartextOrigin && !tab.secureProvisionalLoad
            let localRequest = NavigationSecurity.isLoopback(url) && !tab.secureProvisionalLoad
            if let cleartext, !localRequest, !explicitlyAllowed {
                decisionHandler(.cancel, preferences)
                // App-originated upgrade retains GET semantics. Never resubmit a form.
                if action.request.httpMethod == "GET", let upgraded = NavigationSecurity.upgrade(url),
                   !tab.secureProvisionalLoad || action.navigationType == .linkActivated {
                    var request = action.request
                    request.url = upgraded
                    tab.allowedCleartextOrigin = nil
                    tab.secureProvisionalLoad = true
                    webView.load(request)
                } else {
                    showNavigationWarning("Sisu blocked an unencrypted navigation to " + cleartext + ".")
                }
                return
            }
            if url.scheme?.lowercased() == "https" {
                tab.secureProvisionalLoad = true
                tab.allowedCleartextOrigin = nil
            }
            if #available(macOS 15.2,*), !NavigationSecurity.isLoopback(url), !explicitlyAllowed {
                preferences.preferredHTTPSNavigationPolicy = .errorOnFailure
            }
        }
        WebSettings.navigation(preferences, profile.preferences)
        decisionHandler(action.shouldPerformDownload ? .download : .allow, preferences)
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if navigationResponse.isForMainFrame, let url = navigationResponse.response.url,
           let origin = NavigationSecurity.cleartextOrigin(url),
           let tab = tabs.values.first(where: {$0.web === webView}),
           tab.secureProvisionalLoad || (!NavigationSecurity.isLoopback(url) && tab.allowedCleartextOrigin != origin) {
            decisionHandler(.cancel)
            showNavigationWarning("Sisu blocked a redirect to unencrypted HTTP.")
            return
        }
        if let response = navigationResponse.response as? HTTPURLResponse,
           response.statusCode == 204 || response.statusCode == 205 {
            decisionHandler(.cancel)
            return
        }
        decisionHandler(navigationResponse.canShowMIMEType ? .allow : .download)
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? { addTab(configuration: configuration)?.web }
    func webViewDidClose(_ webView: WKWebView) { if let tab = tabs.values.first(where: {$0.web === webView}) { requestClose(tab.id) } }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { showError("This page's process stopped. Reload it when you are ready; unsaved edits may be unavailable.") }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        reportNavigationFailure(error as NSError)
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        reportNavigationFailure(error as NSError)
    }
    private func reportNavigationFailure(_ error: NSError) {
        // WebKitErrorFrameLoadInterruptedByPolicyChange accompanies a handled navigation,
        // including a handoff to WKDownload. WKError.Code does not expose this legacy code.
        if error.domain == "WebKitErrorDomain", error.code == 102 { return }
        if !isCancellation(error) { showNavigationWarning(error.localizedDescription) }
    }
    private func showNavigationWarning(_ message: String) {
        guard let window, window.isVisible, window.attachedSheet == nil else { return }
        let alert = NSAlert()
        alert.messageText = "Page could not load"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: window)
    }
    private func isCancellation(_ error: NSError) -> Bool {
        (error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled) ||
        (error.domain == NSCocoaErrorDomain && error.code == NSUserCancelledError)
    }
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
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) { decisionHandler(profile.isPrivate || profile.preferences.camera == "deny" ? .deny : .prompt) }
    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) { register(download) }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) { register(download) }
    private func register(_ download: WKDownload) { downloads[ObjectIdentifier(download)] = download; download.delegate = self }
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        var name = URL(fileURLWithPath: suggestedFilename).lastPathComponent
        if name.isEmpty || name == "/" || name.hasPrefix(".") { name = "download" + name }
        if profile.preferences.downloads == "downloads",
           let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            let base = (name as NSString).deletingPathExtension, ext = (name as NSString).pathExtension
            var destination = folder.appendingPathComponent(name), copy = 2
            while FileManager.default.fileExists(atPath: destination.path) || downloadDestinations.values.contains(destination) {
                destination = folder.appendingPathComponent(ext.isEmpty ? "\(base) \(copy)" : "\(base) \(copy).\(ext)"); copy += 1
            }
            downloadDestinations[ObjectIdentifier(download)] = destination
            completionHandler(destination); return
        }
        let panel = NSSavePanel(); panel.nameFieldStringValue = name
        panel.beginSheetModal(for: window!) { answer in
            let destination = answer == .OK ? panel.url : nil
            if destination == nil { self.downloads.removeValue(forKey: ObjectIdentifier(download)) }
            completionHandler(destination)
        }
    }
    func downloadDidFinish(_ download: WKDownload) {
        downloads.removeValue(forKey: ObjectIdentifier(download))
        // Bounce the Dock's Downloads stack for files saved without a panel. The
        // notification is visible to other apps, so private windows never post it.
        if let file = downloadDestinations.removeValue(forKey: ObjectIdentifier(download)), !profile.isPrivate {
            DistributedNotificationCenter.default().post(name: .init("com.apple.DownloadFileFinished"), object: file.path)
        }
    }
    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        downloadDestinations.removeValue(forKey: ObjectIdentifier(download))
        guard downloads.removeValue(forKey: ObjectIdentifier(download)) != nil else { return }
        if !isCancellation(error as NSError) { showError(error.localizedDescription) }
    }

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
         "webViews": tabs.values.filter({$0.web != nil}).count,
         "committedURL": current?.committedURL?.absoluteString ?? "",
         "notSecure": !cleartextLabel.isHidden,
         "isLoading": current?.web?.isLoading ?? false,
         "hasDialog": NSApp.modalWindow != nil || window?.attachedSheet != nil]
    }
}

@MainActor final class WeakWorkHandler: NSObject, WKScriptMessageHandler {
    weak var owner: BrowserWindow?
    init(_ owner: BrowserWindow) { self.owner = owner }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) { owner?.userContentController(userContentController, didReceive: message) }
}
