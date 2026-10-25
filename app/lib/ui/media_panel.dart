import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import '../models/device.dart';
import '../services/agent_client.dart';
import '../services/media_smoother.dart';
import 'perf.dart';
import 'marquee.dart';
import 'theme.dart';
import 'transitions.dart';

String formatTime(int ms) {
  final s = (ms / 1000).floor();
  final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
  final mm = h > 0 ? m.toString().padLeft(2, '0') : '$m';
  return '${h > 0 ? '$h:' : ''}$mm:${sec.toString().padLeft(2, '0')}';
}

/// Aba de mídia: o que está tocando no PC, com controles, no estilo do player
/// do Caelestia. Só consulta o PC enquanto está na tela: com [live], o agente
/// avisa quando algo muda; sem, pergunta a cada segundo (agentes antigos).
class MediaPanel extends StatefulWidget {
  final AgentClient client;
  final bool live;
  const MediaPanel({super.key, required this.client, this.live = false});

  @override
  State<MediaPanel> createState() => _MediaPanelState();
}

class _MediaPanelState extends State<MediaPanel> {
  MediaState? _state;
  Uint8List? _art;
  String _artId = '';
  Timer? _poll, _tick, _retryLive;
  StreamSubscription<MediaState>? _live;
  DateTime _stamp = DateTime.now(); // quando _state foi lido (para avançar a posição)
  double? _dragPosition, _dragVolume;
  DateTime _lastVolumeSent = DateTime(0);
  bool _busy = false;
  late final _smoother = MediaSmoother(onChange: _shown);
  int _trackIndex = 0; // muda a cada faixa; o sinal diz para que lado desliza
  int _direction = 1; // 1 próxima, -1 anterior
  double _dragDx = 0; // arrasto da capa com o dedo
  bool _dragging = false;
  bool _volumeOpen = false; // slider de volume à mostra
  Timer? _volumeHide;

  AgentClient get _c => widget.client;

