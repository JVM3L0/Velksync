import 'dart:async';

import '../models/device.dart';

/// Suaviza a troca de faixa. Ao pular, o player do PC some por um instante
/// (SMTC e MPRIS relatam "nenhuma sessão"); mostrar isso como "Nada tocando"
/// pisca a tela. Aqui o estado anterior fica na tela, marcado como
/// [switching], até chegar a faixa nova ou passar [grace].
class MediaSmoother {
  MediaSmoother({required this.onChange, this.grace = const Duration(seconds: 3)});

  final void Function() onChange;
  final Duration grace;

  MediaState? shown;
  bool switching = false;

  Timer? _timer;
  MediaState? _held; // "nada tocando" segurado enquanto espera
  String? _from; // faixa de quando o usuário pediu para trocar

  static String _id(MediaState s) => '${s.title}|${s.artist}|${s.artId}';

  void push(MediaState st) {
    final cur = shown;
    if (!st.available && cur != null && cur.available) {
      _held = st;
      _begin();
      return;
    }
    _held = null;
    if (_from != null && st.available && _id(st) == _from) {
      // Pediu para trocar e o PC ainda mostra a faixa antiga: segue trocando.
      shown = st;
      onChange();
      return;
    }
    _end();
    shown = st;
    onChange();
  }

  /// O usuário tocou em próxima/anterior: já mostra "trocando".
  void expectChange() {
    final cur = shown;
    if (cur == null || !cur.available) return;
    _from = _id(cur);
    _begin();
  }

  void _begin() {
    if (!switching) {
      switching = true;
      onChange();
    }
    _timer ??= Timer(grace, () {
      _timer = null;
      final held = _held;
      _held = null;
      _end();
      if (held != null) shown = held; // sumiu de verdade
      onChange();
    });
  }

  void _end() {
    _timer?.cancel();
    _timer = null;
    _from = null;
    switching = false;
  }

  void dispose() => _timer?.cancel();
}
