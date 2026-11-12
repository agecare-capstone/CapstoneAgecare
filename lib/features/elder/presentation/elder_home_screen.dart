import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/accessibility/accessibility_settings.dart';
import '../../../core/speech/speech_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/medical_disclaimer.dart';
import '../../alerts/presentation/sos_button.dart';
import '../../auth/application/auth_controller.dart';
import '../../medications/domain/models.dart';
import '../application/elder_providers.dart';
import '../domain/models.dart';
import 'elder_content_screen.dart';
import 'elder_medicines_screen.dart';
import 'elder_slideshow_screen.dart';

/// Pantalla PRINCIPAL de la vista del adulto mayor (shell del rol elder).
///
/// Diseño accesible: saludo grande, fecha en palabras, "Tu día" (próximo
/// remedio, comidas pendientes y próxima cita) y botones con letra grande.
/// Cada acción se lee en voz alta al tocarla y hay un botón de emergencia
/// (SOS) muy visible. El adulto mayor ve sus remedios pero no los modifica.
class ElderHomeScreen extends ConsumerWidget {
  const ElderHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final firstName = _firstName(user?.fullName);
    final patientId = ref.watch(elderPatientIdProvider);
    final speech = ref.read(speechServiceProvider);

    final tiles = <_ElderTile>[
      _ElderTile(
        icon: Icons.video_call_rounded,
        label: 'Llamar a la\nfamilia',
        color: AppColors.primary,
        speak: 'Llamar a la familia',
        onTap: () => context.push(
            patientId == null ? '/chat' : '/chat?patient=$patientId'),
      ),
      _ElderTile(
        icon: Icons.photo_library_rounded,
        label: 'Mis fotos',
        color: const Color(0xFF3D7A45), // secondary oscurecido → ~4.7:1 WCAG AA
        speak: 'Mis fotos',
        // Abre la presentación: las fotos avanzan solas (DAC05-29).
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ElderSlideshowScreen()),
        ),
      ),
      _ElderTile(
        icon: Icons.favorite_rounded,
        label: 'Para ti',
        color: const Color(0xFF8A5C10), // statusWarning oscurecido → ~5.3:1 WCAG AA
        speak: 'Para ti. Noticias, chistes y ejercicios.',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ElderContentScreen()),
        ),
      ),
      _ElderTile(
        icon: Icons.medication_rounded,
        label: 'Mis\nremedios',
        color: const Color(0xFF1F7A44), // statusOk oscurecido → contraste AA
        speak: 'Mis remedios de hoy y de la semana',
        // Solo lectura: el adulto mayor no agrega ni cambia remedios.
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ElderMedicinesScreen()),
        ),
      ),
    ];

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(elderDosesProvider(1));
            ref.invalidate(elderMealsProvider);
            ref.invalidate(elderAppointmentsProvider);
          },
          child: ListView(
            // Espacio abajo para que el botón SOS no tape el contenido.
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Hola, $firstName',
                          style: const TextStyle(
                            fontSize: 38,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _spanishDate(DateTime.now()),
                          style: const TextStyle(
                            fontSize: 24,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _SettingsButton(
                    onLogout: () =>
                        ref.read(authControllerProvider.notifier).logout(),
                  ),
                  const SizedBox(width: 8),
                  _HelpButton(
                    onTap: () => speech.speak(
                      'Esta es tu pantalla de inicio. Arriba ves tu día: tu '
                      'próximo remedio, tus comidas y tu próxima cita. Abajo '
                      'hay botones para llamar a tu familia, ver tus fotos, '
                      'escuchar contenido para ti o revisar tus remedios. El '
                      'botón rojo es para pedir ayuda en una emergencia.',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (patientId != null) ...[
                _TodayAgenda(speech: speech),
                const SizedBox(height: 20),
              ],
              // Botones más bajos y con letra más grande.
              GridView.count(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.45,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  for (final tile in tiles)
                    _ElderTileButton(tile: tile, speech: speech),
                ],
              ),
              const SizedBox(height: 20),
              const MedicalDisclaimer(forElder: true),
            ],
          ),
        ),
      ),
      floatingActionButton: const SosButton(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  static String _firstName(String? fullName) {
    if (fullName == null || fullName.trim().isEmpty) return 'hola';
    return fullName.trim().split(RegExp(r'\s+')).first;
  }

  /// Fecha en español sin depender de datos de locale de intl.
  static String _spanishDate(DateTime d) {
    const days = [
      'lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'
    ];
    const months = [
      'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto',
      'septiembre', 'octubre', 'noviembre', 'diciembre'
    ];
    final day = days[d.weekday - 1];
    final month = months[d.month - 1];
    final capitalized = day[0].toUpperCase() + day.substring(1);
    return '$capitalized ${d.day} de $month';
  }
}

