import AppKit
import SwiftUI

struct SearchInputView: View {
    @Binding var text: String
    @Binding var isActive: Bool
    let placeholder: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            Text(text.isEmpty ? placeholder : text)
                .foregroundStyle(text.isEmpty ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .font(.callout)
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isActive ? Color.accentColor : Color(nsColor: .separatorColor).opacity(0.75), lineWidth: isActive ? 2 : 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            isActive = true
        }
        .background(KeyboardSearchCapture(text: $text, isActive: $isActive))
    }
}

private struct KeyboardSearchCapture: NSViewRepresentable {
    @Binding var text: String
    @Binding var isActive: Bool

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.text = $text
        context.coordinator.isActive = $isActive
        context.coordinator.updateMonitor()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isActive: $isActive)
    }

    final class Coordinator {
        var text: Binding<String>
        var isActive: Binding<Bool>
        private var monitor: Any?

        init(text: Binding<String>, isActive: Binding<Bool>) {
            self.text = text
            self.isActive = isActive
        }

        deinit {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }

        func updateMonitor() {
            guard monitor == nil else {
                return
            }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handle(event) ?? event
            }
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            guard isActive.wrappedValue else {
                return event
            }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags.contains(.command) || flags.contains(.control) {
                return event
            }

            switch event.keyCode {
            case 36, 48, 53:
                isActive.wrappedValue = false
                return nil
            case 123, 124, 125, 126:
                return nil
            case 51, 117:
                if !text.wrappedValue.isEmpty {
                    text.wrappedValue.removeLast()
                }
                return nil
            default:
                guard let characters = event.characters, !characters.isEmpty else {
                    return event
                }
                text.wrappedValue.append(characters)
                return nil
            }
        }
    }
}
