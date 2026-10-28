import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ui/palettes.dart';

enum ThemeFamily {
  dynamic('Dinâmico', 'Cores do papel de parede'),
  velksync('Velksync', 'Gelo e marinho, as cores do ícone'),
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
  static const _gruvboxAccentKey = 'theme_gruvbox_accent', _catppuccinAccentKey = 'theme_catppuccin_accent';
  static const _gruvboxIntensityKey = 'theme_gruvbox_intensity';
  static const _catppuccinIntensityKey = 'theme_catppuccin_intensity';

  ThemeFamily family = ThemeFamily.dynamic;
  ThemeMode mode = ThemeMode.system;
  // Padrão nas versões suaves; as saturadas continuam a uma escolha de distância.
  GruvboxVariant gruvbox = GruvboxVariant.soft;
  CatppuccinFlavor catppuccin = CatppuccinFlavor.frappe;

  /// Destaque escolhido (id de [Palettes.gruvboxAccents] ou [Palettes.catppuccinAccents]);
  /// null usa o padrão (laranja no Gruvbox, verde no Suave, mauve no Catppuccin).
  String? gruvboxAccent, catppuccinAccent;

  /// Intensidade escolhida; null usa o padrão (Bem pastel, ou Vivo no Gruvbox Original).
  ThemeIntensity? gruvboxIntensity, catppuccinIntensity;

  /// Intensidade em uso na família atual (a escolhida ou a padrão).
  ThemeIntensity get intensity => switch (family) {
    ThemeFamily.gruvbox => gruvboxIntensity ?? Palettes.defaultIntensity(gruvbox),
    _ => catppuccinIntensity ?? ThemeIntensity.soft,
  };

  Future<void> setIntensity(ThemeIntensity i) async {
    final String key;
    if (family == ThemeFamily.gruvbox) {
      gruvboxIntensity = i;
      key = _gruvboxIntensityKey;
    } else if (family == ThemeFamily.catppuccin) {
      catppuccinIntensity = i;
      key = _catppuccinIntensityKey;
    } else {
      return;
    }
    notifyListeners();
    await (await SharedPreferences.getInstance()).setString(key, i.name);
  }

  /// Paletas (clara, escura) da família escolhida; null no tema dinâmico.
  (Palette, Palette)? get palettes => switch (family) {
    ThemeFamily.dynamic => null,
    ThemeFamily.velksync => Palettes.velksync,
    ThemeFamily.gruvbox => Palettes.gruvbox(gruvbox, gruvboxAccent, gruvboxIntensity),
    ThemeFamily.catppuccin => Palettes.catppuccin(catppuccin, catppuccinAccent, catppuccinIntensity),
  };

  /// Destaques da família atual, para o seletor (vazio sem seletor).
  List<Accent> get accentOptions => switch (family) {
    ThemeFamily.gruvbox => Palettes.gruvboxAccents,
    ThemeFamily.catppuccin => Palettes.catppuccinAccents,
    _ => const [],
  };

  Future<void> setAccent(String id) async {
    final key = switch (family) {
      ThemeFamily.gruvbox => _gruvboxAccentKey,
      ThemeFamily.catppuccin => _catppuccinAccentKey,
      _ => null,
    };
    if (key == null) return;
    if (family == ThemeFamily.gruvbox) {
      gruvboxAccent = id;
    } else {
      catppuccinAccent = id;
    }
    notifyListeners();
    await (await SharedPreferences.getInstance()).setString(key, id);
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    family = ThemeFamily.values.asNameMap()[prefs.getString(_familyKey)] ?? ThemeFamily.dynamic;
    mode = ThemeMode.values.asNameMap()[prefs.getString(_modeKey)] ?? ThemeMode.system;
    gruvbox = GruvboxVariant.values.asNameMap()[prefs.getString(_gruvboxKey)] ?? GruvboxVariant.soft;
    catppuccin = CatppuccinFlavor.values.asNameMap()[prefs.getString(_catppuccinKey)] ?? CatppuccinFlavor.frappe;
    gruvboxAccent = prefs.getString(_gruvboxAccentKey);
    gruvboxIntensity = ThemeIntensity.values.asNameMap()[prefs.getString(_gruvboxIntensityKey)];
    catppuccinIntensity = ThemeIntensity.values.asNameMap()[prefs.getString(_catppuccinIntensityKey)];
    catppuccinAccent = prefs.getString(_catppuccinAccentKey);
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
