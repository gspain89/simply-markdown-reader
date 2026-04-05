import Cocoa
import WebKit

// Drop target view — accepts .md files dragged from Finder
final class DropView: NSView {
    var onDrop: ((String) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], urls.contains(where: { Self.mdExts.contains($0.pathExtension.lowercased()) }) else {
            return []
        }
        return .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] else { return false }

        for url in urls {
            if Self.mdExts.contains(url.pathExtension.lowercased()) {
                onDrop?(url.path)
                return true
            }
        }
        return false
    }

    private static let mdExts: Set<String> = ["md", "markdown", "mdown", "mkd", "mdx"]
}

final class MarkdownWindowController: NSObject, WKNavigationDelegate, WKScriptMessageHandler {

    let window: NSWindow
    let webView: WKWebView
    private(set) var filePath: String?
    private var fileWatcher: FileWatcher?
    private var navigationHistory: [String] = []
    private var historyIndex: Int = -1
    private var isNavigatingHistory = false

    // MARK: - Initialization

    init(filePath: String? = nil) {
        // Configure WKWebView
        let config = WKWebViewConfiguration()
        let ucc = WKUserContentController()
        config.userContentController = ucc
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        self.webView = webView

        // Create window
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        w.minSize = NSSize(width: 480, height: 360)
        w.center()
        w.tabbingMode = .preferred
        w.titlebarAppearsTransparent = false
        w.isReleasedWhenClosed = false
        w.tabbingIdentifier = "MarkdownReaderTabs"
        self.window = w

        super.init()

        // Register JS message handler
        ucc.add(self, name: "app")

        webView.navigationDelegate = self

        // Wrap WKWebView in DropView for Finder drag-and-drop support
        let dropView = DropView(frame: .zero)
        dropView.translatesAutoresizingMaskIntoConstraints = false
        webView.translatesAutoresizingMaskIntoConstraints = false
        dropView.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: dropView.topAnchor),
            webView.bottomAnchor.constraint(equalTo: dropView.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: dropView.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: dropView.trailingAnchor)
        ])
        dropView.onDrop = { [weak self] path in self?.loadFile(path: path) }
        w.contentView = dropView

        // Observe settings changes
        NotificationCenter.default.addObserver(
            self, selector: #selector(settingsDidChange),
            name: Settings.changedNotification, object: nil
        )

        // Load the HTML template from the app bundle's Resources
        loadTemplate()

        if let filePath = filePath {
            // Defer file loading until the template has finished loading
            self.filePath = filePath
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        fileWatcher?.stop()
    }

    // MARK: - Template loading

    private func resourcesPath() -> String {
        // Running inside .app bundle: <app>/Contents/MacOS/MarkdownReader
        // Resources at: <app>/Contents/Resources/
        if let bundlePath = Bundle.main.resourcePath {
            let candidate = bundlePath
            if FileManager.default.fileExists(atPath: candidate + "/template.html") {
                return candidate
            }
        }
        // Development fallback: look relative to executable
        let execURL = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        let devPath = execURL.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources").path
        if FileManager.default.fileExists(atPath: devPath + "/template.html") {
            return devPath
        }
        // Last resort: current directory
        let cwd = FileManager.default.currentDirectoryPath + "/Resources"
        return cwd
    }

    private func loadTemplate() {
        let resPath = resourcesPath()
        let templateURL = URL(fileURLWithPath: resPath + "/template.html")
        // Allow read access to the entire filesystem so local images in markdown work
        webView.loadFileURL(templateURL, allowingReadAccessTo: URL(fileURLWithPath: "/"))
    }

    // MARK: - File loading

    func loadFile(path: String) {
        let resolvedPath: String
        if path.hasPrefix("/") {
            resolvedPath = path
        } else if let currentDir = filePath.map({ URL(fileURLWithPath: $0).deletingLastPathComponent().path }) {
            resolvedPath = currentDir + "/" + path
        } else {
            resolvedPath = path
        }

        guard FileManager.default.fileExists(atPath: resolvedPath) else { return }

        // Update navigation history
        if !isNavigatingHistory {
            if historyIndex < navigationHistory.count - 1 {
                navigationHistory = Array(navigationHistory.prefix(historyIndex + 1))
            }
            navigationHistory.append(resolvedPath)
            historyIndex = navigationHistory.count - 1
        }

        self.filePath = resolvedPath
        Settings.shared.addRecentFile(resolvedPath)

        window.title = URL(fileURLWithPath: resolvedPath).lastPathComponent.precomposedStringWithCanonicalMapping
        window.representedFilename = resolvedPath

        guard let content = try? String(contentsOfFile: resolvedPath, encoding: .utf8) else { return }
        let baseDir = URL(fileURLWithPath: resolvedPath).deletingLastPathComponent().path

        let escapedContent = escapeForJS(content)
        let escapedPath = escapeForJS(resolvedPath)
        let escapedBase = escapeForJS(baseDir)

        let js = "render(\(escapedContent), \(escapedPath), \(escapedBase));"
        webView.evaluateJavaScript(js, completionHandler: nil)

        setupFileWatcher(path: resolvedPath)
        listSiblingFiles(dir: baseDir)

        // Update bookmark button state
        let isBookmarked = Settings.shared.isBookmarked(resolvedPath)
        webView.evaluateJavaScript("updateBookmarkState(\(isBookmarked));", completionHandler: nil)
    }

    private func setupFileWatcher(path: String) {
        fileWatcher?.stop()
        guard Settings.shared.autoReload else { return }
        fileWatcher = FileWatcher(path: path) { [weak self] in
            guard let self = self else { return }
            // Debounce: small delay to let writes complete
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.reloadCurrentFile()
            }
        }
    }

    private func reloadCurrentFile() {
        guard let path = filePath,
              let content = try? String(contentsOfFile: path, encoding: .utf8) else { return }
        let escaped = escapeForJS(content)
        webView.evaluateJavaScript("reloadContent(\(escaped));", completionHandler: nil)
    }

    private func listSiblingFiles(dir: String) {
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return }
        let mdFiles = items.filter { $0.hasSuffix(".md") || $0.hasSuffix(".markdown") || $0.hasSuffix(".mdx") }
            .sorted()
            .map { $0.precomposedStringWithCanonicalMapping }
        guard let data = try? JSONSerialization.data(withJSONObject: mdFiles),
              let json = String(data: data, encoding: .utf8) else { return }
        let dirEscaped = escapeForJS(dir)
        webView.evaluateJavaScript("setSiblingFiles(\(json), \(dirEscaped));", completionHandler: nil)

        // Also send folder tree
        sendFolderTree(root: dir)
    }

    private func sendFolderTree(root: String) {
        let fm = FileManager.default
        let mdExts: Set<String> = ["md", "markdown", "mdown", "mkd", "mdx"]

        func buildTree(at path: String, depth: Int) -> [String: Any]? {
            guard depth < 4 else { return nil } // Limit depth to 4 levels
            guard let items = try? fm.contentsOfDirectory(atPath: path) else { return nil }

            var tree: [String: Any] = [:]
            for item in items.sorted() {
                let normalized = item.precomposedStringWithCanonicalMapping
                if item.hasPrefix(".") { continue }
                let fullPath = path + "/" + item
                var isDir: ObjCBool = false
                fm.fileExists(atPath: fullPath, isDirectory: &isDir)

                if isDir.boolValue {
                    if let subtree = buildTree(at: fullPath, depth: depth + 1), !subtree.isEmpty {
                        tree[normalized] = subtree
                    }
                } else {
                    let ext = URL(fileURLWithPath: item).pathExtension.lowercased()
                    if mdExts.contains(ext) {
                        tree[normalized] = true
                    }
                }
            }
            return tree.isEmpty ? nil : tree
        }

        guard let tree = buildTree(at: root, depth: 0) else { return }
        guard let data = try? JSONSerialization.data(withJSONObject: tree),
              let json = String(data: data, encoding: .utf8) else { return }
        let rootEscaped = escapeForJS(root)
        webView.evaluateJavaScript("setFolderTree(\(json), \(rootEscaped));", completionHandler: nil)
    }

    // MARK: - Navigation

    func goBack() {
        guard historyIndex > 0 else { return }
        historyIndex -= 1
        isNavigatingHistory = true
        loadFile(path: navigationHistory[historyIndex])
        isNavigatingHistory = false
    }

    func goForward() {
        guard historyIndex < navigationHistory.count - 1 else { return }
        historyIndex += 1
        isNavigatingHistory = true
        loadFile(path: navigationHistory[historyIndex])
        isNavigatingHistory = false
    }

    // MARK: - Actions

    func exportPDF() {
        guard let filePath = filePath else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = URL(fileURLWithPath: filePath)
            .deletingPathExtension().lastPathComponent + ".pdf"

        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            let config = WKPDFConfiguration()
            config.rect = CGRect(x: 0, y: 0, width: 595, height: 842) // A4 in points
            self?.webView.createPDF(configuration: config) { result in
                if case .success(let data) = result {
                    try? data.write(to: url)
                }
            }
        }
    }

    func zoomIn() {
        let size = min(Settings.shared.fontSize + 2, 28)
        Settings.shared.fontSize = size
    }

    func zoomOut() {
        let size = max(Settings.shared.fontSize - 2, 12)
        Settings.shared.fontSize = size
    }

    func resetZoom() {
        Settings.shared.fontSize = 16
    }

    func toggleTOC() {
        Settings.shared.showTOC.toggle()
    }

    func toggleSource() {
        webView.evaluateJavaScript("toggleSource();", completionHandler: nil)
    }

    func toggleContentWidth() {
        let order = ["narrow", "standard", "wide", "full"]
        let current = Settings.shared.contentWidth
        if let idx = order.firstIndex(of: current) {
            Settings.shared.contentWidth = order[(idx + 1) % order.count]
        }
    }

    // MARK: - Settings observer

    @objc private func settingsDidChange() {
        let json = Settings.shared.toJSON()
        webView.evaluateJavaScript("applySettings(\(json));", completionHandler: nil)

        // Restart or stop file watcher based on autoReload
        if let path = filePath {
            if Settings.shared.autoReload {
                if fileWatcher == nil {
                    setupFileWatcher(path: path)
                }
            } else {
                fileWatcher?.stop()
                fileWatcher = nil
            }
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Template loaded — apply settings and load file if pending
        let json = Settings.shared.toJSON()
        webView.evaluateJavaScript("applySettings(\(json));") { [weak self] _, _ in
            guard let self = self else { return }
            if let path = self.filePath {
                self.loadFile(path: path)
            } else {
                // Show welcome with recent files (NFC-normalized for Korean)
                let recent = Settings.shared.recentFiles.map { $0.precomposedStringWithCanonicalMapping }
                if let data = try? JSONSerialization.data(withJSONObject: recent),
                   let json = String(data: data, encoding: .utf8) {
                    webView.evaluateJavaScript("showWelcome(\(json));", completionHandler: nil)
                }
            }

            // Send bookmarks to sidebar
            self.sendBookmarks()

            // Restore scroll position
            if let path = self.filePath, Settings.shared.rememberScroll {
                let pos = Settings.shared.scrollPosition(for: path)
                if pos > 0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        webView.evaluateJavaScript("setScrollPosition(\(pos));", completionHandler: nil)
                    }
                }
            }
        }
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String else { return }

        switch type {
        case "openFile":
            if let path = body["path"] as? String {
                loadFile(path: path)
            }
        case "openExternal":
            if let urlStr = body["url"] as? String, let url = URL(string: urlStr) {
                NSWorkspace.shared.open(url)
            }
        case "copyToClipboard":
            if let text = body["text"] as? String {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
        case "saveScrollPosition":
            if let pos = body["position"] as? Double, let path = filePath {
                Settings.shared.setScrollPosition(pos, for: path)
            }
        case "browseDirectory":
            if let dir = body["path"] as? String {
                listSiblingFiles(dir: dir)
            }
        case "updateSetting":
            if let key = body["key"] as? String, let value = body["value"] {
                updateSettingFromJS(key: key, value: value)
            }
        case "toggleTOC":
            toggleTOC()
        case "goBack":
            goBack()
        case "goForward":
            goForward()
        case "exportPDF":
            exportPDF()
        case "share":
            shareDocument()
        case "requestFolderTree":
            if let dir = body["path"] as? String {
                sendFolderTree(root: dir)
            }
        case "toggleBookmark":
            toggleBookmark()
        case "requestBookmarks":
            sendBookmarks()
        case "log":
            if let msg = body["message"] as? String {
                NSLog("WebView: %@", msg)
            }
        default:
            break
        }
    }

    // MARK: - Settings from JS

    private func updateSettingFromJS(key: String, value: Any) {
        let s = Settings.shared
        switch key {
        case "theme":       if let v = value as? String { s.theme = v }
        case "fontFamily":  if let v = value as? String { s.fontFamily = v }
        case "fontSize":    if let v = value as? Int { s.fontSize = v }
        case "contentWidth": if let v = value as? String { s.contentWidth = v }
        case "autoReload":  if let v = value as? Bool { s.autoReload = v }
        case "rememberScroll": if let v = value as? Bool { s.rememberScroll = v }
        case "showTOC":     if let v = value as? Bool { s.showTOC = v }
        case "showBreadcrumb": if let v = value as? Bool { s.showBreadcrumb = v }
        case "showWordCount": if let v = value as? Bool { s.showWordCount = v }
        case "showProgress": if let v = value as? Bool { s.showProgress = v }
        case "enableMermaid": if let v = value as? Bool { s.enableMermaid = v }
        case "enableKatex":  if let v = value as? Bool { s.enableKatex = v }
        case "enableHighlight": if let v = value as? Bool { s.enableHighlight = v }
        default: break
        }
    }

    func openSettingsPanel() {
        webView.evaluateJavaScript("toggleSettingsPanel();", completionHandler: nil)
    }

    func shareDocument() {
        guard let path = filePath else { return }
        let url = URL(fileURLWithPath: path)
        let picker = NSSharingServicePicker(items: [url])
        // Show from the export button area (top-right of window)
        let toolbarFrame = NSRect(x: window.frame.width - 80, y: window.frame.height - 40, width: 1, height: 1)
        picker.show(relativeTo: toolbarFrame, of: webView, preferredEdge: .minY)
    }

    // MARK: - Bookmarks

    private func toggleBookmark() {
        guard let path = filePath else { return }
        let isBookmarked = Settings.shared.toggleBookmark(path)
        webView.evaluateJavaScript("updateBookmarkState(\(isBookmarked));", completionHandler: nil)
        sendBookmarks()
    }

    private func sendBookmarks() {
        let bookmarks = Settings.shared.bookmarks
            .map { $0.precomposedStringWithCanonicalMapping }
        guard let data = try? JSONSerialization.data(withJSONObject: bookmarks),
              let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("setBookmarks(\(json));", completionHandler: nil)
    }

    // MARK: - Helpers

    private func escapeForJS(_ str: String) -> String {
        // Normalize NFD → NFC so Korean filenames render correctly (macOS FS uses NFD)
        let normalized = str.precomposedStringWithCanonicalMapping
        let data = try! JSONSerialization.data(withJSONObject: normalized, options: .fragmentsAllowed)
        return String(data: data, encoding: .utf8)!
    }
}
