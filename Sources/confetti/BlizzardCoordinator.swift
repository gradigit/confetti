import AppKit
import ConfettiKit

/// Global PID file path for atexit cleanup (C function pointers can't capture context)
private let blizzardPIDFilePath = "/tmp/confetti-blizzard.pid"

/// Manages singleton blizzard lifecycle with multi-session escalation via IPC.
///
/// - First launch: claims PID file, starts blizzard, listens for escalation notifications
/// - Subsequent launches: post escalation notification and exit immediately
/// - Per-session file watchers trigger de-escalation when transcripts change
/// - Last session removal → stopSnowing → melt → cleanup → exit
final class BlizzardCoordinator {

    private let pidFilePath = blizzardPIDFilePath
    private let notificationName = Notification.Name("com.confetti.blizzard.escalate")

    private var controller: ConfettiController?
    private var transcriptWatchers: [String: TranscriptWatcher] = [:]  // sessionID → watcher
    private var sessionIDs: [String] = []  // ordered list of session IDs

    private var sigTermSource: DispatchSourceSignal?
    private let screens: [NSScreen]
    private let windowLevel: WindowLevel
    private let duration: Double?

    /// The default session ID created on first launch (before any escalation)
    private let defaultSessionID = "__default__"

    init(screens: [NSScreen], windowLevel: WindowLevel, duration: Double?) {
        self.screens = screens
        self.windowLevel = windowLevel
        self.duration = duration
    }

    // MARK: - Entry Point

    /// Returns true if this process should continue running (is the owner).
    /// Returns false if it posted an escalation and should exit.
    func start(transcriptPath: String?) -> Bool {
        // Check if an owner already exists
        if let existingPID = readPIDFile() {
            if isProcessAlive(existingPID) {
                // Owner exists — post escalation and exit
                postEscalation(transcriptPath: transcriptPath)
                return false
            } else {
                // Stale PID file — clean up
                try? FileManager.default.removeItem(atPath: pidFilePath)
            }
        }

        // Try to claim ownership
        guard claimPIDFile() else {
            // Race condition: another process claimed it first
            postEscalation(transcriptPath: transcriptPath)
            return false
        }

        // We are the owner
        setupSIGTERM()
        setupNotificationListener()
        setupExitCleanup()
        startBlizzard(transcriptPath: transcriptPath)
        return true
    }

    // MARK: - Blizzard Lifecycle

    private func startBlizzard(transcriptPath: String?) {
        let ctrl = ConfettiController(
            config: .blizzard,
            angles: .default,
            emissionDuration: 0,
            intensity: 1.0,
            windowLevel: windowLevel
        )

        ctrl.onBlizzardComplete = { [weak self] in
            self?.handleBlizzardComplete()
        }

        ctrl.fire(on: screens)
        self.controller = ctrl

        // Add the default session layer and register watcher
        sessionIDs.append(defaultSessionID)
        ctrl.escalateBlizzard(sessionID: defaultSessionID)
        if let path = transcriptPath {
            addWatcher(sessionID: defaultSessionID, path: path)
        }

        // Duration timeout
        if let dur = duration {
            DispatchQueue.main.asyncAfter(deadline: .now() + dur) { [weak self] in
                self?.controller?.stopSnowing()
            }
        }
    }

    private func handleBlizzardComplete() {
        controller?.cleanup()
        removePIDFile()
        NSApp.terminate(nil)
    }

    /// Graceful shutdown — triggers melt animation before exit.
    func gracefulShutdown() {
        controller?.stopSnowing()
    }

    // MARK: - Session Management

    private func addSession(transcriptPath: String?) {
        let sessionID = UUID().uuidString

        sessionIDs.append(sessionID)
        controller?.escalateBlizzard(sessionID: sessionID)

        if let path = transcriptPath {
            addWatcher(sessionID: sessionID, path: path)
        }
    }

    private func removeSession(_ sessionID: String) {
        transcriptWatchers[sessionID]?.cancel()
        transcriptWatchers.removeValue(forKey: sessionID)
        sessionIDs.removeAll { $0 == sessionID }

        controller?.deescalateBlizzard(sessionID: sessionID)
    }

    private func addWatcher(sessionID: String, path: String) {
        guard let watcher = TranscriptWatcher(path: path) else { return }
        watcher.onChange = { [weak self] in
            self?.removeSession(sessionID)
        }
        transcriptWatchers[sessionID] = watcher
    }

    // MARK: - PID File

    private func readPIDFile() -> pid_t? {
        guard let data = FileManager.default.contents(atPath: pidFilePath),
              let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let pid = Int32(str) else {
            return nil
        }
        return pid
    }

    private func claimPIDFile() -> Bool {
        let pid = "\(getpid())\n"
        let fd = open(pidFilePath, O_WRONLY | O_CREAT | O_EXCL, 0o644)
        guard fd >= 0 else { return false }
        _ = pid.withCString { write(fd, $0, strlen($0)) }
        close(fd)
        return true
    }

    private func removePIDFile() {
        try? FileManager.default.removeItem(atPath: pidFilePath)
    }

    private func isProcessAlive(_ pid: pid_t) -> Bool {
        return kill(pid, 0) == 0
    }

    // MARK: - IPC

    private func postEscalation(transcriptPath: String?) {
        var userInfo: [String: String] = [:]
        if let path = transcriptPath {
            userInfo["transcriptPath"] = path
        }
        DistributedNotificationCenter.default().postNotificationName(
            notificationName,
            object: nil,
            userInfo: userInfo,
            deliverImmediately: true
        )
    }

    private func setupNotificationListener() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleEscalationNotification(_:)),
            name: notificationName,
            object: nil
        )
    }

    @objc private func handleEscalationNotification(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            let transcriptPath = notification.userInfo?["transcriptPath"] as? String
            self?.addSession(transcriptPath: transcriptPath)
        }
    }

    // MARK: - Signal Handling

    private func setupSIGTERM() {
        // Ignore default SIGTERM so dispatch source can handle it
        signal(SIGTERM, SIG_IGN)

        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { [weak self] in
            self?.gracefulShutdown()
        }
        source.resume()
        sigTermSource = source
    }

    // MARK: - Exit Cleanup

    private func setupExitCleanup() {
        // Belt-and-suspenders for unexpected exits
        atexit {
            unlink(blizzardPIDFilePath)
        }
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
        sigTermSource?.cancel()
        removePIDFile()
    }
}
