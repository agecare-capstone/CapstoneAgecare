// Cuidadora y familia pueden eliminar un remedio del plan desde "Cambiar un
// remedio" (antes no había cómo).
import 'package:agecare_app/core/theme/app_theme.dart';
import 'package:agecare_app/features/medications/data/medications_repository.dart';
import 'package:agecare_app/features/medications/presentation/medication_plan_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';

class _Recording extends MedicationsRepositoryMock {
  final deleted = <String>[];

  @override
  Future<void> deleteMedication(String patientId, String medicationId) async {
    deleted.add('$patientId/$medicationId');
    await super.deleteMedication(patientId, medicationId);
  }
}

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  Future<_Recording> pump(WidgetTester tester, {String? medicationId}) async {
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _Recording();
    final id = medicationId ?? 'm-losartan';
    final router = GoRouter(initialLocation: '/', routes: [
      GoRoute(
        path: '/',
        builder: (context, __) => Scaffold(
          body: TextButton(
            onPressed: () => context.push('/plan'),
            child: const Text('abrir'),
          ),
        ),
      ),
      GoRoute(
        path: '/plan',
        builder: (_, __) => MedicationPlanScreen(patientId: 'p-elena', medicationId: id),
      ),
    ]);
    await tester.pumpWidget(ProviderScope(
      overrides: [medicationsRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    return repo;
  }

  testWidgets('al editar un remedio se puede eliminar, con confirmación', (tester) async {
    final repo = await pump(tester);
    const id = 'm-losartan';

    expect(find.byKey(const Key('delete-medication-button')), findsOneWidget);
    await tester.tap(find.byKey(const Key('delete-medication-button')));
    await tester.pumpAndSettle();
    expect(find.textContaining('del plan?'), findsOneWidget);

    // Cancelar no elimina.
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(repo.deleted, isEmpty);

    await tester.tap(find.byKey(const Key('delete-medication')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-delete-medication')));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(repo.deleted, ['p-elena/$id']);
    expect(find.byType(MedicationPlanScreen), findsNothing, reason: 'vuelve a la lista');
    expect(find.textContaining('se eliminó del plan'), findsOneWidget);
  });

  testWidgets('al agregar un remedio nuevo no aparece "Eliminar"', (tester) async {
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [medicationsRepositoryProvider.overrideWithValue(_Recording())],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const MedicationPlanScreen(patientId: 'p-elena'),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('delete-medication')), findsNothing);
    expect(find.byKey(const Key('delete-medication-button')), findsNothing);
  });
}
