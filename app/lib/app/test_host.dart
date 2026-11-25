// #151: the macOS app as host of the Swift tests (`xcodebuild … test`). xcodebuild sets these variables
// for a hosted test bundle; the Dart app then does not start, so a test run never touches the keychain,
// the microphone, the sync or the library of the installed app. The same check is in
// macos/Runner/MainFlutterWindow.swift (isTestHost).
const swiftTestHostVariables = [
  'XCTestConfigurationFilePath',
  'XCTestBundlePath',
  'XCTestSessionIdentifier',
];

/// True if [environment] is the one of a Swift test run.
bool isSwiftTestHost(Map<String, String> environment) =>
    swiftTestHostVariables.any(environment.containsKey);
