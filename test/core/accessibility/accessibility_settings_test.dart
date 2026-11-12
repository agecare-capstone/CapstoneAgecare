// Accesibilidad visual ajustable (AGE-NEW-01 / DAC05-94): tamaño de letra
// persistente, alto contraste y cambios sin reiniciar la app.
import 'package:agecare_app/core/accessibility/accessibility_settings.dart';
import 'package:agecare_app/core/theme/app_theme.dart';
import 'package:agecare_app/features/elder/presentation/elder_home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryStore implements AccessibilityStore {
  _MemoryStore([Map<String, String>? initial]) : values = {...?initial};
  final Map<String, String> values;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

/// Muestra el tamaño efectivo de una letra de 10 px y si hay negrita.
class _Probe extends StatelessWidget {
  const _Probe();

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Text('escala ${media.textScaler.scale(10).toStringAsFixed(1)} '
        'negrita ${media.boldText}');
  }
}

void main() {
  Future<ProviderContainer> pumpScope(
      WidgetTester tester, _MemoryStore store) async {
    final container = ProviderContainer(
        overrides: [accessibilityStoreProvider.overrideWithValue(store)]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        builder: (context, child) => AccessibilityScope(child: child!),
        home: const Scaffold(body: _Probe()),
      ),
    ));
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('el tamaño y el contraste se aplican al instante, sin reiniciar',
      (tester) async {
    final store = _MemoryStore();
    final container = await pumpScope(tester, store);
    expect(find.text('escala 10.0 negrita false'), findsOneWidget);
    expect(find.byKey(const Key('high-contrast-filter')), findsNothing);

    await container
        .read(accessibilityProvider.notifier)
        .setTextSize(TextSizeOption.extraLarge);
    await tester.pump();
    expect(find.text('escala 14.0 negrita false'), findsOneWidget);

    await container.read(accessibilityProvider.notifier).setHighContrast(true);
    await tester.pump();
    expect(find.text('escala 14.0 negrita true'), findsOneWidget);
    expect(find.byKey(const Key('high-contrast-filter')), findsOneWidget);

    // Queda guardado en el equipo.
    expect(store.values, {
      AccessibilityController.textSizeKey: 'extraLarge',
      AccessibilityController.highContrastKey: 'true',
    });
  });

  testWidgets('al abrir la app se recuerdan los ajustes guardados',
      (tester) async {
    await pumpScope(
        tester,
        _MemoryStore({
          AccessibilityController.textSizeKey: 'large',
          AccessibilityController.highContrastKey: 'true',
        }));
    expect(find.text('escala 12.0 negrita true'), findsOneWidget);
  });

  testWidgets('el adulto mayor cambia la letra y el contraste desde Ajustes',
      (tester) async {
    tester.view.physicalSize = const Size(430, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = _MemoryStore();
    final container = ProviderContainer(
        overrides: [accessibilityStoreProvider.overrideWithValue(store)]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: ElderSettingsSheet()),
      ),
    ));

    await tester.tap(find.byKey(const Key('text-size-large')));
    await tester.pump();
    expect(
        container.read(accessibilityProvider).textSize, TextSizeOption.large);

    await tester.tap(find.byKey(const Key('high-contrast-switch')));
    await tester.pump();
    expect(container.read(accessibilityProvider).highContrast, isTrue);
    expect(store.values[AccessibilityController.textSizeKey], 'large');
    expect(find.text('Cerrar sesión'), findsOneWidget);
  });
}
