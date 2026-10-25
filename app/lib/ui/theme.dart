import 'package:material_ui/material_ui.dart';
import 'package:google_fonts/google_fonts.dart';

/// Rounding scale from Caelestia (quickshell), which follows Material 3 Expressive.
abstract final class Radii {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double lgPlus = 20;
  static const double xl = 28;
  static const double xlPlus = 32;
  static const double xxl = 48;
}

/// Caelestia's expressive motion tokens: spatial curves overshoot like a spring,
/// effect curves (color, opacity) settle without bouncing.
abstract final class Motion {
  static const spatial = Cubic(0.38, 1.21, 0.22, 1);
  static const spatialFast = Cubic(0.42, 1.67, 0.21, 0.9);
  static const effects = Cubic(0.34, 0.8, 0.34, 1);
  static const spatialDuration = Duration(milliseconds: 500);
  static const spatialFastDuration = Duration(milliseconds: 350);
  static const effectsDuration = Duration(milliseconds: 200);
}

/// Used when the phone has no wallpaper colors (Android < 12, iOS).
const fallbackSeed = Color(0xFF8B7CF6);

/// Wallpaper colors from Android come without the newer surface container
/// roles, so the scheme is regenerated from their primary color.
ColorScheme schemeFrom(ColorScheme? dynamic, Brightness brightness) =>
    ColorScheme.fromSeed(seedColor: dynamic?.primary ?? fallbackSeed, brightness: brightness);

TextStyle monoStyle({double size = 13, Color? color}) =>
    GoogleFonts.cascadiaCode(fontSize: size, height: 1.45, color: color);

ThemeData buildTheme(ColorScheme scheme) {
  final base = ThemeData(colorScheme: scheme);
  final text = GoogleFonts.googleSansFlexTextTheme(base.textTheme)
      .apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);
  const stadium = StadiumBorder();
  RoundedRectangleBorder rounded(double r) => RoundedRectangleBorder(borderRadius: BorderRadius.circular(r));
  // Underline (estilo "filled" do M3): o rótulo flutua dentro do campo, não na borda.
  UnderlineInputBorder field([BorderSide side = BorderSide.none]) =>
      UnderlineInputBorder(borderRadius: BorderRadius.circular(Radii.lg), borderSide: side);

  return base.copyWith(
    textTheme: text,
    scaffoldBackgroundColor: scheme.surface,
    // Volta preditiva do Android 14+: a tela acompanha o gesto e revela a de
    // trás; fora do gesto, cai no fade forwards do Android 16.
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {TargetPlatform.android: PredictiveBackPageTransitionsBuilder()},
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    iconTheme: IconThemeData(color: scheme.onSurfaceVariant, weight: 500),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainer,
      shape: rounded(Radii.xl),
      clipBehavior: Clip.antiAlias,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 56),
        padding: const EdgeInsets.symmetric(horizontal: 28),
        shape: stadium,
        textStyle: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: stadium,
        textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primaryContainer,
      foregroundColor: scheme.onPrimaryContainer,
      elevation: 2,
      highlightElevation: 2,
      shape: rounded(Radii.lgPlus),
      extendedTextStyle: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      border: field(),
      enabledBorder: field(),
      focusedBorder: field(BorderSide(color: scheme.primary, width: 2)),
      errorBorder: field(BorderSide(color: scheme.error)),
      focusedErrorBorder: field(BorderSide(color: scheme.error, width: 2)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: text.bodyMedium?.copyWith(color: scheme.onInverseSurface),
      shape: rounded(Radii.lg),
      insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerHigh,
      shape: rounded(Radii.xl),
      titleTextStyle: text.headlineSmall,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.xl))),
    ),
    // ignore: deprecated_member_use
    progressIndicatorTheme: const ProgressIndicatorThemeData(year2023: false),
  );
}
