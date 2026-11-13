import 'package:flutter/material.dart';

/// Tipos de vital (alineados con enum VitalType de la API).
enum VitalType {
  heartRate('heart_rate', 'Ritmo cardíaco', 'bpm', Icons.favorite_rounded),
  spo2('spo2', 'Oxígeno (SpO2)', '%', Icons.air_rounded),
  temperature('temperature', 'Temperatura', '°C', Icons.thermostat_rounded),
  sleep('sleep', 'Sueño', 'h', Icons.bedtime_rounded),
  steps('steps', 'Pasos', 'pasos', Icons.directions_walk_rounded),
  sedentaryMin(
      'sedentary_min', 'Tiempo sedentario', 'min', Icons.chair_rounded),
  fallEvent('fall_event', 'Caídas', 'eventos', Icons.warning_rounded),
  bloodPressure('blood_pressure', 'Presión arterial', 'mmHg',
      Icons.monitor_heart_rounded);

  /// true para los signos vitales "core" que se muestran siempre en Salud
  /// (AGE-304): ritmo cardíaco y SpO2. El resto son datos de actividad/sueño,
  /// que se agrupan aparte.
  bool get isCoreVital => this == heartRate || this == spo2;

  /// La temperatura no se muestra en la app (feedback del equipo: el reloj
  /// no la mide y no aporta). El backend la sigue aceptando.
  bool get isHidden => this == temperature;

  /// Tipos de la API que la app no muestra.
  static const hiddenApiValues = {'temperature'};

  const VitalType(this.apiValue, this.label, this.unit, this.icon);

  final String apiValue;
  final String label;
  final String unit;
  final IconData icon;

  static VitalType fromApi(String v) => VitalType.values
      .firstWhere((t) => t.apiValue == v, orElse: () => VitalType.heartRate);
}

class VitalReading {
  const VitalReading({
    required this.type,
    required this.value,
    required this.measuredAt,
    this.meta,
  });

  final VitalType type;
  final double value;
  final DateTime measuredAt;
  final Map<String, dynamic>? meta;

  Map<String, dynamic> toJson() => {
        'type': type.apiValue,
        'value': value,
        'measured_at': measuredAt.toUtc().toIso8601String(),
        if (meta != null) 'meta': meta,
      };
}

class VitalPoint {
  const VitalPoint({required this.ts, required this.value, this.min, this.max});

  final DateTime ts;
  final double value;
  final double? min;
  final double? max;

  factory VitalPoint.fromJson(Map<String, dynamic> json) => VitalPoint(
        ts: DateTime.parse(json['ts'] as String).toLocal(),
        value: (json['value'] as num).toDouble(),
        min: (json['min'] as num?)?.toDouble(),
        max: (json['max'] as num?)?.toDouble(),
      );
}

class Threshold {
  const Threshold({
    required this.type,
    this.minValue,
    this.maxValue,
    this.minSecondary,
    this.maxSecondary,
  });

  final VitalType type;
  final double? minValue;
  final double? maxValue;

  /// Rango de la diastólica; solo en presión arterial (DAC05-196).
  final double? minSecondary;
  final double? maxSecondary;

  bool isOutOfRange(double value) =>
      (minValue != null && value < minValue!) ||
      (maxValue != null && value > maxValue!);

  factory Threshold.fromJson(Map<String, dynamic> json) => Threshold(
        type: VitalType.fromApi(json['type'] as String),
        minValue: (json['min_value'] as num?)?.toDouble(),
        maxValue: (json['max_value'] as num?)?.toDouble(),
        minSecondary: (json['min_secondary'] as num?)?.toDouble(),
        maxSecondary: (json['max_secondary'] as num?)?.toDouble(),
      );
}

class VitalSeries {
  const VitalSeries({
    required this.type,
    required this.points,
    this.threshold,
  });

  final VitalType type;
  final List<VitalPoint> points;
  final Threshold? threshold;
}

class LatestVital {
  const LatestVital({
    required this.type,
    required this.value,
    required this.measuredAt,
    this.inRange = true,
    this.valueSecondary,
  });

  final VitalType type;
  final double value;
  final DateTime measuredAt;
  final bool inRange;

  /// Diastólica, en lecturas de presión arterial.
  final double? valueSecondary;

  factory LatestVital.fromJson(Map<String, dynamic> json) => LatestVital(
        type: VitalType.fromApi(json['type'] as String),
        value: (json['value'] as num).toDouble(),
        measuredAt: DateTime.parse(json['measured_at'] as String).toLocal(),
        inRange: (json['in_range'] ?? true) as bool,
        valueSecondary: (json['value_secondary'] as num?)?.toDouble(),
      );

  String get displayValue {
    switch (type) {
      case VitalType.steps:
      case VitalType.sedentaryMin:
      case VitalType.fallEvent:
        return value.toInt().toString();
      case VitalType.sleep:
        final h = value.floor();
        final m = ((value - h) * 60).round();
        return '${h}h ${m.toString().padLeft(2, '0')}m';
      case VitalType.temperature:
        return value.toStringAsFixed(1);
      case VitalType.bloodPressure:
        final dia = valueSecondary;
        return dia == null
            ? value.toStringAsFixed(0)
            : '${value.toStringAsFixed(0)}/${dia.toStringAsFixed(0)}';
      default:
        return value.toStringAsFixed(0);
    }
  }
}
