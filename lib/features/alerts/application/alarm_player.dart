import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Alarma sonora de la pantalla de caída (AGE-505 / DAC05-84): suena en bucle
/// hasta que el familiar la silencia o atiende la alerta.
abstract class AlarmPlayer {
  Future<void> start();
  Future<void> stop();
}

class AudioAlarmPlayer implements AlarmPlayer {
  AudioPlayer? _player;

  @override
  Future<void> start() async {
    try {
      HapticFeedback.heavyImpact();
      final player = _player ??= AudioPlayer();
      // En Android usa el volumen de alarma, no el multimedia.
      await player.setAudioContext(AudioContext(
        android: const AudioContextAndroid(
          usageType: AndroidUsageType.alarm,
          contentType: AndroidContentType.sonification,
          audioFocus: AndroidAudioFocus.gainTransient,
          stayAwake: true,
        ),
      ));
      await player.setReleaseMode(ReleaseMode.loop);
      await player.play(AssetSource('sounds/alarma_caida.wav'));
    } catch (_) {
      // Sin audio (p. ej. navegador sin interacción previa): la pantalla roja
      // y la notificación siguen avisando.
    }
  }

  @override
  Future<void> stop() async {
    final player = _player;
    _player = null;
    if (player == null) return;
    try {
      await player.stop();
      await player.dispose();
    } catch (_) {}
  }
}

/// La pantalla de caída la detiene al silenciarla, al atender o al salir.
final alarmPlayerProvider = Provider<AlarmPlayer>((ref) {
  final player = AudioAlarmPlayer();
  ref.onDispose(player.stop);
  return player;
});
