/// OpenSubtitles REST client.
///
/// OpenSubtitles is the canonical free subtitle database; their REST v1 API
/// requires (a) an API key registered at opensubtitles.com and (b) a user
/// login for the download endpoint. The search endpoint can be hit
/// unauthenticated but rate-limits aggressively.
///
/// Auth flow:
///   POST /login → token (cached in memory for the session)
///   Authorization: Bearer <token> on subsequent requests
///
/// The API key + password live in the user's login Keychain (a generic
/// password keyed by service name); username is stored in UserDefaults
/// since it's not sensitive and is needed to look up the password's
/// account field. Earlier versions stored everything in UserDefaults
/// plaintext, which any other app on the machine could read.
///
/// API docs: https://opensubtitles.stoplight.io/docs/opensubtitles-api/
import Foundation
import Security

enum OpenSubtitlesService {
    private static let baseURL = "https://api.opensubtitles.com/api/v1"
    private static var cachedToken: String?

    struct SubtitleResult {
        let fileID: Int
        let language: String
        let release: String
        let downloadCount: Int
    }

    enum ServiceError: Error, LocalizedError {
        case missingAPIKey
        case missingCredentials
        case loginFailed(String)
        case searchFailed(String)
        case downloadFailed(String)

        var errorDescription: String? {
            switch self {
            case .missingAPIKey: return L("OpenSubtitles API key is not set. Add it in Preferences → Subtitles.")
            case .missingCredentials: return L("OpenSubtitles username/password is not set.")
            case .loginFailed(let msg): return String(format: L("Login failed: %@"), msg)
            case .searchFailed(let msg): return String(format: L("Search failed: %@"), msg)
            case .downloadFailed(let msg): return String(format: L("Download failed: %@"), msg)
            }
        }
    }

    // MARK: - Public surface

    static func search(query: String, languages: [String] = ["en"]) async throws -> [SubtitleResult] {
        guard let apiKey = storedAPIKey() else { throw ServiceError.missingAPIKey }
        var components = URLComponents(string: "\(baseURL)/subtitles")!
        components.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "languages", value: languages.joined(separator: ",")),
        ]
        var req = URLRequest(url: components.url!, timeoutInterval: 15)
        req.setValue(apiKey, forHTTPHeaderField: "Api-Key")
        req.setValue(userAgent(), forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        do { (data, _) = try await URLSession.shared.data(for: req) }
        catch { throw ServiceError.searchFailed(error.localizedDescription) }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["data"] as? [[String: Any]] else {
            throw ServiceError.searchFailed("Unexpected response")
        }
        return items.compactMap { item in
            guard let attrs = item["attributes"] as? [String: Any],
                  let files = attrs["files"] as? [[String: Any]],
                  let fileID = files.first?["file_id"] as? Int else { return nil }
            let lang = (attrs["language"] as? String) ?? "?"
            let release = (attrs["release"] as? String) ?? "?"
            let dc = (attrs["download_count"] as? Int) ?? 0
            return SubtitleResult(fileID: fileID, language: lang, release: release, downloadCount: dc)
        }
    }

    /// Downloads the subtitle to a temporary file and returns its URL. Caller
    /// is responsible for moving / loading the file.
    static func download(fileID: Int) async throws -> URL {
        let token = try await ensureLoggedIn()
        let link = try await requestDownloadLink(fileID: fileID, token: token)
        return try await downloadFile(from: link)
    }

    // MARK: - Credentials storage (Keychain-backed)

    /// All Keychain items live under this service string. The account field
    /// disambiguates the API key vs. the user password.
    private static let keychainService = "com.awesomeplayer.opensubs"
    private static let apiKeyAccount = "apiKey"
    private static let passwordAccount = "userPassword"

    static func storedAPIKey() -> String? {
        keychainRead(account: apiKeyAccount)
    }

    static func setAPIKey(_ key: String) {
        keychainWrite(account: apiKeyAccount, value: key)
        cachedToken = nil
    }

    static func storedUsername() -> String? {
        // Username isn't sensitive; UserDefaults is fine and lets the
        // Preferences pane's NSTextField bind directly.
        UserDefaults.standard.string(forKey: "opensubs.username").flatMap { $0.isEmpty ? nil : $0 }
    }

    static func storedPassword() -> String? {
        keychainRead(account: passwordAccount)
    }

    static func setCredentials(username: String, password: String) {
        UserDefaults.standard.set(username, forKey: "opensubs.username")
        keychainWrite(account: passwordAccount, value: password)
        cachedToken = nil
    }

    // MARK: - Keychain helpers

    private static func keychainQuery(account: String) -> [String: Any] {
        [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
        ]
    }

    private static func keychainRead(account: String) -> String? {
        var query = keychainQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data,
              let value = String(data: data, encoding: .utf8), !value.isEmpty else { return nil }
        return value
    }

    private static func keychainWrite(account: String, value: String) {
        let data = value.data(using: .utf8) ?? Data()
        if value.isEmpty {
            SecItemDelete(keychainQuery(account: account) as CFDictionary)
            return
        }
        // Upsert: try update first, fall back to add if no existing item.
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(keychainQuery(account: account) as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = keychainQuery(account: account)
            add[kSecValueData as String] = data
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    // MARK: - Internals

    private static func userAgent() -> String {
        let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0"
        return "AwesomePlayer v\(version)"
    }

    private static func ensureLoggedIn() async throws -> String {
        if let cached = cachedToken { return cached }
        guard let apiKey = storedAPIKey() else { throw ServiceError.missingAPIKey }
        guard let user = storedUsername(), let pass = storedPassword() else {
            throw ServiceError.missingCredentials
        }

        var req = URLRequest(url: URL(string: "\(baseURL)/login")!, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "Api-Key")
        req.setValue(userAgent(), forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let body: [String: Any] = ["username": user, "password": pass]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let data: Data
        do { (data, _) = try await URLSession.shared.data(for: req) }
        catch { throw ServiceError.loginFailed(error.localizedDescription) }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["token"] as? String else {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ServiceError.loginFailed(msg)
        }
        cachedToken = token
        return token
    }

    private static func requestDownloadLink(fileID: Int, token: String) async throws -> URL {
        var req = URLRequest(url: URL(string: "\(baseURL)/download")!, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue(storedAPIKey() ?? "", forHTTPHeaderField: "Api-Key")
        req.setValue(userAgent(), forHTTPHeaderField: "User-Agent")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let body: [String: Any] = ["file_id": fileID]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let data: Data
        do { (data, _) = try await URLSession.shared.data(for: req) }
        catch { throw ServiceError.downloadFailed(error.localizedDescription) }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let link = json["link"] as? String,
              let url = URL(string: link) else {
            throw ServiceError.downloadFailed("Could not parse download link")
        }
        return url
    }

    private static func downloadFile(from url: URL) async throws -> URL {
        let tempURL: URL
        let response: URLResponse
        do { (tempURL, response) = try await URLSession.shared.download(from: url) }
        catch { throw ServiceError.downloadFailed(error.localizedDescription) }

        // Move to a stable temp location with a sensible extension. The
        // header sometimes provides filename via Content-Disposition; if
        // not, default to .srt (the most common format).
        var ext = "srt"
        if let suggested = (response as? HTTPURLResponse)?.suggestedFilename,
           let dot = suggested.lastIndex(of: ".") {
            ext = String(suggested[suggested.index(after: dot)...])
        }
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent("opensubs-\(UUID().uuidString).\(ext)")
        do {
            try FileManager.default.moveItem(at: tempURL, to: dest)
            return dest
        } catch {
            throw ServiceError.downloadFailed(error.localizedDescription)
        }
    }
}
