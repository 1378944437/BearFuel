import 'package:flutter_test/flutter_test.dart';

import 'package:bearfuel/data/services/ai_audit_service.dart';

void main() {
  group('OpenAI Responses API 输出解析', () {
    test('优先使用顶层 output_text 字段', () {
      const body = '''
{
  "id": "resp_1",
  "output": [
    {"type": "reasoning", "summary": []},
    {"type": "message", "content": [{"type": "output_text", "text": "来自 output 数组"}]}
  ],
  "output_text": "来自顶层字段"
}
''';
      expect(AiAuditService.parseResponsesOutput(body), '来自顶层字段');
    });

    test('拼接 output 数组中 message 的 output_text 片段', () {
      const body = '''
{
  "id": "resp_2",
  "output": [
    {"type": "reasoning", "summary": []},
    {"type": "message", "content": [
      {"type": "output_text", "text": "{\\"status\\":"},
      {"type": "output_text", "text": " \\"normal\\"}"}
    ]}
  ]
}
''';
      expect(AiAuditService.parseResponsesOutput(body), '{"status": "normal"}');
    });

    test('缺少 output 数组时报 Responses 格式错误', () {
      const body = '{"id": "resp_3", "status": "completed"}';
      expect(
        () => AiAuditService.parseResponsesOutput(body),
        throwsA(
          isA<AiServiceException>().having(
            (e) => e.message,
            'message',
            contains('Responses API'),
          ),
        ),
      );
    });

    test('output 中没有文本时报模型返回为空', () {
      const body = '''
{"id": "resp_4", "output": [{"type": "message", "content": []}]}
''';
      expect(
        () => AiAuditService.parseResponsesOutput(body),
        throwsA(
          isA<AiServiceException>().having(
            (e) => e.message,
            'message',
            '模型返回内容为空',
          ),
        ),
      );
    });

    test('非 JSON 响应抛出格式异常', () {
      expect(
        () => AiAuditService.parseResponsesOutput('not json'),
        throwsFormatException,
      );
    });
  });
}
