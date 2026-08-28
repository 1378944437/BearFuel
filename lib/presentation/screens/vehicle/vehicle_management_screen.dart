import 'package:bearfuel/core/theme/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/validators.dart';
import '../../../core/utils/input_formatters.dart';
import '../../../data/models/vehicle_model.dart';
import '../../../providers/vehicle_provider.dart';
import '../../../providers/refuel_provider.dart';
import '../../../providers/expense_provider.dart';
import '../../widgets/license_plate_input_field.dart';
import '../settings/service_settings_screen.dart';
import '../../widgets/app_page_title.dart';

/// 车辆档案与多车辆管理页面
class VehicleManagementScreen extends StatelessWidget {
  const VehicleManagementScreen({super.key});

  /// 弹出添加/编辑车辆对话框
  void _showVehicleDialog(BuildContext context, {VehicleModel? editVehicle}) {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController(text: editVehicle?.name ?? '');
    final plateCtrl = TextEditingController(
      text: editVehicle?.plateNumber ?? '',
    );
    final brandCtrl = TextEditingController(text: editVehicle?.brand ?? '');
    final modelCtrl = TextEditingController(text: editVehicle?.model ?? '');
    final capacityCtrl = TextEditingController(
      text: editVehicle != null ? editVehicle.tankCapacity.toString() : '50',
    );
    final mileageCtrl = TextEditingController(
      text: editVehicle != null ? editVehicle.initialMileage.toString() : '0',
    );
    String selectedFuel = editVehicle?.defaultFuelType ?? FuelType.gas92;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final bgColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;

        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            return Material(
              color: bgColor,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  top: 20,
                  bottom: MediaQuery.of(modalCtx).viewInsets.bottom + 20,
                ),
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              editVehicle != null ? '编辑车辆档案' : '添加爱车',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(AppIcons.close),
                              onPressed: () => Navigator.pop(ctx),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: nameCtrl,
                          inputFormatters: [AppInputFormatters.maxChars(40)],
                          decoration: const InputDecoration(
                            labelText: '车辆昵称 *',
                            hintText: '如：我的领克03、家用卡罗拉',
                            prefixIcon: Icon(AppIcons.directions_car),
                          ),
                          validator: (v) =>
                              Validators.requiredText(v, message: '请输入车辆昵称'),
                        ),
                        const SizedBox(height: 12),

                        // 中国机动车号牌专用录入模块（省份简称点选 + 大写/新能源车牌）
                        LicensePlateInputField(
                          initialPlate: plateCtrl.text,
                          onChanged: (val) {
                            plateCtrl.text = val;
                          },
                        ),
                        const SizedBox(height: 12),

