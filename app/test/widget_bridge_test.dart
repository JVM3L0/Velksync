import 'package:material_ui/material_ui.dart';
import 'package:velksync/ui/palettes.dart';

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velksync/models/device.dart';
import 'package:velksync/services/pc_probe.dart';
import 'package:velksync/services/widget_bridge.dart';

/// O widget (Kotlin) lê o que o app grava; os dois testes usam test/fixtures.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final seen = DateTime.fromMillisecondsSinceEpoch(1761400000000);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<Map<String, dynamic>> saved() async =>
      jsonDecode((await SharedPreferences.getInstance()).getString(WidgetBridge.prefsKey)!) as Map<String, dynamic>;

  test('grava o estado no formato que o widget lê', () async {
    final w = WidgetBridge(now: () => seen);
    await w.report('pc1', PcPower.online);
    await w.report('pc2', PcPower.offline);
    final fixture = jsonDecode(File('test/fixtures/widget_state.json').readAsStringSync());
    expect(await saved(), fixture);
  });

  test('não regrava o mesmo estado a cada consulta, mas regrava ao mudar', () async {
    var now = seen;
    final w = WidgetBridge(now: () => now);
    await w.report('pc1', PcPower.online);
    now = now.add(const Duration(seconds: 5));
    await w.report('pc1', PcPower.online);
    expect((await saved())['pc1']['at'], seen.millisecondsSinceEpoch);
    await w.report('pc1', PcPower.offline);
    expect((await saved())['pc1']['power'], 'offline');
  });

  test('apagar o PC tira ele do widget', () async {
    final w = WidgetBridge(now: () => seen);
    await w.report('pc1', PcPower.online);
    await w.forget('pc1');
    expect(await saved(), isEmpty);
  });

  test('a lista de PCs do app tem os campos que o widget usa', () {
    final fixture = (jsonDecode(File('test/fixtures/devices.json').readAsStringSync()) as List).first as Map;
    final json = const Device(id: 'pc1', name: 'Velkhyro', host: 'h', mac: 'aa:bb:cc:dd:ee:ff').toJson();
    for (final key in ['id', 'name', 'mac', 'broadcast']) {
      expect(json, contains(key));
      expect(fixture, contains(key));
    }
  });

  group('toque no widget', () {
    Future<void> send(Object? args) =>
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
          'velksync/widget',
          const StandardMethodCodec().encodeMethodCall(MethodCall('open', args)),
          (_) {},
        );

    test('o botão de desligar chega com a ação', () async {
      final got = <WidgetLaunch>[];
      WidgetBridge.onOpen(got.add);
      await send({'device': 'pc1', 'action': 'shutdown'});
      await send({'device': 'pc1', 'action': null});
      expect(got, [(device: 'pc1', action: 'shutdown'), (device: 'pc1', action: null)]);
    });

    test('chamada malformada é ignorada', () async {
      final got = <WidgetLaunch>[];
      WidgetBridge.onOpen(got.add);
      await send('pc1');
      await send({'action': 'shutdown'});
      expect(got, isEmpty);
    });
  });

  test('tema do widget: grava os dois modos, não regrava igual e some no dinâmico', () async {
    SharedPreferences.setMockInitialValues({});
    final p = Palettes.catppuccin(CatppuccinFlavor.mocha);
    final light = WidgetBridge.themeColors(p.$1.toScheme(), p.$1.toRoles()!);
    final dark = WidgetBridge.themeColors(p.$2.toScheme(), p.$2.toRoles()!);
    expect(dark['bg'], startsWith('#ff'));
    expect(dark.keys, containsAll(['bg', 'text', 'button', 'on_button', 'danger', 'on_danger']));

    await WidgetBridge.theme(light: light, dark: dark, mode: ThemeMode.dark);
    final prefs = await SharedPreferences.getInstance();
    final saved = jsonDecode(prefs.getString(WidgetBridge.themeKey)!) as Map<String, dynamic>;
    expect(saved['mode'], 'dark');
    expect((saved['dark'] as Map)['button'], dark['button']);

    await WidgetBridge.theme();
    expect(prefs.getString(WidgetBridge.themeKey), isNull, reason: 'tema dinâmico: cores do sistema');
  });
}
