import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../core/config/app_config.dart';
import 'ai_audit_config_store.dart';

/// AI 审查结果（已通过结构校验）
class AiReviewResult {
  final String
  status; // normal / info / warning / critical / insufficient_evidence
  final String severity; // info / warning / critical
  final String type;
  final String title;
  final String explanation;
  final String? suggestion;
  final List<Map<String, dynamic>> evidence;
  final List<Map<String, dynamic>> suggestedChanges;
  final String? confidence;
  final bool requiresUserConfirmation;

  const AiReviewResult({
    required this.status,
    required this.severity,
    required this.type,
    required this.title,
    required this.explanation,
    this.suggestion,
    this.evidence = const [],
    this.suggestedChanges = const [],
    this.confidence,
    this.requiresUserConfirmation = true,
  });
}

/// AI 账本审查服务。
///
/// 支持多种兼容接口：OpenAI /chat/completions、Anthropic /v1/messages、
/// Gemini :generateContent，按激活供应商的接口类型自动适配。
///
/// 安全边界：
/// - 只发送异常记录的必要字段与规则结论，不发送完整账本、车牌、API Key。
/// - 不可信文本以分隔符包裹，避免影响 AI 行为。
/// - 返回内容必须为合法 JSON 且通过结构校验，否则整体丢弃。
/// - AI 不覆盖原始账单，修正建议需用户在界面确认后才生效。
class AiAuditService {
  AiAuditService._();

  static const String promptVersion = 'ledger-audit-v1';

  static const String _systemPrompt = '''
你是 BearFuel 的账本审查助手。
只能依据用户消息中给出的数据分析，不得补造不存在的数据。
不得修改原始账单。
不得将推测结果描述为确定事实。
接口数据和用户账单存在差异时，只能提示冲突。
无法判断时必须返回 insufficient_evidence。
必须只返回一个 JSON 对象，不得返回 Markdown 或多余文字。
JSON 字段固定为: status, severity, type, title, explanation, suggestion, evidence, suggested_changes, confidence, requires_user_confirmation。
status 只能是 normal / info / warning / critical / insufficient_evidence。
severity 只能是 info / warning / critical。
suggested_changes 数组元素形如 {"field": "字段名", "current": 原值, "suggested": 建议值}；
金额、油量、里程、日期等业务字段仅在有明确数值依据时才给出建议，否则留空数组。
evidence 数组元素形如 {"field": "字段名", "record_value": 原值, "reference_value": 参考值, "source": "来源"}。''';

  static const String _priceSystemPrompt = '''
你是 BearFuel 的油价数据审查助手。
只能依据输入的接口油价和调价日历分析，不得猜测、补造或修改官方调价金额。
如果调价金额缺失，必须明确返回 insufficient_evidence，并说明缺少什么官方依据。
请只返回 JSON；如果无法返回 JSON，普通文本结论也会被作为证据不足展示。
JSON 可包含字段：status, severity, type, title, explanation, suggestion, evidence, confidence, requires_user_confirmation。
status 只能是 normal / info / warning / critical / insufficient_evidence。
severity 只能是 info / warning / critical。
''';

  // ------------------------------------------------------------------
  // 公共入口
  // ------------------------------------------------------------------

  /// 测试连接：校验 URL 格式、Key、模型与响应可解析性
  static Future<(bool ok, String message)> testConnection({
    String? model,
  }) async {
    final profile = AiAuditConfigStore.activeProfile;
    if (profile == null) return (false, '请先添加 AI 服务配置');
    if (!profile.baseUrl.startsWith('http')) {
      return (false, 'Base URL 需以 http(s):// 开头');
    }
    if (profile.apiKey.isEmpty) {
      return (false, '请填写 API Key');
    }
    final effectiveModel =
        ((model != null && model.isNotEmpty) ? model : profile.activeModel)
            .trim();
    if (effectiveModel.isEmpty) {
      return (false, '请先添加模型名称');
    }
    try {
      final content = await _chat(
        [
          {'role': 'user', 'content': '连接测试，请只回复两个字符：OK'},
        ],
        maxTokens: 16,
        model: effectiveModel,
      );
      if (content.trim().isEmpty) {
        return (false, '连接成功但模型返回内容为空，请确认模型可用');
      }
      return (true, '连接成功（模型: $effectiveModel）');
    } on SocketException {
      return (false, '网络连接失败，请检查 Base URL 与网络');
    } on TimeoutException {
      return (false, '连接超时，请稍后重试');
    } on AiServiceException catch (e) {
      return (false, e.message);
    } catch (e) {
      AppConfig.log('AI 测试连接异常: $e');
      return (false, '连接失败：$e');
    }
  }

