// #151: as host of the Swift tests the app does not start its Dart part, so a test run never touches
// the keychain, the microphone or the library of the installed app.
import Cocoa
import FlutterMacOS
import Testing

@testable import Woodshed_Player

struct TestHostTests {
  @Test("#151/AK4 the test run is recognised as test host")
  func recognisedAsTestHost() {
    #expect(MainFlutterWindow.isTestHost())
  }

  @Test("#151/AK4 a normal start is no test host")
  func normalStartIsNoTestHost() {
    #expect(!MainFlutterWindow.isTestHost([:]))
    #expect(!MainFlutterWindow.isTestHost(["HOME": "/Users/x", "PATH": "/usr/bin"]))
    #expect(MainFlutterWindow.isTestHost(["XCTestConfigurationFilePath": "/tmp/x.xctestconfiguration"]))
    #expect(MainFlutterWindow.isTestHost(["XCTestBundlePath": "/tmp/RunnerTests.xctest"]))
    #expect(MainFlutterWindow.isTestHost(["XCTestSessionIdentifier": "1"]))
  }

  @Test("#151/AK1 #151/AK4 the main window has its Flutter view, but the Dart app is not started")
  @MainActor
  func dartNotStarted() throws {
    let window = try #require(NSApp.windows.compactMap { $0 as? MainFlutterWindow }.first)
    #expect(window.contentViewController is FlutterViewController)
    #expect(window.contentView != nil)
    #expect(!window.dartStarted)
  }
}

struct TestHostGuardTests {
  @Test("#151/AK1 no call from Dart reached keychain, microphone or sign-in during the test run")
  @MainActor
  func noDartCalls() {
    #expect(MainFlutterWindow.dartCallsInTestHost == 0)
  }

  @Test("#151/AK1 the keychain is never touched as test host")
  func keychainRefused() {
    for method in ["read", "write", "delete"] {
      let reply = MainFlutterWindow.keychain(method, key: "google.refreshToken", value: "x")
      #expect((reply as? FlutterError)?.code == "testHost", "\(method)")
    }
  }
}
