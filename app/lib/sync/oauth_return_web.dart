// Takes the provider's answer from the page address before Flutter replaces it (#131). Small on purpose:
// it is loaded with the app, the provider modules only once a provider is chosen (#54/AK6).

import 'package:web/web.dart' as web;

import 'oauth_return.dart';

/// Called at start, before the first frame: the answer in the fragment (without «#»), '' if there is none.
/// The entry in the history is replaced, so the token is neither in the address nor in the history.
String takeStartAnswer() {
  final loc = web.window.location;
  return takeOAuthAnswer(
    loc.hash,
    () => web.window.history.replaceState(
      null,
      '',
      '${loc.pathname}${loc.search}',
    ),
  );
}
