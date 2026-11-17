import 'package:flutter_test/flutter_test.dart';
import 'package:agecare_app/features/caregiver/data/caregiver_repository.dart';
import 'package:agecare_app/features/caregiver/domain/models.dart';

void main() {
  group('CaregiverRepository Unit Tests', () {
    late CaregiverRepositoryMock caregiverRepo;

    setUp(() {
      caregiverRepo = CaregiverRepositoryMock();
    });

    test('getToday returns caregiver shift summary and patient details', () async {
      final todayData = await caregiverRepo.getToday();

      expect(todayData, isNotNull);
      expect(todayData.patientName, isNotEmpty);
    });

    test('listTasks returns daily tasks for patient', () async {
      final tasks = await caregiverRepo.listTasks('p-elena');

      expect(tasks, isNotEmpty);
      expect(tasks.first.title, isNotEmpty);
    });

    test('checkin updates shift status to checkedIn', () async {
      final shift = await caregiverRepo.checkin('p-elena', type: 'in');

      expect(shift, equals(ShiftStatus.checkedIn));
    });

    test('createObservation adds a new observation note', () async {
      final obs = await caregiverRepo.createObservation(
        'p-elena',
        text: 'Paciente almorzó adecuadamente y tomó sus medicamentos.',
        category: 'rutina',
      );

      expect(obs.id, isNotEmpty);
      expect(obs.text, contains('almorzó'));
    });

    test('createObservation persists severity when provided (DAC05-209)', () async {
      final obs = await caregiverRepo.createObservation(
        'p-elena',
        text: 'Se observó una lesión leve en el antebrazo izquierdo.',
        category: 'Lesión/Piel',
        severity: ObservationSeverity.medium,
      );

      expect(obs.severity, equals(ObservationSeverity.medium));
      expect(obs.category, equals('Lesión/Piel'));
    });

    test('createObservation accepts mediaUrl for photo attachment (DAC05-209)',
        () async {
      final obs = await caregiverRepo.createObservation(
        'p-elena',
        text: 'Foto del estado de la piel adjunta.',
        category: 'Lesión/Piel',
        severity: ObservationSeverity.low,
        mediaUrl: 'https://blob.azure.net/test/foto.jpg',
      );

      expect(obs.mediaUrl, equals('https://blob.azure.net/test/foto.jpg'));
      expect(obs.severity, equals(ObservationSeverity.low));
    });

    test('createObservation without severity leaves it null (DAC05-209)',
        () async {
      final obs = await caregiverRepo.createObservation(
        'p-elena',
        text: 'Revisión general sin incidentes.',
      );

      expect(obs.severity, isNull);
    });

    test('createHandoverNote registers shift change note', () async {
      final note = await caregiverRepo.createHandoverNote(
        'p-elena',
        text: 'Queda pendiente verificar presión arterial a las 20:00.',
      );

      expect(note.id, isNotEmpty);
      expect(note.text, contains('presión arterial'));
    });
  });
}
