import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/app_config.dart';
import 'core/notifications/notification_navigator.dart';
import 'core/notifications/push_service.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/application/auth_controller.dart';
import 'features/profile/data/profile_repository.dart';

export 'core/notifications/notification_navigator.dart' show routeForNotification;

/// Widget raíz de la aplicación.
class AgeCareApp extends ConsumerStatefulWidget {
  const AgeCareApp({super.key});

  @override
  ConsumerState<AgeCareApp> createState() => _AgeCareAppState();
}

class _AgeCareAppState extends ConsumerState<AgeCareApp> {
  StreamSubscription<Map<String, dynamic>>? _taps;
  late final NotificationNavigator _notifications = NotificationNavigator(
    router: () => ref.read(goRouterProvider),
    isLoggedIn: () => ref.read(authControllerProvider) is Authenticated,
  );

  @override
  void initState() {
    super.initState();
    _taps = PushService.instance.onNotificationTap.listen(_notifications.open);
    // La app se abrió desde una notificación estando cerrada.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final initial = PushService.instance.takeInitialTap();
      if (initial != null) _notifications.open(initial);
    });
  }

  /// Envía el token FCM al backend para que pueda mandarle push a este
  /// usuario (caídas, SOS) aunque la app esté cerrada (DAC05-193).
  Future<void> _registerPushToken() async {
    final token = PushService.instance.fcmToken;
    if (token == null || kIsWeb) return;
    final platform =
        defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';
    try {
      PushService.instance.deviceId = await ref
          .read(profileRepositoryProvider)
          .registerDevice(token, platform);
    } catch (_) {
      // Sin red o backend caído: se reintenta en el próximo inicio de sesión.
    }
  }

  @override
  void dispose() {
    _taps?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(goRouterProvider);
    ref.listen<AuthState>(authControllerProvider, (prev, next) {
      if (next is Authenticated && prev is! Authenticated) {
        _registerPushToken();
        _notifications.flush();
      }
    });

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
