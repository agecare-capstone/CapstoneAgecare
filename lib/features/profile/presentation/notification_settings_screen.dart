import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/notifications/push_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../application/profile_providers.dart';
import '../data/profile_repository.dart';
import '../domain/models.dart';

/// Preferencias de notificaciones: un switch por preferencia, con guardado
/// inmediato (PUT) y estado del token push del dispositivo.
class NotificationSettingsScreen extends ConsumerStatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  ConsumerState<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends ConsumerState<NotificationSettingsScreen> {
  NotificationSettings? _settings;
  bool _saving = false;

  Future<void> _update(NotificationSettings next) async {
    final previous = _settings;
    setState(() {
      _settings = next;
      _saving = true;
    });
    try {
      await ref
          .read(profileRepositoryProvider)
          .updateNotificationSettings(next);
    } catch (e) {
      // Revertir en caso de error.
      setState(() => _settings = previous);
      if (mounted) showAppSnackBar(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(notificationSettingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Notificaciones')),
      body: async.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
          message: e.toString(),
          onRetry: () => ref.invalidate(notificationSettingsProvider),
        ),
        data: (loaded) {
          final s = _settings ??= loaded;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    // AGE-507: SOS y caídas llegan siempre; no se pueden apagar.
                    const _SwitchTile(
                      title: 'Alertas críticas (SOS y caídas)',
                      subtitle: 'Siempre activas por seguridad del paciente.',
                      value: true,
                      onChanged: null,
                      locked: true,
                    ),
                    const Divider(height: 1),
                    _SwitchTile(
                      title: 'Alertas por push',
                      subtitle: 'Recibe alertas de salud y SOS en el teléfono.',
                      value: s.alertsPush,
                      onChanged: _saving
                          ? null
                          : (v) => _update(s.copyWith(alertsPush: v)),
                    ),
                    const Divider(height: 1),
                    _SwitchTile(
                      title: 'Alertas por correo',
                      subtitle: 'Recibe un correo cuando haya una alerta.',
                      value: s.alertsEmail,
                      onChanged: _saving
                          ? null
                          : (v) => _update(s.copyWith(alertsEmail: v)),
                    ),
                    const Divider(height: 1),
                    _SwitchTile(
                      title: 'Recordatorios de medicación',
                      subtitle: 'Avisos a la hora de cada toma.',
                      value: s.medicationReminders,
                      onChanged: _saving
                          ? null
                          : (v) =>
                              _update(s.copyWith(medicationReminders: v)),
                    ),
                    const Divider(height: 1),
                    _SwitchTile(
                      title: 'Mensajes del chat',
                      subtitle: 'Notificaciones de mensajes nuevos.',
                      value: s.chatPush,
                      onChanged: _saving
                          ? null
                          : (v) => _update(s.copyWith(chatPush: v)),
                    ),
                    const Divider(height: 1),
                    _SwitchTile(
                      title: 'Resumen diario',
                      subtitle: 'Un resumen del día del paciente.',
                      value: s.digestDaily,
                      onChanged: _saving
                          ? null
                          : (v) => _update(s.copyWith(digestDaily: v)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              AppCard(
                padding: EdgeInsets.zero,
                child: ListTile(
                  leading: const Icon(Icons.tune_rounded,
                      color: AppColors.primary),
                  title: const Text('Umbrales de alerta',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text(
                      'Define desde qué valores de pulso, oxígeno y '
                      'temperatura se genera una alerta.',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textSecondary)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/settings/thresholds'),
                ),
              ),
              const SizedBox(height: 20),
              const _PushTokenCard(),
            ],
          );
        },
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  const _SwitchTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.locked = false,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  /// Muestra un candado: la preferencia no se puede cambiar.
  final bool locked;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      secondary: locked
          ? const Icon(Icons.lock_rounded, color: AppColors.critical)
          : null,
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle,
          style: const TextStyle(
              fontSize: 12, color: AppColors.textSecondary)),
      value: value,
      activeThumbColor: AppColors.primary,
      onChanged: onChanged,
    );
  }
}

class _PushTokenCard extends StatelessWidget {
  const _PushTokenCard();

  @override
  Widget build(BuildContext context) {
    final token = PushService.instance.fcmToken;
    final platform = kIsWeb
        ? 'Navegador'
        : defaultTargetPlatform == TargetPlatform.iOS
            ? 'iOS'
            : defaultTargetPlatform == TargetPlatform.android
                ? 'Android'
                : 'Este dispositivo';
    final registered = token != null && token.isNotEmpty;
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            registered
                ? Icons.cloud_done_rounded
                : Icons.cloud_off_rounded,
            color: registered ? AppColors.statusOk : AppColors.textSecondary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Notificaciones push ($platform)',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                  registered
                      ? 'Dispositivo registrado para recibir push.'
                      : 'Sin token de push. Las notificaciones remotas '
                          'podrían no llegar en este dispositivo.',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                ),
                if (registered) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Token: ${token.substring(0, token.length.clamp(0, 18))}…',
                    style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                        fontFamily: 'monospace'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
