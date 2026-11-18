import AppKit

@MainActor private var promptingForEdits = false

@MainActor func confirmDiscard(count: Int, action: String) -> Bool {
    guard count > 0 else { return true }
    guard !promptingForEdits else { return false }
    promptingForEdits = true
    defer { promptingForEdits = false }
    let alert = NSAlert()
    alert.messageText = "You have unsaved changes"
    alert.informativeText = count == 1
        ? "Changes on this page may be lost."
        : "Changes on \(count) pages may be lost."
    alert.addButton(withTitle: "Stay")
    alert.addButton(withTitle: action).hasDestructiveAction = true
    return alert.runModal() == .alertSecondButtonReturn
}
