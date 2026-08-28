# BearFuel

BearFuel 是一款以本地数据为核心的个人车辆油耗与用车成本管理应用，使用 Flutter 开发。

[![CI](https://github.com/1378944437/BearFuel/actions/workflows/ci.yml/badge.svg)](https://github.com/1378944437/BearFuel/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/1378944437/BearFuel)](https://github.com/1378944437/BearFuel/releases)

## 功能

- 多车辆档案、加油记录和其他用车费用管理
- 加满法油耗计算、费用统计、趋势图表与异常分析
- 高德地图定位、地址解析和附近加油站查询
- ApiZero 省级实时油价、调价预测与历史记录
- 墨迹天气查询与本地天气快照趋势
- JSON 全量备份与恢复、小熊油耗账单导入
- 深色模式和 Android、iOS 支持

在线服务均在 App 的“设置 > 服务”中配置。高德地图需要用户自己的 Web 服务 Key；油价和天气支持 ApiZero 匿名请求，也可填写个人 Key。密钥只保存在当前设备的安全存储中，不写入源码或安装包。

## 数据与隐私

车辆、账单、服务配置和历史快照默认保存在设备本地。BearFuel 不提供云端账户或同步服务，也不内置虚构的油价、加油站和天气数据。建议定期通过“设置 > 备份 > 数据导入与备份”导出全量 JSON。

## 开发

构建基线：Flutter 3.44.3、Dart 3.12.2、Java 17。

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

主要目录：

```text
lib/
├── core/          # 配置、主题与通用工具
├── data/          # SQLite、数据模型与在线服务
├── domain/        # 油耗计算、导入与统计逻辑
├── presentation/  # 页面与组件
└── providers/     # 应用状态
```

## 发布

推送与 `pubspec.yaml` 版本一致的 `vX.Y.Z` 标签后，GitHub Actions 会生成：

- 已签名的 `armeabi-v7a`、`arm64-v8a`、`x86_64` Android APK
- 未签名的 iOS IPA，安装前需自行签名或使用 TrollStore
- 每个安装包对应的 SHA-256 校验文件

Android 发布需要在 GitHub 仓库中配置以下 Actions Secrets：

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`
- `ANDROID_STORE_PASSWORD`

版本号以 `pubspec.yaml` 为唯一来源。发布前更新版本和 [CHANGELOG.md](CHANGELOG.md)，再创建标签。

## 说明

本项目为个人自用项目，未附带开源许可证。第三方地图、油价和天气服务的使用应遵守各自服务条款与额度限制。
