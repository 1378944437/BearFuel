# Flutter 引擎与插件默认保留规则
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
# 反射依赖的安全存储/SQLite 桥接
-keep class com.it_nomads.fluttersecurestorage.** { *; }
-keep class com.tekartik.sqflite.** { *; }
