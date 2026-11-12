// Galería en modo presentación del adulto mayor (AGE-806 / DAC05-29): las
// fotos avanzan solas a pantalla completa y hay un botón de reacción.
import 'package:agecare_app/core/theme/app_theme.dart';
import 'package:agecare_app/features/elder/application/elder_providers.dart';
import 'package:agecare_app/features/elder/data/elder_repository.dart';
import 'package:agecare_app/features/elder/presentation/elder_photos_screen.dart';
import 'package:agecare_app/features/elder/presentation/elder_slideshow_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Repo extends ElderRepositoryMock {
  final reactions = <String>[];

  @override
  Future<void> reactPhoto(String photoId, String reaction) async {
    reactions.add('$photoId:$reaction');
  }
}

void main() {
  Future<_Repo> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _Repo();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        elderPatientIdProvider.overrideWithValue('p-elena'),
        elderRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(
          theme: AppTheme.light(), home: const ElderSlideshowScreen()),
    ));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    return repo;
  }

  testWidgets('las fotos avanzan solas cada 6 segundos', (tester) async {
    await pump(tester);
    expect(find.text('1 de 3'), findsOneWidget);
    expect(find.text('Tus nietos en la playa'), findsOneWidget);

    await tester.pump(ElderSlideshowScreen.interval);
    await tester.pumpAndSettle();
    expect(find.text('2 de 3'), findsOneWidget);
    expect(find.text('La comida del domingo, todos juntos'), findsOneWidget);
  });

  testWidgets('se puede pausar la presentación', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('slideshow-play')));
    await tester.pump(ElderSlideshowScreen.interval * 2);
    await tester.pumpAndSettle();
    expect(find.text('1 de 3'), findsOneWidget);
  });

  testWidgets('el botón grande de corazón envía la reacción', (tester) async {
    final repo = await pump(tester);
    await tester.tap(find.byKey(const Key('slideshow-love')));
    await tester.pump();
    expect(repo.reactions, ['ph-1:love']);
    expect(find.text('¡Enviado!'), findsOneWidget);
    expect(find.text('Le enviaste cariño a María'), findsOneWidget);
  });

  testWidgets('"Ver todas" abre la lista para agregar fotos', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('slideshow-all')));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    expect(find.byType(ElderPhotosScreen), findsOneWidget);
  });
}
