import Cocoa
import FlutterMacOS
import UniformTypeIdentifiers

// NSDraggingDestination ausdrücklich angeben (#22): Ohne die Konformität sind die Drag-Methoden unten
// für AppKit unsichtbar (kein @objc), und es greift die Standard-Implementierung von NSWindow, die nichts tut.
class MainFlutterWindow: NSWindow, NSDraggingDestination {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    registerFileChannel(flutterViewController.engine.binaryMessenger)
    registerForDraggedTypes([.fileURL])

    super.awakeFromNib()
  }

  private(set) var channel: FlutterMethodChannel?

  // MARK: Drag & Drop: Audiodateien ins Fenster ziehen (#17, #22), sie kommen in die Bibliothek.

  /// Pfade der Audiodateien auf dem Pasteboard; andere Dateien werden übergangen (#22/AK2).
  static func audioPaths(on pasteboard: NSPasteboard) -> [String] {
    let options: [NSPasteboard.ReadingOptionKey: Any] = [
      .urlReadingFileURLsOnly: true,
      .urlReadingContentsConformToTypes: [UTType.audio.identifier],
    ]
    let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] ?? []
    return urls.map(\.path)
  }

  /// Übergibt die Pfade an Dart (Kanal «woodshed/files», Methode «dropFiles»). false: nichts Brauchbares.
  @discardableResult
  func deliverDrop(_ pasteboard: NSPasteboard) -> Bool {
    let paths = Self.audioPaths(on: pasteboard)
    guard !paths.isEmpty else { return false }
    channel?.invokeMethod("dropFiles", arguments: paths)
    return true
  }

  func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    Self.audioPaths(on: sender.draggingPasteboard).isEmpty ? [] : .copy
  }

  func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
    Self.audioPaths(on: sender.draggingPasteboard).isEmpty ? [] : .copy
  }

  func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    deliverDrop(sender.draggingPasteboard)
  }

  /// Dateiauswahl und Ablageort für Aufnahmen (ohne zusätzliches Plugin).
  func registerFileChannel(_ messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "woodshed/files", binaryMessenger: messenger)
    self.channel = channel
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "pickAudioFiles":
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = true
        panel.begin { response in
          result(response == .OK ? panel.urls.map(\.path) : [])
        }
      case "supportDir":
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        result(dir.path)
      case "keepAwake":
        result(nil)  // auf dem Mac nicht nötig
      case "recordingsDir":
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
          .appendingPathComponent("Recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        result(dir.path)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
