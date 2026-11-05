// Pruebas de las preferencias de notificación (AGE-507 / DAC05-92).
//
// Criterio: las alertas críticas (SOS y caídas) aparecen bloqueadas. Se ven
// activas, con candado, y no se pueden apagar; las demás preferencias sí.
import 'package:agecare_app/core/theme/app_theme.dart';
import 'package:agecare_app/features/profile/data/profile_repository.dart';
import 'package:agecare_app/features/profile/domain/models.dart';
import 'package:agecare_app/features/profile/presentation/notification_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Repositorio de demo que además registra cada guardado.
class _RecordingProfileRepo extends ProfileRepositoryMock {
  final saved = <NotificationSettings>[];

  @override
  Future<void> updateNotificationSettings(NotificationSettings settings) {
    saved.add(settings);
    return super.updateNotificationSettings(settings);
  }
}

void main() {
  const criticalTitle = 'Alertas críticas (SOS y caídas)';

  Future<_RecordingProfileRepo> pumpScreen(WidgetTester tester) async {
    final repo = _RecordingProfileRepo();
    await tester.pumpWidget(ProviderScope(
      overrides: [profileRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
          theme: AppTheme.light(), home: const NotificationSettingsScreen()),
    ));
    await tester.pumpAndSettle();
    return repo;
  }

  Finder tile(String title) => find.widgetWithText(SwitchListTile, title);

  testWidgets('las alertas críticas aparecen activas y con candado',
      (tester) async {
    await pumpScreen(tester);

    final critical = tester.widget<SwitchListTile>(tile(criticalTitle));
    expect(critical.value, isTrue);
    expect(critical.onChanged, isNull);
    expect(find.text('Siempre activas por seguridad del paciente.'),
        findsOneWidget);
    expect(
        find.descendant(
            of: tile(criticalTitle),
            matching: find.byIcon(Icons.lock_rounded)),
        findsOneWidget);
    // Es la única preferencia bloqueada.
    expect(find.byIcon(Icons.lock_rounded), findsOneWidget);
  });

  testWidgets('tocar las alertas críticas no las apaga ni guarda nada',
      (tester) async {
    final repo = await pumpScreen(tester);

    await tester.tap(tile(criticalTitle));
    await tester.pumpAndSettle();

    expect(tester.widget<SwitchListTile>(tile(criticalTitle)).value, isTrue);
    expect(repo.saved, isEmpty);
  });

  testWidgets('las demás preferencias sí se pueden apagar', (tester) async {
    final repo = await pumpScreen(tester);

    await tester.tap(tile('Alertas por push'));
    await tester.pumpAndSettle();

    expect(repo.saved.single.alertsPush, isFalse);
    expect(tester.widget<SwitchListTile>(tile('Alertas por push')).value,
        isFalse);
    // Apagar el push general no apaga las críticas.
    expect(tester.widget<SwitchListTile>(tile(criticalTitle)).value, isTrue);
  });
}
