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
      case "openUrl":
        // #50/AK6: links of the About dialog open in the default browser.
        if let text = call.arguments as? String, let url = URL(string: text),
          url.scheme == "https"
        {
          NSWorkspace.shared.open(url)
        }
        result(nil)
      case "buildInfo":
        // #50/AK6: written by tool/stamp_build_info.sh at build time.
        let info = Bundle.main.infoDictionary ?? [:]
        result(["tag": info["WPGitTag"] as? String ?? "", "date": info["WPBuildDate"] as? String ?? ""])
      case "setAboutMenuTitle":
        if let title = call.arguments as? String { self.routeAboutMenu(title: title) }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  // MARK: About (#50/AK6): the app menu item «About …» opens the Flutter dialog instead of the standard panel.

  /// Points the first item of the app menu (the standard «About …») at [showAbout] and sets its localized title.
  func routeAboutMenu(title: String) {
    guard let item = NSApp.mainMenu?.items.first?.submenu?.items.first,
      item.action == #selector(NSApplication.orderFrontStandardAboutPanel(_:))
        || item.action == #selector(showAbout(_:))
    else { return }
    item.title = title
    item.target = self
    item.action = #selector(showAbout(_:))
  }

  @objc func showAbout(_ sender: Any?) {
    channel?.invokeMethod("showAbout", arguments: nil)
  }
}
