// ============================================================================
// si_theme.dart
// Sistemassi — Enterprise Quiet Design System (Flutter tokens)
//
// Uso:
//   1) pubspec.yaml:
//        dependencies:
//          google_fonts: ^6.2.1
//   2) main.dart:
//        import 'theme/si_theme.dart';
//        MaterialApp(theme: SiTheme.light, darkTheme: SiTheme.dark, ...)
//   3) En widgets:
//        final c = SiColors.of(context);
//        Container(color: c.panel, ...)
// ============================================================================

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ----------------------------------------------------------------------------
// 1) COLOR TOKENS
// ----------------------------------------------------------------------------

class SiColors extends ThemeExtension<SiColors> {
  // Brand
  final Color brand;
  final Color brandInk;
  final Color brandTint;
  final Color brandHover;

  // Surface / neutrals (cool scale)
  final Color bg;
  final Color panel;
  final Color ink;      // primary text
  final Color ink2;     // secondary
  final Color ink3;     // tertiary / muted
  final Color ink4;     // disabled / icons
  final Color line;     // 1px borders
  final Color line2;    // subtle dividers
  final Color hover;
  final Color active;

  // Semantic
  final Color success;
  final Color successTint;
  final Color warn;
  final Color warnTint;
  final Color danger;
  final Color dangerTint;

  const SiColors({
    required this.brand,
    required this.brandInk,
    required this.brandTint,
    required this.brandHover,
    required this.bg,
    required this.panel,
    required this.ink,
    required this.ink2,
    required this.ink3,
    required this.ink4,
    required this.line,
    required this.line2,
    required this.hover,
    required this.active,
    required this.success,
    required this.successTint,
    required this.warn,
    required this.warnTint,
    required this.danger,
    required this.dangerTint,
  });

  static const light = SiColors(
    brand:       Color(0xFF344092),
    brandInk:    Color(0xFF1A2466),
    brandTint:   Color(0xFFEFF1FA), // oklch(0.96 0.02 265)
    brandHover:  Color(0xFF2A3577),

    bg:          Color(0xFFFBFBFC), // oklch(0.992 0.003 250)
    panel:       Color(0xFFFFFFFF),
    ink:         Color(0xFF1C2030), // oklch(0.20 0.02 260)
    ink2:        Color(0xFF4A5068), // oklch(0.38 0.02 260)
    ink3:        Color(0xFF737A92), // oklch(0.55 0.015 260)
    ink4:        Color(0xFFA2A7B8), // oklch(0.70 0.012 260)
    line:        Color(0xFFE4E6EC), // oklch(0.92 0.006 260)
    line2:       Color(0xFFEEF0F4), // oklch(0.95 0.005 260)
    hover:       Color(0xFFF4F5F8), // oklch(0.97 0.006 260)
    active:      Color(0xFFEAECF2), // oklch(0.94 0.012 265)

    success:     Color(0xFF2E9460),
    successTint: Color(0xFFEAF6EE),
    warn:        Color(0xFFD99531),
    warnTint:    Color(0xFFFCF4E4),
    danger:      Color(0xFFC93B2E),
    dangerTint:  Color(0xFFF9E9E6),
  );

  static const dark = SiColors(
    brand:       Color(0xFF6B7BD6),
    brandInk:    Color(0xFF8B9AE8),
    brandTint:   Color(0xFF1E2340),
    brandHover:  Color(0xFF7D8DE0),

    bg:          Color(0xFF0D0F14),
    panel:       Color(0xFF14171F),
    ink:         Color(0xFFEEF0F5),
    ink2:        Color(0xFFB8BCCB),
    ink3:        Color(0xFF8A90A3),
    ink4:        Color(0xFF5C6278),
    line:        Color(0xFF24283A),
    line2:       Color(0xFF1C2030),
    hover:       Color(0xFF1A1E2B),
    active:      Color(0xFF232841),

    success:     Color(0xFF49B27E),
    successTint: Color(0xFF18291E),
    warn:        Color(0xFFE8AE56),
    warnTint:    Color(0xFF2D2416),
    danger:      Color(0xFFE56155),
    dangerTint:  Color(0xFF2D1915),
  );

  static SiColors of(BuildContext ctx) =>
      Theme.of(ctx).extension<SiColors>() ?? SiColors.light;

