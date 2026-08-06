import SwiftUI

@main
struct CaptionStudioApp: App {
    @StateObject private var editor = EditorViewModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(editor)
                .preferredColorScheme(.dark)
        }
        #if os(macOS)
        .defaultSize(width: 1180, height: 760)
        #endif
    }
}

struct RootView: View {
    @EnvironmentObject private var editor: EditorViewModel

    var body: some View {
        Group {
            if editor.project.videoURL == nil {
                HomeView()
            } else {
                EditorView()
            }
        }
        .animation(.easeInOut(duration: 0.35), value: editor.project.videoURL != nil)
        .alert("Something went wrong", isPresented: Binding(
            get: { editor.errorMessage != nil },
            set: { if !$0 { editor.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { editor.errorMessage = nil }
        } message: {
            Text(editor.errorMessage ?? "")
        }
    }
}
