import SwiftUI

struct ContentView: View {
    @Environment(Library.self) private var library
    @Environment(AudioPlayer.self) private var player
    @State private var selection: UUID?

    var body: some View {
        NavigationSplitView {
            TrackListView(selection: $selection)
        } detail: {
            if player.track != nil {
                PlayerView()
            } else {
                ContentUnavailableView(
                    "Kein Titel ausgewählt",
                    systemImage: "music.note",
                    description: Text("Wähle links einen Titel aus der Liste.")
                )
            }
        }
        .onChange(of: selection) { _, id in
            guard let id, id != player.track?.id, let track = library.track(withID: id) else { return }
            player.load(track, url: library.fileURL(for: track))
        }
        .onChange(of: library.tracks.map(\.id)) { _, ids in
            // The playing track was deleted.
            if let current = player.track?.id, !ids.contains(current) {
                player.unload()
            }
            if let selection, !ids.contains(selection) {
                self.selection = nil
            }
        }
        .playerKeyboardShortcuts(player)
        .alert("Fehler", isPresented: errorBinding) {
            Button("OK") {
                library.lastError = nil
                player.errorMessage = nil
            }
        } message: {
            Text(library.lastError ?? player.errorMessage ?? "")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { library.lastError != nil || player.errorMessage != nil },
            set: { if !$0 { library.lastError = nil; player.errorMessage = nil } }
        )
    }
}