  /// 审查单条异常：输入规则发现的结构化上下文，返回校验后的 AI 结论。
  /// 返回 null 表示 AI 不可用或返回非法（本地规则结果不受影响）。
  static Future<AiReviewResult?> reviewFinding({
    required Map<String, dynamic> context,
    String? model,
  }) async {
    final profile = AiAuditConfigStore.activeProfile;
    if (profile == null || !profile.isComplete) return null;
    try {
      final userContent =
          '请审查以下加油记录异常（数据由系统提供，仅供分析）：\n'
          '<<<DATA\n${const JsonEncoder.withIndent('  ').convert(context)}\nDATA>>>\n'
          '按系统提示词要求只返回 JSON。';
      final content = await _chat(
        [
          {'role': 'system', 'content': _systemPrompt},
          {'role': 'user', 'content': userContent},
        ],
        maxTokens: 900,
        model: model,
      );
      return _parseReview(content);
    } on AiServiceException catch (e) {
      AppConfig.log('AI 审查失败: ${e.message}');
      return null;
    } catch (e) {
      AppConfig.log('AI 审查异常: $e');
      return null;
    }
  }

  /// 专用油价审查：使用独立提示词与宽松结果兜底，
  /// 不要求账本异常字段，避免油价分析被误判为无效结果。
  static Future<AiReviewResult?> reviewPriceData({
    required Map<String, dynamic> context,
    String? model,
  }) async {
    final profile = AiAuditConfigStore.activeProfile;
    if (profile == null || !profile.isComplete) return null;
    try {
      final userContent =
          '请审查以下实时油价/调价日历数据：\n'
          '<<<PRICE_DATA\n${const JsonEncoder.withIndent('  ').convert(context)}\nPRICE_DATA>>>\n'
          '严禁猜测缺失金额；请返回 JSON，字段可简化为 status、title、analysis、message、result、suggestion、evidence、confidence。';
      final raw = await _chat(
        [
          {'role': 'system', 'content': _priceSystemPrompt},
          {'role': 'user', 'content': userContent},
        ],
        maxTokens: 900,
        model: model,
      );
      return parsePriceReviewResponse(raw);
    } on AiServiceException catch (e) {
      AppConfig.log('AI 油价审查失败: ${e.message}');
      return null;
    } catch (e) {
      AppConfig.log('AI 油价审查异常: $e');
      return null;
    }
  }

  /// 解析油价审查响应，兼容完整 JSON、简化 JSON、代码围栏和普通文本。
  /// 普通文本不会被丢弃，而是以低置信度的证据不足结果展示。
  static AiReviewResult parsePriceReviewResponse(String raw) {
    final text = raw.trim();
    try {
      final jsonText = _extractJsonObject(text);
      final decoded = jsonDecode(jsonText);
      if (decoded is Map<String, dynamic>) {
        return _parsePriceMap(decoded);
      }
    } catch (_) {
      // 继续走普通文本兜底，避免油价页面只显示“未返回有效结果”。
    }
    return AiReviewResult(
      status: 'insufficient_evidence',
      severity: 'info',
      type: 'price_review',
      title: 'AI 油价审查结果（证据不足）',
      explanation: text.isEmpty ? '模型未返回可展示的油价分析内容。' : text,
      suggestion: '请以接口原始数据和官方调价公告为准；AI 不会补造缺失金额。',
      confidence: 'low',
      requiresUserConfirmation: true,
    );
  }

