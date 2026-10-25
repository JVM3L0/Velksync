import 'dart:async';
import 'dart:typed_data';

import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import '../models/device.dart';
import '../services/agent_client.dart';
import 'perf.dart';
import 'theme.dart';

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
    _live?.cancel();
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
      await _apply(await _c.media());
    } on AgentException {
      // queda momentânea: mantém o último estado
    }
  }

  Future<void> _apply(MediaState st) async {
    if (!mounted) return;
    setState(() {
      _state = st;
      _stamp = DateTime.now();
    });
    if (st.artId != _artId) {
      _artId = st.artId;
      final art = st.artId.isEmpty ? null : await _c.mediaArt();
      if (mounted && _artId == st.artId) setState(() => _art = art);
    }
  }

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

  void _volumeChanged(double v) {
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
        MediaCover(art: st.available ? _art : null, artId: _artId, available: st.available, playing: st.playing),
        const SizedBox(height: 24),
        if (st.available) ...[
          Text(
            st.title.isEmpty ? 'Sem título' : st.title,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          if (st.artist.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                st.artist,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.titleMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          if (st.player.isNotEmpty) ...[
            const SizedBox(height: 12),
            Center(child: _playerChip(st.player, scheme, text)),
          ],
          const SizedBox(height: 16),
          _progress(st, scheme, text),
          const SizedBox(height: 8),
          _controls(st, scheme),
        ] else
          Text(
            'Nada tocando no PC',
            textAlign: TextAlign.center,
            style: text.titleMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
        if (st.volume != null) ...[const SizedBox(height: 28), _volume(st, scheme)],
      ],
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
          onPressed: enabled ? () => _run(() => _c.mediaCommand('previous')) : null,
          icon: const Icon(Symbols.skip_previous_rounded, fill: 1),
        ),
        const SizedBox(width: 20),
        _PlayButton(playing: st.playing, onPressed: enabled ? _playPause : null),
        const SizedBox(width: 20),
        IconButton.filledTonal(
          tooltip: 'Próxima',
          iconSize: 30,
          style: IconButton.styleFrom(minimumSize: const Size(64, 64)),
          onPressed: enabled ? () => _run(() => _c.mediaCommand('next')) : null,
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
                setState(() => _state = MediaState.fromJson({..._json(st), 'muted': !muted}));
                _run(() => _c.mediaVolume(muted: !muted));
              },
              icon: Icon(
                muted
                    ? Symbols.volume_off_rounded
                    : v < 0.34
                    ? Symbols.volume_mute_rounded
                    : v < 0.67
                    ? Symbols.volume_down_rounded
                    : Symbols.volume_up_rounded,
                fill: 1,
                color: muted ? scheme.error : scheme.primary,
              ),
            ),
            Expanded(
              child: Slider(
                value: v.clamp(0, 1),
                onChanged: _volumeChanged,
                onChangeEnd: (x) {
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
        child: AspectRatio(
          aspectRatio: 1,
          child: AnimatedSwitcher(
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
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainer,
                      borderRadius: BorderRadius.circular(Radii.xl),
                    ),
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
          ),
        ),
      ),
    );
  }
}
