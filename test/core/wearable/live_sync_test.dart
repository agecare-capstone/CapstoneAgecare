// Sincronización con el reloj cada 10 segundos mientras la app está abierta.
import 'dart:async';

import 'package:agecare_app/core/wearable/live_sync.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('sincroniza cada 10 segundos y se detiene al pausar', (tester) async {
    var ticks = 0;
    final live = LiveSync(onTick: () async => ticks++);
    live.start();
    await tester.pump(const Duration(seconds: 9));
    expect(ticks, 0);
    await tester.pump(const Duration(seconds: 1));
    expect(ticks, 1);
    await tester.pump(const Duration(seconds: 20));
    expect(ticks, 3);

    live.stop();
    expect(live.isRunning, isFalse);
    await tester.pump(const Duration(seconds: 30));
    expect(ticks, 3);
  });

  testWidgets('si una vuelta no termina, la siguiente se salta', (tester) async {
    var started = 0;
    final pending = Completer<void>();
    final live = LiveSync(onTick: () {
      started++;
      return pending.future;
    });
    live.start();
    await tester.pump(const Duration(seconds: 30));
    expect(started, 1);
    pending.complete();
    await tester.pump(const Duration(seconds: 10));
    expect(started, 2);
    live.stop();
  });

  testWidgets('un error de red no corta las siguientes vueltas', (tester) async {
    var calls = 0;
    final live = LiveSync(onTick: () async {
      calls++;
      throw Exception('sin conexión');
    });
    live.start();
    await tester.pump(const Duration(seconds: 30));
    expect(calls, 3);
    live.stop();
  });
}