  static String _extractJsonObject(String raw) {
    var text = raw.trim();
    if (text.startsWith('```')) {
      text = text.replaceFirst(RegExp(r'^```[a-zA-Z]*\\s*'), '');
      final fenceEnd = text.lastIndexOf('```');
      if (fenceEnd >= 0) text = text.substring(0, fenceEnd);
      text = text.trim();
    }
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start < 0 || end <= start) {
      throw const FormatException('AI response has no JSON object');
    }
    return text.substring(start, end + 1);
  }

  static AiReviewResult _parsePriceMap(Map<String, dynamic> decoded) {
    String? textValue(dynamic value) =>
        value is String && value.trim().isNotEmpty ? value.trim() : null;

    final status =
        textValue(decoded['status']) ??
        (decoded['insufficient_evidence'] == true
            ? 'insufficient_evidence'
            : 'info');
    const validStatuses = {
      'normal',
      'info',
      'warning',
      'critical',
      'insufficient_evidence',
    };
    final normalizedStatus = validStatuses.contains(status) ? status : 'info';
    final severityValue = textValue(decoded['severity']);
    const validSeverities = {'info', 'warning', 'critical'};
    final severity = validSeverities.contains(severityValue)
        ? severityValue!
        : normalizedStatus == 'critical'
        ? 'critical'
        : normalizedStatus == 'warning'
        ? 'warning'
        : 'info';
    final explanation =
        textValue(decoded['explanation']) ??
        textValue(decoded['analysis']) ??
        textValue(decoded['message']) ??
        textValue(decoded['result']);
    if (explanation == null) {
      throw const FormatException('AI price response has no analysis text');
    }

    List<Map<String, dynamic>> readMapList(dynamic value) {
      if (value is! List) return const [];
      return value
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }

    return AiReviewResult(
      status: normalizedStatus,
      severity: severity,
      type: textValue(decoded['type']) ?? 'price_review',
      title: textValue(decoded['title']) ?? 'AI 油价审查结果',
      explanation: explanation,
      suggestion:
          textValue(decoded['suggestion']) ??
          textValue(decoded['recommendation']) ??
          (normalizedStatus == 'insufficient_evidence'
              ? '缺少足够的官方调价依据，请以接口原始数据和官方公告为准。'
              : null),
      evidence: readMapList(decoded['evidence']),
      suggestedChanges: const [],
      confidence:
          textValue(decoded['confidence']) ??
          (normalizedStatus == 'insufficient_evidence' ? 'low' : null),
      requiresUserConfirmation: true,
    );
  }

  /// 拉取激活供应商的可用模型列表（按接口类型适配）
  static Future<List<String>> fetchModels() async {
    final profile = AiAuditConfigStore.activeProfile;
    if (profile == null) {
      throw const AiServiceException('请先添加 AI 服务配置');
    }
    if (profile.baseUrl.isEmpty) {
      throw const AiServiceException('请先填写 Base URL');
    }
    if (profile.apiKey.isEmpty) {
      throw const AiServiceException('请先填写 API Key');
    }
    return _fetchModelsFor(profile);
  }

  // ------------------------------------------------------------------
  // 按接口类型分发
  // ------------------------------------------------------------------
  static Future<String> _chat(
    List<Map<String, String>> messages, {
    required int maxTokens,
    String? model,
  }) async {
    final profile = AiAuditConfigStore.activeProfile;
    if (profile == null) {
      throw const AiServiceException('请先添加 AI 服务配置');
    }
    final effectiveModel =
        ((model != null && model.isNotEmpty) ? model : profile.activeModel)
            .trim();
    if (effectiveModel.isEmpty) {
      throw const AiServiceException('请先添加模型名称');
    }
    switch (profile.interfaceType) {
      case AiInterfaceType.anthropic:
        return _chatAnthropic(
          profile,
          messages,
          model: effectiveModel,
          maxTokens: maxTokens,
        );
      case AiInterfaceType.gemini:
        return _chatGemini(
          profile,
          messages,
          model: effectiveModel,
          maxTokens: maxTokens,
        );
      default:
        return _chatOpenai(
          profile,
          messages,
          model: effectiveModel,
          maxTokens: maxTokens,
        );
    }
  }

  static Future<List<String>> _fetchModelsFor(AiProviderProfile profile) {
    switch (profile.interfaceType) {
      case AiInterfaceType.anthropic:
        return _fetchModelsAnthropic(profile);
      case AiInterfaceType.gemini:
        return _fetchModelsGemini(profile);
      default:
        return _fetchModelsOpenai(profile);
    }
  }

  // ------------------------------------------------------------------
  // OpenAI 兼容实现
  // ------------------------------------------------------------------
  static Future<List<String>> _fetchModelsOpenai(
    AiProviderProfile profile,
  ) async {
    final base = _trimBase(profile.baseUrl);
    final responseBody = await _getJson(
      url: '$base/models',
      headers: {HttpHeaders.authorizationHeader: 'Bearer ${profile.apiKey}'},
    );
    final decoded = jsonDecode(responseBody);
    if (decoded is! Map<String, dynamic>) {
      throw const AiServiceException('模型列表响应不是有效的 JSON 对象');
    }
    final data = decoded['data'];
    if (data is! List) {
      throw const AiServiceException('模型列表响应缺少 data 数组');
    }
    final ids =
        data
            .whereType<Map>()
            .map((item) => item['id'])
            .whereType<String>()
            .where((id) => id.trim().isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    if (ids.isEmpty) {
      throw const AiServiceException('服务未返回任何模型');
    }
    return ids;
  }

  static Future<String> _chatOpenai(
    AiProviderProfile profile,
    List<Map<String, String>> messages, {
    required String model,
    required int maxTokens,
  }) async {
    final base = _trimBase(profile.baseUrl);
    final responseBody = await _postJson(
      url: '$base/chat/completions',
      headers: {HttpHeaders.authorizationHeader: 'Bearer ${profile.apiKey}'},
      body: {
        'model': model,
        'messages': messages,
        'temperature': 0,
        'max_tokens': maxTokens,
        'stream': false,
      },
    );
    final decoded = jsonDecode(responseBody);
    if (decoded is! Map<String, dynamic>) {
      throw const AiServiceException('响应不是有效的 JSON 对象');
    }
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) {
      throw const AiServiceException('响应缺少 choices，请确认接口为 OpenAI 兼容格式');
    }
    final first = choices.first;
    if (first is! Map<String, dynamic>) {
      throw const AiServiceException('响应 choices 结构异常');
    }
    final message = first['message'];
    final content = message is Map<String, dynamic> ? message['content'] : null;
    if (content is! String || content.trim().isEmpty) {
      throw const AiServiceException('模型返回内容为空');
    }
    return content;
  }

  // ------------------------------------------------------------------
  // Anthropic 兼容实现
  // ------------------------------------------------------------------
  static Future<List<String>> _fetchModelsAnthropic(
    AiProviderProfile profile,
  ) async {
    final base = _trimBase(profile.baseUrl);
    final responseBody = await _getJson(
      url: '$base/v1/models',
      headers: {'x-api-key': profile.apiKey, 'anthropic-version': '2023-06-01'},
    );
    final decoded = jsonDecode(responseBody);
    if (decoded is! Map<String, dynamic>) {
      throw const AiServiceException('模型列表响应不是有效的 JSON 对象');
    }
    final data = decoded['data'];
    if (data is! List) {
      throw const AiServiceException('模型列表响应缺少 data 数组');
    }
    final ids =
        data
            .whereType<Map>()
            .map((item) => item['id'])
            .whereType<String>()
            .where((id) => id.trim().isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    if (ids.isEmpty) {
      throw const AiServiceException('服务未返回任何模型');
    }
    return ids;
  }

  static Future<String> _chatAnthropic(
    AiProviderProfile profile,
    List<Map<String, String>> messages, {
    required String model,
    required int maxTokens,
  }) async {
    final base = _trimBase(profile.baseUrl);
    final systemText = messages
        .where((m) => m['role'] == 'system')
        .map((m) => m['content'])
        .join('\n');
    final chatMessages = messages
        .where((m) => m['role'] != 'system')
        .map((m) => {'role': m['role'], 'content': m['content']})
        .toList();

    final responseBody = await _postJson(
      url: '$base/v1/messages',
      headers: {'x-api-key': profile.apiKey, 'anthropic-version': '2023-06-01'},
      body: {
        'model': model,
        'max_tokens': maxTokens,
        if (systemText.isNotEmpty) 'system': systemText,
        'messages': chatMessages,
      },
    );
    final decoded = jsonDecode(responseBody);
    if (decoded is! Map<String, dynamic>) {
      throw const AiServiceException('响应不是有效的 JSON 对象');
    }
    final contentBlocks = decoded['content'];
    if (contentBlocks is! List || contentBlocks.isEmpty) {
      throw const AiServiceException('响应缺少 content，请确认接口为 Anthropic 兼容格式');
    }
    final text = contentBlocks
        .whereType<Map>()
        .map((block) => block['text'])
        .whereType<String>()
        .join();
    if (text.trim().isEmpty) {
      throw const AiServiceException('模型返回内容为空');
    }
    return text;
  }

  // ------------------------------------------------------------------
  // Gemini 兼容实现
  // ------------------------------------------------------------------
  static Future<List<String>> _fetchModelsGemini(
    AiProviderProfile profile,
  ) async {
    final base = _trimBase(profile.baseUrl);
    final responseBody = await _getJson(
      url: '$base/v1beta/models',
      headers: {'x-goog-api-key': profile.apiKey},
    );
    final decoded = jsonDecode(responseBody);
    if (decoded is! Map<String, dynamic>) {
      throw const AiServiceException('模型列表响应不是有效的 JSON 对象');
    }
    final modelList = decoded['models'];
    if (modelList is! List) {
      throw const AiServiceException('模型列表响应缺少 models 数组');
    }
    final ids =
        modelList
            .whereType<Map>()
            .map((item) => item['name'])
            .whereType<String>()
            .map(
              (name) => name.startsWith('models/') ? name.substring(7) : name,
            )
            .where((id) => id.trim().isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    if (ids.isEmpty) {
      throw const AiServiceException('服务未返回任何模型');
    }
    return ids;
  }

  static Future<String> _chatGemini(
    AiProviderProfile profile,
    List<Map<String, String>> messages, {
    required String model,
    required int maxTokens,
  }) async {
    final base = _trimBase(profile.baseUrl);
    final systemText = messages
        .where((m) => m['role'] == 'system')
        .map((m) => m['content'])
        .join('\n');
    final contents = messages
        .where((m) => m['role'] != 'system')
        .map(
          (m) => {
            'role': m['role'] == 'assistant' ? 'model' : 'user',
            'parts': [
              {'text': m['content']},
            ],
          },
        )
        .toList();

    final responseBody = await _postJson(
      url: '$base/v1beta/models/$model:generateContent',
      headers: {'x-goog-api-key': profile.apiKey},
      body: {
        'contents': contents,
        if (systemText.isNotEmpty)
          'systemInstruction': {
            'parts': [
              {'text': systemText},
            ],
          },
        'generationConfig': {'temperature': 0, 'maxOutputTokens': maxTokens},
      },
    );
    final decoded = jsonDecode(responseBody);
    if (decoded is! Map<String, dynamic>) {
      throw const AiServiceException('响应不是有效的 JSON 对象');
    }
    final candidates = decoded['candidates'];
    if (candidates is! List || candidates.isEmpty) {
      throw const AiServiceException('响应缺少 candidates，请确认接口为 Gemini 兼容格式');
    }
    final first = candidates.first;
    final content = first is Map<String, dynamic> ? first['content'] : null;
    final parts = content is Map<String, dynamic> ? content['parts'] : null;
    if (parts is! List) {
      throw const AiServiceException('响应 candidates 结构异常');
    }
    final text = parts
        .whereType<Map>()
        .map((part) => part['text'])
        .whereType<String>()
        .join();
    if (text.trim().isEmpty) {
      throw const AiServiceException('模型返回内容为空');
    }
    return text;
  }

  // ------------------------------------------------------------------
  // 结果解析与结构校验
  // ------------------------------------------------------------------
  static AiReviewResult? _parseReview(String raw) {
    var text = raw.trim();
    // 剥离 Markdown 代码围栏
    if (text.startsWith('```')) {
      text = text.replaceFirst(RegExp(r'^```[a-zA-Z]*\s*'), '');
      final fenceEnd = text.lastIndexOf('```');
      if (fenceEnd >= 0) text = text.substring(0, fenceEnd);
      text = text.trim();
    }
    // 截取首个 { 到末个 } 之间的内容，容忍前后说明文字
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start < 0 || end <= start) {
      throw const AiServiceException('AI 返回内容不包含 JSON');
    }
    text = text.substring(start, end + 1);

    final dynamic decoded;
    try {
      decoded = jsonDecode(text);
    } catch (_) {
      throw const AiServiceException('AI 返回的 JSON 无法解析');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const AiServiceException('AI 返回的 JSON 结构不是对象');
    }

    const validStatuses = [
      'normal',
      'info',
      'warning',
      'critical',
      'insufficient_evidence',
    ];
    final status = decoded['status'];
    if (status is! String || !validStatuses.contains(status)) {
      throw const AiServiceException('AI 返回的 status 非法');
    }
    var severity = decoded['severity'];
    severity =
        severity is String && ['info', 'warning', 'critical'].contains(severity)
        ? severity
        : 'info';
    final title = decoded['title'];
    final explanation = decoded['explanation'];
    if (explanation is! String || explanation.trim().isEmpty) {
      throw const AiServiceException('AI 返回缺少 explanation');
    }

    List<Map<String, dynamic>> readMapList(dynamic value) {
      if (value is! List) return const [];
      return value
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }

    return AiReviewResult(
      status: status,
      severity: severity,
      type: decoded['type'] is String ? decoded['type'] as String : 'ai_review',
      title: title is String && title.trim().isNotEmpty
          ? title.trim()
          : 'AI 审查结论',
      explanation: explanation.trim(),
      suggestion: decoded['suggestion'] is String
          ? decoded['suggestion'] as String
          : null,
      evidence: readMapList(decoded['evidence']),
      suggestedChanges: readMapList(decoded['suggested_changes']),
      confidence: decoded['confidence'] is String
          ? decoded['confidence'] as String
          : null,
      requiresUserConfirmation: decoded['requires_user_confirmation'] is! bool
          ? true
          : decoded['requires_user_confirmation'] as bool,
    );
  }
}

