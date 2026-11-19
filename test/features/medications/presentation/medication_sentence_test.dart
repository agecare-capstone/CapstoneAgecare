// Frase simple al agregar un remedio (feedback del equipo): la cuidadora y el
// adulto mayor deben entender qué se está cargando.
import 'package:agecare_app/features/medications/domain/models.dart';
import 'package:agecare_app/features/medications/presentation/medication_plan_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  NewMedication med({List<String> schedule = const ['08:00', '20:00'],
          DateTime? start, DateTime? end}) =>
      NewMedication(
        name: 'Losartán',
        dose: '50',
        unit: 'mg',
        form: 'tablet',
        schedule: schedule,
        startDate: start ?? DateTime.now(),
        endDate: end,
      );

  test('arma la frase con dosis, horarios y "desde hoy"', () {
    expect(medicationSentence(med()),
        'Losartán 50 mg, a las 08:00 y 20:00, todos los días desde hoy.');
  });

  test('con fecha de inicio y término muestra ambas', () {
    expect(
        medicationSentence(med(
            schedule: ['09:00'],
            start: DateTime(2030, 1, 5),
            end: DateTime(2030, 2, 1))),
        'Losartán 50 mg, a las 09:00, todos los días desde el 05/01 hasta el 01/02.');
  });

  test('sin horarios no deja la frase a medias', () {
    expect(medicationSentence(med(schedule: [])),
        'Losartán 50 mg, sin horario fijo, todos los días desde hoy.');
  });
}