  @override
  void initState() {
    super.initState();
    if (widget.live) {
      _startLive();
    } else {
      _startPolling();
    }
    // Avança a barra suavemente entre as leituras.
    _tick = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted && (_state?.playing ?? false) && _dragPosition == null) setState(() {});
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _tick?.cancel();
    _retryLive?.cancel();
    _volumeHide?.cancel();
    _live?.cancel();
    _smoother.dispose();
    super.dispose();
  }

  void _startPolling() {
    _refresh();
    _poll ??= Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
  }

  void _startLive() {
    _live = _c.liveMedia().listen(_apply, onError: (_) => _liveLost(), onDone: _liveLost);
  }

  /// Caiu o canal ao vivo: pergunta enquanto isso e tenta voltar depois.
  void _liveLost() {
    _live = null;
    if (!mounted) return;
    _startPolling();
    _retryLive?.cancel();
    _retryLive = Timer(const Duration(seconds: 15), () {
      if (!mounted) return;
      _poll?.cancel();
      _poll = null;
      _startLive();
    });
  }

  Future<void> _refresh() async {
    try {
      _apply(await _c.media());
    } on AgentException {
      // queda momentânea: mantém o último estado
    }
  }

  void _apply(MediaState st) {
    if (mounted) _smoother.push(st);
  }

  /// O que o [MediaSmoother] decidiu mostrar (segura a faixa durante a troca).
  Future<void> _shown() async {
    if (!mounted) return;
    final st = _smoother.shown;
    if (st == null) return;
    var art = _art;
    if (st.artId != _artId) {
      // A capa nova chega antes de a faixa entrar na tela: assim ela já
      // desliza com a capa certa, sem trocar de imagem no meio.
      art = st.artId.isEmpty ? null : await _c.mediaArt().timeout(const Duration(seconds: 3), onTimeout: () => null);
      if (!mounted || !identical(_smoother.shown, st)) return; // chegou estado mais novo
    }
    setState(() {
      if (!identical(st, _state)) _stamp = DateTime.now();
      final prev = _state;
      if (prev != null && _trackKey(prev) != _trackKey(st)) {
        _trackIndex += _direction;
        _direction = 1; // trocas sem toque (fim da faixa) vêm "para a frente"
      }
      _state = st;
      _artId = st.artId;
      _art = art;
    });
  }

  static String _trackKey(MediaState s) => s.available ? '${s.title}|${s.artist}|${s.album}' : '';

  int get _position {
    final st = _state;
    if (st == null) return 0;
    var p = st.positionMs;
    if (st.playing) p += DateTime.now().difference(_stamp).inMilliseconds;
    return st.durationMs > 0 ? p.clamp(0, st.durationMs) : p;
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    _busy = true;
    try {
      await action();
    } on AgentException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      _busy = false;
      await _refresh();
    }
  }

  void _playPause() {
    final st = _state;
    if (st == null) return;
    // Resposta imediata na tela; a próxima leitura confirma.
    setState(() {
      _state = MediaState.fromJson({
        ..._json(st),
        'status': st.playing ? 'paused' : 'playing',
        'position_ms': _position,
      });
      _stamp = DateTime.now();
    });
    _run(() => _c.mediaCommand('play_pause'));
  }

  void _skip(String action) {
    _direction = action == 'previous' ? -1 : 1;
    _smoother.expectChange();
    _run(() => _c.mediaCommand(action));
  }

  Map<String, dynamic> _json(MediaState s) => {
    'available': s.available,
    'player': s.player,
    'status': s.status,
    'title': s.title,
    'artist': s.artist,
    'album': s.album,
    'art_id': s.artId,
    'position_ms': s.positionMs,
    'duration_ms': s.durationMs,
    'can_seek': s.canSeek,
    'can_control': s.canControl,
    'volume': s.volume,
    'muted': s.muted,
  };

  /// Some sozinho depois de um tempo sem mexer, como nos players.
  void _keepVolumeOpen() {
    _volumeHide?.cancel();
    _volumeHide = Timer(const Duration(seconds: 5), () {
      if (mounted && _dragVolume == null) setState(() => _volumeOpen = false);
    });
  }

  void _toggleVolume() {
    setState(() => _volumeOpen = !_volumeOpen);
    if (_volumeOpen) {
      _keepVolumeOpen();
    } else {
      _volumeHide?.cancel();
    }
  }

  Widget _volumeButton(MediaState st, ColorScheme scheme) {
    final muted = st.muted ?? false;
    final v = _dragVolume ?? st.volume ?? 0;
    return IconButton(
      tooltip: 'Volume',
      isSelected: _volumeOpen,
      style: IconButton.styleFrom(
        backgroundColor: _volumeOpen ? scheme.secondaryContainer : null,
        minimumSize: const Size(48, 48),
      ),
      onPressed: _toggleVolume,
      icon: Icon(_volumeIcon(muted, v), fill: 1, color: muted ? scheme.error : scheme.onSurfaceVariant),
    );
  }

  static IconData _volumeIcon(bool muted, double v) => muted
      ? Symbols.volume_off_rounded
      : v < 0.34
      ? Symbols.volume_mute_rounded
      : v < 0.67
      ? Symbols.volume_down_rounded
      : Symbols.volume_up_rounded;

  void _volumeChanged(double v) {
    _keepVolumeOpen();
    setState(() => _dragVolume = v);
    // Enquanto arrasta, manda no máximo a cada 150 ms.
    if (DateTime.now().difference(_lastVolumeSent) > const Duration(milliseconds: 150)) {
      _lastVolumeSent = DateTime.now();
      _c.mediaVolume(volume: v).catchError((_) {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = _state;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    if (st == null) return const Center(child: CircularProgressIndicator());
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        _track(st, scheme, text),
        if (st.available) ...[
          const SizedBox(height: 16),
          _progress(st, scheme, text),
          const SizedBox(height: 8),
          _controls(st, scheme),
        ],
        const SizedBox(height: 16),
        // Embaixo de tudo: abrir o volume não empurra os controles.
        Row(
          children: [
            if (st.available && st.player.isNotEmpty) Flexible(child: _playerChip(st.player, scheme, text)),
            const Spacer(),
            if (st.volume != null) _volumeButton(st, scheme),
          ],
        ),
        AnimatedSize(
          duration: Motion.spatialDuration,
          curve: Motion.spatial,
          alignment: Alignment.topCenter,
          child: _volumeOpen && st.volume != null
              ? Padding(padding: const EdgeInsets.only(top: 8), child: _volume(st, scheme))
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }

  /// Capa e título da faixa. Desliza para o lado da troca (como Spotify e
  /// YouTube Music) e dá para arrastar a capa para pular de faixa.
  Widget _track(MediaState st, ColorScheme scheme, TextTheme text) {
    final swipe = st.available && st.canControl;
    final block = Column(
      children: [
        MediaCover(art: st.available ? _art : null, artId: _artId, available: st.available, playing: st.playing),
        const SizedBox(height: 24),
        if (st.available) ...[
          // Uma linha cada, sempre: os controles não descem com títulos longos.
          MarqueeText(
            st.title.isEmpty ? 'Sem título' : st.title,
            style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          MarqueeText(
            st.artist.isEmpty ? ' ' : st.artist,
            style: text.titleMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ] else
          Text(
            'Nada tocando no PC',
            textAlign: TextAlign.center,
            style: text.titleMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
      ],
    );
    return GestureDetector(
      onHorizontalDragStart: swipe ? (_) => setState(() => _dragging = true) : null,
      // Com resistência: a capa acompanha o dedo, mas um pouco atrás.
      onHorizontalDragUpdate: swipe ? (d) => setState(() => _dragDx += d.delta.dx * 0.6) : null,
      onHorizontalDragEnd: swipe
          ? (d) {
              final v = d.primaryVelocity ?? 0;
              final far = _dragDx.abs() > 72;
              final toward = far ? _dragDx : v;
              setState(() {
                _dragging = false;
                _dragDx = 0;
              });
              if (far || v.abs() > 700) {
                HapticFeedback.selectionClick();
                _skip(toward < 0 ? 'next' : 'previous');
              }
            }
          : null,
      child: AnimatedContainer(
        duration: _dragging ? Duration.zero : Motion.spatialFastDuration,
        curve: Motion.spatial,
        transform: Matrix4.translationValues(_dragDx, 0, 0),
        child: SharedAxisSwitcher(index: _trackIndex, distance: 160, child: block),
      ),
    );
  }

  Widget _playerChip(String player, ColorScheme scheme, TextTheme text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: ShapeDecoration(color: scheme.surfaceContainerHigh, shape: const StadiumBorder()),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Symbols.speaker_rounded, size: 16, color: scheme.primary),
        const SizedBox(width: 6),
        Text(player, style: text.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
      ],
    ),
  );

  Widget _progress(MediaState st, ColorScheme scheme, TextTheme text) {
    final dur = st.durationMs;
    final pos = _dragPosition?.round() ?? _position;
    final enabled = st.canSeek && dur > 0;
    return Column(
      children: [
        Slider(
          value: dur > 0 ? pos.clamp(0, dur).toDouble() : 0,
          max: dur > 0 ? dur.toDouble() : 1,
          onChanged: enabled ? (v) => setState(() => _dragPosition = v) : null,
          onChangeEnd: enabled
              ? (v) {
                  setState(() {
                    _dragPosition = null;
                    _state = MediaState.fromJson({..._json(st), 'position_ms': v.round()});
                    _stamp = DateTime.now();
                  });
                  _run(() => _c.mediaSeek(v.round()));
                }
              : null,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(formatTime(pos), style: text.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
              Text(
                dur > 0 ? formatTime(dur) : '--:--',
                style: text.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _controls(MediaState st, ColorScheme scheme) {
    final enabled = st.canControl;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton.filledTonal(
          tooltip: 'Anterior',
          iconSize: 30,
          style: IconButton.styleFrom(minimumSize: const Size(64, 64)),
          onPressed: enabled ? () => _skip('previous') : null,
          icon: const Icon(Symbols.skip_previous_rounded, fill: 1),
        ),
        const SizedBox(width: 20),
        _PlayButton(playing: st.playing, onPressed: enabled ? _playPause : null),
        const SizedBox(width: 20),
        IconButton.filledTonal(
          tooltip: 'Próxima',
          iconSize: 30,
          style: IconButton.styleFrom(minimumSize: const Size(64, 64)),
          onPressed: enabled ? () => _skip('next') : null,
          icon: const Icon(Symbols.skip_next_rounded, fill: 1),
        ),
      ],
    );
  }

  Widget _volume(MediaState st, ColorScheme scheme) {
    final muted = st.muted ?? false;
    final v = _dragVolume ?? st.volume ?? 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            IconButton(
              tooltip: muted ? 'Ativar som' : 'Mudo',
              onPressed: () {
                _keepVolumeOpen();
                setState(() => _state = MediaState.fromJson({..._json(st), 'muted': !muted}));
                _run(() => _c.mediaVolume(muted: !muted));
              },
              icon: Icon(_volumeIcon(muted, v), fill: 1, color: muted ? scheme.error : scheme.primary),
            ),
            Expanded(
              child: Slider(
                value: v.clamp(0, 1),
                onChanged: _volumeChanged,
                onChangeEnd: (x) {
                  _keepVolumeOpen();
                  setState(() {
                    _dragVolume = null;
                    _state = MediaState.fromJson({..._json(st), 'volume': x});
                  });
                  _run(() => _c.mediaVolume(volume: x));
                },
              ),
            ),
            SizedBox(width: 44, child: Text('${(v * 100).round()}%', textAlign: TextAlign.end)),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}

/// Play/pause que muda de forma: círculo pausado, quadrado arredondado tocando.
class _PlayButton extends StatefulWidget {
  final bool playing;
  final VoidCallback? onPressed;
  const _PlayButton({required this.playing, required this.onPressed});

  @override
  State<_PlayButton> createState() => _PlayButtonState();
}

class _PlayButtonState extends State<_PlayButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = widget.onPressed != null;
    final radius = BorderRadius.circular(_pressed ? Radii.lg : (widget.playing ? Radii.xl : 44));
    return AnimatedScale(
      scale: _pressed ? 0.94 : 1,
      duration: Motion.spatialFastDuration,
      curve: Motion.spatialFast,
      child: AnimatedContainer(
        duration: Motion.spatialDuration,
        curve: Motion.spatial,
        width: widget.playing ? 104 : 88,
        height: 88,
        decoration: BoxDecoration(
          color: enabled ? scheme.primary : scheme.surfaceContainerHighest,
          borderRadius: radius,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: radius,
            onTap: widget.onPressed,
            onHighlightChanged: (v) => setState(() => _pressed = v),
            child: AnimatedSwitcher(
              duration: Motion.spatialFastDuration,
              transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
              child: Icon(
                widget.playing ? Symbols.pause_rounded : Symbols.play_arrow_rounded,
                key: ValueKey(widget.playing),
                size: 44,
                fill: 1,
                color: enabled ? scheme.onPrimary : scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Capa quadrada do que está tocando; sem capa, um formato que muda de
/// forma conforme toca ou não.
class MediaCover extends StatelessWidget {
  final Uint8List? art;
  final String artId;
  final bool available, playing;
  const MediaCover({super.key, this.art, this.artId = '', this.available = true, this.playing = false});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: AspectRatio(aspectRatio: 1, child: _art(scheme)),
      ),
    );
  }

  Widget _art(ColorScheme scheme) => AnimatedSwitcher(
    duration: Motion.spatialDuration,
    switchInCurve: Motion.effects,
    // O AnimatedSwitcher dá restrições frouxas: sem o SizedBox.expand
    // a capa (o Windows manda 120 px) ficava no tamanho natural, minúscula.
    child: art != null
        ? SizedBox.expand(
            key: ValueKey(artId),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Radii.xl),
              child: Image.memory(
                art!,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                // Ampliada ~3x: suaviza em vez de pixelar.
                filterQuality: FilterQuality.medium,
              ),
            ),
          )
        : Container(
            key: const ValueKey('sem-capa'),
            decoration: BoxDecoration(color: scheme.surfaceContainer, borderRadius: BorderRadius.circular(Radii.xl)),
            child: Center(
              child: MorphingShape(
                shape: playing ? LoadShape.sunny : LoadShape.cookie4,
                color: scheme.secondaryContainer,
                size: 140,
                child: Icon(
                  available ? Symbols.music_note_rounded : Symbols.music_off_rounded,
                  size: 56,
                  color: scheme.onSecondaryContainer,
                ),
              ),
            ),
          ),
  );
}
