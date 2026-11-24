// Cuenta nueva de cuidadora / adulto mayor: sin pacientes ve "Tengo un
// código", y al unirse la app recarga su perfil para abrir la vista de su rol.
import 'package:agecare_app/core/theme/app_theme.dart';
import 'package:agecare_app/features/auth/application/auth_controller.dart';
import 'package:agecare_app/features/auth/domain/models.dart';
import 'package:agecare_app/features/home/data/dashboard_repository.dart';
import 'package:agecare_app/features/home/presentation/screens/home/family_home_screen.dart';
import 'package:agecare_app/features/patients/data/patients_repository.dart';
import 'package:agecare_app/features/patients/domain/models.dart';
import 'package:agecare_app/features/patients/presentation/accept_invitation_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const _newUser = User(userId: 'u-rosa', fullName: 'Rosa Nueva', email: 'rosa@x.cl');

/// Sesión de una cuenta recién creada; al recargar el perfil ya es cuidadora.
class _Auth extends AuthController {
  int refreshes = 0;

  @override
  AuthState build() => const Authenticated(_newUser);

  @override
  Future<void> refreshProfile() async {
    refreshes++;
    state = const Authenticated(User(
      userId: 'u-rosa',
      fullName: 'Rosa Nueva',
      email: 'rosa@x.cl',
      memberships: [
        Membership(patientId: 'p-ana', patientName: 'Ana', role: RoleType.caregiver),
      ],
    ));
  }
}

class _Patients extends Fake implements PatientsRepository {
  bool joined = false;

  @override
  Future<List<PatientCard>> listMyPatients() async => joined
      ? const [
          PatientCard(
            patientId: 'p-ana',
            fullName: 'Ana',
            role: RoleType.caregiver,
            wellbeingStatus: WellbeingStatus.ok,
          ),
        ]
      : const [];

  @override
  Future<PatientCard> acceptInvitation(String code) async {
    joined = true;
    return const PatientCard(
      patientId: 'p-ana',
      fullName: 'Ana',
      role: RoleType.caregiver,
      wellbeingStatus: WellbeingStatus.ok,
    );
  }
}

void main() {
  testWidgets('sin pacientes ofrece "Tengo un código" y al unirse cambia al rol de cuidadora',
      (tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final patients = _Patients();
    final router = GoRouter(initialLocation: '/home', routes: [
      GoRoute(path: '/home', builder: (_, __) => const FamilyHomeScreen()),
      GoRoute(path: '/invite/accept', builder: (_, __) => const AcceptInvitationScreen()),
      GoRoute(path: '/patients/create', builder: (_, __) => const SizedBox()),
    ]);
    final container = ProviderContainer(overrides: [
      authControllerProvider.overrideWith(_Auth.new),
      patientsRepositoryProvider.overrideWithValue(patients),
      dashboardRepositoryProvider.overrideWithValue(DashboardRepositoryMock()),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Aún no tienes pacientes'), findsOneWidget);
    expect(find.text('Crear paciente'), findsOneWidget);
    await tester.tap(find.byKey(const Key('join-with-code')));
    await tester.pumpAndSettle();
    expect(find.byType(AcceptInvitationScreen), findsOneWidget);

    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.widgetWithText(FilledButton, 'Unirme'));
    await tester.pumpAndSettle();

    expect(find.text('Te uniste al cuidado de Ana'), findsOneWidget);
    final auth = container.read(authControllerProvider.notifier) as _Auth;
    expect(auth.refreshes, 1, reason: 'recarga el perfil para tomar el rol nuevo');
    expect(container.read(currentUserProvider)!.primaryRole, RoleType.caregiver);
  });
}
