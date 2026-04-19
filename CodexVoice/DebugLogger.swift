import Foundation

actor DebugLogger {
    static let shared = DebugLogger()
    private static let isEnabled = ProcessInfo.processInfo.environment["CODEX_VOICE_DEBUG_LOG"] == "1"

    private let logURL: URL = {
        let directoryURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("Logs")
        return directoryURL.appendingPathComponent("CodexVoice.log")
    }()

    func log(_ message: String) {
        guard Self.isEnabled else {
            return
        }

        let formatter = ISO8601DateFormatter()
        let line = "[\(formatter.string(from: Date()))] \(message)\n"

        do {
            let directoryURL = logURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

            if FileManager.default.fileExists(atPath: logURL.path) {
                let handle = try FileHandle(forWritingTo: logURL)
                try handle.seekToEnd()
                handle.write(Data(line.utf8))
                try handle.close()
            } else {
                try Data(line.utf8).write(to: logURL, options: .atomic)
            }
        } catch {
            print("CodexVoice log write failed: \(error.localizedDescription)")
        }
    }

    func reset() {
        guard Self.isEnabled else {
            return
        }

        try? FileManager.default.removeItem(at: logURL)
    }

    nonisolated static func write(_ message: String) {
        Task {
            await DebugLogger.shared.log(message)
        }
    }

    nonisolated static func clear() {
        Task {
            await DebugLogger.shared.reset()
        }
    }
}
