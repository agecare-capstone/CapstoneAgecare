import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../network/api_client.dart';
import '../network/upload_service.dart';

/// Servicio de voz: grabación de notas, transcripción (STT) y lectura (TTS).
///
/// - STT: POST /stt  { audio_url } -> { text }   (Azure AI Speech en backend)
/// - TTS: POST /tts  { text, voice } -> { audio_url }
///
/// Pensado para la vista del adulto mayor (chat con voz) y notas de voz en el
/// chat familiar-cuidadora.
class SpeechService {
  SpeechService(this._api, this._uploads);

  final ApiClient _api;
  final UploadService _uploads;
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();

  String? _currentPath;

  Future<bool> get hasPermission => _recorder.hasPermission();

  /// Comienza a grabar una nota de voz en un archivo temporal.
  Future<void> startRecording() async {
    if (!await _recorder.hasPermission()) {
      throw StateError('Permiso de micrófono no concedido.');
    }
    final stamp = DateTime.now().millisecondsSinceEpoch;
    // En el navegador no hay carpeta temporal ni AAC: se graba WAV en memoria.
    if (kIsWeb) {
      _currentPath = 'voice_$stamp.wav';
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.wav),
        path: _currentPath!,
      );
      return;
    }
    final dir = await getTemporaryDirectory();
    _currentPath = '${dir.path}/voice_$stamp.m4a';
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc),
      path: _currentPath!,
    );
  }

  /// Detiene la grabación y devuelve el archivo resultante.
  Future<XFile?> stopRecording() async {
    final path = await _recorder.stop();
    if (path == null) return null;
    // En web, path es una URL blob: el nombre real viene de _currentPath.
    final name = (_currentPath ?? path).split('/').last;
    return XFile(path, name: name, mimeType: kIsWeb ? 'audio/wav' : null);
  }

  /// Sube el audio y devuelve su URL (para adjuntar a un mensaje).
  Future<String> uploadVoiceNote(XFile audio) async {
    final uploaded = await _uploads.uploadFile(audio, kind: 'audio');
    return uploaded.fileUrl;
  }

  /// Transcribe un audio ya subido (STT).
  Future<String> transcribe(String audioUrl) async {
    final res = await _api.post<Map<String, dynamic>>('/stt',
        data: {'audio_url': audioUrl});
    return (res['text'] ?? '') as String;
  }

  /// Graba, sube y transcribe en un solo paso.
  Future<({String text, String audioUrl})> recordAndTranscribe(XFile audio) async {
    final url = await uploadVoiceNote(audio);
    final text = await transcribe(url);
    return (text: text, audioUrl: url);
  }

  /// Convierte texto a voz y lo reproduce (TTS) — útil para el adulto mayor.
  Future<void> speak(String text, {String voice = 'es-MX-DaliaNeural'}) async {
    final res = await _api.post<Map<String, dynamic>>('/tts',
        data: {'text': text, 'voice': voice});
    final audioUrl = res['audio_url'] as String;
    await _player.play(UrlSource(audioUrl));
  }

  Future<void> playUrl(String url) => _player.play(UrlSource(url));
  Future<void> stopPlayback() => _player.stop();
  Future<void> pausePlayback() => _player.pause();
  Future<void> resumePlayback() => _player.resume();
  Stream<PlayerState> get playerStateStream => _player.onPlayerStateChanged;

  Future<void> dispose() async {
    await _recorder.dispose();
    await _player.dispose();
  }
}

final speechServiceProvider = Provider<SpeechService>((ref) {
  final s = SpeechService(
    ref.watch(apiClientProvider),
    ref.watch(uploadServiceProvider),
  );
  ref.onDispose(s.dispose);
  return s;
});
