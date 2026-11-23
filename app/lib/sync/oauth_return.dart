// The answer of a sign-in by redirect comes back in the fragment of the page address (#131). Flutter's hash
// URL strategy replaces the address with the first frame, long before the provider module is loaded with
// its deferred import. So the start of the app takes the answer first and hands it on.

/// The fragment (without «#») is an answer of the provider (token or error).
bool isOAuthAnswer(String fragment) =>
    RegExp(r'(^|&)(state|error|access_token)=').hasMatch(fragment);

/// Takes the provider's answer out of [hash] (the page address's fragment, with or without «#»): returns it
/// without «#» and calls [removeFromAddress], so no token stays in the address or the history; '' if
/// [hash] is no answer (the address stays as it is).
String takeOAuthAnswer(String hash, void Function() removeFromAddress) {
  final fragment = hash.startsWith('#') ? hash.substring(1) : hash;
  if (!isOAuthAnswer(fragment)) return '';
  removeFromAddress();
  return fragment;
}
