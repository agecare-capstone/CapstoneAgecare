// Alimentación e hidratación (DAC05-95): la cuidadora registra comidas con
// botones grandes y vasos de agua; la familia ve el resumen sin editar.
import 'package:agecare_app/core/theme/app_theme.dart';
import 'package:agecare_app/features/auth/application/auth_controller.dart';
import 'package:agecare_app/features/auth/domain/models.dart';
import 'package:agecare_app/features/nutrition/data/nutrition_repository.dart';
import 'package:agecare_app/features/nutrition/presentation/nutrition_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

User _user(RoleType role) => User(
      userId: 'u1',
      fullName: 'Rosa Pérez',
      email: 'rosa@agecare.cl',
      memberships: [Membership(patientId: 'p1', patientName: 'Elena', role: role)],
    );

void main() {
  Future<NutritionRepositoryMock> pump(WidgetTester tester, RoleType role) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = NutritionRepositoryMock();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        nutritionRepositoryProvider.overrideWithValue(repo),
        currentUserProvider.overrideWithValue(_user(role)),
      ],
      child: MaterialApp(theme: AppTheme.light(), home: const NutritionScreen(patientId: 'p1')),
    ));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    return repo;
  }

  testWidgets('la cuidadora registra cuánto comió en la once', (tester) async {
    await pump(tester, RoleType.caregiver);
    expect(find.text('Sin registrar'), findsNWidgets(2)); // once y cena
    await tester.tap(find.byKey(const Key('meal-snack')));
    await tester.pumpAndSettle();
    expect(find.text('¿Cuánto comió en la once?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('portion-50')));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(find.text('Once: la mitad. Registrado.'), findsOneWidget);
    expect(find.text('Sin registrar'), findsOneWidget);
  });

  testWidgets('la pregunta usa el artículo correcto', (tester) async {
    await pump(tester, RoleType.caregiver);
    await tester.tap(find.byKey(const Key('meal-dinner')));
    await tester.pumpAndSettle();
    expect(find.text('¿Cuánto comió en la cena?'), findsOneWidget);
  });

  testWidgets('la cuidadora suma un vaso de agua', (tester) async {
    await pump(tester, RoleType.caregiver);
    expect(find.text('2 de 6 vasos'), findsOneWidget);
    await tester.tap(find.byKey(const Key('add-glass')));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(find.text('3 de 6 vasos'), findsOneWidget);
    expect(find.text('750 ml de 1500 ml'), findsOneWidget);
  });

  testWidgets('la familia ve el resumen pero no registra', (tester) async {
    await pump(tester, RoleType.family);
    expect(find.text('Todo'), findsOneWidget); // desayuno
    expect(find.text('Casi todo'), findsOneWidget); // almuerzo
    expect(find.byKey(const Key('add-glass')), findsNothing);
    await tester.tap(find.byKey(const Key('meal-dinner')));
    await tester.pumpAndSettle();
    expect(find.text('¿Cuánto comió en la cena?'), findsNothing);
    // Puede ajustar el aviso de "sin ingesta".
    expect(find.text('Si pasan 4 horas sin registros (de 8:00 a 21:00)'), findsOneWidget);
  });

  testWidgets('la tarjeta del inicio resume comidas y vasos', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [nutritionRepositoryProvider.overrideWithValue(NutritionRepositoryMock())],
      child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: NutritionSummaryCard(patientId: 'p1'))),
    ));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(find.text('2 de 4 comidas · 2 de 6 vasos de agua'), findsOneWidget);
  });
}
