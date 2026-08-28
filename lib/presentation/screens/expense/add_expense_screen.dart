import 'package:bearfuel/core/theme/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/validators.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/utils/input_formatters.dart';
import '../../../data/models/expense_record_model.dart';
import '../../../providers/vehicle_provider.dart';
import '../../../providers/expense_provider.dart';
import '../../../providers/refuel_provider.dart';

/// 记录车辆其他费用与保养页面
class AddExpenseScreen extends StatefulWidget {
  const AddExpenseScreen({super.key});

  @override
  State<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends State<AddExpenseScreen> {
  final _formKey = GlobalKey<FormState>();

  late DateTime _selectedDate;
  late String _selectedCategory;
  late TextEditingController _amountController;
  late TextEditingController _mileageController;
  late TextEditingController _reminderMileageController;
  late TextEditingController _noteController;

  DateTime? _reminderDate;
  bool _enableReminder = false;

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();
    _selectedCategory = ExpenseCategory.maintenance;

    final refuelProv = context.read<RefuelProvider>();
    final currentMileage = refuelProv.latestMileage;

    _amountController = TextEditingController();
    _mileageController = TextEditingController(
      text: currentMileage > 0 ? currentMileage.toStringAsFixed(0) : '',
    );
    _reminderMileageController = TextEditingController(
      text:
          currentMileage > 0 ? (currentMileage + 5000).toStringAsFixed(0) : '',
    );
    _noteController = TextEditingController();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _mileageController.dispose();
    _reminderMileageController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  /// 选择费用发生日期
  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      locale: const Locale('zh', 'CN'),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  /// 选择下次到期提醒日期
  Future<void> _pickReminderDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate:
          _reminderDate ?? DateTime.now().add(const Duration(days: 180)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
      locale: const Locale('zh', 'CN'),
    );
    if (picked != null) {
      setState(() => _reminderDate = picked);
    }
  }

  /// 保存费用记录
  Future<void> _saveExpense() async {
    if (!_formKey.currentState!.validate()) return;

    final vehicleProv = context.read<VehicleProvider>();
    final expenseProv = context.read<ExpenseProvider>();
    final refuelProv = context.read<RefuelProvider>();
    final currentVehicle = vehicleProv.currentVehicle;

    if (currentVehicle == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先添加或选择一辆爱车')),
      );
      return;
    }

    final amount = double.parse(_amountController.text.trim());
    final currentMileage = double.tryParse(_mileageController.text.trim());

    double? reminderMileage;
    DateTime? reminderDate;
    if (_enableReminder) {
      reminderMileage = double.tryParse(_reminderMileageController.text.trim());
      reminderDate = _reminderDate;
    }

    final record = ExpenseRecordModel(
      id: const Uuid().v4(),
      vehicleId: currentVehicle.id,
      category: _selectedCategory,
      expenseDate: _selectedDate,
      amount: amount,
      currentMileage: currentMileage,
      nextReminderMileage: reminderMileage,
      nextReminderDate: reminderDate,
      note: _noteController.text.trim().isEmpty
          ? null
          : _noteController.text.trim(),
    );

