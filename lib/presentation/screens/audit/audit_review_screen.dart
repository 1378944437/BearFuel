import 'package:bearfuel/core/theme/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../data/models/audit_finding_model.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../data/models/refuel_record_model.dart';
import '../../../data/services/audit_rule_store.dart';
import '../../../providers/audit_provider.dart';
import '../settings/audit_rules_screen.dart';
import '../../../providers/fuel_price_provider.dart';
import '../../../providers/refuel_provider.dart';
import '../../../providers/vehicle_provider.dart';
import '../../widgets/empty_state_view.dart';

/// 账本异常审查页：本地规则 + AI 解释 + 用户确认。
class AuditReviewScreen extends StatefulWidget {
  const AuditReviewScreen({super.key});

  @override
  State<AuditReviewScreen> createState() => _AuditReviewScreenState();
}

class _AuditReviewScreenState extends State<AuditReviewScreen> {
  String _filter = 'pending'; // pending / critical / all / handled

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AuditProvider>().loadFindings();
      // 规则库加载完成后刷新工具栏中的规则名称
      AuditRuleSetStore.ensureLoaded().then((_) {
        if (mounted) setState(() {});
      });
    });
  }

  List<RefuelRecordModel> _recordsCache = const [];

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final audit = context.watch<AuditProvider>();
    _recordsCache = context.read<RefuelProvider>().records;
    final findings = _applyFilter(audit.findings);

    return Scaffold(
      appBar: AppBar(
        title: const Text('账本审查'),
        actions: [
          IconButton(
            icon: const Icon(AppIcons.settings_outlined),
            tooltip: '审查规则库',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AuditRuleSetsScreen()),
              );
              if (context.mounted) setState(() {});
            },
          ),
        ],
      ),
      body: Column(
        children: [
          _buildToolbar(audit),
          Divider(height: 1, color: colors.outlineVariant),
          Expanded(child: _buildBody(audit, findings)),
          _buildDisclaimer(),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------
  // 顶部工具栏
  // ------------------------------------------------------------------
  Widget _buildToolbar(AuditProvider audit) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${audit.statusText} · 当前规则：${audit.activeRuleSet.name}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _actionChip(
                  label: audit.isRunning ? '规则审查中…' : '审查全部账本',
                  icon: AppIcons.assessment_outlined,
                  enabled: !audit.isRunning,
                  onTap: () => _runRules(last30DaysOnly: false),
                ),
                const SizedBox(width: 6),
                _actionChip(
                  label: '最近 30 天',
                  icon: AppIcons.calendar_month,
                  enabled: !audit.isRunning,
                  onTap: () => _runRules(last30DaysOnly: true),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final entry in {
                  'pending': '待确认',
                  'critical': '严重异常',
                  'all': '全部',
                  'handled': '已处理',
                }.entries)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(
                        entry.key == 'pending' && audit.pendingCount > 0
                            ? '${entry.value} ${audit.pendingCount}'
                            : entry.value,
                      ),
                      selected: _filter == entry.key,
                      showCheckmark: false,
                      labelStyle: TextStyle(
                        fontSize: 12,
                        fontWeight: _filter == entry.key
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                      onSelected: (_) => setState(() => _filter = entry.key),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionChip({
    required String label,
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    final colors = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: enabled
              ? const Color(0xFFFF5A24).withValues(alpha: 0.1)
              : colors.onSurfaceVariant.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: enabled
                ? const Color(0xFFFF5A24).withValues(alpha: 0.35)
                : colors.outlineVariant,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: enabled
                  ? const Color(0xFFFF5A24)
                  : colors.onSurfaceVariant,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: enabled
                    ? const Color(0xFFFF5A24)
                    : colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------
  // 列表主体
  // ------------------------------------------------------------------
  Widget _buildBody(AuditProvider audit, List<AuditFinding> findings) {
    if (audit.isLoading || audit.isRunning) {
      return const Center(child: CircularProgressIndicator());
    }
    if (findings.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          EmptyStateView(
            title: _filter == 'handled' ? '暂无已处理记录' : '没有待确认的异常',
            subtitle: '按激活规则库对账本执行本地规则检查，发现异常可确认、忽略或采纳修正建议',
            buttonText: audit.findings.isEmpty ? '审查全部账本' : null,
            onButtonPressed: audit.findings.isEmpty
                ? () => _runRules(last30DaysOnly: false)
                : null,
          ),
        ],
      );
    }

    return RefreshIndicator(
      onRefresh: () => audit.loadFindings(),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
        itemCount: findings.length,
        itemBuilder: (context, index) =>
            _buildFindingCard(context, findings[index]),
      ),
    );
  }

  Widget _buildFindingCard(BuildContext context, AuditFinding finding) {
    final colors = Theme.of(context).colorScheme;
    final severityColor = finding.severity == AuditSeverity.critical
        ? Colors.red
        : finding.severity == AuditSeverity.warning
        ? Colors.orange
        : colors.primary;
    final statusLabel = finding.status == AuditStatus.pending
        ? '待确认'
        : finding.status == AuditStatus.resolved
        ? '已处理'
        : '已忽略';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题行
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: severityColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _typeLabel(finding.findingType),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: severityColor,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                if (finding.status != AuditStatus.pending)
                  Text(
                    statusLabel,
                    style: TextStyle(
                      fontSize: 10,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                const Spacer(),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              finding.title,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            if (_linkedRecordSummary(finding)) ...[
              const SizedBox(height: 3),
              Text(
                _linkedRecordSummaryText(finding),
                style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 4),
            Text(
              finding.explanation,
              style: const TextStyle(fontSize: 12, height: 1.45),
            ),
            if (finding.suggestion != null &&
                finding.suggestion!.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                '建议：${finding.suggestion}',
                style: TextStyle(
                  fontSize: 12,
                  color: colors.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ],
            // 证据
            if (finding.evidence != null && finding.evidence!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colors.onSurfaceVariant.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          AppIcons.check_circle_outline,
                          size: 14,
                          color: colors.onSurfaceVariant,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          '核查证据',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    for (final entry in finding.evidence!.entries)
                      _buildEvidenceRow(context, entry.key, entry.value),
                  ],
                ),
              ),
            ],
            if (finding.userNote != null && finding.userNote!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                '备注：${finding.userNote}',
                style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 8),
            // 操作区
            if (finding.isPending)
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  if (finding.suggestedChanges.isNotEmpty)
                    _findingAction(
                      label: '采纳建议',
                      icon: AppIcons.check,
                      color: Colors.green,
                      onTap: () => _adoptSuggestion(finding),
                    ),
                  _findingAction(
                    label: '确认无误',
                    icon: AppIcons.verified_outlined,
                    color: colors.primary,
                    onTap: () => _updateStatus(
                      finding,
                      AuditStatus.ignored,
                      note: '确认为优惠价或正常情况',
                    ),
                  ),
                  _findingAction(
                    label: '已处理',
                    icon: AppIcons.check_circle,
                    color: colors.onSurfaceVariant,
                    onTap: () => _updateStatus(
                      finding,
                      AuditStatus.resolved,
                      note: null,
                    ),
                  ),
                  _findingAction(
                    label: '忽略',
                    icon: AppIcons.close,
                    color: colors.onSurfaceVariant,
                    onTap: () =>
                        _updateStatus(finding, AuditStatus.ignored, note: null),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  bool _linkedRecordSummary(AuditFinding finding) =>
      _recordById(finding.recordId ?? '', _recordsCache) != null;

  String _linkedRecordSummaryText(AuditFinding finding) {
    final record = _recordById(finding.recordId ?? '', _recordsCache);
    if (record == null) return '';
    return '${DateFormatter.formatMonthDay(record.refuelDate)} · '
        '${record.mileage.toStringAsFixed(0)}km · '
        '¥${record.totalPrice.toStringAsFixed(2)}';
  }

  Widget _buildEvidenceRow(BuildContext context, String key, dynamic value) {
    final colors = Theme.of(context).colorScheme;
    const labels = {
      'field': '字段',
      'record_value': '账单值',
      'reference_value': '参考值',
      'source': '来源',
      'source_date': '来源日期',
      'province': '省份',
    };
    final text = value == null ? '未提供' : value.toString();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 58,
            child: Text(
              labels[key] ?? key,
              style: TextStyle(fontSize: 10, color: colors.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: colors.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _findingAction({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDisclaimer() {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      child: Text(
        '审查结果仅提示异常，原始账单不会被自动修改。',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 10, color: colors.onSurfaceVariant),
      ),
    );
  }

  // ------------------------------------------------------------------
  // 交互
  // ------------------------------------------------------------------
  List<AuditFinding> _applyFilter(List<AuditFinding> findings) {
    switch (_filter) {
      case 'pending':
        return findings.where((f) => f.isPending).toList();
      case 'critical':
        return findings
            .where(
              (f) =>
                  f.severity == AuditSeverity.critical ||
                  f.severity == AuditSeverity.warning,
            )
            .toList();
      case 'handled':
        return findings.where((f) => !f.isPending).toList();
      default:
        return findings;
    }
  }

  String _typeLabel(String type) {
    const labels = {
      'amount_mismatch': '金额不匹配',
      'mileage_decrease': '里程回退',
      'mileage_duplicate': '里程重复',
      'mileage_jump': '里程跳跃',
      'duplicate_record': '疑似重复',
      'tank_overflow': '超油箱容量',
      'unit_price_difference': '价格差异',
      'consumption_anomaly': '油耗偏离',
      'future_date': '日期异常',
    };
    return labels[type] ?? type;
  }

  Future<void> _runRules({required bool last30DaysOnly}) async {
    HapticFeedback.lightImpact();
    final refuelProv = context.read<RefuelProvider>();
    final vehicleProv = context.read<VehicleProvider>();
    final fuelProv = context.read<FuelPriceProvider>();
    final audit = context.read<AuditProvider>();

    final vehicle = vehicleProv.currentVehicle;
    if (vehicle == null) {
      _showMessage('请先添加或选择一辆爱车');
      return;
    }
    final records = List<RefuelRecordModel>.from(refuelProv.records);
    final province = fuelProv.currentProvince;
    final snapshot = fuelProv.priceSnapshotFor(province);

    await audit.runLocalRulesAudit(
      records: records,
      tankCapacity: vehicle.tankCapacity,
      priceSnapshot: snapshot,
      last30DaysOnly: last30DaysOnly,
    );
  }

  RefuelRecordModel? _recordById(String id, List<RefuelRecordModel> records) {
    for (final r in records) {
      if (r.id == id) return r;
    }
    return null;
  }

  Future<void> _updateStatus(
    AuditFinding finding,
    String status, {
    String? note,
  }) async {
    HapticFeedback.selectionClick();
    await context.read<AuditProvider>().setFindingStatus(
      finding,
      status,
      userNote: note,
    );
  }

  /// 采纳建议：展示原值 → 建议值，确认后更新记录并标记已处理
  Future<void> _adoptSuggestion(AuditFinding finding) async {
    final refuelProv = context.read<RefuelProvider>();
    final record = _recordById(finding.recordId ?? '', refuelProv.records);
    if (record == null) {
      _showMessage('找不到关联的加油记录（可能已删除）');
      return;
    }

    const whitelist = ['total_price', 'unit_price', 'fuel_amount', 'mileage'];
    final changes = finding.suggestedChanges
        .where((c) => whitelist.contains(c['field']))
        .toList();
    if (changes.isEmpty) {
      _showMessage('该建议不包含可自动应用的字段修改');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('采纳修改建议'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('以下字段将被更新（原值 → 建议值）：'),
            const SizedBox(height: 10),
            for (final c in changes)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  '${_fieldLabel(c['field'])}: ${c['current']} → ${c['suggested']}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Text(
              '数据来源：${finding.evidence?['source'] ?? '本地规则'}。修改会立即写入账本。',
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(ctx).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF5A24),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认修改'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    var updated = record;
    for (final c in changes) {
      final value = c['suggested'];
      switch (c['field']) {
        case 'total_price':
          if (value is num && value > 0) {
            updated = updated.copyWith(totalPrice: value.toDouble());
          }
          break;
        case 'unit_price':
          if (value is num && value > 0) {
            updated = updated.copyWith(unitPrice: value.toDouble());
          }
          break;
        case 'fuel_amount':
          if (value is num && value > 0) {
            updated = updated.copyWith(fuelAmount: value.toDouble());
          }
          break;
        case 'mileage':
          if (value is num && value >= 0) {
            updated = updated.copyWith(mileage: value.toDouble());
          }
          break;
      }
    }

    final success = await refuelProv.updateRecord(updated);
    if (!mounted) return;
    if (success) {
      await context.read<AuditProvider>().setFindingStatus(
        finding,
        AuditStatus.resolved,
        userNote: '已采纳修改建议',
      );
      _showMessage('记录已按建议更新');
    } else {
      _showMessage('修改保存失败，请重试');
    }
  }

  String _fieldLabel(String? field) {
    const labels = {
      'total_price': '实付金额',
      'unit_price': '单价',
      'fuel_amount': '加油量',
      'mileage': '里程',
    };
    return labels[field ?? ''] ?? (field ?? '字段');
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
