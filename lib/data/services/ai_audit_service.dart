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

/// AI 账本审查服务（OpenAI 兼容 /chat/completions 接口）。
///
/// 安全边界：
/// - 只发送异常记录的必要字段与规则结论，不发送完整账本、车牌、API Key。
/// - 网页/接口/备注等不可信文本在提示词中以分隔符包裹。
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

  static String get _endpoint {
    var base = AiAuditConfigStore.baseUrl.trim();
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    return '$base/chat/completions';
  }

  /// 测试连接：校验 URL 格式、Key、模型与响应可解析性
  static Future<(bool ok, String message)> testConnection({
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
    if (!AiAuditConfigStore.isConfigured) return null;
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

  /// 拉取服务商可用模型列表（OpenAI 兼容 GET /models）
  static Future<List<String>> fetchModels() async {
    if (!AiAuditConfigStore.hasBaseUrl) {
      throw const AiServiceException('请先填写 Base URL');
    }
    if (!AiAuditConfigStore.hasApiKey) {
      throw const AiServiceException('请先填写 API Key');
    }
    var base = AiAuditConfigStore.baseUrl.trim();
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }

    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
      final request = await client
          .getUrl(Uri.parse('$base/models'))
          .timeout(const Duration(seconds: 10));
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer ${AiAuditConfigStore.apiKey}',
      );
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == HttpStatus.unauthorized) {
        throw const AiServiceException('API Key 无效（401）');
      }
      if (response.statusCode == HttpStatus.notFound) {
        throw const AiServiceException('该服务不提供模型列表接口（404），请手动填写模型名称');
      }
      if (response.statusCode == HttpStatus.tooManyRequests) {
        throw const AiServiceException('请求过于频繁（429），请稍后再试');
      }
      if (response.statusCode != HttpStatus.ok) {
        throw AiServiceException('服务返回 HTTP ${response.statusCode}');
      }

      final decoded = jsonDecode(body);
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
    } on AiServiceException {
      rethrow;
    } on SocketException {
      throw const AiServiceException('网络连接失败，请检查 Base URL 与网络');
    } on TimeoutException {
      throw const AiServiceException('连接超时，请稍后重试');
    } catch (e) {
      throw AiServiceException('获取模型列表失败：$e');
    } finally {
      client?.close(force: true);
    }
  }

  // ------------------------------------------------------------------
  // 底层对话调用
  // ------------------------------------------------------------------
  static Future<String> _chat(
    List<Map<String, String>> messages, {
    required int maxTokens,
    String? model,
  }) async {
    final effectiveModel = (model ?? AiAuditConfigStore.model).trim();
    if (effectiveModel.isEmpty) {
      throw const AiServiceException('请先添加模型名称');
    }
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
      final request = await client
          .getUrl(Uri.parse(_endpoint))
          .timeout(const Duration(seconds: 10));
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer ${AiAuditConfigStore.apiKey}',
      );
      final body = jsonEncode({
        'model': effectiveModel,
        'messages': messages,
        'temperature': 0,
        'max_tokens': maxTokens,
        'stream': false,
      });
      request.write(body);
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      final responseBody = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == HttpStatus.unauthorized) {
        throw const AiServiceException('API Key 无效（401）');
      }
      if (response.statusCode == HttpStatus.notFound) {
        throw const AiServiceException('接口或模型不存在（404），请检查 Base URL 与模型名称');
      }
      if (response.statusCode == HttpStatus.tooManyRequests) {
        throw const AiServiceException('请求过于频繁或额度不足（429）');
      }
      if (response.statusCode == HttpStatus.paymentRequired) {
        throw const AiServiceException('账户额度不足（402）');
      }
      if (response.statusCode != HttpStatus.ok) {
        throw AiServiceException('服务返回 HTTP ${response.statusCode}');
      }

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
      final content = message is Map<String, dynamic>
          ? message['content']
          : null;
      if (content is! String || content.trim().isEmpty) {
        throw const AiServiceException('模型返回内容为空');
      }
      return content;
    } finally {
      client?.close(force: true);
    }
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
