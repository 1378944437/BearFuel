/// 车辆其他费用记录数据模型（保养、保险、年检、停车、洗车等）
class ExpenseRecordModel {
  final String id; // 记录唯一主键 UUID
  final String vehicleId; // 所属车辆 ID
  final String category; // 费用类别 (如 保养维护、车辆保险等)
  final DateTime expenseDate; // 费用发生日期
  final double amount; // 金额 (¥)
  final double? currentMileage; // 发生时里程表读数 (km)
  final double? nextReminderMileage; // 下次提醒里程 (如保养提醒：15000 km)
  final DateTime? nextReminderDate; // 下次提醒日期 (如保险到期日)
  final String? note; // 备注说明
  final DateTime createdAt; // 创建时间

  ExpenseRecordModel({
    required this.id,
    required this.vehicleId,
    required this.category,
    required this.expenseDate,
    required this.amount,
    this.currentMileage,
    this.nextReminderMileage,
    this.nextReminderDate,
    this.note,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// 转换为 Map 存入 SQLite
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'vehicle_id': vehicleId,
      'category': category,
      'expense_date': expenseDate.toIso8601String(),
      'amount': amount,
      'current_mileage': currentMileage,
      'next_reminder_mileage': nextReminderMileage,
      'next_reminder_date': nextReminderDate?.toIso8601String(),
      'note': note,
      'created_at': createdAt.toIso8601String(),
    };
  }

  /// 从 SQLite Map 映射还原
  factory ExpenseRecordModel.fromMap(Map<String, dynamic> map) {
    return ExpenseRecordModel(
      id: map['id'] as String,
      vehicleId: map['vehicle_id'] as String,
      category: map['category'] as String,
      expenseDate:
          DateTime.tryParse(map['expense_date'] as String? ?? '') ??
          DateTime.now(),
      amount: (map['amount'] as num).toDouble(),
      currentMileage: (map['current_mileage'] as num?)?.toDouble(),
      nextReminderMileage: (map['next_reminder_mileage'] as num?)?.toDouble(),
      nextReminderDate: map['next_reminder_date'] != null
          ? DateTime.tryParse(map['next_reminder_date'] as String)
          : null,
      note: map['note'] as String?,
      createdAt:
          DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  /// 复制并更新部分属性
  ExpenseRecordModel copyWith({
    String? id,
    String? vehicleId,
    String? category,
    DateTime? expenseDate,
    double? amount,
    double? currentMileage,
    double? nextReminderMileage,
    DateTime? nextReminderDate,
    String? note,
    DateTime? createdAt,
  }) {
    return ExpenseRecordModel(
      id: id ?? this.id,
      vehicleId: vehicleId ?? this.vehicleId,
      category: category ?? this.category,
      expenseDate: expenseDate ?? this.expenseDate,
      amount: amount ?? this.amount,
      currentMileage: currentMileage ?? this.currentMileage,
      nextReminderMileage: nextReminderMileage ?? this.nextReminderMileage,
      nextReminderDate: nextReminderDate ?? this.nextReminderDate,
      note: note ?? this.note,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
