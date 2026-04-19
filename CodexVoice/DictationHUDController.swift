import AppKit
import SwiftUI

@MainActor
final class DictationHUDController {
    private let viewModel = DictationHUDViewModel()
    private lazy var panel: NSPanel = {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 248, height: 72),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.isMovable = false
        panel.contentView = NSHostingView(rootView: DictationHUDView(viewModel: viewModel))
        return panel
    }()

    private var hideWorkItem: DispatchWorkItem?

    func update(for state: DictationController.State) {
        hideWorkItem?.cancel()
        viewModel.state = state

        switch state {
        case .idle:
            hide(animated: true, delay: 0.05)
        case .recording, .transcribing, .inserting:
            show()
        case .error:
            show()
            hide(animated: true, delay: 1.8)
        }
    }

    private func show() {
        positionPanel()
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                panel.animator().alphaValue = 1
            }
        } else {
            panel.orderFrontRegardless()
        }
    }

    private func hide(animated: Bool, delay: TimeInterval) {
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else {
                return
            }

            guard self.panel.isVisible else {
                return
            }

            if animated {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.18
                    self.panel.animator().alphaValue = 0
                } completionHandler: {
                    DispatchQueue.main.async {
                        self.panel.orderOut(nil)
                    }
                }
            } else {
                self.panel.orderOut(nil)
            }
        }

        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func positionPanel() {
        let frame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = panel.frame.size
        let origin = NSPoint(
            x: frame.maxX - size.width - 24,
            y: frame.minY + 24
        )
        panel.setFrameOrigin(origin)
    }
}

@MainActor
private final class DictationHUDViewModel: ObservableObject {
    @Published var state: DictationController.State = .idle
}

private struct DictationHUDView: View {
    @ObservedObject var viewModel: DictationHUDViewModel

    var body: some View {
        let presentation = HUDPresentation(state: viewModel.state)

        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThickMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.28), lineWidth: 1)
                }

            HStack(spacing: 10) {
                HUDGlyph(kind: presentation.kind)
                VStack(alignment: .leading, spacing: 2) {
                    Text(presentation.title)
                        .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text(presentation.subtitle)
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
        }
        .frame(width: 248, height: 72)
        .compositingGroup()
    }
}

private struct HUDGlyph: View {
    let kind: HUDPresentation.Kind

    var body: some View {
        ZStack {
            Circle()
                .fill(kind.background)
                .frame(width: 32, height: 32)

            switch kind {
            case .recording:
                RecordingGlyph()
            case .transcribing:
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
                    .scaleEffect(0.58)
            case .inserting:
                Image(systemName: "arrow.down.left.and.arrow.up.right")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white)
            case .error:
                Image(systemName: "exclamationmark")
                    .font(.system(size: 15.5, weight: .bold))
                    .foregroundStyle(.white)
            case .idle:
                EmptyView()
            }
        }
    }
}

private struct RecordingGlyph: View {
    @State private var animate = false

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(0 ..< 4, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(Color.white)
                    .frame(width: 3, height: animate ? [11, 16, 13, 9][index] : [7, 11, 9, 6][index])
                    .animation(
                        .easeInOut(duration: 0.45)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.08),
                        value: animate
                    )
            }
        }
        .onAppear {
            animate = true
        }
    }
}

private struct HUDPresentation {
    enum Kind {
        case idle
        case recording
        case transcribing
        case inserting
        case error

        var background: Color {
            switch self {
            case .idle:
                return .gray
            case .recording:
                return Color(red: 0.92, green: 0.24, blue: 0.24)
            case .transcribing:
                return Color(red: 0.20, green: 0.49, blue: 0.94)
            case .inserting:
                return Color(red: 0.19, green: 0.67, blue: 0.38)
            case .error:
                return Color(red: 0.95, green: 0.62, blue: 0.20)
            }
        }
    }

    let kind: Kind
    let title: String
    let subtitle: String

    init(state: DictationController.State) {
        switch state {
        case .idle:
            kind = .idle
            title = "Codex Voice"
            subtitle = "Ready"
        case .recording:
            kind = .recording
            title = "Listening"
            subtitle = "Release Control-M to transcribe"
        case .transcribing:
            kind = .transcribing
            title = "Transcribing with Codex"
            subtitle = "Using the Codex desktop backend"
        case .inserting:
            kind = .inserting
            title = "Inserting text"
            subtitle = "Dropping the transcript into the focused app"
        case .error(let message):
            kind = .error
            title = "Dictation stopped"
            subtitle = message
        }
    }
}
