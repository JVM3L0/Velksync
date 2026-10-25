import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/device.dart';

class DeviceStore {
  static const _key = 'devices';

  Future<List<Device>> load() async {
    final raw = (await SharedPreferences.getInstance()).getString(_key);
    if (raw == null) return [];
    return [for (final j in jsonDecode(raw) as List) Device.fromJson(j as Map<String, dynamic>)];
  }

  Future<void> save(List<Device> devices) async {
    await (await SharedPreferences.getInstance()).setString(_key, jsonEncode([for (final d in devices) d.toJson()]));
  }
}
