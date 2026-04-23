import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var windowControllers: [MarkdownWindowController] = []

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()

        // If launched without a file, show an empty welcome window
        if windowControllers.isEmpty {
            let wc = MarkdownWindowController()
            windowControllers.append(wc)
            wc.window.makeKeyAndOrderFront(nil)
        }

        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    // Handle file open from Finder (double-click .md)
    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        openFileInWindow(path: filename)
        return true
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        for f in filenames {
            openFileInWindow(path: f)
        }
        NSApp.reply(toOpenOrPrint: .success)
    }

    // MARK: - Window management

    /// Public entry point for opening a file (used by drag-and-drop, etc.)
    func openFilePath(_ path: String) {
        openFileInWindow(path: path)
    }

    private func openFileInWindow(path: String) {
        // If this file is already open in a visible tab, focus it instead of
        // creating a duplicate. Normalize paths (resolve `.`/`..`, NFC) so
        // e.g. `/foo/./bar.md` matches `/foo/bar.md`, and NFD-decomposed
        // Korean filenames match their NFC form.
        let normalizedTarget = normalizedPath(path)
        if let existing = windowControllers.first(where: { wc in
            guard wc.window.isVisible, let p = wc.filePath else { return false }
            return normalizedPath(p) == normalizedTarget
        }) {
            existing.window.makeKeyAndOrderFront(nil)
            return
        }

        // Reuse the welcome window if it has no file
        if let existing = windowControllers.first(where: { $0.filePath == nil }) {
            existing.loadFile(path: path)
            existing.window.makeKeyAndOrderFront(nil)
            return
        }
        let wc = MarkdownWindowController(filePath: path)
        windowControllers.append(wc)

        // Add as tab to existing window if one exists
        if let existingWindow = windowControllers.first(where: { $0 !== wc })?.window {
            existingWindow.addTabbedWindow(wc.window, ordered: .above)
        }
        wc.window.makeKeyAndOrderFront(nil)
    }

    private func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
            .precomposedStringWithCanonicalMapping
    }

    private func activeWindowController() -> MarkdownWindowController? {
        if let keyWindow = NSApp.keyWindow {
            return windowControllers.first { $0.window === keyWindow }
        }
        return windowControllers.first
    }

    // MARK: - Menu Bar

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // App menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Simply Markdown Reader", action: #selector(showAbout), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Simply Markdown Reader", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Simply Markdown Reader", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // File menu
        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Open…", action: #selector(openFile), keyEquivalent: "o")
        fileMenu.addItem(withTitle: "Open Recent", action: nil, keyEquivalent: "")
        let recentItem = fileMenu.items.last!
        recentItem.submenu = buildRecentMenu()
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Export as PDF…", action: #selector(exportPDF), keyEquivalent: "e")
            .keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Print…", action: #selector(printDocument), keyEquivalent: "p")
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Close", action: #selector(closeWindow), keyEquivalent: "w")
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        // Edit menu
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Find…", action: #selector(performFind), keyEquivalent: "f")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Toggle Bookmark", action: #selector(toggleBookmark), keyEquivalent: "d")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // View menu
        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        viewMenu.addItem(withTitle: "Reload File", action: #selector(reloadFile), keyEquivalent: "r")
        viewMenu.addItem(withTitle: "Toggle Table of Contents", action: #selector(toggleTOC), keyEquivalent: "t")
            .keyEquivalentModifierMask = [.command, .shift]
        viewMenu.addItem(withTitle: "Toggle Source View", action: #selector(toggleSource), keyEquivalent: "u")
        viewMenu.addItem(.separator())
        viewMenu.addItem(withTitle: "Zoom In", action: #selector(zoomIn), keyEquivalent: "+")
        viewMenu.addItem(withTitle: "Zoom Out", action: #selector(zoomOut), keyEquivalent: "-")
        viewMenu.addItem(withTitle: "Actual Size", action: #selector(resetZoom), keyEquivalent: "0")
        viewMenu.addItem(.separator())
        viewMenu.addItem(withTitle: "Toggle Content Width", action: #selector(toggleWidth), keyEquivalent: "\\")
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        // Go menu
        let goMenuItem = NSMenuItem()
        let goMenu = NSMenu(title: "Go")
        goMenu.addItem(withTitle: "Back", action: #selector(goBack), keyEquivalent: "[")
        goMenu.addItem(withTitle: "Forward", action: #selector(goForward), keyEquivalent: "]")
        goMenuItem.submenu = goMenu
        mainMenu.addItem(goMenuItem)

        // Window menu
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.zoom(_:)), keyEquivalent: "")
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }

    private func buildRecentMenu() -> NSMenu {
        let menu = NSMenu(title: "Open Recent")
        for path in Settings.shared.recentFiles.prefix(10) {
            let name = URL(fileURLWithPath: path).lastPathComponent
            let item = NSMenuItem(title: name, action: #selector(openRecentFile(_:)), keyEquivalent: "")
            item.representedObject = path
            item.toolTip = path
            menu.addItem(item)
        }
        if !Settings.shared.recentFiles.isEmpty {
            menu.addItem(.separator())
            menu.addItem(withTitle: "Clear Menu", action: #selector(clearRecent), keyEquivalent: "")
        }
        return menu
    }

    // MARK: - Menu Actions

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "Simply Markdown Reader"
        alert.informativeText = "A native macOS Markdown viewer\nwith warm, readable styling.\n\nVersion 1.0.2"
        alert.alertStyle = .informational
        alert.runModal()
    }

    @objc private func openSettings() {
        activeWindowController()?.openSettingsPanel()
    }

    @objc private func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText]
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            for url in panel.urls {
                openFileInWindow(path: url.path)
            }
        }
    }

    @objc private func openRecentFile(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        openFileInWindow(path: path)
    }

    @objc private func clearRecent() {
        Settings.shared.recentFiles = []
    }

    @objc private func exportPDF() { activeWindowController()?.exportPDF() }

    @objc private func printDocument() {
        activeWindowController()?.webView.evaluateJavaScript("window.print();", completionHandler: nil)
    }

    @objc private func closeWindow() { NSApp.keyWindow?.close() }
    @objc private func performFind() {
        activeWindowController()?.webView.evaluateJavaScript(
            "openSearch();", completionHandler: nil)
    }

    @objc private func toggleBookmark() {
        activeWindowController()?.webView.evaluateJavaScript("sendToSwift('toggleBookmark');", completionHandler: nil)
    }
    @objc private func reloadFile() { activeWindowController()?.reloadCurrentFile() }
    @objc private func toggleTOC() { activeWindowController()?.toggleTOC() }
    @objc private func toggleSource() { activeWindowController()?.toggleSource() }
    @objc private func zoomIn() { activeWindowController()?.zoomIn() }
    @objc private func zoomOut() { activeWindowController()?.zoomOut() }
    @objc private func resetZoom() { activeWindowController()?.resetZoom() }
    @objc private func toggleWidth() { activeWindowController()?.toggleContentWidth() }
    @objc private func goBack() { activeWindowController()?.goBack() }
    @objc private func goForward() { activeWindowController()?.goForward() }
}
