import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../application/caregiver_providers.dart';
import '../data/caregiver_repository.dart';
import '../domain/models.dart';

/// Muestra la última nota de relevo si existe, destacada al hacer check-in.
class _HandoverNoteHighlight extends ConsumerWidget {
  const _HandoverNoteHighlight({required this.patientId});

  final String patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notesAsync = ref.watch(handoverNotesProvider);
    return notesAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (notes) {
        if (notes.isEmpty) return const SizedBox.shrink();
        final latest = notes.first;
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.statusWarning.withValues(alpha: .10),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.statusWarning.withValues(alpha: .40),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.swap_horiz_rounded,
                      size: 18, color: AppColors.statusWarning),
                  const SizedBox(width: 6),
                  const Text(
                    'Nota del turno anterior',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: AppColors.statusWarning,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    DateFormat('d MMM · HH:mm', 'es').format(latest.createdAt),
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textSecondary),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(latest.text,
                  style: const TextStyle(fontSize: 14, height: 1.4)),
              const SizedBox(height: 4),
              Text('— ${latest.authorName}',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
            ],
          ),
        );
      },
    );
  }
}

/// Confirmación de check-in / check-out del turno.
class CheckinScreen extends ConsumerStatefulWidget {
  const CheckinScreen({super.key, required this.patientId});

  final String patientId;

  @override
  ConsumerState<CheckinScreen> createState() => _CheckinScreenState();
}

class _CheckinScreenState extends ConsumerState<CheckinScreen> {
  bool _saving = false;

  Future<void> _submit(ShiftStatus current) async {
    setState(() => _saving = true);
    final type = current.nextCheckinType;
    try {
      await ref
          .read(caregiverRepositoryProvider)
          .checkin(widget.patientId, type: type);
      ref.invalidate(caregiverTodayProvider);
      if (mounted) {
        showAppSnackBar(
          context,
          type == 'in' ? 'Turno iniciado. ¡Buen trabajo!' : 'Turno finalizado.',
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) showAppSnackBar(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final todayAsync = ref.watch(caregiverTodayProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Registro de turno')),
      body: todayAsync.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
          message: e.toString(),
          onRetry: () => ref.invalidate(caregiverTodayProvider),
        ),
        data: (today) {
          final current = today.shiftStatus;
          final entering = !current.isCheckedIn;
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppCard(
                  child: Column(
                    children: [
                      Icon(current.icon, size: 48, color: current.color),
                      const SizedBox(height: 12),
                      Text(
                        'Estado actual: ${current.label}',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Paciente: ${today.patientName}',
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                // Nota de relevo destacada al hacer check-in (AGE-607).
                if (entering) ...[
                  const SizedBox(height: 16),
                  _HandoverNoteHighlight(patientId: widget.patientId),
                ],
                const Spacer(),
                Text(
                  entering
                      ? '¿Comenzar tu turno ahora?'
                      : '¿Finalizar tu turno ahora?',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  height: 72,
                  child: FilledButton.icon(
                    onPressed: _saving ? null : () => _submit(current),
                    style: FilledButton.styleFrom(
                      backgroundColor:
                          entering ? AppColors.statusOk : AppColors.primary,
                      textStyle: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w700),
                    ),
                    icon: _saving
                        ? const SizedBox(
                            height: 24,
                            width: 24,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.5, color: Colors.white),
                          )
                        : Icon(entering
                            ? Icons.login_rounded
                            : Icons.logout_rounded),
                    label: Text(entering ? 'Check-in' : 'Check-out'),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          );
        },
      ),
    );
  }
}
