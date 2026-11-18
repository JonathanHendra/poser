import 'package:flutter/material.dart';

class AppColors {
  static const navy = Color(0xFF0B1F44);
  static const darkField = Color(0xFF0D223A);
  static const darkFieldBorder = Color(0xFF284A70);
  static const darkFieldFocusedBorder = Color(0xFF426C99);
  static const electricBlue = Color(0xFF066BFF);
  static const blueAccent = Color(0xFF2997FF);
  static const background = Color(0xFFF8FAFC);
  static const surface = Colors.white;
  static const textPrimary = Color(0xFF0F172A);
  static const textSecondary = Color(0xFF64748B);
  static const border = Color(0xFFE2E8F0);
  static const success = Color(0xFF10B981);
  static const warning = Color(0xFFF59E0B);
  static const danger = Color(0xFFEF4444);
  static const chartPalette = [
    electricBlue,
    Color(0xFF00B8AE),
    warning,
    Color(0xFFAD55E8),
    Color(0xFFED649C),
    textSecondary,
    success,
  ];
}

class AppSpacing {
  static const x1 = 4.0, x2 = 8.0, x3 = 12.0, x4 = 16.0;
  static const x5 = 20.0, x6 = 24.0, x8 = 32.0;
  static const x10 = 40.0, x12 = 48.0;
}

class AppRadius {
  static const card = 8.0, input = 12.0, dialog = 16.0;
}

@immutable
class AppStatusColors extends ThemeExtension<AppStatusColors> {
  const AppStatusColors({required this.success, required this.warning});
  final Color success, warning;

  static AppStatusColors of(BuildContext context) =>
      Theme.of(context).extension<AppStatusColors>() ??
      const AppStatusColors(
        success: AppColors.success,
        warning: AppColors.warning,
      );

  @override
  AppStatusColors copyWith({Color? success, Color? warning}) => AppStatusColors(
    success: success ?? this.success,
    warning: warning ?? this.warning,
  );

  @override
  AppStatusColors lerp(covariant AppStatusColors? other, double t) =>
      other == null
      ? this
      : AppStatusColors(
          success: Color.lerp(success, other.success, t)!,
          warning: Color.lerp(warning, other.warning, t)!,
        );
}

