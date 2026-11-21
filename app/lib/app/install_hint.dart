// #39/AK6: on iPhone and iPad the browser offers no install prompt; the app shows a hint «Add to Home
// Screen» while it runs in the browser and not as the installed app. The check is pure so it can be tested
// with any user agent; platform_web.dart passes the browser's values.

/// iPhone, iPod or iPad. iPadOS reports itself as «Macintosh» but has a touch screen.
bool isIosBrowser(String userAgent, int maxTouchPoints) =>
    RegExp('iPhone|iPad|iPod').hasMatch(userAgent) ||
    (userAgent.contains('Macintosh') && maxTouchPoints > 1);

/// The hint shows on iPhone and iPad as long as the app is not started from the home screen
/// ([standalone]: `navigator.standalone` or display mode «standalone»).
bool wantsInstallHint({
  required String userAgent,
  required int maxTouchPoints,
  required bool standalone,
}) => !standalone && isIosBrowser(userAgent, maxTouchPoints);