class AiServiceException implements Exception {
  final String message;

  const AiServiceException(this.message);

  @override
  String toString() => message;
}

// ---------------------------------------------------------------------------
// 通用 HTTP 辅助（统一错误映射）
// ---------------------------------------------------------------------------

String _trimBase(String base) {
  var b = base.trim();
  while (b.endsWith('/')) {
    b = b.substring(0, b.length - 1);
  }
  return b;
}

Future<String> _getJson({
  required String url,
  required Map<String, String> headers,
}) async {
  HttpClient? client;
  try {
    client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    final request = await client
        .getUrl(Uri.parse(url))
        .timeout(const Duration(seconds: 10));
    headers.forEach(request.headers.set);
    final response = await request.close().timeout(const Duration(seconds: 20));
    final body = await response
        .transform(utf8.decoder)
        .join()
        .timeout(const Duration(seconds: 20));
    _ensureOk(response.statusCode, body);
    return body;
  } on SocketException {
    throw const AiServiceException('网络连接失败，请检查 Base URL 与网络');
  } on TimeoutException {
    throw const AiServiceException('连接超时，请稍后重试');
  } finally {
    client?.close(force: true);
  }
}

Future<String> _postJson({
  required String url,
  required Map<String, String> headers,
  required Map<String, dynamic> body,
}) async {
  HttpClient? client;
  try {
    client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    final request = await client
        .postUrl(Uri.parse(url))
        .timeout(const Duration(seconds: 10));
    request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
    headers.forEach(request.headers.set);
    request.write(jsonEncode(body));
    final response = await request.close().timeout(const Duration(seconds: 30));
    final responseBody = await response
        .transform(utf8.decoder)
        .join()
        .timeout(const Duration(seconds: 30));
    _ensureOk(response.statusCode, responseBody);
    return responseBody;
  } on SocketException {
    throw const AiServiceException('网络连接失败，请检查 Base URL 与网络');
  } on TimeoutException {
    throw const AiServiceException('连接超时，请稍后重试');
  } finally {
    client?.close(force: true);
  }
}

void _ensureOk(int statusCode, String responseBody) {
  if (statusCode == HttpStatus.ok) return;
  switch (statusCode) {
    case HttpStatus.unauthorized:
      throw const AiServiceException('API Key 无效（401）');
    case HttpStatus.forbidden:
      throw const AiServiceException('访问被拒绝（403），请检查 Key 权限');
    case HttpStatus.notFound:
      throw const AiServiceException('接口不存在（404），请检查 Base URL');
    case HttpStatus.tooManyRequests:
      throw const AiServiceException('请求过于频繁或额度不足（429）');
    case HttpStatus.paymentRequired:
      throw const AiServiceException('账户额度不足（402）');
    default:
      throw AiServiceException('服务返回 HTTP $statusCode');
  }
}

// ---------------------------------------------------------------------------
// 通用 HTTP 辅助（统一错误映射）
// ---------------------------------------------------------------------------
