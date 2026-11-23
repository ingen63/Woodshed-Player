// Nativer Teil des macOS-Fensters: Drag & Drop in die Bibliothek (#22).
import Cocoa
import FlutterMacOS
import Testing
import UniformTypeIdentifiers

@testable import Woodshed_Player

/// Fängt, was das Fenster über den Kanal an Dart schickt.
final class RecordingMessenger: NSObject, FlutterBinaryMessenger {
  var sent: [(channel: String, message: Data?)] = []
  func send(onChannel channel: String, message: Data?) { sent.append((channel, message)) }
  func send(onChannel channel: String, message: Data?, binaryReply callback: FlutterBinaryReply? = nil) {
    sent.append((channel, message))
  }
  func setMessageHandlerOnChannel(
    _ channel: String, binaryMessageHandler handler: FlutterBinaryMessageHandler? = nil
  ) -> FlutterBinaryMessengerConnection { 0 }
  func cleanUpConnection(_ connection: FlutterBinaryMessengerConnection) {}
}

/// Eigenes Pasteboard mit Dateien (leer erzeugt, keine echten Audiodaten nötig).
func pasteboard(with names: [String]) throws -> (NSPasteboard, [URL]) {
  let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  let urls = try names.map { name -> URL in
    let u = dir.appendingPathComponent(name)
    try Data("x".utf8).write(to: u)
    return u
  }
  let pb = NSPasteboard(name: .init("wp-test-\(UUID().uuidString)"))
  pb.clearContents()
  pb.writeObjects(urls as [NSURL])
  return (pb, urls)
}

struct DragAndDropTests {

  @Test("#22 Regressionstest: Drag-Methoden sind für AppKit sichtbar (eigene Implementierung)")
  func dragMethodsReachAppKit() {
    for name in ["draggingEntered:", "draggingUpdated:", "draggingExited:", "performDragOperation:"] {
      let sel = NSSelectorFromString(name)
      let own = class_getInstanceMethod(MainFlutterWindow.self, sel)
      #expect(own != nil, "\(name) fehlt")
      #expect(own != class_getInstanceMethod(NSWindow.self, sel), "\(name) ist nur die NSWindow-Fassung")
    }
  }

  @Test("#22 Fenster ist Drag-Ziel, kein Unter-View fängt Dateien vorher ab")
  @MainActor
  func windowReceivesFileDrags() throws {
    let window = try #require(NSApp.windows.compactMap { $0 as? MainFlutterWindow }.first)
    func views(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(views) }
    let content = try #require(window.contentView)
    let interceptors = views(content).filter { $0.registeredDraggedTypes.contains(.fileURL) }
    #expect(interceptors.isEmpty, "\(interceptors)")
  }

  @Test("#22/AK1 mehrere Audiodateien werden erkannt")
  func audioFilesAccepted() throws {
    let (pb, urls) = try pasteboard(with: ["a.mp3", "b.flac", "c.wav", "d.m4a"])
    #expect(MainFlutterWindow.audioPaths(on: pb) == urls.map(\.path))
  }

  @Test("#22/AK2 nicht unterstützte Dateien werden übergangen")
  func otherFilesSkipped() throws {
    let (pb, urls) = try pasteboard(with: ["notiz.txt", "lied.mp3", "bild.png"])
    #expect(MainFlutterWindow.audioPaths(on: pb) == [urls[1].path])
    let (onlyText, _) = try pasteboard(with: ["notiz.txt"])
    #expect(MainFlutterWindow.audioPaths(on: onlyText).isEmpty)
  }

  @Test("#22/AK3 Pfade gehen als «dropFiles» über den Kanal «woodshed/files» an Dart")
  @MainActor
  func pathsDeliveredToDart() throws {
    let window = MainFlutterWindow()
    let messenger = RecordingMessenger()
    window.registerFileChannel(messenger)
    let (pb, urls) = try pasteboard(with: ["a.mp3", "notiz.txt", "b.wav"])

    #expect(window.deliverDrop(pb, at: ["x": 12, "y": 34]))
    let msg = try #require(messenger.sent.last)
    #expect(msg.channel == "woodshed/files")
    let call = FlutterStandardMethodCodec.sharedInstance().decodeMethodCall(try #require(msg.message))
    #expect(call.method == "dropFiles")
    let args = try #require(call.arguments as? [String: Any])
    #expect(args["paths"] as? [String] == [urls[0].path, urls[2].path])
    #expect(args["x"] as? Double == 12)
    #expect(args["y"] as? Double == 34)

    let (none, _) = try pasteboard(with: ["notiz.txt"])
    let before = messenger.sent.count
    #expect(!window.deliverDrop(none))
    #expect(messenger.sent.count == before)
  }

  @Test("#121/AK4 audio files over the window report their position as «dragFiles», leaving as «dragExit»")
  @MainActor
  func dragPositionDeliveredToDart() throws {
    let window = MainFlutterWindow()
    let messenger = RecordingMessenger()
    window.registerFileChannel(messenger)
    let codec = FlutterStandardMethodCodec.sharedInstance()
    let (pb, _) = try pasteboard(with: ["a.mp3"])

    #expect(window.dragOperation(pb, at: ["x": 5, "y": 7]) == .copy)
    let over = codec.decodeMethodCall(try #require(messenger.sent.last?.message))
    #expect(over.method == "dragFiles")
    #expect((over.arguments as? [String: Double]) == ["x": 5, "y": 7])

    let (none, _) = try pasteboard(with: ["notiz.txt"])
    let before = messenger.sent.count
    #expect(window.dragOperation(none, at: ["x": 5, "y": 7]) == [])
    #expect(messenger.sent.count == before)

    window.draggingExited(nil)
    #expect(codec.decodeMethodCall(try #require(messenger.sent.last?.message)).method == "dragExit")
  }

  @Test("#121 a point of the window counts from the top left corner of the Flutter view")
  @MainActor
  func positionFromTopLeft() throws {
    let window = MainFlutterWindow(
      contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.borderless],
      backing: .buffered, defer: true)
    #expect(window.flutterPosition(NSPoint(x: 1, y: 1)).isEmpty)
    let controller = NSViewController()
    controller.view = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
    window.contentViewController = controller
    let p = window.flutterPosition(NSPoint(x: 10, y: 150))
    #expect(p["x"] == 10)
    #expect(p["y"] == 50)
  }
}
