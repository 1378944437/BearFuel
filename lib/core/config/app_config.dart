import 'package:flutter/foundation.dart';

/// 环境类型枚举
enum Environment {
  development, // 开发环境
  production, // 生产环境
}

/// 全局应用环境与配置隔离类
class AppConfig {
  // Release workflows inject this from pubspec.yaml; debug runs use a neutral
  // value so the version is not maintained in two source files.
  static const String versionName = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: 'dev',
  );

  static Environment _environment = Environment.development;

  /// 获取当前环境
  static Environment get environment => _environment;

  /// 是否为开发环境
  static bool get isDevelopment => _environment == Environment.development;

  /// 是否为生产环境
  static bool get isProduction => _environment == Environment.production;

  /// 数据库名称配置
  static String get databaseName =>
      isDevelopment ? 'bear_fuel_dev.db' : 'bear_fuel.db';

  // ---------- 项目与发布信息（"关于应用"板块与检查更新共用） ----------
  static const String githubRepoUrl = 'https://github.com/1378944437/BearFuel';
  static const String githubReleasesUrl = '$githubRepoUrl/releases';
  static const String githubLatestReleaseUrl = '$githubRepoUrl/releases/latest';
  static const String githubActionsUrl = '$githubRepoUrl/actions';
  static const String githubLatestReleaseApiUrl =
      'https://api.github.com/repos/1378944437/BearFuel/releases/latest';

  /// 一键发布流水线命令（升版 → 本地构建 → 推送触发远端构建）
  static const String releaseCommand = 'bash scripts/release.sh';

  /// 日志级别控制
  // 诊断日志仅在调试构建开启：Release 包不再向系统日志输出
  // GPS 坐标、数据库路径等敏感信息。
  static bool get enableDebugLog => kDebugMode;

  /// 默认货币符号
  static const String currencySymbol = '¥';

  /// 默认油耗单位
  static const String fuelUnit = 'L/100km';

  /// 默认里程单位
  static const String distanceUnit = 'km';

  /// 初始化环境配置
  static void initialize({Environment env = Environment.development}) {
    _environment = env;
  }

  /// 统一日志输出
  static void log(String message, {String tag = 'BearFuel'}) {
    if (enableDebugLog) {
      // ignore: avoid_print
      print('[$tag][${DateTime.now().toIso8601String()}] $message');
    }
  }
}
