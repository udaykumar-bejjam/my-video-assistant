import SwiftUI
#if os(macOS)
import AppKit
#endif

/// macOS / hardware-keyboard shortcuts for the editor (P1.3).
/// Skips when a text field is first responder so typing captions stays intact.
struct EditorShortcutsModifier: ViewModifier {
    @EnvironmentObject private var editor: EditorViewModel
    @FocusState private var editorFocused: Bool

    func body(content: Content) -> some View {
        content
            .focusable()
            .focused($editorFocused)
            .onAppear { editorFocused = true }
            .onKeyPress(keys: [.space]) { _ in
                guard !isEditingText else { return .ignored }
                editor.togglePlayback()
                return .handled
            }
            .onKeyPress(keys: [.delete, .deleteForward]) { _ in
                guard !isEditingText else { return .ignored }
                return editor.deleteTimelineSelection() ? .handled : .ignored
            }
            .onKeyPress(keys: [.escape]) { _ in
                guard !isEditingText else { return .ignored }
                editor.clearTimelineMultiSelection()
                return .handled
            }
            .onKeyPress(keys: [.leftArrow, .rightArrow]) { press in
                guard !isEditingText else { return .ignored }
                let sign: TimeInterval = press.key == .leftArrow ? -1 : 1
                let delta = sign * EditorShortcuts.nudgeDelta(shift: press.modifiers.contains(.shift))
                _ = editor.nudgeSelectionOrPlayhead(delta: delta)
                return .handled
            }
            .onKeyPress(characters: .init(charactersIn: "jklJKL")) { press in
                guard !isEditingText else { return .ignored }
                guard let ch = press.characters.lowercased().first else { return .ignored }
                switch ch {
                case "j":
                    editor.bumpPlaybackJKL(forward: false)
                case "k":
                    editor.pausePlayback()
                case "l":
                    editor.bumpPlaybackJKL(forward: true)
                default:
                    return .ignored
                }
                return .handled
            }
    }

    private var isEditingText: Bool {
        #if os(macOS)
        guard let fr = NSApp.keyWindow?.firstResponder else { return false }
        return fr is NSTextView || fr is NSTextField
        #else
        return false
        #endif
    }
}

extension View {
    func editorTransportShortcuts() -> some View {
        modifier(EditorShortcutsModifier())
    }
}
