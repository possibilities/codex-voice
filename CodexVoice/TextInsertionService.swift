import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Foundation

@MainActor
final class TextInsertionService {
    func insert(_ text: String) async -> Bool {
        guard !text.isEmpty else {
            DebugLogger.write("Insert aborted: empty text")
            return false
        }

        let frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
        DebugLogger.write("Insert starting for frontmost app: \(frontmostBundleID)")

        if shouldPreferPasteboard(for: frontmostBundleID) {
            DebugLogger.write("Preferring pasteboard insert for app: \(frontmostBundleID)")
            if await insertViaPasteboard(text) {
                return true
            }
        }

        if insertViaAccessibility(text, frontmostBundleID: frontmostBundleID) {
            DebugLogger.write("Insert succeeded via Accessibility")
            return true
        }

        DebugLogger.write("Accessibility insert failed, falling back to pasteboard")
        return await insertViaPasteboard(text)
    }

    private func insertViaAccessibility(_ text: String, frontmostBundleID: String) -> Bool {
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedObject: CFTypeRef?
        let focusedResult = AXUIElementCopyAttributeValue(
            systemWideElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedObject
        )

        guard focusedResult == .success, let focusedObject else {
            DebugLogger.write("AX focused element lookup failed: \(focusedResult.rawValue)")
            return false
        }

        let element = unsafeDowncast(focusedObject, to: AXUIElement.self)
        let role = stringValue(for: kAXRoleAttribute as CFString, element: element) ?? "unknown"
        let subrole = stringValue(for: kAXSubroleAttribute as CFString, element: element) ?? "none"
        DebugLogger.write("AX focused role=\(role) subrole=\(subrole) app=\(frontmostBundleID)")

        let selectedTextSetResult = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )

        if selectedTextSetResult == .success {
            DebugLogger.write("AX selected text replacement succeeded")
            return true
        } else {
            DebugLogger.write("AX selected text replacement failed: \(selectedTextSetResult.rawValue)")
        }

        var selectedRangeObject: CFTypeRef?
        let selectedRangeResult = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &selectedRangeObject
        )

        if selectedRangeResult == .success,
           let selectedRangeObject,
           CFGetTypeID(selectedRangeObject) == AXValueGetTypeID() {
            let selectedRangeValue = unsafeDowncast(selectedRangeObject, to: AXValue.self)
            var selectedRange = CFRange()
            if AXValueGetValue(selectedRangeValue, .cfRange, &selectedRange) {
                var valueObject: CFTypeRef?
                let valueResult = AXUIElementCopyAttributeValue(
                    element,
                    kAXValueAttribute as CFString,
                    &valueObject
                )

                if valueResult == .success, let currentValue = valueObject as? String {
                    let nsValue = currentValue as NSString
                    let replacementRange = NSRange(location: selectedRange.location, length: selectedRange.length)
                    guard replacementRange.location != NSNotFound,
                          replacementRange.upperBound <= nsValue.length else {
                        return false
                    }

                    let updatedValue = nsValue.replacingCharacters(in: replacementRange, with: text)
                    var updatedSelection = CFRange(location: selectedRange.location + (text as NSString).length, length: 0)

                    let valueSetResult = AXUIElementSetAttributeValue(
                        element,
                        kAXValueAttribute as CFString,
                        updatedValue as CFTypeRef
                    )

                    guard valueSetResult == .success else {
                        DebugLogger.write("AX value set failed: \(valueSetResult.rawValue)")
                        return false
                    }

                    if let updatedSelectionValue = AXValueCreate(.cfRange, &updatedSelection) {
                        _ = AXUIElementSetAttributeValue(
                            element,
                            kAXSelectedTextRangeAttribute as CFString,
                            updatedSelectionValue
                        )
                    }

                    return true
                }
            }
        }

        DebugLogger.write("AX insert path unavailable")
        return false
    }

    private func shouldPreferPasteboard(for bundleIdentifier: String) -> Bool {
        let pasteFirstApps = [
            "com.google.Chrome",
            "com.google.Chrome.canary",
            "com.microsoft.edgemac",
            "com.brave.Browser",
            "company.thebrowser.Browser",
            "org.mozilla.firefox",
            "com.electron.",
            "com.todesktop.",
            "com.tinyspeck.slackmacgap",
            "com.apple.Safari",
        ]

        return pasteFirstApps.contains(where: { bundleIdentifier == $0 || bundleIdentifier.hasPrefix($0) })
    }

    private func stringValue(for attribute: CFString, element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success else {
            return nil
        }

        return value as? String
    }

    private func insertViaPasteboard(_ text: String) async -> Bool {
        let targetApplication = NSWorkspace.shared.frontmostApplication
        DebugLogger.write("Paste fallback targeting app: \(targetApplication?.bundleIdentifier ?? "unknown")")
        let pasteboard = NSPasteboard.general
        let previousItems = pasteboard.pasteboardItems?.map { item in
            item.types.reduce(into: [NSPasteboard.PasteboardType: Data]()) { result, type in
                if let data = item.data(forType: type) {
                    result[type] = data
                }
            }
        }

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        await waitForHotkeyModifiersToRelease()
        try? await Task.sleep(for: .milliseconds(100))

        NSApp.deactivate()
        targetApplication?.activate(options: [.activateIgnoringOtherApps])
        try? await Task.sleep(for: .milliseconds(120))

        let didPaste = pasteWithAppleScript() || pasteWithCGEvents()
        DebugLogger.write("Paste fallback result: \(didPaste)")

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            restorePasteboard(previousItems)
        }

        return didPaste
    }

    private func waitForHotkeyModifiersToRelease() async {
        for _ in 0 ..< 12 {
            let leftControlDown = CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(kVK_Control))
            let rightControlDown = CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(kVK_RightControl))

            guard leftControlDown || rightControlDown else {
                return
            }

            try? await Task.sleep(for: .milliseconds(25))
        }
    }

    private func pasteWithAppleScript() -> Bool {
        let source = """
        tell application id "com.apple.systemevents"
            keystroke "v" using command down
        end tell
        """

        guard let script = NSAppleScript(source: source) else {
            return false
        }

        var error: NSDictionary?
        script.executeAndReturnError(&error)
        if let error {
            DebugLogger.write("AppleScript paste failed: \(error)")
        } else {
            DebugLogger.write("AppleScript paste succeeded")
        }
        return error == nil
    }

    private func pasteWithCGEvents() -> Bool {
        let commandDown = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_Command), keyDown: true)
        commandDown?.flags = .maskCommand
        let vDown = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
        vDown?.flags = .maskCommand
        let vUp = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        vUp?.flags = .maskCommand
        let commandUp = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_Command), keyDown: false)

        guard let commandDown, let vDown, let vUp, let commandUp else {
            return false
        }

        commandDown.post(tap: .cghidEventTap)
        vDown.post(tap: .cghidEventTap)
        vUp.post(tap: .cghidEventTap)
        commandUp.post(tap: .cghidEventTap)
        DebugLogger.write("CGEvent paste posted")
        return true
    }

    private func restorePasteboard(_ items: [[NSPasteboard.PasteboardType: Data]]?) {
        guard let items else {
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        for item in items {
            let pasteboardItem = NSPasteboardItem()
            for (type, data) in item {
                pasteboardItem.setData(data, forType: type)
            }
            pasteboard.writeObjects([pasteboardItem])
        }
    }
}
