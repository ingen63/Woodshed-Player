// Random tests (#10/AK1, AK2, AK6): every property runs over many cases from `dart:math` Random with a
// fixed seed that is printed, so every failure can be repeated exactly. No extra package.
//
// - WP_PROPERTY_CASES: number of random cases per property (default [defaultCases], fast enough for
//   every run; the nightly workflow runs thousands). A property may scale it (e.g. the slow sync cases).
// - WP_PROPERTY_SEED: seed of the run (default [defaultSeed]). Case i uses the seed
//   `caseSeed(runSeed, i)`; the failure message names it.
// - Regressions: case seeds that once failed are checked in to `regressions.json` under the name of the
//   property and run first, on every run, before the random cases.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

const defaultCases = 100;
const defaultSeed = 20261119;

/// Run configuration from the environment (or a given map, for the tests of this helper).
class PropertyConfig {
  const PropertyConfig(this.cases, this.seed);

  factory PropertyConfig.fromEnvironment([Map<String, String>? env]) {
    final e = env ?? Platform.environment;
    final cases = int.tryParse(e['WP_PROPERTY_CASES'] ?? '');
    final seed = int.tryParse(e['WP_PROPERTY_SEED'] ?? '');
    return PropertyConfig(
      cases != null && cases > 0 ? cases : defaultCases,
      seed ?? defaultSeed,
    );
  }

  final int cases;
  final int seed;

  static final current = PropertyConfig.fromEnvironment();
}

/// Seed of case [index] in a run with [runSeed]: distinct per case, the same on every platform
/// (below 2^31, also exact in JavaScript).
int caseSeed(int runSeed, int index) =>
    (runSeed * 1000003 + index * 7919 + 12345) & 0x7fffffff;

/// Case seeds checked in for [name] (`regressions.json` next to this file).
List<int> regressionSeeds(String name, {String? file}) {
  final f = File(file ?? 'test/property/regressions.json');
  if (!f.existsSync()) return const [];
  final j = jsonDecode(f.readAsStringSync()) as Map<String, Object?>;
  final entry = j[name];
  if (entry is! List) return const [];
  return [
    for (final e in entry)
      if (e is Map && e['seed'] is int) e['seed'] as int,
  ];
}

/// The seeds a property runs, in order: regressions first, then [cases] random ones.
List<(int, String)> plannedSeeds(
  String name,
  PropertyConfig config, {
  int? cases,
  List<int>? regressions,
}) => [
  for (final s in regressions ?? regressionSeeds(name)) (s, 'regression'),
  for (var i = 0; i < (cases ?? config.cases); i++)
    (caseSeed(config.seed, i), 'case $i'),
];

/// Defines a test that checks [body] for every planned seed. [scale] multiplies the number of
/// random cases (e.g. 0.2 for slow properties, at least 1 case).
void property(
  String name,
  FutureOr<void> Function(Random random) body, {
  double scale = 1,
  Timeout? timeout,
}) {
  final config = PropertyConfig.current;
  final cases = max(1, (config.cases * scale).round());
  test(name, () async {
    final seeds = plannedSeeds(name, config, cases: cases);
    // ignore: avoid_print
    print(
      'property "$name": run seed ${config.seed}, $cases cases, '
      '${seeds.length - cases} regressions',
    );
    for (final (seed, label) in seeds) {
      try {
        await body(Random(seed));
      } catch (e, st) {
        fail(
          'property "$name" failed for case seed $seed ($label, run seed '
          '${config.seed}). Repeat: put {"seed": $seed} under "$name" in '
          'test/property/regressions.json.\n$e\n$st',
        );
      }
    }
  }, timeout: timeout);
}

/// Picks one element.
T pick<T>(Random r, List<T> items) => items[r.nextInt(items.length)];
