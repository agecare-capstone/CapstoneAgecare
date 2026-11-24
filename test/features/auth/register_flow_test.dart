// Registro: crea la cuenta y vuelve al login con el correo listo; no abre
// sesión sola (la persona entra con su contraseña).
import 'package:agecare_app/core/network/api_client.dart';
import 'package:agecare_app/core/storage/token_storage.dart';
import 'package:agecare_app/features/auth/application/auth_controller.dart';
import 'package:agecare_app/features/auth/data/auth_repository.dart';
import 'package:agecare_app/features/auth/domain/models.dart';
import 'package:agecare_app/features/auth/presentation/login_screen.dart';
import 'package:agecare_app/features/auth/presentation/register_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _FakeTokens extends TokenStorage {
  final saved = <String>[];

  @override
  Future<bool> get hasSession async => false;

  @override
  Future<void> save({required String access, required String refresh}) async => saved.add(access);

  @override
  Future<void> clear() async {}
}

class _RecordingRepo extends AuthRepositoryMock {
  final registered = <String>[];
  final codes = <String?>[];

  @override
  Future<AuthSession> register({
    required String fullName,
    required String email,
    required String password,
    String? phone,
    String? invitationToken,
  }) async {
    registered.add(email);
    codes.add(invitationToken);
    return super.register(fullName: fullName, email: email, password: password, phone: phone);
  }
}

void main() {
  testWidgets('al crear la cuenta vuelve al login con el correo y sin sesión', (tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final tokens = _FakeTokens();
    final repo = _RecordingRepo();
    final router = GoRouter(initialLocation: '/login', routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),
    ]);
    final container = ProviderContainer(overrides: [
      tokenStorageProvider.overrideWithValue(tokens),
      authRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Regístrate'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Nombre completo'), 'Ana Soto');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Correo electrónico'), 'ana.soto@example.com');
    await tester.enterText(find.widgetWithText(TextFormField, 'Contraseña'), 'clave-segura-1');
    await tester.tap(find.widgetWithText(FilledButton, 'Crear cuenta'));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(repo.registered, ['ana.soto@example.com'], reason: 'la cuenta se crea en el servidor');
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(RegisterScreen), findsNothing);
    expect(find.text('ana.soto@example.com'), findsOneWidget);
    expect(find.textContaining('Cuenta creada'), findsOneWidget);
    expect(tokens.saved, isEmpty, reason: 'no se abre sesión sola');
    expect(container.read(authControllerProvider), isA<Unauthenticated>());
    expect(repo.codes, [null], reason: 'sin código: cuenta de familiar');
  });

  testWidgets('la cuidadora puede crear su cuenta con el código de invitación', (tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _RecordingRepo();
    final router = GoRouter(initialLocation: '/login', routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),
    ]);
    final container = ProviderContainer(overrides: [
      tokenStorageProvider.overrideWithValue(_FakeTokens()),
      authRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Regístrate'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Nombre completo'), 'Rosa Pérez');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Correo electrónico'), 'rosa@example.com');
    await tester.enterText(find.widgetWithText(TextFormField, 'Contraseña'), 'clave-segura-1');

    // Un código mal escrito no se envía.
    await tester.enterText(find.byKey(const Key('register-code')), '12');
    await tester.tap(find.widgetWithText(FilledButton, 'Crear cuenta'));
    await tester.pumpAndSettle();
    expect(find.text('El código tiene 6 dígitos'), findsOneWidget);
    expect(repo.registered, isEmpty);

    await tester.enterText(find.byKey(const Key('register-code')), '482913');
    await tester.tap(find.widgetWithText(FilledButton, 'Crear cuenta'));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(repo.codes, ['482913']);
    expect(find.byType(LoginScreen), findsOneWidget);
  });
}
