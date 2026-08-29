import 'package:bearfuel/core/theme/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/config/app_config.dart';
import '../../../core/utils/validators.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/utils/input_formatters.dart';
import '../../../data/models/refuel_record_model.dart';
import '../../../providers/vehicle_provider.dart';
import '../../../providers/refuel_provider.dart';
import 'station_map_picker_sheet.dart';
import '../../widgets/app_date_picker.dart';

/// BearFuel 记录加油页面（支持双向联动换算、里程快捷增量与触感反馈）
class AddRefuelScreen extends StatefulWidget {
  final RefuelRecordModel? editRecord; // 若传入则为编辑模式

  const AddRefuelScreen({super.key, this.editRecord});

  @override
  State<AddRefuelScreen> createState() => _AddRefuelScreenState();
}

class _AddRefuelScreenState extends State<AddRefuelScreen> {
  final _formKey = GlobalKey<FormState>();

  late DateTime _selectedDate;
  late TextEditingController _mileageController;
  late TextEditingController _amountController; // 升数
  late TextEditingController _unitPriceController; // 单价
  late TextEditingController _totalPriceController; // 总额
  late TextEditingController _stationController;
  late TextEditingController _noteController;

  late String _selectedFuelType;
  late bool _isFullTank;
  late bool _isForgotPrevious;

  bool _isAutoCalculating = false;
  bool _isSaving = false; // 防止连点保存产生重复记录

  @override
  void initState() {
    super.initState();
    final edit = widget.editRecord;
    final refuelProv = context.read<RefuelProvider>();
    final vehicleProv = context.read<VehicleProvider>();
    final currentVehicle = vehicleProv.currentVehicle;

    _selectedDate = edit?.refuelDate ?? DateTime.now();
    _mileageController = TextEditingController(
      text: edit != null ? edit.mileage.toString() : '',
    );
    _amountController = TextEditingController(
      text: edit != null ? edit.fuelAmount.toString() : '',
    );
    _unitPriceController = TextEditingController(
      text: edit != null
          ? edit.unitPrice.toString()
          : (refuelProv.latestUnitPrice?.toString() ?? ''),
    );
    _totalPriceController = TextEditingController(
      text: edit != null ? edit.totalPrice.toString() : '',
    );
    _stationController = TextEditingController(
      text: edit?.gasStation ?? (refuelProv.latestGasStation ?? ''),
    );
    _noteController = TextEditingController(text: edit?.note ?? '');

    _selectedFuelType =
        edit?.fuelType ??
        (currentVehicle?.defaultFuelType ??
            refuelProv.latestFuelType ??
            FuelType.gas92);
    _isFullTank = edit?.isFullTank ?? true;
    _isForgotPrevious = edit?.isForgotPrevious ?? false;
  }

