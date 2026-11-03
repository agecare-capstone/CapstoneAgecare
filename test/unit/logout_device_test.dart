// Cerrar sesión desactiva el push del teléfono (DAC05-193): si no, el
// dispositivo seguiría recibiendo las alertas de la cuenta que salió.
import 'package:agecare_app/core/network/api_client.dart';
import 'package:agecare_app/core/notifications/push_service.dart';
import 'package:agecare_app/core/storage/token_storage.dart';
import 'package:agecare_app/features/auth/application/auth_controller.dart';
import 'package:agecare_app/features/auth/data/auth_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Sesión guardada en memoria, sin almacenamiento seguro del sistema.
class _FakeTokens extends TokenStorage {
  @override
  Future<String?> get refreshToken async => 'refresh-1';

  @override
  Future<bool> get hasSession async => false;

  @override
  Future<void> clear() async {}
}

/// Registra con qué dispositivo se pidió el logout.
class _RecordingAuthRepo extends AuthRepositoryMock {
  final deviceIds = <String?>[];

  @override
  Future<void> logout(String refreshToken, {String? deviceId}) async {
    deviceIds.add(deviceId);
  }
}

void main() {
  test('el logout envía el device_id y lo olvida', () async {
    final repo = _RecordingAuthRepo();
    final container = ProviderContainer(overrides: [
      tokenStorageProvider.overrideWithValue(_FakeTokens()),
      authRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(container.dispose);

    PushService.instance.deviceId = 'device-1';
    container.read(authControllerProvider);
    await container.read(authControllerProvider.notifier).logout();

    expect(repo.deviceIds, ['device-1']);
    expect(PushService.instance.deviceId, isNull);
    expect(container.read(authControllerProvider), isA<Unauthenticated>());
  });
}
