import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../application/caregiver_providers.dart';
import '../data/caregiver_repository.dart';
import '../domain/models.dart';

/// Pantalla de perfil profesional de la cuidadora.
/// Muestra los campos del perfil y permite publicarlo en el marketplace
/// con el botón "Publicar Perfil" (AGE-906 / DAC05-34).
class CaregiverProfessionalProfileScreen extends ConsumerWidget {
  const CaregiverProfessionalProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(caregiverProfileProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Mi Perfil Profesional')),
      body: profileAsync.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
          message: e.toString(),
          onRetry: () => ref.invalidate(caregiverProfileProvider),
        ),
        data: (profile) => _ProfileBody(profile: profile),
      ),
    );
  }
}

class _ProfileBody extends ConsumerStatefulWidget {
  const _ProfileBody({required this.profile});
  final CaregiverProfile profile;

  @override
  ConsumerState<_ProfileBody> createState() => _ProfileBodyState();
}

class _ProfileBodyState extends ConsumerState<_ProfileBody> {
  late CaregiverProfile _profile;
  bool _publishing = false;

  @override
  void initState() {
    super.initState();
    _profile = widget.profile;
  }

  Future<void> _publish() async {
    setState(() => _publishing = true);
    try {
      final updated =
          await ref.read(caregiverRepositoryProvider).publishProfile();
      ref.invalidate(caregiverProfileProvider);
      if (mounted) {
        setState(() => _profile = updated);
        showAppSnackBar(
          context,
          'Tu perfil ya es visible en el marketplace.',
        );
      }
    } catch (e) {
      if (mounted) {
        showAppSnackBar(context, e.toString(), error: true);
      }
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _profile;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        // Estado de publicación
        _PublicationBanner(isPublished: p.isPublished),
        const SizedBox(height: 20),

        // Resumen profesional
        _Section(
          title: 'Encabezado profesional',
          child: Text(
            p.headline.isNotEmpty
                ? p.headline
                : 'Sin encabezado. Edita tu perfil para agregar uno.',
            style: const TextStyle(fontSize: 16, color: AppColors.textPrimary),
          ),
        ),
        const SizedBox(height: 16),

        _Section(
          title: 'Sobre mí',
          child: Text(
            p.bio.isNotEmpty
                ? p.bio
                : 'Sin descripción. Edita tu perfil para agregar una.',
            style: const TextStyle(fontSize: 15, color: AppColors.textPrimary),
          ),
        ),
        const SizedBox(height: 16),

        // Datos clave
        AppCard(
          child: Column(
            children: [
              _InfoRow(
                icon: Icons.workspace_premium_outlined,
                label: '${p.yearsExperience} años de experiencia',
              ),
              if (p.zones.isNotEmpty)
                _InfoRow(
                  icon: Icons.location_on_outlined,
                  label: 'Zonas: ${p.zones.join(', ')}',
                ),
              if (p.languages.isNotEmpty)
                _InfoRow(
                  icon: Icons.translate_rounded,
                  label: 'Idiomas: ${p.languages.join(', ')}',
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        if (p.specialties.isNotEmpty) ...[
          _Section(
            title: 'Especialidades',
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [for (final s in p.specialties) _Pill(label: s)],
            ),
          ),
          const SizedBox(height: 16),
        ],

        if (p.certifications.isNotEmpty) ...[
          _Section(
            title: 'Certificaciones',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final c in p.certifications)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        const Icon(Icons.verified_outlined,
                            size: 18, color: AppColors.secondary),
                        const SizedBox(width: 8),
                        Expanded(child: Text(c)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Botón principal
        if (!p.isPublished)
          SizedBox(
            height: 56,
            child: FilledButton.icon(
              onPressed: _publishing ? null : _publish,
              icon: _publishing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.public_rounded),
              label: Text(
                _publishing ? 'Publicando…' : 'Publicar Perfil',
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
          )
        else
          OutlinedButton.icon(
            onPressed: null,
            icon: const Icon(Icons.check_circle_rounded,
                color: AppColors.secondary),
            label: const Text(
              'Perfil publicado en el marketplace',
              style: TextStyle(color: AppColors.secondary),
            ),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              side: const BorderSide(color: AppColors.secondary),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Widgets auxiliares
// ---------------------------------------------------------------------------

class _PublicationBanner extends StatelessWidget {
  const _PublicationBanner({required this.isPublished});
  final bool isPublished;

  @override
  Widget build(BuildContext context) {
    if (isPublished) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.secondary.withValues(alpha: .10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.secondary.withValues(alpha: .3)),
        ),
        child: const Row(
          children: [
            Icon(Icons.visibility_rounded,
                color: AppColors.secondary, size: 22),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Tu ficha es visible para las familias en el marketplace.',
                style: TextStyle(
                    color: AppColors.secondary, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.statusWarning.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: AppColors.statusWarning.withValues(alpha: .3)),
      ),
      child: const Row(
        children: [
          Icon(Icons.visibility_off_rounded,
              color: AppColors.statusWarning, size: 22),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Tu perfil aún no es visible. Pulsa "Publicar Perfil" para aparecer en el marketplace.',
              style: TextStyle(
                  color: AppColors.statusWarning,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(label)),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
            fontSize: 12,
            color: AppColors.primaryDark,
            fontWeight: FontWeight.w600),
      ),
    );
  }
}
