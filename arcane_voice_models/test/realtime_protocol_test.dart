import 'package:arcane_voice_models/arcane_voice_models.dart';
import 'package:test/test.dart';

void main() {
  test('client message codec round-trips session start requests', () {
    RealtimeSessionStartRequest original = RealtimeSessionStartRequest(
      provider: RealtimeProviderCatalog.geminiId,
      model: RealtimeProviderCatalog.gemini.defaultModel,
      voice: RealtimeProviderCatalog.gemini.defaultVoice,
      instructions: 'Say hello.',
      providerOptionsJson: '{"agentId":"agent_test"}',
      turnDetection: const RealtimeTurnDetectionConfig(
        speechThresholdRms: 120,
        speechStartMs: 250,
        speechEndSilenceMs: 1100,
        preSpeechMs: 400,
        bargeInEnabled: false,
      ),
      clientTools: const <RealtimeToolDefinition>[],
    );

    String encoded = RealtimeProtocolCodec.encodeClientJson(original);
    RealtimeClientMessage decoded = RealtimeProtocolCodec.decodeClientJson(
      encoded,
    );

    expect(decoded, isA<RealtimeSessionStartRequest>());
    expect((decoded as RealtimeSessionStartRequest).provider, original.provider);
    expect(decoded.model, original.model);
    expect(decoded.voice, original.voice);
    expect(decoded.instructions, original.instructions);
    expect(decoded.providerOptionsJson, original.providerOptionsJson);
    expect(
      decoded.turnDetection.speechEndSilenceMs,
      original.turnDetection.speechEndSilenceMs,
    );
    expect(
      decoded.turnDetection.bargeInEnabled,
      original.turnDetection.bargeInEnabled,
    );
  });

  test('server message codec round-trips session started events', () {
    RealtimeSessionStartedEvent original = RealtimeSessionStartedEvent(
      provider: RealtimeProviderCatalog.grokId,
      model: RealtimeProviderCatalog.grok.defaultModel,
      voice: RealtimeProviderCatalog.grok.defaultVoice,
      inputSampleRate: 24000,
      outputSampleRate: 24000,
    );

    String encoded = RealtimeProtocolCodec.encodeServerJson(original);
    RealtimeServerMessage decoded = RealtimeProtocolCodec.decodeServerJson(
      encoded,
    );

    expect(decoded, isA<RealtimeSessionStartedEvent>());
    expect(
      (decoded as RealtimeSessionStartedEvent).provider,
      RealtimeProviderCatalog.grokId,
    );
    expect(decoded.model, RealtimeProviderCatalog.grok.defaultModel);
    expect(decoded.voice, RealtimeProviderCatalog.grok.defaultVoice);
  });

  test('provider catalog defaults stay stable', () {
    expect(
      RealtimeProviderCatalog.ids,
      <String>[
        RealtimeProviderCatalog.openAiId,
        RealtimeProviderCatalog.geminiId,
        RealtimeProviderCatalog.grokId,
        RealtimeProviderCatalog.elevenLabsId,
      ],
    );
    expect(
      RealtimeProviderCatalog.defaultModelFor(RealtimeProviderCatalog.openAiId),
      'gpt-realtime-1.5',
    );
    expect(
      RealtimeProviderCatalog.defaultVoiceFor(RealtimeProviderCatalog.geminiId),
      'Kore',
    );
    expect(
      const RealtimeTurnDetectionConfig().speechEndSilenceMs,
      900,
    );
  });
}
