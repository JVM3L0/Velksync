import 'package:dynamic_color/dynamic_color.dart';
import 'package:material_ui/material_ui.dart';

import 'screens/home_screen.dart';
import 'ui/theme.dart';

final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

void main() => runApp(const VelksyncApp());

class VelksyncApp extends StatelessWidget {
  const VelksyncApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Cores do papel de parede (Material You), como o Caelestia faz no desktop.
    return DynamicColorBuilder(
      builder: (light, dark) => MaterialApp(
        title: 'Velksync',
        debugShowCheckedModeBanner: false,
        scaffoldMessengerKey: scaffoldMessengerKey,
        theme: buildTheme(schemeFrom(light, Brightness.light)),
        darkTheme: buildTheme(schemeFrom(dark, Brightness.dark)),
        home: HomeScreen(messenger: scaffoldMessengerKey),
      ),
    );
  }
}
