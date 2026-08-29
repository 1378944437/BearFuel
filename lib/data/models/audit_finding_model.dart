import 'dart:convert';

/// AI 账本审查状态
class AuditStatus {
  static const String pending = 'pending'; // 待确认
  static const String resolved = 'resolved'; // 已处理
  static const String ignored = 'ignored'; // 已忽略

  const AuditStatus._();
}

/// 审查严重级别
class AuditSeverity {
  static const String info = 'info';
  static const String warning = 'warning';
  static const String critical = 'critical';

  static int rank(String severity) {
    switch (severity) {
      case critical:
        return 3;
      case warning:
        return 2;
      default:
        return 1;
    }
  }

  const AuditSeverity._();
}

/// 审查发现（异常条目）
class AuditFinding {
  final String id;
  final String runId; // 产生该发现的审查批次
  final String? recordId; // 关联的加油记录（null = 车辆级发现）
  final String findingType; // finding_type 见 LedgerAuditService 规则常量
  final String severity;
  final String title;
  final String explanation;
  final String? suggestion;
  final Map<String, dynamic>? evidence; // 证据：字段/原值/参考值/来源
  final List<Map<String, dynamic>> suggestedChanges; // 采纳需人工确认
  final String? confidence; // low / medium / high
  final String status;
  final String? userNote;
  final String dataHash; // 原始数据指纹，用于变更后要求重新审查
  final DateTime createdAt;
  final DateTime? resolvedAt;

  const AuditFinding({
    required this.id,
    required this.runId,
    required this.recordId,
    required this.findingType,
    required this.severity,
    required this.title,
    required this.explanation,
    this.suggestion,
    this.evidence,
    this.suggestedChanges = const [],
    this.confidence,
    required this.status,
    this.userNote,
    required this.dataHash,
    required this.createdAt,
    this.resolvedAt,
  });

  bool get isPending => status == AuditStatus.pending;

  Map<String, dynamic> toMap() => {
    'id': id,
    'run_id': runId,
    'record_id': recordId,
    'finding_type': findingType,
    'severity': severity,
    'title': title,
    'explanation': explanation,
    'suggestion': suggestion,
    'evidence_json': evidence == null
        ? null
        : jsonEncode(evidence),
    'suggested_changes_json': suggestedChanges.isEmpty
        ? null
        : jsonEncode(suggestedChanges),
    'confidence': confidence,
    'status': status,
    'user_note': userNote,
    'data_hash': dataHash,
    'created_at': createdAt.toIso8601String(),
    'resolved_at': resolvedAt?.toIso8601String(),
  };

  factory AuditFinding.fromMap(Map<String, dynamic> map) {
    Map<String, dynamic>? readJsonMap(String? text) {
      if (text == null || text.isEmpty) return null;
      try {
        final decoded = jsonDecode(text);
        return decoded is Map<String, dynamic> ? decoded : null;
      } catch (_) {
        return null;
      }
    }

    List<Map<String, dynamic>> readJsonList(String? text) {
      if (text == null || text.isEmpty) return const [];
      try {
        final decoded = jsonDecode(text);
        if (decoded is! List) return const [];
        return decoded
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
      } catch (_) {
        return const [];
      }
    }

    return AuditFinding(
      id: map['id'] as String,
      runId: map['run_id'] as String? ?? '',
      recordId: map['record_id'] as String?,
      findingType: map['finding_type'] as String? ?? 'unknown',
      severity: map['severity'] as String? ?? AuditSeverity.info,
      title: map['title'] as String? ?? '',
      explanation: map['explanation'] as String? ?? '',
      suggestion: map['suggestion'] as String?,
      evidence: readJsonMap(map['evidence_json'] as String?),
      suggestedChanges: readJsonList(map['suggested_changes_json'] as String?),
      confidence: map['confidence'] as String?,
      status: map['status'] as String? ?? AuditStatus.pending,
      userNote: map['user_note'] as String?,
      dataHash: map['data_hash'] as String? ?? '',
      createdAt:
          DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.now(),
      resolvedAt: DateTime.tryParse(map['resolved_at'] as String? ?? ''),
    );
  }
}

/// 一次审查批次
class AuditRun {
  final String id;
  final String? vehicleId;
  final String triggerType; // manual / record_saved / price_refreshed
  final String dataHash;
  final String? model; // 参与解释的 AI 模型（未用 AI 为 null）
  final String? promptVersion;
  final String status; // running / success / error
  final DateTime createdAt;
  final DateTime? completedAt;
  final String? errorMessage;

  const AuditRun({
    required this.id,
    this.vehicleId,
    required this.triggerType,
    required this.dataHash,
    this.model,
    this.promptVersion,
    required this.status,
    required this.createdAt,
    this.completedAt,
    this.errorMessage,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'vehicle_id': vehicleId,
    'trigger_type': triggerType,
    'data_hash': dataHash,
    'model': model,
    'prompt_version': promptVersion,
    'status': status,
    'created_at': createdAt.toIso8601String(),
    'completed_at': completedAt?.toIso8601String(),
    'error_message': errorMessage,
  };
}
