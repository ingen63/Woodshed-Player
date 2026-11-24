import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  /// #140: the program of the app is also its command line. With a command (`play`, `record`,
  /// `--help`) it talks to the running app and ends; otherwise it starts as the app.
  static func main() {
    if let code = CommandLineTool.run(CommandLine.arguments) {
      exit(code)
    }
    _ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}

/// #140: the command line of the desktop app. Arguments, help and the conversation with the app are
/// in the core (`wp_cli_main`, core/src/cli.cpp, the same on Windows and Linux later); this file only
/// gives it the socket file and a way to start the app.
enum CommandLineTool {
  /// Socket file of the command line in the app's container: the same for the app and its program
  /// started from a shell, sandboxed or not. Short, because a socket path holds at most 103 bytes.
  static var socketPath: String {
    let home: String
    if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
      home = String(cString: dir)
    } else {
      home = NSHomeDirectory()
    }
    let id = Bundle.main.bundleIdentifier ?? "ch.woodshed-player-app.desktop"
    return "\(home)/Library/Containers/\(id)/Data/wp-cli.sock"
  }

  private typealias Main = @convention(c) (
    Int32, UnsafePointer<UnsafePointer<CChar>?>?, UnsafePointer<CChar>?,
    (@convention(c) () -> Void)?
  ) -> Int32

  /// The exit code of the command in [arguments], nil if they hold none (start the app).
  static func run(_ arguments: [String]) -> Int32? {
    // Only look further if the first argument may be a command; the app starts fast otherwise.
    guard arguments.count > 1, ["play", "record", "help", "--help", "-h"].contains(arguments[1])
    else { return nil }
    guard let main = loadMain() else {
      FileHandle.standardError.write(Data("The command line is not available in this build.\n".utf8))
      return 1
    }
    let cStrings = arguments.map { strdup($0) }
    defer { cStrings.forEach { free($0) } }
    var argv = cStrings.map { UnsafePointer<CChar>($0) }
    let code = argv.withUnsafeMutableBufferPointer { buf in
      socketPath.withCString { path in
        main(Int32(buf.count), UnsafePointer(buf.baseAddress), path, launchApp)
      }
    }
    return code == -1 ? nil : code  // WP_CLI_NOT_A_COMMAND
  }

  /// `wp_cli_main` of the core, which the Flutter plugin wp_core bundles as a framework.
  private static func loadMain() -> Main? {
    let candidates = [
      Bundle.main.privateFrameworksPath.map { "\($0)/wp_core.framework/wp_core" },
      "wp_core.framework/wp_core",
    ].compactMap { $0 }
    for path in candidates {
      if let handle = dlopen(path, RTLD_NOW), let sym = dlsym(handle, "wp_cli_main") {
        return unsafeBitCast(sym, to: Main.self)
      }
    }
    return nil
  }

  /// Starts a new instance of this app in the background; the command waits for its socket.
  private static let launchApp: @convention(c) () -> Void = {
    let config = NSWorkspace.OpenConfiguration()
    config.activates = false
    config.addsToRecentItems = false
    // The command itself runs from the app's program, so Launch Services would only find it.
    config.createsNewApplicationInstance = true
    NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config) { _, error in
      if let error {
        FileHandle.standardError.write(Data("Woodshed Player could not be started: \(error)\n".utf8))
      }
    }
  }
}
