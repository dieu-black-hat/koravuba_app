import 'package:flutter/material.dart';

/// KoraVuba palette (dark slate + emerald, from the new design).
class Kv {
  Kv._();

  // brand (blue KV logo)
  static const brand = Color(0xFF1E6BFF);
  static const brandLight = Color(0xFF4A8BFF);
  static const orange = Color(0xFFFF5A00);
  static const orangeLight = Color(0xFFFF7A00);
  static const orangeDark = Color(0xFFE83B00);

  // role accents
  static const emerald = Color(0xFF10B981);
  static const emeraldLight = Color(0xFF34D399);
  static const amber = Color(0xFFF59E0B);
  static const amberLight = Color(0xFFFBBF24);
  static const blue = Color(0xFF3B82F6);
  static const blueLight = Color(0xFF60A5FA);
  static const purple = Color(0xFFA855F7);
  static const purpleLight = Color(0xFFC084FC);
  static const pink = Color(0xFFEC4899);
  static const red = Color(0xFFEF4444);
  static const sky = Color(0xFF0EA5E9);
  static const teal = Color(0xFF14B8A6);
  static const violet = Color(0xFF8B5CF6);
  static const yellow = Color(0xFFEAB308);

  // slate scale
  static const s950 = Color(0xFF020617);
  static const s900 = Color(0xFF0F172A);
  static const s800 = Color(0xFF1E293B);
  static const s700 = Color(0xFF334155);
  static const s600 = Color(0xFF475569);
  static const s500 = Color(0xFF64748B);
  static const s400 = Color(0xFF94A3B8);
  static const s300 = Color(0xFFCBD5E1);
  static const s200 = Color(0xFFE2E8F0);
  static const s100 = Color(0xFFF1F5F9);
  static const s50 = Color(0xFFF8FAFC);

  static const mono = 'monospace';

  static const brandGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [orangeLight, orange, orangeDark],
  );

  static Color named(String? name) => switch (name) {
        'amber' => amber,
        'blue' => blue,
        'violet' => violet,
        'pink' => pink,
        'yellow' => yellow,
        'sky' => sky,
        'teal' => teal,
        'purple' => purple,
        'red' => red,
        _ => emerald,
      };
}

Color fade(Color c, double opacity) => c.withValues(alpha: opacity);

/// Surface colours that change with light / dark mode.
@immutable
class KvColors extends ThemeExtension<KvColors> {
  const KvColors({
    required this.bg,
    required this.card,
    required this.cardAlt,
    required this.border,
    required this.text,
    required this.muted,
    required this.faint,
    required this.isDark,
  });

  final Color bg;
  final Color card;
  final Color cardAlt;
  final Color border;
  final Color text;
  final Color muted;
  final Color faint;
  final bool isDark;

  static const dark = KvColors(
    bg: Kv.s950,
    card: Kv.s900,
    cardAlt: Color(0xFF0B1222),
    border: Kv.s800,
    text: Colors.white,
    muted: Kv.s400,
    faint: Kv.s500,
    isDark: true,
  );

  static const light = KvColors(
    bg: Kv.s100,
    card: Colors.white,
    cardAlt: Kv.s50,
    border: Kv.s200,
    text: Kv.s900,
    muted: Kv.s600,
    faint: Kv.s500,
    isDark: false,
  );

  @override
  KvColors copyWith({Color? bg, Color? card, Color? cardAlt, Color? border, Color? text, Color? muted, Color? faint, bool? isDark}) =>
      KvColors(
        bg: bg ?? this.bg,
        card: card ?? this.card,
        cardAlt: cardAlt ?? this.cardAlt,
        border: border ?? this.border,
        text: text ?? this.text,
        muted: muted ?? this.muted,
        faint: faint ?? this.faint,
        isDark: isDark ?? this.isDark,
      );

  @override
  KvColors lerp(ThemeExtension<KvColors>? other, double t) {
    if (other is! KvColors) return this;
    return KvColors(
      bg: Color.lerp(bg, other.bg, t)!,
      card: Color.lerp(card, other.card, t)!,
      cardAlt: Color.lerp(cardAlt, other.cardAlt, t)!,
      border: Color.lerp(border, other.border, t)!,
      text: Color.lerp(text, other.text, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      faint: Color.lerp(faint, other.faint, t)!,
      isDark: t < 0.5 ? isDark : other.isDark,
    );
  }
}

extension KvContext on BuildContext {
  KvColors get kv => Theme.of(this).extension<KvColors>() ?? KvColors.dark;
}

ThemeData buildTheme(Brightness brightness) {
  final c = brightness == Brightness.dark ? KvColors.dark : KvColors.light;
  final scheme = ColorScheme.fromSeed(
    seedColor: Kv.emerald,
    brightness: brightness,
    primary: Kv.emerald,
    secondary: Kv.amber,
    surface: c.card,
    error: Kv.red,
  );
  final base = ThemeData(useMaterial3: true, brightness: brightness, colorScheme: scheme);
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: BorderSide(color: c.border),
  );
  return base.copyWith(
    scaffoldBackgroundColor: c.bg,
    extensions: [c],
    textTheme: base.textTheme.apply(bodyColor: c.text, displayColor: c.text),
    appBarTheme: AppBarTheme(
      backgroundColor: c.bg,
      foregroundColor: c.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(color: c.text, fontSize: 18, fontWeight: FontWeight.w800),
    ),
    dividerTheme: DividerThemeData(color: c.border, thickness: 1, space: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.isDark ? Kv.s950 : Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(borderSide: const BorderSide(color: Kv.emerald, width: 1.4)),
      errorBorder: border.copyWith(borderSide: const BorderSide(color: Kv.red)),
      hintStyle: TextStyle(color: c.faint, fontSize: 14),
      labelStyle: TextStyle(color: c.muted),
      prefixIconColor: c.muted,
      suffixIconColor: c.muted,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.card,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      showDragHandle: true,
      dragHandleColor: c.border,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: c.isDark ? Kv.s800 : Kv.s900,
      contentTextStyle: const TextStyle(color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    sliderTheme: base.sliderTheme.copyWith(
      activeTrackColor: Kv.emerald,
      inactiveTrackColor: c.border,
      thumbColor: Kv.emerald,
      overlayColor: fade(Kv.emerald, 0.15),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : Kv.s400),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Kv.emerald : c.border),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: Kv.emerald),
  );
}
