import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Estado del semáforo de bienestar (GET /patients/{id}/wellbeing, DAC05-178).
enum TrafficLight {
  ok('ok', 'Estable', AppColors.statusOk, Icons.check_circle_rounded),
  warning('warning', 'En observación', AppColors.statusWarning,
      Icons.error_rounded),
  critical('critical', 'Requiere atención', AppColors.statusAttention,
      Icons.warning_rounded),
  noData('no_data', 'Sin datos', AppColors.textSecondary,
      Icons.sensors_off_rounded);

  const TrafficLight(this.apiValue, this.label, this.color, this.icon);

  final String apiValue;
  final String label;
  final Color color;
  final IconData icon;

  static TrafficLight fromApi(String value) => TrafficLight.values.firstWhere(
        (s) => s.apiValue == value,
        orElse: () => TrafficLight.noData,
      );
}

/// Semáforo de las últimas 24 horas: estado, puntaje y motivos.
class Wellbeing {
  const Wellbeing({
    required this.status,
    required this.summary,
    this.score,
    this.reasons = const [],
  });

  final TrafficLight status;
  final String summary;

  /// 0 a 100; null cuando no hay datos.
  final int? score;
  final List<String> reasons;

  /// Motivo principal para destacar junto al semáforo.
  String? get topReason => reasons.isEmpty ? null : reasons.first;

  factory Wellbeing.fromJson(Map<String, dynamic> json) => Wellbeing(
        status: TrafficLight.fromApi((json['status'] ?? 'no_data') as String),
        summary: (json['summary'] ?? '') as String,
        score: (json['score'] as num?)?.toInt(),
        reasons: ((json['reasons'] ?? const []) as List).cast<String>(),
      );
}
