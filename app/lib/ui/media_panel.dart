import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import '../models/device.dart';
import '../services/agent_client.dart';
import '../services/lru_cache.dart';
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

/// Aba de mídia: o que está tocando no PC. O layout segue os players de
/// referência (Spotify, YouTube Music, Apple Music, Android 16): capa grande
/// no formato original, fundo com as cores dela, texto à esquerda e controles
/// fixos embaixo. Só consulta o PC enquanto está na tela: com [live], o agente
/// avisa quando algo muda; sem, pergunta a cada segundo (agentes antigos).
class MediaPanel extends StatefulWidget {
  final AgentClient client;
  final bool live;
  const MediaPanel({super.key, required this.client, this.live = false});

  @override
  State<MediaPanel> createState() => _MediaPanelState();
}

/// Capa baixada e o que se tirou dela (formato e cores).
typedef _Art = ({Uint8List bytes, double aspect, (ColorScheme, ColorScheme)? schemes});

class _MediaPanelState extends State<MediaPanel> {
  /// Duração da troca de faixa (capa e títulos), curta como nos players.
  static const _switch = Duration(milliseconds: 380);

  /// Quanto a troca espera pela capa nova; se demorar, ela entra depois.
  static const _artWait = Duration(milliseconds: 600);

  /// Últimas capas já baixadas e analisadas, por PC e capa: voltar a uma
  /// faixa mostra a capa na hora. Só na memória, alguns MB no máximo.
  static final _artCache = LruCache<String, _Art>(20);

