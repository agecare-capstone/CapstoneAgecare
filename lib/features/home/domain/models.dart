import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Un dato destacado del resumen del día (icono + etiqueta + valor).
class SummaryHighlight {
  const SummaryHighlight({
    required this.iconKey,
    required this.label,
    required this.value,
  });

  final String iconKey;
  final String label;
  final String value;

  /// Mapea la clave del backend a un icono de Material.
  IconData get icon => _iconFor(iconKey);

  static IconData _iconFor(String key) {
    switch (key) {
      case 'heart':
      case 'heart_rate':
        return Icons.favorite_rounded;
      case 'steps':
      case 'activity':
        return Icons.directions_walk_rounded;
      case 'sleep':
        return Icons.bedtime_rounded;
      case 'spo2':
      case 'oxygen':
        return Icons.air_rounded;
      case 'blood_pressure':
        return Icons.monitor_heart_rounded;
      case 'temperature':
        return Icons.thermostat_rounded;
      case 'medication':
      case 'adherence':
        return Icons.medication_rounded;
      case 'alert':
        return Icons.notifications_active_rounded;
      default:
        return Icons.insights_rounded;
    }
  }

  factory SummaryHighlight.fromJson(Map<String, dynamic> json) => SummaryHighlight(
        iconKey: (json['icon'] ?? json['icon_key'] ?? '').toString(),
        label: (json['label'] ?? '').toString(),
        value: (json['value'] ?? '').toString(),
      );
}

/// Última lectura de un signo vital para mostrar en el tablero.
class VitalReading {
  const VitalReading({
    required this.type,
    required this.label,
    required this.value,
    this.unit,
    this.iconKey,
    this.measuredAt,
    this.inRange = true,
  });

  final String type;
  final String label;
  final String value;
  final String? unit;
  final String? iconKey;
  final DateTime? measuredAt;
  final bool inRange;

  IconData get icon => SummaryHighlight._iconFor(iconKey ?? type);

  String get display => unit == null || unit!.isEmpty ? value : '$value $unit';

  factory VitalReading.fromJson(Map<String, dynamic> json) => VitalReading(
        type: (json['type'] ?? '').toString(),
        label: (json['label'] ?? '').toString(),
        value: (json['value'] ?? '').toString(),
        unit: json['unit'] as String?,
        iconKey: json['icon'] as String?,
        measuredAt: json['measured_at'] != null
            ? DateTime.parse(json['measured_at'] as String).toLocal()
            : null,
        inRange: (json['in_range'] ?? true) as bool,
      );
}

/// Resumen del día de un paciente para el tablero familiar
/// (GET /patients/{id}/summary/today).
class TodaySummary {
  const TodaySummary({
    required this.wellbeingStatus,
    required this.date,
    required this.summary,
    this.highlights = const [],
    this.activeAlertsCount = 0,
    this.adherencePct,
    this.latestVitals = const [],
    this.topReason,
  });

  final WellbeingStatus wellbeingStatus;
  final DateTime date;

  /// Resumen textual legible para la familia.
  final String summary;

  /// Datos destacados del día.
  final List<SummaryHighlight> highlights;

  /// Número de alertas activas.
  final int activeAlertsCount;

  /// Porcentaje de adherencia a la medicación del día (0-100).
  final int? adherencePct;

  /// Últimas lecturas de vitals.
  final List<VitalReading> latestVitals;

  /// Razón principal detrás del estado del semáforo.
  final String? topReason;

  bool get hasAlerts => activeAlertsCount > 0;

  factory TodaySummary.fromJson(Map<String, dynamic> json) => TodaySummary(
        wellbeingStatus:
            WellbeingStatus.fromApi((json['wellbeing_status'] ?? 'ok') as String),
        date: json['date'] != null
            ? DateTime.parse(json['date'] as String)
            : DateTime.now(),
        summary: (json['summary'] ?? '').toString(),
        highlights: ((json['highlights'] ?? []) as List)
            .map((e) => SummaryHighlight.fromJson(e as Map<String, dynamic>))
            .toList(),
        activeAlertsCount: (json['active_alerts_count'] ?? 0) as int,
        adherencePct: json['adherence_pct'] as int?,
        latestVitals: ((json['latest_vitals'] ?? []) as List)
            // La temperatura no se muestra en la app.
            .where((e) =>
                (e as Map)['type'] != 'temperature' && e['icon'] != 'temperature')
            .map((e) => VitalReading.fromJson(e as Map<String, dynamic>))
            .toList(),
        topReason: json['top_reason'] as String?,
      );
}
