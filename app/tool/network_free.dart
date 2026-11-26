// #58: checks that the app stays free of network access apart from the decided functions (CLAUDE.md
// «Kein Netzwerk», README privacy section). Four checks, strategy in docs/TESTS.md:
//   1. Dart and JavaScript of the app (app/lib, app/packages, app/web and the web core files shipped from
//      core/web): only the provider modules in [providerDir] may import HTTP or socket packages or open
//      connections (HttpClient, WebSocket, sockets, fetch, XMLHttpRequest, ...). Comments do not count.
//      Loading the app's own files (same origin) is allowed on a line marked with [ownOriginMarker] and a
//      reason, on that line or one of the two above. #140: a local Unix domain socket (the command line
//      talks to the running app through a socket file) is allowed on lines marked with [localSocketMarker]
//      in the same way, only in a file that names [InternetAddressType.unix] and nothing of IP (see
//      [localSocketFileProblem]).
//   2. app/pubspec.lock contains no package from [blockedPackages] (analytics, crash reports, ads,
//      remote configuration); exact package names.
//   3. The C++ core (core/src, core/include) has no network calls or headers. core/third_party is never read.
//      #140: the command line client connects to the app's Unix domain socket; lines marked with
//      [localSocketMarker] are allowed in a file that uses AF_UNIX and nothing of IP.
//   4. The web app (app/web/index.html) has a Content Security Policy whose connect-src is exactly
//      [allowedConnectSrc], and every inline script is allowed by its hash in script-src.
//
// Usage: dart app/tool/network_free.dart [--root <repository>]
// Exit code 0: no finding; 1: findings, each with file and line; 2: wrong usage or a file is missing.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// The only place for network code: the cloud provider modules (#38: Google Drive #54, direct
/// connection #56).
const providerDir = 'app/lib/sync/providers/';

/// Marks a line that loads a file of the app's own origin (e.g. the WASM core next to the app).
const ownOriginMarker = 'network-free: own origin';

/// #140: marks a line that uses a local Unix domain socket (a socket file, never TCP or UDP).
const localSocketMarker = 'network-free: local unix socket';

/// #140: a file with [localSocketMarker] lines must name the Unix address family and nothing of IP.
final _unixFamily = RegExp(r'\bInternetAddressType\.unix\b|\bAF_UNIX\b');
final _ipUse = RegExp(
  r'\bInternetAddress\.(?:loopback|any|lookup|tryParse)\w*|\bInternetAddressType\.IPv|'
  r'\b(?:Raw|Secure)?Socket\.(?:connect|startConnect)\b|\bAF_INET6?\b|\bPF_INET6?\b|'
  r'\bsockaddr_in6?\b|\bgetaddrinfo\b|\bgethostbyname\w*|\binet_\w+',
);

/// Folders with Dart and JavaScript of the app, relative to the repository.
const appDirs = ['app/lib', 'app/packages', 'app/web'];

/// Web core files that build_web_core.sh copies into the app (app/web/wp_core/ is the generated copy).
const shippedWebFiles = [
  'core/web/wp_core_web.mjs',
  'core/web/wp_loader.js',
  'core/web/wp_recorder.js',
  'core/web/wp_worklet.js',
];

/// Folders of the C++ core that are checked.
const coreDirs = ['core/src', 'core/include'];

const _appExtensions = {'.dart', '.js', '.mjs', '.html'};
const _coreExtensions = {'.c', '.cc', '.cpp', '.h', '.hpp', '.m', '.mm'};

/// Folders never scanned: build output, tools' caches, generated copies, third-party code.
const _skipDirs = {
  'build',
  '.dart_tool',
  'node_modules',
  'third_party',
  'Pods',
  'ephemeral',
};
const _skipPaths = {'app/web/wp_core'};

