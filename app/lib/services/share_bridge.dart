import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Texto que chega pelo menu Compartilhar do Android, para mandar a um PC.
abstract final class ShareBridge {
  static const _channel = MethodChannel('velksync/share');
  static bool get _android => defaultTargetPlatform == TargetPlatform.android && !kIsWeb;

  /// O texto que abriu o app (uma vez só; depois devolve null).
  static Future<String?> take() async {
    if (!_android) return null;
    try {
      return await _channel.invokeMethod<String>('take');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Compartilhamentos com o app já aberto.
  static void onShared(void Function(String text) handler) {
    if (!_android) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'shared' && call.arguments is String) handler(call.arguments as String);
    });
  }
}
