import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/elder_providers.dart';
import '../data/elder_repository.dart';
import '../domain/models.dart';
import 'elder_photos_screen.dart';

/// Galería en modo presentación para el adulto mayor (AGE-806 / DAC05-29):
/// las fotos de la familia avanzan solas a pantalla completa y un botón
/// grande de corazón envía una reacción. Se puede pausar, ir a la anterior o
/// a la siguiente, y abrir la lista para ver todas o agregar una foto.
class ElderSlideshowScreen extends ConsumerStatefulWidget {
  const ElderSlideshowScreen({super.key, this.initialIndex = 0});

  final int initialIndex;

  /// Tiempo que se muestra cada foto.
  static const interval = Duration(seconds: 6);

  @override
  ConsumerState<ElderSlideshowScreen> createState() =>
      _ElderSlideshowScreenState();
}

class _ElderSlideshowScreenState extends ConsumerState<ElderSlideshowScreen> {
  late final PageController _pages =
      PageController(initialPage: widget.initialIndex);
  Timer? _timer;
  bool _playing = true;
  int _index = 0;
  int _count = 0;
  final Set<String> _loved = {};

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _start();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pages.dispose();
    super.dispose();
  }

  void _start() {
    _timer?.cancel();
    _timer = Timer.periodic(ElderSlideshowScreen.interval, (_) => _go(1));
  }

  void _go(int step) {
    if (_count == 0 || !_pages.hasClients) return;
    final next = (_index + step) % _count;
    _pages.animateToPage(next < 0 ? _count - 1 : next,
        duration: const Duration(milliseconds: 500), curve: Curves.easeInOut);
  }

  void _togglePlay() {
    setState(() => _playing = !_playing);
    if (_playing) {
      _start();
    } else {
      _timer?.cancel();
    }
  }

  Future<void> _love(FamilyPhoto photo) async {
    setState(() => _loved.add(photo.id));
    try {
      await ref.read(elderRepositoryProvider).reactPhoto(photo.id, 'love');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Le enviaste cariño a ${photo.fromName}',
            style: const TextStyle(fontSize: 20)),
      ));
    } catch (_) {
      if (!mounted) return;
      setState(() => _loved.remove(photo.id));
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No se pudo enviar tu reacción',
            style: TextStyle(fontSize: 20)),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final photos = ref.watch(photosProvider);
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: photos.when(
          loading: () => const Center(
              child: CircularProgressIndicator(color: Colors.white)),
          error: (_, __) => _Message(
            text: 'No pudimos cargar tus fotos.',
            onClose: () => Navigator.of(context).maybePop(),
          ),
          data: (list) {
            _count = list.length;
            if (list.isEmpty) {
              return _Message(
                text: 'Aún no hay fotos. Cuando tu familia comparta fotos, '
                    'aparecerán aquí.',
                onClose: () => Navigator.of(context).maybePop(),
              );
            }
            final current = list[_index.clamp(0, list.length - 1)];
            return Stack(
              children: [
                PageView.builder(
                  key: const Key('slideshow-pages'),
                  controller: _pages,
                  itemCount: list.length,
                  onPageChanged: (i) => setState(() => _index = i),
                  itemBuilder: (_, i) => _Slide(photo: list[i]),
                ),
                // Barra superior: cerrar y ver todas.
                Positioned(
                  top: 8,
                  left: 8,
                  right: 8,
                  child: Row(
                    children: [
                      _RoundButton(
                        key: const Key('slideshow-close'),
                        icon: Icons.close_rounded,
                        label: 'Cerrar',
                        onTap: () => Navigator.of(context).maybePop(),
                      ),
                      const Spacer(),
                      Text('${_index + 1} de ${list.length}',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 20)),
                      const Spacer(),
                      _RoundButton(
                        key: const Key('slideshow-all'),
                        icon: Icons.grid_view_rounded,
                        label: 'Ver todas',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const ElderPhotosScreen()),
                        ),
                      ),
                    ],
                  ),
                ),
                // Abajo: texto de la foto y controles grandes.
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black87],
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if ((current.caption ?? '').isNotEmpty)
                          Text(current.caption!,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 26,
                                  fontWeight: FontWeight.w800)),
                        Text('De ${current.fromName}',
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 20)),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _RoundButton(
                              icon: Icons.chevron_left_rounded,
                              label: 'Foto anterior',
                              onTap: () => _go(-1),
                            ),
                            const SizedBox(width: 20),
                            _RoundButton(
                              key: const Key('slideshow-play'),
                              icon: _playing
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              label: _playing ? 'Pausar' : 'Seguir',
                              onTap: _togglePlay,
                            ),
                            const SizedBox(width: 20),
                            _RoundButton(
                              icon: Icons.chevron_right_rounded,
                              label: 'Foto siguiente',
                              onTap: () => _go(1),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        // Corazón grande en su propia fila, fácil de tocar.
                        _LoveButton(
                          loved: _loved.contains(current.id),
                          onTap: () => _love(current),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Slide extends StatelessWidget {
  const _Slide({required this.photo});

  final FamilyPhoto photo;

  @override
  Widget build(BuildContext context) => Center(
        child: Image.network(
          photo.url,
          fit: BoxFit.contain,
          width: double.infinity,
          height: double.infinity,
          semanticLabel: photo.caption ?? 'Foto de ${photo.fromName}',
          errorBuilder: (_, __, ___) => const Icon(
              Icons.image_not_supported_rounded,
              color: Colors.white54,
              size: 96),
        ),
      );
}

class _RoundButton extends StatelessWidget {
  const _RoundButton(
      {super.key,
      required this.icon,
      required this.label,
      required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: Material(
          color: Colors.white24,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Icon(icon, color: Colors.white, size: 36),
            ),
          ),
        ),
      );
}

class _LoveButton extends StatelessWidget {
  const _LoveButton({required this.loved, required this.onTap});

  final bool loved;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: loved ? 'Ya enviaste un corazón' : 'Me encanta',
        excludeSemantics: true,
        child: Material(
          key: const Key('slideshow-love'),
          color: loved ? const Color(0xFFC0392B) : Colors.white,
          borderRadius: BorderRadius.circular(40),
          child: InkWell(
            borderRadius: BorderRadius.circular(40),
            onTap: loved ? null : onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.favorite_rounded,
                      size: 36,
                      color: loved ? Colors.white : const Color(0xFFC0392B)),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(loved ? '¡Enviado!' : 'Me encanta',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: loved
                                ? Colors.white
                                : const Color(0xFFC0392B))),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class _Message extends StatelessWidget {
  const _Message({required this.text, required this.onClose});

  final String text;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(text,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 24)),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: onClose,
                child: const Text('Volver', style: TextStyle(fontSize: 22)),
              ),
            ],
          ),
        ),
      );
}
