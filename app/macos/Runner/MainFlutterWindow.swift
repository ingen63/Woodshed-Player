import Cocoa
import FlutterMacOS
import UniformTypeIdentifiers

class MainFlutterWindow: NSWindow {
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

  private var channel: FlutterMethodChannel?

  // MARK: Drag & Drop: Audiodatei ins Fenster ziehen.

  private func droppedAudioURL(_ sender: NSDraggingInfo) -> URL? {
    let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingContentsConformToTypes: [UTType.audio.identifier]]
    return (sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL])?.first
  }

  func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    droppedAudioURL(sender) == nil ? [] : .copy
  }

  func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
    droppedAudioURL(sender) == nil ? [] : .copy
  }

  func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    guard let url = droppedAudioURL(sender) else { return false }
    channel?.invokeMethod("openFile", arguments: url.path)
    return true
  }

  /// Dateiauswahl und Ablageort für Aufnahmen (ohne zusätzliches Plugin).
  private func registerFileChannel(_ messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "woodshed/files", binaryMessenger: messenger)
    self.channel = channel
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "pickAudio":
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.begin { response in
          result(response == .OK ? panel.url?.path : nil)
        }
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
