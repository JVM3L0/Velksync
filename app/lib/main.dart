import 'package:dynamic_color/dynamic_color.dart';
import 'package:material_ui/material_ui.dart';

import 'screens/home_screen.dart';
import 'services/settings.dart';
import 'ui/palettes.dart';
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
          final (lightScheme, darkScheme) = switch (settings.family) {
            // Cores do papel de parede (Material You), como o Caelestia faz no desktop.
            ThemeFamily.dynamic => (schemeFrom(light, Brightness.light), schemeFrom(dark, Brightness.dark)),
            ThemeFamily.gruvbox => (Palettes.gruvboxLight.toScheme(), Palettes.gruvboxDark.toScheme()),
            ThemeFamily.catppuccin => (Palettes.catppuccinLatte.toScheme(), Palettes.catppuccinMocha.toScheme()),
          };
          return MaterialApp(
            title: 'Velksync',
            debugShowCheckedModeBanner: false,
            scaffoldMessengerKey: scaffoldMessengerKey,
            themeMode: settings.mode,
            theme: buildTheme(lightScheme),
            darkTheme: buildTheme(darkScheme),
            themeAnimationDuration: Motion.spatialDuration,
            themeAnimationCurve: Motion.effects,
            home: HomeScreen(messenger: scaffoldMessengerKey, settings: settings),
          );
        },
      ),
    );
  }
}