class _ElderTile {
  const _ElderTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.speak,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final String speak;
  final VoidCallback onTap;
}

class _ElderTileButton extends StatelessWidget {
  const _ElderTileButton({required this.tile, required this.speech});

  final _ElderTile tile;
  final SpeechService speech;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tile.speak,
      child: Material(
        color: tile.color,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () {
            speech.speak(tile.speak);
            tile.onTap();
          },
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(tile.icon, size: 34, color: Colors.white),
                const SizedBox(height: 4),
                // Si la pantalla es angosta, el texto se achica en vez de cortarse.
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      tile.label,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        height: 1.1,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Acceso discreto a "Cerrar sesión": icono pequeño y confirmación explícita,
/// para que el adulto mayor no salga de la app por un toque accidental.
class _SettingsButton extends StatelessWidget {
  const _SettingsButton({required this.onLogout});

  final VoidCallback onLogout;

  /// Ajustes del adulto mayor: tamaño de letra, alto contraste y cerrar
  /// sesión (DAC05-94). Los cambios se ven al instante.
  Future<void> _openSettings(BuildContext context) async {
    final logout = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const ElderSettingsSheet(),
    );
    if (logout == true && context.mounted) await _confirm(context);
  }

  Future<void> _confirm(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Quieres cerrar sesión?',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
        content: const Text(
          'Necesitarás tu correo y contraseña para volver a entrar.',
          style: TextStyle(fontSize: 20),
        ),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar', style: TextStyle(fontSize: 20)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('Cerrar sesión', style: TextStyle(fontSize: 20)),
          ),
        ],
      ),
    );
    if (ok == true) onLogout();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Ajustes. Tamaño de letra, contraste y cerrar sesión.',
      child: IconButton(
        key: const Key('elder-settings'),
        onPressed: () => _openSettings(context),
        iconSize: 32,
        color: AppColors.textSecondary,
        tooltip: 'Ajustes',
        icon: const Icon(Icons.settings_outlined),
      ),
    );
  }
}

class _HelpButton extends StatelessWidget {
  const _HelpButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Ayuda. Escuchar cómo usar esta pantalla.',
      child: Material(
        color: AppColors.primary.withValues(alpha: .12),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: const Padding(
            padding: EdgeInsets.all(14),
            child: Icon(Icons.volume_up_rounded,
                size: 36, color: AppColors.primaryDark),
          ),
        ),
      ),
    );
  }
}

/// "Tu día": próximo remedio, comidas pendientes y próxima cita médica.
class _TodayAgenda extends ConsumerWidget {
  const _TodayAgenda({required this.speech});

  final SpeechService speech;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final doses = ref.watch(elderDosesProvider(1));
    final meals = ref.watch(elderMealsProvider);
    final appointments = ref.watch(elderAppointmentsProvider);
    final now = DateTime.now();

    final pending = (doses.valueOrNull ?? const <Dose>[])
        .where((d) => d.status == DoseStatus.pending || d.status == DoseStatus.skipped)
        .toList()
      ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    final next = pending.where((d) => !d.scheduledAt.isBefore(now)).firstOrNull ??
        pending.firstOrNull;
    final medText = doses.isLoading
        ? 'Cargando…'
        : next == null
            ? 'Ya no te quedan remedios por hoy'
            : '${next.timeLabel} · ${next.medicationName} ${doseAmount(next)}'.trim();

    final pendingMeals = (meals.valueOrNull ?? const <AgendaTask>[])
        .where((t) => t.isPending)
        .toList();
    final mealText = meals.isLoading
        ? 'Cargando…'
        : pendingMeals.isEmpty
            ? 'No tienes comidas pendientes'
            : pendingMeals
                .map((t) => t.time == null ? t.title : '${t.time} · ${t.title}')
                .join('\n');

