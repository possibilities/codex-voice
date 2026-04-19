import AVFoundation
import Foundation

struct RecordedAudio {
    let url: URL
    let contentType: String
    let filename: String
}

enum AudioCaptureError: LocalizedError {
    case authorizationDenied
    case recorderUnavailable

    var errorDescription: String? {
        switch self {
        case .authorizationDenied:
            return "Microphone permission was denied."
        case .recorderUnavailable:
            return "The microphone could not start recording."
        }
    }
}

@MainActor
final class AudioCaptureService {
    private let permissionCoordinator: PermissionCoordinator
    private var recorder: AVAudioRecorder?
    private var currentRecordingURL: URL?
    private var recordingStartedAt: Date?

    init(permissionCoordinator: PermissionCoordinator) {
        self.permissionCoordinator = permissionCoordinator
    }

    func start() async throws {
        guard await permissionCoordinator.requestMicrophonePermission() else {
            DebugLogger.write("Microphone permission denied")
            throw AudioCaptureError.authorizationDenied
        }

        cancel()

        let recordingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-voice-\(UUID().uuidString)")
            .appendingPathExtension("wav")

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
        ]

        let recorder = try AVAudioRecorder(url: recordingURL, settings: settings)
        recorder.isMeteringEnabled = true

        guard recorder.record() else {
            DebugLogger.write("Recorder failed to start")
            throw AudioCaptureError.recorderUnavailable
        }

        self.recorder = recorder
        currentRecordingURL = recordingURL
        recordingStartedAt = Date()
        DebugLogger.write("Recording started: \(recordingURL.lastPathComponent)")
    }

    func stop() -> RecordedAudio? {
        guard let recorder, let recordingURL = currentRecordingURL else {
            DebugLogger.write("Stop called without active recorder")
            return nil
        }

        let duration = Date().timeIntervalSince(recordingStartedAt ?? Date())
        recorder.stop()
        self.recorder = nil
        currentRecordingURL = nil
        recordingStartedAt = nil
        DebugLogger.write("Recording stopped: duration=\(String(format: "%.2f", duration))s file=\(recordingURL.lastPathComponent)")

        guard duration >= 0.12 else {
            DebugLogger.write("Recording too short, discarded")
            deleteFile(at: recordingURL)
            return nil
        }

        return RecordedAudio(
            url: recordingURL,
            contentType: "audio/wav",
            filename: recordingURL.lastPathComponent
        )
    }

    func cancel() {
        recorder?.stop()
        DebugLogger.write("Recording cancelled")

        if let currentRecordingURL {
            deleteFile(at: currentRecordingURL)
        }

        recorder = nil
        currentRecordingURL = nil
        recordingStartedAt = nil
    }

    func deleteRecording(_ recording: RecordedAudio) {
        DebugLogger.write("Deleting recording: \(recording.filename)")
        deleteFile(at: recording.url)
    }

    private func deleteFile(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
