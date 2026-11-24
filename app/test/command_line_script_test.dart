// #140: command line of the desktop app, its parts outside the app: the shell script, the README and
// the exit codes of the program (core/include/wp_cli.h).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:woodshed_player/app/command_line.dart';

void main() {
  test('#140/AK18, AK21: the shell script runs the program of the app; the README says how to install it', () {
    final script = File('../tools/woodshed');
    expect(script.statSync().modeString(), startsWith('rwx'));
    final text = script.readAsStringSync();
    expect(text, startsWith('#!/bin/bash'));
    expect(text, contains('/Applications/Woodshed Player.app'));
    expect(text, contains('Contents/MacOS/Woodshed Player'));
    expect(text, contains(r'exec -a "$(basename "$0")" "$BIN" "$@"'));
    expect(text, contains('set -- --help'));
    final readme = File('../README.md').readAsStringSync();
    expect(readme, contains('| Kommandozeile (nur Mac, #140) |'));
    expect(readme, contains('cp tools/woodshed ~/bin/woodshed'));
    expect(readme, contains('woodshed play --title'));
    expect(readme, contains('woodshed record'));
  });

  test('#140: the exit codes are those of wp_cli.h', () {
    final header = File('../core/include/wp_cli.h').readAsStringSync();
    for (final (name, value) in [
      ('OK', CliExit.ok),
      ('FAILED', CliExit.failed),
      ('USAGE', CliExit.usage),
      ('UNREACHABLE', CliExit.unreachable),
      ('CANCELLED', CliExit.cancelled),
    ]) {
      expect(
        RegExp('#define WP_CLI_EXIT_$name $value\\b').hasMatch(header),
        isTrue,
        reason: name,
      );
    }
  });
}
