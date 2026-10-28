import 'package:dynamic_color/dynamic_color.dart';
import 'package:material_ui/material_ui.dart';

import 'screens/home_screen.dart';
import 'services/settings.dart';
import 'services/widget_bridge.dart';
import 'ui/role_colors.dart';
import 'ui/theme.dart';

final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = AppSettings();
  await settings.load(); // tema salvo antes do primeiro quadro, sem "piscar"
  runApp(VelksyncApp(settings: settings));
}

class VelksyncApp extends StatelessWidget {
  final AppSettings settings;
  const VelksyncApp({super.key, required this.settings});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (_, _) => DynamicColorBuilder(
        builder: (light, dark) {
          final palettes = settings.palettes;
          final (lightScheme, darkScheme) = switch (palettes) {
            // Cores do papel de parede (Material You), como o Caelestia faz no desktop.
            null => (schemeFrom(light, Brightness.light), schemeFrom(dark, Brightness.dark)),
            (final l, final d) => (l.toScheme(), d.toScheme()),
          };
          // O widget da tela inicial segue o tema (no dinâmico, as cores do sistema).
          final lightRoles = palettes?.$1.toRoles() ?? RoleColors.fromScheme(lightScheme);
          final darkRoles = palettes?.$2.toRoles() ?? RoleColors.fromScheme(darkScheme);
          WidgetBridge.theme(
            light: palettes == null ? null : WidgetBridge.themeColors(lightScheme, lightRoles),
            dark: palettes == null ? null : WidgetBridge.themeColors(darkScheme, darkRoles),
            mode: settings.mode,
          );
          return MaterialApp(
            title: 'Velksync',
            debugShowCheckedModeBanner: false,
            scaffoldMessengerKey: scaffoldMessengerKey,
            themeMode: settings.mode,
            theme: buildTheme(lightScheme, roles: lightRoles),
            darkTheme: buildTheme(darkScheme, roles: darkRoles),
            themeAnimationDuration: Motion.spatialDuration,
            themeAnimationCurve: Motion.effects,
            home: HomeScreen(messenger: scaffoldMessengerKey, settings: settings),
          );
        },
      ),
    );
  }
}
