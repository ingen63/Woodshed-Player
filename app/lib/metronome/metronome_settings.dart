/// Einstellungen des Metronoms (FEA-3), werden als JSON gespeichert. Nicht gespeichert werden das Tempo
/// (nach einem Neustart gilt 120 BPM) und «läuft» (nach einem Neustart ist das Metronom gestoppt).
class MetronomeSettings {
  const MetronomeSettings({
    this.bpm = 120,
    this.meter = 4,
    this.subdivision = 1,
    this.volume = 0.7,
    this.rampEnabled = false,
    this.rampStart = 100,
    this.rampTarget = 150,
    this.rampStep = 5,
    this.rampEveryBars = 4,
  });

  static const minBpm = 20;
  static const maxBpm = 300;
  static const meters = [4, 3, 2, 6];
  static const rampSteps = [1, 2, 5, 10, 20];

  final int bpm;
  final int meter; // Schläge pro Takt; 6 = 6/8
  final int subdivision; // Klicks pro Schlag 1–4
  final double volume; // 0–1
  final bool rampEnabled;
  final int rampStart;
  final int rampTarget;
  final int rampStep;
  final int rampEveryBars;

  static int clampBpm(int bpm) => bpm.clamp(minBpm, maxBpm);

  static String meterLabel(int meter) => meter == 6 ? '6/8' : '$meter/4';

  MetronomeSettings copyWith({
    int? bpm,
    int? meter,
    int? subdivision,
    double? volume,
    bool? rampEnabled,
    int? rampStart,
    int? rampTarget,
    int? rampStep,
    int? rampEveryBars,
  }) => MetronomeSettings(
    bpm: clampBpm(bpm ?? this.bpm),
    meter: meters.contains(meter) ? meter! : this.meter,
    subdivision: (subdivision ?? this.subdivision).clamp(1, 4),
    volume: (volume ?? this.volume).clamp(0.0, 1.0),
    rampEnabled: rampEnabled ?? this.rampEnabled,
    rampStart: clampBpm(rampStart ?? this.rampStart),
    rampTarget: clampBpm(rampTarget ?? this.rampTarget),
    rampStep: rampSteps.contains(rampStep) ? rampStep! : this.rampStep,
    rampEveryBars: (rampEveryBars ?? this.rampEveryBars).clamp(1, 20),
  );

  Map<String, Object> toJson() => {
    'meter': meter,
    'subdivision': subdivision,
    'volume': volume,
    'rampEnabled': rampEnabled,
    'rampStart': rampStart,
    'rampTarget': rampTarget,
    'rampStep': rampStep,
    'rampEveryBars': rampEveryBars,
  };

  /// Liest gespeicherte Werte; fehlende oder ungültige Felder bekommen den Standardwert bzw. werden begrenzt.
  factory MetronomeSettings.fromJson(Object? json) {
    const d = MetronomeSettings();
    if (json is! Map) return d;
    int? i(String k) => json[k] is num ? (json[k] as num).round() : null;
    return d.copyWith(
      meter: i('meter'),
      subdivision: i('subdivision'),
      volume: json['volume'] is num ? (json['volume'] as num).toDouble() : null,
      rampEnabled: json['rampEnabled'] is bool
          ? json['rampEnabled'] as bool
          : null,
      rampStart: i('rampStart'),
      rampTarget: i('rampTarget'),
      rampStep: i('rampStep'),
      rampEveryBars: i('rampEveryBars'),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MetronomeSettings &&
      other.bpm == bpm &&
      other.toJson().toString() == toJson().toString();

  @override
  int get hashCode => Object.hash(bpm, toJson().toString());
}
