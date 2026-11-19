import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/domain/models.dart';
import '../data/nutrition_repository.dart';
import '../domain/models.dart';

/// Resumen de alimentación del día de un paciente.
final nutritionDayProvider =
    FutureProvider.autoDispose.family<NutritionDay, String>((ref, patientId) {
  return ref.watch(nutritionRepositoryProvider).getDay(patientId);
});

String _ago(DateTime when) {
  final d = DateTime.now().difference(when.toLocal());
  if (d.inMinutes < 1) return 'recién';
  if (d.inMinutes < 60) return 'hace ${d.inMinutes} min';
  if (d.inHours < 24) return 'hace ${d.inHours} h';
  return 'hace ${d.inDays} días';
}

String _glasses(double value) =>
    value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toStringAsFixed(1);

/// Alimentación e hidratación (DAC05-95): la cuidadora registra cada comida
/// con botones grandes y suma vasos de agua; la familia ve el resumen.
class NutritionScreen extends ConsumerWidget {
  const NutritionScreen({super.key, required this.patientId});

  final String patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final day = ref.watch(nutritionDayProvider(patientId));
    final role = ref.watch(currentUserProvider)?.primaryRole;
    final canLog = role == RoleType.caregiver;
    final canConfigure = role == RoleType.caregiver || role == RoleType.family;

    return Scaffold(
      appBar: AppBar(title: const Text('Alimentación de hoy')),
      body: day.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
          message: 'No se pudo cargar la alimentación.',
          onRetry: () => ref.invalidate(nutritionDayProvider(patientId)),
        ),
        data: (d) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(nutritionDayProvider(patientId)),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              if (d.lastIntakeAt != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text('Última vez que comió o tomó algo: ${_ago(d.lastIntakeAt!)}',
                      style: const TextStyle(color: AppColors.textSecondary)),
                ),
              Text('Comidas', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              for (final type in MealType.values)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _MealTile(
                    meal: d.meal(type),
                    onTap: canLog ? () => _pickPortion(context, ref, type) : null,
                  ),
                ),
              const SizedBox(height: 12),
              Text('Líquidos', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              _WaterCard(day: d, onAddGlass: canLog ? () => _addGlass(context, ref) : null),
              if (canConfigure) ...[
                const SizedBox(height: 20),
                _AlertSettings(
                  settings: d.settings,
                  onChanged: (hours) => _saveAlert(context, ref, hours),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickPortion(BuildContext context, WidgetRef ref, MealType type) async {
    final percent = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('¿Cuánto comió en ${type.withArticle}?',
                  style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 12),
              for (final entry in mealPortions.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: OutlinedButton(
                    key: Key('portion-${entry.key}'),
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                    onPressed: () => Navigator.pop(ctx, entry.key),
                    child: Text(entry.value, style: const TextStyle(fontSize: 18)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (percent == null) return;
    try {
      await ref.read(nutritionRepositoryProvider).logMeal(patientId, type, percent);
      ref.invalidate(nutritionDayProvider(patientId));
      if (context.mounted) {
        showAppSnackBar(
            context, '${type.label}: ${portionLabel(percent).toLowerCase()}. Registrado.');
      }
    } catch (_) {
      if (context.mounted) showAppSnackBar(context, 'No se pudo registrar la comida.', error: true);
    }
  }

  Future<void> _addGlass(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(nutritionRepositoryProvider).logGlass(patientId);
      ref.invalidate(nutritionDayProvider(patientId));
      if (context.mounted) showAppSnackBar(context, 'Se sumó un vaso de agua.');
    } catch (_) {
      if (context.mounted) showAppSnackBar(context, 'No se pudo registrar el vaso.', error: true);
    }
  }

  Future<void> _saveAlert(BuildContext context, WidgetRef ref, int? hours) async {
    try {
      await ref
          .read(nutritionRepositoryProvider)
          .updateSettings(patientId, noIntakeAlertHours: hours);
      ref.invalidate(nutritionDayProvider(patientId));
      if (context.mounted) {
        showAppSnackBar(
            context,
            hours == null
                ? 'Aviso apagado.'
                : 'Avisaremos si pasan $hours horas sin comer ni beber.');
      }
    } catch (_) {
      if (context.mounted) showAppSnackBar(context, 'No se pudo guardar el aviso.', error: true);
    }
  }
}

class _MealTile extends StatelessWidget {
  const _MealTile({required this.meal, this.onTap});

  final MealSummary meal;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = !meal.logged
        ? AppColors.textSecondary
        : (meal.percentEaten! >= 50 ? AppColors.statusOk : AppColors.statusWarning);
    return AppCard(
      key: Key('meal-${meal.type.apiValue}'),
      onTap: onTap,
      child: Row(
        children: [
          Icon(meal.logged ? Icons.restaurant_rounded : Icons.restaurant_outlined, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(meal.type.label,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          ),
          Flexible(
            child: Text(portionLabel(meal.percentEaten),
                textAlign: TextAlign.end,
                style: TextStyle(color: color, fontWeight: FontWeight.w600)),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
          ],
        ],
      ),
    );
  }
}

class _WaterCard extends StatelessWidget {
  const _WaterCard({required this.day, this.onAddGlass});

  final NutritionDay day;
  final VoidCallback? onAddGlass;

  @override
  Widget build(BuildContext context) {
    final color = day.goalReached ? AppColors.statusOk : AppColors.primary;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.water_drop_rounded, color: color, size: 30),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${_glasses(day.glasses)} de ${day.settings.goalGlasses} vasos',
                  key: const Key('water-count'),
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(value: day.progress, minHeight: 10, color: color),
          ),
          const SizedBox(height: 6),
          Text('${day.totalMl} ml de ${day.settings.hydrationGoalMl} ml',
              style: const TextStyle(color: AppColors.textSecondary)),
          if (onAddGlass != null) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('add-glass'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: onAddGlass,
              icon: const Icon(Icons.add_rounded),
              label: Text('Sumar 1 vaso (${day.settings.glassMl} ml)'),
            ),
          ],
        ],
      ),
    );
  }
}

