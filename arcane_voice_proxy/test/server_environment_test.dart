import 'package:arcane_voice_proxy/arcane_voice_proxy.dart';
import 'package:test/test.dart';

void main() {
  test('ArcaneVoiceProxyEnvironment keeps explicit keys without platform fallbacks', () {
    ArcaneVoiceProxyEnvironment environment = const ArcaneVoiceProxyEnvironment(
      openAiApiKey: 'openai-explicit',
      geminiApiKey: 'gemini-explicit',
    );

    expect(environment.openAiApiKey, 'openai-explicit');
    expect(environment.geminiApiKey, 'gemini-explicit');
    expect(environment.xAiApiKey, isNull);
    expect(environment.elevenLabsApiKey, isNull);
  });

  test(
    'ArcaneVoiceProxyEnvironment.withPlatformFallbacks uses explicit keys and fills missing keys from platform backups',
    () {
      ArcaneVoiceProxyEnvironment environment =
          const ArcaneVoiceProxyEnvironment.withPlatformFallbacks(
        openAiApiKey: 'openai-explicit',
        xAiApiKey: '   ',
        platformEnvironment: <String, String>{
          'OPENAI_API_KEY': 'openai-platform',
          'GEMINI_API_KEY': 'gemini-platform',
          'XAI_API_KEY': 'xai-platform',
          'ELEVENLABS_API_KEY': 'eleven-platform',
        },
      );

      expect(environment.openAiApiKey, 'openai-explicit');
      expect(environment.geminiApiKey, 'gemini-platform');
      expect(environment.xAiApiKey, 'xai-platform');
      expect(environment.elevenLabsApiKey, 'eleven-platform');
    },
  );

  test('ArcaneVoiceProxyEnvironment resolves keys by provider id', () {
    ArcaneVoiceProxyEnvironment environment =
        const ArcaneVoiceProxyEnvironment.withPlatformFallbacks(
          geminiApiKey: 'gemini-explicit',
          platformEnvironment: <String, String>{
            'OPENAI_API_KEY': 'openai-platform',
            'XAI_API_KEY': 'xai-platform',
            'ELEVENLABS_API_KEY': 'eleven-platform',
          },
        );

    expect(
      environment.apiKeyForProvider(RealtimeProviderCatalog.openAiId),
      'openai-platform',
    );
    expect(
      environment.apiKeyForProvider(RealtimeProviderCatalog.geminiId),
      'gemini-explicit',
    );
    expect(
      environment.apiKeyForProvider(RealtimeProviderCatalog.grokId),
      'xai-platform',
    );
    expect(
      environment.apiKeyForProvider(RealtimeProviderCatalog.elevenLabsId),
      'eleven-platform',
    );
  });
}
