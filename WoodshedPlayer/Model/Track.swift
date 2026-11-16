import Foundation

/// Per-track playback settings. Remembered individually for every file.
struct PlaybackSettings: Codable, Hashable {
    var speedEnabled = false
    /// Playback rate, 0.1 … 2.0. Pitch is preserved.
    var speed: Double = 1.0
    var loopEnabled = false
    /// Loop bounds in seconds. `loopEnd == 0` means "not set yet".
    var loopStart: TimeInterval = 0
    var loopEnd: TimeInterval = 0

    static let speedRange: ClosedRange<Double> = 0.1...2.0

    var effectiveRate: Double { speedEnabled ? speed : 1.0 }
}

struct Track: Identifiable, Codable, Hashable {
    var id: UUID
    /// File name inside the app's library folder.
    var fileName: String
    /// Original file name the user imported.
    var originalFileName: String
    var title: String
    var artist: String?
    var album: String?
    var duration: TimeInterval
    var hasArtwork: Bool
    var dateAdded: Date
    var customOrder: Int
    var settings: PlaybackSettings
    /// Folder the track is grouped in; nil = "Ohne Ordner".
    var folderID: UUID?
}

/// A user-created group in the library.
struct TrackFolder: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
}

enum TrackSortOrder: String, CaseIterable, Identifiable, Codable {
    case alphabetical
    case dateAdded
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .alphabetical: "Alphabetisch"
        case .dateAdded: "Hinzugefügt"
        case .custom: "Eigene Reihenfolge"
        }
    }

    var systemImage: String {
        switch self {
        case .alphabetical: "textformat.abc"
        case .dateAdded: "calendar"
        case .custom: "hand.draw"
        }
    }
}
