import 'package:flutter/material.dart';

import 'theme_controller.dart';

/// B听「闭眼听友」主题：深蓝 / 奶油底色、珊瑚粉主操作，支持明亮模式。
///
/// 颜色通过 getter 动态返回，由 [AppTheme.mode]（与 [ThemeController.mode] 同步）
/// 决定取哪套。组件在构建时读取即可自动跟随。
class AppTheme {
  AppTheme._();

  static ThemeMode mode = ThemeMode.system;

  static bool get isDark {
    if (mode == ThemeMode.dark) return true;
    if (mode == ThemeMode.light) return false;
    final d = WidgetsBinding.instance.platformDispatcher.platformBrightness;
    return d == Brightness.dark;
  }

  // ---- 品牌填充色（两种模式通用）；文字强调使用 actionText ----
  static const Color accent = Color(0xFFF58F9C);
  static const Color primaryFill = accent;
  static const Color onPrimary = Color(0xFF152342);
  static const Color accentDecorative = Color(0xFF8BD8D8);
  // 保留旧接口，已有自绘控件继续读取同一套品牌色。
  static const Color accentDeep = accent;
  static const Color accentSoft = accentDecorative;
  static const Color accentViolet = accent;
  static const Color accentLilac = accentDecorative;
  static const Color accentIce = accentDecorative;
  static const Color accentMoon = Color(0xFFFFF4DE);
  static const Color accentNavy = onPrimary;

