import SwiftUI

struct PlayerView: View {
    @Environment(AudioPlayer.self) private var player

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                NowPlayingCard()
                SpeedCard()
                LoopCard()
            }
            .padding()
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background {
            LinearGradient(
                colors: [Color.accentColor.opacity(0.30), Color.accentColor.opacity(0.06)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
        .navigationTitle(player.track?.originalFileName ?? "")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

/// Binding into the loaded track's settings that goes through `AudioPlayer.updateSettings`.
@MainActor
private func settingBinding<T>(_ player: AudioPlayer, _ keyPath: WritableKeyPath<PlaybackSettings, T>) -> Binding<T> {
    Binding(
        get: { player.settings[keyPath: keyPath] },
        set: { value in player.updateSettings { $0[keyPath: keyPath] = value } }
    )
}

private struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) { content }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

// MARK: - Now playing (layout modelled on the macOS Quick Look player)

private struct NowPlayingCard: View {
    @Environment(AudioPlayer.self) private var player

    var body: some View {
        if let track = player.track {
            Card {
                HStack {
                    Spacer()
                    VolumeControl()
                }
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 24) {
                        ArtworkView(track: track, size: 190, cornerRadius: 4)
                        TrackInfo(track: track, duration: player.duration)
                            .frame(minWidth: 240, alignment: .leading)
                        Spacer(minLength: 0)
                    }
                    VStack(spacing: 16) {
                        ArtworkView(track: track, size: 220, cornerRadius: 4)
                        TrackInfo(track: track, duration: player.duration)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                TransportBar()
            }
        }
    }
}

private struct TrackInfo: View {
    let track: Track
    let duration: TimeInterval

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(track.title)
                .font(.title2.bold())
                .lineLimit(2)
                .padding(.bottom, 4)
            InfoLine(label: "Künstler:in", value: track.artist)
            InfoLine(label: "Album", value: track.album)
            InfoLine(label: "Dauer", value: TimeFormat.string(duration))
        }
    }
}

private struct InfoLine: View {
    let label: String
    let value: String?

    var body: some View {
        if let value, !value.isEmpty {
            HStack(spacing: 4) {
                Text("\(label):").foregroundStyle(.secondary)
                Text(value).fontWeight(.semibold)
            }
            .font(.callout)
            .lineLimit(1)
        }
    }
}

private struct VolumeControl: View {
    @Environment(AudioPlayer.self) private var player

    var body: some View {
        HStack(spacing: 8) {
            Slider(
                value: Binding(get: { Double(player.volume) }, set: { player.setVolume(Float($0)) }),
                in: 0...1
            )
            .frame(width: 110)
            .tint(.white)
            Image(systemName: volumeSymbol)
                .frame(width: 22)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.black.opacity(0.55)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Lautstärke")
    }

    private var volumeSymbol: String {
        switch player.volume {
        case 0: "speaker.slash.fill"
        case ..<0.34: "speaker.wave.1.fill"
        case ..<0.67: "speaker.wave.2.fill"
        default: "speaker.wave.3.fill"
        }
    }
}

private struct TransportBar: View {
    @Environment(AudioPlayer.self) private var player

    var body: some View {
        // One row like the Quick Look player; two rows on narrow screens.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                buttons
                timeline(minWidth: 160)
            }
            VStack(spacing: 8) {
                timeline(minWidth: 80)
                HStack(spacing: 40) { buttons }
            }
        }
        .font(.title3)
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.black.opacity(0.6)))
    }

    @ViewBuilder private var buttons: some View {
        Button { player.skip(by: -15) } label: {
            Image(systemName: "gobackward.15")
        }
        .accessibilityLabel("15 Sekunden zurück")

        Button { player.togglePlayPause() } label: {
            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                .font(.title2)
                .frame(width: 26)
        }
        .accessibilityLabel(player.isPlaying ? "Pause" : "Wiedergabe")

        Button { player.skip(by: 15) } label: {
            Image(systemName: "goforward.15")
        }
        .accessibilityLabel("15 Sekunden vor")
    }

    private func timeline(minWidth: CGFloat) -> some View {
        HStack(spacing: 12) {
            Text(TimeFormat.string(player.currentTime))
            ProgressScrubber(
                current: player.currentTime,
                duration: player.duration,
                onSeek: { player.seek(to: $0) }
            )
            .frame(minWidth: minWidth)
            Text(TimeFormat.string(player.duration))
        }
        .monospacedDigit()
        .font(.callout)
    }
}

