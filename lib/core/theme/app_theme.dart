import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/cupertino.dart';

class AppSpacing {
  static const double xs = 4;
  static const double s = 8;
  static const double m = 12;
  static const double l = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const EdgeInsets pagePadding = EdgeInsets.symmetric(horizontal: l);
}

class AppRadius {
  static const double none = 0;
  static const double extraSmall = 4;
  static const double small = 6;
  static const double medium = 8;
  static const double large = 16;
  static const double extraLarge = 20;
  static const double dialog = 12;
  static const double pill = 999;
}

/// 品牌语义色：组件内的品牌色 / 辅助蓝 / 主文本色统一从此取值，
/// 避免散落的硬编码 Color(0xFF…) 随主题演进悄悄漂移。
class AppBrandColors {
  static const Color brand = Color(0xFFFF5A24); // 品牌橙（主操作）
  static const Color infoBlue = Color(0xFF1E88E5); // 信息蓝（选中/辅助）
  static const Color textPrimary = Color(0xFF333333); // 亮色模式主文本
}

class AppSize {
  static const double buttonHeight = 48;
  static const double iconClickArea = 48;
  static const double iconVisualSize = 22;
  static const double textFieldHeight = 56;
  static const double appBarHeight = 64;
  static const double bottomNavHeight = 72;
  static const double fabSize = 54;
}

class AppElevation {
  static const double level0 = 0;
  static const double level1 = 1;
  static const double level2 = 2;
  static const double level3 = 3;
}

/// BearFuel visual system: editorial data hierarchy with restrained surfaces.
class AppTheme {
  static const Color seedColor = Color(0xFFFF5A24);
  static const Color primaryColor = seedColor;
  static const Color primaryDarkColor = Color(0xFFD9410F);
  static const Color secondaryColor = Color(0xFF007D83);
  static const Color accentColor = Color(0xFF6558D3);

  static const Color scaffoldBackground = Color(0xFFF3F5F6);
  static const Color cardBackground = Color(0xFFFFFFFF);
  static const Color darkScaffoldBackground = Color(0xFF0B0D0E);
  static const Color darkCardBackground = Color(0xFF141719);

  static const Color textPrimary = Color(0xFF15191A);
  static const Color textSecondary = Color(0xFF596164);
  static const Color textHint = Color(0xFF8B9497);

  static const Color errorColor = Color(0xFFC9372C);
  static const Color warningColor = Color(0xFFE98400);
  static const Color successColor = Color(0xFF1D7A52);

