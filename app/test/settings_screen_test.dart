import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velksync/screens/settings_screen.dart';
import 'package:velksync/services/settings.dart';
import 'package:velksync/ui/palettes.dart';

void main() {
  test('padrão nas versões suaves', () async {
    SharedPreferences.setMockInitialValues({});
    final s = AppSettings();
    await s.load();
    expect(s.gruvbox, GruvboxVariant.soft);
    expect(s.catppuccin, CatppuccinFlavor.frappe);
    await s.setFamily(ThemeFamily.catppuccin);
    expect(s.palettes!.$2, Palettes.catppuccinFrappe);
    await s.setCatppuccin(CatppuccinFlavor.mocha);
    final again = AppSettings();
    await again.load();
    expect(again.palettes!.$2, Palettes.catppuccinMocha, reason: 'a escolha fica salva');
  });

  for (final family in [ThemeFamily.gruvbox, ThemeFamily.catppuccin]) {
    testWidgets('variantes de ${family.label} cabem na tela', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1220, 2712);
      tester.view.devicePixelRatio = 4;
      addTearDown(tester.view.reset);
      final settings = AppSettings();
      await settings.setFamily(family);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: SettingsScreen(settings: settings),
        ),
      );
      await tester.pumpAndSettle();
      final first = family == ThemeFamily.gruvbox ? 'Original' : 'Macchiato';
      await tester.scrollUntilVisible(find.text(first), 200);
      await tester.ensureVisible(find.text(first)); // inteiro na tela, não só na borda
      await tester.pumpAndSettle();
      await tester.tap(find.text(first));
      await tester.pumpAndSettle();
      if (family == ThemeFamily.gruvbox) {
        expect(settings.gruvbox, GruvboxVariant.classic);
      } else {
        expect(settings.catppuccin, CatppuccinFlavor.macchiato);
      }
    });
  }
}