/// Thin progress bar with a white knob. While the loop is on, its range is highlighted
/// and the start / end markers can be dragged.
private struct ProgressScrubber: View {
    @Environment(AudioPlayer.self) private var player
    let current: TimeInterval
    let duration: TimeInterval
    let onSeek: (TimeInterval) -> Void

    @State private var dragTime: TimeInterval?

    private var loop: (start: TimeInterval, end: TimeInterval)? {
        player.settings.loopEnabled ? (player.settings.loopStart, player.settings.loopEnd) : nil
    }

    var body: some View {
        let dragLoopStart = player.draggedLoopStart
        let dragLoopEnd = player.draggedLoopEnd

        GeometryReader { geo in
            let width = geo.size.width
            let shown = dragTime ?? current
            let x = duration > 0 ? width * shown / duration : 0

            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.25)).frame(height: 5)
                Capsule().fill(.white.opacity(0.7)).frame(width: max(0, x), height: 5)
                if let loop, duration > 0 {
                    let start = dragLoopStart ?? loop.start
                    let end = dragLoopEnd ?? loop.end
                    if end > start {
                        Capsule()
                            .fill(Color.orange.opacity(0.75))
                            .frame(width: max(3, width * (end - start) / duration), height: 9)
                            .offset(x: width * start / duration)
                    }
                }
                Capsule()
                    .fill(.white)
                    .frame(width: 22, height: 14)
                    .shadow(color: .black.opacity(0.3), radius: 1.5)
                    .offset(x: min(max(0, x - 11), width - 22))
                if let loop, duration > 0 {
                    loopMarker(at: dragLoopStart ?? loop.start, width: width, help: "Loop-Anfang (Taste S) – zum Verschieben ziehen") { time in
                        player.draggedLoopStart = max(0, min(time, loop.end - AudioPlayer.minimumLoopLength))
                    } onEnded: {
                        if let start = player.draggedLoopStart { player.setLoopStart(start) }
                        player.draggedLoopStart = nil
                    }
                    loopMarker(at: dragLoopEnd ?? loop.end, width: width, help: "Loop-Ende (Taste E) – zum Verschieben ziehen") { time in
                        player.draggedLoopEnd = min(duration, max(time, loop.start + AudioPlayer.minimumLoopLength))
                    } onEnded: {
                        if let end = player.draggedLoopEnd { player.setLoopEnd(end) }
                        player.draggedLoopEnd = nil
                    }
                }
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .coordinateSpace(name: Self.space)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard width > 0 else { return }
                        dragTime = min(max(0, value.location.x / width), 1) * duration
                    }
                    .onEnded { _ in
                        if let dragTime { onSeek(dragTime) }
                        dragTime = nil
                    }
            )
        }
        .frame(height: 24)
        .accessibilityElement()
        .accessibilityLabel("Position")
        .accessibilityValue(TimeFormat.string(current))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onSeek(current + 5)
            case .decrement: onSeek(current - 5)
            @unknown default: break
            }
        }
    }

    private static let space = "scrubber"

    /// Orange flag with a wider invisible grab area; its gesture wins over the seek gesture.
    private func loopMarker(
        at time: TimeInterval,
        width: CGFloat,
        help: String,
        onChanged: @escaping (TimeInterval) -> Void,
        onEnded: @escaping () -> Void
    ) -> some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(Color.orange)
            .overlay(RoundedRectangle(cornerRadius: 1.5).stroke(.white.opacity(0.85), lineWidth: 1))
            .frame(width: 4, height: 22)
            .frame(width: 18, height: 24)
            .contentShape(Rectangle())
            .help(help)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
                    .onChanged { value in
                        guard width > 0 else { return }
                        onChanged(min(max(0, value.location.x / width), 1) * duration)
                    }
                    .onEnded { _ in onEnded() }
            )
            .offset(x: width * time / duration - 9)
    }
}

// MARK: - Speed

private struct SpeedCard: View {
    @Environment(AudioPlayer.self) private var player
    private let presets: [Double] = [0.5, 0.7, 0.8, 0.9, 1.0, 1.1]

