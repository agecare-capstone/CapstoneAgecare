// Flujo de caída con la app cerrada (AGE-505 / DAC05-86).
//
// Con la app cerrada, el toque en el push llega antes de que se restaure la
// sesión. La pantalla de la alerta debe abrirse igual apenas haya sesión, y
// "Atrás" debe volver a la app (/home), no al splash.
import 'package:agecare_app/core/notifications/notification_navigator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Router mínimo con el mismo redirect de autenticación que la app.
GoRouter _router(ValueNotifier<bool> loggedIn) => GoRouter(
      initialLocation: '/splash',
      refreshListenable: loggedIn,
      redirect: (_, state) {
        final loc = state.matchedLocation;
        if (!loggedIn.value) return loc == '/splash' ? null : '/splash';
        if (notificationEntryRoutes.contains(loc)) return '/home';
        return null;
      },
      routes: [
        for (final path in ['/splash', '/login', '/home', '/alerts'])
          GoRoute(path: path, builder: (_, __) => Text('pantalla $path')),
        GoRoute(
          path: '/alerts/:id',
          builder: (_, st) => Text('alerta ${st.pathParameters['id']}'),
        ),
      ],
    );

void main() {
  group('routeForNotification', () {
    test('caída con id abre su pantalla', () {
      expect(
          routeForNotification(
              {'type': 'CRITICAL_FALL', 'alert_id': 'a-fall-1'}),
          '/alerts/a-fall-1');
    });

    test('caída sin id abre el centro de alertas', () {
      expect(routeForNotification({'type': 'CRITICAL_FALL'}), '/alerts');
      expect(routeForNotification({'type': 'alert'}), '/alerts');
    });

    test('otros tipos sin destino no navegan', () {
      expect(routeForNotification({'type': 'chat'}), isNull);
      expect(routeForNotification({}), isNull);
    });
  });

  testWidgets(
      'con la app cerrada, la caída se abre cuando termina de cargar la sesión',
      (tester) async {
    final loggedIn = ValueNotifier(false);
    final router = _router(loggedIn);
    final nav = NotificationNavigator(
      router: () => router,
      isLoggedIn: () => loggedIn.value,
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    expect(find.text('pantalla /splash'), findsOneWidget);

    // 1. Llega el toque del push mientras la sesión todavía se restaura.
    nav.open({'type': 'CRITICAL_FALL', 'alert_id': 'a-fall-1'});
    await tester.pumpAndSettle();
    expect(nav.pendingRoute, '/alerts/a-fall-1');
    expect(find.text('pantalla /splash'), findsOneWidget);

    // 2. La sesión queda lista: se abre la pantalla de la caída.
    loggedIn.value = true;
    nav.flush();
    await tester.pumpAndSettle();
    expect(nav.pendingRoute, isNull);
    expect(find.text('alerta a-fall-1'), findsOneWidget);

    // 3. "Atrás" vuelve a la app, no al splash.
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('pantalla /home'), findsOneWidget);
  });

  testWidgets('con sesión iniciada, la caída se abre de inmediato',
      (tester) async {
    final loggedIn = ValueNotifier(true);
    final router = _router(loggedIn);
    final nav = NotificationNavigator(
      router: () => router,
      isLoggedIn: () => loggedIn.value,
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(find.text('pantalla /home'), findsOneWidget);

    nav.open({'type': 'CRITICAL_FALL', 'alert_id': 'a-fall-2'});
    await tester.pumpAndSettle();

    expect(find.text('alerta a-fall-2'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('pantalla /home'), findsOneWidget);
  });
}
