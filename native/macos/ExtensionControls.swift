import AppKit
import WebKit

extension BrowserWindow {
    @objc func openExtensionStore() { _ = addTab(url:StoreListing.shop) }
    @objc func extensionButtonPressed() {
        if #available(macOS 15.4,*), let library = ExtensionLibrary.library(for:profile) {
            if let id = StoreListing.id(for:current?.web?.url), library.records[id] == nil {
                startExtensionInstall(id)
                return
            }
            let menu = NSMenu()
            for (id,entry) in library.loaded.sorted(by:{$0.key < $1.key}) {
                let item = NSMenuItem(title:entry.context.webExtension.displayName ?? id,action:#selector(runExtension(_:)),keyEquivalent:"")
                item.target = self; item.representedObject = id; menu.addItem(item)
            }
            if !menu.items.isEmpty { menu.addItem(.separator()) }
            let manage = NSMenuItem(title:"Manage Extensions…",action:#selector(manageExtensions),keyEquivalent:"")
            manage.target = self; menu.addItem(manage)
            menu.popUp(positioning:nil,at:NSPoint(x:0,y:extensionButton.bounds.height),in:extensionButton)
        } else { manageExtensions() }
    }
    @objc private func runExtension(_ sender:NSMenuItem) {
        if #available(macOS 15.4,*), let id = sender.representedObject as? String, let tab = current {
            ExtensionLibrary.library(for:profile)?.loaded[id]?.context.performAction(for:tab)
        }
    }
    func startExtensionInstall(_ id:String) {
        guard #available(macOS 15.4,*), !profile.isPrivate, let library = ExtensionLibrary.library(for:profile) else { return }
        guard !isInstallingExtension else { return }
        isInstallingExtension = true; updateExtensionButton()
        Task {
            defer { isInstallingExtension = false; updateExtensionButton() }
            do { try await library.install(id:id,in:self) }
            catch { showError(error.localizedDescription) }
        }
    }
    func updateExtensionButton() {
        var canInstall = false
        if #available(macOS 15.4,*), let id = StoreListing.id(for:current?.web?.url),
           let library = ExtensionLibrary.library(for:profile) {
            canInstall = library.records[id] == nil
        }
        let text = isInstallingExtension ? "Installing…" : canInstall ? "Add to Sisu" : ""
        if extensionButton.title != text {
            extensionButton.title = text
            extensionButton.imagePosition = text.isEmpty ? .imageOnly : .noImage
            layout()
        }
        extensionButton.isEnabled = !isInstallingExtension
        extensionButton.setAccessibilityLabel(text.isEmpty ? "Extensions" : text)
        extensionButton.toolTip = text.isEmpty ? "Extensions" : text
    }
    @objc func manageExtensions() {
        guard #available(macOS 15.4,*), let library = ExtensionLibrary.library(for:profile) else {
            showError(profile.isPrivate ? "Extensions run in ordinary windows only." : "WebKit extensions require macOS 15.4 or later.")
            return
        }
        Task {
            await library.waitForRestore()
            guard let window else { return }
            let panel = NSAlert()
            panel.messageText = "Extensions"
            panel.informativeText = "Open a Chrome Web Store listing and click Add to Sisu in the toolbar, or paste the listing link below."
            let input = NSTextField(frame:NSRect(x:0,y:0,width:400,height:25))
            input.placeholderString = "Chrome Web Store link"
            input.setAccessibilityLabel("Chrome Web Store link")
            let rows = NSStackView()
            rows.orientation = .vertical; rows.alignment = .leading; rows.spacing = 8
            rows.addArrangedSubview(input)
            input.widthAnchor.constraint(equalToConstant:400).isActive = true
            let ids = Set(library.records.keys).union(library.problems.keys).sorted()
            let choices = NSPopUpButton()
            if !ids.isEmpty {
                for id in ids {
                    let label = library.records[id]?.name ?? id
                    choices.addItem(withTitle:library.problems[id] == nil ? label : label+" (unavailable)")
                    choices.lastItem?.representedObject = id
                }
                rows.addArrangedSubview(NSTextField(labelWithString:"Installed extensions"))
                rows.addArrangedSubview(choices)
            }
            rows.frame.size = rows.fittingSize
            panel.accessoryView = rows
            panel.addButton(withTitle:"Open Chrome Web Store"); panel.addButton(withTitle:"Install from Link")
            if !ids.isEmpty { panel.addButton(withTitle:"Remove Selected") }
            panel.addButton(withTitle:"Done")
            switch await panel.beginSheetModal(for:window) {
            case .alertFirstButtonReturn: openExtensionStore()
            case .alertSecondButtonReturn:
                guard let id = StoreListing.id(for:URL(string:input.stringValue.trimmingCharacters(in:.whitespacesAndNewlines))) else {
                    showError("Paste an extension detail link from chromewebstore.google.com."); return
                }
                startExtensionInstall(id)
            case .alertThirdButtonReturn where !ids.isEmpty:
                guard let id = choices.selectedItem?.representedObject as? String else { return }
                do { try library.remove(id) } catch { showError(error.localizedDescription) }
            default: break
            }
        }
    }
}