/// Network access in Dart and JavaScript, with the text of the finding.
final appPatterns = <(RegExp, String)>[
  (
    RegExp(
      r'''\b(?:import|export)\s+['"]package:(http|http2|dio|web_socket_channel|cronet_http|cupertino_http|ok_http|socket_io_client|grpc|chopper|retrofit)/''',
    ),
    'imports a network package',
  ),
  (RegExp(r'\bHttpClient\b'), 'HttpClient'),
  (RegExp(r'\bHttpServer\b'), 'HttpServer'),
  (RegExp(r'\bHttpRequest\b'), 'HttpRequest'),
  (RegExp(r'\bWebSocket\b'), 'WebSocket'),
  (
    RegExp(
      r'\b(?:Socket|RawSocket|SecureSocket|RawSecureSocket|ServerSocket|RawServerSocket|RawDatagramSocket)\b',
    ),
    'socket',
  ),
  (RegExp(r'\bfetch\s*\('), 'fetch'),
  (RegExp(r'\bXMLHttpRequest\b'), 'XMLHttpRequest'),
  (RegExp(r'\bEventSource\b'), 'EventSource'),
  (RegExp(r'\bsendBeacon\b'), 'sendBeacon'),
  (RegExp(r'\bRTCPeerConnection\b'), 'RTCPeerConnection'),
  (RegExp(r'\bWebTransport\b'), 'WebTransport'),
];

/// Network calls and headers in C and C++.
final corePatterns = <(RegExp, String)>[
  (
    RegExp(
      r'#\s*include\s*[<"](?:sys/socket\.h|netdb\.h|arpa/inet\.h|netinet/[^>"]*|curl/[^>"]*|winsock2?\.h|ws2tcpip\.h)[>"]',
    ),
    'includes a network header',
  ),
  (RegExp(r'\bsocket\s*\('), 'socket'),
  (RegExp(r'\bconnect\s*\('), 'connect'),
  (RegExp(r'\bgetaddrinfo\b'), 'getaddrinfo'),
  (RegExp(r'\bgethostbyname\w*'), 'gethostbyname'),
  (RegExp(r'\bcurl_\w+'), 'curl'),
  (RegExp(r'\bNSURLSession\w*'), 'NSURLSession'),
  (RegExp(r'\bNSURLConnection\b'), 'NSURLConnection'),
  (RegExp(r'\bnw_connection\w*'), 'Network.framework'),
  (RegExp(r'\bCFSocket\w*'), 'CFSocket'),
];

/// Packages for analytics, crash reports, ads or remote configuration. Exact names, no prefixes.
const blockedPackages = {
  // Firebase
  'firebase_core', 'firebase_analytics', 'firebase_crashlytics',
  'firebase_remote_config', 'firebase_performance', 'firebase_messaging',
  'firebase_in_app_messaging', 'firebase_app_installations',
  'firebase_dynamic_links',
  // crash reports
  'sentry', 'sentry_flutter', 'sentry_dart_plugin', 'sentry_logging',
  'bugsnag_flutter', 'bugsnag_flutter_performance', 'datadog_flutter_plugin',
  'instabug_flutter', 'newrelic_mobile', 'embrace', 'raygun4flutter',
  'flutter_rollbar', 'rollbar_flutter', 'appcenter', 'appcenter_crashes',
  'appcenter_analytics', 'flutter_appcenter_bundle',
  // analytics
  'amplitude_flutter', 'mixpanel_flutter', 'mixpanel_analytics',
  'posthog_flutter', 'segment_analytics', 'flutter_segment',
  'analytics', 'rudder_sdk_flutter', 'matomo_tracker', 'plausible_analytics',
  'umami_tracker', 'aptabase_flutter', 'countly_flutter', 'flutter_mixpanel',
  'facebook_app_events', 'appsflyer_sdk', 'adjust_sdk', 'flutter_branch_sdk',
  'singular_flutter_sdk', 'kochava_tracker', 'smartlook', 'uxcam',
  'clarity_flutter',
  // ads
  'google_mobile_ads',
  'applovin_max',
  'unity_ads_plugin',
  'ironsource_mediation',
  'facebook_audience_network', 'easy_ads_flutter', 'admob_flutter',
  'flutter_unity_ads', 'yandex_mobileads', 'appodeal_flutter',
  // remote configuration and feature flags
  'launchdarkly_flutter_client_sdk', 'flagsmith', 'configcat_client',
  'statsig', 'growthbook_sdk_flutter', 'unleash_proxy_client_flutter',
};

