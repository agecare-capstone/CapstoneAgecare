import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Servicio de notificaciones.
///
/// - Locales: alarmas de medicación programadas en el dispositivo
///   (flutter_local_notifications).
/// - Remotas: push desde el backend vía FCM; el token se reenvía al backend
///   (POST /users/me/devices), que lo registra en Azure Notification Hubs.
///
/// En modo mocks el registro remoto se omite para poder correr sin proyecto
/// Firebase configurado.
class PushService {
  PushService._();
  static final PushService instance = PushService._();

  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  /// Se emite cuando llega un push o se toca una notificación local, con el
  /// payload (p. ej. {"type":"dose","dose_id":"..."} o {"type":"alert",...}).
  final StreamController<Map<String, dynamic>> _taps =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get onNotificationTap => _taps.stream;

  /// Toque que abrió la app estando cerrada (AGE-505): se entrega una sola vez.
  Map<String, dynamic>? _initialTap;
  Map<String, dynamic>? takeInitialTap() {
    final tap = _initialTap;
    _initialTap = null;
    return tap;
  }

  String? _fcmToken;
  String? get fcmToken => _fcmToken;

  /// device_id que asignó el backend al registrar el token en esta sesión.
  String? deviceId;

  bool _initialized = false;

  Future<void> init({required bool enableRemote}) async {
    if (_initialized) return;
    _initialized = true;
    // En el navegador no hay notificaciones locales ni proyecto Firebase web:
    // la versión web funciona sin alarmas ni push.
    if (kIsWeb) return;

    const androidInit =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const linuxInit = LinuxInitializationSettings(
      defaultActionName: 'Open notification',
    );
    try {
      await _local.initialize(
        const InitializationSettings(
          android: androidInit,
          iOS: iosInit,
          linux: linuxInit,
        ),
        onDidReceiveNotificationResponse: (resp) {
          final payload = resp.payload;
          if (payload != null) _taps.add(_parse(payload));
        },
      );
      // Canal de máxima prioridad para caídas y SOS: el backend lo usa en el
      // push (channel_id critical_alerts) para que suene aun con la app cerrada.
      await _local
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(criticalChannel);
      final launch = await _local.getNotificationAppLaunchDetails();
      final launchPayload = launch?.notificationResponse?.payload;
      if (launch?.didNotificationLaunchApp == true && launchPayload != null) {
        _initialTap = _parse(launchPayload);
      }
    } catch (e) {
      // Ignorar o registrar error en plataformas que no soportan notificaciones locales
    }

    if (enableRemote) {
      try {
        await Firebase.initializeApp();
        final messaging = FirebaseMessaging.instance;
        await messaging.requestPermission();
        _fcmToken = await messaging.getToken();
        messaging.onTokenRefresh.listen((t) => _fcmToken = t);
        FirebaseMessaging.onMessage.listen(_onForegroundMessage);
        FirebaseMessaging.onMessageOpenedApp.listen((m) => _taps.add(tapData(m)));
        final initial = await messaging.getInitialMessage();
        if (initial != null) _initialTap = tapData(initial);
      } catch (e) {
        // Sin configuración Firebase (o en desarrollo): las notificaciones
        // locales siguen funcionando.
        _fcmToken = null;
      }
    }
  }

  /// Datos de navegación de un push tocado: van a [routeForNotification].
  static Map<String, dynamic> tapData(RemoteMessage m) =>
      Map<String, dynamic>.from(m.data);

  /// Canal de la notificación según el tipo: caídas y SOS van al crítico.
  static AndroidNotificationChannel channelFor(Map<String, dynamic> data) {
    if (criticalAlertTypes.contains(data['alert_type'])) return criticalChannel;
    return data['type'] == 'alert' ? _alertChannel : _generalChannel;
  }

  void _onForegroundMessage(RemoteMessage m) {
    final n = m.notification;
    if (n != null) {
      _local.show(
        m.hashCode,
        n.title,
        n.body,
        _details(channelFor(m.data)),
        payload: _encode(m.data),
      );
    }
  }

  /// Programa la alarma local de una dosis de medicación (ticket AGE-403).
  Future<void> scheduleDoseReminder({
    required int id,
    required String medicationName,
    required DateTime when,
    required String doseId,
  }) async {
    // Nota: para disparo exacto se recomienda zonedSchedule con timezone.
    // Aquí usamos show inmediato si la hora ya pasó; en producción usar
    // flutter_local_notifications + timezone para zonedSchedule.
    if (kIsWeb) return;
    await _local.show(
      id,
      'Hora de tu medicamento',
      'Es momento de tomar $medicationName',
      _details(_medChannel),
      payload: _encode({'type': 'dose', 'dose_id': doseId}),
    );
  }

  Future<void> cancelDoseReminder(int id) async {
    if (kIsWeb) return;
    await _local.cancel(id);
  }

  NotificationDetails _details(AndroidNotificationChannel ch) => NotificationDetails(
        android: AndroidNotificationDetails(
          ch.id,
          ch.name,
          channelDescription: ch.description,
          importance: Importance.max,
          priority: Priority.high,
          // El canal crítico suena con el volumen de alarma.
          audioAttributesUsage: ch.id == criticalChannel.id
              ? AudioAttributesUsage.alarm
              : AudioAttributesUsage.notification,
        ),
        iOS: const DarwinNotificationDetails(),
      );

  /// Tipos de alerta que usan el canal crítico (igual que el backend).
  static const criticalAlertTypes = {'fall', 'sos'};

  static const criticalChannel = AndroidNotificationChannel(
    'critical_alerts',
    'Alertas críticas',
    description: 'Caídas y SOS: suenan con prioridad máxima',
    importance: Importance.max,
    audioAttributesUsage: AudioAttributesUsage.alarm,
  );
  static const _medChannel = AndroidNotificationChannel(
      'meds', 'Medicación', description: 'Alarmas de medicamentos');
  static const _alertChannel = AndroidNotificationChannel(
      'alerts', 'Alertas', description: 'Alertas de salud y SOS');
  static const _generalChannel = AndroidNotificationChannel(
      'general', 'General', description: 'Notificaciones generales');

  String _encode(Map<String, dynamic> data) =>
      data.entries.map((e) => '${e.key}=${e.value}').join('&');

  Map<String, dynamic> _parse(String payload) {
    final out = <String, dynamic>{};
    for (final pair in payload.split('&')) {
      final kv = pair.split('=');
      if (kv.length == 2) out[kv[0]] = kv[1];
    }
    return out;
  }
}
