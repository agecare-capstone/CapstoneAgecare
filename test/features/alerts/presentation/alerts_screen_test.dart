// Centro de alertas: las alertas ya vistas siguen en "Activas" hasta resolverlas
// (antes no aparecían en ninguna pestaña) y las resueltas del historial no
// ofrecen volver a resolverlas.
import 'package:agecare_app/core/theme/app_theme.dart';
import 'package:agecare_app/features/alerts/data/alerts_repository.dart';
import 'package:agecare_app/features/alerts/domain/models.dart';
import 'package:agecare_app/features/alerts/presentation/alerts_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FixedAlertsRepo extends AlertsRepositoryMock {
  _FixedAlertsRepo(this.items);
  final List<Alert> items;

  @override
  Future<List<Alert>> listAlerts(
          {String? patientId, bool activeOnly = false}) async =>
      items;
}

Alert _alert(String id, String title, AlertStatus status) => Alert(
      id: id,
      patientId: 'p-elena',
      patientName: 'Elena Ramírez',
      type: AlertType.wearableOffline,
      severity: AlertSeverity.warning,
      title: title,
      message: 'Detalle',
      createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
      status: status,
    );

void main() {
  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        alertsRepositoryProvider.overrideWithValue(_FixedAlertsRepo([
          _alert('a1', 'Alerta activa', AlertStatus.active),
          _alert('a2', 'Alerta ya vista', AlertStatus.acknowledged),
          _alert('a3', 'Alerta resuelta', AlertStatus.resolved),
        ])),
      ],
      child: MaterialApp(theme: AppTheme.light(), home: const AlertsScreen()),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('las alertas ya vistas siguen en Activas hasta resolverlas',
      (tester) async {
    await pump(tester);
    expect(find.text('Alerta activa'), findsOneWidget);
    expect(find.text('Alerta ya vista'), findsOneWidget);
    expect(find.text('Alerta resuelta'), findsNothing);
    expect(find.text('Marcar como resuelto'), findsNWidgets(2));
  });

  testWidgets('el historial muestra las resueltas sin botón de resolver',
      (tester) async {
    await pump(tester);
    await tester.tap(find.text('Historial'));
    await tester.pumpAndSettle();
    expect(find.text('Alerta resuelta'), findsOneWidget);
    expect(find.text('Resuelta'), findsOneWidget);
    expect(find.text('Marcar como resuelto'), findsNothing);
    expect(find.text('Ya lo vi'), findsNothing);
  });
}