/// connect-src of the web app: the own origin and the API and sign-in hosts of the cloud providers.
const allowedConnectSrc = {
  "'self'",
  // Google Drive (#54)
  'https://www.googleapis.com',
  'https://oauth2.googleapis.com',
  'https://accounts.google.com',
};

/// One finding: repository-relative path, line (1-based, 0 = whole file) and what was found.
class Finding {
  const Finding(this.path, this.line, this.what);
  final String path;
  final int line;
  final String what;

  @override
  String toString() => line > 0 ? '$path:$line: $what' : '$path: $what';
}

/// [text] with comments replaced by spaces; strings, line breaks and so line numbers stay.
/// Knows `//`, `/* */` (nested in Dart), `<!-- -->` (HTML), strings in '', "", ``, ''' and """ and
/// raw strings. A single-quoted string ends at a line break, so an apostrophe in prose does not hide
/// the rest of the file.
String stripComments(String text) {
  final out = StringBuffer();
  var i = 0;
  final n = text.length;
  String at(int k) => k < n ? text[k] : '';
  void blank(int from, int to) {
    for (var k = from; k < to && k < n; k++) {
      out.write(text[k] == '\n' ? '\n' : ' ');
    }
  }

  while (i < n) {
    final c = text[i];
    if (c == '/' && at(i + 1) == '/') {
      final end = text.indexOf('\n', i);
      final stop = end < 0 ? n : end;
      blank(i, stop);
      i = stop;
    } else if (c == '/' && at(i + 1) == '*') {
      var depth = 1;
      var k = i + 2;
      while (k < n && depth > 0) {
        if (text[k] == '/' && at(k + 1) == '*') {
          depth++;
          k += 2;
        } else if (text[k] == '*' && at(k + 1) == '/') {
          depth--;
          k += 2;
        } else {
          k++;
        }
      }
      blank(i, k);
      i = k;
    } else if (text.startsWith('<!--', i)) {
      final end = text.indexOf('-->', i + 4);
      final stop = end < 0 ? n : end + 3;
      blank(i, stop);
      i = stop;
    } else if (c == "'" || c == '"' || c == '`') {
      final triple = c != '`' && at(i + 1) == c && at(i + 2) == c;
      final quote = triple ? c * 3 : c;
      final raw = i > 0 && text[i - 1] == 'r';
      final multiLine = triple || c == '`';
      var k = i + quote.length;
      while (k < n) {
        if (!raw && text[k] == '\\') {
          k += 2;
          continue;
        }
        if (text.startsWith(quote, k)) {
          k += quote.length;
          break;
        }
        if (!multiLine && text[k] == '\n') break;
        k++;
      }
      out.write(text.substring(i, k > n ? n : k));
      i = k;
    } else {
      out.write(c);
      i++;
    }
  }
  return out.toString();
}

/// Whether [marker] (default [ownOriginMarker]) is on line [index] or one of the two lines above (a
/// call split by the formatter).
bool _marked(
  List<String> lines,
  int index, [
  String marker = ownOriginMarker,
]) => [
  for (var k = index - 2; k <= index; k++)
    if (k >= 0) lines[k],
].any((l) => l.contains(marker));

/// #140: why the [localSocketMarker] lines of [code] (comments removed) are not allowed, null if
/// they are: the file must use the Unix address family and nothing of IP.
String? localSocketFileProblem(String code) {
  if (!_unixFamily.hasMatch(code)) {
    return 'marked as local unix socket, but the file names no Unix address '
        '(InternetAddressType.unix or AF_UNIX)';
  }
  if (_ipUse.hasMatch(code)) {
    return 'marked as local unix socket, but the file also uses IP '
        '(${_ipUse.firstMatch(code)!.group(0)})';
  }
  return null;
}

/// Socket findings marked with [localSocketMarker] are allowed in a file without [problem].
bool _localSocket(List<String> original, int i, String what, String? problem) =>
    problem == null &&
    const {'socket', 'connect', 'includes a network header'}.contains(what) &&
    _marked(original, i, localSocketMarker);

