import Foundation
import CryptoKit

struct ExtensionFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}

enum StoreListing {
    static let shop = URL(string: "https://chromewebstore.google.com/")!
    static func validID(_ id: String) -> Bool {
        id.utf8.count == 32 && id.utf8.allSatisfy { (97...112).contains($0) }
    }
    static func id(for url: URL?) -> String? {
        guard let url, url.scheme?.lowercased() == "https", url.host?.lowercased() == shop.host,
              url.user == nil, url.password == nil, url.port == nil || url.port == 443 else { return nil }
        let parts = url.path.split(separator: "/")
        guard (2...3).contains(parts.count), parts.first == "detail", let last = parts.last,
              validID(String(last)) else { return nil }
        return String(last)
    }
    static func download(_ id: String) async throws -> Data {
        guard validID(id) else { throw ExtensionFailure("Choose an extension detail page on the Chrome Web Store.") }
        var url = URLComponents(string: "https://clients2.google.com/service/update2/crx")!
        url.queryItems = [
            URLQueryItem(name:"response",value:"redirect"), URLQueryItem(name:"acceptformat",value:"crx3"),
            URLQueryItem(name:"prodversion",value:"156.0.0.0"), URLQueryItem(name:"x",value:"id=\(id)&uc")
        ]
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        config.urlCache = nil
        config.timeoutIntervalForResource = 90
        let guardrail = StoreTransfer()
        let session = URLSession(configuration:config, delegate:guardrail, delegateQueue:nil)
        defer { session.invalidateAndCancel() }
        let (file,response) = try await session.download(from:url.url!)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, StoreTransfer.allows(response.url) else {
            throw ExtensionFailure("The Chrome Web Store did not offer this extension for download.")
        }
        return try readPackage(file)
    }
    static func readPackage(_ file: URL) throws -> Data {
        let values = try file.resourceValues(forKeys:[.isRegularFileKey,.fileSizeKey])
        guard values.isRegularFile == true, let size = values.fileSize, size > 0, size <= StoreTransfer.limit else {
            throw ExtensionFailure("Extensions must be smaller than 32 MB.")
        }
        let handle = try FileHandle(forReadingFrom:file)
        defer { try? handle.close() }
        let data = try handle.read(upToCount:StoreTransfer.limit + 1) ?? Data()
        guard data.count == size else { throw ExtensionFailure("Incomplete extension download.") }
        return data
    }
}

private final class StoreTransfer: NSObject, URLSessionDownloadDelegate {
    static let limit = 32 * 1024 * 1024
    static func allows(_ url: URL?) -> Bool {
        guard let url, url.scheme == "https", let host = url.host?.lowercased(), url.user == nil,
              url.password == nil, url.port == nil || url.port == 443 else { return false }
        return host == "clients2.google.com" || host.hasSuffix(".googleusercontent.com")
    }
    func urlSession(_ session:URLSession, task:URLSessionTask, willPerformHTTPRedirection response:HTTPURLResponse,
                    newRequest request:URLRequest, completionHandler:@escaping (URLRequest?) -> Void) {
        completionHandler(Self.allows(request.url) ? request : nil)
    }
    func urlSession(_ session:URLSession, downloadTask:URLSessionDownloadTask, didWriteData bytesWritten:Int64,
                    totalBytesWritten:Int64, totalBytesExpectedToWrite:Int64) {
        if max(totalBytesExpectedToWrite,totalBytesWritten) > Self.limit { downloadTask.cancel() }
    }
    func urlSession(_ session:URLSession, downloadTask:URLSessionDownloadTask, didFinishDownloadingTo location:URL) {}
}

// Each context reads from its own verified, bounded extraction until WebKit unloads it.
final class StoreResources {
    let directory: URL
    let digest: String
    init(package: Data, id: String) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("sisu-ext-" + UUID().uuidString, isDirectory:true)
        digest = SHA256.hash(data:package).map { String(format:"%02x",$0) }.joined()
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        do {
            try package.withUnsafeBytes { raw in
                if let failure = sisu_unpack_store_package(raw.bindMemory(to:UInt8.self).baseAddress, raw.count, id, directory.path) {
                    defer { sisu_core_free(failure) }
                    throw ExtensionFailure(String(cString:failure))
                }
            }
        } catch {
            try? FileManager.default.removeItem(at:directory)
            throw error
        }
    }
    deinit { try? FileManager.default.removeItem(at:directory) }
}
