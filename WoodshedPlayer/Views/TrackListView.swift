import SwiftUI
import UniformTypeIdentifiers

struct TrackListView: View {
    @Environment(Library.self) private var library
    @Environment(AudioPlayer.self) private var player
    @Binding var selection: UUID?
    @State private var showingImporter = false
    /// Folder that "MP3 hinzufügen" imports into (nil = no folder).
    @State private var importFolder: UUID?
    @State private var pendingDeletion: Set<UUID> = []
    @State private var pendingFolderDeletion: TrackFolder?
    @State private var folderPrompt: FolderPrompt?
    @State private var folderName = ""
    @State private var collapsedFolders: Set<UUID> = []

    /// What the name alert is for.
    private enum FolderPrompt {
        case create(moving: UUID?)
        case rename(UUID)
    }

    var body: some View {
        @Bindable var library = library
        let folders = library.sortedFolders

        List(selection: $selection) {
            let unfiled = library.sortedTracks(in: nil)
            if folders.isEmpty {
                trackRows(unfiled, folderID: nil)
            } else {
                Section {
                    if unfiled.isEmpty {
                        emptyRow(folderID: nil)
                    }
                    trackRows(unfiled, folderID: nil)
                } header: {
                    Label("Ohne Ordner", systemImage: "tray")
                        .dropDestination(for: String.self) { items, _ in dropTracks(items, into: nil) }
                }
                ForEach(folders) { folder in
                    Section(isExpanded: expandedBinding(folder.id)) {
                        let tracks = library.sortedTracks(in: folder.id)
                        if tracks.isEmpty {
                            emptyRow(folderID: folder.id)
                        }
                        trackRows(tracks, folderID: folder.id)
                    } header: {
                        Label(folder.name, systemImage: "folder")
                            .contextMenu { folderMenu(folder) }
                            .dropDestination(for: String.self) { items, _ in dropTracks(items, into: folder.id) }
                    }
                }
            }
        }
        .overlay {
            if library.tracks.isEmpty && folders.isEmpty {
                ContentUnavailableView {
                    Label("Keine Titel", systemImage: "music.note.list")
                } description: {
                    #if os(macOS)
                    Text("Füge MP3-Dateien mit + hinzu oder zieh sie hierher.")
                    #else
                    Text("Füge MP3-Dateien mit + hinzu.")
                    #endif
                } actions: {
                    Button("MP3 hinzufügen") { startImport(into: nil) }
                }
            }
        }
        .navigationTitle("Bibliothek")
        #if os(macOS)
        .navigationSplitViewColumnWidth(min: 240, ideal: 290)
        .onDeleteCommand {
            if let selection { pendingDeletion = [selection] }
        }
        #endif
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .topBarLeading) {
                EditButton()
            }
            #endif
            ToolbarItem {
                Menu {
                    Picker("Sortierung", selection: $library.sortOrder) {
                        ForEach(TrackSortOrder.allCases) { order in
                            Label(order.label, systemImage: order.systemImage).tag(order)
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label("Sortieren", systemImage: "arrow.up.arrow.down")
                }
                .help("Sortierung")
            }
            ToolbarItem {
                Button("Neuer Ordner", systemImage: "folder.badge.plus") {
                    promptForFolder(.create(moving: nil))
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .help("Neuer Ordner")
            }
            ToolbarItem {
                if library.isImporting {
                    ProgressView().controlSize(.small)
                } else {
                    Button("MP3 hinzufügen", systemImage: "plus") {
                        startImport(into: nil)
                    }
                    .keyboardShortcut("o", modifiers: .command)
                    .help("MP3-Dateien hinzufügen")
                }
            }
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.mp3], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                let folder = importFolder
                Task { await library.importFiles(urls, into: folder) }
            case .failure(let error):
                library.lastError = error.localizedDescription
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let mp3s = urls.filter { $0.pathExtension.lowercased() == "mp3" }
            guard !mp3s.isEmpty else { return false }
            Task { await library.importFiles(mp3s) }
            return true
        }
        .confirmationDialog(
            pendingDeletion.count == 1 ? "Titel löschen?" : "\(pendingDeletion.count) Titel löschen?",
            isPresented: Binding(get: { !pendingDeletion.isEmpty }, set: { if !$0 { pendingDeletion = [] } }),
            titleVisibility: .visible
        ) {
            Button("Löschen", role: .destructive) {
                library.delete(ids: pendingDeletion)
                pendingDeletion = []
            }
        } message: {
            Text("Der Titel wird aus der App entfernt. Die Originaldatei bleibt unverändert.")
        }
        .confirmationDialog(
            "Ordner „\(pendingFolderDeletion?.name ?? "")“ löschen?",
            isPresented: Binding(get: { pendingFolderDeletion != nil }, set: { if !$0 { pendingFolderDeletion = nil } }),
            titleVisibility: .visible
        ) {
            Button("Ordner löschen", role: .destructive) {
                if let folder = pendingFolderDeletion { library.deleteFolder(folder.id) }
                pendingFolderDeletion = nil
            }
        } message: {
            Text("Die Titel bleiben in der Bibliothek und erscheinen unter „Ohne Ordner“.")
        }
        .alert(
            folderPromptTitle,
            isPresented: Binding(get: { folderPrompt != nil }, set: { if !$0 { folderPrompt = nil } })
        ) {
            TextField("Name", text: $folderName)
            Button("Abbrechen", role: .cancel) { folderPrompt = nil }
            Button("OK", action: commitFolderPrompt)
        }
    }

