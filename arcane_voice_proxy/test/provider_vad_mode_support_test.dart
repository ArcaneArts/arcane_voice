import 'package:arcane_voice_proxy/arcane_voice_proxy.dart';
import 'package:arcane_voice_proxy/src/provider_vad_mode_support.dart';
import 'package:test/test.dart';

void main() {
  test('proxy server defaults to auto VAD mode', () {
    ArcaneVoiceProxyServer server = ArcaneVoiceProxyServer(
      environment: const ArcaneVoiceProxyEnvironment(),
    );

    expect(server.vadMode, ArcaneVoiceProxyVadMode.auto);
    expect(server.gateway.vadMode, ArcaneVoiceProxyVadMode.auto);
  });

  test('passthrough resolved sessions preserve VAD mode overrides', () {
    ArcaneVoiceProxyResolvedSession session =
        ArcaneVoiceProxyResolvedSession.passthrough(
          request: RealtimeSessionStartRequest(
            provider: RealtimeProviderCatalog.openAiId,
            model: RealtimeProviderCatalog.openAi.defaultModel,
            voice: RealtimeProviderCatalog.openAi.defaultVoice,
            instructions: 'Use a calm voice.',
            clientTools: const <RealtimeToolDefinition>[],
          ),
          proxyTools: ArcaneVoiceProxyToolRegistry.empty(),
          vadMode: ArcaneVoiceProxyVadMode.provider,
        );

    expect(session.vadMode, ArcaneVoiceProxyVadMode.provider);
  });

  test('openai compatible turn detection stays manual in local mode', () {
    Map<String, Object?>? turnDetection =
        ProxyVadModeSupport.buildOpenAiCompatibleTurnDetection(
          vadMode: ArcaneVoiceProxyVadMode.local,
          config: const RealtimeTurnDetectionConfig(),
          supportsResponseControls: true,
        );

    expect(turnDetection, isNull);
  });

  test('openai compatible turn detection enables server VAD in auto mode', () {
    Map<String, Object?>? turnDetection =
        ProxyVadModeSupport.buildOpenAiCompatibleTurnDetection(
          vadMode: ArcaneVoiceProxyVadMode.auto,
          config: const RealtimeTurnDetectionConfig(
            speechEndSilenceMs: 650,
            preSpeechMs: 275,
            bargeInEnabled: false,
          ),
          supportsResponseControls: true,
        );

    expect(turnDetection?['type'], 'server_vad');
    expect(turnDetection?['prefix_padding_ms'], 275);
    expect(turnDetection?['silence_duration_ms'], 650);
    expect(turnDetection?['create_response'], isTrue);
    expect(turnDetection?['interrupt_response'], isFalse);
  });

  test('gemini realtime input config flips between local and provider VAD', () {
    Map<String, Object?> localConfig =
        ProxyVadModeSupport.buildGeminiRealtimeInputConfig(
          vadMode: ArcaneVoiceProxyVadMode.local,
          config: const RealtimeTurnDetectionConfig(),
        );
    Map<String, Object?> providerConfig =
        ProxyVadModeSupport.buildGeminiRealtimeInputConfig(
          vadMode: ArcaneVoiceProxyVadMode.provider,
          config: const RealtimeTurnDetectionConfig(
            speechEndSilenceMs: 480,
            preSpeechMs: 180,
            bargeInEnabled: false,
          ),
        );

    expect(
      localConfig,
      <String, Object?>{
        'automaticActivityDetection': <String, Object?>{'disabled': true},
      },
    );
    expect(
      providerConfig['automaticActivityDetection'],
      <String, Object?>{
        'disabled': false,
        'prefixPaddingMs': 180,
        'silenceDurationMs': 480,
      },
    );
    expect(providerConfig['activityHandling'], 'NO_INTERRUPTION');
  });
}
