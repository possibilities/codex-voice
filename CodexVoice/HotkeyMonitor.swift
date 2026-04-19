import Carbon
import Foundation

@MainActor
final class HotkeyMonitor {
    private static var shared: HotkeyMonitor?

    private let hotKeyID = EventHotKeyID(signature: OSType(0x43565848), id: 1)
    private let onPress: () -> Void
    private let onRelease: () -> Void

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var isStarted = false

    init(onPress: @escaping () -> Void, onRelease: @escaping () -> Void) {
        self.onPress = onPress
        self.onRelease = onRelease
    }

    func start() {
        guard !isStarted else {
            DebugLogger.write("Hotkey monitor start ignored because it is already active")
            return
        }

        Self.shared = self

        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]

        let handler: EventHandlerUPP = { _, event, _ in
            guard let shared = HotkeyMonitor.shared, let event else {
                return noErr
            }

            var receivedHotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &receivedHotKeyID
            )

            guard status == noErr,
                  receivedHotKeyID.signature == shared.hotKeyID.signature,
                  receivedHotKeyID.id == shared.hotKeyID.id else {
                return noErr
            }

            let kind = GetEventKind(event)
            switch Int(kind) {
            case kEventHotKeyPressed:
                shared.onPress()
            case kEventHotKeyReleased:
                shared.onRelease()
            default:
                break
            }

            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            handler,
            eventTypes.count,
            &eventTypes,
            nil,
            &eventHandlerRef
        )

        RegisterEventHotKey(
            UInt32(kVK_ANSI_M),
            UInt32(controlKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        isStarted = true
        DebugLogger.write("Hotkey monitor started")
    }
}
