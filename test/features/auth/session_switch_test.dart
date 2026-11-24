// Cambio de cuenta en el mismo equipo: el usuario nuevo no debe ver los
// pacientes (p. ej. "Elena Ramírez") de quien usó la app antes.
import 'package:agecare_app/core/theme/app_theme.dart';
import 'package:agecare_app/features/auth/application/auth_controller.dart';
import 'package:agecare_app/features/auth/domain/models.dart';
import 'package:agecare_app/features/patients/application/patients_providers.dart';
import 'package:agecare_app/features/patients/data/patients_repository.dart';
import 'package:agecare_app/features/patients/domain/models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAuth extends AuthController {
  @override
  AuthState build() => const Unauthenticated();

  void signIn(String userId) =>
      state = Authenticated(User(userId: userId, fullName: userId, email: '$userId@x.cl'));

  void signOut() => state = const Unauthenticated();
}

class _Patients extends Fake implements PatientsRepository {
  String current = 'demo';

  @override
  Future<List<PatientCard>> listMyPatients() async => current == 'demo' ? [_elena] : [];
}

const _elena = PatientCard(
  patientId: 'p-elena',
  fullName: 'Elena Ramírez',
  role: RoleType.family,
  wellbeingStatus: WellbeingStatus.ok,
);

void main() {
  test('al entrar con otra cuenta se recargan los pacientes y se olvida el elegido', () async {
    final repo = _Patients();
    final container = ProviderContainer(overrides: [
      authControllerProvider.overrideWith(_FakeAuth.new),
      patientsRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(container.dispose);
    final auth = container.read(authControllerProvider.notifier) as _FakeAuth;
    container.listen(selectedPatientProvider, (_, __) {});

    auth.signIn('demo');
    expect(await container.read(myPatientsProvider.future), [_elena]);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(selectedPatientProvider)?.fullName, 'Elena Ramírez');

    auth.signOut();
    repo.current = 'nuevo';
    auth.signIn('nuevo');
    expect(await container.read(myPatientsProvider.future), isEmpty);
    expect(container.read(selectedPatientProvider), isNull);
  });
}
