import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Tamaño de letra elegido por el usuario (AGE-NEW-01 / DAC05-94).
enum TextSizeOption {
  normal('normal', 'Normal', 1.0),
  large('large', 'Grande', 1.2),
  extraLarge('extraLarge', 'Extra grande', 1.4);

  const TextSizeOption(this.key, this.label, this.scale);

  final String key;
  final String label;
  final double scale;

  static TextSizeOption fromKey(String? key) => TextSizeOption.values
      .firstWhere((o) => o.key == key, orElse: () => TextSizeOption.normal);
}

/// Ajustes de accesibilidad visual: tamaño de letra y alto contraste.
@immutable
class AccessibilitySettings {
  const AccessibilitySettings({
    this.textSize = TextSizeOption.normal,
    this.highContrast = false,
  });

  final TextSizeOption textSize;
  final bool highContrast;

  AccessibilitySettings copyWith(
          {TextSizeOption? textSize, bool? highContrast}) =>
      AccessibilitySettings(
        textSize: textSize ?? this.textSize,
        highContrast: highContrast ?? this.highContrast,
      );
}

/// Dónde se guardan los ajustes en el equipo. Se puede reemplazar en pruebas.
abstract class AccessibilityStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class SecureAccessibilityStore implements AccessibilityStore {
  static const _storage = FlutterSecureStorage();

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
}

final accessibilityStoreProvider =
    Provider<AccessibilityStore>((ref) => SecureAccessibilityStore());

/// Ajustes de accesibilidad persistentes. Los cambios se aplican al instante
/// en toda la app (sin reiniciar) y se recuerdan al volver a abrirla.
class AccessibilityController extends Notifier<AccessibilitySettings> {
  static const textSizeKey = 'a11y_text_size';
  static const highContrastKey = 'a11y_high_contrast';

  @override
  AccessibilitySettings build() {
    _load();
    return const AccessibilitySettings();
  }

  AccessibilityStore get _store => ref.read(accessibilityStoreProvider);

  Future<void> _load() async {
    try {
      final size = await _store.read(textSizeKey);
      final contrast = await _store.read(highContrastKey);
      state = AccessibilitySettings(
        textSize: TextSizeOption.fromKey(size),
        highContrast: contrast == 'true',
      );
    } catch (_) {
      // Sin almacenamiento disponible: se usan los valores por defecto.
    }
  }

  Future<void> setTextSize(TextSizeOption option) async {
    state = state.copyWith(textSize: option);
    try {
      await _store.write(textSizeKey, option.key);
    } catch (_) {}
  }

  Future<void> setHighContrast(bool value) async {
    state = state.copyWith(highContrast: value);
    try {
      await _store.write(highContrastKey, value.toString());
    } catch (_) {}
  }
}

final accessibilityProvider =
    NotifierProvider<AccessibilityController, AccessibilitySettings>(
        AccessibilityController.new);

/// Aplica los ajustes a todo lo que cuelga de [child]: escala del texto y,
/// con alto contraste, texto en negrita y colores más intensos.
class AccessibilityScope extends ConsumerWidget {
  const AccessibilityScope({super.key, required this.child});

  final Widget child;

  /// Aumenta el contraste de todos los colores alrededor del gris medio:
  /// los grises de los textos secundarios pasan a casi negro y los fondos de
  /// color se oscurecen, mientras el blanco sigue blanco.
  static const contrastMatrix = <double>[
    1.6, 0, 0, 0, -38, //
    0, 1.6, 0, 0, -38, //
    0, 0, 1.6, 0, -38, //
    0, 0, 0, 1, 0, //
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(accessibilityProvider);
    final media = MediaQuery.of(context);
    final scaled = MediaQuery(
      data: media.copyWith(
        textScaler: TextScaler.linear(
            media.textScaler.scale(1) * settings.textSize.scale),
        boldText: media.boldText || settings.highContrast,
        highContrast: settings.highContrast,
      ),
      child: child,
    );
    if (!settings.highContrast) return scaled;
    return ColorFiltered(
      key: const Key('high-contrast-filter'),
      colorFilter: const ColorFilter.matrix(contrastMatrix),
      child: scaled,
    );
  }
}