  MediaState? _state;
  Uint8List? _art;
  String _artId = '';
  Timer? _poll, _tick, _retryLive;
  StreamSubscription<MediaState>? _live;
  DateTime _stamp = DateTime.now(); // quando _state foi lido (para avançar a posição)
  double? _dragPosition, _dragVolume;
  DateTime _lastVolumeSent = DateTime(0);
  bool _busy = false;
  int? _frozenAt; // posição parada da barra durante a troca de faixa
  late final _smoother = MediaSmoother(onChange: _shown);
  int _trackIndex = 0; // muda a cada faixa; o sinal diz para que lado desliza
  int _direction = 1; // 1 próxima, -1 anterior
  double _dragDx = 0; // arrasto da capa com o dedo
  bool _dragging = false;
  bool _armed = false; // passou do ponto: soltar pula de faixa
  bool _flown = false; // a capa saiu voando e espera a faixa nova
  bool _snap = false; // volta ao centro sem animar (a faixa nova entra pela transição)
  bool _hideOut = false; // esconde a capa antiga até a troca terminar
  Timer? _unhide;
  Timer? _flyBack;
  Timer? _volumeHide;
  final _volumeLink = LayerLink();
  final _volumePopup = OverlayPortalController(); // balão do volume
  // Formato e cores da capa atual (16:9 em vídeos; cores pastel para o fundo).
  double _artAspect = 1;
  (ColorScheme, ColorScheme)? _artSchemes;

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
      if (mounted && (_state?.playing ?? false) && _dragPosition == null && _frozenAt == null) setState(() {});
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _tick?.cancel();
    _retryLive?.cancel();
    _volumeHide?.cancel();
    _flyBack?.cancel();
    _unhide?.cancel();
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
    // Durante a troca a barra para (a faixa antiga não segue correndo).
    if (_smoother.switching) {
      _frozenAt ??= _livePosition;
    } else {
      _frozenAt = null;
    }
    var art = _art;
    var newArt = st.artId != _artId;
    if (newArt) {
      // Espera um pouco a capa nova para ela já entrar deslizando; se o PC
      // demorar, a faixa entra com a capa padrão e a imagem chega depois.
      final load = _loadArt(st);
      var late = false;
      final got = await load.timeout(
        _artWait,
        onTimeout: () {
          late = true;
          return null;
        },
      );
      if (!mounted || !identical(_smoother.shown, st)) return; // chegou estado mais novo
      _useArt(got);
      art = got?.bytes;
      if (late) {
        load.then((a) {
          if (a != null && mounted && _artId == st.artId) setState(() => _useArt(a));
        });
      }
    }
    setState(() {
      if (!identical(st, _state)) _stamp = DateTime.now();
      final prev = _state;
      if (prev != null && _trackKey(prev) != _trackKey(st)) {
        _trackIndex += _direction;
        _direction = 1; // trocas sem toque (fim da faixa) vêm "para a frente"
        // A capa que saiu voando volta ao centro já como a faixa nova, sem
        // animar: quem entra deslizando do outro lado é a transição de faixa.
        _flyBack?.cancel();
        if (_flown) {
          _snap = true;
          _flown = false;
          WidgetsBinding.instance.addPostFrameCallback((_) => _snap = false);
          _unhide?.cancel();
          _unhide = Timer(_switch + const Duration(milliseconds: 50), () {
            if (mounted) setState(() => _hideOut = false);
          });
        }
        _dragDx = 0;
      }
      _state = st;
      _artId = st.artId;
      if (newArt) _art = art;
    });
  }

  Future<_Art?> _loadArt(MediaState st) async {
    if (st.artId.isEmpty) return null;
    final key = '${_c.device.id}|${st.artId}';
    if (_artCache.get(key) case final hit?) return hit;
    try {
      final bytes = await _c.mediaArt().timeout(const Duration(seconds: 3), onTimeout: () => null);
      if (bytes == null) return null;
      final look = await _analyzeArt(bytes);
      if (look == null) return (bytes: bytes, aspect: 1.0, schemes: null); // não decodifica: não guarda
      final art = (bytes: bytes, aspect: look.aspect, schemes: look.schemes);
      _artCache.put(key, art);
      return art;
    } on AgentException {
      return null;
    }
  }

  void _useArt(_Art? a) {
    _art = a?.bytes;
    _artAspect = a?.aspect ?? 1;
    _artSchemes = a?.schemes;
  }

  /// Proporção da capa e esquemas de cor (claro, escuro) tirados dela, no
  /// estilo tonal spot: pastel, combinando com os temas suaves.
  static Future<({double aspect, (ColorScheme, ColorScheme)? schemes})?> _analyzeArt(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final aspect = frame.image.width / frame.image.height;
      frame.image.dispose();
      codec.dispose();
      // As cores saem de uma miniatura: decodificar a capa inteira é lento.
      final provider = ResizeImage(MemoryImage(bytes), width: 112, height: 112, policy: ResizeImagePolicy.fit);
      final light = await ColorScheme.fromImageProvider(provider: provider);
      final dark = await ColorScheme.fromImageProvider(provider: provider, brightness: Brightness.dark);
      return (aspect: aspect, schemes: (light, dark));
    } on Exception {
      return null; // imagem que não decodifica: segue com a capa padrão
    }
  }

  static String _trackKey(MediaState s) => s.available ? '${s.title}|${s.artist}|${s.album}' : '';

  int get _position => _frozenAt ?? _livePosition;

  int get _livePosition {
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
    // Próxima ou anterior, a faixa que entra começa do zero.
    if (_state?.available ?? false) setState(() => _frozenAt = 0);
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
      if (mounted && _dragVolume == null) _closeVolume();
    });
  }

  void _toggleVolume() => _volumePopup.isShowing ? _closeVolume() : _openVolume();

  void _openVolume() {
    setState(_volumePopup.show);
    _keepVolumeOpen();
  }

  void _closeVolume() {
    _volumeHide?.cancel();
    if (_volumePopup.isShowing) setState(_volumePopup.hide);
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

  void _toggleMute(MediaState st) {
    final muted = st.muted ?? false;
    setState(() => _state = MediaState.fromJson({..._json(st), 'muted': !muted}));
    _run(() => _c.mediaVolume(muted: !muted));
  }

  @override
  Widget build(BuildContext context) {
    final st = _state;
    if (st == null) return const Center(child: CircularProgressIndicator());
    final base = Theme.of(context);
    final dark = base.brightness == Brightness.dark;
    final schemes = _artSchemes;
    final scheme = schemes == null || !st.available ? base.colorScheme : (dark ? schemes.$2 : schemes.$1);
    // As cores da capa valem só aqui dentro; trocam suavemente entre faixas.
    return AnimatedTheme(
      // Barras finas, como nos players (o padrão do M3 Expressive é 16 px).
      data: base.copyWith(
        colorScheme: scheme,
        // O tema do app fixa cor de texto e ícone; aqui seguem a capa.
        textTheme: base.textTheme.apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface),
        iconTheme: base.iconTheme.copyWith(color: scheme.onSurfaceVariant),
        sliderTheme: base.sliderTheme.copyWith(trackHeight: 6),
      ),
      duration: Motion.spatialDuration,
      curve: Motion.effects,
      child: Builder(builder: (context) => _player(context, st)),
    );
  }

  Widget _player(BuildContext context, MediaState st) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return DecoratedBox(
      // Degradê com a cor da capa em cima, como no YouTube Music e no Android 16.
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color.alphaBlend(scheme.primaryContainer.withValues(alpha: 0.85), scheme.surface), scheme.surface],
          stops: const [0, 0.8],
        ),
      ),
      child: LayoutBuilder(
        builder: (context, box) {
          final bottom = Column(
            children: [
              const SizedBox(height: 24),
              _titles(st, scheme, text),
              const SizedBox(height: 12),
              if (st.available) _progress(context, st, scheme, text),
              const SizedBox(height: 4),
              _controls(st, scheme),
            ],
          );
          const pad = EdgeInsets.fromLTRB(24, 16, 24, 20);
          // Tela baixa (paisagem, fonte grande): rola, com a capa num tamanho fixo.
          if (box.maxHeight < 560) {
            return SingleChildScrollView(
              padding: pad,
              child: Column(children: [_cover(context, st, (box.maxWidth - 48).clamp(0.0, 280.0)), bottom]),
            );
          }
          // Senão, tudo na tela: a capa fica com exatamente o espaço que sobra.
          return Padding(
            padding: pad,
            child: Column(
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, area) =>
                        Center(child: _cover(context, st, area.maxHeight.clamp(0.0, area.maxWidth))),
                  ),
                ),
                bottom,
              ],
            ),
          );
        },
      ),
    );
  }

  /// Capa: dá para arrastá-la para pular de faixa. Segue o dedo, inclina e
  /// mostra ⏭/⏮ no lado revelado; só pula depois de 40% da largura (ou num
  /// gesto rápido e longo), com vibração no ponto. Voltar o dedo cancela.
  Widget _cover(BuildContext context, MediaState st, double side) {
    final swipe = st.available && st.canControl;
    final width = MediaQuery.sizeOf(context).width;
    final threshold = side * 0.4;
    final p = (_dragDx.abs() / threshold).clamp(0.0, 1.0);
    final scheme = Theme.of(context).colorScheme;

    void update(double dx) {
      final armed = dx.abs() >= threshold;
      if (armed != _armed) armed ? HapticFeedback.mediumImpact() : HapticFeedback.selectionClick();
      setState(() {
        _dragDx = dx;
        _armed = armed;
      });
    }

    void release(double velocity) {
      final fling = velocity.abs() > 1200 && _dragDx.abs() >= 80 && velocity.sign == _dragDx.sign;
      final go = _armed || fling;
      final toward = _dragDx;
      setState(() {
        _dragging = false;
        _armed = false;
        if (go) {
          _flown = true;
          _hideOut = true;
          _dragDx = toward.sign * (width + side); // sai voando da tela
        } else {
          _dragDx = 0; // volta com mola
        }
      });
      if (!go) return;
      _skip(toward < 0 ? 'next' : 'previous');
      // Se a faixa não mudar (player recusou), a capa volta.
      _flyBack?.cancel();
      _flyBack = Timer(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() {
            _dragDx = 0;
            _hideOut = false;
          });
        }
      });
    }

    final cover = AnimatedContainer(
      duration: _dragging || _snap
          ? Duration.zero
          : _flown && _dragDx != 0
          ? const Duration(milliseconds: 180)
          : Motion.spatialDuration,
      curve: _flown && _dragDx != 0 ? Curves.easeIn : Motion.spatial,
      transformAlignment: Alignment.bottomCenter,
      transform: Matrix4.identity()
        ..translateByDouble(_dragDx, 0, 0, 1)
        ..rotateZ(_dragDx / width * 0.15)
        ..scaleByDouble(1 - 0.08 * p, 1 - 0.08 * p, 1, 1),
      // Depois do quadro: o fim da animação pode cair no meio de um build.
      onEnd: () => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _dragDx == 0 && _flown) setState(() => _flown = false);
      }),
      child: SharedAxisSwitcher(
        index: _trackIndex,
        distance: width * 0.9,
        duration: _switch,
        hideOutgoing: _hideOut,
        child: MediaCover(
          art: st.available ? _art : null,
          artId: _artId,
          available: st.available,
          playing: st.playing,
          side: side,
          aspect: _artAspect,
        ),
      ),
    );

    // ⏭ à direita ao arrastar para a esquerda (e vice-versa); cheio quando armado.
    final next = _dragDx < 0;
    final hint = IgnorePointer(
      child: AnimatedOpacity(
        opacity: _dragging ? p : 0,
        duration: Motion.effectsDuration,
        child: Align(
          alignment: next ? Alignment.centerRight : Alignment.centerLeft,
          child: AnimatedContainer(
            duration: Motion.spatialFastDuration,
            curve: Motion.spatialFast,
            width: _armed ? 64 : 48,
            height: _armed ? 64 : 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _armed ? scheme.primary : scheme.surfaceContainerHigh,
            ),
            child: Icon(
              next ? Symbols.skip_next_rounded : Symbols.skip_previous_rounded,
              fill: 1,
              size: _armed ? 32 : 24,
              color: _armed ? scheme.onPrimary : scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );

    return GestureDetector(
      onHorizontalDragStart: swipe
          ? (_) => setState(() {
              _dragging = true;
              _flyBack?.cancel();
            })
          : null,
      onHorizontalDragUpdate: swipe ? (d) => update(_dragDx + d.delta.dx) : null,
      onHorizontalDragEnd: swipe ? (d) => release(d.primaryVelocity ?? 0) : null,
      onHorizontalDragCancel: swipe ? () => release(0) : null,
      child: Stack(
        children: [
          cover,
          Positioned.fill(child: hint),
        ],
      ),
    );
  }

  /// App que toca, título e artista à esquerda, uma linha cada: títulos longos
  /// rolam em vez de empurrar os controles.
  Widget _titles(MediaState st, ColorScheme scheme, TextTheme text) {
    final muted = text.labelLarge?.copyWith(color: scheme.onSurfaceVariant);
    final info = SharedAxisSwitcher(
      index: _trackIndex,
      distance: 96,
      duration: _switch,
      child: SizedBox(
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Sempre ocupa a linha (mesmo vazia): o layout não pula quando o player some.
            Row(
              children: [
                Icon(
                  Symbols.speaker_rounded,
                  size: 16,
                  fill: 1,
                  color: st.available && st.player.isNotEmpty ? scheme.primary : Colors.transparent,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    st.available ? st.player : '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: muted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            MarqueeText(
              st.available ? (st.title.isEmpty ? 'Sem título' : st.title) : 'Nada tocando',
              textAlign: TextAlign.start,
              style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            MarqueeText(
              st.available ? (st.artist.isEmpty ? ' ' : st.artist) : 'Dê play em algo no PC',
              textAlign: TextAlign.start,
              style: text.titleMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
    // O botão de volume fica fora da animação de troca: não desliza com a faixa.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(child: info),
        const SizedBox(width: 8),
        _volumeButton(st, scheme),
      ],
    );
  }

  /// Barra fina do Material 3 Expressive, alinhada às bordas do conteúdo.
  Widget _progress(BuildContext context, MediaState st, ColorScheme scheme, TextTheme text) {
    final dur = st.durationMs;
    final pos = _dragPosition?.round() ?? _position;
    final enabled = st.canSeek && dur > 0;
    final time = text.labelMedium?.copyWith(
      color: scheme.onSurfaceVariant,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(padding: EdgeInsets.zero),
          child: Slider(
            // ignore: deprecated_member_use
            year2023: false,
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
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(formatTime(pos), style: time),
            Text(dur > 0 ? formatTime(dur) : '--:--', style: time),
          ],
        ),
      ],
    );
  }

  /// Anterior, play e próxima, centralizados.
  Widget _controls(MediaState st, ColorScheme scheme) {
    final enabled = st.available && st.canControl;
    final skip = IconButton.styleFrom(minimumSize: const Size(72, 72), foregroundColor: scheme.onSurface);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          tooltip: 'Anterior',
          iconSize: 40,
          style: skip,
          onPressed: enabled ? () => _skip('previous') : null,
          icon: const Icon(Symbols.skip_previous_rounded, fill: 1),
        ),
        const SizedBox(width: 24),
        _PlayButton(playing: st.playing, onPressed: enabled ? _playPause : null),
        const SizedBox(width: 24),
        IconButton(
          tooltip: 'Próxima',
          iconSize: 40,
          style: skip,
          onPressed: enabled ? () => _skip('next') : null,
          icon: const Icon(Symbols.skip_next_rounded, fill: 1),
        ),
      ],
    );
  }

  /// Único botão de som: mostra o nível e abre o balão com o slider e o mudo.
  Widget _volumeButton(MediaState st, ColorScheme scheme) {
    final muted = st.muted ?? false;
    return _volumeAnchor(
      st,
      IconButton(
        tooltip: 'Volume',
        style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
        isSelected: _volumePopup.isShowing,
        onPressed: st.volume != null ? _toggleVolume : null,
        icon: Icon(
          _volumeIcon(muted, _dragVolume ?? st.volume ?? 0),
          fill: 1,
          color: muted ? scheme.error : scheme.onSurfaceVariant,
        ),
      ),
    );
  }

  /// Pílula do volume: nasce do próprio botão (morph do M3 Expressive) e
  /// cresce para cima, por cima da capa, sem empurrar nada. Fecha ao tocar
  /// fora ou depois de 5 s parado.
  Widget _volumeAnchor(MediaState st, Widget button) => CompositedTransformTarget(
    link: _volumeLink,
    child: OverlayPortal(
      controller: _volumePopup,
      overlayChildBuilder: (context) => CompositedTransformFollower(
        link: _volumeLink,
        targetAnchor: Alignment.bottomCenter,
        followerAnchor: Alignment.bottomCenter,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: TapRegion(onTapOutside: (_) => _closeVolume(), child: _volumePill(context, st)),
        ),
      ),
      child: button,
    ),
  );

  Widget _volumePill(BuildContext context, MediaState st) {
    final scheme = Theme.of(context).colorScheme;
    final muted = st.muted ?? false;
    final v = (_dragVolume ?? st.volume ?? 0).clamp(0.0, 1.0);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Motion.spatialDuration,
      curve: Motion.spatial,
      builder: (context, t, child) => SizedBox(
        // Do tamanho do botão (48) até a pílula inteira (64 × 248).
        width: 48 + 16 * t.clamp(0.0, 1.0),
        height: 48 + 200 * t,
        child: child,
      ),
      child: Material(
        color: scheme.surfaceContainerHigh,
        elevation: 4,
        shadowColor: scheme.shadow,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        // Pequena (começo da animação), é só o ícone; crescida, o controle todo.
        child: LayoutBuilder(
          builder: (context, box) => box.maxHeight < 140
              ? Center(child: Icon(_volumeIcon(muted, v), fill: 1, color: scheme.primary))
              : Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    children: [
                      Text(
                        '${(v * 100).round()}%',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(fontWeight: FontWeight.w600, fontFeatures: const [FontFeature.tabularFigures()]),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: VerticalVolume(
                          key: const ValueKey('volume'),
                          value: v,
                          muted: muted,
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
                      IconButton(
                        tooltip: muted ? 'Ativar som' : 'Mudo',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(width: 40, height: 40),
                        onPressed: () {
                          _keepVolumeOpen();
                          _toggleMute(st);
                        },
                        icon: Icon(_volumeIcon(muted, v), fill: 1, color: muted ? scheme.error : scheme.primary),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

/// Barra de volume vertical: a área inteira é o controle (toque ou arraste),
/// preenchida de baixo para cima. Anunciada como controle ajustável.
class VerticalVolume extends StatefulWidget {
  final double value;
  final bool muted;
  final ValueChanged<double> onChanged, onChangeEnd;
  const VerticalVolume({
    super.key,
    required this.value,
    required this.onChanged,
    required this.onChangeEnd,
    this.muted = false,
  });

  @override
  State<VerticalVolume> createState() => _VerticalVolumeState();
}

class _VerticalVolumeState extends State<VerticalVolume> {
  static const _step = 0.05;
  double? _last;

  double _at(Offset local, double height) => (1 - local.dy / height).clamp(0.0, 1.0);

  void _set(double v) {
    _last = v;
    widget.onChanged(v);
  }

  void _end() {
    final v = _last;
    _last = null;
    if (v != null) widget.onChangeEnd(v);
  }

  void _nudge(double delta) {
    final v = (widget.value + delta).clamp(0.0, 1.0);
    widget.onChanged(v);
    widget.onChangeEnd(v);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pct = (widget.value * 100).round();
    return Semantics(
      slider: true,
      label: 'Volume do PC',
      value: '$pct%',
      increasedValue: '${((widget.value + _step).clamp(0.0, 1.0) * 100).round()}%',
      decreasedValue: '${((widget.value - _step).clamp(0.0, 1.0) * 100).round()}%',
      onIncrease: () => _nudge(_step),
      onDecrease: () => _nudge(-_step),
      child: LayoutBuilder(
        builder: (context, box) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => _set(_at(d.localPosition, box.maxHeight)),
          onTapUp: (_) => _end(),
          onVerticalDragStart: (d) => _set(_at(d.localPosition, box.maxHeight)),
          onVerticalDragUpdate: (d) => _set(_at(d.localPosition, box.maxHeight)),
          onVerticalDragEnd: (_) => _end(),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Radii.lgPlus),
            child: ColoredBox(
              color: scheme.surfaceContainerHighest,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: AnimatedFractionallySizedBox(
                  duration: _last == null ? Motion.spatialFastDuration : Duration.zero,
                  curve: Motion.effects,
                  widthFactor: 1,
                  heightFactor: widget.value,
                  child: ColoredBox(color: widget.muted ? scheme.outline : scheme.primary),
                ),
              ),
            ),
          ),
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

/// Capa no formato original (quadrada para álbuns, 16:9 para vídeos), dentro
/// de uma área de altura fixa [side]: trocar de faixa não mexe no layout. Sem
/// capa, um formato que muda de forma conforme toca ou não.
class MediaCover extends StatelessWidget {
  final Uint8List? art;
  final String artId;
  final bool available, playing;
  final double side;

  /// Largura / altura da imagem.
  final double aspect;
  const MediaCover({
    super.key,
    this.art,
    this.artId = '',
    this.available = true,
    this.playing = false,
    this.side = 360,
    this.aspect = 1,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, box) {
        final maxW = box.maxWidth.isFinite ? box.maxWidth : side;
        final wide = art != null && aspect > 1.15;
        final w = wide ? (side * aspect).clamp(0.0, maxW) : side.clamp(0.0, maxW);
        final h = wide ? w / aspect : w;
        return SizedBox(
          height: side,
          width: double.infinity,
          child: Center(
            child: SizedBox(
              width: w,
              height: h,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(Radii.xl),
                  boxShadow: [
                    BoxShadow(
                      color: scheme.shadow.withValues(alpha: 0.25),
                      blurRadius: 32,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: _art(scheme),
              ),
            ),
          ),
        );
      },
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
