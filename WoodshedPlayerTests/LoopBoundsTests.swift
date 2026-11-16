import Foundation
import Testing
@testable import WoodshedPlayer

/// GEN-2/AK2: Loop-Grenzen – das Ende liegt immer mindestens 1 s nach dem Anfang.
/// GEN-2/AK4: Die Audiodatei (10 s Sinuston) wird im Test erzeugt.
@MainActor
struct LoopBoundsTests {
    let player = AudioPlayer()
    let url: URL

    init() throws {
        url = try TestAudio.sineWave(seconds: 10)
        let track = Track(id: UUID(), fileName: url.lastPathComponent, originalFileName: "sinus.wav",
                          title: "Sinus 440 Hz", duration: 10, hasArtwork: false, dateAdded: .now,
                          customOrder: 0, settings: PlaybackSettings())
        player.load(track, url: url)
    }

    @Test("GEN-2/AK4: Erzeugte Testdatei ist ladbar und 10 s lang")
    func generatedAudioLoads() {
        #expect(player.errorMessage == nil)
        #expect(abs(player.duration - 10) < 0.001)
    }

    @Test("GEN-2/AK2: Gültiger Loop bleibt unverändert")
    func validLoop() {
        player.setLoopStart(1)
        player.setLoopEnd(5)
        #expect(player.settings.loopStart == 1)
        #expect(player.settings.loopEnd == 5)
        #expect(player.activeLoop == 1...5)
    }

    @Test("GEN-2/AK2: Ende zu nah am Anfang wird auf Anfang + 1 s gesetzt")
    func endTooClose() {
        player.setLoopStart(2)
        player.setLoopEnd(2.5)
        #expect(player.settings.loopStart == 2)
        #expect(player.settings.loopEnd == 3)
    }

    @Test("GEN-2/AK2: Ende vor dem Anfang wird auf Anfang + 1 s gesetzt")
    func endBeforeStart() {
        player.setLoopStart(4)
        player.setLoopEnd(1)
        #expect(player.settings.loopStart == 4)
        #expect(player.settings.loopEnd == 5)
    }

    @Test("GEN-2/AK2: Anfang hinter dem Ende – Loop läuft bis zum Dateiende")
    func startBehindEnd() {
        player.setLoopStart(1)
        player.setLoopEnd(3)
        player.setLoopStart(6)
        #expect(player.settings.loopStart == 6)
        #expect(player.settings.loopEnd == 10)
    }

    @Test("GEN-2/AK2: Anfang kurz vor dem Dateiende wird auf Dateiende − 1 s begrenzt")
    func startNearFileEnd() {
        player.setLoopStart(9.8)
        #expect(player.settings.loopStart == 9)
        #expect(player.settings.loopEnd == 10)
    }

    @Test("GEN-2/AK2: Grenzen ausserhalb der Datei werden auf die Datei begrenzt")
    func clampedToFile() {
        player.setLoopEnd(50)
        #expect(player.settings.loopStart == 0)
        #expect(player.settings.loopEnd == 10)
    }

    @Test("GEN-2/AK2: Loop ohne Grenzen einschalten umfasst die ganze Datei")
    func enableWithoutBounds() {
        player.updateSettings { $0.loopEnabled = true }
        #expect(player.activeLoop == 0...10)
    }

    @Test("GEN-2/AK2: Ausgeschalteter Loop ist nicht aktiv")
    func disabledLoop() {
        player.setLoopStart(1)
        player.setLoopEnd(5)
        player.updateSettings { $0.loopEnabled = false }
        #expect(player.activeLoop == nil)
        #expect(player.settings.loopStart == 1)
        #expect(player.settings.loopEnd == 5)
    }

    @Test("GEN-2/AK2: Jede Kombination hält mindestens 1 s Abstand")
    func minimumLengthAlways() {
        for start in stride(from: 0.0, through: 10, by: 0.5) {
            for end in stride(from: 0.0, through: 10, by: 0.5) {
                player.updateSettings { $0.loopEnabled = false; $0.loopStart = 0; $0.loopEnd = 0 }
                player.setLoopStart(start)
                player.setLoopEnd(end)
                let s = player.settings
                #expect(s.loopEnd - s.loopStart >= AudioPlayer.minimumLoopLength,
                        "Start \(start), Ende \(end) → \(s.loopStart)…\(s.loopEnd)")
                #expect(s.loopStart >= 0 && s.loopEnd <= 10)
            }
        }
    }
}
