import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/device.dart';

/// Dados dos PCs ficam nas preferências; os tokens, no armazenamento seguro
/// (Android Keystore), fora do backup automático.
class DeviceStore {
  static const _key = 'devices';
  static const _secure = FlutterSecureStorage();

  static String _tokenKey(String id) => 'token_$id';

  Future<List<Device>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    final devices = <Device>[];
    var migrated = false;
    for (final item in list) {
      final j = item as Map<String, dynamic>;
      // v0.1 guardava o token mestre em texto no JSON e falava HTTP: descarta
      // e o PC passa a aparecer como "não pareado" (ligar continua funcionando).
      if (j.remove('token') != null) migrated = true;
      final id = j['id'] as String;
      devices.add(Device.fromJson(j, token: await _secure.read(key: _tokenKey(id)) ?? ''));
    }
    if (migrated) await save(devices);
    return devices;
  }

  Future<void> save(List<Device> devices) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode([for (final d in devices) d.toJson()]));
    for (final d in devices) {
      if (d.token.isEmpty) {
        await _secure.delete(key: _tokenKey(d.id));
      } else {
        await _secure.write(key: _tokenKey(d.id), value: d.token);
      }
    }
  }

  Future<void> forget(Device d) => _secure.delete(key: _tokenKey(d.id));
}
