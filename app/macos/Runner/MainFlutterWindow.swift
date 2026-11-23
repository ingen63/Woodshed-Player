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
      let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: Bundle.main.bundleIdentifier ?? "WoodshedPlayer",
        kSecAttrAccount as String: key,
      ]
      switch call.method {
      case "read":
        var item: CFTypeRef?
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data {
          result(String(data: data, encoding: .utf8))
        } else if status == errSecItemNotFound {
          result(nil)
        } else {
          result(FlutterError(code: "keychain", message: "read: \(status)", details: nil))
        }
      case "write":
        let data = Data(((args["value"] as? String) ?? "").utf8)
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
          var add = query
          add[kSecValueData as String] = data
          add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
          status = SecItemAdd(add as CFDictionary, nil)
        }
        result(
          status == errSecSuccess
            ? nil : FlutterError(code: "keychain", message: "write: \(status)", details: nil))
      case "delete":
        let status = SecItemDelete(query as CFDictionary)
        result(
          status == errSecSuccess || status == errSecItemNotFound
            ? nil : FlutterError(code: "keychain", message: "delete: \(status)", details: nil))
      default:
        result(FlutterMethodNotImplemented)
      }
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
