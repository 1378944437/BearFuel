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
- JSON 全量备份与恢复、小熊油耗账单导入（支持 UTF-8 / GBK 编码）
- 深色模式和 Android、iOS 支持

在线服务均在 App 的“设置 > 服务”中配置。高德地图需要用户自己的 Web 服务 Key；油价和天气支持 ApiZero 匿名请求，也可填写个人 Key。密钥只保存在当前设备的安全存储中，不写入源码或安装包。

## 数据与隐私

车辆、账单、服务配置和历史快照默认保存在设备本地。BearFuel 不提供云端账户或同步服务，也不内置虚构的油价、加油站和天气数据。建议定期通过“设置 > 备份 > 数据导入与备份”导出全量 JSON。

## 关于应用

App 内“设置 > 关于应用”提供：

- **版本信息**：当前安装的版本号与 Build 号（以 `pubspec.yaml` 为唯一来源）
- **检查更新**：通过 GitHub Releases 接口检测新版本，并展示更新说明与下载入口
- **更新日志**：应用内直接浏览历届版本变更（中文，与仓库 `CHANGELOG.md` 同源打包）
- **构建与发布**：说明远端优先的发布流程（推送标签触发构建），可复制发布命令并跳转构建进度页与发布页

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

## 构建与发布

发布以**远端构建为主**：更新 `pubspec.yaml` 版本与 [CHANGELOG.md](CHANGELOG.md)，提交后推送 `vX.Y.Z` 标签即可：

```bash
git push origin main
git tag v0.2.14
git push origin v0.2.14
```

推送标签后，[Release 工作流](https://github.com/1378944437/BearFuel/actions/workflows/release.yml)自动构建以下产物并发布到 [Releases 页面](https://github.com/1378944437/BearFuel/releases)：

| 平台 | 产物 | 签名 | 构建位置 |
| --- | --- | --- | --- |
| Android | `armeabi-v7a` / `arm64-v8a` / `x86_64` 三架构 APK | 签名 | 远端（本地可选） |
| iOS | 未签名 IPA（安装前需自行签名或使用 TrollStore） | 未签名 | 远端（仅 GitHub Actions 可构建） |
| 通用 | 每个安装包对应的 SHA-256 校验文件 | — | 远端 |

推送 `main` 分支则由 [CI 工作流](https://github.com/1378944437/BearFuel/actions/workflows/ci.yml)执行格式检查、静态分析、单元测试与 Android/iOS 编译验证。

### 本地构建（可选）

发布前自验或离线安装时，可在本地直接构建：

```bash
flutter build apk --release --split-per-abi   # 分架构 Android APK
```

本地检测到发布密钥时自动签名，否则退化为调试签名。

### Android 签名

本地签名构建需要在 `android/key.properties` 中配置密钥，或设置以下环境变量：

- `BEARFUEL_KEY_ALIAS`
- `BEARFUEL_KEY_PASSWORD`
- `BEARFUEL_KEYSTORE_PATH`
- `BEARFUEL_STORE_PASSWORD`

远端发布需要在 GitHub 仓库中配置以下 Actions Secrets：

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`
- `ANDROID_STORE_PASSWORD`

### 版本规范

版本号以 `pubspec.yaml` 为唯一来源（`X.Y.Z+Build`），发布标签必须与版本一致（`vX.Y.Z`），每次发布同步更新 [CHANGELOG.md](CHANGELOG.md)。

## 说明

本项目为个人自用项目，未附带开源许可证。第三方地图、油价和天气服务的使用应遵守各自服务条款与额度限制。
