import AppKit
import SwiftUI

struct NativeSearchField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String

    /// Called when the field gains or loses first responder, so the shared selection model
    /// knows whether the search field owns key input. Without this, media shortcuts would
    /// be blocked only as a side effect of the browser resigning focus, which is fragile.
    var onFocusChange: ((Bool) -> Void)?

    func makeNSView(context: Context) -> NSSearchField {
        let searchField = FocusableSearchField()
        searchField.onFocusChange = onFocusChange
        searchField.placeholderString = placeholder
        searchField.delegate = context.coordinator
        searchField.sendsSearchStringImmediately = true
        searchField.controlSize = .regular
        searchField.isEditable = true
        searchField.isSelectable = true
        searchField.isEnabled = true
        searchField.focusRingType = .default
        searchField.setAccessibilityIdentifier("media-search-field")
        searchField.setAccessibilityLabel("Search media")
        return searchField
    }

    func updateNSView(_ searchField: NSSearchField, context: Context) {
        context.coordinator.text = $text
        if searchField.stringValue != text {
            searchField.stringValue = text
        }
        searchField.placeholderString = placeholder
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let searchField = notification.object as? NSSearchField else {
                return
            }
            text.wrappedValue = searchField.stringValue
        }
    }
}

private final class FocusableSearchField: NSSearchField {
    var onFocusChange: ((Bool) -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted {
            onFocusChange?(true)
        }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned {
            onFocusChange?(false)
        }
        return resigned
    }

    override func mouseDown(with event: NSEvent) {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        super.mouseDown(with: event)

        if currentEditor() == nil {
            window?.makeFirstResponder(self)
        }
    }
}
