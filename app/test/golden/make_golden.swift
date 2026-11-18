// Erzeugt die Golden-Dateien für #16 mit dem Datenmodell der Swift-App (WoodshedPlayer/Model/Track.swift)
// und denselben Encoder-Einstellungen wie Library.save(). Aufruf aus dem Projektordner:
//   swiftc WoodshedPlayer/Model/Track.swift app/test/golden/make_golden.swift -o /tmp/make_golden && /tmp/make_golden app/test/golden
// Alle Namen und Titel sind erfunden.
import Foundation

struct LibraryIndex: Codable {
    var folders: [TrackFolder]
    var tracks: [Track]
}

@main
struct MakeGolden {
    static func main() throws {
        let dir = URL(fileURLWithPath: CommandLine.arguments[1])
        let f1 = TrackFolder(id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!, name: "Etüden")
        let f2 = TrackFolder(id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!, name: "Swing 2")
        let t1 = Track(
            id: UUID(uuidString: "0F0E0D0C-0B0A-0908-0706-050403020100")!,
            fileName: "0F0E0D0C-0B0A-0908-0706-050403020100.mp3",
            originalFileName: "Übung in C.mp3", title: "Übung in C", artist: "Testband", album: "Testalbum",
            duration: 183.456, hasArtwork: true,
            dateAdded: Date(timeIntervalSinceReferenceDate: 784_123_456.789), customOrder: 2,
            settings: PlaybackSettings(speedEnabled: true, speed: 0.75, loopEnabled: true, loopStart: 12.5, loopEnd: 47),
            folderID: f1.id)
        let t2 = Track(
            id: UUID(uuidString: "99999999-8888-7777-6666-555555555555")!,
            fileName: "99999999-8888-7777-6666-555555555555.flac",
            originalFileName: "sinus.flac", title: "sinus", artist: nil, album: nil,
            duration: 1, hasArtwork: false,
            dateAdded: Date(timeIntervalSinceReferenceDate: 700_000_000), customOrder: 0,
            settings: PlaybackSettings(), folderID: nil)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(LibraryIndex(folders: [f1, f2], tracks: [t1, t2])).write(to: dir.appendingPathComponent("library_swift.json"))
        try enc.encode([t1, t2]).write(to: dir.appendingPathComponent("library_swift_legacy.json"))
        // Rückweg: von Dart geschriebene Datei mit dem Swift-Decoder lesen, falls angegeben.
        if CommandLine.arguments.count > 2 {
            let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))
            let index = try JSONDecoder().decode(LibraryIndex.self, from: data)
            print("Swift liest Dart-Datei: \(index.folders.count) Ordner, \(index.tracks.count) Titel")
        }
    }
}
