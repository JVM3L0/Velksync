import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ui/palettes.dart';

enum ThemeFamily {
  dynamic('Dinâmico', 'Cores do papel de parede'),
  gruvbox('Gruvbox', 'Retrô e quente, suave ou original'),
  catppuccin('Catppuccin', 'Pastel: Latte, Frappé, Macchiato e Mocha');

  final String label;
  final String description;
  const ThemeFamily(this.label, this.description);
}

/// Preferências visuais do app, salvas no celular.
class AppSettings extends ChangeNotifier {
  static const _familyKey = 'theme_family', _modeKey = 'theme_mode';
  static const _gruvboxKey = 'theme_gruvbox', _catppuccinKey = 'theme_catppuccin';

  ThemeFamily family = ThemeFamily.dynamic;
  ThemeMode mode = ThemeMode.system;
  // Padrão nas versões suaves; as saturadas continuam a uma escolha de distância.
  GruvboxVariant gruvbox = GruvboxVariant.soft;
  CatppuccinFlavor catppuccin = CatppuccinFlavor.frappe;

  /// Paletas (clara, escura) da família escolhida; null no tema dinâmico.
  (Palette, Palette)? get palettes => switch (family) {
    ThemeFamily.dynamic => null,
    ThemeFamily.gruvbox => Palettes.gruvbox(gruvbox),
    ThemeFamily.catppuccin => Palettes.catppuccin(catppuccin),
  };

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    family = ThemeFamily.values.asNameMap()[prefs.getString(_familyKey)] ?? ThemeFamily.dynamic;
    mode = ThemeMode.values.asNameMap()[prefs.getString(_modeKey)] ?? ThemeMode.system;
    gruvbox = GruvboxVariant.values.asNameMap()[prefs.getString(_gruvboxKey)] ?? GruvboxVariant.soft;
    catppuccin = CatppuccinFlavor.values.asNameMap()[prefs.getString(_catppuccinKey)] ?? CatppuccinFlavor.frappe;
    notifyListeners();
  }

  Future<void> setFamily(ThemeFamily f) async {
    family = f;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setString(_familyKey, f.name);
  }

  Future<void> setGruvbox(GruvboxVariant v) async {
    gruvbox = v;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setString(_gruvboxKey, v.name);
  }

  Future<void> setCatppuccin(CatppuccinFlavor f) async {
    catppuccin = f;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setString(_catppuccinKey, f.name);
  }

  Future<void> setMode(ThemeMode m) async {
    mode = m;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setString(_modeKey, m.name);
  }
}
