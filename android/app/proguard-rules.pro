# Flutter 引擎与插件默认保留规则
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
# Flutter 引擎的 Play Store 分包管理器为可选依赖，应用未使用分发包，
# R8 编译期忽略这些缺失引用
-dontwarn com.google.android.play.core.**
# 反射依赖的安全存储/SQLite 桥接
-keep class com.it_nomads.fluttersecurestorage.** { *; }
-keep class com.tekartik.sqflite.** { *; }
