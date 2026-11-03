import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/notifications/push_service.dart';
import '../data/auth_repository.dart';
import '../domain/models.dart';

/// Estado global de autenticación.
sealed class AuthState {
  const AuthState();
}

class AuthLoading extends AuthState {
  const AuthLoading();
}

class Unauthenticated extends AuthState {
  const Unauthenticated();
}

class Authenticated extends AuthState {
  const Authenticated(this.user);
  final User user;
}

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    _restoreSession();
    return const AuthLoading();
  }

  AuthRepository get _repo => ref.read(authRepositoryProvider);

  Future<void> _restoreSession() async {
    final tokens = ref.read(tokenStorageProvider);
    if (await tokens.hasSession) {
      try {
        final user = await _repo.me();
        state = Authenticated(user);
        return;
      } catch (_) {
        await tokens.clear();
      }
    }
    state = const Unauthenticated();
  }

  Future<void> login(String email, String password) async {
    final session = await _repo.login(email: email, password: password);
    await ref
        .read(tokenStorageProvider)
        .save(access: session.accessToken, refresh: session.refreshToken);
    state = Authenticated(session.user);
  }

  Future<void> register({
    required String fullName,
    required String email,
    required String password,
    String? phone,
    String? invitationToken,
  }) async {
    final session = await _repo.register(
      fullName: fullName,
      email: email,
      password: password,
      phone: phone,
      invitationToken: invitationToken,
    );
    await ref
        .read(tokenStorageProvider)
        .save(access: session.accessToken, refresh: session.refreshToken);
    // Tras registro con invitación las membresías llegan en /users/me.
    final user =
        invitationToken != null ? await _repo.me() : session.user;
    state = Authenticated(user);
  }

  Future<void> recoverPassword(String email) => _repo.requestPasswordRecovery(email);

  /// Refresca el perfil (ej. tras crear un paciente o aceptar invitación).
  Future<void> refreshProfile() async {
    if (state is! Authenticated) return;
    state = Authenticated(await _repo.me());
  }

  Future<void> logout() async {
    final tokens = ref.read(tokenStorageProvider);
    final refresh = await tokens.refreshToken;
    if (refresh != null) {
      try {
        // Desactiva el push de este teléfono para la cuenta que sale.
        await _repo.logout(refresh, deviceId: PushService.instance.deviceId);
      } catch (_) {/* best effort */}
    }
    PushService.instance.deviceId = null;
    await tokens.clear();
    state = const Unauthenticated();
  }

  void onSessionExpired() => state = const Unauthenticated();
}

final authControllerProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new);

/// Usuario actual (null si no hay sesión).
final currentUserProvider = Provider<User?>((ref) {
  final state = ref.watch(authControllerProvider);
  return state is Authenticated ? state.user : null;
});
