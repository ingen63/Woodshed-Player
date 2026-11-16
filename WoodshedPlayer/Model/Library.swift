import AVFoundation
import Foundation
import Observation

/// Keeps the imported MP3 files (copied into the app's own folder) and their metadata.
@Observable
@MainActor
final class Library {
    private(set) var tracks: [Track] = []
    private(set) var folders: [TrackFolder] = []
    private(set) var isImporting = false
    var lastError: String?

    var sortOrder: TrackSortOrder {
        didSet { UserDefaults.standard.set(sortOrder.rawValue, forKey: Self.sortOrderKey) }
    }

    private static let sortOrderKey = "trackSortOrder"
    private let folder: URL
    private let indexURL: URL
    @ObservationIgnored private var pendingSave: Task<Void, Never>?

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        folder = support.appendingPathComponent("WoodshedPlayer/Tracks", isDirectory: true)
        indexURL = support.appendingPathComponent("WoodshedPlayer/library.json")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let stored = UserDefaults.standard.string(forKey: Self.sortOrderKey)
        sortOrder = stored.flatMap(TrackSortOrder.init(rawValue:)) ?? .dateAdded

        if let data = try? Data(contentsOf: indexURL) {
            let decoder = JSONDecoder()
            // Older versions stored only the track array.
            let index = (try? decoder.decode(LibraryIndex.self, from: data))
                ?? (try? decoder.decode([Track].self, from: data)).map { LibraryIndex(folders: [], tracks: $0) }
            if let index {
                folders = index.folders
                // Drop entries whose file has vanished.
                tracks = index.tracks.filter { FileManager.default.fileExists(atPath: fileURL(for: $0).path) }
            }
        }
    }

    // MARK: - Queries

    var sortedTracks: [Track] {
        switch sortOrder {
        case .alphabetical:
            tracks.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .dateAdded:
            tracks.sorted { $0.dateAdded > $1.dateAdded }
        case .custom:
            tracks.sorted { $0.customOrder < $1.customOrder }
        }
    }

    var sortedFolders: [TrackFolder] {
        folders.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Tracks of one folder (nil = tracks without folder) in the current sort order.
    func sortedTracks(in folderID: UUID?) -> [Track] {
        sortedTracks.filter { $0.folderID == folderID }
    }

    func track(withID id: UUID) -> Track? {
        tracks.first { $0.id == id }
    }

    func fileURL(for track: Track) -> URL {
        folder.appendingPathComponent(track.fileName)
    }

    func artworkURL(for track: Track) -> URL? {
        track.hasArtwork ? folder.appendingPathComponent("\(track.id.uuidString).artwork") : nil
    }

    // MARK: - Import / delete

    func importFiles(_ urls: [URL], into folderID: UUID? = nil) async {
        isImporting = true
        defer { isImporting = false }

        var failed: [String] = []
        for url in urls {
            do {
                var track = try await importFile(url)
                track.folderID = folderID
                tracks.append(track)
            } catch {
                failed.append(url.lastPathComponent)
            }
        }
        if !failed.isEmpty {
            lastError = "Folgende Dateien konnten nicht importiert werden:\n" + failed.joined(separator: "\n")
        }
        save()
    }

    private func importFile(_ source: URL) async throws -> Track {
        let accessing = source.startAccessingSecurityScopedResource()
        defer { if accessing { source.stopAccessingSecurityScopedResource() } }

        let id = UUID()
        let ext = source.pathExtension.isEmpty ? "mp3" : source.pathExtension.lowercased()
        let fileName = "\(id.uuidString).\(ext)"
        let destination = folder.appendingPathComponent(fileName)
        try FileManager.default.copyItem(at: source, to: destination)

        do {
            // AVAudioFile gives the exact length the player engine will use.
            let audioFile = try AVAudioFile(forReading: destination)
            let duration = Double(audioFile.length) / audioFile.processingFormat.sampleRate

            var title: String?
            var artist: String?
            var album: String?
            var artwork: Data?
            let asset = AVURLAsset(url: destination)
            if let metadata = try? await asset.load(.commonMetadata) {
                for item in metadata {
                    switch item.commonKey {
                    case .commonKeyTitle: title = try? await item.load(.stringValue)
                    case .commonKeyArtist: artist = try? await item.load(.stringValue)
                    case .commonKeyAlbumName: album = try? await item.load(.stringValue)
                    case .commonKeyArtwork: artwork = try? await item.load(.dataValue)
                    default: break
                    }
                }
            }

            var hasArtwork = false
            if let artwork {
                let artURL = folder.appendingPathComponent("\(id.uuidString).artwork")
                hasArtwork = (try? artwork.write(to: artURL)) != nil
            }

            let baseName = source.deletingPathExtension().lastPathComponent
            return Track(
                id: id,
                fileName: fileName,
                originalFileName: source.lastPathComponent,
                title: title.flatMap { $0.isEmpty ? nil : $0 } ?? baseName,
                artist: artist,
                album: album,
                duration: duration,
                hasArtwork: hasArtwork,
                dateAdded: .now,
                customOrder: (tracks.map(\.customOrder).max() ?? -1) + 1,
                settings: PlaybackSettings()
            )
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    func delete(ids: Set<UUID>) {
        for track in tracks where ids.contains(track.id) {
            try? FileManager.default.removeItem(at: fileURL(for: track))
            if let art = artworkURL(for: track) {
                try? FileManager.default.removeItem(at: art)
            }
            ArtworkCache.shared.remove(track.id)
        }
        tracks.removeAll { ids.contains($0.id) }
        save()
    }

    // MARK: - Ordering

    /// Moves rows within one folder's `sortedTracks(in:)`. Switches to custom order, starting from the order currently shown.
    func move(in folderID: UUID?, fromOffsets source: IndexSet, toOffset destination: Int) {
        var ordered = sortedTracks
        let slots = ordered.indices.filter { ordered[$0].folderID == folderID }
        var section = slots.map { ordered[$0] }
        section.move(fromOffsets: source, toOffset: destination)
        for (slot, track) in zip(slots, section) {
            ordered[slot] = track
        }
        let positions = Dictionary(uniqueKeysWithValues: ordered.enumerated().map { ($1.id, $0) })
        for index in tracks.indices {
            tracks[index].customOrder = positions[tracks[index].id] ?? index
        }
        sortOrder = .custom
        save()
    }

    // MARK: - Folders

    @discardableResult
    func createFolder(named name: String) -> TrackFolder {
        let folder = TrackFolder(name: Self.cleanFolderName(name))
        folders.append(folder)
        save()
        return folder
    }

    func renameFolder(_ id: UUID, to name: String) {
        guard let index = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[index].name = Self.cleanFolderName(name)
        save()
    }

    /// Removes the folder; its tracks stay in the library without a folder.
    func deleteFolder(_ id: UUID) {
        folders.removeAll { $0.id == id }
        for index in tracks.indices where tracks[index].folderID == id {
            tracks[index].folderID = nil
        }
        save()
    }

    /// Puts tracks into a folder. With `index`, they are placed at that row of the folder's list
    /// (used for "Eigene Reihenfolge"); otherwise their position is kept.
    func moveTracks(_ ids: Set<UUID>, toFolder folderID: UUID?, at index: Int? = nil) {
        guard let index else {
            for i in tracks.indices where ids.contains(tracks[i].id) {
                tracks[i].folderID = folderID
            }
            save()
            return
        }
        var ordered = sortedTracks
        var moving = ordered.filter { ids.contains($0.id) }
        ordered.removeAll { ids.contains($0.id) }
        for i in moving.indices { moving[i].folderID = folderID }

        let slots = ordered.indices.filter { ordered[$0].folderID == folderID }
        let insertAt = index < slots.count ? slots[index] : (slots.last.map { $0 + 1 } ?? ordered.endIndex)
        ordered.insert(contentsOf: moving, at: insertAt)

        let positions = Dictionary(uniqueKeysWithValues: ordered.enumerated().map { ($1.id, ($0, $1.folderID)) })
        for i in tracks.indices {
            guard let (order, folder) = positions[tracks[i].id] else { continue }
            tracks[i].customOrder = order
            tracks[i].folderID = folder
        }
        save()
    }

    private static func cleanFolderName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Neuer Ordner" : trimmed
    }

    // MARK: - Settings

    func updateSettings(_ settings: PlaybackSettings, for id: UUID) {
        guard let index = tracks.firstIndex(where: { $0.id == id }),
              tracks[index].settings != settings else { return }
        tracks[index].settings = settings
        scheduleSave()
    }

    // MARK: - Persistence

    /// Coalesces frequent writes (e.g. while dragging the speed slider).
    private func scheduleSave() {
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    func save() {
        pendingSave?.cancel()
        pendingSave = nil
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(LibraryIndex(folders: folders, tracks: tracks)).write(to: indexURL, options: .atomic)
        } catch {
            lastError = "Bibliothek konnte nicht gespeichert werden: \(error.localizedDescription)"
        }
    }
}

/// Contents of library.json.
private struct LibraryIndex: Codable {
    var folders: [TrackFolder]
    var tracks: [Track]
}
