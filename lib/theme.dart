import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'ui/motion.dart';

abstract final class LinqoColors {
  static const canvas = Color(0xFFF8F4FF);
  static const ink = Color(0xFF30134D);
  static const purple = Color(0xFF7435C9);
  static const lavender = Color(0xFFEAD9FF);
  static const mint = Color(0xFF9AF1CE);
  static const yellow = Color(0xFFFFDB79);
  static const pink = Color(0xFFF3B3DD);
  static const lilac = Color(0xFFDCC5FA);
}

ThemeData linqoTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: LinqoColors.purple,
        brightness: brightness,
      ).copyWith(
        surface: dark ? const Color(0xFF281D36) : Colors.white,
        surfaceContainerLow: dark
            ? const Color(0xFF21172E)
            : const Color(0xFFF2EAFB),
        surfaceContainer: dark
            ? const Color(0xFF30223F)
            : const Color(0xFFF0E5FC),
        surfaceContainerHighest: dark
            ? const Color(0xFF3C2B4E)
            : LinqoColors.lavender,
        onSurface: dark ? const Color(0xFFF8F0FF) : LinqoColors.ink,
        onSurfaceVariant: dark
            ? const Color(0xFFCEBDDD)
            : const Color(0xFF705E82),
        primary: dark ? const Color(0xFFC59AFF) : LinqoColors.purple,
        onPrimary: dark ? LinqoColors.ink : Colors.white,
        primaryContainer: dark ? const Color(0xFF4B2C68) : LinqoColors.lavender,
        onPrimaryContainer: dark ? const Color(0xFFF2E4FF) : LinqoColors.ink,
        secondary: dark ? LinqoColors.mint : const Color(0xFF27684E),
        secondaryContainer: dark ? const Color(0xFF234C3D) : LinqoColors.mint,
        onSecondaryContainer: dark
            ? const Color(0xFFD0FFE9)
            : const Color(0xFF173F30),
        tertiaryContainer: dark ? const Color(0xFF5A4729) : LinqoColors.yellow,
        onTertiaryContainer: dark
            ? const Color(0xFFFFE4A0)
            : const Color(0xFF503A15),
        outline: dark ? const Color(0xFF9680AA) : const Color(0xFF9C86AE),
        outlineVariant: dark
            ? const Color(0xFF4C3A5F)
            : const Color(0xFFE5D7F3),
        error: dark ? const Color(0xFFFFAFC4) : const Color(0xFFB12450),
      );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: 'Nunito',
    visualDensity: VisualDensity.standard,
  );
  final text = base.textTheme.copyWith(
    headlineLarge: TextStyle(
      fontFamily: 'Fredoka',
      fontSize: 34,
      fontWeight: FontWeight.w600,
      letterSpacing: -.4,
      color: scheme.onSurface,
    ),
    headlineMedium: TextStyle(
      fontFamily: 'Fredoka',
      fontSize: 28,
      fontWeight: FontWeight.w600,
      color: scheme.onSurface,
    ),
    headlineSmall: TextStyle(
      fontFamily: 'Fredoka',
      fontSize: 24,
      fontWeight: FontWeight.w500,
      color: scheme.onSurface,
    ),
    titleLarge: TextStyle(
      fontFamily: 'Fredoka',
      fontSize: 21,
      fontWeight: FontWeight.w500,
      color: scheme.onSurface,
    ),
    titleMedium: TextStyle(
      fontFamily: 'Nunito',
      fontSize: 16,
      height: 1.3,
      fontWeight: FontWeight.w800,
      color: scheme.onSurface,
    ),
    titleSmall: TextStyle(
      fontFamily: 'Nunito',
      fontSize: 14,
      fontWeight: FontWeight.w800,
      color: scheme.onSurface,
    ),
    bodyLarge: TextStyle(
      fontFamily: 'Nunito',
      fontSize: 16,
      height: 1.5,
      fontWeight: FontWeight.w500,
      color: scheme.onSurface,
    ),
    bodyMedium: TextStyle(
      fontFamily: 'Nunito',
      fontSize: 14,
      height: 1.45,
      fontWeight: FontWeight.w500,
      color: scheme.onSurface,
    ),
    bodySmall: TextStyle(
      fontFamily: 'Nunito',
      fontSize: 13,
      height: 1.4,
      fontWeight: FontWeight.w500,
      color: scheme.onSurfaceVariant,
    ),
    labelLarge: const TextStyle(
      fontFamily: 'Nunito',
      fontSize: 15,
      fontWeight: FontWeight.w800,
    ),
    labelMedium: const TextStyle(
      fontFamily: 'Nunito',
      fontSize: 13,
      fontWeight: FontWeight.w800,
    ),
    labelSmall: const TextStyle(
      fontFamily: 'Nunito',
      fontSize: 11,
      fontWeight: FontWeight.w700,
    ),
  );
  final fieldShape = OutlineInputBorder(
    borderRadius: BorderRadius.circular(20),
    borderSide: BorderSide(color: scheme.outlineVariant, width: 1.3),
  );
  return base.copyWith(
    splashFactory: NoSplash.splashFactory,
    splashColor: Colors.transparent,
    highlightColor: Colors.transparent,
    hoverColor: scheme.primary.withValues(alpha: .04),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {TargetPlatform.android: LinqoTransitions()},
    ),
    textTheme: text,
    scaffoldBackgroundColor: dark
        ? const Color(0xFF191121)
        : LinqoColors.canvas,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: scheme.onSurface,
      titleTextStyle: text.titleLarge,
      scrolledUnderElevation: 0,
      systemOverlayStyle:
          (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
              .copyWith(
                statusBarColor: Colors.transparent,
                systemNavigationBarColor: scheme.surface,
                systemNavigationBarIconBrightness: dark
                    ? Brightness.light
                    : Brightness.dark,
              ),
    ),
    cardTheme: CardThemeData(
      color: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: .6)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surface,
      border: fieldShape,
      enabledBorder: fieldShape,
      focusedBorder: fieldShape.copyWith(
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
      contentPadding: const EdgeInsets.all(18),
      labelStyle: TextStyle(
        color: scheme.onSurfaceVariant,
        fontWeight: FontWeight.w600,
      ),
      hintStyle: TextStyle(
        color: scheme.onSurfaceVariant,
        fontWeight: FontWeight.w500,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        overlayColor: Colors.transparent,
        minimumSize: const Size(48, 54),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        textStyle: text.labelLarge,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        overlayColor: Colors.transparent,
        minimumSize: const Size(48, 50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        side: BorderSide(color: scheme.outline),
        textStyle: text.labelLarge,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        overlayColor: Colors.transparent,
        minimumSize: const Size(48, 48),
        textStyle: text.labelLarge,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(48, 48),
        overlayColor: Colors.transparent,
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      color: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? scheme.primaryContainer
            : scheme.surface,
      ),
      iconTheme: IconThemeData(color: scheme.primary),
      surfaceTintColor: Colors.transparent,
      pressElevation: 0,
      backgroundColor: scheme.surface,
      selectedColor: scheme.primaryContainer,
      checkmarkColor: scheme.primary,
      side: BorderSide(color: scheme.outlineVariant),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      labelStyle: text.labelLarge?.copyWith(color: scheme.onSurface),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      elevation: 0,
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      extendedTextStyle: text.labelLarge,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      overlayColor: WidgetStatePropertyAll(Colors.transparent),
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      indicatorColor: scheme.primaryContainer,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => text.labelMedium!.copyWith(
          color: states.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.onSurfaceVariant,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.onSurfaceVariant,
        ),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      indicatorColor: scheme.primaryContainer,
      selectedIconTheme: IconThemeData(color: scheme.primary),
      selectedLabelTextStyle: text.labelMedium?.copyWith(color: scheme.primary),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: dark ? LinqoColors.lavender : LinqoColors.ink,
      contentTextStyle: text.bodyMedium?.copyWith(
        color: dark ? LinqoColors.ink : Colors.white,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
    dividerColor: scheme.outlineVariant,
    progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: scheme.primary,
      selectionColor: scheme.primary.withValues(alpha: .2),
      selectionHandleColor: scheme.primary,
    ),
  );
}
