import AppKit
import UniformTypeIdentifiers
import WebKit

struct CookieImport: Sendable {
    private struct Export: Decodable {
        struct Record: Decodable {
            let name: String
            let value: String
            let host: String
            let path: String
            let secure: Bool
            let httpOnly: Bool
            let hostOnly: Bool
            let expires: Int64?
            let sameSite: String
        }

        let cookies: [Record]
        let expired: Int
    }

    private struct ImportError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    let cookies: [HTTPCookie]
    let expired: Int
    private static let maximumFileSize = 8 * 1024 * 1024

    static func readFile(_ url: URL) throws -> CookieImport {
        guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
            throw ImportError(message: "Choose a regular cookie export file.")
        }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var data = Data()
        while let chunk = try file.read(upToCount: 65_536), !chunk.isEmpty {
            data.append(chunk)
            guard data.count <= maximumFileSize else {
                throw ImportError(message: "The cookie export exceeds 8 MiB.")
            }
        }
        return try parse(data)
    }

    static func parse(_ data: Data) throws -> CookieImport {
        let now = Int64(Date().timeIntervalSince1970)
        let decoded: Export = try data.withUnsafeBytes { bytes in
            guard let result = sisu_parse_cookie_export(bytes.bindMemory(to: UInt8.self).baseAddress, bytes.count, now) else {
                throw ImportError(message: "Sisu could not read the cookie export.")
            }
            defer { sisu_core_free(result) }
            let response = Data(String(cString: result).utf8)
            struct Failure: Decodable { let error: String }
            if let failure = try? JSONDecoder().decode(Failure.self, from: response) {
                throw ImportError(message: failure.error)
            }
            return try JSONDecoder().decode(Export.self, from: response)
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        let cookies = try decoded.cookies.map { record in
            try makeCookie(record, formatter: formatter)
        }
        return CookieImport(cookies: cookies, expired: decoded.expired)
    }

    private static func makeCookie(_ record: Export.Record, formatter: DateFormatter) throws -> HTTPCookie {
        let unrepresentable = ImportError(message: "WebKit cannot preserve a cookie’s attributes. No cookies were changed.")
        guard let origin = URL(string: "https://\(record.host)/") else { throw unrepresentable }
        var header = "\(record.name)=\(record.value); Path=\(record.path)"
        if !record.hostOnly { header += "; Domain=\(record.host)" }
        if record.secure { header += "; Secure" }
        if record.httpOnly { header += "; HttpOnly" }
        if record.sameSite != "unspecified" { header += "; SameSite=\(record.sameSite)" }
        if let expiry = record.expires {
            header += "; Expires=\(formatter.string(from: Date(timeIntervalSince1970: Double(expiry))) )"
        }
        let parsed = HTTPCookie.cookies(withResponseHeaderFields: ["Set-Cookie": header], for: origin)
        let expectedDomain = record.hostOnly ? record.host : "." + record.host
        let expectedSite = record.sameSite == "unspecified" ? nil : record.sameSite
        guard parsed.count == 1, let cookie = parsed.first,
              cookie.name == record.name, cookie.value == record.value,
              cookie.domain == expectedDomain, cookie.path == record.path,
              cookie.isSecure == record.secure, cookie.isHTTPOnly == record.httpOnly,
              cookie.sameSitePolicy?.rawValue.lowercased() == expectedSite,
              cookie.isSessionOnly == (record.expires == nil) else { throw unrepresentable }
        if let expiry = record.expires {
            guard let actual = cookie.expiresDate, actual.timeIntervalSince1970 <= Double(expiry) else {
                throw unrepresentable
            }
        }
        return cookie
    }

    @MainActor func store(in profile: Profile) async {
        guard !profile.isPrivate else { return }
        let store = profile.store.httpCookieStore
        if #available(macOS 26.0, *) {
            await store.setCookies(cookies)
        } else {
            for cookie in cookies { await store.setCookie(cookie) }
        }
    }
}

@MainActor enum CookieImporter {
    private static var active = false

    static func choose(in window: NSWindow, profile: Profile) {
        guard !profile.isPrivate else {
            message("Import cookies", "Open an ordinary window to import a cookie export.", in: window)
            return
        }
        guard !active else { return }
        active = true

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.title = "Import cookies from JSON"
        panel.prompt = "Review Export"
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else {
                active = false
                return
            }
            Task { @MainActor in
                defer { active = false }
                do {
                    let batch = try await Task.detached(priority: .userInitiated) { try CookieImport.readFile(url) }.value
                    guard window.isVisible else { return }
                    guard !batch.cookies.isEmpty else {
                        message("No cookies to import", "Expired cookies skipped: \(batch.expired).", in: window)
                        return
                    }
                    let review = NSAlert()
                    review.messageText = "Import \(batch.cookies.count) cookies?"
                    review.informativeText = "The export can contain sign-in sessions. Matching cookies in this Sisu profile may be replaced. Expired entries skipped: \(batch.expired)."
                    review.addButton(withTitle: "Cancel")
                    review.addButton(withTitle: "Import Cookies")
                    let result = await withCheckedContinuation { continuation in
                        review.beginSheetModal(for: window) { continuation.resume(returning: $0) }
                    }
                    guard result == .alertSecondButtonReturn else { return }
                    await batch.store(in: profile)
                    message("Cookie export processed", "Reload open sites to try the imported sessions. Sites may ask you to sign in again.", in: window)
                } catch {
                    if window.isVisible { message("Cookie import stopped", error.localizedDescription, in: window) }
                }
            }
        }
    }

    private static func message(_ title: String, _ detail: String, in window: NSWindow) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: window)
    }
}
