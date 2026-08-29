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
import 'dart:async';

import '../../../providers/audit_provider.dart';
import '../../../providers/fuel_price_provider.dart';
import '../../../providers/refuel_provider.dart';
import 'station_map_picker_sheet.dart';
import '../../widgets/app_date_picker.dart';

/// BearFuel 记录加油页面（对标小熊油耗记油流程：
/// 机显单价 × 加油量 = 机显金额 联动、优惠与实付区、油量警告灯、
/// 加满提示横幅与"上次加油记录了吗"引导）
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
  late TextEditingController _amountController; // 加油量（升）
  late TextEditingController _unitPriceController; // 机显单价
  late TextEditingController _pumpAmountController; // 机显金额
  late TextEditingController _discountController; // 优惠金额
  late TextEditingController _totalPriceController; // 实付金额
  late TextEditingController _stationController;
  late TextEditingController _noteController;

  late String _selectedFuelType;
  late bool _isFullTank;
  late bool _isForgotPrevious;
  bool? _fuelWarningLightOn; // null = 未记录

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
    // 机显金额 = 单价 × 加油量（编辑态回显计算值）
    final initAmount = double.tryParse(_amountController.text);
    final initPrice = double.tryParse(_unitPriceController.text);
    _pumpAmountController = TextEditingController(
      text: edit != null && initAmount != null && initPrice != null
          ? (initAmount * initPrice).toStringAsFixed(2)
          : '',
    );
    _discountController = TextEditingController(
      text: edit?.discountAmount != null ? edit!.discountAmount.toString() : '',
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
    _fuelWarningLightOn = edit?.fuelWarningLightOn;
  }

  @override
  void dispose() {
    _mileageController.dispose();
    _amountController.dispose();
    _unitPriceController.dispose();
    _pumpAmountController.dispose();
    _discountController.dispose();
    _totalPriceController.dispose();
    _stationController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  /// 加油量变更联动：机显金额 = 单价 × 加油量
  void _onAmountChanged(String val) {
    if (_isAutoCalculating) return;
    _isAutoCalculating = true;

    final amount = double.tryParse(val);
    final unitPrice = double.tryParse(_unitPriceController.text);

    if (amount != null && unitPrice != null && amount > 0 && unitPrice > 0) {
      _pumpAmountController.text = (amount * unitPrice).toStringAsFixed(2);
      _syncPaidAmount();
    }
    _isAutoCalculating = false;
  }

  /// 机显单价变更联动
  void _onUnitPriceChanged(String val) {
    if (_isAutoCalculating) return;
    _isAutoCalculating = true;

    final unitPrice = double.tryParse(val);
    final amount = double.tryParse(_amountController.text);
    final pumpAmount = double.tryParse(_pumpAmountController.text);

    if (unitPrice != null && unitPrice > 0) {
      if (amount != null && amount > 0) {
        _pumpAmountController.text = (amount * unitPrice).toStringAsFixed(2);
        _syncPaidAmount();
      } else if (pumpAmount != null && pumpAmount > 0) {
        _amountController.text = (pumpAmount / unitPrice).toStringAsFixed(2);
        _syncPaidAmount();
      }
    }
    _isAutoCalculating = false;
  }

  /// 机显金额变更联动：加油量 = 机显金额 / 单价
  void _onPumpAmountChanged(String val) {
    if (_isAutoCalculating) return;
    _isAutoCalculating = true;

    final pumpAmount = double.tryParse(val);
    final unitPrice = double.tryParse(_unitPriceController.text);

    if (pumpAmount != null &&
        unitPrice != null &&
        pumpAmount > 0 &&
        unitPrice > 0) {
      _amountController.text = (pumpAmount / unitPrice).toStringAsFixed(2);
      _syncPaidAmount();
    }
    _isAutoCalculating = false;
  }

  /// 优惠金额变更：实付金额 = 机显金额 - 优惠金额
  void _onDiscountChanged(String val) {
    if (_isAutoCalculating) return;
    _isAutoCalculating = true;
    _syncPaidAmount();
    _isAutoCalculating = false;
  }

  /// 按当前机显金额与优惠金额刷新实付金额（保留手动覆盖结果）
  void _syncPaidAmount() {
    final pumpAmount = double.tryParse(_pumpAmountController.text);
    if (pumpAmount == null) return;
    final discount = double.tryParse(_discountController.text.trim()) ?? 0.0;
    final paid = pumpAmount - discount;
    if (paid >= 0) {
      _totalPriceController.text = paid.toStringAsFixed(2);
    }
  }

  /// 实付金额手动变更：无优惠时反推加油量
  void _onTotalPriceChanged(String val) {
    if (_isAutoCalculating) return;
    _isAutoCalculating = true;

    final total = double.tryParse(val);
    final unitPrice = double.tryParse(_unitPriceController.text);
    final discount = double.tryParse(_discountController.text.trim()) ?? 0.0;

    if (total != null &&
        unitPrice != null &&
        total > 0 &&
        unitPrice > 0 &&
        discount <= 0) {
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

  /// 快速填入常用加油金额（写入机显金额并联动）
  void _applyQuickAmount(double amount) {
    HapticFeedback.selectionClick();
    _pumpAmountController.text = amount.toStringAsFixed(2);
    _onPumpAmountChanged(amount.toString());
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
    final priceProv = context.read<FuelPriceProvider>();
    final auditProv = context.read<AuditProvider>();
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
      final discountText = _discountController.text.trim();
      final discountAmount = discountText.isEmpty
          ? null
          : double.parse(discountText);

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
        discountAmount: (discountAmount == null || discountAmount <= 0)
            ? null
            : discountAmount,
        fuelWarningLightOn: _fuelWarningLightOn,
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
          // 保存/修改后执行一次本地规则审查（不调用 AI）
          unawaited(
            auditProv.runLocalRulesAudit(
              records: refuelProv.records,
              recordById: (id) {
                for (final r in refuelProv.records) {
                  if (r.id == id) return r;
                }
                return null;
              },
              tankCapacity: currentVehicle.tankCapacity,
              priceSnapshot: priceProv.priceSnapshotFor(
                priceProv.currentProvince,
              ),
              province: priceProv.currentProvince,
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
          // 底部叠加系统手势条安全区，避免最后的内容被遮挡
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            16 + MediaQuery.of(context).padding.bottom,
          ),
          children: [
            // 0. 加满提示横幅（对标小熊油耗官方流程）
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF6D6),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFF0D264)),
              ),
              child: const Text(
                '如果不是正好加满油箱，请不要选择"加满"。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF6B5B1F),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // 1. 日期与时间选择
            Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                leading: const Icon(
                  AppIcons.calendar_today,
                  color: Color(0xFFFF5A24),
                ),
                title: const Text('加油时间 *', style: TextStyle(fontSize: 14)),
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
            const SizedBox(height: 12),

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
                          '当前总里程 *',
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
                        suffixText: '公里',
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
            const SizedBox(height: 12),

            // 3. 机显数据（单价 × 加油量 = 金额）
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Text(
                          '机显数据 *',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(width: 6),
                        _QuestionMarkTooltip(
                          message: '加油机/小票上显示的单价、加油量与金额，输入任意两项自动换算',
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
                    // 机显单价 × 加油量 = 机显金额
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
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
                              labelText: '机显单价',
                              hintText: '7.79',
                              hintStyle: TextStyle(
                                fontSize: 11,
                                color: colors.onSurfaceVariant.withValues(
                                  alpha: 0.75,
                                ),
                              ),
                              suffixText: '元/升',
                            ),
                            onChanged: _onUnitPriceChanged,
                            validator: (val) => Validators.positiveNumber(
                              val,
                              fieldName: '机显单价',
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Text(
                            '×',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                        Expanded(
                          child: TextFormField(
                            controller: _amountController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: [AppInputFormatters.decimal2],
                            style: TextStyle(color: colors.onSurface),
                            decoration: InputDecoration(
                              labelText: '加油量',
                              hintText: '45.50',
                              hintStyle: TextStyle(
                                fontSize: 11,
                                color: colors.onSurfaceVariant.withValues(
                                  alpha: 0.75,
                                ),
                              ),
                              suffixText: '升',
                            ),
                            onChanged: _onAmountChanged,
                            validator: (val) => Validators.positiveNumber(
                              val,
                              fieldName: '加油量',
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Text(
                            '=',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                        Expanded(
                          child: TextFormField(
                            controller: _pumpAmountController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: [AppInputFormatters.decimal2],
                            style: TextStyle(color: colors.onSurface),
                            decoration: InputDecoration(
                              labelText: '机显金额',
                              hintText: '354.00',
                              hintStyle: TextStyle(
                                fontSize: 11,
                                color: colors.onSurfaceVariant.withValues(
                                  alpha: 0.75,
                                ),
                              ),
                              suffixText: '元',
                            ),
                            onChanged: _onPumpAmountChanged,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // 4. 实付区（优惠金额 + 实付金额）
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Text(
                          '实付信息',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(width: 6),
                        _QuestionMarkTooltip(
                          message:
                              '有加油站优惠或支付立减时填写优惠金额，实付金额将自动按"机显金额 - 优惠金额"计算，也可手动修改',
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _discountController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: [AppInputFormatters.decimal2],
                            style: TextStyle(color: colors.onSurface),
                            decoration: InputDecoration(
                              labelText: '优惠金额（选填）',
                              hintText: '0.00',
                              hintStyle: TextStyle(
                                fontSize: 11,
                                color: colors.onSurfaceVariant.withValues(
                                  alpha: 0.75,
                                ),
                              ),
                              suffixText: '元',
                            ),
                            onChanged: _onDiscountChanged,
                            validator: (val) {
                              final text = val?.trim() ?? '';
                              if (text.isEmpty) return null;
                              final discount = double.tryParse(text);
                              if (discount == null || discount < 0) {
                                return '优惠金额格式不正确';
                              }
                              final pumpAmount = double.tryParse(
                                _pumpAmountController.text,
                              );
                              if (pumpAmount != null && discount > pumpAmount) {
                                return '优惠金额不能超过机显金额';
                              }
                              return null;
                            },
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
                              labelText: '实付金额 *',
                              hintText: '如 375.00',
                              hintStyle: TextStyle(
                                fontSize: 11,
                                color: colors.onSurfaceVariant.withValues(
                                  alpha: 0.75,
                                ),
                              ),
                              suffixText: '元',
                            ),
                            onChanged: _onTotalPriceChanged,
                            validator: (val) => Validators.positiveNumber(
                              val,
                              fieldName: '实付金额',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // 5. 是否加满？（分段选择 + 说明）
            _SegmentedQuestionCard(
              label: '是否加满?',
              isRequired: true,
              tooltip: '只有加满跳枪才能精确计算该区间真实油耗；未加满的油量会累计到下一次加满时平摊',
              options: const [true, false],
              optionLabels: const ['加满', '没加满'],
              selected: _isFullTank,
              accentColor: const Color(0xFFFF5A24),
              onSelect: (val) {
                HapticFeedback.selectionClick();
                setState(() => _isFullTank = val);
              },
            ),
            const SizedBox(height: 12),

            // 6. 油量警告灯?
            _SegmentedQuestionCard<bool?>(
              label: '油量警告灯?',
              tooltip: '记录加油时仪表盘油量警告灯是否点亮，用于回顾"亮灯才去加油"的用车习惯',
              options: const [true, false, null],
              optionLabels: const ['油灯亮', '没有亮', '未记录'],
              selected: _fuelWarningLightOn,
              accentColor: const Color(0xFFFF5A24),
              onSelect: (val) {
                HapticFeedback.selectionClick();
                setState(() => _fuelWarningLightOn = val);
              },
            ),
            const SizedBox(height: 12),

            // 7. 燃油标号选择
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
            const SizedBox(height: 12),

            // 8. 上次加油记录了吗?（漏记引导）
            _SegmentedQuestionCard<bool>(
              label: '上次加油记录了吗?',
              tooltip: '若上一次加油忘记记账，选择"没记录"会重置油耗计算基准，避免本次油耗虚高',
              options: const [false, true],
              optionLabels: const ['记录了', '没记录'],
              selected: _isForgotPrevious,
              accentColor: const Color(0xFFFF5A24),
              onSelect: (val) {
                HapticFeedback.selectionClick();
                setState(() => _isForgotPrevious = val);
              },
            ),
            const SizedBox(height: 12),

            // 9. 加油站与备注信息
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
            const SizedBox(height: 20),

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

/// "？" 说明气泡
class _QuestionMarkTooltip extends StatelessWidget {
  final String message;

  const _QuestionMarkTooltip({required this.message});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: message,
      triggerMode: TooltipTriggerMode.tap,
      showDuration: const Duration(seconds: 4),
      child: Container(
        width: 16,
        height: 16,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            width: 1,
          ),
        ),
        child: Text(
          '?',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// 分段式问答题卡片（对标小熊"是否加满 / 油量警告灯 / 上次加油记录了吗"交互）
class _SegmentedQuestionCard<T> extends StatelessWidget {
  final String label;
  final String? tooltip;
  final bool isRequired;
  final List<T> options;
  final List<String> optionLabels;
  final T selected;
  final Color accentColor;
  final ValueChanged<T> onSelect;

  const _SegmentedQuestionCard({
    required this.label,
    required this.options,
    required this.optionLabels,
    required this.selected,
    required this.accentColor,
    required this.onSelect,
    this.tooltip,
    this.isRequired = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(
                  child: Text(
                    isRequired ? '$label *' : label,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (tooltip != null) ...[
                  const SizedBox(width: 6),
                  _QuestionMarkTooltip(message: tooltip!),
                ],
              ],
            ),
            const SizedBox(height: 10),
            // 选项整行铺开（等宽分段），窄屏也不会溢出
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<T>(
                showSelectedIcon: false,
                segments: [
                  for (var i = 0; i < options.length; i++)
                    ButtonSegment(
                      value: options[i],
                      label: Text(
                        optionLabels[i],
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                ],
                selected: {selected},
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  backgroundColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return accentColor;
                    }
                    return colors.surfaceContainerHighest.withValues(
                      alpha: 0.55,
                    );
                  }),
                  foregroundColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return Colors.white;
                    }
                    return colors.onSurfaceVariant;
                  }),
                ),
                onSelectionChanged: (selection) {
                  if (selection.isNotEmpty) {
                    onSelect(selection.first);
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
