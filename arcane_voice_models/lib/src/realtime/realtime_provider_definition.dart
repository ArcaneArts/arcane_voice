import 'package:artifact/artifact.dart';

@artifact
class RealtimeProviderDefinition {
  final String id;
  final String label;
  final String defaultModel;
  final String defaultVoice;
  final List<String> voices;

  const RealtimeProviderDefinition({
    required this.id,
    required this.label,
    required this.defaultModel,
    required this.defaultVoice,
    required this.voices,
  });
}

class RealtimeProviderCatalog {
  static const String openAiId = "openai";
  static const String geminiId = "gemini";
  static const String grokId = "grok";

  static const RealtimeProviderDefinition openAi = RealtimeProviderDefinition(
    id: openAiId,
    label: "OpenAI",
    defaultModel: "gpt-realtime-1.5",
    defaultVoice: "sage",
    voices: <String>[
      "alloy",
      "ash",
      "ballad",
      "coral",
      "echo",
      "sage",
      "shimmer",
      "verse",
      "marin",
      "cedar",
    ],
  );

  static const RealtimeProviderDefinition gemini = RealtimeProviderDefinition(
    id: geminiId,
    label: "Gemini",
    defaultModel: "gemini-3.1-flash-live-preview",
    defaultVoice: "Kore",
    voices: <String>[
      "Zephyr",
      "Puck",
      "Charon",
      "Kore",
      "Fenrir",
      "Leda",
      "Orus",
      "Aoede",
      "Callirrhoe",
      "Autonoe",
      "Enceladus",
      "Iapetus",
      "Umbriel",
      "Algieba",
      "Despina",
      "Erinome",
      "Algenib",
      "Rasalgethi",
      "Laomedeia",
      "Achernar",
      "Alnilam",
      "Schedar",
      "Gacrux",
      "Pulcherrima",
      "Achird",
      "Zubenelgenubi",
      "Vindemiatrix",
      "Sadachbia",
      "Sadaltager",
      "Sulafat",
    ],
  );

  static const RealtimeProviderDefinition grok = RealtimeProviderDefinition(
    id: grokId,
    label: "Grok",
    defaultModel: "voice-agent",
    defaultVoice: "eve",
    voices: <String>["eve", "ara", "rex", "sal", "leo"],
  );

  static const List<RealtimeProviderDefinition> all = <RealtimeProviderDefinition>[
    openAi,
    gemini,
    grok,
  ];

  static const List<String> ids = <String>[openAiId, geminiId, grokId];

  const RealtimeProviderCatalog._();

  static RealtimeProviderDefinition? maybeById(String providerId) =>
      switch (providerId) {
        openAiId => openAi,
        geminiId => gemini,
        grokId => grok,
        _ => null,
      };

  static RealtimeProviderDefinition byId(String providerId) =>
      maybeById(providerId) ?? openAi;

  static String defaultModelFor(String providerId) =>
      byId(providerId).defaultModel;

  static String defaultVoiceFor(String providerId) =>
      byId(providerId).defaultVoice;
}
