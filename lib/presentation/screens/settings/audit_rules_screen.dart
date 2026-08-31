import 'package:bearfuel/core/theme/app_icons.dart';
import 'package:flutter/material.dart';

import '../../../core/utils/input_formatters.dart';
import '../../../data/services/audit_rule_store.dart';
import '../../../domain/ledger_audit_rules.dart';
import '../../widgets/custom_card.dart';
import '../../widgets/swipe_action_card.dart';

/// 账本审查规则库（第一层：规则套件列表）。
///
/// 内置默认规则可编辑、可恢复默认；也可新建多套规则并同时存储，
/// 通过圆点切换激活套件。执行账本审查时按激活套件运行。
class AuditRuleSetsScreen extends StatefulWidget {
  const AuditRuleSetsScreen({super.key});

  @override
  State<AuditRuleSetsScreen> createState() => _AuditRuleSetsScreenState();
}

class _AuditRuleSetsScreenState extends State<AuditRuleSetsScreen> {
  final SwipeActionController _swipeController = SwipeActionController();

  @override
  void initState() {
    super.initState();
    AuditRuleSetStore.ensureLoaded().then((_) {
      if (mounted) setState(() {});
    });
  }

  void _reload() => setState(() {});

  Future<void> _setActive(String id) async {
    await AuditRuleSetStore.setActive(id);
    if (!mounted) return;
    _reload();
  }

