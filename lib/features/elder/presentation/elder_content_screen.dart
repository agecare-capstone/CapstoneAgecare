import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/speech/speech_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../application/elder_providers.dart';
import '../domain/models.dart';

/// Feed "Para ti": tarjetas grandes de entretenimiento (noticias, chistes,
/// recuerdos, ejercicios suaves, consejos) con botón "Escuchar" que activa
/// el motor TTS nativo y controles grandes de pausa (AGE-807 / DAC05-30).
class ElderContentScreen extends ConsumerStatefulWidget {
  const ElderContentScreen({super.key});

  @override
  ConsumerState<ElderContentScreen> createState() =>
      _ElderContentScreenState();
}

class _ElderContentScreenState extends ConsumerState<ElderContentScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  // Id del ítem que se está leyendo actualmente (null = ninguno).
  String? _playingId;
  bool _paused = false;

  static const _tabFilters = <String?>[null, 'news', 'joke'];
  static const _tabLabels = ['Todos', 'Noticias', 'Chistes'];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: _tabFilters.length, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _listen(ContentItem item) async {
    final speech = ref.read(speechServiceProvider);
    if (_playingId == item.id && !_paused) {
      // Mismo ítem reproduciéndose → pausa.
      await speech.pausePlayback();
      setState(() => _paused = true);
      return;
    }
    if (_playingId == item.id && _paused) {
      // Mismo ítem pausado → reanuda.
      await speech.resumePlayback();
      setState(() => _paused = false);
      return;
    }
    // Ítem diferente: detiene el anterior y empieza este.
    if (_playingId != null) await speech.stopPlayback();
    setState(() {
      _playingId = item.id;
      _paused = false;
    });
    try {
      await speech.speak(item.spokenText);
    } finally {
      if (mounted) setState(() => _playingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Para ti',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
        toolbarHeight: 72,
        bottom: TabBar(
          controller: _tabs,
          labelStyle:
              const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          unselectedLabelStyle: const TextStyle(fontSize: 18),
          tabs: [
            for (final label in _tabLabels) Tab(text: label),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          for (final filter in _tabFilters)
            _FeedTab(
              filter: filter,
              playingId: _playingId,
              paused: _paused,
              onListen: _listen,
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab de feed
// ---------------------------------------------------------------------------
class _FeedTab extends ConsumerWidget {
  const _FeedTab({
    required this.filter,
    required this.playingId,
    required this.paused,
    required this.onListen,
  });

  final String? filter;
  final String? playingId;
  final bool paused;
  final Future<void> Function(ContentItem) onListen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feedAsync = ref.watch(contentFeedProvider(filter));

    return feedAsync.when(
      loading: () => const LoadingView(),
      error: (e, _) => ErrorView(
        message:
            e is Exception ? e.toString() : 'No se pudo cargar el contenido.',
        onRetry: () => ref.invalidate(contentFeedProvider(filter)),
      ),
      data: (items) {
        if (items.isEmpty) {
          return const EmptyView(
            icon: Icons.favorite_rounded,
            title: 'Nada por ahora',
            subtitle: 'Vuelve más tarde para ver contenido nuevo.',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 20),
          itemBuilder: (context, i) => _ContentCard(
            item: items[i],
            isPlaying: playingId == items[i].id && !paused,
            isPaused: playingId == items[i].id && paused,
            onListen: () => onListen(items[i]),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Tarjeta de contenido
// ---------------------------------------------------------------------------
class _ContentCard extends StatelessWidget {
  const _ContentCard({
    required this.item,
    required this.isPlaying,
    required this.isPaused,
    required this.onListen,
  });

  final ContentItem item;
  final bool isPlaying;
  final bool isPaused;
  final VoidCallback onListen;

  @override
  Widget build(BuildContext context) {
    final color = item.type.color;
    final btnIcon = isPlaying
        ? Icons.pause_circle_filled_rounded
        : isPaused
            ? Icons.play_circle_filled_rounded
            : Icons.volume_up_rounded;
    final btnLabel = isPlaying
        ? 'Pausar'
        : isPaused
            ? 'Continuar'
            : 'Escuchar';

    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (item.imageUrl != null && item.imageUrl!.isNotEmpty)
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Image.network(
                  item.imageUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      Container(color: color.withValues(alpha: .08)),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(item.type.icon, size: 32, color: color),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      item.type.label,
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: color),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  item.title,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  item.body,
                  style: const TextStyle(
                    fontSize: 22,
                    color: AppColors.textPrimary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 18),
                // Barra de estado de reproducción
                if (isPlaying || isPaused) ...[
                  _PlaybackBar(
                      color: color, isPlaying: isPlaying, isPaused: isPaused),
                  const SizedBox(height: 12),
                ],
                // Botón principal grande
                SizedBox(
                  height: 68,
                  child: FilledButton.icon(
                    key: Key('listen-${item.id}'),
                    onPressed: onListen,
                    style: FilledButton.styleFrom(
                      backgroundColor:
                          isPlaying ? color.withValues(alpha: .75) : color,
                      minimumSize: const Size.fromHeight(68),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18)),
                    ),
                    icon: Icon(btnIcon, size: 32),
                    label: Text(
                      btnLabel,
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Indicador animado de reproducción activa / pausada.
class _PlaybackBar extends StatelessWidget {
  const _PlaybackBar(
      {required this.color,
      required this.isPlaying,
      required this.isPaused});

  final Color color;
  final bool isPlaying;
  final bool isPaused;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          isPaused
              ? Icons.pause_rounded
              : Icons.graphic_eq_rounded,
          color: color,
          size: 24,
        ),
        const SizedBox(width: 8),
        Text(
          isPaused ? 'Pausado' : 'Reproduciendo…',
          style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.w700, color: color),
        ),
      ],
    );
  }
}
