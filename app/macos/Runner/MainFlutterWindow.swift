import AVFoundation
import AuthenticationServices
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
    registerKeychainChannel(flutterViewController.engine.binaryMessenger)
    registerWebAuthChannel(flutterViewController.engine.binaryMessenger)
    registerForDraggedTypes([.fileURL])
    applyWindowSize()

    super.awakeFromNib()
  }

  // MARK: Window size (#130): default and minimum size of the Flutter view, measured in
  // app/test/window_size_test.dart (the same numbers stand in app/lib/ui/window_size.dart).

  /// First start: Player, Practice and Metronome show every control without scrolling.
  static let defaultContentSize = NSSize(width: 1200, height: 880)
  /// Smallest size: the library sidebar has room (desktop layout) and nothing overflows.
  static let minContentSize = NSSize(width: 1010, height: 650)
  /// Key of the saved frame in the user defaults.
  static let frameName = "WoodshedMainWindow"

  /// The frame of the first start: the default size, shrunk to the [visible] area of the screen if that is
  /// smaller, and centred in it.
  static func initialFrame(visible: NSRect, styleMask: NSWindow.StyleMask) -> NSRect {
    let full = NSWindow.frameRect(
      forContentRect: NSRect(origin: .zero, size: defaultContentSize), styleMask: styleMask)
    let width = min(full.width, visible.width)
    let height = min(full.height, visible.height)
    return NSRect(
      x: (visible.midX - width / 2).rounded(), y: (visible.midY - height / 2).rounded(),
      width: width, height: height)
  }

  /// Sets the minimum size and restores the frame saved under [name]; without one (first start) the window
  /// opens with [initialFrame]. Every later change of size or position is saved under [name].
  func applyWindowSize(name: String = MainFlutterWindow.frameName) {
    contentMinSize = Self.minContentSize
    if !setFrameUsingName(name) {
      let visible = (screen ?? NSScreen.main)?.visibleFrame ?? frame
      setFrame(Self.initialFrame(visible: visible, styleMask: styleMask), display: true)
    }
    setFrameAutosaveName(name)
  }

  private(set) var channel: FlutterMethodChannel?

  // MARK: Drag & Drop: audio files dragged into the window (#17, #22) go into the library, onto a playlist or
  // folder where they are dropped (#121).

  /// Pfade der Audiodateien auf dem Pasteboard; andere Dateien werden übergangen (#22/AK2).
  static func audioPaths(on pasteboard: NSPasteboard) -> [String] {
    let options: [NSPasteboard.ReadingOptionKey: Any] = [
      .urlReadingFileURLsOnly: true,
      .urlReadingContentsConformToTypes: [UTType.audio.identifier],
    ]
    let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] ?? []
    return urls.map(\.path)
  }

  /// #121: a point of the window as logical pixels from the top left corner of the Flutter view.
  func flutterPosition(_ windowPoint: NSPoint) -> [String: Double] {
    guard let view = contentViewController?.view else { return [:] }
    let p = view.convert(windowPoint, from: nil)
    return ["x": Double(p.x), "y": Double(view.isFlipped ? p.y : view.bounds.height - p.y)]
  }

  /// Hands the paths and the position to Dart (channel «woodshed/files», method «dropFiles» with
  /// `{paths, x, y}`). false: nothing usable.
  @discardableResult
  func deliverDrop(_ pasteboard: NSPasteboard, at position: [String: Double] = [:]) -> Bool {
    let paths = Self.audioPaths(on: pasteboard)
    guard !paths.isEmpty else { return false }
    var args: [String: Any] = position
    args["paths"] = paths
    channel?.invokeMethod("dropFiles", arguments: args)
    return true
  }

  /// #121: reports the position («dragFiles» `{x, y}`) while audio files are over the window, so that
  /// the target under them lights up.
  func dragOperation(_ pasteboard: NSPasteboard, at position: [String: Double]) -> NSDragOperation {
    guard !Self.audioPaths(on: pasteboard).isEmpty else { return [] }
    channel?.invokeMethod("dragFiles", arguments: position)
    return .copy
  }

  func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    dragOperation(sender.draggingPasteboard, at: flutterPosition(sender.draggingLocation))
  }

  func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
    dragOperation(sender.draggingPasteboard, at: flutterPosition(sender.draggingLocation))
  }

  /// #121: the files left the window; no target stays lit.
  func draggingExited(_ sender: NSDraggingInfo?) {
    channel?.invokeMethod("dragExit", arguments: nil)
  }

  func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    deliverDrop(sender.draggingPasteboard, at: flutterPosition(sender.draggingLocation))
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
      case "commandSocket":
        // #140: the socket file of the command line, the same path the app's program connects to.
        result(CommandLineTool.socketPath)
      case "microphoneAccess":
        // #113/AK4: macOS asks once (NSMicrophoneUsageDescription); afterwards the answer stands until
        // the user changes it in System Settings › Privacy & Security › Microphone.
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
          result(true)
        case .notDetermined:
          AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async { result(granted) }
          }
        default:
          result(false)
        }
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

  // MARK: Keychain (#54/AK1): the refresh token of the cloud sign-in, as a generic password of this app.

  private var keychainChannel: FlutterMethodChannel?

  func registerKeychainChannel(_ messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "woodshed/keychain", binaryMessenger: messenger)
    keychainChannel = channel
    channel.setMethodCallHandler { call, result in
      guard let args = call.arguments as? [String: Any], let key = args["key"] as? String else {
        result(FlutterError(code: "args", message: "key missing", details: nil))
        return
      }
      // SecItem waits while macOS asks for the keychain password (an ad-hoc signed build is a new app to
      // the keychain after every build). Off the main thread, so the window keeps drawing; one serial
      // queue keeps writes and deletes in order. The answer goes back on the main thread.
      MainFlutterWindow.keychainQueue.async {
        let reply = MainFlutterWindow.keychain(call.method, key: key, value: args["value"] as? String)
        DispatchQueue.main.async { result(reply) }
      }
    }
  }

  private static let keychainQueue = DispatchQueue(label: "woodshed.keychain", qos: .userInitiated)

  /// One keychain call; the reply for the channel. A refused or cancelled password prompt is an error
  /// (Dart: the stored sign-in is not readable, the user signs in again).
  private static func keychain(_ method: String, key: String, value: String?) -> Any? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: Bundle.main.bundleIdentifier ?? "WoodshedPlayer",
      kSecAttrAccount as String: key,
    ]
    switch method {
    case "read":
      var item: CFTypeRef?
      var q = query
      q[kSecReturnData as String] = true
      q[kSecMatchLimit as String] = kSecMatchLimitOne
      let status = SecItemCopyMatching(q as CFDictionary, &item)
      if status == errSecSuccess, let data = item as? Data {
        return String(data: data, encoding: .utf8)
      } else if status == errSecItemNotFound {
        return nil
      }
      return FlutterError(code: "keychain", message: "read: \(status)", details: nil)
    case "write":
      let data = Data((value ?? "").utf8)
      var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
      if status == errSecItemNotFound {
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        status = SecItemAdd(add as CFDictionary, nil)
      }
      return status == errSecSuccess
        ? nil : FlutterError(code: "keychain", message: "write: \(status)", details: nil)
    case "delete":
      let status = SecItemDelete(query as CFDictionary)
      return status == errSecSuccess || status == errSecItemNotFound
        ? nil : FlutterError(code: "keychain", message: "delete: \(status)", details: nil)
    default:
      return FlutterMethodNotImplemented
    }
  }
}