  @override
  SiColors copyWith({
    Color? brand, Color? brandInk, Color? brandTint, Color? brandHover,
    Color? bg, Color? panel,
    Color? ink, Color? ink2, Color? ink3, Color? ink4,
    Color? line, Color? line2, Color? hover, Color? active,
    Color? success, Color? successTint,
    Color? warn, Color? warnTint,
    Color? danger, Color? dangerTint,
  }) {
    return SiColors(
      brand: brand ?? this.brand,
      brandInk: brandInk ?? this.brandInk,
      brandTint: brandTint ?? this.brandTint,
      brandHover: brandHover ?? this.brandHover,
      bg: bg ?? this.bg,
      panel: panel ?? this.panel,
      ink: ink ?? this.ink,
      ink2: ink2 ?? this.ink2,
      ink3: ink3 ?? this.ink3,
      ink4: ink4 ?? this.ink4,
      line: line ?? this.line,
      line2: line2 ?? this.line2,
      hover: hover ?? this.hover,
      active: active ?? this.active,
      success: success ?? this.success,
      successTint: successTint ?? this.successTint,
      warn: warn ?? this.warn,
      warnTint: warnTint ?? this.warnTint,
      danger: danger ?? this.danger,
      dangerTint: dangerTint ?? this.dangerTint,
    );
  }

