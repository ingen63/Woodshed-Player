import Foundation
import Testing
@testable import WoodshedPlayer

/// GEN-2/AK2: Zeitformat mm:ss – Formatieren, Parsen, ungültige Eingaben.
struct TimeFormatTests {
    @Test("GEN-2/AK2: Formatieren als mm:ss bzw. h:mm:ss", arguments: [
        (0.0, "00:00"),
        (59.9, "00:59"),
        (83.4, "01:23"),
        (600, "10:00"),
        (3599, "59:59"),
        (3725, "1:02:05"),
    ])
    func format(seconds: Double, expected: String) {
        #expect(TimeFormat.string(seconds) == expected)
    }

    @Test("GEN-2/AK2: Negative und nicht endliche Werte ergeben 00:00")
    func formatInvalid() {
        #expect(TimeFormat.string(-5) == "00:00")
        #expect(TimeFormat.string(.nan) == "00:00")
        #expect(TimeFormat.string(.infinity) == "00:00")
        #expect(TimeFormat.preciseString(.nan) == "00:00.0")
    }

    @Test("GEN-2/AK2: Formatieren mit Zehntelsekunden")
    func preciseFormat() {
        #expect(TimeFormat.preciseString(83.44) == "01:23.4")
        #expect(TimeFormat.preciseString(59.96) == "01:00.0")
        #expect(TimeFormat.preciseString(3725.2) == "1:02:05.2")
    }

    @Test("GEN-2/AK2: Parsen gültiger Eingaben", arguments: [
        ("83", 83.0),
        ("1:23", 83.0),
        ("01:23", 83.0),
        ("01:23.5", 83.5),
        ("01:23,5", 83.5),
        (" 02:11 ", 131.0),
        ("1:02:05", 3725.0),
        ("120:00", 7200.0),
    ])
    func parse(text: String, expected: Double) {
        #expect(TimeFormat.parse(text) == expected)
    }

    @Test("GEN-2/AK2: Ungültige Eingaben ergeben nil", arguments: [
        "", "   ", "abc", "1:60", "1:2:60", "1:2:3:4", "-1", "1:-5", "1::2", "1:2x",
    ])
    func parseInvalid(text: String) {
        #expect(TimeFormat.parse(text) == nil)
    }

    @Test("GEN-2/AK2: Formatieren und Parsen passen zusammen")
    func roundTrip() {
        for seconds in [0.0, 1, 59, 60, 83, 599, 3599, 3600, 3725] {
            #expect(TimeFormat.parse(TimeFormat.string(seconds)) == seconds)
        }
    }
}