// MARK: Sign-in window (#54/AK1): ASWebAuthenticationSession for the cloud sign-in. The provider answers
// through a custom URL scheme; Safari with «HTTPS-Only» refuses a redirect to http://127.0.0.1.

extension MainFlutterWindow: ASWebAuthenticationPresentationContextProviding {
  private static var webAuthChannel: FlutterMethodChannel?
  private static var webAuthSession: ASWebAuthenticationSession?

  func registerWebAuthChannel(_ messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "woodshed/webauth", binaryMessenger: messenger)
    MainFlutterWindow.webAuthChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "start":
        guard let args = call.arguments as? [String: Any],
          let url = (args["url"] as? String).flatMap(URL.init(string:)),
          let scheme = args["scheme"] as? String, let self
        else {
          result(FlutterError(code: "args", message: "url or scheme missing", details: nil))
          return
        }
        self.startWebAuth(url: url, scheme: scheme, result: result)
      case "cancel":
        // the completion handler of the session answers its start with nil
        MainFlutterWindow.webAuthSession?.cancel()
        MainFlutterWindow.webAuthSession = nil
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func startWebAuth(url: URL, scheme: String, result: @escaping FlutterResult) {
    MainFlutterWindow.webAuthSession?.cancel()
    let done: ASWebAuthenticationSession.CompletionHandler = { callback, error in
      DispatchQueue.main.async {
        if let callback {
          result(callback.absoluteString)
        } else if let e = error as? ASWebAuthenticationSessionError, e.code == .canceledLogin {
          result(nil)
        } else {
          result(
            FlutterError(code: "webauth", message: error?.localizedDescription ?? "no answer", details: nil))
        }
      }
    }
    let session: ASWebAuthenticationSession
    if #available(macOS 14.4, *) {
      session = ASWebAuthenticationSession(url: url, callback: .customScheme(scheme), completionHandler: done)
    } else {
      session = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme, completionHandler: done)
    }
    session.presentationContextProvider = self
    MainFlutterWindow.webAuthSession = session
    if !session.start() {
      MainFlutterWindow.webAuthSession = nil
      result(FlutterError(code: "webauth", message: "the sign-in window did not open", details: nil))
    }
  }

  func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
    self
  }
}
