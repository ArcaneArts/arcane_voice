import 'dart:typed_data';

import 'package:arcane_voice_models/arcane_voice_models.dart';
import 'package:arcane_voice_proxy/src/provider_assistant_output_support.dart';
import 'package:arcane_voice_proxy/src/provider_runtime_support.dart';
import 'package:arcane_voice_proxy/src/realtime_provider_session_support.dart';
import 'package:arcane_voice_proxy/src/server_tool_support.dart';
import 'package:test/test.dart';

void main() {
  test(
    'assistant output lifecycle emits responding completion and ready',
    () async {
      List<RealtimeServerMessage> events = <RealtimeServerMessage>[];
      ProviderSessionRuntime runtime = _buildRuntime(events: events);
      AssistantOutputLifecycle lifecycle = AssistantOutputLifecycle(
        runtime: runtime,
      );

      runtime.startDebugClock();
      await lifecycle.ensureStarted(trigger: 'audio', referenceAtMs: 0);
      lifecycle.recordAudioChunk();
      await lifecycle.completeAndNotify(reason: 'response.done');

      expect(events.length, 3);
      expect(events[0], isA<RealtimeSessionStateEvent>());
      expect((events[0] as RealtimeSessionStateEvent).state, 'responding');
      expect(events[1], isA<RealtimeAssistantOutputCompletedEvent>());
      expect(
        (events[1] as RealtimeAssistantOutputCompletedEvent).reason,
        'response.done',
      );
      expect(events[2], isA<RealtimeSessionStateEvent>());
      expect((events[2] as RealtimeSessionStateEvent).state, 'ready');
    },
  );

  test(
    'assistant output lifecycle ignores completion without visible output',
    () async {
      List<RealtimeServerMessage> events = <RealtimeServerMessage>[];
      ProviderSessionRuntime runtime = _buildRuntime(events: events);
      AssistantOutputLifecycle lifecycle = AssistantOutputLifecycle(
        runtime: runtime,
      );

      await lifecycle.completeAndNotify(reason: 'response.done');

      expect(events, isEmpty);
    },
  );
}

ProviderSessionRuntime _buildRuntime({
  required List<RealtimeServerMessage> events,
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
  toolRegistry: ProxyToolRegistry(serverTools: ServerToolRegistry.empty()),
  onJsonEvent: (RealtimeServerMessage payload) async {
    events.add(payload);
  },
  onAudioChunk: (Uint8List audioBytes) async {},
  onClosed: () async {},
);
