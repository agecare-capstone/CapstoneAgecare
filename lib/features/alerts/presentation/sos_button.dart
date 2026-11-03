import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../patients/application/patients_providers.dart';
import '../application/alerts_providers.dart';
import '../data/alerts_repository.dart';

/// Botón SOS autocontenido, reutilizable en Inicio y en la vista del adulto
/// mayor. Confirma, intenta obtener ubicación (best-effort) y envía la alerta.
class SosButton extends ConsumerStatefulWidget {
  const SosButton({super.key});

  @override
  ConsumerState<SosButton> createState() => _SosButtonState();
}

class _SosButtonState extends ConsumerState<SosButton> {
  bool _sending = false;

  Future<void> _onPressed() async {
    final patient = ref.read(selectedPatientProvider);
    if (patient == null) {
      showAppSnackBar(
        context,
        'Selecciona un paciente antes de enviar un SOS.',
        error: true,
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => SosCountdownDialog(patientName: patient.fullName),
    );

    if (confirmed != true) return;

    setState(() => _sending = true);
    try {
      final pos = await _tryGetLocation();
      await ref.read(alertsRepositoryProvider).sendSos(
            patient.patientId,
            lat: pos?.latitude,
            lng: pos?.longitude,
          );
      ref.invalidate(activeAlertsProvider);
      if (!mounted) return;
      showAppSnackBar(
        context,
        pos != null
            ? 'SOS enviado con la ubicación actual.'
            : 'SOS enviado (sin ubicación).',
      );
    } on ApiException catch (e) {
      if (mounted) showAppSnackBar(context, e.message, error: true);
    } catch (_) {
      if (mounted) {
        showAppSnackBar(context, 'No se pudo enviar el SOS.', error: true);
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// Intenta obtener la ubicación; ante cualquier problema devuelve null para
  /// que el SOS se envíe igualmente sin coordenadas.
  Future<Position?> _tryGetLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }

      return await Geolocator.getCurrentPosition()
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      heroTag: null,
      onPressed: _sending ? null : _onPressed,
      backgroundColor: AppColors.critical,
      foregroundColor: Colors.white,
      icon: _sending
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            )
          : const Icon(Icons.sos_rounded),
      label: Text(_sending ? 'Enviando...' : 'SOS'),
    );
  }
}

/// Confirmación anti-toque accidental (AGE-506): cuenta 3 segundos y envía
/// el SOS sola, salvo que se cancele. "Enviar ahora" lo manda sin esperar,
/// así el SOS nunca necesita más de 2 toques.
///
/// Devuelve true si hay que enviar el SOS y false (o null, si se cierra
/// tocando fuera) si se canceló.
class SosCountdownDialog extends StatefulWidget {
  const SosCountdownDialog({super.key, required this.patientName});

  final String patientName;

  static const seconds = 3;

  @override
  State<SosCountdownDialog> createState() => _SosCountdownDialogState();
}

class _SosCountdownDialogState extends State<SosCountdownDialog> {
  int _remaining = SosCountdownDialog.seconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_remaining <= 1) {
        _close(true);
      } else {
        setState(() => _remaining--);
      }
    });
  }

  void _close(bool send) {
    _timer?.cancel();
    if (mounted) Navigator.of(context).pop(send);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.sos_rounded, color: AppColors.critical, size: 40),
      title: Text('Enviando SOS en $_remaining...'),
      content: Text(
        'Se notificará de inmediato a la red de cuidado de ${widget.patientName}. '
        'Si fue un toque accidental, presiona Cancelar.',
      ),
      actions: [
        TextButton(
          onPressed: () => _close(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.critical),
          onPressed: () => _close(true),
          child: const Text('Enviar ahora'),
        ),
      ],
    );
  }
}
