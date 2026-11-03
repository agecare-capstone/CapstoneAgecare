import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/app_config.dart';
import 'core/notifications/push_service.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

/// Ruta a la que lleva el toque en una notificación, o null si no aplica.
/// Una alerta (p. ej. caída, AGE-505) abre su pantalla de acción inmediata.
String? routeForNotification(Map<String, dynamic> data) {
  final alertId = data['alert_id'];
  if (alertId is String && alertId.isNotEmpty) return '/alerts/$alertId';
  final doseId = data['dose_id'];
  if (doseId is String && doseId.isNotEmpty) return '/dose/$doseId';
  return null;
}

/// Widget raíz de la aplicación.
class AgeCareApp extends ConsumerStatefulWidget {
  const AgeCareApp({super.key});

  @override
  ConsumerState<AgeCareApp> createState() => _AgeCareAppState();
}

class _AgeCareAppState extends ConsumerState<AgeCareApp> {
  StreamSubscription<Map<String, dynamic>>? _taps;

  @override
  void initState() {
    super.initState();
    _taps = PushService.instance.onNotificationTap.listen(_open);
    // La app se abrió desde una notificación estando cerrada.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final initial = PushService.instance.takeInitialTap();
      if (initial != null) _open(initial);
    });
  }

  void _open(Map<String, dynamic> data) {
    final route = routeForNotification(data);
    if (route != null) ref.read(goRouterProvider).push(route);
  }

  @override
  void dispose() {
    _taps?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(goRouterProvider);

    return MaterialApp.router(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      routerConfig: router,
      locale: const Locale('es'),
      supportedLocales: const [Locale('es'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}