    final success = await expenseProv.addExpense(
      record,
      currentMaxMileage: refuelProv.latestMileage,
    );

    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('费用记录已保存'), backgroundColor: Colors.green),
        );
        Navigator.of(context).pop(true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('保存失败，请重试'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('记一笔用车费用'),
        actions: [
          IconButton(
            icon: const Icon(AppIcons.check),
            tooltip: '保存',
            onPressed: _saveExpense,
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            // 1. 费用类别选择
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '费用类型',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: ExpenseCategory.allCategories.map((cat) {
                        final isSelected = _selectedCategory == cat;
                        return InkWell(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() {
                              _selectedCategory = cat;
                              // 若为保养或保险，默认开启提醒
                              if (cat == ExpenseCategory.maintenance ||
                                  cat == ExpenseCategory.insurance) {
                                _enableReminder = true;
                              }
                            });
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFFFF5A24)
                                  : Colors.grey.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isSelected
                                    ? const Color(0xFFFF5A24)
                                    : Colors.grey.withValues(alpha: 0.2),
                                width: 1,
                              ),
                            ),
                            child: Text(
                              cat,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: isSelected
                                    ? colors.onPrimary
                                    : colors.onSurface,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 2. 金额与发生日期
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    TextFormField(
                      controller: _amountController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [AppInputFormatters.decimal2],
                      decoration: const InputDecoration(
                        labelText: '支出金额',
                        hintText: '如 350.00',
                        suffixText: '¥',
                        prefixIcon: Icon(AppIcons.monetization_on_outlined),
                      ),
                      validator: (val) =>
                          Validators.positiveNumber(val, fieldName: '金额'),
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(AppIcons.calendar_today,
                          color: Color(0xFFFF5A24)),
                      title: const Text('发生日期'),
                      subtitle:
                          Text(DateFormatter.formatChineseYmd(_selectedDate)),
                      trailing:
                          const Icon(AppIcons.arrow_forward_ios, size: 14),
                      onTap: _pickDate,
                    ),
                    const Divider(height: 1),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _mileageController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [AppInputFormatters.decimal2],
                      decoration: const InputDecoration(
                        labelText: '当前里程（选填）',
                        hintText: '如 12500',
                        suffixText: 'km',
                        prefixIcon: Icon(AppIcons.speed),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 3. 智能保养/保险到期提醒设置
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
                          '设置下次提醒（如保养/保险）',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                        Switch(
                          value: _enableReminder,
                          activeThumbColor: const Color(0xFFFF5A24),
                          onChanged: (val) =>
                              setState(() => _enableReminder = val),
                        ),
                      ],
                    ),
                    if (_enableReminder) ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _reminderMileageController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: [AppInputFormatters.decimal2],
                        decoration: const InputDecoration(
                          labelText: '下次提醒里程 (km)',
                          hintText: '如 17500',
                          prefixIcon:
                              Icon(AppIcons.notification_important_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading:
                            const Icon(AppIcons.alarm, color: Colors.orange),
                        title: const Text('下次提醒日期'),
                        subtitle: Text(
                          _reminderDate != null
                              ? DateFormatter.formatChineseYmd(_reminderDate!)
                              : '点击设定到期提醒日',
                        ),
                        trailing:
                            const Icon(AppIcons.arrow_forward_ios, size: 14),
                        onTap: _pickReminderDate,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 4. 备注说明
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      controller: _noteController,
                      maxLines: 2,
                      inputFormatters: [AppInputFormatters.note],
                      decoration: const InputDecoration(
                        labelText: '备注说明（最多100字）',
                        hintText: '如：更换全合成机油、机滤、工时费等',
                        prefixIcon: Icon(AppIcons.edit_note_outlined),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // 常用项目快捷标签
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      child: Row(
                        children: [
                          ...[
                            '机油机滤',
                            '空气滤芯',
                            '空调滤芯',
                            '刹车片',
                            '火花塞',
                            '电瓶更换',
                            '洗车精洗',
                            '四轮定位'
                          ].map((tag) {
                            return Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: InkWell(
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  final current = _noteController.text.trim();
                                  if (current.isEmpty) {
                                    _noteController.text = tag;
                                  } else if (!current.contains(tag)) {
                                    _noteController.text = '$current、$tag';
                                  }
                                },
                                borderRadius: BorderRadius.circular(4),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                        color:
                                            Colors.grey.withValues(alpha: 0.2)),
                                  ),
                                  child: Text(
                                    '+ $tag',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: colors.onSurfaceVariant),
                                  ),
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // 保存按钮
            ElevatedButton(
              onPressed: _saveExpense,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
              ),
              child: const Text(
                '保存费用记录',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