  /// 主操作沿用统一填充，不以渐变表达状态。
  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [accent, accent],
  );

  /// 保留旧装饰接口。
  static const LinearGradient accentGradientViolet = LinearGradient(
    begin: Alignment.bottomLeft,
    end: Alignment.topRight,
    colors: [accent, accent],
  );

  static Color get bg => isDark ? const Color(0xFF152342) : const Color(0xFFFFF8ED);
  static Color get surface =>
      isDark ? const Color(0xFF203252) : const Color(0xFFFFFFFF);
  static Color get surfaceHigh =>
      isDark ? const Color(0xFF2B4061) : const Color(0xFFF4EBDD);
  static Color get divider =>
      isDark ? const Color(0xFF344761) : const Color(0xFFDFD6CA);
  static Color get textMain =>
      isDark ? const Color(0xFFFFF4DE) : const Color(0xFF152342);
  static Color get textSub =>
      isDark ? const Color(0xFFBBC6DC) : const Color(0xFF53617A);
  static Color get textHint =>
      isDark ? const Color(0xFFBBC6DC) : const Color(0xFF5E6A7D);
  static Color get actionText => isDark ? accent : const Color(0xFFAC4157);
  static Color get outline =>
      isDark ? const Color(0xFF899BB7) : const Color(0xFF6C788B);
  static Color get success =>
      isDark ? const Color(0xFF8ED1B2) : const Color(0xFF216846);
  static Color get warning =>
      isDark ? const Color(0xFFF0C36A) : const Color(0xFF805400);
  static Color get error =>
      isDark ? const Color(0xFFFFADB3) : const Color(0xFFB52B43);
  // 播放页背景模糊的遮罩
  static Color get scrim =>
      isDark ? const Color(0xE6152342) : const Color(0xF2FFF8ED);

  // ---- 语义化图标的双模式取色 ----
  static Color get toneBrand => actionText;
  static Color get toneCyan => isDark ? accentDecorative : const Color(0xFF216846);
  static Color get toneViolet => actionText;
  static Color get toneLilac => actionText;
  static Color get toneIce => textSub;
  static Color get toneInk => textMain;
  static Color get toneDeep => actionText;

  static ThemeData dark() => _build(Brightness.dark, _dark());

  static ThemeData light() => _build(Brightness.light, _light());

  static ({Color bg, Color surface, Color surfaceHigh, Color divider,
          Color textMain, Color textSub, Color textHint})
      _dark() => (
            bg: const Color(0xFF152342),
            surface: const Color(0xFF203252),
            surfaceHigh: const Color(0xFF2B4061),
            divider: const Color(0xFF344761),
            textMain: const Color(0xFFFFF4DE),
            textSub: const Color(0xFFBBC6DC),
            textHint: const Color(0xFFBBC6DC),
          );

  static ({Color bg, Color surface, Color surfaceHigh, Color divider,
          Color textMain, Color textSub, Color textHint})
      _light() => (
            bg: const Color(0xFFFFF8ED),
            surface: const Color(0xFFFFFFFF),
            surfaceHigh: const Color(0xFFF4EBDD),
            divider: const Color(0xFFDFD6CA),
            textMain: const Color(0xFF152342),
            textSub: const Color(0xFF53617A),
            textHint: const Color(0xFF5E6A7D),
          );

  static ThemeData _build(
    Brightness b,
    ({
      Color bg,
      Color surface,
      Color surfaceHigh,
      Color divider,
      Color textMain,
      Color textSub,
      Color textHint
    }) c,
  ) {
    final dark = b == Brightness.dark;
    final action = dark ? accent : const Color(0xFFAC4157);
    final boundary = dark ? const Color(0xFF899BB7) : const Color(0xFF6C788B);
    final danger = dark ? const Color(0xFFFFADB3) : const Color(0xFFB52B43);
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: b,
    ).copyWith(
      primary: accent,
      onPrimary: onPrimary,
      primaryContainer: c.surfaceHigh,
      onPrimaryContainer: c.textMain,
      secondary: accentSoft,
      onSecondary: onPrimary,
      tertiary: action,
      onTertiary: dark ? onPrimary : Colors.white,
      surface: c.surface,
      onSurface: c.textMain,
      surfaceContainerHighest: c.surfaceHigh,
      onSurfaceVariant: c.textSub,
      outline: boundary,
      outlineVariant: c.divider,
      error: danger,
      onError: dark ? onPrimary : Colors.white,
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: b,
      scaffoldBackgroundColor: c.bg,
      splashFactory: InkRipple.splashFactory,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
    );

    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: c.textMain,
        displayColor: c.textMain,
      ).copyWith(
        headlineSmall: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: c.textMain),
        titleLarge: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: c.textMain),
        titleMedium: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: c.textMain),
        bodyLarge: TextStyle(fontSize: 16, color: c.textMain),
        bodyMedium: TextStyle(fontSize: 14, color: c.textMain),
        bodySmall: TextStyle(fontSize: 12, color: c.textSub),
        labelLarge: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: c.bg,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: c.textMain,
          fontSize: 24,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: IconThemeData(color: c.textMain),
      ),
      tabBarTheme: TabBarThemeData(
        indicatorColor: action,
        indicatorSize: TabBarIndicatorSize.label,
        labelColor: c.textMain,
        unselectedLabelColor: c.textSub,
        dividerColor: c.divider,
        labelStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontSize: 16),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: c.surface,
        indicatorColor: accent.withValues(alpha: 0.16),
        height: 64,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w400,
            color: states.contains(WidgetState.selected) ? action : c.textSub,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? action : c.textSub,
            size: 26,
          ),
        ),
      ),
      dividerTheme: DividerThemeData(color: c.divider, thickness: 0.6),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: onPrimary,
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: action,
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: action,
          minimumSize: const Size(48, 48),
          side: BorderSide(color: boundary),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? action : boundary,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        checkColor: const WidgetStatePropertyAll(onPrimary),
        side: BorderSide(color: boundary, width: 2),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? onPrimary : boundary,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? accent : c.surfaceHigh,
        ),
        trackOutlineColor: WidgetStatePropertyAll(boundary),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: action,
        thumbColor: action,
        inactiveTrackColor: c.divider,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surfaceHigh,
        hintStyle: TextStyle(color: c.textHint, fontSize: 14),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: boundary),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: boundary, width: 2),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.surfaceHigh,
        contentTextStyle: TextStyle(color: c.textMain, fontSize: 14),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: action,
        circularTrackColor: c.surfaceHigh,
        linearTrackColor: c.divider,
      ),
      listTileTheme: ListTileThemeData(
        minTileHeight: 48,
        iconColor: c.textSub,
        textColor: c.textMain,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: c.surfaceHigh,
        selectedColor: accent.withValues(alpha: 0.2),
        labelStyle: TextStyle(color: c.textMain, fontSize: 14),
        side: BorderSide(color: boundary),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(20)),
        ),
      ),
    );
  }
}