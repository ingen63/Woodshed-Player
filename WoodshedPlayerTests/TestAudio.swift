import AVFoundation
import Foundation

/// Erzeugt Testaudio zur Laufzeit. Es liegen keine Audiodateien im Repo.
enum TestAudio {
    /// Schreibt einen Sinuston als WAV in einen temporären Ordner und gibt die URL zurück.
    static func sineWave(seconds: Double, frequency: Double = 440, sampleRate: Double = 44_100) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("woodshed-test-\(UUID().uuidString).wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let frames = AVAudioFrameCount(seconds * sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let samples = buffer.floatChannelData![0]
        for i in 0..<Int(frames) {
            samples[i] = Float(0.25 * sin(2 * .pi * frequency * Double(i) / sampleRate))
        }
        let file = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
        ])
        try file.write(from: buffer)
        return url
    }

    /// Leerer temporärer Ordner, z. B. als Bibliotheksordner.
    static func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("woodshed-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
