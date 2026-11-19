import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../domain/models.dart';

/// Alimentación e hidratación (DAC05-95).
abstract class NutritionRepository {
  Future<NutritionDay> getDay(String patientId);
  Future<void> logMeal(String patientId, MealType type, int percentEaten, {String? note});
  Future<void> logGlass(String patientId, {int glasses = 1});
  Future<NutritionSettings> updateSettings(String patientId,
      {int? hydrationGoalMl, int? glassMl, int? noIntakeAlertHours});
}

class NutritionRepositoryHttp implements NutritionRepository {
  NutritionRepositoryHttp(this._api);

  final ApiClient _api;

  @override
  Future<NutritionDay> getDay(String patientId) async {
    final data = await _api.get<Map<String, dynamic>>('/patients/$patientId/nutrition');
    return NutritionDay.fromJson(data);
  }

  @override
  Future<void> logMeal(String patientId, MealType type, int percentEaten, {String? note}) =>
      _api.post<Map<String, dynamic>>('/patients/$patientId/meals', data: {
        'meal_type': type.apiValue,
        'percent_eaten': percentEaten,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      });

  @override
  Future<void> logGlass(String patientId, {int glasses = 1}) =>
      _api.post<Map<String, dynamic>>('/patients/$patientId/fluids', data: {'glasses': glasses});

  @override
  Future<NutritionSettings> updateSettings(String patientId,
      {int? hydrationGoalMl, int? glassMl, int? noIntakeAlertHours}) async {
    final data =
        await _api.put<Map<String, dynamic>>('/patients/$patientId/nutrition/settings', data: {
      if (hydrationGoalMl != null) 'hydration_goal_ml': hydrationGoalMl,
      if (glassMl != null) 'glass_ml': glassMl,
      // 0 apaga el aviso.
      'no_intake_alert_hours': noIntakeAlertHours ?? 0,
    });
    return NutritionSettings.fromJson(data);
  }
}

/// Datos de demo en memoria: desayuno y almuerzo registrados y dos vasos de agua.
class NutritionRepositoryMock implements NutritionRepository {
  final Map<MealType, int> _meals = {MealType.breakfast: 100, MealType.lunch: 75};
  int _totalMl = 500;
  NutritionSettings _settings = const NutritionSettings(noIntakeAlertHours: 4);
  DateTime? _lastIntake = DateTime.now().subtract(const Duration(hours: 1));

  @override
  Future<NutritionDay> getDay(String patientId) async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    final now = DateTime.now();
    return NutritionDay(
      date: DateTime(now.year, now.month, now.day),
      meals: [for (final t in MealType.values) MealSummary(type: t, percentEaten: _meals[t])],
      totalMl: _totalMl,
      fluids: const [],
      settings: _settings,
      lastIntakeAt: _lastIntake,
    );
  }

  @override
  Future<void> logMeal(String patientId, MealType type, int percentEaten, {String? note}) async {
    _meals[type] = percentEaten;
    _lastIntake = DateTime.now();
  }

  @override
  Future<void> logGlass(String patientId, {int glasses = 1}) async {
    _totalMl += glasses * _settings.glassMl;
    _lastIntake = DateTime.now();
  }

  @override
  Future<NutritionSettings> updateSettings(String patientId,
      {int? hydrationGoalMl, int? glassMl, int? noIntakeAlertHours}) async {
    _settings = NutritionSettings(
      hydrationGoalMl: hydrationGoalMl ?? _settings.hydrationGoalMl,
      glassMl: glassMl ?? _settings.glassMl,
      noIntakeAlertHours: (noIntakeAlertHours ?? 0) == 0 ? null : noIntakeAlertHours,
    );
    return _settings;
  }
}

final nutritionRepositoryProvider = Provider<NutritionRepository>((ref) {
  if (AppConfig.useMocks) return NutritionRepositoryMock();
  return NutritionRepositoryHttp(ref.watch(apiClientProvider));
});