  static const PageTransitionsTheme _pageTransitionsTheme =
      PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      );

  static const TextTheme _textTheme = TextTheme(
    displayLarge: TextStyle(
      fontSize: 44,
      height: 1.05,
      fontWeight: FontWeight.w700,
      letterSpacing: 0,
    ),
    displayMedium: TextStyle(
      fontSize: 36,
      height: 1.08,
      fontWeight: FontWeight.w700,
      letterSpacing: 0,
    ),
    displaySmall: TextStyle(
      fontSize: 30,
      height: 1.1,
      fontWeight: FontWeight.w700,
      letterSpacing: 0,
    ),
    headlineLarge: TextStyle(
      fontSize: 28,
      height: 1.15,
      fontWeight: FontWeight.w700,
      letterSpacing: 0,
    ),
    headlineMedium: TextStyle(
      fontSize: 24,
      height: 1.2,
      fontWeight: FontWeight.w700,
      letterSpacing: 0,
    ),
    headlineSmall: TextStyle(
      fontSize: 20,
      height: 1.25,
      fontWeight: FontWeight.w700,
      letterSpacing: 0,
    ),
    titleLarge: TextStyle(
      fontSize: 18,
      height: 1.3,
      fontWeight: FontWeight.w700,
      letterSpacing: 0,
    ),
    titleMedium: TextStyle(
      fontSize: 15,
      height: 1.35,
      fontWeight: FontWeight.w600,
      letterSpacing: 0,
    ),
    titleSmall: TextStyle(
      fontSize: 13,
      height: 1.35,
      fontWeight: FontWeight.w600,
      letterSpacing: 0,
    ),
    bodyLarge: TextStyle(
      fontSize: 15,
      height: 1.5,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
    ),
    bodyMedium: TextStyle(
      fontSize: 13,
      height: 1.5,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
    ),
    bodySmall: TextStyle(
      fontSize: 11,
      height: 1.45,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
    ),
    labelLarge: TextStyle(
      fontSize: 13,
      height: 1.2,
      fontWeight: FontWeight.w600,
      letterSpacing: 0,
    ),
    labelMedium: TextStyle(
      fontSize: 11,
      height: 1.2,
      fontWeight: FontWeight.w600,
      letterSpacing: 0,
    ),
    labelSmall: TextStyle(
      fontSize: 10,
      height: 1.2,
      fontWeight: FontWeight.w600,
      letterSpacing: 0,
    ),
  );

  static ThemeData get lightTheme => _buildTheme(Brightness.light);

  static ThemeData get darkTheme => _buildTheme(Brightness.dark);

  static ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final background = isDark ? darkScaffoldBackground : scaffoldBackground;
    final surface = isDark ? darkCardBackground : cardBackground;
    final baseScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
    );
    final colorScheme = baseScheme.copyWith(
      primary: seedColor,
      onPrimary: Colors.white,
      secondary: secondaryColor,
      tertiary: accentColor,
      error: errorColor,
      surface: surface,
      onSurface: isDark ? const Color(0xFFF3F5F4) : textPrimary,
      onSurfaceVariant: isDark
          ? const Color(0xFFB6BFC1)
          : const Color(0xFF596164),
      outline: isDark ? const Color(0xFF41484A) : const Color(0xFFCBD1D3),
      outlineVariant: isDark
          ? const Color(0xFF2A3032)
          : const Color(0xFFE1E5E6),
    );
    final overlayStyle = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness: isDark
          ? Brightness.light
          : Brightness.dark,
    );
    final fieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.medium),
      borderSide: BorderSide(color: colorScheme.outlineVariant),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      primaryColor: seedColor,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      pageTransitionsTheme: _pageTransitionsTheme,
      splashFactory: InkSparkle.splashFactory,
      textTheme: _textTheme.apply(
        bodyColor: colorScheme.onSurface,
        displayColor: colorScheme.onSurface,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: colorScheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        toolbarHeight: AppSize.appBarHeight,
        systemOverlayStyle: overlayStyle,
        titleTextStyle: TextStyle(
          color: colorScheme.onSurface,
          fontSize: 17,
          height: 1.2,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
        iconTheme: IconThemeData(color: colorScheme.onSurface, size: 21),
        actionsIconTheme: IconThemeData(color: colorScheme.onSurface, size: 21),
      ),
      iconTheme: IconThemeData(color: colorScheme.onSurface, size: 21),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(double.infinity, AppSize.buttonHeight),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          backgroundColor: seedColor,
          foregroundColor: Colors.white,
          textStyle: _textTheme.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.medium),
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(double.infinity, AppSize.buttonHeight),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          backgroundColor: seedColor,
          foregroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          shadowColor: Colors.transparent,
          textStyle: _textTheme.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.medium),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(double.infinity, AppSize.buttonHeight),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          foregroundColor: colorScheme.onSurface,
          side: BorderSide(color: colorScheme.outline),
          textStyle: _textTheme.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.medium),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(0, AppSize.buttonHeight),
          foregroundColor: seedColor,
          textStyle: _textTheme.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.medium),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size.square(AppSize.iconClickArea),
          foregroundColor: colorScheme.onSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.medium),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 15,
        ),
        labelStyle: _textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
        hintStyle: _textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.72),
        ),
        prefixIconColor: colorScheme.secondary,
        suffixIconColor: colorScheme.onSurfaceVariant,
        suffixStyle: _textTheme.labelMedium?.copyWith(color: seedColor),
        border: fieldBorder,
        enabledBorder: fieldBorder,
        focusedBorder: fieldBorder.copyWith(
          borderSide: const BorderSide(color: seedColor, width: 1.5),
        ),
        errorBorder: fieldBorder.copyWith(
          borderSide: const BorderSide(color: errorColor),
        ),
        focusedErrorBorder: fieldBorder.copyWith(
          borderSide: const BorderSide(color: errorColor, width: 1.5),
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.medium),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      tabBarTheme: TabBarThemeData(
        dividerColor: Colors.transparent,
        indicatorColor: seedColor,
        labelColor: colorScheme.onSurface,
        unselectedLabelColor: colorScheme.onSurfaceVariant,
        labelStyle: _textTheme.labelLarge,
        unselectedLabelStyle: _textTheme.labelLarge,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surface,
        selectedColor: seedColor.withValues(alpha: isDark ? 0.24 : 0.12),
        side: BorderSide(color: colorScheme.outlineVariant),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.small),
        ),
        labelStyle: _textTheme.labelMedium!.copyWith(
          color: colorScheme.onSurface,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.dialog),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        modalBackgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark
            ? const Color(0xFFF1F3F2)
            : const Color(0xFF171B1C),
        contentTextStyle: _textTheme.bodyMedium?.copyWith(
          color: isDark ? const Color(0xFF171B1C) : Colors.white,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.medium),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: seedColor,
        foregroundColor: Colors.white,
        elevation: 2,
        focusElevation: 2,
        hoverElevation: 3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.medium)),
        ),
      ),
    );
  }

  static void setSystemUi() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }
}
