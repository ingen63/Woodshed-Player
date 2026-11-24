import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var bonjour: Bonjour?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    bonjour = Bonjour(messenger: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }
}

// K0 (#52): Bonjour (mDNS/DNS-SD) for the native test program. Publishes this instance as
// _woodshed-k0._tcp with a TXT tag derived from the pairing key and reports the instances it finds
// (name, port, tag, IPv4 addresses) over the method channel "k0/bonjour". No internet needed.
final class Bonjour: NSObject, NetServiceDelegate, NetServiceBrowserDelegate {
  static let type = "_woodshed-k0._tcp."
  private let channel: FlutterMethodChannel
  private var published: NetService?
  private var browser: NetServiceBrowser?
  private var resolving: [NetService] = []

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "k0/bonjour", binaryMessenger: messenger)
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return }
      let args = call.arguments as? [String: Any] ?? [:]
      switch call.method {
      case "start":
        self.start(name: args["name"] as? String ?? "", port: args["port"] as? Int ?? 0,
                   tag: args["tag"] as? String ?? "")
        result(nil)
      case "stop":
        self.stop()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func start(name: String, port: Int, tag: String) {
    stop()
    let service = NetService(domain: "local.", type: Bonjour.type, name: name, port: Int32(port))
    service.setTXTRecord(NetService.data(fromTXTRecord: ["tag": Data(tag.utf8)]))
    service.delegate = self
    service.publish()
    published = service
    let browser = NetServiceBrowser()
    browser.delegate = self
    browser.searchForServices(ofType: Bonjour.type, inDomain: "local.")
    self.browser = browser
  }

  private func stop() {
    published?.stop()
    published = nil
    browser?.stop()
    browser = nil
    resolving.forEach { $0.stop() }
    resolving.removeAll()
  }

  func netServiceDidPublish(_ sender: NetService) {
    channel.invokeMethod("published", arguments: ["name": sender.name])
  }

  func netService(_ sender: NetService, didNotPublish errorDict: [String: NSNumber]) {
    channel.invokeMethod("error", arguments: ["text": "publish: \(errorDict)"])
  }

  func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
    channel.invokeMethod("error", arguments: ["text": "browse: \(errorDict)"])
  }

  func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
    service.delegate = self
    resolving.append(service)
    service.resolve(withTimeout: 5)
  }

  func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
    channel.invokeMethod("lost", arguments: ["name": service.name])
  }

  func netServiceDidResolveAddress(_ sender: NetService) {
    var tag = ""
    if let txt = sender.txtRecordData(), let value = NetService.dictionary(fromTXTRecord: txt)["tag"] {
      tag = String(decoding: value, as: UTF8.self)
    }
    let addresses = (sender.addresses ?? []).compactMap(Bonjour.ipv4)
    channel.invokeMethod("found", arguments: [
      "name": sender.name, "port": sender.port, "tag": tag, "addresses": addresses,
    ])
    resolving.removeAll { $0 === sender }
  }

  func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
    resolving.removeAll { $0 === sender }
  }

  private static func ipv4(_ data: Data) -> String? {
    data.withUnsafeBytes { raw -> String? in
      guard raw.count >= MemoryLayout<sockaddr_in>.size else { return nil }
      let addr = raw.load(as: sockaddr_in.self)
      guard addr.sin_family == sa_family_t(AF_INET) else { return nil }
      var sin = addr.sin_addr
      var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
      guard inet_ntop(AF_INET, &sin, &buf, socklen_t(INET_ADDRSTRLEN)) != nil else { return nil }
      return String(cString: buf)
    }
  }
}
