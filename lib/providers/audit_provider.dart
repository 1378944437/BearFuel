import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config/app_config.dart';
import '../data/database/database_helper.dart';
import '../data/models/audit_finding_model.dart';
import '../data/models/refuel_record_model.dart';
import '../data/services/ai_audit_config_store.dart';
import '../data/services/ai_audit_service.dart';
import '../data/services/apizero_fuel_price_service.dart';
import '../domain/ledger_audit_service.dart';

/// AI 账本审查状态管理。
///
/// 职责：执行本地规则审查、持久化发现、调度 AI 解释、维护处理状态。
/// 边界：本地规则可独立工作；AI 仅提供解释与建议，绝不直接修改账单。
class AuditProvider extends ChangeNotifier {
  final DatabaseHelper _db = DatabaseHelper();

  List<AuditFinding> _findings = [];
  bool _isLoading = false;
  bool _isRunning = false; // 规则审查进行中
  bool _isAiRunning = false; // AI 解释进行中
  String _statusText = '尚未执行账本审查';
  int _pendingCount = 0;
  String _highestSeverity = 'info';
  bool _lastRunUsedAi = false;

  List<AuditFinding> get findings => _findings;
  bool get isLoading => _isLoading;
  bool get isRunning => _isRunning;
  bool get isAiRunning => _isAiRunning;
  String get statusText => _statusText;
  int get pendingCount => _pendingCount;
  String get highestSeverity => _highestSeverity;
  bool get lastRunUsedAi => _lastRunUsedAi;
  bool get isAiConfigured => AiAuditConfigStore.isConfigured;

  /// 首页入口数据
  Future<void> refreshSummary() async {
    try {
      final summary = await _db.getAuditSummary();
      _pendingCount = summary['count'] as int? ?? 0;
      _highestSeverity = summary['highest_severity'] as String? ?? 'info';
      notifyListeners();
    } catch (e) {
      AppConfig.log('读取审查摘要失败: $e');
    }
  }

