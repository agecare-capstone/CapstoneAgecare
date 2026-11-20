import 'dart:async';

/// Repite una sincronización cada [interval] mientras la app está en primer
/// plano (pedido del equipo: ver el pulso del reloj casi en vivo).
///
/// No corre en segundo plano: Android no permite tareas cada pocos segundos
/// sin un servicio con notificación fija, que gasta mucha batería.
/// Si una vuelta todavía no termina, la siguiente se salta (no se apilan).
class LiveSync {
  LiveSync({required this.onTick, this.interval = defaultInterval});

  static const defaultInterval = Duration(seconds: 10);

  final Future<void> Function() onTick;
  final Duration interval;

  Timer? _timer;
  bool _busy = false;

  bool get isRunning => _timer != null;

  void start() {
    if (_timer != null) return;
    _timer = Timer.periodic(interval, (_) => _run());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _run() async {
    if (_busy) return;
    _busy = true;
    try {
      await onTick();
    } catch (_) {
      // Un fallo de red no detiene las siguientes vueltas.
    } finally {
      _busy = false;
    }
  }
}
