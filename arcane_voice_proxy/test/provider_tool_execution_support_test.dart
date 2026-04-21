import 'dart:typed_data';

import 'package:arcane_voice_models/arcane_voice_models.dart';
import 'package:arcane_voice_proxy/src/provider_runtime_support.dart';
import 'package:arcane_voice_proxy/src/provider_tool_execution_support.dart';
import 'package:arcane_voice_proxy/src/realtime_provider_session_support.dart';
import 'package:arcane_voice_proxy/src/server_tool_support.dart';
import 'package:test/test.dart';

void main() {
  test(
    'tool execution bridge emits start and completion for server tools',
    () async {
      List<RealtimeServerMessage> events = <RealtimeServerMessage>[];
      ProxyToolRegistry toolRegistry = ProxyToolRegistry(
        serverTools: ServerToolRegistry(
          tools: <ServerTool>[
            CallbackServerTool.jsonSchema(
              name: 'randomNumber',
              description: 'Return a test number.',
              parameters: <String, Object?>{
                'type': 'object',
                'properties': <String, Object?>{},
                'required': <String>[],
              },
              onExecute: (Map<String, Object?> arguments) async => 42,
            ),
          ],
        ),
      );
      ProviderSessionRuntime runtime = _buildRuntime(
        events: events,
        toolRegistry: toolRegistry,
      );
      ProviderToolExecutionBridge bridge = ProviderToolExecutionBridge(
        runtime: runtime,
      );
      ToolExecutionInvocation invocation = bridge.createInvocation(
        callId: 'call-1',
        name: 'randomNumber',
      );

      ToolExecutionResult output = await invocation.executeJson(
        rawArguments: '{}',
      );
      await invocation.emitCompleted(output);

      expect(output.success, isTrue);
      expect(output.outputJson, '42');
      expect(events.length, 2);
      expect(events[0], isA<RealtimeToolStartedEvent>());
      expect((events[0] as RealtimeToolStartedEvent).executionTarget, 'server');
      expect(events[1], isA<RealtimeToolCompletedEvent>());
      expect((events[1] as RealtimeToolCompletedEvent).success, isTrue);
    },
  );

  test(
    'tool execution bridge reports client tools as client execution target',
    () async {
      List<RealtimeServerMessage> events = <RealtimeServerMessage>[];
      ProxyToolRegistry toolRegistry = ProxyToolRegistry(
        clientTools: <RealtimeToolDefinition>[
          const RealtimeToolDefinition(
            name: 'secretCode',
            description: 'Return the secret code.',
            parametersJson: '{"type":"object","properties":{},"required":[]}',
          ),
        ],
        clientToolInvoker:
            ({
              required String requestId,
              required String name,
              required String rawArguments,
            }) async => '"yolo42"',
      );
      ProviderSessionRuntime runtime = _buildRuntime(
        events: events,
        toolRegistry: toolRegistry,
      );
      ProviderToolExecutionBridge bridge = ProviderToolExecutionBridge(
        runtime: runtime,
      );
      ToolExecutionInvocation invocation = bridge.createInvocation(
        callId: 'call-2',
        name: 'secretCode',
      );

      ToolExecutionResult output = await invocation.executeJson(
        rawArguments: '{}',
      );
      await invocation.emitCompleted(output);

      expect(output.success, isTrue);
      expect(output.outputJson, '"yolo42"');
      expect((events[0] as RealtimeToolStartedEvent).executionTarget, 'client');
      expect(
        (events[1] as RealtimeToolCompletedEvent).executionTarget,
        'client',
      );
    },
  );

  test(
    'tool execution bridge reports failures through completion event',
    () async {
      List<RealtimeServerMessage> events = <RealtimeServerMessage>[];
      ProxyToolRegistry toolRegistry = ProxyToolRegistry(
        serverTools: ServerToolRegistry(
          tools: <ServerTool>[
            CallbackServerTool.jsonSchema(
              name: 'explode',
              description: 'Throw an error.',
              parameters: <String, Object?>{
                'type': 'object',
                'properties': <String, Object?>{},
                'required': <String>[],
              },
              onExecute: (Map<String, Object?> arguments) async {
                throw StateError('boom');
              },
            ),
          ],
        ),
      );
      ProviderSessionRuntime runtime = _buildRuntime(
        events: events,
        toolRegistry: toolRegistry,
      );
      ProviderToolExecutionBridge bridge = ProviderToolExecutionBridge(
        runtime: runtime,
      );
      ToolExecutionInvocation invocation = bridge.createInvocation(
        callId: 'call-3',
        name: 'explode',
      );

      ToolExecutionResult output = await invocation.executeJson(
        rawArguments: '{}',
      );
      await invocation.emitCompleted(output);

      expect(output.success, isFalse);
      expect(output.error, contains('boom'));
      expect((events[1] as RealtimeToolCompletedEvent).success, isFalse);
    },
  );
}

ProviderSessionRuntime _buildRuntime({
  required List<RealtimeServerMessage> events,
  required ProxyToolRegistry toolRegistry,
}) => ProviderSessionRuntime(
  providerId: 'test-provider',
  providerLabel: 'test-provider',
  config: const RealtimeSessionConfig(
    model: 'test-model',
    voice: 'test-voice',
    instructions: 'test instructions',
    providerOptionsJson: '{}',
    inputSampleRate: 24000,
    outputSampleRate: 24000,
    turnDetection: RealtimeTurnDetectionConfig(),
  ),
  toolRegistry: toolRegistry,
  onJsonEvent: (RealtimeServerMessage payload) async {
    events.add(payload);
  },
  onAudioChunk: (Uint8List audioBytes) async {},
  onClosed: () async {},
);
