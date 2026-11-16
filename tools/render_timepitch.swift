// Rendert eine Audiodatei offline mit AVAudioUnitTimePitch (wie die Swift-App) als WAV.
// Aufruf: swift tools/render_timepitch.swift <eingabe> <ausgabe.wav> <tempo> [sekunden]
import AVFoundation

let args = CommandLine.arguments
guard args.count >= 4, let rate = Float(args[3]) else {
    print("Aufruf: render_timepitch <eingabe> <ausgabe.wav> <tempo> [sekunden]")
    exit(2)
}
let seconds = args.count > 4 ? Double(args[4]) ?? 0 : 0

let file = try AVAudioFile(forReading: URL(fileURLWithPath: args[1]))
let format = file.processingFormat
let sourceFrames = seconds > 0 ? min(file.length, AVAudioFramePosition(seconds * format.sampleRate)) : file.length

let engine = AVAudioEngine()
let player = AVAudioPlayerNode()
let timePitch = AVAudioUnitTimePitch()
timePitch.rate = rate
engine.attach(player)
engine.attach(timePitch)
engine.connect(player, to: timePitch, format: format)
engine.connect(timePitch, to: engine.mainMixerNode, format: format)
try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
try engine.start()
player.scheduleSegment(file, startingFrame: 0, frameCount: AVAudioFrameCount(sourceFrames), at: nil)
player.play()

// In einer Funktion, damit die Datei am Ende geschlossen wird (Header mit Länge).
func render() throws {
    let wav = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: format.sampleRate,
                            channels: format.channelCount, interleaved: true)!
    let out = try AVAudioFile(forWriting: URL(fileURLWithPath: args[2]), settings: wav.settings,
                              commonFormat: .pcmFormatFloat32, interleaved: false)
    let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 4096)!
    let total = AVAudioFramePosition(Double(sourceFrames) / Double(rate))
    while engine.manualRenderingSampleTime < total {
        let n = min(4096, AVAudioFrameCount(total - engine.manualRenderingSampleTime))
        guard try engine.renderOffline(n, to: buffer) == .success else { break }
        try out.write(from: buffer)
    }
}
try render()
print("\(args[2]): Tempo \(rate)")
