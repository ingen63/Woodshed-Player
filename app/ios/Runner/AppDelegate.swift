import Flutter
import UIKit
import UniformTypeIdentifiers

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var picker: AudioPicker?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "WoodshedFiles") else { return }
    let channel = FlutterMethodChannel(name: "woodshed/files", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "pickAudioFiles":
        self?.pickAudio(result)
      case "supportDir":
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        result(dir.path)
      case "keepAwake":
        // Bildschirm bleibt an, solange das Metronom läuft (FEA-3).
        UIApplication.shared.isIdleTimerDisabled = (call.arguments as? Bool) ?? false
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// Dateiauswahl über den Dokumenten-Dialog; die Datei wird in die App kopiert.
  private func pickAudio(_ result: @escaping FlutterResult) {
    let root = UIApplication.shared.connectedScenes
      .compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }
      .first
    guard let root else { return result(nil) }
    let picker = AudioPicker(result: result)
    self.picker = picker
    root.present(picker.controller, animated: true)
  }
}

private final class AudioPicker: NSObject, UIDocumentPickerDelegate {
  let controller: UIDocumentPickerViewController
  private let result: FlutterResult

  init(result: @escaping FlutterResult) {
    self.result = result
    controller = UIDocumentPickerViewController(forOpeningContentTypes: [.audio], asCopy: true)
    controller.allowsMultipleSelection = true
    super.init()
    controller.delegate = self
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    result(urls.map(\.path))
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    result([String]())
  }
}
