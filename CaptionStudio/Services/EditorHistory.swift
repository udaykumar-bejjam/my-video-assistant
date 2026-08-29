import Foundation

/// Memento snapshot of editable editor document state (not playhead / export progress).
struct EditorDocumentSnapshot: Equatable {
    var project: VideoProject
    var selectedCaptionID: CaptionSegment.ID?
    var selectedOverlayID: OverlayItem.ID?
    var selectedSoundEffectID: SoundEffectCue.ID?
    var isAudioLayerSelected: Bool
    var selectedPreset: CaptionPreset
    var language: AppLanguage
    var trimSuggestions: [TrimSuggestion]
    var selectedTrimIDs: Set<UUID>
    var distribution: DistributionPackage?
    var editorTab: EditorViewModel.EditorTab
    var lastEnhancementNote: String?
}

/// Ring-buffer undo / redo for `EditorViewModel`.
@MainActor
final class EditorHistory {
    private var undoStack: [EditorDocumentSnapshot] = []
    private var redoStack: [EditorDocumentSnapshot] = []
    private let limit: Int

    init(limit: Int = 40) {
        self.limit = max(1, limit)
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var undoCount: Int { undoStack.count }
    var redoCount: Int { redoStack.count }

    func clear() {
        undoStack.removeAll()
        redoStack.removeAll()
    }

    /// Push current state before a mutating edit. Clears redo.
    func push(_ snapshot: EditorDocumentSnapshot) {
        if let last = undoStack.last, last == snapshot { return }
        undoStack.append(snapshot)
        if undoStack.count > limit {
            undoStack.removeFirst(undoStack.count - limit)
        }
        redoStack.removeAll()
    }

    /// Pop undo and stash current onto redo. Returns snapshot to restore.
    func undo(current: EditorDocumentSnapshot) -> EditorDocumentSnapshot? {
        guard let previous = undoStack.popLast() else { return nil }
        redoStack.append(current)
        return previous
    }

    func redo(current: EditorDocumentSnapshot) -> EditorDocumentSnapshot? {
        guard let next = redoStack.popLast() else { return nil }
        undoStack.append(current)
        return next
    }
}
