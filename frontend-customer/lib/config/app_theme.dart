// ══════════════════════════════════════════════════════════════
// Vendra App - Theme Configuration (light + dark)
// Brand and status colours are constants. Neutral surfaces, text, borders
// and the navy accent follow the active theme: they are getters that read
// the brightness ThemeScope last applied (see theme_cubit.dart), so every
// widget picks up the right shade on its next build. ThemeScope rebuilds
// the whole tree when the brightness flips, so no screen keeps stale colours.
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  AppColors._();

  // ── Brand accents ──
  static const Color primary = Color(0xFFFD761A); // Vendra orange (same as the admin panel)
  static const Color navy = Color(0xFF232774); // Vendra navy (brand surfaces, light theme accent)
  static const Color navyOnDark = Color(0xFF7178EE); // Same hue lifted for contrast on slate
  static const Color pakistanGreen = Color(0xFF01411C);

  // ── Light theme surfaces ──
  static const Color lightBackground = Color(0xFFF8F9FA);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightCard = Color(0xFFFFFFFF);
  static const Color lightSurfaceMuted = Color(0xFFF1F3F5);
  static const Color lightBorder = Color(0xFFE6E8EB);
  static const Color lightTextPrimary = Color(0xFF1A1A2E);
  static const Color lightTextSecondary = Color(0xFF6C757D);
  static const Color lightTextLight = Color(0xFF9E9E9E);

  // ── Dark theme surfaces (engineered slate, not pitch black) ──
  static const Color darkBackground = Color(0xFF0F172A);
  static const Color darkSurface = Color(0xFF1E293B);
  static const Color darkCard = Color(0xFF1E293B);
  static const Color darkSurfaceMuted = Color(0xFF273449);
  static const Color darkBorder = Color(0xFF334155);
  static const Color darkTextPrimary = Color(0xFFF8FAFC);
  static const Color darkTextSecondary = Color(0xFF94A3B8);
  static const Color darkTextLight = Color(0xFF64748B);

  // ── Semantic status ──
  static const Color success = Color(0xFF16A34A);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFEF4444);
  static const Color info = Color(0xFF3B82F6);
  static const Color stockGreen = Color(0xFF16A34A);
  static const Color stockRed = Color(0xFFEF4444);
  static const Color reservedAmber = Color(0xFFF59E0B);

  /// Brightness the theme-dependent tokens below resolve against.
  /// Written only by ThemeScope, before the tree rebuilds.
  static Brightness _brightness = Brightness.light;
  static bool get isDark => _brightness == Brightness.dark;

  // ── Theme-dependent tokens ──
  static Color get secondary => isDark ? navyOnDark : navy;
  static Color get background => isDark ? darkBackground : lightBackground;
  static Color get surface => isDark ? darkSurface : lightSurface;
  static Color get cardBg => isDark ? darkCard : lightCard;

  /// Inset fills: input backgrounds, chips, placeholders, progress tracks
  static Color get surfaceMuted => isDark ? darkSurfaceMuted : lightSurfaceMuted;

  /// Dividers and 1 px card outlines
  static Color get hairline => isDark ? darkBorder : lightBorder;
  static Color get textPrimary => isDark ? darkTextPrimary : lightTextPrimary;
  static Color get textSecondary => isDark ? darkTextSecondary : lightTextSecondary;
  static Color get textLight => isDark ? darkTextLight : lightTextLight;

  /// Notice cards: tinted surface + readable ink for that surface
  static Color get warningSurface => isDark ? const Color(0xFF3A2E12) : const Color(0xFFFFF8E1);
  static Color get warningInk => isDark ? const Color(0xFFFBBF24) : const Color(0xFF8A5A00);
  static Color get successSurface => isDark ? const Color(0xFF12352A) : const Color(0xFFE8F5E9);
  static Color get successInk => isDark ? const Color(0xFF6EE7B7) : const Color(0xFF2E7D32);

  /// A soft background for any accent colour (status chips, notice cards), readable in both themes
  static Color tint(Color c) => c.withValues(alpha: isDark ? 0.22 : 0.10);

  /// Text and icons on [tint]: the accent darkened on light surfaces, lifted on dark ones
  static Color ink(Color c) => Color.lerp(c, isDark ? Colors.white : Colors.black, isDark ? 0.35 : 0.30)!;

  /// Brand header / balance card background (navy in both themes; white text on it)
  static const LinearGradient brandGradient = LinearGradient(
    colors: [navy, Color(0xFF14174A)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// One colour per order status in every app: waiting amber, accepted blue,
  /// packed navy, with the rider orange, delivered green, cancelled red
  static Color orderStatus(String status) => switch (status) {
        'pending' => warning,
        'confirmed' => info,
        'packed' => secondary,
        'ready_for_pickup' || 'picked' || 'on_the_way' => primary,
        'delivered' => success,
        'cancelled' => error,
        _ => textSecondary,
      };
}

/// One icon per idea, shared by the three apps (maps, cards, timelines)
class AppIcons {
  AppIcons._();

  /// A rider / a delivery in progress (the vehicle type has its own icons)
  static const IconData rider = Icons.delivery_dining;
  static const IconData store = Icons.storefront;
  static const IconData customer = Icons.home_rounded;
  static const IconData wallet = Icons.account_balance_wallet_outlined;
}

/// Lets ThemeScope switch the tokens; not for use by screens
void applyThemeBrightness(Brightness brightness) => AppColors._brightness = brightness;

class AppTheme {
  AppTheme._();

  static ThemeData get lightTheme => _build(Brightness.light);
  static ThemeData get darkTheme => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final background = dark ? AppColors.darkBackground : AppColors.lightBackground;
    final surface = dark ? AppColors.darkSurface : AppColors.lightSurface;
    final muted = dark ? AppColors.darkSurfaceMuted : AppColors.lightSurfaceMuted;
    final border = dark ? AppColors.darkBorder : AppColors.lightBorder;
    final textPrimary = dark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final textSecondary = dark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    final textLight = dark ? AppColors.darkTextLight : AppColors.lightTextLight;
    final secondary = dark ? AppColors.navyOnDark : AppColors.navy;

    TextStyle poppins(double size, FontWeight weight, Color color) =>
        GoogleFonts.poppins(fontSize: size, fontWeight: weight, color: color);

    // Seeded from the brand orange, with plain neutral surfaces: without these,
    // drawers, sheets, dialogs and dividers pick up an orange tint
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: brightness,
      primary: AppColors.primary,
      onPrimary: Colors.white,
      secondary: secondary,
      onSecondary: Colors.white,
      surface: surface,
      onSurface: textPrimary,
      error: AppColors.error,
    ).copyWith(
      surfaceTint: Colors.transparent,
      surfaceContainerLowest: surface,
      surfaceContainerLow: surface,
      surfaceContainer: surface,
      surfaceContainerHigh: surface,
      surfaceContainerHighest: muted,
      onSurfaceVariant: textSecondary,
      outline: border,
      outlineVariant: border,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      canvasColor: surface,
      cardColor: surface,
      dividerColor: border,
      dividerTheme: DividerThemeData(color: border, thickness: 1),
      // Dialogs and sheets share the 16 px card radius
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      ),
      drawerTheme: DrawerThemeData(backgroundColor: surface, surfaceTintColor: Colors.transparent),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      popupMenuTheme: PopupMenuThemeData(color: surface, surfaceTintColor: Colors.transparent),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      iconTheme: IconThemeData(color: textPrimary),

      // Typography: Google Fonts Poppins
      textTheme: GoogleFonts.poppinsTextTheme(ThemeData(brightness: brightness).textTheme).copyWith(
        headlineLarge: poppins(28, FontWeight.w700, textPrimary),
        headlineMedium: poppins(22, FontWeight.w600, textPrimary),
        titleLarge: poppins(18, FontWeight.w600, textPrimary),
        titleMedium: poppins(16, FontWeight.w500, textPrimary),
        bodyLarge: poppins(16, FontWeight.w400, textPrimary),
        bodyMedium: poppins(14, FontWeight.w400, textPrimary),
        bodySmall: poppins(12, FontWeight.w400, textLight),
        labelLarge: poppins(14, FontWeight.w600, Colors.white),
      ),

      appBarTheme: AppBarTheme(
        surfaceTintColor: Colors.transparent,
        backgroundColor: surface,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: true,
        titleTextStyle: poppins(18, FontWeight.w600, textPrimary),
      ),

      // Flat cards with a hairline outline
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: border),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: muted,
          disabledForegroundColor: textLight,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: secondary,
          side: BorderSide(color: secondary, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),

      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: secondary)),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: muted,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: secondary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        hintStyle: GoogleFonts.poppins(color: textLight, fontSize: 14),
        labelStyle: GoogleFonts.poppins(color: textSecondary, fontSize: 14),
      ),

      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: textLight,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500),
        unselectedLabelStyle: GoogleFonts.poppins(fontSize: 12),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: AppColors.primary.withValues(alpha: 0.14),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: surface,
        side: BorderSide(color: border),
        labelStyle: GoogleFonts.poppins(fontSize: 12, color: textPrimary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),

      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
    );
  }
}