  @override
  SiColors lerp(ThemeExtension<SiColors>? other, double t) {
    if (other is! SiColors) return this;
    return SiColors(
      brand: Color.lerp(brand, other.brand, t)!,
      brandInk: Color.lerp(brandInk, other.brandInk, t)!,
      brandTint: Color.lerp(brandTint, other.brandTint, t)!,
      brandHover: Color.lerp(brandHover, other.brandHover, t)!,
      bg: Color.lerp(bg, other.bg, t)!,
      panel: Color.lerp(panel, other.panel, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      ink2: Color.lerp(ink2, other.ink2, t)!,
      ink3: Color.lerp(ink3, other.ink3, t)!,
      ink4: Color.lerp(ink4, other.ink4, t)!,
      line: Color.lerp(line, other.line, t)!,
      line2: Color.lerp(line2, other.line2, t)!,
      hover: Color.lerp(hover, other.hover, t)!,
      active: Color.lerp(active, other.active, t)!,
      success: Color.lerp(success, other.success, t)!,
      successTint: Color.lerp(successTint, other.successTint, t)!,
      warn: Color.lerp(warn, other.warn, t)!,
      warnTint: Color.lerp(warnTint, other.warnTint, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      dangerTint: Color.lerp(dangerTint, other.dangerTint, t)!,
    );
  }
}

// ----------------------------------------------------------------------------
// 2) SHAPE / RADIUS
// ----------------------------------------------------------------------------

class SiRadius {
  static const double sm = 6;
  static const double md = 8;
  static const double lg = 10;
  static const double xl = 14;

  static const rSm  = BorderRadius.all(Radius.circular(sm));
  static const rMd  = BorderRadius.all(Radius.circular(md));
  static const rLg  = BorderRadius.all(Radius.circular(lg));
  static const rXl  = BorderRadius.all(Radius.circular(xl));
  static const rPill = BorderRadius.all(Radius.circular(999));
}

// ----------------------------------------------------------------------------
// 3) SPACING (4px base)
// ----------------------------------------------------------------------------

class SiSpace {
  static const double x05 = 2;
  static const double x1  = 4;
  static const double x2  = 8;
  static const double x3  = 12;
  static const double x4  = 16;
  static const double x5  = 20;
  static const double x6  = 24;
  static const double x8  = 32;
  static const double x10 = 40;
  static const double x12 = 48;
}

// ----------------------------------------------------------------------------
// 4) LAYOUT CONSTANTS
// ----------------------------------------------------------------------------

class SiLayout {
  static const double railCollapsed = 60;
  static const double railExpanded  = 248;
  static const double headerHeight  = 52;
}

// ----------------------------------------------------------------------------
// 5) SHADOWS (used sparingly — prefer 1px borders)
// ----------------------------------------------------------------------------

class SiShadows {
  static const sm = [
    BoxShadow(
      color: Color(0xFFE4E6EC),
      offset: Offset(0, 1),
      blurRadius: 0,
    ),
  ];

  static const md = [
    BoxShadow(
      color: Color(0x0A1A2466), // rgba(26,36,102,0.04)
      offset: Offset(0, 1),
      blurRadius: 2,
    ),
  ];

  static const lg = [
    BoxShadow(
      color: Color(0x2E1A2466), // rgba(26,36,102,0.18)
      offset: Offset(0, 12),
      blurRadius: 32,
      spreadRadius: -8,
    ),
  ];
}

// ----------------------------------------------------------------------------
// 6) TYPOGRAPHY — Geist + Geist Mono via google_fonts
// ----------------------------------------------------------------------------

class SiType {
  static TextTheme textTheme(Color ink, Color ink2) {
    final base = GoogleFonts.geistTextTheme();
    return base.copyWith(
      displayLarge:  _t(base.displayLarge,  size: 40, weight: FontWeight.w600, color: ink, letter: -0.02),
      displayMedium: _t(base.displayMedium, size: 32, weight: FontWeight.w600, color: ink, letter: -0.02),
      headlineLarge: _t(base.headlineLarge, size: 24, weight: FontWeight.w600, color: ink, letter: -0.015),
      headlineMedium:_t(base.headlineMedium,size: 20, weight: FontWeight.w600, color: ink, letter: -0.01),
      titleLarge:    _t(base.titleLarge,    size: 16, weight: FontWeight.w600, color: ink, letter: -0.005),
      titleMedium:   _t(base.titleMedium,   size: 14, weight: FontWeight.w500, color: ink),
      bodyLarge:     _t(base.bodyLarge,     size: 14, weight: FontWeight.w400, color: ink),
      bodyMedium:    _t(base.bodyMedium,    size: 13, weight: FontWeight.w400, color: ink2),
      bodySmall:     _t(base.bodySmall,     size: 12, weight: FontWeight.w400, color: ink2),
      labelLarge:    _t(base.labelLarge,    size: 13, weight: FontWeight.w500, color: ink),
      labelMedium:   _t(base.labelMedium,   size: 12, weight: FontWeight.w500, color: ink2),
      labelSmall:    _t(base.labelSmall,    size: 11, weight: FontWeight.w500, color: ink2, letter: 0.02),
    );
  }

  static TextStyle mono({
    double size = 12,
    FontWeight weight = FontWeight.w400,
    Color? color,
  }) {
    return GoogleFonts.geistMono(
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: 0,
    );
  }

  static TextStyle _t(TextStyle? b, {
    required double size,
    required FontWeight weight,
    required Color color,
    double letter = 0,
  }) {
    return (b ?? const TextStyle()).copyWith(
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: letter * size,
      height: 1.5,
    );
  }
}

// ----------------------------------------------------------------------------
// 7) DURATIONS & CURVES (micro-interacciones)
// ----------------------------------------------------------------------------

class SiMotion {
  static const fast    = Duration(milliseconds: 120);
  static const normal  = Duration(milliseconds: 180);
  static const slow    = Duration(milliseconds: 260);
  static const railExpand = Duration(milliseconds: 220);

  static const easeOut    = Cubic(0.2, 0.8, 0.2, 1.0);
  static const easeInOut  = Cubic(0.4, 0.0, 0.2, 1.0);
  static const spring     = Cubic(0.34, 1.56, 0.64, 1.0);
}

// ----------------------------------------------------------------------------
// 8) THEME DATA — Light & Dark
// ----------------------------------------------------------------------------

class SiTheme {
  static ThemeData get light => _build(SiColors.light, Brightness.light);
  static ThemeData get dark  => _build(SiColors.dark,  Brightness.dark);

  static ThemeData _build(SiColors c, Brightness b) {
    final textTheme = SiType.textTheme(c.ink, c.ink2);

    return ThemeData(
      useMaterial3: true,
      brightness: b,
      scaffoldBackgroundColor: c.bg,
      canvasColor: c.panel,
      dividerColor: c.line,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.compact,

      colorScheme: ColorScheme(
        brightness: b,
        primary: c.brand,
        onPrimary: Colors.white,
        primaryContainer: c.brandTint,
        onPrimaryContainer: c.brandInk,
        secondary: c.ink2,
        onSecondary: c.panel,
        secondaryContainer: c.hover,
        onSecondaryContainer: c.ink,
        error: c.danger,
        onError: Colors.white,
        errorContainer: c.dangerTint,
        onErrorContainer: c.danger,
        surface: c.panel,
        onSurface: c.ink,
        surfaceContainerHighest: c.hover,
        outline: c.line,
        outlineVariant: c.line2,
        shadow: Colors.black,
        scrim: Colors.black54,
        inverseSurface: c.ink,
        onInverseSurface: c.panel,
        inversePrimary: c.brandTint,
      ),

      textTheme: textTheme,
      primaryTextTheme: textTheme,

      extensions: <ThemeExtension<dynamic>>[c],

      // ---- AppBar ----
      appBarTheme: AppBarTheme(
        backgroundColor: c.panel,
        foregroundColor: c.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: SiLayout.headerHeight,
        shape: Border(bottom: BorderSide(color: c.line, width: 1)),
        titleTextStyle: textTheme.titleLarge,
        iconTheme: IconThemeData(color: c.ink2, size: 18),
      ),

      // ---- Card ----
      cardTheme: CardThemeData(
        color: c.panel,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: SiRadius.rLg,
          side: BorderSide(color: c.line, width: 1),
        ),
      ),

      // ---- Buttons ----
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: c.brand,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size(0, 34),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          shape: const RoundedRectangleBorder(borderRadius: SiRadius.rMd),
          textStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w500),
        ).copyWith(
          overlayColor: WidgetStateProperty.all(c.brandHover.withValues(alpha: 0.15)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.ink,
          minimumSize: const Size(0, 34),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          side: BorderSide(color: c.line, width: 1),
          shape: const RoundedRectangleBorder(borderRadius: SiRadius.rMd),
          textStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w500),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.ink2,
          minimumSize: const Size(0, 34),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          shape: const RoundedRectangleBorder(borderRadius: SiRadius.rMd),
        ),
      ),

