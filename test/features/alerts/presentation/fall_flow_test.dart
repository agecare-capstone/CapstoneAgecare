// Flujo crítico de caída (AGE-505 / DAC05-84, DAC05-85, DAC05-86).
//
// Criterios: el push de caída abre la pantalla roja; desde ahí se llama a la
// cuidadora o a emergencias (131); resolver exige una nota.
import 'package:agecare_app/app.dart';
import 'package:agecare_app/core/notifications/push_service.dart';
import 'package:agecare_app/core/theme/app_theme.dart';
import 'package:agecare_app/features/alerts/application/alarm_player.dart';
import 'package:agecare_app/features/alerts/data/alerts_repository.dart';
import 'package:agecare_app/features/alerts/presentation/alert_detail_screen.dart';
import 'package:agecare_app/features/auth/domain/models.dart';
import 'package:agecare_app/features/patients/application/patients_providers.dart';
import 'package:agecare_app/features/patients/data/patients_repository.dart';
import 'package:agecare_app/features/patients/domain/models.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Repositorio de demo que registra la nota con que se resuelve.
class _RecordingAlertsRepo extends AlertsRepositoryMock {
  final notes = <String?>[];

  final falseAlarms = <bool>[];

  @override
  Future<void> resolve(String alertId,
      {String? note, bool falseAlarm = false}) {
    notes.add(note);
    falseAlarms.add(falseAlarm);
    return super.resolve(alertId, note: note, falseAlarm: falseAlarm);
  }
}

/// Alarma de prueba: cuenta cuántas veces sonó y se detuvo.
class _FakeAlarm implements AlarmPlayer {
  int starts = 0;
  int stops = 0;

  @override
  Future<void> start() async => starts++;

  @override
  Future<void> stop() async => stops++;
}

