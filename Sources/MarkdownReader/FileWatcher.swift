import Foundation

// Watches a file for write events using GCD DispatchSource.
// Re-establishes the watch after rename/delete events so that
// atomic saves (write-to-temp then rename) keep working.
final class FileWatcher {
    private var source: DispatchSourceFileSystemObject?
    private let callback: () -> Void
    private var fileDescriptor: Int32 = -1
    private var watchedPath: String?

    init(path: String, callback: @escaping () -> Void) {
        self.callback = callback
        self.watchedPath = path
        startWatching(path: path)
    }

    private func startWatching(path: String) {
        stopSource()

        fileDescriptor = open(path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )

        src.setEventHandler { [weak self] in
            guard let self = self else { return }
            let flags = src.data
            self.callback()

            // Atomic save: editor wrote a temp file then renamed it over the original.
            // The old file descriptor now points to the deleted inode — re-watch the path.
            if flags.contains(.rename) || flags.contains(.delete) {
                self.restartWatching()
            }
        }

        src.setCancelHandler { [weak self] in
            guard let self = self else { return }
            if self.fileDescriptor >= 0 {
                close(self.fileDescriptor)
                self.fileDescriptor = -1
            }
        }

        src.resume()
        self.source = src
    }

    private func stopSource() {
        source?.cancel()
        source = nil
    }

    private func restartWatching() {
        stopSource()
        guard let path = watchedPath else { return }
        // Brief delay so the new file is fully in place
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.startWatching(path: path)
        }
    }

    func stop() {
        watchedPath = nil
        stopSource()
    }

    deinit {
        stop()
    }
}
