import AVFoundation
import Foundation
import Observation

/// Plays one file through AVAudioEngine:
/// AVAudioPlayerNode → AVAudioUnitTimePitch (rate without pitch change) → main mixer.
/// Loops are scheduled as repeating file segments, so they are gapless and sample-accurate.
@Observable
@MainActor
final class AudioPlayer {
    private(set) var track: Track?
    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var settings = PlaybackSettings()
    private(set) var volume: Float = 1
    var errorMessage: String?
    /// Loop bounds while a marker is being dragged; shown live, committed when the drag ends.
    var draggedLoopStart: TimeInterval?
    var draggedLoopEnd: TimeInterval?

    /// Called whenever the settings of the loaded track change, so they can be persisted.
    @ObservationIgnored var onSettingsChanged: ((UUID, PlaybackSettings) -> Void)?

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private let node = AVAudioPlayerNode()
    @ObservationIgnored private let timePitch = AVAudioUnitTimePitch()
    @ObservationIgnored private var file: AVAudioFile?
    @ObservationIgnored private var sampleRate: Double = 44_100
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    // Scheduling state. `generation` invalidates completion handlers of segments
    // that were scheduled before the last stop/seek.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var segmentStart: AVAudioFramePosition = 0
    @ObservationIgnored private var segmentLength: AVAudioFramePosition = 0
    @ObservationIgnored private var scheduledLoop: Range<AVAudioFramePosition>?
    @ObservationIgnored private var pausedFrame: AVAudioFramePosition = 0

    /// The loop end must always be at least this far after the loop start.
    static let minimumLoopLength: TimeInterval = 1
    /// Step for the + / − keys.
    static let speedStep = 0.05

    init() {
        engine.attach(node)
        engine.attach(timePitch)
        configureAudioSession()
        observeEngine()
    }

    // MARK: - Loading

    func load(_ track: Track, url: URL) {
        stopPlayback()
        do {
            let file = try AVAudioFile(forReading: url)
            let format = file.processingFormat
            engine.stop()
            engine.disconnectNodeOutput(node)
            engine.disconnectNodeOutput(timePitch)
            engine.connect(node, to: timePitch, format: format)
            engine.connect(timePitch, to: engine.mainMixerNode, format: format)
            engine.prepare()

            self.file = file
            self.track = track
            sampleRate = format.sampleRate
            duration = Double(file.length) / sampleRate
            settings = track.settings
            timePitch.rate = Float(settings.effectiveRate)
            pausedFrame = 0
            currentTime = 0
            errorMessage = nil
        } catch {
            unload()
            errorMessage = "Datei konnte nicht geöffnet werden: \(error.localizedDescription)"
        }
    }

    func unload() {
        stopPlayback()
        file = nil
        track = nil
        duration = 0
        currentTime = 0
        pausedFrame = 0
    }

    // MARK: - Transport

    func togglePlayPause() {
        isPlaying ? pause() : play()
    }

    func play() {
        guard file != nil, !isPlaying else { return }
        startPlayback(at: pausedFrame)
    }

    func pause() {
        guard isPlaying else { return }
        pausedFrame = currentFrame()
        stopPlayback()
        currentTime = seconds(pausedFrame)
    }

    func seek(to time: TimeInterval) {
        guard file != nil else { return }
        let frame = frames(min(max(0, time), duration))
        if isPlaying {
            startPlayback(at: frame)
        } else {
            pausedFrame = frame
            currentTime = seconds(frame)
        }
    }

    func skip(by delta: TimeInterval) {
        seek(to: currentTime + delta)
    }

    /// Space bar: like play/pause, but stopping inside an active loop jumps back to the loop start.
    func togglePlayPauseReturningToLoop() {
        guard isPlaying else { return play() }
        pause()
        if let loop = activeLoop { seek(to: loop.lowerBound) }
    }

    func setVolume(_ value: Float) {
        volume = value
        engine.mainMixerNode.outputVolume = value
    }

    // MARK: - Settings

    func updateSettings(_ change: (inout PlaybackSettings) -> Void) {
        var new = settings
        change(&new)
        new.speed = min(max(new.speed, PlaybackSettings.speedRange.lowerBound), PlaybackSettings.speedRange.upperBound)
        new.loopStart = min(max(0, new.loopStart), duration)
        new.loopEnd = min(max(0, new.loopEnd), duration)
        let minimum = Self.minimumLoopLength
        let startMoved = new.loopStart != settings.loopStart
        let endMoved = new.loopEnd != settings.loopEnd
        if new.loopEnd - new.loopStart < minimum && duration >= minimum {
            if startMoved {
                // Start set behind the end: loop up to the end of the track until a new end is set.
                new.loopStart = min(new.loopStart, duration - minimum)
                new.loopEnd = duration
            } else if endMoved {
                new.loopEnd = min(duration, new.loopStart + minimum)
                new.loopStart = min(new.loopStart, new.loopEnd - minimum)
            } else if new.loopEnabled && !settings.loopEnabled {
                // Enabling a loop without bounds: loop the whole file.
                new.loopStart = 0
                new.loopEnd = duration
            }
        }
        guard new != settings else { return }

        let old = settings
        settings = new
        timePitch.rate = Float(new.effectiveRate)

        let loopChanged = old.loopEnabled != new.loopEnabled
            || (new.loopEnabled && (old.loopStart != new.loopStart || old.loopEnd != new.loopEnd))
        if loopChanged && isPlaying {
            startPlayback(at: currentFrame())
        }
        if let id = track?.id {
            onSettingsChanged?(id, new)
        }
    }

