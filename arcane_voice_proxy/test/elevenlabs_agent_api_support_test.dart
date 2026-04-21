import 'package:arcane_voice_proxy/src/elevenlabs_agent_api_support.dart';
import 'package:test/test.dart';

void main() {
  test(
    'buildElevenLabsConversationConfigUpdate merges required client events and tool ids',
    () {
      Map<String, Object?> updatedConfig = buildElevenLabsConversationConfigUpdate(
        conversationConfig: <String, Object?>{
          'conversation': <String, Object?>{
            'client_events': <String>['audio', 'ping'],
          },
          'agent': <String, Object?>{
            'prompt': <String, Object?>{
              'tool_ids': <String>['existing-tool'],
            },
          },
        },
        toolIds: <String>['tool-a', 'tool-b'],
      );

      Map<String, Object?> conversation =
          updatedConfig['conversation'] as Map<String, Object?>;
      List<dynamic> clientEvents = conversation['client_events'] as List<dynamic>;
      expect(clientEvents, contains('audio'));
      expect(clientEvents, contains('ping'));
      expect(clientEvents, contains('user_transcript'));
      expect(clientEvents, contains('client_tool_call'));

      Map<String, Object?> agent = updatedConfig['agent'] as Map<String, Object?>;
      Map<String, Object?> prompt = agent['prompt'] as Map<String, Object?>;
      List<dynamic> toolIds = prompt['tool_ids'] as List<dynamic>;
      expect(toolIds, contains('existing-tool'));
      expect(toolIds, contains('tool-a'));
      expect(toolIds, contains('tool-b'));
    },
  );

  test(
    'formatElevenLabsToolResult preserves objects and stringifies scalar results',
    () {
      expect(
        formatElevenLabsToolResult('{"value":42}'),
        <String, Object?>{'value': 42},
      );
      expect(formatElevenLabsToolResult('"yolo42"'), 'yolo42');
      expect(formatElevenLabsToolResult('55'), '55');
    },
  );
}
