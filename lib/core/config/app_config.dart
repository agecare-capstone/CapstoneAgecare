/// Configuración de entorno de la app.
///
/// Se controla con --dart-define en tiempo de compilación:
///   flutter run --dart-define=USE_MOCKS=true
///   flutter run --dart-define=API_BASE_URL=https://api-dev.agecare.app --dart-define=USE_MOCKS=false
///   flutter run --dart-define=SPIKE_APP_ID=1000
class AppConfig {
  AppConfig._();

  /// true = repositorios en memoria con datos demo (no requiere backend).
  /// Por defecto true para desarrollo y testing offline; en CI/producción
  /// se sobrescribe con --dart-define=USE_MOCKS=false.
  static const bool useMocks =
      bool.fromEnvironment('USE_MOCKS', defaultValue: true);

  /// Backend AgeCare en Azure. Para usar el backend de otro equipo que siga
  /// el contrato de Alloxentric basta con --dart-define=API_BASE_URL=...
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://agecare-api-xnjbc.azurewebsites.net',
  );

  /// Application ID de Spike API (https://docs.spikeapi.com).
  static const int spikeAppId = int.fromEnvironment('SPIKE_APP_ID', defaultValue: 0);

  /// true = usa el simulador de wearable en lugar del SDK de Spike.
  /// El simulador es la fuente por defecto mientras no haya SPIKE_APP_ID.
  static const bool useWearableSimulator = bool.fromEnvironment(
    'USE_WEARABLE_SIMULATOR',
    defaultValue: true,
  );

  static const String appName = 'AgeCare';
  static const String apiVersion = '/api/v1';
}