/// Findings in one Dart or JavaScript file of the app; none in [providerDir].
List<Finding> scanAppSource(String path, String text) {
  if (path.startsWith(providerDir)) return const [];
  final original = text.split('\n');
  final stripped = stripComments(text);
  final code = stripped.split('\n');
  final marked = text.contains(localSocketMarker);
  final problem = marked ? localSocketFileProblem(stripped) : null;
  final found = <Finding>[if (problem != null) Finding(path, 0, problem)];
  for (var i = 0; i < code.length; i++) {
    for (final (pattern, what) in appPatterns) {
      if (!pattern.hasMatch(code[i])) continue;
      if (what == 'fetch' && _marked(original, i)) continue;
      if (marked && _localSocket(original, i, what, problem)) continue;
      final hint = what == 'fetch'
          ? ', or mark a load of own files with «$ownOriginMarker, <reason>»'
          : '';
      found.add(
        Finding(path, i + 1, '$what (network code only in $providerDir$hint)'),
      );
    }
  }
  return found;
}

/// Findings in one C or C++ file of the core.
List<Finding> scanCoreSource(String path, String text) {
  final original = text.split('\n');
  final stripped = stripComments(text);
  final code = stripped.split('\n');
  final marked = text.contains(localSocketMarker);
  final problem = marked ? localSocketFileProblem(stripped) : null;
  final found = <Finding>[if (problem != null) Finding(path, 0, problem)];
  for (var i = 0; i < code.length; i++) {
    for (final (pattern, what) in corePatterns) {
      if (pattern.hasMatch(code[i]) &&
          !(marked && _localSocket(original, i, what, problem))) {
        found.add(Finding(path, i + 1, '$what (no network in the core)'));
      }
    }
  }
  return found;
}

/// Repository-relative paths of the files below [dir] with one of [extensions], sorted.
List<String> sourceFiles(String root, String dir, Set<String> extensions) {
  final base = Directory('$root/$dir');
  if (!base.existsSync()) return const [];
  final files = <String>[];
  void walk(Directory d) {
    for (final e in d.listSync(followLinks: false)) {
      final name = e.uri.pathSegments.where((s) => s.isNotEmpty).last;
      final rel = e.path.substring(root.length + 1);
      if (e is Directory) {
        if (name.startsWith('.') ||
            _skipDirs.contains(name) ||
            _skipPaths.contains(rel)) {
          continue;
        }
        walk(e);
      } else if (e is File && extensions.any(name.endsWith)) {
        files.add(rel);
      }
    }
  }

  walk(base);
  return files..sort();
}

/// Names of all packages in a pubspec.lock.
Set<String> lockPackages(String lock) {
  final names = <String>{};
  var inPackages = false;
  for (final line in const LineSplitter().convert(lock)) {
    if (line.startsWith('packages:')) {
      inPackages = true;
    } else if (line.isNotEmpty && !line.startsWith(' ')) {
      inPackages = false;
    } else if (inPackages) {
      final m = RegExp(r'^  ([A-Za-z0-9_]+):\s*$').firstMatch(line);
      if (m != null) names.add(m.group(1)!);
    }
  }
  return names;
}

/// Findings for blocked packages in [lock] (text of [path]).
List<Finding> checkLock(String path, String lock) {
  final lines = const LineSplitter().convert(lock);
  return [
    for (final name in lockPackages(lock).where(blockedPackages.contains))
      Finding(
        path,
        lines.indexOf('  $name:') + 1,
        'blocked package $name (analytics, crash reports, ads or remote configuration)',
      ),
  ];
}

/// The Content Security Policy of a <meta http-equiv> in [html], or null.
String? cspOf(String html) {
  final meta = RegExp(
    r'''<meta\s[^>]*http-equiv\s*=\s*["']Content-Security-Policy["'][^>]*>''',
    caseSensitive: false,
  ).firstMatch(stripComments(html));
  if (meta == null) return null;
  return RegExp(
    r'''content\s*=\s*"([^"]*)"''',
    caseSensitive: false,
  ).firstMatch(meta.group(0)!)?.group(1);
}

