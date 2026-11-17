import AppKit
import WebKit

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    var windows: [BrowserWindow] = []
    private var testInput: TestInput?
    func applicationDidFinishLaunching(_ notification: Notification) {
        installMenu()
        Blocker.shared.prepare { [weak self] in
            guard let self else { return }
            if let failure = Blocker.shared.failure {
                let alert = NSAlert(); alert.messageText = "Blocking rules could not start"; alert.informativeText = failure
                alert.addButton(withTitle: "Quit"); alert.runModal(); NSApp.terminate(nil); return
            }
            let args = CommandLine.arguments
            let urls = args.compactMap { $0.hasPrefix("--url=") ? String($0.dropFirst(6)) : nil }.filter { URL(string:$0).map { ["https","http"].contains($0.scheme ?? "") } == true }
            self.open(privateMode: args.contains("--private"), urls: urls)
            if args.contains("--test-control=stdio"), ProcessInfo.processInfo.environment["BROWSER_TEST_HOME"] != nil {
                self.testInput = TestInput(app:self)
            }
        }
    }
    @discardableResult func open(privateMode: Bool, urls: [String] = []) -> BrowserWindow? {
        do { let controller = BrowserWindow(profile:try Profile(isPrivate:privateMode)); windows.append(controller); controller.start(urls:urls); return controller }
        catch { let alert = NSAlert(); alert.messageText = "Sisu couldn't open this profile"; alert.informativeText=error.localizedDescription; alert.runModal(); return nil }
    }
    var active: BrowserWindow? { windows.first(where: {$0.window === NSApp.keyWindow}) ?? windows.last }
    func remove(_ controller:BrowserWindow){ windows.removeAll{$0 === controller} }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool{true}
    func applicationShouldTerminate(_ sender:NSApplication)->NSApplication.TerminateReply {
        windows.allSatisfy{$0.canCloseWindow()} ? .terminateNow : .terminateCancel
    }
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows:Bool)->Bool{if !hasVisibleWindows{open(privateMode:false)};return true}
    @objc func newWindow(){open(privateMode:false)}
    @objc func about(){NSApp.orderFrontStandardAboutPanel(options:[.applicationName:"Sisu WebKit Preview",.version:Bundle.main.object(forInfoDictionaryKey:"SisuVersion") as? String ?? "0.1.0-alpha.1"])}
    @objc func newPrivateWindow(){open(privateMode:true)}
    @objc func newTab(){active?.newTab()}
    @objc func closeTab(){active?.closeCurrent()}
    @objc func focusAddress(){active?.focusAddress()}
    @objc func reload(){active?.reload()}
    @objc func back(){active?.back()}
    @objc func forward(){active?.forward()}
    @objc func settings(){active?.openSettings()}
    @objc func toggleTabs(){active?.togglePlacement()}
    @objc func zoomIn(){active?.zoomIn()}
    @objc func zoomOut(){active?.zoomOut()}
    @objc func zoomReset(){active?.zoomReset()}
    @objc func find(){guard let web=active?.current?.web else{return}; let alert=NSAlert();alert.messageText="Find on page";let input=NSSearchField(frame:NSRect(x:0,y:0,width:320,height:30));alert.accessoryView=input;alert.addButton(withTitle:"Find");alert.addButton(withTitle:"Cancel");if alert.runModal() == .alertFirstButtonReturn{web.find(input.stringValue,configuration:WKFindConfiguration()){_ in}}}
    private func installMenu() {
        let bar=NSMenu()
        func menu(_ title:String)->NSMenu{let top=NSMenuItem();let menu=NSMenu(title:title);top.submenu=menu;bar.addItem(top);return menu}
        func add(_ menu:NSMenu,_ title:String,_ action:Selector,_ key:String,_ modifiers:NSEvent.ModifierFlags = .command,_ target:AnyObject? = nil){let item=NSMenuItem(title:title,action:action,keyEquivalent:key);item.keyEquivalentModifierMask=modifiers;item.target=target ?? self;menu.addItem(item)}
        let app=menu("Sisu")
        add(app,"About Sisu WebKit Preview",#selector(about),"")
        app.addItem(.separator());add(app,"Settings…",#selector(settings),",")
        app.addItem(.separator());add(app,"Hide Sisu",#selector(NSApplication.hide(_:)),"h",.command,NSApp)
        add(app,"Hide Others",#selector(NSApplication.hideOtherApplications(_:)),"h",[.command,.option],NSApp)
        app.addItem(.separator());add(app,"Quit Sisu",#selector(NSApplication.terminate(_:)),"q",.command,NSApp)
        let file=menu("File");add(file,"New Tab",#selector(newTab),"t");add(file,"New Window",#selector(newWindow),"n");add(file,"New Private Window",#selector(newPrivateWindow),"n",[.command,.shift]);file.addItem(.separator());add(file,"Close Tab",#selector(closeTab),"w")
        let edit=menu("Edit")
        for (title,selector,key) in [("Undo",Selector(("undo:")),"z"),("Redo",Selector(("redo:")),"Z"),("Cut",#selector(NSText.cut(_:)),"x"),("Copy",#selector(NSText.copy(_:)),"c"),("Paste",#selector(NSText.paste(_:)),"v"),("Select All",#selector(NSText.selectAll(_:)),"a")] {
            let entry=NSMenuItem(title:title,action:selector,keyEquivalent:key);entry.target=nil;edit.addItem(entry)
        }
        edit.addItem(.separator());add(edit,"Find…",#selector(find),"f")
        let view=menu("View");add(view,"Open Location…",#selector(focusAddress),"l");add(view,"Reload",#selector(reload),"r");add(view,"Toggle Left Tabs",#selector(toggleTabs),"s",[.command,.option]);view.addItem(.separator());add(view,"Zoom In",#selector(zoomIn),"+");add(view,"Zoom Out",#selector(zoomOut),"-");add(view,"Actual Size",#selector(zoomReset),"0")
        let history=menu("History");add(history,"Back",#selector(back),"[");add(history,"Forward",#selector(forward),"]")
        let window=menu("Window");add(window,"Minimize",#selector(NSWindow.performMiniaturize(_:)),"m");window.items.last?.target=nil;NSApp.windowsMenu=window
        NSApp.mainMenu=bar
    }
}

// Opt-in, process-local test transport. No socket, renderer bridge, inspector,
// personal-profile access or remote debugging. Normal launches don't read stdin.
@MainActor final class TestInput {
    weak var app:AppDelegate?
    init(app:AppDelegate){self.app=app;DispatchQueue.global(qos:.utility).async{[weak self] in
        while let line=readLine(){guard line.utf8.count<=65536,let bytes=line.data(using:.utf8),let command=(try? JSONSerialization.jsonObject(with:bytes)) as? [String:Any] else{continue}
            DispatchQueue.main.async{[weak self] in self?.run(command)}
        }
    }}
    private func reply(_ id:Any,_ value:Any){let object:[String:Any]=["id":id,"result":value];if let data=try? JSONSerialization.data(withJSONObject:object,options:[.sortedKeys]){FileHandle.standardOutput.write(data);FileHandle.standardOutput.write(Data([10]))}}
    private func run(_ c:[String:Any]){
        let id=c["id"] ?? 0
        guard let app,let controller=app.active,let op=c["op"] as? String else{reply(id,["error":"No active window"]);return}
        switch op {
        case "snapshot":reply(id,controller.snapshot())
        case "new":_ = controller.addTab(url:(c["url"] as? String).flatMap{URL(string:$0)});reply(id,controller.snapshot())
        case "navigate":controller.navigate(c["url"] as? String ?? "");reply(id,controller.snapshot())
        case "select":controller.select(c["tab"] as? Int ?? 0);reply(id,controller.snapshot())
        case "close":controller.requestClose(c["tab"] as? Int ?? 0);reply(id,controller.snapshot())
        case "layout":controller.setPlacement(c["value"] as? String == "left" ? "left":"top");reply(id,controller.snapshot())
        case "theme":controller.setTheme(c["value"] as? String == "light" ? "light":"dark");reply(id,controller.snapshot())
        case "eval":
            guard let web=controller.current?.web,let url=web.url,["localhost","127.0.0.1","::1"].contains(url.host ?? ""),let source=c["source"] as? String else{reply(id,["error":"Evaluation restricted to the isolated loopback fixture"]);return}
            web.evaluateJavaScript(source){[weak self] value,error in self?.reply(id,error.map{["error":$0.localizedDescription]} ?? value ?? NSNull())}
        case "quit":reply(id,["quitting":true]);NSApp.terminate(nil)
        default:reply(id,["error":"Unknown test command"])
        }
    }
}

if CommandLine.arguments.contains("--version") {
    print(Bundle.main.object(forInfoDictionaryKey:"SisuVersion") as? String ?? "0.1.0-alpha.1")
    exit(0)
}
MainActor.assumeIsolated {
    let app=NSApplication.shared
    let delegate=AppDelegate()
    app.setActivationPolicy(.regular)
    app.delegate=delegate
    withExtendedLifetime(delegate) { app.run() }
}
