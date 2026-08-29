# -*- coding: utf-8 -*-
path = 'lib/data/services/ai_audit_service.dart'
src = open(path, encoding='utf-8').read()

old = """  static Future<(bool ok, String message)> testConnection() async {
    if (!AiAuditConfigStore.hasBaseUrl) {
      return (false, '请填写 Base URL');
    }
    if (!AiAuditConfigStore.baseUrl.startsWith('http')) {
      return (false, 'Base URL 需以 http(s):// 开头');
    }
    if (!AiAuditConfigStore.hasApiKey) {
      return (false, '请填写 API Key');
    }
    if (!AiAuditConfigStore.hasModel) {
      return (false, '请填写模型名称');
    }
    try {
      final content = await _chat([
        {'role': 'user', 'content': '连接测试，请只回复两个字符：OK'},
      ], maxTokens: 16);
      if (content.trim().isEmpty) {
        return (false, '连接成功但模型返回内容为空，请确认模型可用');
      }
      return (true, '连接成功（模型: ${AiAuditConfigStore.model}）');"""
new = """  static Future<(bool ok, String message)> testConnection({
    String? model,
  }) async {
    if (!AiAuditConfigStore.hasBaseUrl) {
      return (false, '请填写 Base URL');
    }
    if (!AiAuditConfigStore.baseUrl.startsWith('http')) {
      return (false, 'Base URL 需以 http(s):// 开头');
    }
    if (!AiAuditConfigStore.hasApiKey) {
      return (false, '请填写 API Key');
    }
    final effectiveModel = (model ?? AiAuditConfigStore.model).trim();
    if (effectiveModel.isEmpty) {
      return (false, '请先添加模型名称');
    }
    try {
      final content = await _chat([
        {'role': 'user', 'content': '连接测试，请只回复两个字符：OK'},
      ], maxTokens: 16, model: effectiveModel);
      if (content.trim().isEmpty) {
        return (false, '连接成功但模型返回内容为空，请确认模型可用');
      }
      return (true, '连接成功（模型: $effectiveModel）');"""
assert src.count(old) == 1, 'test anchor'
src = src.replace(old, new)

old = """  static Future<AiReviewResult?> reviewFinding({
    required Map<String, dynamic> context,
  }) async {"""
new = """  static Future<AiReviewResult?> reviewFinding({
    required Map<String, dynamic> context,
    String? model,
  }) async {"""
assert src.count(old) == 1, 'review sig anchor'
src = src.replace(old, new)

old = """      final content = await _chat(
        [
          {'role': 'system', 'content': _systemPrompt},
          {'role': 'user', 'content': userContent},
        ],
        maxTokens: 900,
      );"""
new = """      final content = await _chat(
        [
          {'role': 'system', 'content': _systemPrompt},
          {'role': 'user', 'content': userContent},
        ],
        maxTokens: 900,
        model: model,
      );"""
assert src.count(old) == 1, 'review call anchor'
src = src.replace(old, new)

old = """  static Future<String> _chat(
    List<Map<String, String>> messages, {
    required int maxTokens,
  }) async {"""
new = """  static Future<String> _chat(
    List<Map<String, String>> messages, {
    required int maxTokens,
    String? model,
  }) async {
    final effectiveModel = (model ?? AiAuditConfigStore.model).trim();
    if (effectiveModel.isEmpty) {
      throw const AiServiceException('请先添加模型名称');
    }"""
assert src.count(old) == 1, 'chat sig anchor'
src = src.replace(old, new)

old = "        'model': AiAuditConfigStore.model,"
new = "        'model': effectiveModel,"
assert src.count(old) == 1, 'body anchor'
src = src.replace(old, new)

open(path, 'w', encoding='utf-8', newline='\n').write(src)
print('service patch ok')
