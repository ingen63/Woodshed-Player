import SwiftUI

#if os(macOS)
import AppKit
typealias PlatformImage = NSImage

extension Image {
    init(platformImage: PlatformImage) { self.init(nsImage: platformImage) }
}
#else
import UIKit
typealias PlatformImage = UIImage

extension Image {
    init(platformImage: PlatformImage) { self.init(uiImage: platformImage) }
}
#endif

/// Small in-memory cache so list rows don't decode cover art on every redraw.
final class ArtworkCache: @unchecked Sendable {
    static let shared = ArtworkCache()
    private let cache = NSCache<NSUUID, PlatformImage>()

    func image(for id: UUID, url: URL?) -> PlatformImage? {
        if let cached = cache.object(forKey: id as NSUUID) { return cached }
        guard let url, let data = try? Data(contentsOf: url), let image = PlatformImage(data: data) else { return nil }
        cache.setObject(image, forKey: id as NSUUID)
        return image
    }

    func remove(_ id: UUID) {
        cache.removeObject(forKey: id as NSUUID)
    }
}

enum TimeFormat {
    /// 83.4 → "01:23", 3725 → "1:02:05"
    static func string(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "00:00" }
        let total = Int(max(0, seconds).rounded(.down))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }

    /// Like `string`, with tenths of a second: "01:23.4"
    static func preciseString(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "00:00.0" }
        let tenths = Int((max(0, seconds) * 10).rounded())
        let total = tenths / 10
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        let base = h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
        return base + ".\(tenths % 10)"
    }

    /// Parses "83", "1:23", "01:23.5" or "1:02:05". Returns nil for invalid input.
    static func parse(_ text: String) -> TimeInterval? {
        let cleaned = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty else { return nil }
        let parts = cleaned.split(separator: ":", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        var result: TimeInterval = 0
        for (index, part) in parts.enumerated() {
            guard let value = Double(part), value >= 0 else { return nil }
            // Only the leading component may exceed 59.
            if index > 0 && value >= 60 { return nil }
            result = result * 60 + value
        }
        return result
    }
}
