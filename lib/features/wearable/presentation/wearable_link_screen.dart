import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:spike_flutter_sdk/spike_flutter_sdk.dart' as spike;

import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../../core/wearable/health_connect_sync.dart';
import '../../health/presentation/health_screen.dart' show latestVitalsProvider;
import '../../home/application/home_providers.dart';
import '../../patients/application/patients_providers.dart';
import '../../../core/wearable/wearable_service.dart';

/// Pantalla de vinculación del wearable de un paciente.
///
/// Explica el vínculo con la salud del teléfono (Apple Salud / Health Connect)
/// y ofrece conectar proveedores de terceros (Garmin, Whoop, ...).
class WearableLinkScreen extends ConsumerStatefulWidget {
  const WearableLinkScreen({super.key, required this.patientId});

  final String patientId;

  @override
  ConsumerState<WearableLinkScreen> createState() => _WearableLinkScreenState();
}

class _WearableLinkScreenState extends ConsumerState<WearableLinkScreen> {
  bool _linking = false;
  bool _syncing = false;
  String? _syncInfo;

  /// Lee pulso y oxígeno de Health Connect (Android) y los envía al backend.
  Future<void> _syncHealthConnect() async {
    final hc = ref.read(healthConnectSyncProvider);
    setState(() {
      _syncing = true;
      _syncInfo = null;
    });
    try {
      if (!await hc.isAvailable()) {
        if (!mounted) return;
        showAppSnackBar(context,
            'Health Connect no está instalado o necesita actualizarse.',
            error: true);
        await hc.installHealthConnect();
        return;
      }
      if (!await hc.requestPermissions()) {
        if (!mounted) return;
        showAppSnackBar(
            context, 'Sin permiso para leer el pulso en Health Connect.',
            error: true);
        return;
      }
      final r = await hc.sync(widget.patientId);
      await hc.rememberPatient(widget.patientId);
      // Las pantallas de Inicio y Salud guardan los datos ya cargados: se recargan
      // para que muestren las lecturas recién enviadas.
      ref.invalidate(todaySummaryProvider);
      ref.invalidate(selectedPatientDetailProvider);
      ref.invalidate(latestVitalsProvider);
      if (!mounted) return;
      setState(() => _syncInfo = r.read == 0
          ? 'No hay lecturas de las últimas 24 horas en Health Connect. '
              'Revisa que la app de tu reloj (o la app puente) esté copiando el pulso.'
          : '${r.read} lecturas encontradas, ${r.accepted} nuevas enviadas a AgeCare.');
    } on ApiException catch (e) {
      if (!mounted) return;
      showAppSnackBar(context, e.message, error: true);
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(context, 'No se pudo leer Health Connect: $e',
          error: true);
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  spike.Provider? _connectingProvider;

  Future<void> _linkPhoneHealth() async {
    setState(() => _linking = true);
    try {
      await ref.read(wearableServiceProvider).linkPatient(widget.patientId);
      if (!mounted) return;
      showAppSnackBar(context, 'Wearable vinculado correctamente.');
      context.pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      showAppSnackBar(context, e.message, error: true);
    } catch (_) {
      if (!mounted) return;
      showAppSnackBar(context,
          'No se pudo vincular la salud del teléfono. Intenta de nuevo.',
          error: true);
    } finally {
      if (mounted) setState(() => _linking = false);
    }
  }

  Future<void> _connectProvider(spike.Provider provider) async {
    setState(() => _connectingProvider = provider);
    try {
      await ref
          .read(wearableServiceProvider)
          .connectProvider(widget.patientId, provider);
      if (!mounted) return;
      showAppSnackBar(context, 'Abriendo la conexión con ${provider.name}...');
    } on ApiException catch (e) {
      if (!mounted) return;
      showAppSnackBar(context, e.message, error: true);
    } catch (_) {
      if (!mounted) return;
      showAppSnackBar(
          context, 'No se pudo conectar el proveedor. Intenta de nuevo.',
          error: true);
    } finally {
      if (mounted) setState(() => _connectingProvider = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    const providers = spike.Provider.values;
    return Scaffold(
      appBar: AppBar(title: const Text('Vincular wearable')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Health Connect directo (Android): no requiere Spike.
          if (ref.read(healthConnectSyncProvider).isSupported) ...[
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.monitor_heart_rounded,
                          color: AppColors.primary),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text('Health Connect',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Envía a AgeCare el pulso y el oxígeno de las últimas 24 horas que '
                    'tu reloj guardó en Health Connect.',
                    style: TextStyle(
                        color: AppColors.textSecondary,
                        height: 1.4,
                        fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _syncing ? null : _syncHealthConnect,
                    icon: _syncing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.sync_rounded),
                    label: Text(
                        _syncing ? 'Sincronizando...' : 'Sincronizar ahora'),
                  ),
                  if (_syncInfo != null) ...[
                    const SizedBox(height: 12),
                    Text(_syncInfo!,
                        style: const TextStyle(fontSize: 14, height: 1.4)),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
          // Spike (proveedores y salud del teléfono): solo si la app se compiló con SPIKE_APP_ID.
          if (AppConfig.spikeAppId != 0) ...[
            // Explicación del vínculo.
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.favorite_rounded, color: AppColors.primary),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text('Salud del teléfono',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Conecta la app con Apple Salud (iPhone) o Health Connect (Android) '
                    'para seguir el ritmo cardíaco, la actividad y el sueño de tu familiar. '
                    'Solo se leen los datos de salud necesarios y puedes revocar el acceso '
                    'cuando quieras desde los ajustes del teléfono.',
                    style: TextStyle(
                        color: AppColors.textSecondary,
                        height: 1.4,
                        fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _linking ? null : _linkPhoneHealth,
                    icon: _linking
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.health_and_safety_rounded),
                    label: Text(_linking
                        ? 'Conectando...'
                        : 'Conectar salud del teléfono'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Proveedores de terceros.
            const Padding(
              padding: EdgeInsets.only(left: 4, bottom: 8),
              child: Text('Proveedores',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            const Padding(
              padding: EdgeInsets.only(left: 4, bottom: 12),
              child: Text(
                'Conecta una cuenta de proveedor si tu familiar usa una pulsera o '
                'reloj compatible.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ),
            ...providers.map((p) {
              final busy = _connectingProvider == p;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: AppCard(
                  onTap: busy ? null : () => _connectProvider(p),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      const Icon(Icons.watch_rounded, color: AppColors.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(_prettyName(p.name),
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 15)),
                      ),
                      if (busy)
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        const Icon(Icons.chevron_right_rounded,
                            color: AppColors.textSecondary),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 16),

            // Nota de sincronización y accesibilidad.
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: .06),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded,
                      size: 20, color: AppColors.primary),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'La sincronización ocurre en segundo plano: los datos se '
                      'actualizan solos a lo largo del día, sin que tengas que abrir '
                      'la app. Los botones y textos están pensados para ser grandes y '
                      'legibles; puedes ampliar el tamaño del texto desde los ajustes '
                      'del teléfono.',
                      style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                          height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Nombre legible del proveedor (capitaliza el enum del SDK).
  String _prettyName(String raw) {
    if (raw.isEmpty) return raw;
    return raw[0].toUpperCase() + raw.substring(1);
  }
}
