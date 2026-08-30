import 'package:flutter/foundation.dart';

import '../core/config/app_config.dart';
import '../data/database/database_helper.dart';
import '../data/models/audit_finding_model.dart';
import '../data/models/refuel_record_model.dart';
import '../data/services/apizero_fuel_price_service.dart';
import '../data/services/audit_rule_store.dart';
import '../domain/ledger_audit_rules.dart';
import '../domain/ledger_audit_service.dart';

/// 账本审查状态管理。
///
/// 职责：按激活规则库执行本地规则审查、持久化发现、维护处理状态。
/// 边界：纯本地规则引擎，不依赖任何在线服务；发现异常仅提示，绝不直接修改账单。
class AuditProvider extends ChangeNotifier {
  final DatabaseHelper _db = DatabaseHelper();

  List<AuditFinding> _findings = [];
  bool _isLoading = false;
  bool _isRunning = false; // 规则审查进行中
  String _statusText = '尚未执行账本审查';
  int _pendingCount = 0;
  String _highestSeverity = 'info';
  String _lastRunRuleSetId = AuditRuleSet.builtinId;

  List<AuditFinding> get findings => _findings;
  bool get isLoading => _isLoading;
  bool get isRunning => _isRunning;
  String get statusText => _statusText;
  int get pendingCount => _pendingCount;
  String get highestSeverity => _highestSeverity;

  /// 当前激活的规则套件（审查页展示用）
  AuditRuleSet get activeRuleSet {
    final sets = AuditRuleSetStore.sets;
    final match = sets.where((s) => s.id == _lastRunRuleSetId).toList();
    return match.isNotEmpty ? match.first : AuditRuleSetStore.activeSet;
  }

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

  /// 按激活规则库执行本地规则审查
  ///
  /// [last30DaysOnly] 为 true 时只审查最近 30 天的记录。
  Future<int> runLocalRulesAudit({
    required List<RefuelRecordModel> records,
    required double? tankCapacity,
    required ApiZeroFuelPriceSnapshot? priceSnapshot,
    bool last30DaysOnly = false,
  }) async {
    if (_isRunning) return 0;
    _isRunning = true;
    await AuditRuleSetStore.ensureLoaded();
    final ruleSet = AuditRuleSetStore.activeSet;
    _lastRunRuleSetId = ruleSet.id;
    _statusText = '正在按「${ruleSet.name}」执行本地规则审查...';
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
      promptVersion: 'ledger-local-rules-v1',
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
        ruleSet: ruleSet,
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
      _statusText =
          '规则审查完成（${ruleSet.name}）：${findings.length} 项发现，本次新增 $newCount 项';
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
}
