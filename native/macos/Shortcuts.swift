import AppKit
import UniformTypeIdentifiers

struct SiteShortcut: Codable {
    let title: String
    let url: URL

    private static let limit = 12
    private static let maximumFileSize = 32 * 1024

    private enum ImportError: LocalizedError {
        case invalidFile
        case tooMany

        var errorDescription: String? {
            switch self {
            case .invalidFile: return "Choose a JSON list of named HTTP or HTTPS links."
            case .tooMany: return "Sisu can show up to 12 shortcuts on the new-tab page."
            }
        }
    }

    private static func file(in root: URL) -> URL {
        root.appendingPathComponent("shortcuts.json")
    }

    private static func read(_ url: URL) throws -> [SiteShortcut] {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, let size = values.fileSize, size <= maximumFileSize else {
            throw ImportError.invalidFile
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maximumFileSize + 1) ?? Data()
        guard data.count <= maximumFileSize else { throw ImportError.invalidFile }
        let entries = try JSONDecoder().decode([SiteShortcut].self, from: data)
        guard entries.count <= limit else { throw ImportError.tooMany }
        return try entries.map { entry in
            let title = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, title.count <= 80,
                  title.rangeOfCharacter(from: .controlCharacters) == nil,
                  ["http", "https"].contains(entry.url.scheme?.lowercased() ?? ""),
                  let host = entry.url.host, !host.isEmpty, entry.url.user == nil, entry.url.password == nil
            else { throw ImportError.invalidFile }
            return SiteShortcut(title: title, url: entry.url)
        }
    }

    static func load(in root: URL) -> [SiteShortcut] {
        (try? read(file(in: root))) ?? []
    }

    static func copy(from source: URL, into root: URL) throws -> Int {
        let incoming = try read(source)
        let target = file(in: root)
        var entries = FileManager.default.fileExists(atPath: target.path) ? try read(target) : []
        let previousCount = entries.count
        var known = Set(entries.map(\.url))
        entries.append(contentsOf: incoming.filter { known.insert($0.url).inserted })
        guard entries.count <= limit else { throw ImportError.tooMany }
        if entries.count > previousCount {
            try JSONEncoder().encode(entries).write(to: target, options: .atomic)
        }
        return entries.count - previousCount
    }
}

extension AppDelegate {
    @objc func importShortcuts() {
        guard let controller = active, !controller.profile.isPrivate, let window = controller.window else { return }
        let panel = NSOpenPanel()
        panel.title = "Import Site Shortcuts"
        panel.allowedContentTypes = [.json]
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let count = try SiteShortcut.copy(from: url, into: controller.profile.root)
                if count > 0 { controller.newTab() }
                else { controller.showError("These shortcuts are already on the new-tab page.") }
            } catch {
                controller.showError(error.localizedDescription)
            }
        }
    }
}
