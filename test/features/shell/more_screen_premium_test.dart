// Premium para la familia (DAC05-33): el menú "Más" ofrece AgeCare Premium
// al familiar (antes solo a la cuidadora).
import 'package:agecare_app/core/theme/app_theme.dart';
import 'package:agecare_app/features/auth/application/auth_controller.dart';
import 'package:agecare_app/features/auth/domain/models.dart';
import 'package:agecare_app/features/patients/data/patients_repository.dart';
import 'package:agecare_app/features/shell/more_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester, RoleType role) async {
    tester.view.physicalSize = const Size(430, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        patientsRepositoryProvider.overrideWithValue(PatientsRepositoryMock()),
        currentUserProvider.overrideWithValue(User(
          userId: 'u1',
          fullName: 'Carolina Ramírez',
          email: 'familia@agecare.cl',
          memberships: [
            Membership(patientId: 'p1', patientName: 'Elena', role: role)
          ],
        )),
      ],
      child: MaterialApp(
          theme: AppTheme.light(), home: const Scaffold(body: MoreScreen())),
    ));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
  }

  testWidgets('el familiar ve AgeCare Premium en el menú', (tester) async {
    await pump(tester, RoleType.family);
    expect(find.text('AgeCare Premium'), findsOneWidget);
    expect(find.text('Mis reportes'), findsNothing);
  });

  testWidgets('la cuidadora sigue viendo Premium y sus reportes',
      (tester) async {
    await pump(tester, RoleType.caregiver);
    expect(find.text('AgeCare Premium'), findsOneWidget);
    expect(find.text('Mis reportes'), findsOneWidget);
  });

  testWidgets('el médico no ve la oferta Premium', (tester) async {
    await pump(tester, RoleType.doctor);
    expect(find.text('AgeCare Premium'), findsNothing);
  });
}