class _AlertSettings extends StatelessWidget {
  const _AlertSettings({required this.settings, required this.onChanged});

  final NutritionSettings settings;
  final ValueChanged<int?> onChanged;

  static const _options = [3, 4, 6, 8];

  @override
  Widget build(BuildContext context) {
    final hours = settings.noIntakeAlertHours;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            key: const Key('intake-alert-switch'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Avisar si no come ni bebe'),
            subtitle: Text(hours == null
                ? 'Apagado'
                : 'Si pasan $hours horas sin registros (de 8:00 a 21:00)'),
            value: hours != null,
            onChanged: (on) => onChanged(on ? 4 : null),
          ),
          if (hours != null)
            Wrap(
              spacing: 8,
              children: [
                for (final h in _options)
                  ChoiceChip(
                    label: Text('$h h'),
                    selected: h == hours,
                    onSelected: (_) => onChanged(h),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Tarjeta compacta para el inicio (familia y cuidadora): comidas y vasos de hoy.
class NutritionSummaryCard extends ConsumerWidget {
  const NutritionSummaryCard({super.key, required this.patientId});

  final String patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final day = ref.watch(nutritionDayProvider(patientId));
    return day.maybeWhen(
      data: (d) => AppCard(
        key: const Key('nutrition-summary'),
        onTap: () => context.push('/nutrition?patient=$patientId'),
        child: Row(
          children: [
            const Icon(Icons.restaurant_menu_rounded, color: AppColors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Alimentación de hoy', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    '${d.mealsLogged} de ${MealType.values.length} comidas · '
                    '${_glasses(d.glasses)} de ${d.settings.goalGlasses} vasos de agua',
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
          ],
        ),
      ),
      orElse: () => const SizedBox.shrink(),
    );
  }
}
