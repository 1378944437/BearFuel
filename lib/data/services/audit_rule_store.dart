import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/ledger_audit_rules.dart';

/// 账本审查规则库存储（SharedPreferences JSON）。
///
/// 内置一套默认规则（可编辑、可恢复默认），支持新建多套规则并切换激活。
/// 规则不含敏感信息，普通存储即可。
class AuditRuleSetStore {
  static const String _keySets = 'audit_rule_sets';
  static const String _keyActiveId = 'audit_rule_active_id';

  static List<AuditRuleSet> _sets = [];
  static String _activeId = AuditRuleSet.builtinId;
  static bool _loaded = false;

  static List<AuditRuleSet> get sets => List.unmodifiable(_sets);

  static AuditRuleSet get activeSet {
    for (final s in _sets) {
      if (s.id == _activeId) return s;
    }
    // 未加载或数据异常时兜底为内置默认，避免界面崩溃
    if (_sets.isEmpty) return AuditRuleSet.builtinDefault();
    return _sets.first;
  }

  static AuditRuleSet? setById(String id) {
    for (final s in _sets) {
      if (s.id == id) return s;
    }
    return null;
  }

  static bool get isBuiltinActive => activeSet.id == AuditRuleSet.builtinId;

  /// 确保已从存储加载（幂等）
  static Future<void> ensureLoaded() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_keySets);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          _sets = decoded
              .whereType<Map>()
              .map(
                (item) =>
                    AuditRuleSet.fromJson(Map<String, dynamic>.from(item)),
              )
              .whereType<AuditRuleSet>()
              .toList();
        }
      }
      _activeId = prefs.getString(_keyActiveId) ?? AuditRuleSet.builtinId;
    } catch (_) {
      _sets = [];
      _activeId = AuditRuleSet.builtinId;
    }
    if (_sets.isEmpty) {
      _sets = [AuditRuleSet.builtinDefault()];
      _activeId = AuditRuleSet.builtinId;
    }
    if (setById(_activeId) == null) {
      _activeId = AuditRuleSet.builtinId;
    }
    // 内置规则被删除（异常数据）时重建
    if (setById(AuditRuleSet.builtinId) == null) {
      _sets = [AuditRuleSet.builtinDefault(), ..._sets];
    }
    _loaded = true;
  }

  static Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _keySets,
      jsonEncode(_sets.map((s) => s.toJson()).toList()),
    );
    await prefs.setString(_keyActiveId, _activeId);
  }

  /// 保存（更新）一套规则
  static Future<void> saveSet(AuditRuleSet set) async {
    await ensureLoaded();
    final index = _sets.indexWhere((s) => s.id == set.id);
    if (index >= 0) {
      _sets[index] = set;
    } else {
      _sets = [..._sets, set];
    }
    await _persist();
  }

  /// 删除一套规则；内置默认不可删除；删除激活规则时回落到默认
  static Future<bool> deleteSet(String id) async {
    await ensureLoaded();
    if (id == AuditRuleSet.builtinId) return false;
    _sets = _sets.where((s) => s.id != id).toList();
    if (_activeId == id) {
      _activeId = AuditRuleSet.builtinId;
    }
    await _persist();
    return true;
  }

  /// 切换激活规则套件
  static Future<void> setActive(String id) async {
    await ensureLoaded();
    if (setById(id) == null) return;
    _activeId = id;
    await _persist();
  }

  /// 内置默认规则恢复出厂：丢弃自定义修改
  static Future<void> restoreBuiltin() async {
    await ensureLoaded();
    final restored = AuditRuleSet.builtinDefault();
    final index = _sets.indexWhere((s) => s.id == AuditRuleSet.builtinId);
    if (index >= 0) {
      _sets[index] = restored;
    } else {
      _sets = [restored, ..._sets];
    }
    _activeId = AuditRuleSet.builtinId;
    await _persist();
  }
}
