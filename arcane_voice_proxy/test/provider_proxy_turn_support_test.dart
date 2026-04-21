import 'dart:typed_data';

import 'package:arcane_voice_models/arcane_voice_models.dart';
import 'package:arcane_voice_proxy/src/provider_proxy_turn_support.dart';
import 'package:arcane_voice_proxy/src/provider_runtime_support.dart';
import 'package:arcane_voice_proxy/src/realtime_provider_session_support.dart';
import 'package:arcane_voice_proxy/src/server_tool_support.dart';
import 'package:test/test.dart';

void main() {
  test(
    'proxy turn detector emits one speech start and one speech stop per turn',
    () async {
      List<RealtimeServerMessage> events = <RealtimeServerMessage>[];
      List<Uint8List> appendedAudio = <Uint8List>[];
      List<ProxySpeechStartEvent> started = <ProxySpeechStartEvent>[];
      List<ProxySpeechStopEvent> stopped = <ProxySpeechStopEvent>[];
      ProviderSessionRuntime runtime = _buildRuntime(events: events);
      ProxyTurnDetector detector = ProxyTurnDetector(runtime: runtime);

      runtime.startDebugClock();
      await detector.processAudio(
        audioBytes: _pcmChunk(amplitude: 0),
        onAppendAudio: (Uint8List audioBytes) async {
          appendedAudio.add(audioBytes);
        },
        onSpeechStarted: (ProxySpeechStartEvent event) async {
          started.add(event);
        },
        onSpeechStopped: (ProxySpeechStopEvent event) async {
          stopped.add(event);
        },
      );
      await detector.processAudio(
        audioBytes: _pcmChunk(amplitude: 500),
        onAppendAudio: (Uint8List audioBytes) async {
          appendedAudio.add(audioBytes);
        },
        onSpeechStarted: (ProxySpeechStartEvent event) async {
          started.add(event);
        },
        onSpeechStopped: (ProxySpeechStopEvent event) async {
          stopped.add(event);
        },
      );
      await detector.processAudio(
        audioBytes: _pcmChunk(amplitude: 500),
        onAppendAudio: (Uint8List audioBytes) async {
          appendedAudio.add(audioBytes);
        },
        onSpeechStarted: (ProxySpeechStartEvent event) async {
          started.add(event);
        },
        onSpeechStopped: (ProxySpeechStopEvent event) async {
          stopped.add(event);
        },
      );
      await detector.processAudio(
        audioBytes: _pcmChunk(amplitude: 0),
        onAppendAudio: (Uint8List audioBytes) async {
          appendedAudio.add(audioBytes);
        },
        onSpeechStarted: (ProxySpeechStartEvent event) async {
          started.add(event);
        },
        onSpeechStopped: (ProxySpeechStopEvent event) async {
          stopped.add(event);
        },
      );
      await detector.processAudio(
        audioBytes: _pcmChunk(amplitude: 0),
        onAppendAudio: (Uint8List audioBytes) async {
          appendedAudio.add(audioBytes);
        },
        onSpeechStarted: (ProxySpeechStartEvent event) async {
          started.add(event);
        },
        onSpeechStopped: (ProxySpeechStopEvent event) async {
          stopped.add(event);
        },
      );
      await detector.processAudio(
        audioBytes: _pcmChunk(amplitude: 0),
        onAppendAudio: (Uint8List audioBytes) async {
          appendedAudio.add(audioBytes);
        },
        onSpeechStarted: (ProxySpeechStartEvent event) async {
          started.add(event);
        },
        onSpeechStopped: (ProxySpeechStopEvent event) async {
          stopped.add(event);
        },
      );

      expect(started.length, 1);
      expect(started[0].bufferedChunkCount, 3);
      expect(stopped.length, 1);
      expect(stopped[0].turnNumber, 1);
      expect(events.whereType<RealtimeInputSpeechStartedEvent>().length, 1);
      expect(events.whereType<RealtimeInputSpeechStoppedEvent>().length, 1);
      expect(appendedAudio.length, greaterThanOrEqualTo(3));
    },
  );
}

ProviderSessionRuntime _buildRuntime({
  required List<RealtimeServerMessage> events,
}) => ProviderSessionRuntime(
  providerId: 'test-provider',
  providerLabel: 'test-provider',
  config: RealtimeSessionConfig(
    model: 'test-model',
    voice: 'test-voice',
    instructions: 'test instructions',
    inputSampleRate: 24000,
    outputSampleRate: 24000,
    turnDetection: const RealtimeTurnDetectionConfig(
      speechThresholdRms: 100,
      speechStartMs: 200,
      speechEndSilenceMs: 300,
      preSpeechMs: 300,
      bargeInEnabled: true,
    ),
  ),
  toolRegistry: ProxyToolRegistry(serverTools: ServerToolRegistry.empty()),
  onJsonEvent: (RealtimeServerMessage payload) async {
    events.add(payload);
  },
  onAudioChunk: (Uint8List audioBytes) async {},
  onClosed: () async {},
);

Uint8List _pcmChunk({required int amplitude, int sampleCount = 2400}) {
  ByteData byteData = ByteData(sampleCount * 2);
  for (int index = 0; index < sampleCount; index++) {
    byteData.setInt16(index * 2, amplitude, Endian.little);
  }
  return byteData.buffer.asUint8List();
}