    final visit = (appointments.valueOrNull ?? const <AgendaTask>[]).firstOrNull;
    final visitText = appointments.isLoading
        ? 'Cargando…'
        : visit == null
            ? 'No tienes citas esta semana'
            : '${elderDayLabel(visit.date)}${visit.time == null ? '' : ', ${visit.time}'}\n${visit.title}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Tu día',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        const SizedBox(height: 10),
        _AgendaCard(
          key: const Key('agenda-medicine'),
          icon: Icons.medication_rounded,
          color: const Color(0xFF1F7A44),
          title: 'Próximo remedio',
          text: medText,
          speech: speech,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ElderMedicinesScreen()),
          ),
        ),
        const SizedBox(height: 10),
        _AgendaCard(
          key: const Key('agenda-meals'),
          icon: Icons.restaurant_rounded,
          color: const Color(0xFF8A5C10),
          title: 'Comidas pendientes',
          text: mealText,
          speech: speech,
        ),
        const SizedBox(height: 10),
        _AgendaCard(
          key: const Key('agenda-appointment'),
          icon: Icons.event_rounded,
          color: AppColors.primaryDark,
          title: 'Próxima cita médica',
          text: visitText,
          speech: speech,
        ),
      ],
    );
  }
}

class _AgendaCard extends StatelessWidget {
  const _AgendaCard({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.text,
    required this.speech,
    this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String text;
  final SpeechService speech;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final spoken = '$title. ${text.replaceAll('\n', '. ').replaceAll(' · ', ', ')}';
    return Semantics(
      button: true,
      label: spoken,
      excludeSemantics: true,
      child: Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: color.withValues(alpha: .35), width: 1.5),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () {
            speech.speak(spoken);
            onTap?.call();
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 34, color: color),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: color)),
                      const SizedBox(height: 2),
                      Text(text,
                          style: const TextStyle(
                              fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.textPrimary, height: 1.25)),
                    ],
                  ),
                ),
                if (onTap != null)
                  const Icon(Icons.chevron_right_rounded, size: 34, color: AppColors.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Hoja de ajustes del adulto mayor (DAC05-94): botones grandes para elegir el
/// tamaño de letra y un interruptor de alto contraste.
class ElderSettingsSheet extends ConsumerWidget {
  const ElderSettingsSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(accessibilityProvider);
    final controller = ref.read(accessibilityProvider.notifier);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Ajustes',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            const Text('Tamaño de letra',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            for (final option in TextSizeOption.values)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _SizeChoice(
                  option: option,
                  selected: settings.textSize == option,
                  onTap: () => controller.setTextSize(option),
                ),
              ),
            const SizedBox(height: 8),
            Material(
              color: AppColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: AppColors.divider, width: 1.5),
              ),
              child: SwitchListTile(
                key: const Key('high-contrast-switch'),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                title: const Text('Alto contraste',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                subtitle: const Text('Colores más fuertes y letra en negrita',
                    style: TextStyle(fontSize: 18)),
                value: settings.highContrast,
                onChanged: controller.setHighContrast,
              ),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.redAccent,
                minimumSize: const Size.fromHeight(56),
              ),
              onPressed: () => Navigator.of(context).pop(true),
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Cerrar sesión', style: TextStyle(fontSize: 20)),
            ),
          ],
        ),
      ),
    );
  }
}

class _SizeChoice extends StatelessWidget {
  const _SizeChoice({required this.option, required this.selected, required this.onTap});

  final TextSizeOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: 'Letra ${option.label}',
      excludeSemantics: true,
      child: Material(
        key: Key('text-size-${option.key}'),
        color: selected ? AppColors.primary.withValues(alpha: .10) : AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: selected ? AppColors.primary : AppColors.divider,
            width: selected ? 2.5 : 1.5,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                // Muestra del tamaño: la "A" crece con cada opción.
                SizedBox(
                  width: 48,
                  child: Text('A',
                      textScaler: TextScaler.noScaling,
                      style: TextStyle(
                          fontSize: 22 * option.scale, fontWeight: FontWeight.w800)),
                ),
                Expanded(
                  child: Text(option.label,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
                ),
                if (selected)
                  const Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 30),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
