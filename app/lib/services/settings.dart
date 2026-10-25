import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ThemeFamily {
  dynamic('Dinâmico', 'Cores do papel de parede'),
  gruvbox('Gruvbox', 'Retrô e quente'),
  catppuccin('Catppuccin', 'Pastel, Mocha e Latte');

  final String label;
  final String description;
  const ThemeFamily(this.label, this.description);
}

/// Preferências visuais do app, salvas no celular.
class AppSettings extends ChangeNotifier {
  static const _familyKey = 'theme_family', _modeKey = 'theme_mode';

  ThemeFamily family = ThemeFamily.dynamic;
  ThemeMode mode = ThemeMode.system;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    family = ThemeFamily.values.asNameMap()[prefs.getString(_familyKey)] ?? ThemeFamily.dynamic;
    mode = ThemeMode.values.asNameMap()[prefs.getString(_modeKey)] ?? ThemeMode.system;
    notifyListeners();
  }

  Future<void> setFamily(ThemeFamily f) async {
    family = f;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setString(_familyKey, f.name);
  }

  Future<void> setMode(ThemeMode m) async {
    mode = m;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setString(_modeKey, m.name);
  }
}