/// Directive name → sources of a policy.
Map<String, List<String>> cspDirectives(String policy) => {
  for (final part in policy.split(';'))
    if (part.trim().isNotEmpty)
      part.trim().split(RegExp(r'\s+')).first.toLowerCase(): part
          .trim()
          .split(RegExp(r'\s+'))
          .skip(1)
          .toList(),
};

/// CSP source for an inline script with exactly [content].
String scriptHash(String content) =>
    "'sha256-${base64.encode(sha256.convert(utf8.encode(content)).bytes)}'";

/// Findings for the Content Security Policy of the web app's [html] (text of [path]).
List<Finding> checkCsp(String path, String html) {
  final policy = cspOf(html);
  if (policy == null) {
    return [Finding(path, 0, 'no Content-Security-Policy <meta>')];
  }
  final line =
      html.split('\n').indexWhere((l) => l.contains('Content-Security')) + 1;
  final d = cspDirectives(policy);
  final found = <Finding>[];
  if (d['default-src'] == null) {
    found.add(Finding(path, line, 'CSP without default-src'));
  }
  final connect = d['connect-src'];
  if (connect == null) {
    found.add(Finding(path, line, 'CSP without connect-src'));
  } else {
    final extra = connect.toSet().difference(allowedConnectSrc);
    final missing = allowedConnectSrc.difference(connect.toSet());
    if (extra.isNotEmpty) {
      found.add(
        Finding(path, line, 'connect-src allows more: ${extra.join(' ')}'),
      );
    }
    if (missing.isNotEmpty) {
      found.add(
        Finding(path, line, 'connect-src is missing: ${missing.join(' ')}'),
      );
    }
  }
  final scriptSrc = d['script-src'] ?? d['default-src'] ?? const <String>[];
  for (final m in RegExp(
    r'<script>(.*?)</script>',
    dotAll: true,
  ).allMatches(html)) {
    final hash = scriptHash(m.group(1)!);
    if (!scriptSrc.contains(hash)) {
      final at = html.substring(0, m.start).split('\n').length;
      found.add(
        Finding(path, at, 'inline script not in script-src, add $hash'),
      );
    }
  }
  return found;
}

/// All checks on the repository at [root]. Throws [FileSystemException] if a required file is missing.
({List<Finding> findings, int files}) checkRepository(String root) {
  final found = <Finding>[];
  var files = 0;
  String read(String rel) => File('$root/$rel').readAsStringSync();

  for (final dir in appDirs) {
    for (final rel in sourceFiles(root, dir, _appExtensions)) {
      files++;
      found.addAll(scanAppSource(rel, read(rel)));
    }
  }
  for (final rel in shippedWebFiles) {
    if (!File('$root/$rel').existsSync()) continue;
    files++;
    found.addAll(scanAppSource(rel, read(rel)));
  }
  for (final dir in coreDirs) {
    for (final rel in sourceFiles(root, dir, _coreExtensions)) {
      files++;
      found.addAll(scanCoreSource(rel, read(rel)));
    }
  }
  found.addAll(checkLock('app/pubspec.lock', read('app/pubspec.lock')));
  found.addAll(checkCsp('app/web/index.html', read('app/web/index.html')));
  return (findings: found, files: files + 2);
}

void main(List<String> args) {
  var root = Directory.current.path;
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--root' && i + 1 < args.length) {
      root = args[++i];
    } else {
      stderr.writeln('usage: dart app/tool/network_free.dart [--root <dir>]');
      exit(2);
    }
  }
  root = Directory(root).absolute.path;
  if (root.endsWith('/')) root = root.substring(0, root.length - 1);
  final ({List<Finding> findings, int files}) result;
  try {
    result = checkRepository(root);
  } on FileSystemException catch (e) {
    stderr.writeln('network-free: ${e.message}: ${e.path}');
    exit(2);
  }
  for (final f in result.findings) {
    stdout.writeln(f);
  }
  if (result.findings.isNotEmpty) {
    stdout.writeln(
      'network-free: ${result.findings.length} finding(s) in ${result.files} files',
    );
    exit(1);
  }
  stdout.writeln('network-free: ok, ${result.files} files checked');
}