                        TextFormField(
                          controller: brandCtrl,
                          inputFormatters: [AppInputFormatters.maxChars(40)],
                          decoration: const InputDecoration(
                            labelText: '车辆品牌/车型（选填）',
                            hintText: '如：丰田卡罗拉 / 大众高尔夫',
                            prefixIcon: Icon(
                              AppIcons.branding_watermark_outlined,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),

                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: capacityCtrl,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                inputFormatters: [AppInputFormatters.decimal2],
                                decoration: const InputDecoration(
                                  labelText: '油箱容积 (L) *',
                                  hintText: '50.0',
                                  suffixText: 'L',
                                  prefixIcon: Icon(
                                    AppIcons.local_gas_station_outlined,
                                  ),
                                ),
                                validator: (v) => Validators.positiveNumber(
                                  v,
                                  fieldName: '油箱容积',
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: mileageCtrl,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                inputFormatters: [AppInputFormatters.decimal2],
                                decoration: const InputDecoration(
                                  labelText: '初始里程 (km) *',
                                  hintText: '0.0',
                                  suffixText: 'km',
                                  prefixIcon: Icon(AppIcons.speed),
                                ),
                                validator: (v) => Validators.nonNegativeNumber(
                                  v,
                                  fieldName: '初始里程',
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          '推荐燃油标号',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          children: FuelType.allTypes.map((fuel) {
                            return ChoiceChip(
                              label: Text(
                                fuel,
                                style: const TextStyle(fontSize: 12),
                              ),
                              selected: selectedFuel == fuel,
                              showCheckmark: false,
                              selectedColor: const Color(
                                0xFFFF5A24,
                              ).withValues(alpha: 0.18),
                              labelStyle: TextStyle(
                                color: selectedFuel == fuel
                                    ? const Color(0xFFFF5A24)
                                    : null,
                                fontWeight: selectedFuel == fuel
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                              onSelected: (sel) {
                                if (sel) {
                                  setModalState(() => selectedFuel = fuel);
                                }
                              },
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton(
                          onPressed: () async {
                            if (!formKey.currentState!.validate()) return;
                            final vehicleProv = context.read<VehicleProvider>();

                            final vehicle = VehicleModel(
                              id: editVehicle?.id ?? const Uuid().v4(),
                              name: nameCtrl.text.trim(),
                              plateNumber: plateCtrl.text.trim().isEmpty
                                  ? null
                                  : plateCtrl.text.trim(),
                              brand: brandCtrl.text.trim().isEmpty
                                  ? null
                                  : brandCtrl.text.trim(),
                              model: modelCtrl.text.trim().isEmpty
                                  ? null
                                  : modelCtrl.text.trim(),
                              tankCapacity:
                                  double.tryParse(capacityCtrl.text.trim()) ??
                                      50.0,
                              initialMileage:
                                  double.tryParse(mileageCtrl.text.trim()) ??
                                      0.0,
                              defaultFuelType: selectedFuel,
                              isDefault: editVehicle?.isDefault ??
                                  (vehicleProv.vehicles.isEmpty),
                            );

                            bool success = false;
                            String? errorMsg;
                            try {
                              if (editVehicle != null) {
                                success = await vehicleProv.updateVehicle(
                                  vehicle,
                                );
                              } else {
                                success = await vehicleProv.addVehicle(vehicle);
                                // 自动激活新添加的车辆
                                if (success &&
                                    (vehicleProv.vehicles.length == 1 ||
                                        vehicle.isDefault)) {
                                  await vehicleProv.selectVehicle(vehicle);
                                  if (context.mounted) {
                                    context.read<RefuelProvider>().loadRecords(
                                          vehicle.id,
                                        );
                                    context
                                        .read<ExpenseProvider>()
                                        .loadExpenses(vehicle.id);
                                  }
                                }
                              }
                            } catch (e) {
                              success = false;
                              errorMsg = e.toString();
                            }

                            if (ctx.mounted) Navigator.pop(ctx);

                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    success
                                        ? (editVehicle != null
                                            ? '已修改车辆“${vehicle.name}”档案'
                                            : '已成功添加爱车“${vehicle.name}”！')
                                        : '保存失败: ${errorMsg ?? "数据存取异常，请重试"}',
                                  ),
                                  backgroundColor:
                                      success ? Colors.green : Colors.red,
                                ),
                              );
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFF5A24),
                            foregroundColor: Colors.white,
                            minimumSize: const Size(double.infinity, 48),
                          ),
                          child: Text(editVehicle != null ? '保存修改' : '确认添加车辆'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildAddVehicleCard(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showVehicleDialog(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF5A24).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(AppIcons.add, color: Color(0xFFFF5A24)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '添加新爱车',
                      style: TextStyle(
                        color: colors.onSurface,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '建立车辆档案，开始记录油耗与用车成本',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(AppIcons.chevron_right, color: colors.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vehicleProv = context.watch<VehicleProvider>();
    final vehicles = vehicleProv.vehicles;
    final current = vehicleProv.currentVehicle;
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const AppPageTitle(title: '爱车档案', subtitle: '车辆资料与数据管理'),
        actions: [
          IconButton(
            icon: const Icon(AppIcons.settings_outlined),
            tooltip: '服务设置',
            onPressed: () {
              HapticFeedback.selectionClick();
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ServiceSettingsScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: vehicles.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    AppIcons.directions_car,
                    size: 64,
                    color: colors.onSurfaceVariant,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '暂无车辆档案，请先添加一辆爱车',
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: MediaQuery.of(context).size.width - 48,
                    child: _buildAddVehicleCard(context),
                  ),
                ],
              ),
            )
          : ListView.builder(
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
              itemCount: vehicles.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _buildAddVehicleCard(context);
                }

                final v = vehicles[index - 1];
                final isSelected = v.id == current?.id;

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  elevation: isSelected ? 3 : 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: isSelected
                          ? const Color(0xFFFF5A24)
                          : Colors.transparent,
                      width: 1.5,
                    ),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () async {
                      HapticFeedback.selectionClick();
                      final refuelProv = context.read<RefuelProvider>();
                      final expenseProv = context.read<ExpenseProvider>();
                      final success = await vehicleProv.selectVehicle(v);
                      // 切换关联数据
                      if (context.mounted) {
                        if (success) {
                          await refuelProv.loadRecords(v.id);
                          if (!context.mounted) return;
                          await expenseProv.loadExpenses(
                            v.id,
                            currentMaxMileage: refuelProv.latestMileage,
                          );
                          if (!context.mounted) return;
                        }
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              success ? '已切换当前车辆为: ${v.name}' : '切换车辆失败，请稍后重试',
                            ),
                            backgroundColor: success ? null : Colors.red,
                          ),
                        );
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    AppIcons.directions_car_filled,
                                    color: isSelected
                                        ? const Color(0xFFFF5A24)
                                        : colors.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    v.name,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              if (isSelected)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFF5A24),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Text(
                                    '当前激活',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // 左列：车牌 与 油箱（左边界严格对齐）
                              Expanded(
                                flex: 5,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '车牌: ${v.plateNumber != null && v.plateNumber!.isNotEmpty ? v.plateNumber! : "未录入"}',
                                      style: TextStyle(
                                        color: colors.onSurfaceVariant,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      '油箱: ${v.tankCapacity} L',
                                      style: TextStyle(
                                        color: colors.onSurfaceVariant,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              // 右列：油品标号 与 初始里程（左边界严格对齐）
                              Expanded(
                                flex: 5,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '油品标号: ${v.defaultFuelType}',
                                      style: TextStyle(
                                        color: colors.onSurfaceVariant,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      '初始里程: ${v.initialMileage} km',
                                      style: TextStyle(
                                        color: colors.onSurfaceVariant,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton.icon(
                                icon: const Icon(AppIcons.edit, size: 16),
                                label: const Text('编辑'),
                                onPressed: () {
                                  HapticFeedback.lightImpact();
                                  _showVehicleDialog(context, editVehicle: v);
                                },
                              ),
                              if (vehicles.length > 1) ...[
                                const SizedBox(width: 8),
                                TextButton.icon(
                                  icon: const Icon(
                                    AppIcons.delete_outline,
                                    size: 16,
                                    color: Colors.red,
                                  ),
                                  label: const Text(
                                    '删除',
                                    style: TextStyle(color: Colors.red),
                                  ),
                                  onPressed: () async {
                                    HapticFeedback.lightImpact();
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: const Text('确认删除车辆？'),
                                        content: Text(
                                          '删除“${v.name}”将同时清空该车辆名下的所有加油流水与费用明细记录，此操作无法撤销！',
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(ctx, false),
                                            child: const Text('取消'),
                                          ),
                                          ElevatedButton(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.red,
                                            ),
                                            onPressed: () =>
                                                Navigator.pop(ctx, true),
                                            child: const Text('确认彻底删除'),
                                          ),
                                        ],
                                      ),
                                    );

                                    if (confirm == true && context.mounted) {
                                      final wasCurrent =
                                          vehicleProv.currentVehicle?.id ==
                                              v.id;
                                      final refuelProv =
                                          context.read<RefuelProvider>();
                                      final expenseProv =
                                          context.read<ExpenseProvider>();
                                      final deleted =
                                          await vehicleProv.deleteVehicle(v.id);
                                      if (deleted &&
                                          wasCurrent &&
                                          context.mounted &&
                                          vehicleProv.currentVehicle != null) {
                                        final next =
                                            vehicleProv.currentVehicle!;
                                        await refuelProv.loadRecords(next.id);
                                        if (!context.mounted) return;
                                        await expenseProv.loadExpenses(
                                          next.id,
                                          currentMaxMileage:
                                              refuelProv.latestMileage,
                                        );
                                      }
                                    }
                                  },
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
