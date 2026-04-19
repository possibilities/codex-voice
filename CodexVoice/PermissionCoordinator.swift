import AppKit
import AVFoundation
import ApplicationServices
import Foundation

@MainActor
final class PermissionCoordinator {
    private let accessibilityPromptKey = "AXTrustedCheckOptionPrompt" as CFString

    enum AccessibilityStatus {
        case trusted
        case needsPrompt
    }

    func requestMicrophonePermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    func accessibilityStatus(promptIfNeeded: Bool) -> AccessibilityStatus {
        let options = [accessibilityPromptKey: promptIfNeeded] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        DebugLogger.write("Accessibility trusted=\(trusted) promptIfNeeded=\(promptIfNeeded)")
        return trusted ? .trusted : .needsPrompt
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    func openMicrophoneSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") else {
            return
        }

        NSWorkspace.shared.open(url)
    }
}