    /// Sets a loop bound (S / E keys, marker drag) and switches the loop on.
    func setLoopStart(_ time: TimeInterval) {
        updateSettings {
            $0.loopEnabled = true
            $0.loopStart = time
        }
    }

    func setLoopEnd(_ time: TimeInterval) {
        updateSettings {
            $0.loopEnabled = true
            $0.loopEnd = time
        }
    }

    /// Changes the speed by whole `speedStep`s (+ / − keys) and switches speed on.
    func adjustSpeed(bySteps steps: Int) {
        updateSettings {
            $0.speedEnabled = true
            $0.speed = (($0.speed / Self.speedStep).rounded() + Double(steps)) * Self.speedStep
        }
    }

    /// The active loop in seconds, or nil if looping is off or the bounds are invalid.
    var activeLoop: ClosedRange<TimeInterval>? {
        guard settings.loopEnabled,
              settings.loopEnd - settings.loopStart >= Self.minimumLoopLength else { return nil }
        return settings.loopStart...settings.loopEnd
    }

    // MARK: - Scheduling

    private func startPlayback(at requested: AVAudioFramePosition) {
        guard let file else { return }
        generation += 1
        let gen = generation
        node.stop()

        let total = file.length
        var start = min(max(0, requested), total)

        if let loop = activeLoop {
            let range = frames(loop.lowerBound)..<frames(loop.upperBound)
            // Positions at or past the loop end restart at the loop start.
            if start >= range.upperBound { start = range.lowerBound }
            segmentStart = start
            segmentLength = range.upperBound - start
            scheduledLoop = range
            node.scheduleSegment(file, startingFrame: start, frameCount: AVAudioFrameCount(segmentLength), at: nil)
            // Keep two loop passes queued so there is never a gap.
            scheduleLoopPass(gen)
            scheduleLoopPass(gen)
        } else {
            if start >= total { start = 0 }
            segmentStart = start
            segmentLength = total - start
            scheduledLoop = nil
            node.scheduleSegment(file, startingFrame: start, frameCount: AVAudioFrameCount(segmentLength), at: nil,
                                 completionCallbackType: .dataPlayedBack) { [weak self] _ in
                Task { @MainActor in self?.playbackReachedEnd(gen) }
            }
        }

        do {
            if !engine.isRunning { try engine.start() }
        } catch {
            errorMessage = "Audio konnte nicht gestartet werden: \(error.localizedDescription)"
            return
        }
        node.play()
        isPlaying = true
        startTimer()
        tick()
    }

    private func scheduleLoopPass(_ gen: Int) {
        guard gen == generation, let file, let loop = scheduledLoop else { return }
        node.scheduleSegment(file, startingFrame: loop.lowerBound, frameCount: AVAudioFrameCount(loop.count), at: nil,
                             completionCallbackType: .dataConsumed) { [weak self] _ in
            Task { @MainActor in self?.scheduleLoopPass(gen) }
        }
    }

    private func playbackReachedEnd(_ gen: Int) {
        guard gen == generation else { return }
        stopPlayback()
        pausedFrame = 0
        currentTime = 0
    }

    private func stopPlayback() {
        generation += 1
        node.stop()
        isPlaying = false
        timer?.invalidate()
        timer = nil
    }

    /// Current position in file frames, derived from what the player node has rendered.
    private func currentFrame() -> AVAudioFramePosition {
        guard isPlaying,
              let nodeTime = node.lastRenderTime,
              let playerTime = node.playerTime(forNodeTime: nodeTime) else { return pausedFrame }
        let played = max(0, playerTime.sampleTime)
        if played < segmentLength {
            return segmentStart + played
        }
        if let loop = scheduledLoop {
            return loop.lowerBound + (played - segmentLength) % AVAudioFramePosition(loop.count)
        }
        return segmentStart + segmentLength
    }

    private func startTimer() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        currentTime = seconds(currentFrame())
    }

    private func frames(_ time: TimeInterval) -> AVAudioFramePosition {
        AVAudioFramePosition((time * sampleRate).rounded())
    }

    private func seconds(_ frames: AVAudioFramePosition) -> TimeInterval {
        Double(frames) / sampleRate
    }

    // MARK: - System integration

    private func configureAudioSession() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
        #endif
    }

    private func observeEngine() {
        let center = NotificationCenter.default
        // Output device changed (e.g. headphones): the engine stops, so restart from the current position.
        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isPlaying else { return }
                let frame = self.currentFrame()
                self.stopPlayback()
                self.startPlayback(at: frame)
            }
        })
        #if os(iOS)
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let typeValue = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            MainActor.assumeIsolated {
                if typeValue == AVAudioSession.InterruptionType.began.rawValue {
                    self?.pause()
                }
            }
        })
        #endif
    }
}
