import 'package:flutter/material.dart';

/// Shared visual tokens and reusable presentation primitives for NightLink.
/// Keep this file presentation-only: it contains no app state or backend code.
abstract final class NightLinkDesign {
  static const background = Color(0xFF090D18);
  static const backgroundRaised = Color(0xFF111827);
  static const surface = Color(0xFF151D2E);
  static const surfaceRaised = Color(0xFF1B263A);
  static const gold = Color(0xFFFFC857);
  static const blue = Color(0xFF2589FF);
  static const text = Color(0xFFFFFFFF);
  static const textMuted = Color(0xFFAAB4C5);
  static const success = Color(0xFF22C55E);
  static const error = Color(0xFFEF4444);
  static const radius = 22.0;

  static ThemeData theme() {
    final base = ThemeData.dark();
    final scheme = const ColorScheme.dark(
      primary: gold,
      secondary: blue,
      surface: surface,
      error: error,
      onPrimary: background,
      onSecondary: text,
      onSurface: text,
      onError: text,
    );
    return base.copyWith(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        foregroundColor: text,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: text,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: .4,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: BorderSide(color: Colors.white.withOpacity(.055)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        hintStyle: const TextStyle(color: textMuted),
        labelStyle: const TextStyle(color: textMuted),
        prefixIconColor: textMuted,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white.withOpacity(.08)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white.withOpacity(.08)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: gold, width: 1.4),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: gold,
          foregroundColor: background,
          disabledBackgroundColor: gold.withOpacity(.24),
          disabledForegroundColor: textMuted,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: .3),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: text,
          side: BorderSide(color: blue.withOpacity(.6)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        ),
      ),
      dividerTheme: DividerThemeData(color: Colors.white.withOpacity(.08), thickness: 1),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceRaised,
        contentTextStyle: const TextStyle(color: text),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  static BoxDecoration surfaceDecoration({
    Color? accent,
    bool gradient = false,
    double radius = NightLinkDesign.radius,
  }) {
    final color = accent ?? gold;
    return BoxDecoration(
      color: gradient ? null : surface,
      gradient: gradient
          ? const LinearGradient(
              colors: [Color(0xFF1A2B45), Color(0xFF111827)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            )
          : null,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: color.withOpacity(.18)),
      boxShadow: [
        BoxShadow(
          color: color.withOpacity(.045),
          blurRadius: 22,
          offset: const Offset(0, 10),
        ),
      ],
    );
  }

  static Widget eyebrow(String text, {Color color = blue}) => Text(
        text.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.25,
        ),
      );

  static Widget avatar({
    required String name,
    String? imageUrl,
    double radius = 24,
    Color accent = blue,
  }) {
    final initials = name.trim().isEmpty
        ? 'N'
        : name.trim().split(RegExp(r'\s+')).take(2).map((part) => part[0]).join().toUpperCase();
    final url = imageUrl?.trim();
    return CircleAvatar(
      radius: radius,
      backgroundColor: accent.withOpacity(.16),
      backgroundImage: url == null || url.isEmpty ? null : NetworkImage(url),
      onBackgroundImageError: url == null || url.isEmpty ? null : (_, __) {},
      child: url == null || url.isEmpty
          ? Text(initials, style: TextStyle(color: accent, fontWeight: FontWeight.w700))
          : null,
    );
  }
}

class NightLinkPanel extends StatelessWidget {
  const NightLinkPanel({
    super.key,
    required this.child,
    this.accent = NightLinkDesign.blue,
    this.gradient = false,
    this.padding = const EdgeInsets.all(18),
    this.radius = NightLinkDesign.radius,
  });

  final Widget child;
  final Color accent;
  final bool gradient;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: NightLinkDesign.surfaceDecoration(
          accent: accent,
          gradient: gradient,
          radius: radius,
        ),
        child: child,
      );
}
