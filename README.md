# BearFuel - 类小熊油耗 Flutter 车辆油耗与成本管理应用

本项目是一款对标 **“小熊油耗”** 业务模型的专业级车用油耗与全周期用车成本管理应用。基于 **Flutter 3.x + Dart 3.x** 构建，采用标准分层架构与状态管理，支持多车辆档案管理、精准油耗平摊算法、保养智能预警及可视化图表分析。

---

## 一、 项目架构分层

```text
lib/
├── core/                       # 核心基础设施层
│   ├── config/app_config.dart  # 环境隔离与日志配置 (Dev/Prod)
│   ├── constants/              # 全局常量 (燃油类型、费用类型等)
│   ├── theme/app_theme.dart    # 视觉主题规范 (Material 3 + 车机深浅色适配)
│   └── utils/                  # 边界校验器 (Validators) 与日期格式化 (DateFormatter)
├── data/                       # 数据持久层
│   ├── models/                 # 数据实体 (VehicleModel, RefuelRecordModel, ExpenseRecordModel)
│   └── database/               # 本地 SQLite 核心数据库管理与仓储 (DatabaseHelper)
├── domain/                     # 业务算法与领域服务层
│   ├── fuel_calculator.dart    # 小熊油耗核心计算引擎 (连续加满、未加满平摊、漏记断点算法)
│   └── statistics_service.dart # 统计汇总、趋势点位、费用占比与保养提醒服务
├── providers/                  # 响应式状态管理层 (Provider)
│   ├── vehicle_provider.dart   # 车辆状态管理
│   ├── refuel_provider.dart    # 加油记录与油耗计算状态管理
│   └── expense_provider.dart   # 其他费用与到期提醒状态管理
├── presentation/               # 视图呈现层 (UI Screens & Widgets)
│   ├── widgets/                # 通用 UI 组件 (CustomCard, StatBadge, EmptyStateView)
│   └── screens/
│       ├── main_navigation_screen.dart # 底部主导航框架
│       ├── dashboard/          # 首页仪表盘 (综合油耗大字、快捷记账、预警Banner)
│       ├── refuel/             # 加油记账页面 (三项智能联动换算、加满/漏记开关)
│       ├── expense/            # 其它费用记账页面 (保养/保险/洗车/路桥，提醒设定)
│       ├── records/            # 历史流水明细列表 (支持编辑、滑动删除与计算状态标记)
│       ├── charts/             # 可视化统计图表大屏 (fl_chart 油耗趋势、油价走势、费用环形图)
│       └── vehicle/            # 车辆车库档案管理 (多车切换、增删改查)
└── main.dart                   # 应用入口与依赖注入配置
```

---

## 二、 交付配套三件套

### 1. 依赖清单 (Dependencies Manifest)

| 依赖包名称 | 版本范围 | 作用与选型理由 |
| :--- | :--- | :--- |
| **`flutter`** | `>=3.10.0` | 跨平台 UI 框架核心 SDK |
| **`flutter_localizations`** | SDK 内置 | 国际化与简体中文语言包支持（日期选择器等） |
| **`provider`** | `^6.1.2` | 官方推荐的高性能响应式状态管理，轻量且分层清晰 |
| **`sqflite`** | `^2.3.3+1` | 本地 SQLite 关系型数据库，保障数据离线安全持久化 |
| **`path`** | `^1.9.0` | 跨平台文件路径拼接与数据库路径管理 |
| **`shared_preferences`** | `^2.2.3` | 轻量级本地键值对配置存储 |
| **`fl_chart`** | `^0.68.0` | 专业 Flutter 图表引擎（支持折线图、平滑曲线、饼状图） |
| **`intl`** | `^0.19.0` | 规范化日期时间解析与货币数值格式化 |
| **`uuid`** | `^4.4.0` | 生成全局唯一业务主键 ID |
| **`cupertino_icons`** | `^1.0.8` | iOS/macOS 风格矢量图标集 |

---

### 2. 完整调用示例 (Code Examples)

#### 示例 1：小熊油耗算法计算引擎直接调用
```dart
import 'package:bearfuel/data/models/refuel_record_model.dart';
import 'package:bearfuel/domain/fuel_calculator.dart';

void main() {
  // 构造加油记录流水
  final records = [
    RefuelRecordModel(
      id: '1',
      vehicleId: 'car_001',
      refuelDate: DateTime(2026, 1, 1),
      mileage: 10000.0,
      fuelAmount: 50.0,
      unitPrice: 8.0,
      totalPrice: 400.0,
      fuelType: '92# 汽油',
      isFullTank: true, // 基准首充加满
    ),
    RefuelRecordModel(
      id: '2',
      vehicleId: 'car_001',
      refuelDate: DateTime(2026, 1, 10),
      mileage: 10600.0, // 区间行驶 600 km
      fuelAmount: 45.0, // 加满消耗 45 L
      unitPrice: 8.0,
      totalPrice: 360.0,
      fuelType: '92# 汽油',
      isFullTank: true,
    ),
  ];

  // 1. 批量计算油耗
  final computed = FuelCalculator.computeRecords(records);
  print('第2次加油百公里油耗: ${computed[1].fuelConsumption} L/100km'); // 输出: 7.50 L/100km
  print('第2次加油每公里花费: ¥${computed[1].costPerKm}/km'); // 输出: ¥0.60/km

  // 2. 统计整车指标
  final summary = FuelCalculator.calculateSummary(computed);
  print('综合加权平均油耗: ${summary.averageConsumption} L/100km');
}
```

