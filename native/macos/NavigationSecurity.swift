import Foundation

enum NavigationSecurity {
    static func isLoopback(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host)
    }

    static func cleartextOrigin(_ url: URL) -> String? {
        guard url.scheme?.lowercased() == "http", let host = url.host?.lowercased() else { return nil }
        return "\(host):\(url.port ?? 80)"
    }

    static func upgrade(_ url: URL) -> URL? {
        var target = URLComponents(url: url, resolvingAgainstBaseURL: false)
        target?.scheme = "https"
        if target?.port == 80 { target?.port = nil }
        return target?.url
    }
}
