import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

/// Ruta a la que lleva el toque en una notificación, o null si no aplica.
/// Una alerta (p. ej. caída, AGE-505) abre su pantalla de acción inmediata.
String? routeForNotification(Map<String, dynamic> data) {
  final alertId = data['alert_id'];
  if (alertId is String && alertId.isNotEmpty) return '/alerts/$alertId';
  final doseId = data['dose_id'];
  if (doseId is String && doseId.isNotEmpty) return '/dose/$doseId';
  // Push de alerta sin id (p. ej. CRITICAL_FALL mal formado): al menos se
  // abre el centro de alertas en vez de no hacer nada.
  final type = data['type']?.toString().toLowerCase() ?? '';
  if (type == 'alert' || type.contains('fall')) return '/alerts';
  return null;
}

/// Rutas de entrada: mientras el router esté en una de estas todavía no hay
/// sesión lista ni pantalla principal sobre la que abrir la alerta.
const notificationEntryRoutes = {'/splash', '/login', '/register', '/recover'};

/// Abre la pantalla de una notificación tocada, también cuando el toque
/// abrió la app desde cerrada (AGE-505 / DAC05-86).
///
/// Con la app cerrada, el toque llega antes de que termine de restaurarse la
/// sesión. Si se hiciera `push` en ese momento, el redirect del router lo
/// mandaría a /splash o /login y la alerta se perdería. Por eso la ruta queda
/// pendiente hasta que haya sesión y luego se apila sobre /home, para que
/// "Atrás" vuelva a la app y no al splash.
class NotificationNavigator {
  NotificationNavigator({required this.router, required this.isLoggedIn});

  final GoRouter Function() router;
  final bool Function() isLoggedIn;

  String? _pending;

  /// Ruta esperando a que haya sesión (visible para tests).
  @visibleForTesting
  String? get pendingRoute => _pending;

  /// Registra el toque de una notificación e intenta abrirla.
  void open(Map<String, dynamic> data) {
    final route = routeForNotification(data);
    if (route == null) return;
    _pending = route;
    flush();
  }

  /// Abre la ruta pendiente si ya hay sesión. Llamar de nuevo cuando el
  /// usuario inicie sesión.
  void flush() {
    final route = _pending;
    if (route == null || !isLoggedIn()) return;
    _pending = null;

    final r = router();
    final delegate = r.routerDelegate;
    bool onEntry() =>
        notificationEntryRoutes.contains(delegate.currentConfiguration.uri.path);

    if (!onEntry()) {
      r.push(route);
      return;
    }

    // Todavía en splash/login: esperar a que el router llegue a /home.
    late final VoidCallback listener;
    listener = () {
      if (onEntry()) return;
      delegate.removeListener(listener);
      scheduleMicrotask(() => r.push(route));
    };
    delegate.addListener(listener);
    r.go('/home');
  }
}
