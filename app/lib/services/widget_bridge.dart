import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'pc_probe.dart';

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

  /// PC tocado no widget que abriu o app (uma vez só).
  static Future<String?> takeLaunchDevice() async {
    if (!_android) return null;
    try {
      return await _channel.invokeMethod<String>('takeLaunchDevice');
    } on MissingPluginException {
      return null;
    }
  }

  /// Toque no widget com o app já aberto.
  static void onOpenDevice(void Function(String deviceId) open) {
    if (!_android) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'openDevice' && call.arguments is String) open(call.arguments as String);
    });
  }
}