class AppTheme {
  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    var scheme = ColorScheme.fromSeed(
      seedColor: AppColors.electricBlue,
      brightness: brightness,
      primary: AppColors.electricBlue,
      onPrimary: Colors.white,
      surface: dark ? const Color(0xFF0E141D) : AppColors.surface,
      onSurface: dark ? const Color(0xFFF1F5F9) : AppColors.textPrimary,
      onSurfaceVariant: dark
          ? const Color(0xFFB8C7DB)
          : AppColors.textSecondary,
      outline: dark ? AppColors.blueAccent : const Color(0xFF94A3B8),
      outlineVariant: dark ? AppColors.electricBlue : AppColors.border,
      error: dark ? const Color(0xFFFF9494) : AppColors.danger,
    );
    if (dark) {
      scheme = scheme.copyWith(
        primaryContainer: const Color(0xFF0A2A52),
        onPrimaryContainer: const Color(0xFFDCEAFF),
        surfaceContainerLowest: const Color(0xFF06090E),
        surfaceContainerLow: const Color(0xFF101722),
        surfaceContainer: const Color(0xFF141D2A),
        surfaceContainerHigh: const Color(0xFF192536),
        surfaceContainerHighest: const Color(0xFF213047),
      );
    }
    TextStyle type(double size, FontWeight weight) => TextStyle(
      fontFamily: 'POSPRO Sans',
      fontFamilyFallback: const ['Noto Sans', 'sans-serif'],
      fontSize: size,
      fontWeight: weight,
      height: 1.4,
      letterSpacing: 0,
      color: scheme.onSurface,
    );
    final text = TextTheme(
      displayLarge: type(32, FontWeight.w700),
      displayMedium: type(30, FontWeight.w700),
      displaySmall: type(28, FontWeight.w700),
      headlineLarge: type(28, FontWeight.w700),
      headlineMedium: type(26, FontWeight.w700),
      headlineSmall: type(24, FontWeight.w700),
      titleLarge: type(22, FontWeight.w700),
      titleMedium: type(18, FontWeight.w600),
      titleSmall: type(16, FontWeight.w600),
      bodyLarge: type(16, FontWeight.w400),
      bodyMedium: type(14, FontWeight.w400),
      bodySmall: type(
        12,
        FontWeight.w400,
      ).copyWith(color: scheme.onSurfaceVariant),
      labelLarge: type(14, FontWeight.w600),
      labelMedium: type(12, FontWeight.w600),
      labelSmall: type(11, FontWeight.w600),
    );
    final cardShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.card),
      side: BorderSide(color: scheme.outlineVariant),
    );
    OutlineInputBorder input(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
          borderSide: BorderSide(color: color, width: width),
        );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: 'POSPRO Sans',
      textTheme: text,
      scaffoldBackgroundColor: dark
          ? const Color(0xFF05080D)
          : AppColors.background,
      canvasColor: scheme.surface,
      cardColor: scheme.surface,
      extensions: [
        AppStatusColors(
          success: dark ? const Color(0xFF6EE7B7) : const Color(0xFF047857),
          warning: dark ? const Color(0xFFFCD34D) : const Color(0xFFB45309),
        ),
      ],
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        titleTextStyle: text.titleLarge,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: cardShape,
        color: scheme.surface,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        titleTextStyle: text.titleLarge,
        contentTextStyle: text.bodyMedium,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.dialog),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        modalBackgroundColor: scheme.surface,
        dragHandleColor: scheme.outline,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.dialog),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          textStyle: text.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.input),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          foregroundColor: scheme.primary,
          side: BorderSide(color: scheme.outlineVariant),
          textStyle: text.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.input),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          textStyle: text.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        selectedColor: scheme.primaryContainer,
        disabledColor: scheme.surfaceContainerHighest,
        labelStyle: text.labelMedium,
        secondaryLabelStyle: text.labelMedium!.copyWith(
          color: scheme.onPrimaryContainer,
        ),
        checkmarkColor: scheme.onPrimaryContainer,
        side: BorderSide(color: scheme.outlineVariant),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? AppColors.darkField : scheme.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        labelStyle: text.bodyMedium!.copyWith(color: scheme.onSurfaceVariant),
        hintStyle: text.bodyMedium!.copyWith(color: scheme.onSurfaceVariant),
        border: input(dark ? AppColors.darkFieldBorder : scheme.outlineVariant),
        enabledBorder: input(
          dark ? AppColors.darkFieldBorder : scheme.outlineVariant,
        ),
        disabledBorder: input(
          dark ? AppColors.darkFieldBorder : scheme.outlineVariant,
        ),
        focusedBorder: input(
          dark ? AppColors.darkFieldFocusedBorder : scheme.primary,
          1.5,
        ),
        errorBorder: input(scheme.error),
        focusedErrorBorder: input(scheme.error, 1.5),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        titleTextStyle: text.bodyLarge,
        subtitleTextStyle: text.bodySmall,
        iconColor: scheme.onSurfaceVariant,
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      dividerColor: scheme.outlineVariant,
      iconTheme: IconThemeData(color: scheme.onSurfaceVariant, size: 24),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surface,
        selectedIconTheme: IconThemeData(color: scheme.primary),
        selectedLabelTextStyle: text.labelLarge!.copyWith(
          color: scheme.primary,
        ),
        unselectedLabelTextStyle: text.labelLarge!.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      dataTableTheme: DataTableThemeData(
        headingTextStyle: text.labelLarge,
        dataTextStyle: text.bodyMedium,
        columnSpacing: 24,
        horizontalMargin: 16,
        dataRowMinHeight: 56,
        dataRowMaxHeight: 88,
        headingRowColor: WidgetStatePropertyAll(scheme.surfaceContainerLow),
        dividerThickness: 1,
      ),
    );
  }
}
