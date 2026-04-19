import AppKit
import Foundation

@MainActor
final class DictationController {
    enum State {
        case idle
        case recording
        case transcribing
        case inserting
        case error(String)

        var statusText: String {
            switch self {
            case .idle:
                return "Idle"
            case .recording:
                return "Listening…"
            case .transcribing:
                return "Transcribing with Codex…"
            case .inserting:
                return "Inserting…"
            case .error(let message):
                return message
            }
        }
    }

    private let permissionCoordinator: PermissionCoordinator
    private let audioCaptureService: AudioCaptureService
    private let transcriptionService: CodexTranscriptionService
    private let textInsertionService: TextInsertionService

    private(set) var state: State = .idle {
        didSet {
            onStateChange?(state)
        }
    }

    var onStateChange: ((State) -> Void)?

    init(
        permissionCoordinator: PermissionCoordinator,
        audioCaptureService: AudioCaptureService,
        transcriptionService: CodexTranscriptionService,
        textInsertionService: TextInsertionService
    ) {
        self.permissionCoordinator = permissionCoordinator
        self.audioCaptureService = audioCaptureService
        self.transcriptionService = transcriptionService
        self.textInsertionService = textInsertionService
    }

    func handleHotkeyPressed() {
        switch state {
        case .recording, .transcribing, .inserting:
            DebugLogger.write("Hotkey press ignored because state=\(state.statusText)")
            return
        case .idle, .error:
            break
        }

        DebugLogger.write("Hotkey pressed")
        Task { @MainActor in
            await beginDictation()
        }
    }

    func handleHotkeyReleased() {
        guard case .recording = state else {
            DebugLogger.write("Hotkey release ignored because state=\(state.statusText)")
            return
        }

        DebugLogger.write("Hotkey released")
        Task { @MainActor in
            await finishDictation()
        }
    }

    private func beginDictation() async {
        do {
            try await audioCaptureService.start()
            state = .recording
        } catch {
            DebugLogger.write("Begin dictation failed: \(error.localizedDescription)")
            state = .error(error.localizedDescription)
        }
    }

    private func finishDictation() async {
        state = .transcribing
        guard let recording = audioCaptureService.stop() else {
            state = .idle
            return
        }

        let transcript: String
        do {
            transcript = try await transcriptionService.transcribe(recording)
        } catch {
            audioCaptureService.deleteRecording(recording)
            if case AudioCaptureError.authorizationDenied = error {
                permissionCoordinator.openMicrophoneSettings()
            }
            DebugLogger.write("Finish dictation failed during transcription: \(error.localizedDescription)")
            state = .error(error.localizedDescription)
            return
        }

        audioCaptureService.deleteRecording(recording)

        guard !transcript.isEmpty else {
            DebugLogger.write("Transcript was empty")
            state = .idle
            return
        }

        state = .inserting
        switch permissionCoordinator.accessibilityStatus(promptIfNeeded: true) {
        case .trusted:
            let inserted = await textInsertionService.insert(transcript)
            DebugLogger.write("Insert result: \(inserted)")
            if inserted {
                state = .idle
            } else {
                state = .error("Insert failed")
            }
        case .needsPrompt:
            permissionCoordinator.openAccessibilitySettings()
            DebugLogger.write("Accessibility permission missing at insert time")
            state = .error("Grant Accessibility")
        }
    }
}
