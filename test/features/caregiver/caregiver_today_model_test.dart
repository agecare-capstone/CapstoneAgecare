// "Hoy" de la cuidadora con el formato real del servidor: paciente, turno
// abierto y turno de 8 h en curso (mañana 08-16, tarde 16-24).
import 'package:agecare_app/features/caregiver/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('lee paciente, turno abierto y turno en curso', () {
    final today = CaregiverToday.fromJson({
      'patient_id': 'p1',
      'patient_name': 'Elena Ramírez',
      'shift_status': 'checked_in',
      'current_shift': {
        'name': 'Tarde',
        'start': '16:00',
        'end': '24:00',
        'ends_at': '2026-11-21T03:00:00Z',
      },
      'pending_tasks': [
        {'task_id': 't1', 'title': 'Cena', 'status': 'pending', 'due': '2026-11-20T23:30:00Z'},
      ],
    });
    expect(today.patientId, 'p1');
    expect(today.shiftStatus.isCheckedIn, isTrue);
    expect(today.currentShift, 'Turno tarde · 16:00 a 24:00');
    expect(today.pendingTasks.single.title, 'Cena');
  });

  test('sin turno informado no muestra nada', () {
    final today = CaregiverToday.fromJson({'patient_id': 'p1'});
    expect(today.currentShift, isNull);
    expect(today.shiftStatus.isCheckedIn, isFalse);
  });
}
