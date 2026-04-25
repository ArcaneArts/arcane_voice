import 'package:arcane_voice_models/arcane_voice_models.dart';
import 'package:arcane_voice_proxy/src/proxy_session_support.dart';

class ProxyVadModeSupport {
  const ProxyVadModeSupport._();

  static bool usesProviderVad(ArcaneVoiceProxyVadMode vadMode) =>
      vadMode != ArcaneVoiceProxyVadMode.local;

  static Map<String, Object?>? buildOpenAiCompatibleTurnDetection({
    required ArcaneVoiceProxyVadMode vadMode,
    required RealtimeTurnDetectionConfig config,
    required bool supportsResponseControls,
  }) {
    if (!usesProviderVad(vadMode)) {
      return null;
    }

    return <String, Object?>{
      "type": "server_vad",
      "prefix_padding_ms": config.preSpeechMs,
      "silence_duration_ms": config.speechEndSilenceMs,
      if (supportsResponseControls) "create_response": true,
      if (supportsResponseControls)
        "interrupt_response": config.bargeInEnabled,
    };
  }

  static Map<String, Object?> buildGeminiRealtimeInputConfig({
    required ArcaneVoiceProxyVadMode vadMode,
    required RealtimeTurnDetectionConfig config,
  }) {
    if (!usesProviderVad(vadMode)) {
      return <String, Object?>{
        "automaticActivityDetection": <String, Object?>{"disabled": true},
      };
    }

    return <String, Object?>{
      "automaticActivityDetection": <String, Object?>{
        "disabled": false,
        "prefixPaddingMs": config.preSpeechMs,
        "silenceDurationMs": config.speechEndSilenceMs,
      },
      if (!config.bargeInEnabled) "activityHandling": "NO_INTERRUPTION",
    };
  }
}
