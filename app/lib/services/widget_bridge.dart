import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ui/role_colors.dart';
import 'pc_probe.dart';

/// Toque no widget: qual PC e, se foi o botão de desligar, `shutdown`.
typedef WidgetLaunch = ({String device, String? action});

WidgetLaunch? _launchOf(Object? args) {
  if (args is! Map || args['device'] is! String) return null;
  return (device: args['device'] as String, action: args['action'] as String?);
}

/// Ponte com o widget "Ligar PC" do Android. O app grava o último estado que
/// viu de cada PC (o widget não pergunta ao PC) e pede para ele se redesenhar;
/// do outro lado, um toque no widget abre a tela daquele PC.
class WidgetBridge {
  WidgetBridge({DateTime Function()? now}) : _now = now ?? DateTime.now;

  static const prefsKey = 'widget_state';
  static const _channel = MethodChannel('velksync/widget');

  final DateTime Function() _now;
  final _last = <String, (PcPower, DateTime)>{};

  static bool get _android => defaultTargetPlatform == TargetPlatform.android && !kIsWeb;

  /// Grava quando o estado muda (ou a cada minuto, para o "visto às" andar):
  /// a tela inicial pergunta a cada 5 s e não precisa acordar o widget sempre.
  Future<void> report(String deviceId, PcPower power) async {
    final now = _now();
    final prev = _last[deviceId];
    if (prev != null && prev.$1 == power && now.difference(prev.$2) < const Duration(minutes: 1)) return;
    _last[deviceId] = (power, now);
    await _edit((m) => m[deviceId] = {'power': power.name, 'at': now.millisecondsSinceEpoch});
  }

  /// PC apagado do app: some do widget também.
  Future<void> forget(String deviceId) async {
    _last.remove(deviceId);
    await _edit((m) => m.remove(deviceId));
  }

  Future<void> _edit(void Function(Map<String, dynamic>) change) async {
    final prefs = await SharedPreferences.getInstance();
    Map<String, dynamic> map;
    try {
      map = jsonDecode(prefs.getString(prefsKey) ?? '{}') as Map<String, dynamic>;
    } on FormatException {
      map = {};
    }
    change(map);
    await prefs.setString(prefsKey, jsonEncode(map));
    await _refresh();
  }

  static const themeKey = 'widget_theme';

  /// Cores do widget num modo (claro ou escuro), tiradas do tema do app.
  static Map<String, String> themeColors(ColorScheme s, RoleColors r) {
    String hex(Color c) => '#${c.toARGB32().toRadixString(16).padLeft(8, '0')}';
    return {
      'bg': hex(s.surfaceContainer),
      'text': hex(s.onSurface),
      'subtext': hex(s.onSurfaceVariant),
      'icon_bg': hex(s.secondaryContainer),
      'icon': hex(s.onSecondaryContainer),
      'button': hex(s.primary),
      'on_button': hex(s.onPrimary),
      'button_off': hex(s.surfaceContainerHighest),
      'on_button_off': hex(s.onSurfaceVariant),
      'danger': hex(r.danger),
      'on_danger': hex(r.onDanger),
    };
  }

  /// O widget segue o tema do app: grava as cores dos dois modos e o modo
  /// escolhido; null (tema dinâmico) volta às cores do sistema. Só regrava
  /// e redesenha quando muda.
  static Future<void> theme({
    Map<String, String>? light,
    Map<String, String>? dark,
    ThemeMode mode = ThemeMode.system,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final value = light == null || dark == null ? null : jsonEncode({'mode': mode.name, 'light': light, 'dark': dark});
    if (prefs.getString(themeKey) == value) return;
    if (value == null) {
      await prefs.remove(themeKey);
    } else {
      await prefs.setString(themeKey, value);
    }
    await _refresh();
  }

  static Future<void> _refresh() async {
    if (!_android) return;
    try {
      await _channel.invokeMethod<void>('refresh');
    } on MissingPluginException {
      // testes e plataformas sem widget
    } on PlatformException {
      // widget indisponível: o estado fica salvo para a próxima vez
    }
  }

  /// Toque no widget que abriu o app (uma vez só).
  static Future<WidgetLaunch?> takeLaunch() async {
    if (!_android) return null;
    try {
      return _launchOf(await _channel.invokeMethod<Object?>('takeLaunch'));
    } on MissingPluginException {
      return null;
    }
  }

  /// Toque no widget com o app já aberto.
  static void onOpen(void Function(WidgetLaunch launch) open) {
    if (!_android) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'open') return;
      if (_launchOf(call.arguments) case final launch?) open(launch);
    });
  }
}