    var body: some View {
        Card {
            Toggle(isOn: settingBinding(player, \.speedEnabled)) {
                Label("Geschwindigkeit", systemImage: "speedometer").font(.headline)
            }
            .toggleStyle(.switch)

            Group {
                HStack(spacing: 10) {
                    Text("0,1×").font(.caption).foregroundStyle(.secondary)
                    // Rounded to 0.05 steps here instead of `step:`, which draws tick marks on macOS.
                    Slider(
                        value: Binding(
                            get: { player.settings.speed },
                            set: { value in player.updateSettings { $0.speed = (value * 20).rounded() / 20 } }
                        ),
                        in: PlaybackSettings.speedRange
                    )
                    Text("2×").font(.caption).foregroundStyle(.secondary)
                    Text(Self.format(player.settings.speed))
                        .font(.title3.monospacedDigit().weight(.semibold))
                        .frame(width: 70, alignment: .trailing)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(presets, id: \.self) { preset in
                            Button(Self.format(preset)) {
                                player.updateSettings { $0.speed = preset }
                            }
                            .buttonStyle(.bordered)
                            .tint(abs(player.settings.speed - preset) < 0.001 ? .accentColor : .secondary)
                        }
                    }
                }
            }
            .disabled(!player.settings.speedEnabled)
            .opacity(player.settings.speedEnabled ? 1 : 0.45)

            Text("Die Tonhöhe bleibt unverändert. Pfeiltasten ← / → ändern die Geschwindigkeit in 0,05er-Schritten.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    static func format(_ speed: Double) -> String {
        speed.formatted(.number.precision(.fractionLength(2))) + "×"
    }
}

// MARK: - Loop

private struct LoopCard: View {
    @Environment(AudioPlayer.self) private var player

    var body: some View {
        let settings = player.settings

        Card {
            Toggle(isOn: settingBinding(player, \.loopEnabled)) {
                Label("Loop", systemImage: "repeat").font(.headline)
            }
            .toggleStyle(.switch)

            Group {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                    GridRow {
                        Text("Anfang").foregroundStyle(.secondary)
                        TimeField(value: player.draggedLoopStart ?? settings.loopStart) { new in
                            player.updateSettings { $0.loopStart = new }
                        }
                        CurrentPositionButton(help: "Aktuelle Wiedergabeposition als Anfang übernehmen (Taste S)") {
                            player.setLoopStart(player.currentTime)
                        }
                    }
                    GridRow {
                        Text("Ende").foregroundStyle(.secondary)
                        TimeField(value: player.draggedLoopEnd ?? settings.loopEnd) { new in
                            player.updateSettings { $0.loopEnd = new }
                        }
                        CurrentPositionButton(help: "Aktuelle Wiedergabeposition als Ende übernehmen (Taste E)") {
                            player.setLoopEnd(player.currentTime)
                        }
                    }
                }
                .buttonStyle(.bordered)

                HStack {
                    Button("Zum Loop-Anfang", systemImage: "backward.end.fill") {
                        player.seek(to: settings.loopStart)
                    }
                    Button("Ganzer Titel", systemImage: "arrow.left.and.right") {
                        player.updateSettings {
                            $0.loopStart = 0
                            $0.loopEnd = player.duration
                        }
                    }
                }
                .buttonStyle(.bordered)

                if settings.loopEnabled && player.activeLoop == nil {
                    Label("Das Ende muss mindestens 1 Sekunde nach dem Anfang liegen.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .disabled(!settings.loopEnabled)
            .opacity(settings.loopEnabled ? 1 : 0.45)

            Text("Format: mm:ss, z. B. 01:23 – Zehntelsekunden mit Punkt, z. B. 01:23.5. Tasten: S = Anfang, E = Ende, Leertaste = Play/Pause (springt bei aktivem Loop zum Anfang zurück). Die orangen Marker im Fortschrittsbalken lassen sich mit der Maus ziehen.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct CurrentPositionButton: View {
    let help: String
    let action: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            Button("Aktuelle Position", systemImage: "location.fill", action: action)
            Button("Aktuelle Position", systemImage: "location.fill", action: action)
                .labelStyle(.iconOnly)
        }
        .help(help)
    }
}

/// Text field for a time like "01:23". Commits on Return or when focus leaves.
private struct TimeField: View {
    let value: TimeInterval
    let onCommit: (TimeInterval) -> Void

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("mm:ss", text: $text)
            .textFieldStyle(.roundedBorder)
            .monospacedDigit()
            .multilineTextAlignment(.center)
            .frame(width: 96)
            .focused($focused)
            #if os(iOS)
            .keyboardType(.numbersAndPunctuation)
            #endif
            .onSubmit(commit)
            .onChange(of: focused) { _, isFocused in
                if !isFocused { commit() }
            }
            .onChange(of: value) { _, newValue in
                if !focused { text = Self.format(newValue) }
            }
            .onAppear { text = Self.format(value) }
    }

    private func commit() {
        if let parsed = TimeFormat.parse(text) {
            onCommit(parsed)
            text = Self.format(parsed)
        } else {
            text = Self.format(value)
        }
    }

    static func format(_ time: TimeInterval) -> String {
        abs(time - time.rounded()) < 0.05 ? TimeFormat.string(time.rounded()) : TimeFormat.preciseString(time)
    }
}