      // ---- Inputs ----
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.panel,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        hintStyle: textTheme.bodyMedium?.copyWith(color: c.ink4),
        labelStyle: textTheme.labelMedium,
        border: OutlineInputBorder(
          borderRadius: SiRadius.rMd,
          borderSide: BorderSide(color: c.line, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: SiRadius.rMd,
          borderSide: BorderSide(color: c.line, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: SiRadius.rMd,
          borderSide: BorderSide(color: c.brand, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: SiRadius.rMd,
          borderSide: BorderSide(color: c.danger, width: 1),
        ),
      ),

      // ---- Chips ----
      chipTheme: ChipThemeData(
        backgroundColor: c.panel,
        side: BorderSide(color: c.line, width: 1),
        labelStyle: textTheme.labelSmall?.copyWith(color: c.ink2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        shape: const RoundedRectangleBorder(borderRadius: SiRadius.rPill),
      ),

      // ---- Dividers ----
      dividerTheme: DividerThemeData(
        color: c.line,
        thickness: 1,
        space: 1,
      ),

      // ---- Nav ----
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: c.panel,
        selectedIconTheme: IconThemeData(color: c.brand, size: 18),
        unselectedIconTheme: IconThemeData(color: c.ink3, size: 18),
        selectedLabelTextStyle: textTheme.labelLarge?.copyWith(color: c.brand),
        unselectedLabelTextStyle: textTheme.labelLarge?.copyWith(color: c.ink2),
        indicatorColor: c.brandTint,
        useIndicator: true,
      ),

      // ---- ListTile ----
      listTileTheme: ListTileThemeData(
        minVerticalPadding: 8,
        dense: true,
        iconColor: c.ink3,
        textColor: c.ink,
        shape: const RoundedRectangleBorder(borderRadius: SiRadius.rMd),
        selectedColor: c.brand,
        selectedTileColor: c.brandTint,
        hoverColor: c.hover,
      ),

      // ---- Tooltip ----
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: c.ink,
          borderRadius: SiRadius.rSm,
        ),
        textStyle: textTheme.labelSmall?.copyWith(color: c.panel),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        waitDuration: const Duration(milliseconds: 400),
      ),

      // ---- Scrollbar ----
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(c.ink4.withValues(alpha: 0.4)),
        thickness: WidgetStateProperty.all(6),
        radius: const Radius.circular(3),
      ),

      // ---- Dialogs ----
      dialogTheme: DialogThemeData(
        backgroundColor: c.panel,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: SiRadius.rXl),
      ),
    );
  }
}
