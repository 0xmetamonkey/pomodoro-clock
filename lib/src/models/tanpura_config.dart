/// Tanpura drone settings. Pure data, JSON-serialisable for persistence.
library;

/// When the drone should be audible.
enum DroneMode {
  /// Never plays.
  off,

  /// Plays only while a focus block is running — stops with pauses and breaks.
  followFocus,

  /// Plays continuously, independent of the timer. This is the "just give me a
  /// tanpura" mode.
  standalone,
}

extension DroneModeLabel on DroneMode {
  String get label => switch (this) {
    DroneMode.off => 'Off',
    DroneMode.followFocus => 'With focus',
    DroneMode.standalone => 'Always',
  };

  String get hint => switch (this) {
    DroneMode.off => 'No drone',
    DroneMode.followFocus => 'Runs while a focus block runs',
    DroneMode.standalone => 'Runs regardless of the timer',
  };
}

/// The tonic the drone is tuned to, named by Western key out of habit; in
/// practice this is the Sa a singer tunes to.
enum DronePitch {
  c('C', 130.81),
  d('D', 146.83),
  e('E', 164.81),
  f('F', 174.61),
  g('G', 196.00),
  a('A', 220.00);

  const DronePitch(this.label, this.hertz);

  /// Display name, also the asset suffix.
  final String label;
  final double hertz;

  String get assetPath => 'assets/audio/tanpura_${name.toLowerCase()}.wav';

  static DronePitch fromName(String? value) => DronePitch.values.firstWhere(
    (p) => p.name == value,
    orElse: () => DronePitch.c,
  );
}

class DroneConfig {
  const DroneConfig({
    this.mode = DroneMode.off,
    this.pitch = DronePitch.c,
    this.volume = 0.6,
  });

  final DroneMode mode;
  final DronePitch pitch;
  final double volume;

  /// Kept well above zero so "playing" is actually audible, and below unity so
  /// the phase-end alert can still cut through.
  static const double minVolume = 0.1;
  static const double maxVolume = 1.0;

  bool get enabled => mode != DroneMode.off;

  double get clampedVolume => volume.clamp(minVolume, maxVolume);

  DroneConfig copyWith({DroneMode? mode, DronePitch? pitch, double? volume}) {
    return DroneConfig(
      mode: mode ?? this.mode,
      pitch: pitch ?? this.pitch,
      volume: volume ?? this.volume,
    );
  }

  Map<String, dynamic> toJson() => {
    'mode': mode.name,
    'pitch': pitch.name,
    'volume': clampedVolume,
  };

  factory DroneConfig.fromJson(Map<String, dynamic> json) {
    final volume = json['volume'];
    return DroneConfig(
      mode: DroneMode.values.firstWhere(
        (m) => m.name == json['mode'],
        orElse: () => DroneMode.off,
      ),
      pitch: DronePitch.fromName(json['pitch'] as String?),
      // Anything non-numeric (or NaN, which would silence the drone forever)
      // falls back rather than throwing on load.
      volume: volume is num && volume.isFinite ? volume.toDouble() : 0.6,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DroneConfig &&
      other.mode == mode &&
      other.pitch == pitch &&
      other.clampedVolume == clampedVolume;

  @override
  int get hashCode => Object.hash(mode, pitch, clampedVolume);
}