    // MARK: - Rows

    private func trackRows(_ tracks: [Track], folderID: UUID?) -> some View {
        ForEach(tracks) { track in
            TrackRow(
                track: track,
                isCurrent: player.track?.id == track.id,
                isPlaying: player.isPlaying
            )
            .tag(track.id)
            .contextMenu { trackMenu(track) }
            // Lets the row be dropped into another folder.
            .itemProvider { NSItemProvider(object: track.id.uuidString as NSString) }
        }
        // Dragging a row within its folder switches to "Eigene Reihenfolge".
        .onMove { library.move(in: folderID, fromOffsets: $0, toOffset: $1) }
        // Dropped between the rows of another folder.
        .onInsert(of: [.plainText]) { index, providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                    guard let string = object as? String, let id = UUID(uuidString: string) else { return }
                    Task { @MainActor in library.moveTracks([id], toFolder: folderID, at: index) }
                }
            }
        }
        .onDelete { offsets in
            pendingDeletion = Set(offsets.map { tracks[$0].id })
        }
    }

    /// Placeholder in an empty folder; also a drop target.
    private func emptyRow(folderID: UUID?) -> some View {
        Text(folderID == nil ? "Keine Titel ohne Ordner" : "Leer – Titel hierher ziehen")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dropDestination(for: String.self) { items, _ in dropTracks(items, into: folderID) }
    }

    /// Track IDs dropped onto a folder header or an empty folder.
    private func dropTracks(_ items: [String], into folderID: UUID?) -> Bool {
        let ids = Set(items.compactMap(UUID.init(uuidString:)))
        guard !ids.isEmpty else { return false }
        library.moveTracks(ids, toFolder: folderID)
        return true
    }

    @ViewBuilder private func trackMenu(_ track: Track) -> some View {
        Menu("In Ordner verschieben", systemImage: "folder") {
            Button("Ohne Ordner") { library.moveTracks([track.id], toFolder: nil) }
                .disabled(track.folderID == nil)
            Divider()
            ForEach(library.sortedFolders) { folder in
                Button(folder.name) { library.moveTracks([track.id], toFolder: folder.id) }
                    .disabled(track.folderID == folder.id)
            }
            Divider()
            Button("Neuer Ordner …") { promptForFolder(.create(moving: track.id)) }
        }
        Button("Löschen", systemImage: "trash", role: .destructive) {
            pendingDeletion = [track.id]
        }
    }

    @ViewBuilder private func folderMenu(_ folder: TrackFolder) -> some View {
        Button("MP3 hinzufügen …", systemImage: "plus") { startImport(into: folder.id) }
        Button("Umbenennen …", systemImage: "pencil") {
            folderName = folder.name
            folderPrompt = .rename(folder.id)
        }
        Button("Ordner löschen", systemImage: "trash", role: .destructive) {
            pendingFolderDeletion = folder
        }
    }

    // MARK: - Actions

    private func expandedBinding(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { !collapsedFolders.contains(id) },
            set: { expanded in
                if expanded { collapsedFolders.remove(id) } else { collapsedFolders.insert(id) }
            }
        )
    }

    private func startImport(into folderID: UUID?) {
        importFolder = folderID
        showingImporter = true
    }

    private func promptForFolder(_ prompt: FolderPrompt) {
        folderName = ""
        folderPrompt = prompt
    }

    private var folderPromptTitle: String {
        if case .rename = folderPrompt { return "Ordner umbenennen" }
        return "Neuer Ordner"
    }

    private func commitFolderPrompt() {
        switch folderPrompt {
        case .create(let trackID):
            let folder = library.createFolder(named: folderName)
            if let trackID { library.moveTracks([trackID], toFolder: folder.id) }
        case .rename(let id):
            library.renameFolder(id, to: folderName)
        case nil:
            break
        }
        folderPrompt = nil
    }
}

private struct TrackRow: View {
    let track: Track
    let isCurrent: Bool
    let isPlaying: Bool

    var body: some View {
        HStack(spacing: 10) {
            ArtworkView(track: track, size: 40, cornerRadius: 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.body.weight(isCurrent ? .semibold : .regular))
                    .lineLimit(1)
                Text([track.artist, TimeFormat.string(track.duration)].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if isCurrent {
                Image(systemName: isPlaying ? "speaker.wave.2.fill" : "speaker.fill")
                    .foregroundStyle(.tint)
                    .symbolEffect(.variableColor.iterative, isActive: isPlaying)
            }
            if track.settings.loopEnabled {
                Image(systemName: "repeat").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct ArtworkView: View {
    @Environment(Library.self) private var library
    let track: Track
    let size: CGFloat
    var cornerRadius: CGFloat = 10

    var body: some View {
        Group {
            if let image = ArtworkCache.shared.image(for: track.id, url: library.artworkURL(for: track)) {
                Image(platformImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color.gray.opacity(0.15)
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.5))
                        .foregroundStyle(.gray.opacity(0.6))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