#### 示例 2：在 Flutter 页面中通过 Provider 触发记账
```dart
// 在任一 StatelessWidget 或 StatefulWidget 中：
final refuelProv = context.read<RefuelProvider>();

final newRecord = RefuelRecordModel(
  id: const Uuid().v4(),
  vehicleId: '当前车辆ID',
  refuelDate: DateTime.now(),
  mileage: 11200.0,
  fuelAmount: 42.5,
  unitPrice: 8.15,
  totalPrice: 346.38,
  fuelType: '92# 汽油',
  gasStation: '中石化朝阳路站',
  isFullTank: true,
  isForgotPrevious: false,
);

// 保存后自动触发状态更新并重算油耗指标
await refuelProv.addRecord(newRecord);
```

---

### 3. 部署调试与运行步骤

#### 环境准备
- **Flutter SDK**: 3.10.0 或更高版本
- **Dart SDK**: 3.0.0 或更高版本
- 操作系统支持：Android、iOS、Windows、macOS、Web

#### 运行与调试命令
1. **克隆/进入项目根目录**：
   ```bash
   cd c:/Users/z1768/Desktop/新建文件夹
   ```
2. **下载并安装所有依赖包**：
   ```bash
   flutter pub get
   ```
3. **配置高德真实地址和加油站 POI（可选）**：
   打开 App 首页右上角的“地图服务设置”，输入个人申请的高德 Web 服务 Key 并保存。Key 会保存在当前设备的安全存储中。

   配置 Key 后，地图选站会请求高德真实地址和周边加油站；未配置时不会加载内置站点示例数据。
4. **运行算法单元测试**：
   ```bash
   flutter test test/fuel_calculator_test.dart
   ```
5. **以开发模式启动应用 (支持热重载 Hot Reload)**：
   ```bash
   # 启动到连接的手机/模拟器/Windows桌面
   flutter run
   ```
6. **打包生产环境安装包 (Release)**：
   ```bash
   # Android 全架构 APK（armeabi-v7a、arm64-v8a、x86_64）
   flutter build apk --release --target-platform android-arm,android-arm64,android-x64 \
     -Pbearfuel.targetAbis=armeabi-v7a,arm64-v8a,x86_64

   # iOS 未签名 IPA（需自签名或 TrollStore 后使用）
   flutter build ios --release --no-codesign
   ```

#### 发布产物
Release 仅生成 Android 全架构 APK 和 iOS 未签名 IPA。iOS 产物不包含 Apple 开发者证书，需使用自签名或 TrollStore 处理后安装。

#### 工程与发布约定

- 本项目以 Flutter `3.44.3`、Dart `3.12.2` 和 Java `17` 为构建基线。
- `pubspec.yaml` 是版本名称和 Android build number 的唯一来源。
- `main` 为稳定分支；功能和修复使用短期分支，经 CI 通过后合并。
- 发布时先更新 `CHANGELOG.md` 和 `pubspec.yaml`，再创建 `vX.Y.Z` Tag。
- Tag 会触发 `.github/workflows/release.yml`，构建并发布 Android 全架构 APK 和 iOS 未签名 IPA。
- Release Keystore、`android/key.properties`、个人 API Key、APK 和个人账本数据禁止提交。

GitHub Release 工作流需要以下仓库 Secrets：

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`
- `ANDROID_STORE_PASSWORD`

#### 签名说明
Android Release 使用固定的 BearFuel Release Keystore；iOS 发布包为未签名 IPA，需自行完成签名或通过 TrollStore 安装。

1. **`Target file "lib/main.dart" not found`**：确认当前终端位于项目根目录下执行命令。
2. **SQLite 数据库只读或权限报错**：`sqflite` 自动在各端应用专属沙盒路径中建立数据库文件（开发环境为 `bear_fuel_dev.db`，生产环境为 `bear_fuel.db`），无需手动申请额外存储权限。
3. **中文显示方块/乱码**：本工程已配置 `flutter_localizations` 并使用 Material Design 标准无衬线字体，在各平台原生正常渲染。

---

## 三、 数据备份与安全回滚方案

1. **自动环境隔离**：开发调试与生产运行分别使用独立数据库名（`bear_fuel_dev.db` vs `bear_fuel.db`），避免测试脏数据污染生产库。
2. **SQLite 事务保护机制**：车辆删除、记录增删改均在 `db.transaction` 中执行，发生异常自动回滚，确保数据强一致性。
3. **数据库备份与恢复**：
   - 数据库文件位于系统应用沙盒 `getDatabasesPath()` 目录下。
   - 备份命令：直接复制该 `.db` 文件至备份目录。
   - 回滚方案：若版本迁移或测试出现异常，将备份的 `.db` 文件覆盖回原路径即可无损恢复。
