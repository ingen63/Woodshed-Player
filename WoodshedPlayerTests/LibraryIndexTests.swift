import Foundation
import Testing
@testable import WoodshedPlayer

/// GEN-2/AK3: library.json im alten Format `[Track]` und im neuen Format `{folders, tracks}`.
/// Die Bibliothek liegt in einem temporären Ordner; die echte Bibliothek wird nicht berührt.
@MainActor
struct LibraryIndexTests {
    let directory: URL
    let trackID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    let folderID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

    init() throws {
        directory = try TestAudio.temporaryDirectory()
        let tracks = directory.appendingPathComponent("Tracks", isDirectory: true)
        try FileManager.default.createDirectory(at: tracks, withIntermediateDirectories: true)
        // Library prüft nur, ob die Datei existiert; der Inhalt spielt hier keine Rolle.
        try Data().write(to: tracks.appendingPathComponent("\(trackID.uuidString).mp3"))
    }

    private func trackJSON(folder: Bool) -> String {
        """
        {
          "id": "\(trackID.uuidString)",
          "fileName": "\(trackID.uuidString).mp3",
          "originalFileName": "Tonleiter C-Dur.mp3",
          "title": "Tonleiter C-Dur",
          "artist": "Übungsband",
          "duration": 125.5,
          "hasArtwork": false,
          "dateAdded": 700000000,
          "customOrder": 3,
          "settings": { "speedEnabled": true, "speed": 0.75, "loopEnabled": true, "loopStart": 12, "loopEnd": 20.5 }\(folder ? ",\n  \"folderID\": \"\(folderID.uuidString)\"" : "")
        }
        """
    }

    private func write(_ json: String) throws {
        try Data(json.utf8).write(to: directory.appendingPathComponent("library.json"))
    }

    private func expectTrack(_ track: Track?) {
        #expect(track?.title == "Tonleiter C-Dur")
        #expect(track?.artist == "Übungsband")
        #expect(track?.album == nil)
        #expect(track?.duration == 125.5)
        #expect(track?.customOrder == 3)
        #expect(track?.dateAdded == Date(timeIntervalSinceReferenceDate: 700_000_000))
        #expect(track?.settings == PlaybackSettings(speedEnabled: true, speed: 0.75,
                                                    loopEnabled: true, loopStart: 12, loopEnd: 20.5))
    }

    @Test("GEN-2/AK3: Altes Format [Track] wird gelesen")
    func oldFormat() throws {
        try write("[\(trackJSON(folder: false))]")
        let library = Library(directory: directory)
        #expect(library.folders.isEmpty)
        #expect(library.tracks.count == 1)
        expectTrack(library.track(withID: trackID))
        #expect(library.track(withID: trackID)?.folderID == nil)
    }

    @Test("GEN-2/AK3: Neues Format {folders, tracks} wird gelesen")
    func newFormat() throws {
        try write("""
        { "folders": [ { "id": "\(folderID.uuidString)", "name": "Etüden" } ],
          "tracks": [ \(trackJSON(folder: true)) ] }
        """)
        let library = Library(directory: directory)
        #expect(library.folders == [TrackFolder(id: folderID, name: "Etüden")])
        expectTrack(library.track(withID: trackID))
        #expect(library.track(withID: trackID)?.folderID == folderID)
    }

    @Test("GEN-2/AK3: Einträge ohne Datei werden beim Lesen verworfen")
    func missingFileDropped() throws {
        let other = UUID()
        let missing = trackJSON(folder: false)
            .replacingOccurrences(of: trackID.uuidString, with: other.uuidString)
        try write("[\(trackJSON(folder: false)), \(missing)]")
        let library = Library(directory: directory)
        #expect(library.tracks.map(\.id) == [trackID])
    }

    @Test("GEN-2/AK3: Gespeichert wird im neuen Format, erneutes Lesen ergibt denselben Stand")
    func saveRoundTrip() throws {
        try write("[\(trackJSON(folder: false))]")
        let library = Library(directory: directory)
        let folder = library.createFolder(named: "  Etüden  ")
        library.moveTracks([trackID], toFolder: folder.id)

        let saved = try JSONSerialization.jsonObject(
            with: Data(contentsOf: directory.appendingPathComponent("library.json"))) as? [String: Any]
        #expect(saved?["folders"] is [Any])
        #expect(saved?["tracks"] is [Any])

        let reloaded = Library(directory: directory)
        #expect(reloaded.folders == [TrackFolder(id: folder.id, name: "Etüden")])
        #expect(reloaded.tracks == library.tracks)
    }

    @Test("GEN-2/AK3: Fehlende oder kaputte library.json ergibt eine leere Bibliothek")
    func emptyOrBroken() throws {
        #expect(Library(directory: directory).tracks.isEmpty)
        try write("{ kaputt")
        let library = Library(directory: directory)
        #expect(library.tracks.isEmpty)
        #expect(library.folders.isEmpty)
    }
}
