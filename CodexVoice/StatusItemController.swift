import AppKit
import Foundation

@MainActor
final class StatusItemController {
    private let permissionCoordinator: PermissionCoordinator
    private let dictationController: DictationController

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    init(permissionCoordinator: PermissionCoordinator, dictationController: DictationController) {
        self.permissionCoordinator = permissionCoordinator
        self.dictationController = dictationController
    }

    func start() {
        configureButton()
        configureMenu()
        updateAppearance(for: .idle)
    }

    func handleStateChange(_ state: DictationController.State) {
        updateAppearance(for: state)
    }

    private func configureButton() {
        statusItem.button?.title = "CV"
        statusItem.button?.toolTip = "Codex Voice"
    }

    private func configureMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Hold Control-M to dictate", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())

        let accessibilityItem = NSMenuItem(title: "Open Accessibility Settings", action: #selector(openAccessibilitySettings), keyEquivalent: "")
        accessibilityItem.target = self
        menu.addItem(accessibilityItem)

        let settingsItem = NSMenuItem(title: "Open Settings", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Codex Voice", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func updateAppearance(for state: DictationController.State) {
        statusItem.button?.title = switch state {
        case .idle:
            "CV"
        case .recording:
            "● CV"
        case .transcribing:
            "◌ CV"
        case .inserting:
            "… CV"
        case .error:
            "! CV"
        }

        statusItem.button?.toolTip = "Codex Voice: \(state.statusText)"
    }

    @objc
    private func openAccessibilitySettings() {
        permissionCoordinator.openAccessibilitySettings()
    }

    @objc
    private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc
    private func quit() {
        NSApp.terminate(nil)
    }
}
