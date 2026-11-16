import SwiftUI

/// Single-key player shortcuts: Space = play/pause, S / E = loop start / end, ← / → = speed.
/// They are ignored while a text field is being edited.
enum PlayerKey {
    case playPause, loopStart, loopEnd, faster, slower

    init?(characters: String) {
        switch characters.lowercased() {
        case " ": self = .playPause
        case "s": self = .loopStart
        case "e": self = .loopEnd
        default: return nil
        }
    }

    /// Only the speed keys repeat while held down.
    var repeats: Bool { self == .faster || self == .slower }
}

extension AudioPlayer {
    /// Returns false if no track is loaded, so the key can be handled elsewhere.
    func perform(_ key: PlayerKey) -> Bool {
        guard track != nil else { return false }
        switch key {
        case .playPause: togglePlayPauseReturningToLoop()
        case .loopStart: setLoopStart(currentTime)
        case .loopEnd: setLoopEnd(currentTime)
        case .faster: adjustSpeed(bySteps: 1)
        case .slower: adjustSpeed(bySteps: -1)
        }
        return true
    }
}

extension View {
    func playerKeyboardShortcuts(_ player: AudioPlayer) -> some View {
        modifier(PlayerKeyboardShortcuts(player: player))
    }
}

#if os(macOS)
import AppKit

/// A local key monitor sees the keys before lists and buttons do, so they work regardless of focus.
private struct PlayerKeyboardShortcuts: ViewModifier {
    let player: AudioPlayer
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard monitor == nil else { return }
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [player] event in
                    MainActor.assumeIsolated { Self.handle(event, player: player) } ? nil : event
                }
            }
            .onDisappear {
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
            }
    }

    @MainActor
    private static func handle(_ event: NSEvent, player: AudioPlayer) -> Bool {
        guard event.modifierFlags.isDisjoint(with: [.command, .control, .option]),
              let window = event.window, window.isKeyWindow, !window.isSheet, window.attachedSheet == nil,
              !(window.firstResponder is NSText), // a text field is being edited
              let key = Self.key(for: event) else { return false }
        if event.isARepeat && !key.repeats { return player.track != nil }
        return player.perform(key)
    }

    private static func key(for event: NSEvent) -> PlayerKey? {
        switch event.keyCode {
        case 124: .faster // →
        case 123: .slower // ←
        default: event.characters.flatMap(PlayerKey.init(characters:))
        }
    }
}
#else
/// Hardware keyboard on iPad / iPhone.
private struct PlayerKeyboardShortcuts: ViewModifier {
    let player: AudioPlayer

    func body(content: Content) -> some View {
        content.onKeyPress(phases: [.down, .repeat]) { press in
            guard press.modifiers.isDisjoint(with: [.command, .control, .option]),
                  let key = Self.key(for: press) else { return .ignored }
            if press.phase == .repeat && !key.repeats { return player.track != nil ? .handled : .ignored }
            return player.perform(key) ? .handled : .ignored
        }
    }

    private static func key(for press: KeyPress) -> PlayerKey? {
        switch press.key {
        case .rightArrow: .faster
        case .leftArrow: .slower
        default: PlayerKey(characters: press.characters)
        }
    }
}
#endif
