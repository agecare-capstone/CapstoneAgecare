// Tareas en "Hoy": el servidor solo acepta pendiente/completada/omitida, así
// que la app ya no envía "En curso" (antes el primer toque daba 422).
import 'package:agecare_app/features/caregiver/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('los estados de tarea son solo pendiente y completada', () {
    expect(TaskStatus.values.map((s) => s.apiValue), ['pending', 'done']);
  });

  test('un estado desconocido del servidor se lee como pendiente', () {
    expect(TaskStatus.fromApi('in_progress'), TaskStatus.pending);
    expect(TaskStatus.fromApi('done'), TaskStatus.done);
  });
}
