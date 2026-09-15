import SwiftUI

@main
struct SoundtrackApp: App {
    @StateObject private var recorder = SystemAudioRecorder()

    var body: some Scene {
        Window("Soundtrack", id: "main") {
            ContentView(recorder: recorder)
                .onAppear {
                    Task { await recorder.runCommandLineIfNeeded() }
                }
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}
