import SwiftUI

@main
struct WoodshedPlayerApp: App {
    @State private var library = Library()
    @State private var player = AudioPlayer()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(library)
                .environment(player)
                .onAppear {
                    player.onSettingsChanged = { [library] id, settings in
                        library.updateSettings(settings, for: id)
                    }
                }
        }
        #if os(macOS)
        .defaultSize(width: 980, height: 640)
        #endif
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { library.save() }
        }
    }
}
