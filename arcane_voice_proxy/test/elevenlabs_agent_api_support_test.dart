import 'dart:convert';

import 'package:arcane_voice_models/arcane_voice_models.dart';
import 'package:arcane_voice_proxy/src/elevenlabs_agent_api_support.dart';
import 'package:arcane_voice_proxy/src/server_tool_support.dart';
import 'package:test/test.dart';

void main() {
  test('elevenlabs client tools use parameters schema instead of params', () {
    ProxyToolRegistry registry = ProxyToolRegistry(
      proxyTools: ArcaneVoiceProxyToolRegistry(
        tools: <ArcaneVoiceProxyTool>[
          ArcaneVoiceProxyCallbackTool(
            definition: RealtimeToolDefinition(
              name: 'query_record',
              description: 'Search the active record.',
              parametersJson: jsonEncode(<String, Object?>{
                'type': 'object',
                'properties': <String, Object?>{
                  'queries': <String, Object?>{
                    'type': 'array',
                    'items': <String, Object?>{'type': 'string'},
                    'description': 'One or more focused search queries.',
                  },
                },
                'required': <String>['queries'],
                'additionalProperties': false,
              }),
            ),
            onExecute: (_) async => <String, Object?>{'ok': true},
          ),
        ],
      ),
    );

    Map<String, Object?> toolConfig = registry.elevenLabsClientTools.single;
    expect(toolConfig['type'], 'client');
    expect(toolConfig['name'], 'query_record');
    expect(toolConfig.containsKey('params'), isFalse);

    Map<String, Object?> parameters =
        toolConfig['parameters'] as Map<String, Object?>;
    expect(parameters['type'], 'object');
    expect(parameters['required'], <String>['queries']);
    expect(parameters.containsKey('additionalProperties'), isFalse);

    Map<String, Object?> properties =
        parameters['properties'] as Map<String, Object?>;
    Map<String, Object?> queries =
        properties['queries'] as Map<String, Object?>;
    expect(queries['type'], 'array');
    expect(queries['description'], contains('focused search queries'));
    expect(queries['items'], <String, Object?>{
      'type': 'string',
      'description': 'A single queries value.',
    });
  });

  test(
    'buildElevenLabsConversationConfigUpdate merges required client events and tool ids',
    () {
      Map<String, Object?> updatedConfig =
          buildElevenLabsConversationConfigUpdate(
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
      List<dynamic> clientEvents =
          conversation['client_events'] as List<dynamic>;
      expect(clientEvents, contains('audio'));
      expect(clientEvents, contains('ping'));
      expect(clientEvents, contains('user_transcript'));
      expect(clientEvents, contains('client_tool_call'));

      Map<String, Object?> agent =
          updatedConfig['agent'] as Map<String, Object?>;
      Map<String, Object?> prompt = agent['prompt'] as Map<String, Object?>;
      List<dynamic> toolIds = prompt['tool_ids'] as List<dynamic>;
      expect(toolIds, contains('existing-tool'));
      expect(toolIds, contains('tool-a'));
      expect(toolIds, contains('tool-b'));
    },
  );

  test(
    'formatElevenLabsToolResult stringifies structured outputs for websocket results',
    () {
      expect(formatElevenLabsToolResult('{"value":42}'), '{"value":42}');
      expect(formatElevenLabsToolResult('"yolo42"'), 'yolo42');
      expect(formatElevenLabsToolResult('55'), '55');
    },
  );
}
