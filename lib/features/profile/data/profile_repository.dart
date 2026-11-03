import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../domain/models.dart';

abstract class ProfileRepository {
  Future<void> updateProfile({
    String? fullName,
    String? phone,
    String? avatarUrl,
    String? locale,
  });
  Future<NotificationSettings> getNotificationSettings();
  Future<void> updateNotificationSettings(NotificationSettings settings);
  /// Registra el token push del dispositivo; devuelve su device_id.
  Future<String?> registerDevice(String token, String platform);
}

// ---------------------------------------------------------------------------
// HTTP
// ---------------------------------------------------------------------------
class ProfileRepositoryHttp implements ProfileRepository {
  ProfileRepositoryHttp(this._api);
  final ApiClient _api;

  @override
  Future<void> updateProfile({
    String? fullName,
    String? phone,
    String? avatarUrl,
    String? locale,
  }) =>
      _api.patch<void>('/users/me', data: {
        if (fullName != null) 'full_name': fullName,
        if (phone != null) 'phone': phone,
        if (avatarUrl != null) 'avatar_url': avatarUrl,
        if (locale != null) 'locale': locale,
      });

  @override
  Future<NotificationSettings> getNotificationSettings() async {
    final data = await _api
        .get<Map<String, dynamic>>('/users/me/notification-settings');
    return NotificationSettings.fromJson(data);
  }

  @override
  Future<void> updateNotificationSettings(NotificationSettings settings) =>
      _api.put<void>('/users/me/notification-settings',
          data: settings.toJson());

  @override
  Future<String?> registerDevice(String token, String platform) async {
    final res = await _api.post<Map<String, dynamic>>('/users/me/devices',
        data: {'token': token, 'platform': platform});
    return res['device_id'] as String?;
  }
}

// ---------------------------------------------------------------------------
// Mock
// ---------------------------------------------------------------------------
class ProfileRepositoryMock implements ProfileRepository {
  NotificationSettings _settings = const NotificationSettings();

  @override
  Future<void> updateProfile({
    String? fullName,
    String? phone,
    String? avatarUrl,
    String? locale,
  }) async {
    await Future.delayed(const Duration(milliseconds: 350));
  }

  @override
  Future<NotificationSettings> getNotificationSettings() async {
    await Future.delayed(const Duration(milliseconds: 250));
    return _settings;
  }

  @override
  Future<void> updateNotificationSettings(NotificationSettings settings) async {
    await Future.delayed(const Duration(milliseconds: 250));
    _settings = settings;
  }

  @override
  Future<String?> registerDevice(String token, String platform) async {
    await Future.delayed(const Duration(milliseconds: 200));
    return 'dev-mock';
  }
}

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  if (AppConfig.useMocks) return ProfileRepositoryMock();
  return ProfileRepositoryHttp(ref.watch(apiClientProvider));
});
