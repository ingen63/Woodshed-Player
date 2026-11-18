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
  });

  static const minSpeed = 0.1;
  static const maxSpeed = 2.0;
  static const speedStep = 0.05;

  final bool speedEnabled;

  /// 0,1–2,0, Tonhöhe bleibt gleich.
  final double speed;
  final bool loopEnabled;
  final double loopStart;
  final double loopEnd;

  double get effectiveRate => speedEnabled ? speed : 1.0;

  PlaybackSettings copyWith({
    bool? speedEnabled,
    double? speed,
    bool? loopEnabled,
    double? loopStart,
    double? loopEnd,
  }) => PlaybackSettings(
    speedEnabled: speedEnabled ?? this.speedEnabled,
    speed: speed ?? this.speed,
    loopEnabled: loopEnabled ?? this.loopEnabled,
    loopStart: loopStart ?? this.loopStart,
    loopEnd: loopEnd ?? this.loopEnd,
  );

  /// Liest auch unvollständige Einträge (fehlende Schlüssel = Standardwert).
  factory PlaybackSettings.fromJson(Map<String, Object?> json) =>
      PlaybackSettings(
        speedEnabled: json['speedEnabled'] as bool? ?? false,
        speed: (json['speed'] as num?)?.toDouble() ?? 1.0,
        loopEnabled: json['loopEnabled'] as bool? ?? false,
        loopStart: (json['loopStart'] as num?)?.toDouble() ?? 0,
        loopEnd: (json['loopEnd'] as num?)?.toDouble() ?? 0,
      );

  Map<String, Object?> toJson() => {
    'loopEnabled': loopEnabled,
    'loopEnd': loopEnd,
    'loopStart': loopStart,
    'speed': speed,
    'speedEnabled': speedEnabled,
  };

  @override
  bool operator ==(Object other) =>
      other is PlaybackSettings &&
      other.speedEnabled == speedEnabled &&
      other.speed == speed &&
      other.loopEnabled == loopEnabled &&
      other.loopStart == loopStart &&
      other.loopEnd == loopEnd;

  @override
  int get hashCode =>
      Object.hash(speedEnabled, speed, loopEnabled, loopStart, loopEnd);

  @override
  String toString() =>
      'PlaybackSettings(speed: $speedEnabled/$speed, loop: $loopEnabled/$loopStart–$loopEnd)';
}
