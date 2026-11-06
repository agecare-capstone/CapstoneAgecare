import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../../../../core/widgets/common.dart';
import '../../../application/home_providers.dart';
import '../../../domain/wellbeing.dart';

/// Semáforo de bienestar del paciente seleccionado (AGE-305 / DAC05-177):
/// verde, amarillo o rojo con el motivo destacado, más los estados de carga,
/// sin datos y error con reintento.
class WellbeingTrafficLight extends ConsumerWidget {
  const WellbeingTrafficLight({super.key});

  static const emptyText = 'Sin datos de signos vitales disponibles';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(wellbeingProvider).when(
          loading: () => AppCard(
            child: SizedBox(
              height: 96,
              child: Center(
                child: Semantics(
                  label: 'Cargando el semáforo de bienestar',
                  child: const CircularProgressIndicator(),
                ),
              ),
            ),
          ),
          error: (_, __) => AppCard(
            child: ErrorView(
              message: 'No se pudo cargar el semáforo de bienestar.',
              onRetry: () => ref.invalidate(wellbeingProvider),
            ),
          ),
          data: (wellbeing) {
            if (wellbeing == null) return const SizedBox.shrink();
            if (wellbeing.status == TrafficLight.noData) {
              return const _NoData();
            }
            return _Light(wellbeing: wellbeing);
          },
        );
  }
}

class _Light extends StatelessWidget {
  const _Light({required this.wellbeing});

  final Wellbeing wellbeing;

  @override
  Widget build(BuildContext context) {
    final status = wellbeing.status;
    final reason = wellbeing.topReason;
    return Semantics(
      container: true,
      label: 'Semáforo de bienestar: ${status.label}. '
          '${reason ?? wellbeing.summary}',
      child: ExcludeSemantics(
        child: AppCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Lamps(active: status),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Semáforo de bienestar',
                        style: TextStyle(
                            fontSize: 13, color: AppColors.textSecondary)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(status.icon, color: status.color, size: 26),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(status.label,
                              style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.textPrimary)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (reason != null)
                      // Motivo destacado: fondo del color del estado y texto oscuro (contraste).
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: status.color.withValues(alpha: .14),
                          borderRadius: BorderRadius.circular(10),
                          border: Border(
                              left: BorderSide(color: status.color, width: 4)),
                        ),
                        child: Text(reason,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary)),
                      )
                    else
                      Text(wellbeing.summary,
                          style:
                              const TextStyle(color: AppColors.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Las tres luces del semáforo; solo la del estado actual queda encendida.
class _Lamps extends StatelessWidget {
  const _Lamps({required this.active});

  final TrafficLight active;

  @override
  Widget build(BuildContext context) {
    const lamps = [
      TrafficLight.critical,
      TrafficLight.warning,
      TrafficLight.ok
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.textPrimary,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          for (final lamp in lamps) ...[
            Container(
              key: ValueKey('lamp-${lamp.apiValue}'),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: lamp == active
                    ? lamp.color
                    : lamp.color.withValues(alpha: .25),
                boxShadow: lamp == active
                    ? [BoxShadow(color: lamp.color, blurRadius: 8)]
                    : null,
              ),
            ),
            if (lamp != lamps.last) const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _NoData extends StatelessWidget {
  const _NoData();

  @override
  Widget build(BuildContext context) {
    return const AppCard(
      child: Row(
        children: [
          Icon(Icons.sensors_off_rounded,
              size: 36, color: AppColors.textSecondary),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(WellbeingTrafficLight.emptyText,
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
                SizedBox(height: 4),
                Text(
                  'Cuando el reloj o la cuidadora registren lecturas, aquí '
                  'verás el estado del día.',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
