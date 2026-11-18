// Wiedergabe-Einstellungen pro Datei, wie `PlaybackSettings` der Swift-App (Track.swift).
// JSON-Schlüssel gleich wie dort, damit library.json austauschbar bleibt.

/// Tempo und Loop eines Titels. `loopEnd == 0` heisst «noch nicht gesetzt».
class PlaybackSettings {
  const PlaybackSettings({
    this.speedEnabled = false,
    this.speed = 1.0,
    this.loopEnabled = false,
    this.loopStart = 0,
    this.loopEnd = 0,
    this.rampEnabled = false,
    this.rampStart = 60,
    this.rampTarget = 100,
    this.rampStep = 5,
    this.rampPasses = 10,
  });

  static const minSpeed = 0.1;
  static const maxSpeed = 2.0;
  static const speedStep = 0.05;

  /// Steigerung nach Loop-Durchgängen (#29): Stufen in ganzen Prozent.
  static const minRampPercent = 10;
  static const maxRampPercent = 200;
  static const rampSteps = [1, 2, 5, 10, 20];
  static const maxRampPasses = 100;

  final bool speedEnabled;

  /// 0,1–2,0, Tonhöhe bleibt gleich.
  final double speed;
  final bool loopEnabled;
  final double loopStart;
  final double loopEnd;

  /// Steigerung nach Loop-Durchgängen (#29): von [rampStart] % in Schritten von [rampStep] % bis
  /// [rampTarget] %, je eine Stufe nach [rampPasses] Durchgängen.
  final bool rampEnabled;
  final int rampStart;
  final int rampTarget;
  final int rampStep;
  final int rampPasses;

  double get effectiveRate => speedEnabled ? speed : 1.0;

  /// Die aktuelle Geschwindigkeit in ganzen Prozent.
  int get speedPercent => (speed * 100).round();

  static int clampRampPercent(int p) => p.clamp(minRampPercent, maxRampPercent);

  PlaybackSettings copyWith({
    bool? speedEnabled,
    double? speed,
    bool? loopEnabled,
    double? loopStart,
    double? loopEnd,
    bool? rampEnabled,
    int? rampStart,
    int? rampTarget,
    int? rampStep,
    int? rampPasses,
  }) => PlaybackSettings(
    speedEnabled: speedEnabled ?? this.speedEnabled,
    speed: speed ?? this.speed,
    loopEnabled: loopEnabled ?? this.loopEnabled,
    loopStart: loopStart ?? this.loopStart,
    loopEnd: loopEnd ?? this.loopEnd,
    rampEnabled: rampEnabled ?? this.rampEnabled,
    rampStart: clampRampPercent(rampStart ?? this.rampStart),
    rampTarget: clampRampPercent(rampTarget ?? this.rampTarget),
    rampStep: rampSteps.contains(rampStep) ? rampStep! : this.rampStep,
    rampPasses: (rampPasses ?? this.rampPasses).clamp(1, maxRampPasses),
  );

  /// Liest auch unvollständige Einträge (fehlende Schlüssel = Standardwert).
  factory PlaybackSettings.fromJson(Map<String, Object?> json) {
    int? i(String k) => json[k] is num ? (json[k] as num).round() : null;
    return PlaybackSettings(
      speedEnabled: json['speedEnabled'] as bool? ?? false,
      speed: (json['speed'] as num?)?.toDouble() ?? 1.0,
      loopEnabled: json['loopEnabled'] as bool? ?? false,
      loopStart: (json['loopStart'] as num?)?.toDouble() ?? 0,
      loopEnd: (json['loopEnd'] as num?)?.toDouble() ?? 0,
    ).copyWith(
      rampEnabled: json['rampEnabled'] is bool
          ? json['rampEnabled'] as bool
          : null,
      rampStart: i('rampStart'),
      rampTarget: i('rampTarget'),
      rampStep: i('rampStep'),
      rampPasses: i('rampPasses'),
    );
  }

  /// Die Schlüssel der Steigerung (#29) stehen nur in der Datei, wenn sie vom Standard abweichen; sonst
  /// bleibt library.json gleich wie bisher.
  Map<String, Object?> toJson() {
    const d = PlaybackSettings();
    return {
      'loopEnabled': loopEnabled,
      'loopEnd': loopEnd,
      'loopStart': loopStart,
      if (rampEnabled != d.rampEnabled) 'rampEnabled': rampEnabled,
      if (rampPasses != d.rampPasses) 'rampPasses': rampPasses,
      if (rampStart != d.rampStart) 'rampStart': rampStart,
      if (rampStep != d.rampStep) 'rampStep': rampStep,
      if (rampTarget != d.rampTarget) 'rampTarget': rampTarget,
      'speed': speed,
      'speedEnabled': speedEnabled,
    };
  }

  @override
  bool operator ==(Object other) =>
      other is PlaybackSettings &&
      other.speedEnabled == speedEnabled &&
      other.speed == speed &&
      other.loopEnabled == loopEnabled &&
      other.loopStart == loopStart &&
      other.loopEnd == loopEnd &&
      other.rampEnabled == rampEnabled &&
      other.rampStart == rampStart &&
      other.rampTarget == rampTarget &&
      other.rampStep == rampStep &&
      other.rampPasses == rampPasses;

  @override
  int get hashCode => Object.hash(
    speedEnabled,
    speed,
    loopEnabled,
    loopStart,
    loopEnd,
    rampEnabled,
    rampStart,
    rampTarget,
    rampStep,
    rampPasses,
  );

  @override
  String toString() =>
      'PlaybackSettings(speed: $speedEnabled/$speed, loop: $loopEnabled/$loopStart–$loopEnd, '
      'ramp: $rampEnabled/$rampStart–$rampTarget +$rampStep/$rampPasses)';
}