  /// 加载发现列表（全部状态，界面侧再过滤）
  Future<void> loadFindings() async {
    _isLoading = true;
    notifyListeners();
    try {
      final rows = await _db.getAuditFindings();
      _findings = rows.map(AuditFinding.fromMap).toList();
    } catch (e) {
      AppConfig.log('读取审查发现失败: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 某条记录的待确认发现（账单详情页提示用）
  Future<List<AuditFinding>> findingsForRecord(String recordId) async {
    try {
      final rows = await _db.getAuditFindings(
        statuses: [AuditStatus.pending],
        recordId: recordId,
      );
      return rows.map(AuditFinding.fromMap).toList();
    } catch (_) {
      return const [];
    }
  }

  /// 执行本地规则审查
  ///
  /// [last30DaysOnly] 为 true 时只审查最近 30 天的记录。
  Future<int> runLocalRulesAudit({
    required RefuelRecordModel? Function(String recordId) recordById,
    required List<RefuelRecordModel> records,
    required double? tankCapacity,
    required ApiZeroFuelPriceSnapshot? priceSnapshot,
    required String province,
    bool last30DaysOnly = false,
  }) async {
    if (_isRunning) return 0;
    _isRunning = true;
    _statusText = '正在执行本地规则审查...';
    notifyListeners();

    final runId = 'run_${DateTime.now().millisecondsSinceEpoch}';
    final scope = last30DaysOnly
        ? records
              .where(
                (r) => r.refuelDate.isAfter(
                  DateTime.now().subtract(const Duration(days: 30)),
                ),
              )
              .toList()
        : records;

    final runMap = AuditRun(
      id: runId,
      triggerType: 'manual',
      dataHash:
          'records_${scope.length}_${DateTime.now().millisecondsSinceEpoch}',
      promptVersion: LedgerAuditServiceRuntime.promptVersion,
      status: 'running',
      createdAt: DateTime.now(),
    ).toMap();

    try {
      await _db.insertAuditRun(runMap);
      var newCount = 0;
      if (scope.isEmpty) {
        _statusText = '所选范围内没有加油记录';
        await _db.updateAuditRun(
          runId,
          status: 'success',
          completedAt: DateTime.now(),
        );
        return 0;
      }

      final findings = LedgerAuditService.runLocalRules(
        records: scope,
        dataHashOf: LedgerAuditService.hashRecord,
        tankCapacity: tankCapacity,
        priceSnapshot: priceSnapshot,
      );
      final findingMaps = findings
          .map(
            (f) => AuditFinding(
              id: 'f_${DateTime.now().microsecondsSinceEpoch}_$newCount',
              runId: runId,
              recordId: f.recordId,
              findingType: f.findingType,
              severity: f.severity,
              title: f.title,
              explanation: f.explanation,
              suggestion: f.suggestion,
              evidence: f.evidence,
              suggestedChanges: f.suggestedChanges,
              confidence: 'high',
              status: AuditStatus.pending,
              dataHash: f.dataHash,
              createdAt: DateTime.now(),
            ).toMap(),
          )
          .toList();
      newCount = await _db.upsertAuditFindings(runId, findingMaps);
      await _db.updateAuditRun(
        runId,
        status: 'success',
        completedAt: DateTime.now(),
      );
      _lastRunUsedAi = false;
      _statusText = '本地规则审查完成：${findings.length} 项发现，本次新增 $newCount 项';
      await loadFindings();
      await refreshSummary();
      return newCount;
    } catch (e) {
      AppConfig.log('本地规则审查失败: $e');
      _statusText = '本地规则审查失败：$e';
      await _db.updateAuditRun(
        runId,
        status: 'error',
        completedAt: DateTime.now(),
        errorMessage: '$e',
      );
      return 0;
    } finally {
      _isRunning = false;
      notifyListeners();
    }
  }

  /// 对待确认发现批量请求 AI 解释（需先完成本地审查并配置 AI）。
  /// 手动触发间隔至少 1 分钟；单次最多处理 [limit] 条。
  Future<int> runAiExplanations({
    required Map<String, dynamic> Function(AuditFinding finding) contextBuilder,
    int limit = 10,
  }) async {
    if (_isAiRunning) return 0;
    if (!AiAuditConfigStore.isConfigured) {
      _statusText = '尚未配置 AI 审查服务，本地规则结果不受影响';
      notifyListeners();
      return 0;
    }

    // 手动重分析间隔至少 1 分钟
    try {
      final prefs = await SharedPreferences.getInstance();
      final last = prefs.getInt('audit_ai_last_manual');
      if (last != null) {
        final elapsed = DateTime.now().difference(
          DateTime.fromMillisecondsSinceEpoch(last),
        );
        if (!elapsed.isNegative && elapsed < const Duration(minutes: 1)) {
          _statusText = 'AI 分析间隔至少 1 分钟，请稍后再试';
          notifyListeners();
          return 0;
        }
      }
      await prefs.setInt(
        'audit_ai_last_manual',
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {}

    final pending = _findings.where((f) => f.isPending).take(limit).toList();
    if (pending.isEmpty) {
      _statusText = '没有待确认的异常需要 AI 分析';
      notifyListeners();
      return 0;
    }

    _isAiRunning = true;
    _statusText = '正在请求 AI 解释（0/${pending.length}）...';
    notifyListeners();

    var succeeded = 0;
    try {
      for (var i = 0; i < pending.length; i++) {
        final finding = pending[i];
        _statusText = '正在请求 AI 解释（${i + 1}/${pending.length}）...';
        notifyListeners();

        final result = await AiAuditService.reviewFinding(
          context: contextBuilder(finding),
        );
        if (result == null) {
          // AI 不可用：保留本地规则结果
          _statusText = 'AI 解释暂不可用，本地规则已完成检查';
          break;
        }
        await _db.updateAuditFindingAiResult(
          finding.id,
          explanation: result.explanation,
          suggestion: result.suggestion,
          confidence: result.confidence,
          severity: result.severity,
          model: AiAuditConfigStore.model,
        );
        succeeded++;
      }
      if (succeeded > 0) {
        _lastRunUsedAi = true;
        _statusText = 'AI 解释完成：$succeeded/${pending.length} 条';
        await loadFindings();
      }
      return succeeded;
    } catch (e) {
      AppConfig.log('AI 解释失败: $e');
      _statusText = 'AI 解释失败：本地规则结果不受影响';
      return succeeded;
    } finally {
      _isAiRunning = false;
      notifyListeners();
    }
  }

  /// 更新发现状态（处理 / 忽略 / 重新打开）
  Future<void> setFindingStatus(
    AuditFinding finding,
    String status, {
    String? userNote,
  }) async {
    await _db.updateAuditFindingStatus(
      finding.id,
      status: status,
      userNote: userNote ?? finding.userNote,
    );
    await loadFindings();
    await refreshSummary();
  }

  /// 为 AI 请求构建结构化上下文（不含车牌、完整备注与定位信息）
  Map<String, dynamic> buildFindingContext({
    required AuditFinding finding,
    RefuelRecordModel? record,
    double? tankCapacity,
    double? recentMedianConsumption,
    required String province,
    ApiZeroFuelPriceSnapshot? priceSnapshot,
  }) {
    final evidence = finding.evidence;
    final reference = <String, dynamic>{};
    final apiPrice = priceSnapshot?.price;
    if (priceSnapshot != null && apiPrice != null) {
      reference['province'] = province;
      reference['api_price_date'] = apiPrice.lastChangeDate
          .toIso8601String()
          .substring(0, 10);
      reference['source'] = 'ApiZero';
      reference['gas92'] = apiPrice.gas92;
      reference['gas95'] = apiPrice.gas95;
      reference['gas98'] = apiPrice.gas98;
    }

    return {
      'task': 'review_refuel_record',
      'rule_finding': {
        'type': finding.findingType,
        'severity': finding.severity,
        'title': finding.title,
        'explanation': finding.explanation,
      },
      if (record != null)
        'record': {
          'date': record.refuelDate.toIso8601String().substring(0, 10),
          'mileage': record.mileage,
          'fuel_amount': record.fuelAmount,
          'unit_price': record.unitPrice,
          'total_price': record.totalPrice,
          'discount_amount': record.discountAmount,
          'fuel_type': record.fuelType,
          'is_full_tank': record.isFullTank,
          'is_forgot_previous': record.isForgotPrevious,
        },
      if (tankCapacity != null)
        'vehicle': {
          'tank_capacity': tankCapacity,
          'recent_median_consumption': ?recentMedianConsumption,
        },
      if (reference.isNotEmpty) 'reference': reference,
      'rule_findings': [
        finding.explanation,
        ...?evidence?.values.map(
          (e) => jsonizeEvidence(Map<String, dynamic>.from(e as Map)),
        ),
      ],
    };
  }
}

Map<String, dynamic> jsonizeEvidence(Map<String, dynamic> evidence) => {
  'field': evidence['field'],
  'record_value': evidence['record_value'],
  'reference_value': evidence['reference_value'],
  'source': evidence['source'],
};

/// 运行期常量（与提示词版本联动）
class LedgerAuditServiceRuntime {
  static const String promptVersion = AiAuditService.promptVersion;
}
