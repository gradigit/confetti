import Foundation

/// Watches a file for modifications using GCD file system events.
/// Records initial file size at creation and fires `onChange` at most once
/// when the file grows beyond that initial size.
final class TranscriptWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private let path: String
    private let initialSize: UInt64
    private var hasFired = false

    /// Called at most once when the watched file grows. Always called on main queue.
    var onChange: (() -> Void)?

    /// Creates a watcher for the file at `path`.
    /// Returns `nil` if the file can't be opened (prints warning to stderr).
    init?(path: String) {
        self.path = path

        // Get initial file size
        if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
           let size = attrs[.size] as? UInt64 {
            self.initialSize = size
        } else {
            self.initialSize = 0
        }

        // Open file descriptor for event monitoring only
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else {
            fputs("Warning: cannot watch '\(path)' (open failed), running without file watcher\n", stderr)
            return nil
        }
        self.fileDescriptor = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            self?.handleEvent()
        }

        source.setCancelHandler { [weak self] in
            guard let self = self else { return }
            if self.fileDescriptor >= 0 {
                close(self.fileDescriptor)
                self.fileDescriptor = -1
            }
        }

        self.source = source
        source.resume()
    }

    private func handleEvent() {
        guard !hasFired else { return }

        // Check if file actually grew beyond initial size
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let currentSize = attrs[.size] as? UInt64,
              currentSize > initialSize else {
            return
        }

        hasFired = true
        source?.cancel()
        source = nil
        onChange?()
    }

    func cancel() {
        source?.cancel()
        source = nil
    }

    deinit {
        cancel()
    }
}
