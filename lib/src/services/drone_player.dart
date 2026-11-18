import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'drone_service.dart';

/// Reads an asset out of the bundle. Injectable so unit tests never need a
/// running engine; the default is Flutter's own [rootBundle].
typedef AssetReader = Future<Uint8List> Function(String assetPath);

Future<Uint8List> _rootBundleRead(String assetPath) async {
  final data = await rootBundle.load(assetPath);
  return data.buffer.asUint8List();
}

/// Media Foundation on Windows, AVAudioPlayer on macOS.
///
/// Both loop natively, which matters more here than it sounds: the drone assets
/// were synthesised as exact periods, so the sample the engine loops back to is
/// already mid-rotation of the previous pluck's tail. An engine loop is
/// inaudible; a re-seek every eight seconds would throb like a wobble.
class AudioplayersDrone implements DronePlayer {
  AudioplayersDrone({AudioPlayer? player, AssetReader? reader})
    : _provided = player,
      _read = reader ?? _rootBundleRead;

  /// Not touched until the drone is actually asked to play, so an app that
  /// never enables the drone never talks to the audio plugin at all.
  final AudioPlayer? _provided;
  final Future<Uint8List> Function(String assetPath) _read;

  AudioPlayer? _playerInstance;
  String? _loadedAsset;

  AudioPlayer get _player => _playerInstance ??= _provided ?? AudioPlayer();

  @override
  Future<void> playLoop(String assetPath, double volume) async {
    // Set every time rather than once in the constructor: AudioPlayer's only
    // constructor argument is playerId, and a shared player may have had its
    // release mode changed by something else.
    await _player.setReleaseMode(ReleaseMode.loop);
    if (_loadedAsset != assetPath) {
      _loadedAsset = assetPath;
      // Read on every pitch change rather than caching all six: retuning is a
      // rare click, the bundle read is milliseconds, and a cache keyed by
      // nothing would be one stale-buffer bug away from playing the wrong Sa.
      final bytes = await _read(assetPath);
      // BytesSource rather than AssetSource. AssetSource takes a path relative
      // to its own 'assets/' prefix, and on desktop it works around that by
      // writing a copy into a temp folder for the native side to reopen. Feeding
      // it a full Flutter asset key asks for assets/assets/audio/... and throws;
      // handing over decoded bytes skips the prefix trap and the temp hop.
      await _player.setSource(BytesSource(bytes, mimeType: 'audio/wav'));
    }
    await _player.setVolume(volume);
    await _player.resume();
  }

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  @override
  Future<void> stop() async {
    // Nothing was ever loaded, so there is nothing to stop — and this keeps a
    // stop on an unused drone from instantiating the plugin.
    final player = _playerInstance ?? _provided;
    if (player == null) return;
    await player.stop();
    // `stop` releases the loaded source in some backends, so forget which asset
    // is hot and let the next play call re-arm.
    _loadedAsset = null;
  }

  @override
  Future<void> dispose() async {
    _loadedAsset = null;
    final player = _playerInstance ?? _provided;
    _playerInstance = null;
    await player?.dispose();
  }
}