  @override
  void dispose() {
    _mileageController.dispose();
    _amountController.dispose();
    _unitPriceController.dispose();
    _totalPriceController.dispose();
    _stationController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  /// 升数变更联动计算
  void _onAmountChanged(String val) {
    if (_isAutoCalculating) return;
    _isAutoCalculating = true;

    final amount = double.tryParse(val);
    final unitPrice = double.tryParse(_unitPriceController.text);

    if (amount != null && unitPrice != null && amount > 0 && unitPrice > 0) {
      _totalPriceController.text = (amount * unitPrice).toStringAsFixed(2);
    }
    _isAutoCalculating = false;
  }

  /// 单价变更联动计算
  void _onUnitPriceChanged(String val) {
    if (_isAutoCalculating) return;
    _isAutoCalculating = true;

    final unitPrice = double.tryParse(val);
    final amount = double.tryParse(_amountController.text);
    final total = double.tryParse(_totalPriceController.text);

    if (unitPrice != null && unitPrice > 0) {
      if (amount != null && amount > 0) {
        _totalPriceController.text = (amount * unitPrice).toStringAsFixed(2);
      } else if (total != null && total > 0) {
        _amountController.text = (total / unitPrice).toStringAsFixed(2);
      }
    }
    _isAutoCalculating = false;
  }

  /// 总额变更联动计算
  void _onTotalPriceChanged(String val) {
    if (_isAutoCalculating) return;
    _isAutoCalculating = true;

    final total = double.tryParse(val);
    final unitPrice = double.tryParse(_unitPriceController.text);

    if (total != null && unitPrice != null && total > 0 && unitPrice > 0) {
      _amountController.text = (total / unitPrice).toStringAsFixed(2);
    }
    _isAutoCalculating = false;
  }

  /// 快速按增量增加里程
  void _applyMileageIncrement(double increment, double baseMileage) {
    HapticFeedback.selectionClick();
    final current =
        double.tryParse(_mileageController.text.trim()) ?? baseMileage;
    final newMileage =
        (current > baseMileage ? current : baseMileage) + increment;
    setState(() {
      _mileageController.text = newMileage.toStringAsFixed(1);
    });
  }

  /// 快速填入常用加油金额
  void _applyQuickAmount(double amount) {
    HapticFeedback.selectionClick();
    _totalPriceController.text = amount.toStringAsFixed(2);
    _onTotalPriceChanged(amount.toString());
  }

  /// 选择日期时间
  Future<void> _pickDateTime() async {
    HapticFeedback.selectionClick();
    final pickedDate = await AppDatePicker.show(
      context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      title: '选择加油日期',
    );

    if (pickedDate != null && mounted) {
      final pickedTime = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(_selectedDate),
      );

      setState(() {
        if (pickedTime != null) {
          _selectedDate = DateTime(
            pickedDate.year,
            pickedDate.month,
            pickedDate.day,
            pickedTime.hour,
            pickedTime.minute,
          );
        } else {
          // 取消时间选择时保留原有时间，仅替换日期，避免时间被重置为 00:00
          _selectedDate = DateTime(
            pickedDate.year,
            pickedDate.month,
            pickedDate.day,
            _selectedDate.hour,
            _selectedDate.minute,
          );
        }
      });
    }
  }