void main() {
  late _FakeAlarm alarm;
  setUp(() => alarm = _FakeAlarm());

  List<Override> fallOverrides(_RecordingAlertsRepo repo, RoleType role) => [
        alertsRepositoryProvider.overrideWithValue(repo),
        patientsRepositoryProvider.overrideWithValue(PatientsRepositoryMock()),
        alarmPlayerProvider.overrideWithValue(alarm),
        myPatientsProvider.overrideWith((ref) async => [
              PatientCard(
                patientId: 'p-elena',
                fullName: 'Elena Ramírez',
                role: role,
                wellbeingStatus: WellbeingStatus.ok,
              ),
            ]),
      ];

  test('tocar el push de una caída lleva a la pantalla de la alerta', () {
    expect(
      routeForNotification({'type': 'alert', 'alert_id': 'a-fall-1', 'alert_type': 'fall'}),
      '/alerts/a-fall-1',
    );
    expect(routeForNotification({'type': 'dose', 'dose_id': 'd-1'}), '/dose/d-1');
    expect(routeForNotification({'type': 'chat'}), isNull);
  });

  Future<_RecordingAlertsRepo> pumpFall(WidgetTester tester,
      {RoleType role = RoleType.family}) async {
    final repo = _RecordingAlertsRepo();
    await tester.pumpWidget(ProviderScope(
      overrides: fallOverrides(repo, role),
      child: MaterialApp(
          theme: AppTheme.light(),
          home: const AlertDetailScreen(alertId: 'a-fall-1')),
    ));
    await tester.pumpAndSettle();
    return repo;
  }

  testWidgets('una caída activa muestra la pantalla roja con las dos llamadas',
      (tester) async {
    await pumpFall(tester);

    expect(find.widgetWithText(AppBar, 'Caída detectada'), findsOneWidget);
    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    expect(appBar.backgroundColor, AppColors.critical);
    // Título legible sobre el rojo.
    expect(
        tester
            .widget<Text>(find.descendant(
                of: find.byType(AppBar), matching: find.text('Caída detectada')))
            .style
            ?.color,
        Colors.white);

    // La cuidadora de la demo tiene teléfono: el botón queda habilitado.
    final caregiver = find.widgetWithText(FilledButton, 'Llamar a Cuidadora');
    expect(caregiver, findsOneWidget);
    expect(tester.widget<FilledButton>(caregiver).onPressed, isNotNull);
    expect(find.widgetWithText(OutlinedButton, 'Llamar a Emergencias (131)'),
        findsOneWidget);
  });

  testWidgets('la cuidadora no ve "Llamar a Cuidadora", solo el 131',
      (tester) async {
    await pumpFall(tester, role: RoleType.caregiver);

    expect(find.textContaining('Llamar a Cuidadora'), findsNothing);
    expect(find.textContaining('Cuidadora sin teléfono'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'Llamar a Emergencias (131)'),
        findsOneWidget);
  });

  testWidgets('resolver una caída exige escribir una nota', (tester) async {
    final repo = await pumpFall(tester);

    await tester.scrollUntilVisible(find.text('Resolver alerta'), 200);
    await tester.tap(find.text('Resolver alerta'));
    await tester.pumpAndSettle();

    // Sin nota, "Resolver" está deshabilitado.
    final confirm = find.widgetWithText(FilledButton, 'Resolver');
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'Ya está acostada, sin golpes');
    await tester.pump();
    await tester.tap(confirm);
    await tester.pumpAndSettle();

    expect(repo.notes, ['Ya está acostada, sin golpes']);
    // Atender la caída apaga la alarma.
    expect(alarm.stops, greaterThanOrEqualTo(1));
    // Deja que se cierre el aviso de confirmación.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('confirmar falsa alarma exige justificación y queda registrada',
      (tester) async {
    final repo = await pumpFall(tester);

    await tester.scrollUntilVisible(find.text('Confirmar falsa alarma'), 200);
    await tester.tap(find.text('Confirmar falsa alarma'));
    await tester.pumpAndSettle();

    // Sin justificación, "Confirmar" está deshabilitado.
    final confirm = find.widgetWithText(FilledButton, 'Confirmar');
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'Se le cayó el reloj al velador');
    await tester.pump();
    await tester.tap(confirm);
    await tester.pumpAndSettle();

    expect(repo.falseAlarms, [true]);
    expect(repo.notes, ['Se le cayó el reloj al velador']);
    await tester.scrollUntilVisible(
        find.text('Descartada como falsa alarma.'), 200);
    expect(find.text('Descartada como falsa alarma.'), findsOneWidget);
    // Deja que se cierre el aviso de confirmación.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets(
      'la pantalla de caída muestra nombre, domicilio y última ubicación '
      '(DAC05-84)', (tester) async {
    await pumpFall(tester);

    expect(find.text('Adulto mayor'), findsOneWidget);
    expect(find.text('Elena Ramírez'), findsWidgets);
    expect(find.text('Av. Irarrázaval 2850, depto. 304, Ñuñoa'), findsOneWidget);
    expect(find.text('Última ubicación: -33.45420, -70.60110'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Ver en el mapa'), findsOneWidget);
    // Las coordenadas no se repiten en "Detalles".
    expect(find.text('Latitud'), findsNothing);

    // Fondo de alta visibilidad: encabezado rojo sólido.
    final header =
        tester.widget<Container>(find.byKey(const ValueKey('alert-header')));
    expect((header.decoration! as BoxDecoration).color, AppColors.critical);
  });

  testWidgets('la alarma suena al abrir la caída y se puede silenciar',
      (tester) async {
    await pumpFall(tester);

    expect(alarm.starts, 1);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Silenciar alarma'));
    await tester.pumpAndSettle();

    expect(alarm.stops, 1);
    expect(find.text('Silenciar alarma'), findsNothing);
    // No vuelve a sonar al redibujar la pantalla.
    await tester.pump(const Duration(seconds: 1));
    expect(alarm.starts, 1);
  });

  testWidgets('una alerta que no es caída no hace sonar la alarma',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: fallOverrides(_RecordingAlertsRepo(), RoleType.family),
      child: MaterialApp(
          theme: AppTheme.light(),
          home: const AlertDetailScreen(alertId: 'a-hr-1')),
    ));
    await tester.pumpAndSettle();

    expect(alarm.starts, 0);
    expect(find.text('Adulto mayor'), findsNothing);
  });

  test('caídas y SOS usan el canal de notificación crítico', () {
    expect(PushService.channelFor({'type': 'alert', 'alert_type': 'fall'}).id,
        'critical_alerts');
    expect(PushService.channelFor({'type': 'alert', 'alert_type': 'sos'}).id,
        'critical_alerts');
    expect(
        PushService.channelFor(
            {'type': 'alert', 'alert_type': 'vital_out_of_range'}).id,
        'alerts');
  });

  testWidgets(
      'un push de caída (RemoteMessage) navega con go_router a la pantalla de '
      'acción inmediata (DAC05-194)', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => const Scaffold(body: Text('Inicio'))),
      GoRoute(
        path: '/alerts/:id',
        builder: (_, st) => AlertDetailScreen(alertId: st.pathParameters['id']!),
      ),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: fallOverrides(_RecordingAlertsRepo(), RoleType.family),
      child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Inicio'), findsOneWidget);

    // Lo que entrega FirebaseMessaging al tocar la notificación.
    const message = RemoteMessage(data: {
      'type': 'alert',
      'alert_id': 'a-fall-1',
      'patient_id': 'p-elena',
      'alert_type': 'fall',
    });
    final route = routeForNotification(PushService.tapData(message));
    expect(route, '/alerts/a-fall-1');
    router.push(route!);
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Caída detectada'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Llamar a Emergencias (131)'),
        findsOneWidget);
    expect(alarm.starts, 1);
  });
}
