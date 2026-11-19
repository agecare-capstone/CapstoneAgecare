/// Alimentación e hidratación del adulto mayor (DAC05-95).
library;

/// Comidas del día, en el orden en que ocurren.
enum MealType {
  breakfast('breakfast', 'Desayuno'),
  lunch('lunch', 'Almuerzo'),
  snack('snack', 'Once'),
  dinner('dinner', 'Cena');

  const MealType(this.apiValue, this.label);

  final String apiValue;
  final String label;

  /// "el desayuno", "el almuerzo", "la once", "la cena".
  String get withArticle =>
      '${this == MealType.breakfast || this == MealType.lunch ? 'el' : 'la'} ${label.toLowerCase()}';

  static MealType fromApi(String value) =>
      MealType.values.firstWhere((m) => m.apiValue == value, orElse: () => MealType.snack);
}

/// Opciones rápidas de cuánto comió (botones grandes, sin escribir números).
const mealPortions = <int, String>{
  0: 'Nada',
  25: 'Poco',
  50: 'La mitad',
  75: 'Casi todo',
  100: 'Todo',
};

String portionLabel(int? percent) {
  if (percent == null) return 'Sin registrar';
  return mealPortions[percent] ?? '$percent %';
}

class MealSummary {
  const MealSummary({required this.type, this.percentEaten});

  final MealType type;
  final int? percentEaten;

  bool get logged => percentEaten != null;
}

class FluidEntry {
  const FluidEntry(
      {required this.id, required this.amountMl, required this.kind, required this.loggedAt});

  final String id;
  final int amountMl;
  final String kind;
  final DateTime loggedAt;

  factory FluidEntry.fromJson(Map<String, dynamic> json) => FluidEntry(
        id: json['fluid_id'] as String,
        amountMl: (json['amount_ml'] as num).toInt(),
        kind: (json['kind'] ?? 'water') as String,
        loggedAt: DateTime.parse(json['logged_at'] as String),
      );
}

class NutritionSettings {
  const NutritionSettings({
    this.hydrationGoalMl = 1500,
    this.glassMl = 250,
    this.noIntakeAlertHours,
  });

  final int hydrationGoalMl;
  final int glassMl;

  /// null = aviso apagado.
  final int? noIntakeAlertHours;

  int get goalGlasses => (hydrationGoalMl / glassMl).round();

  factory NutritionSettings.fromJson(Map<String, dynamic> json) => NutritionSettings(
        hydrationGoalMl: (json['hydration_goal_ml'] as num?)?.toInt() ?? 1500,
        glassMl: (json['glass_ml'] as num?)?.toInt() ?? 250,
        noIntakeAlertHours: (json['no_intake_alert_hours'] as num?)?.toInt(),
      );
}

/// Resumen del día: comidas, líquidos contra la meta y última ingesta.
class NutritionDay {
  const NutritionDay({
    required this.date,
    required this.meals,
    required this.totalMl,
    required this.fluids,
    required this.settings,
    this.lastIntakeAt,
  });

  final DateTime date;
  final List<MealSummary> meals;
  final int totalMl;
  final List<FluidEntry> fluids;
  final NutritionSettings settings;
  final DateTime? lastIntakeAt;

  double get glasses => totalMl / settings.glassMl;
  double get progress => (totalMl / settings.hydrationGoalMl).clamp(0, 1).toDouble();
  bool get goalReached => totalMl >= settings.hydrationGoalMl;
  int get mealsLogged => meals.where((m) => m.logged).length;

  MealSummary meal(MealType type) =>
      meals.firstWhere((m) => m.type == type, orElse: () => MealSummary(type: type));

  factory NutritionDay.fromJson(Map<String, dynamic> json) {
    final fluids = (json['fluids'] ?? const <String, dynamic>{}) as Map<String, dynamic>;
    return NutritionDay(
      date: DateTime.parse(json['date'] as String),
      meals: [
        for (final m in (json['meals_summary'] ?? const []) as List)
          MealSummary(
            type: MealType.fromApi((m as Map<String, dynamic>)['meal_type'] as String),
            percentEaten: (m['percent_eaten'] as num?)?.toInt(),
          ),
      ],
      totalMl: (fluids['total_ml'] as num?)?.toInt() ?? 0,
      fluids: [
        for (final f in (fluids['entries'] ?? const []) as List)
          FluidEntry.fromJson(f as Map<String, dynamic>),
      ],
      settings: NutritionSettings.fromJson(
          (json['settings'] ?? const <String, dynamic>{}) as Map<String, dynamic>),
      lastIntakeAt:
          json['last_intake_at'] == null ? null : DateTime.parse(json['last_intake_at'] as String),
    );
  }
}