  Future<void> _addSet() async {
    await AuditRuleSetStore.ensureLoaded();
    if (!mounted) return;
    final template = AuditRuleSetStore.activeSet;
    final controller = TextEditingController(
      text: '规则套件 ${AuditRuleSetStore.sets.length}',
    );
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('新建规则套件'),
        content: TextField(
          controller: controller,
          autofocus: true,
          inputFormatters: [AppInputFormatters.maxChars(30)],
          decoration: const InputDecoration(
            labelText: '规则名称',
            hintText: '如：宽松规则 / 严格规则',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF5A24),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    final created = AuditRuleSet.copyFrom(
      template,
      id: 'rules_${DateTime.now().microsecondsSinceEpoch}',
      name: name,
    );
    await AuditRuleSetStore.saveSet(created);
    if (!mounted) return;
    _reload();
    await _openEditor(created.id);
  }

  Future<void> _openEditor(String id) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AuditRuleSetEditScreen(setId: id)),
    );
    if (!mounted) return;
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    const accent = Color(0xFFFF5A24);
    final sets = AuditRuleSetStore.sets;
    final activeId = AuditRuleSetStore.activeSet.id;
    return Scaffold(
      appBar: AppBar(
        title: const Text('审查规则库'),
        actions: [
          IconButton(
            icon: const Icon(AppIcons.add, size: 20),
            tooltip: '新建规则套件',
            onPressed: _addSet,
          ),
        ],
      ),
      body: NotificationListener<ScrollStartNotification>(
        onNotification: (_) {
          _swipeController.close();
          return false;
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            Text(
              '审查按激活的规则套件执行。内置「默认规则」可编辑参数、可恢复默认；'
              '也可以模板复制新建多套规则并同时保存，随时切换。',
              style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            for (final set in sets)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                // 账本同款左滑卡片（全局协调器）：左滑调出"编辑 / 删除"操作；
                // 内置默认规则仅可编辑，不显示删除
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: SwipeActionCard(
                    controller: _swipeController,
                    canDelete: !set.isBuiltin,
                    onEdit: () => _openEditor(set.id),
                    onDelete: () => _swipeDelete(set),
                    onTap: () => _openEditor(set.id),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          InkWell(
                            borderRadius: BorderRadius.circular(999),
                            onTap: () => _setActive(set.id),
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: Icon(
                                set.id == activeId
                                    ? AppIcons.check_circle
                                    : AppIcons.circle_outlined,
                                size: 20,
                                color: set.id == activeId
                                    ? accent
                                    : colors.onSurfaceVariant,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        set.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    if (set.isBuiltin) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 1,
                                        ),
                                        decoration: BoxDecoration(
                                          color: colors.onSurfaceVariant
                                              .withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                        ),
                                        child: Text(
                                          '内置',
                                          style: TextStyle(
                                            fontSize: 9,
                                            color: colors.onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '${set.rules.where((r) => r.enabled).length}/${set.rules.length} 条规则启用'
                                  ' · 点按圆点设为使用中，左滑可编辑 / 删除（内置仅编辑）',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            AppIcons.keyboard_arrow_down,
                            size: 18,
                            color: colors.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 左滑删除：确认后删除并回落到默认规则
  Future<void> _swipeDelete(AuditRuleSet set) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('删除规则套件'),
        content: Text('将删除「${set.name}」，删除后审查回落到默认规则。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await AuditRuleSetStore.deleteSet(set.id);
    if (!mounted) return;
    _reload();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已删除「${set.name}」'),
        backgroundColor: Colors.orange,
      ),
    );
  }
}

/// 规则套件编辑页（第二层：单条规则开关与阈值参数）。
class AuditRuleSetEditScreen extends StatefulWidget {
  final String setId;

  const AuditRuleSetEditScreen({super.key, required this.setId});

  @override
  State<AuditRuleSetEditScreen> createState() => _AuditRuleSetEditScreenState();
}

class _AuditRuleSetEditScreenState extends State<AuditRuleSetEditScreen> {
  late AuditRuleSet _set;
  final Map<String, Map<String, TextEditingController>> _paramControllers = {};
  late TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    final stored = AuditRuleSetStore.setById(widget.setId);
    _set = stored ?? AuditRuleSet.builtinDefault();
    _nameController = TextEditingController(text: _set.name);
    _syncControllers();
  }

  void _syncControllers() {
    _paramControllers.clear();
    for (final rule in _set.rules) {
      final specs = auditRuleParamSpecs[rule.type] ?? const [];
      if (specs.isEmpty) continue;
      _paramControllers[rule.type] = {
        for (final spec in specs)
          spec.key: TextEditingController(
            text: rule.param(spec.key).toStringAsFixed(spec.decimals),
          ),
      };
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    for (final map in _paramControllers.values) {
      for (final c in map.values) {
        c.dispose();
      }
    }
    super.dispose();
  }

  Future<void> _toggleRule(String type, bool enabled) async {
    final rule = _set.ruleOf(type);
    if (rule == null) return;
    final index = _set.rules.indexWhere((r) => r.type == type);
    _set.rules[index] = rule.copyWith(enabled: enabled);
    setState(() {});
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    // 收集参数输入
    for (final rule in _set.rules) {
      final controllers = _paramControllers[rule.type];
      if (controllers == null) continue;
      final specs = auditRuleParamSpecs[rule.type] ?? const [];
      final params = <String, double>{...rule.params};
      for (final spec in specs) {
        final value = double.tryParse(controllers[spec.key]!.text.trim());
        if (value == null) continue;
        params[spec.key] = value.clamp(spec.min, spec.max).toDouble();
      }
      final index = _set.rules.indexWhere((r) => r.type == rule.type);
      _set.rules[index] = rule.copyWith(params: params);
    }
    _set.name = _nameController.text.trim().isEmpty
        ? _set.name
        : _nameController.text.trim();
    await AuditRuleSetStore.saveSet(_set);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('规则已保存'), backgroundColor: Colors.green),
    );
    setState(() {});
  }

  Future<void> _restoreDefault() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('恢复默认规则'),
        content: const Text('内置默认规则的所有开关与阈值将恢复为出厂值，当前修改会被覆盖。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('恢复默认'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await AuditRuleSetStore.restoreBuiltin();
    if (!mounted) return;
    final restored = AuditRuleSetStore.setById(AuditRuleSet.builtinId)!;
    setState(() {
      _set = restored;
      _nameController.text = restored.name;
      _syncControllers();
    });
  }

  Future<void> _deleteSet() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('删除规则套件'),
        content: Text('将删除「${_set.name}」，删除后审查回落到默认规则。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final deleted = await AuditRuleSetStore.deleteSet(_set.id);
    if (!mounted) return;
    if (!deleted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('内置默认规则不可删除')));
      return;
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    const accent = Color(0xFFFF5A24);
    return Scaffold(
      appBar: AppBar(
        title: Text(_set.name),
        actions: [
          IconButton(
            icon: const Icon(AppIcons.check, size: 20),
            tooltip: '保存规则',
            onPressed: _save,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Text(
            '每条规则可独立开关并调整阈值参数；保存后下次执行账本审查生效。'
            '修改不会改动账单数据，异常仅提示。',
            style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 14),
          CustomCard(
            margin: EdgeInsets.zero,
            padding: const EdgeInsets.all(16),
            child: TextFormField(
              controller: _nameController,
              inputFormatters: [AppInputFormatters.maxChars(30)],
              decoration: const InputDecoration(
                labelText: '规则名称',
                prefixIcon: Icon(AppIcons.branding_watermark_outlined),
              ),
            ),
          ),
          const SizedBox(height: 12),
          for (final type in AuditRuleType.all)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _buildRuleCard(colors, type),
            ),
          if (_set.isBuiltin)
            CustomCard(
              margin: EdgeInsets.zero,
              padding: const EdgeInsets.all(14),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _restoreDefault,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.orange,
                  ),
                  icon: const Icon(AppIcons.backup_outlined, size: 16),
                  label: const Text('恢复默认规则'),
                ),
              ),
            )
          else
            CustomCard(
              margin: EdgeInsets.zero,
              padding: const EdgeInsets.all(14),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _deleteSet,
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                  icon: const Icon(AppIcons.delete_outline, size: 16),
                  label: const Text('删除该规则套件'),
                ),
              ),
            ),
          const SizedBox(height: 10),
          Center(
            child: ElevatedButton.icon(
              onPressed: _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(AppIcons.check, size: 16),
              label: const Text('保存规则'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRuleCard(ColorScheme colors, String type) {
    final rule = _set.ruleOf(type) ?? AuditRuleConfig.defaultFor(type);
    final controllers = _paramControllers[type];
    final specs = auditRuleParamSpecs[type] ?? const [];
    return CustomCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  AuditRuleType.label(type),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Switch(
                value: rule.enabled,
                activeThumbColor: const Color(0xFFFF5A24),
                onChanged: (v) => _toggleRule(type, v),
              ),
            ],
          ),
          Text(
            AuditRuleType.description(type),
            style: TextStyle(
              fontSize: 11,
              height: 1.4,
              color: colors.onSurfaceVariant,
            ),
          ),
          if (rule.enabled && specs.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                for (var i = 0; i < specs.length; i++) ...[
                  if (i > 0) const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: controllers![specs[i].key],
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [AppInputFormatters.maxChars(12)],
                      decoration: InputDecoration(
                        labelText: specs[i].label,
                        suffixText: specs[i].unit.isEmpty
                            ? null
                            : specs[i].unit,
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}
