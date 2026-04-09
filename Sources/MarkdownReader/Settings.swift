import Foundation

// Persistent settings backed by UserDefaults
final class Settings {
    static let shared = Settings()
    static let changedNotification = Notification.Name("SettingsChanged")

    private let defaults = UserDefaults.standard

    // MARK: - Appearance

    var theme: String {
        get { defaults.string(forKey: "theme") ?? "auto" }
        set { defaults.set(newValue, forKey: "theme"); notify() }
    }

    var fontFamily: String {
        get { defaults.string(forKey: "fontFamily") ?? "serif" }
        set { defaults.set(newValue, forKey: "fontFamily"); notify() }
    }

    var fontSize: Int {
        get {
            let v = defaults.integer(forKey: "fontSize")
            return v > 0 ? v : 16
        }
        set { defaults.set(newValue, forKey: "fontSize"); notify() }
    }

    var contentWidth: String {
        get { defaults.string(forKey: "contentWidth") ?? "standard" }
        set { defaults.set(newValue, forKey: "contentWidth"); notify() }
    }

    // MARK: - Behavior

    var autoReload: Bool {
        get { defaults.object(forKey: "autoReload") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "autoReload"); notify() }
    }

    var showTOC: Bool {
        get { defaults.object(forKey: "showTOC") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "showTOC"); notify() }
    }

    var showBreadcrumb: Bool {
        get { defaults.object(forKey: "showBreadcrumb") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "showBreadcrumb"); notify() }
    }

    var showWordCount: Bool {
        get { defaults.object(forKey: "showWordCount") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "showWordCount"); notify() }
    }

    var showProgress: Bool {
        get { defaults.object(forKey: "showProgress") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "showProgress"); notify() }
    }

    // MARK: - Content

    var enableMermaid: Bool {
        get { defaults.object(forKey: "enableMermaid") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "enableMermaid"); notify() }
    }

    var enableKatex: Bool {
        get { defaults.object(forKey: "enableKatex") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "enableKatex"); notify() }
    }

    var enableHighlight: Bool {
        get { defaults.object(forKey: "enableHighlight") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "enableHighlight"); notify() }
    }

    // MARK: - Bookmarks

    var bookmarks: [String] {
        get { defaults.stringArray(forKey: "bookmarks") ?? [] }
        set { defaults.set(newValue, forKey: "bookmarks"); notify() }
    }

    func toggleBookmark(_ path: String) -> Bool {
        var list = bookmarks
        if let idx = list.firstIndex(of: path) {
            list.remove(at: idx)
            bookmarks = list
            return false
        } else {
            list.insert(path, at: 0)
            bookmarks = list
            return true
        }
    }

    func isBookmarked(_ path: String) -> Bool {
        bookmarks.contains(path)
    }

    // MARK: - Recent files

    var recentFiles: [String] {
        get { defaults.stringArray(forKey: "recentFiles") ?? [] }
        set { defaults.set(newValue, forKey: "recentFiles") }
    }

    func addRecentFile(_ path: String) {
        var files = recentFiles.filter { $0 != path }
        files.insert(path, at: 0)
        if files.count > 20 { files = Array(files.prefix(20)) }
        recentFiles = files
    }

    // MARK: - Serialization for JS bridge

    func toJSON() -> String {
        let dict: [String: Any] = [
            "theme": theme,
            "fontFamily": fontFamily,
            "fontSize": fontSize,
            "contentWidth": contentWidth,
            "autoReload": autoReload,
            "showTOC": showTOC,
            "showBreadcrumb": showBreadcrumb,
            "showWordCount": showWordCount,
            "showProgress": showProgress,
            "enableMermaid": enableMermaid,
            "enableKatex": enableKatex,
            "enableHighlight": enableHighlight
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let str = String(data: data, encoding: .utf8) else { return "{}" }
        return str
    }

    private func notify() {
        NotificationCenter.default.post(name: Settings.changedNotification, object: nil)
    }
}