  /// 保存加油记录
  Future<void> _saveRecord() async {
    if (_isSaving) return; // 写入进行中，忽略重复点击
    if (!_formKey.currentState!.validate()) return;

    final vehicleProv = context.read<VehicleProvider>();
    final refuelProv = context.read<RefuelProvider>();
    final currentVehicle = vehicleProv.currentVehicle;

    if (currentVehicle == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先添加或选择一辆爱车')));
      return;
    }

    HapticFeedback.lightImpact();
    setState(() => _isSaving = true);

    try {
      final mileage = double.parse(_mileageController.text.trim());
      final fuelAmount = double.parse(_amountController.text.trim());
      final unitPrice = double.parse(_unitPriceController.text.trim());
      final totalPrice = double.parse(_totalPriceController.text.trim());

      final isEdit = widget.editRecord != null;
      final record = RefuelRecordModel(
        id: isEdit ? widget.editRecord!.id : const Uuid().v4(),
        vehicleId: widget.editRecord?.vehicleId ?? currentVehicle.id,
        refuelDate: _selectedDate,
        mileage: mileage,
        fuelAmount: fuelAmount,
        unitPrice: unitPrice,
        totalPrice: totalPrice,
        fuelType: _selectedFuelType,
        gasStation: _stationController.text.trim().isEmpty
            ? null
            : _stationController.text.trim(),
        isFullTank: _isFullTank,
        isForgotPrevious: _isForgotPrevious,
        note: _noteController.text.trim().isEmpty
            ? null
            : _noteController.text.trim(),
      );

      final success = isEdit
          ? await refuelProv.updateRecord(record)
          : await refuelProv.addRecord(record);

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(isEdit ? '加油记录已更新' : '加油记录保存成功'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context);
        } else {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('保存失败，请检查输入')));
        }
      }
    } catch (e) {
      AppConfig.log('保存加油记录异常: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('保存异常，请重试')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isEdit = widget.editRecord != null;
    final refuelProv = context.watch<RefuelProvider>();
    final lastMileage = refuelProv.latestMileage;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? '编辑加油记录' : '记一笔加油'),
        actions: [
          IconButton(
            icon: const Icon(AppIcons.check, size: 26),
            tooltip: '保存',
            onPressed: _isSaving ? null : _saveRecord,
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            // 1. 日期与时间选择
            Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                leading: const Icon(
                  AppIcons.calendar_today,
                  color: Color(0xFFFF5A24),
                ),
                title: const Text('加油时间', style: TextStyle(fontSize: 14)),
                trailing: Text(
                  DateFormatter.formatYmdHm(_selectedDate),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                onTap: _pickDateTime,
              ),
            ),
            const SizedBox(height: 16),

            // 2. 当前总里程输入与快捷增量步进器
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '当前表显总里程',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (lastMileage > 0)
                          Text(
                            '上次里程: ${lastMileage.toStringAsFixed(1)} km',
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _mileageController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [AppInputFormatters.decimal2],
                      decoration: InputDecoration(
                        hintText: '输入仪表盘总里程',
                        hintStyle: TextStyle(
                          fontSize: 11,
                          color: colors.onSurfaceVariant.withValues(
                            alpha: 0.75,
                          ),
                        ),
                        suffixText: 'km',
                        prefixIcon: const Icon(AppIcons.speed),
                      ),
                      validator: (val) => Validators.mileage(
                        val,
                        lastMileage:
                            widget.editRecord == null && lastMileage > 0
                            ? lastMileage
                            : null,
                      ),
                    ),
                    if (lastMileage > 0 && !isEdit) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text(
                            '快捷累加: ',
                            style: TextStyle(
                              fontSize: 11,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                          ...[50.0, 100.0, 200.0, 500.0].map((inc) {
                            return Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: InkWell(
                                onTap: () =>
                                    _applyMileageIncrement(inc, lastMileage),
                                borderRadius: BorderRadius.circular(4),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(
                                      0xFFFF5A24,
                                    ).withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '+${inc.toInt()}km',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFFFF5A24),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 3. 加油升数、单价与总额（三项双向联动）
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '燃油数据（输入任意两项自动换算）',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // 快捷金额胶囊
                    Row(
                      children: [
                        Text(
                          '快捷金额: ',
                          style: TextStyle(
                            fontSize: 11,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        ...[100.0, 200.0, 300.0, 400.0, 500.0].map((amt) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: InkWell(
                              onTap: () => _applyQuickAmount(amt),
                              borderRadius: BorderRadius.circular(4),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '¥${amt.toInt()}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.blue,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _amountController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [AppInputFormatters.decimal2],
                      style: TextStyle(color: colors.onSurface),
                      decoration: InputDecoration(
                        labelText: '加油量',
                        hintText: '如 45.50',
                        hintStyle: TextStyle(
                          fontSize: 11,
                          color: colors.onSurfaceVariant.withValues(
                            alpha: 0.75,
                          ),
                        ),
                        suffixText: 'L',
                        prefixIcon: const Icon(AppIcons.local_gas_station),
                      ),
                      onChanged: _onAmountChanged,
                      validator: (val) =>
                          Validators.positiveNumber(val, fieldName: '加油量'),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _unitPriceController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: [AppInputFormatters.decimal2],
                            style: TextStyle(color: colors.onSurface),
                            decoration: InputDecoration(
                              labelText: '单价',
                              hintText: '如 8.25',
                              hintStyle: TextStyle(
                                fontSize: 11,
                                color: colors.onSurfaceVariant.withValues(
                                  alpha: 0.75,
                                ),
                              ),
                              suffixText: '¥/L',
                              prefixIcon: const Icon(
                                AppIcons.price_change_outlined,
                              ),
                            ),
                            onChanged: _onUnitPriceChanged,
                            validator: (val) =>
                                Validators.positiveNumber(val, fieldName: '单价'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _totalPriceController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: [AppInputFormatters.decimal2],
                            style: TextStyle(color: colors.onSurface),
                            decoration: InputDecoration(
                              labelText: '实付总金额',
                              hintText: '如 375.00',
                              hintStyle: TextStyle(
                                fontSize: 11,
                                color: colors.onSurfaceVariant.withValues(
                                  alpha: 0.75,
                                ),
                              ),
                              suffixText: '¥',
                              prefixIcon: const Icon(
                                AppIcons.monetization_on_outlined,
                              ),
                            ),
                            onChanged: _onTotalPriceChanged,
                            validator: (val) => Validators.positiveNumber(
                              val,
                              fieldName: '实付总额',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 4. 燃油标号选择
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '燃油标号',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: FuelType.allTypes.map((type) {
                        final isSelected = _selectedFuelType == type;
                        return ChoiceChip(
                          label: Text(type),
                          selected: isSelected,
                          showCheckmark: false,
                          selectedColor: const Color(
                            0xFFFF5A24,
                          ).withValues(alpha: 0.18),
                          labelStyle: TextStyle(
                            color: isSelected ? const Color(0xFFFF5A24) : null,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                          onSelected: (selected) {
                            if (selected) {
                              HapticFeedback.selectionClick();
                              setState(() => _selectedFuelType = type);
                            }
                          },
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 5. 小熊油耗关键计算开关
            Card(
              margin: EdgeInsets.zero,
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('本次加满跳枪（推荐）'),
                    subtitle: const Text(
                      'BearFuel 算法基准：只有加满才能精确测算该区间真实油耗',
                      style: TextStyle(fontSize: 12),
                    ),
                    activeThumbColor: const Color(0xFFFF5A24),
                    value: _isFullTank,
                    onChanged: (val) {
                      HapticFeedback.selectionClick();
                      setState(() => _isFullTank = val);
                    },
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    title: const Text('漏记了前一次加油'),
                    subtitle: const Text(
                      '若之前某次加油忘记记录，开启此项将重置计算断点，避免油耗失真',
                      style: TextStyle(fontSize: 12),
                    ),
                    activeThumbColor: Colors.orange,
                    value: _isForgotPrevious,
                    onChanged: (val) {
                      HapticFeedback.selectionClick();
                      setState(() => _isForgotPrevious = val);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 6. 加油站与备注信息
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    TextFormField(
                      controller: _stationController,
                      style: TextStyle(color: colors.onSurface),
                      inputFormatters: [AppInputFormatters.stationName],
                      decoration: InputDecoration(
                        labelText: '加油站名称（最多40字）',
                        hintText: '如 中国石化金龙加油站',
                        hintStyle: TextStyle(
                          fontSize: 11,
                          color: colors.onSurfaceVariant.withValues(
                            alpha: 0.75,
                          ),
                        ),
                        prefixIcon: const Icon(AppIcons.storefront),
                        suffixIcon: IconButton(
                          icon: const Icon(
                            AppIcons.map_outlined,
                            color: Color(0xFFFF5A24),
                          ),
                          tooltip: '智能地图选站',
                          onPressed: () async {
                            HapticFeedback.lightImpact();
                            final selected = await StationMapPickerSheet.show(
                              context,
                              initialStationName: _stationController.text,
                            );
                            if (selected != null && selected.isNotEmpty) {
                              setState(() {
                                _stationController.text = selected;
                              });
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _noteController,
                      style: TextStyle(color: colors.onSurface),
                      inputFormatters: [AppInputFormatters.note],
                      decoration: InputDecoration(
                        labelText: '备注说明（最多100字）',
                        hintText: '记录优惠活动、高速路段或路况等',
                        hintStyle: TextStyle(
                          fontSize: 11,
                          color: colors.onSurfaceVariant.withValues(
                            alpha: 0.75,
                          ),
                        ),
                        prefixIcon: const Icon(AppIcons.note_alt_outlined),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // 保存大按钮
            ElevatedButton(
              onPressed: _isSaving ? null : _saveRecord,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF5A24),
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
              ),
              child: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      isEdit ? '保存修改' : '保存加油记录',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
