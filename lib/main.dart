import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'core/config/app_config.dart';
import 'core/theme/app_theme.dart';
import 'providers/vehicle_provider.dart';
import 'providers/refuel_provider.dart';
import 'providers/expense_provider.dart';
import 'providers/fuel_price_provider.dart';
import 'providers/weather_provider.dart';
import 'data/services/amap_key_store.dart';
import 'data/services/fuel_price_api_config.dart';
import 'data/services/weather_api_config.dart';
import 'presentation/screens/main_navigation_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AmapKeyStore.load();
  await FuelPriceApiConfigStore.load();
  await WeatherApiConfigStore.load();

  // 1. 全局异常与闪退防护（捕获所有同步/异步未捕获异常，绝不闪退白屏）
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    AppConfig.log('全局拦截 FlutterError: ${details.exceptionAsString()}');
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    AppConfig.log('全局拦截异步异常: $error\n$stack');
    return false; // 记录后交给 Flutter/系统默认处理，避免静默吞掉严重故障
  };

  // 2. 初始化应用环境与沉浸式 UI
  AppConfig.initialize(
    env: kReleaseMode ? Environment.production : Environment.development,
  );
  AppTheme.setSystemUi();
  AppConfig.log('BearFuel 应用启动...');

  runApp(const BearFuelApp());
}

/// BearFuel 记账主应用根组件
class BearFuelApp extends StatelessWidget {
  const BearFuelApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => VehicleProvider()),
        ChangeNotifierProvider(create: (_) => RefuelProvider()),
        ChangeNotifierProvider(create: (_) => ExpenseProvider()),
        ChangeNotifierProvider(create: (_) => FuelPriceProvider()),
        ChangeNotifierProvider(create: (_) => WeatherProvider()),
      ],
      child: MaterialApp(
        title: 'BearFuel',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.system, // 支持随系统深浅色切换
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('zh', 'CN'), // 简体中文
          Locale('en', 'US'),
        ],
        locale: const Locale('zh', 'CN'),
        builder: (context, child) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: isDark
                  ? Brightness.light
                  : Brightness.dark,
              statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
              systemNavigationBarColor: Colors.transparent,
              systemNavigationBarDividerColor: Colors.transparent,
              systemNavigationBarIconBrightness: isDark
                  ? Brightness.light
                  : Brightness.dark,
            ),
            child: child ?? const SizedBox(),
          );
        },
        home: const MainNavigationScreen(),
      ),
    );
  }
}
