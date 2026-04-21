import 'dart:convert';
import 'dart:typed_data';

import 'package:arcane_voice_models/arcane_voice_models.dart';

abstract class RealtimeProviderSession {
  Future<void> start();
  Future<void> sendAudio(Uint8List audioBytes);
  Future<void> sendText(String text);
  Future<void> interrupt();
  Future<void> close();
}

class RealtimeSessionConfig {
  static const int defaultInputSampleRate = 24000;
  static const int defaultOutputSampleRate = 24000;

  final String model;
  final String voice;
  final String instructions;
  final String initialGreeting;
  final String sessionContextJson;
  final String providerOptionsJson;
  final int inputSampleRate;
  final int outputSampleRate;
  final RealtimeTurnDetectionConfig turnDetection;

  const RealtimeSessionConfig({
    required this.model,
    required this.voice,
    required this.instructions,
    required this.initialGreeting,
    required this.sessionContextJson,
    required this.providerOptionsJson,
    required this.inputSampleRate,
    required this.outputSampleRate,
    required this.turnDetection,
  });

  factory RealtimeSessionConfig.fromRequest(
    RealtimeSessionStartRequest request,
  ) => RealtimeSessionConfig(
    model: request.model,
    voice: request.voice,
    instructions: request.instructions,
    initialGreeting: request.initialGreeting,
    sessionContextJson: request.sessionContextJson,
    providerOptionsJson: request.providerOptionsJson,
    inputSampleRate: request.inputSampleRate,
    outputSampleRate: request.outputSampleRate,
    turnDetection: request.turnDetection,
  );

  RealtimeSessionConfig copyWith({
    String? model,
    String? voice,
    String? instructions,
    String? initialGreeting,
    String? sessionContextJson,
    String? providerOptionsJson,
    int? inputSampleRate,
    int? outputSampleRate,
    RealtimeTurnDetectionConfig? turnDetection,
  }) => RealtimeSessionConfig(
    model: model ?? this.model,
    voice: voice ?? this.voice,
    instructions: instructions ?? this.instructions,
    initialGreeting: initialGreeting ?? this.initialGreeting,
    sessionContextJson: sessionContextJson ?? this.sessionContextJson,
    providerOptionsJson: providerOptionsJson ?? this.providerOptionsJson,
    inputSampleRate: inputSampleRate ?? this.inputSampleRate,
    outputSampleRate: outputSampleRate ?? this.outputSampleRate,
    turnDetection: turnDetection ?? this.turnDetection,
  );

  Map<String, Object?> get providerOptions {
    try {
      Object? decoded = jsonDecode(providerOptionsJson);
      if (decoded is Map<String, dynamic>) {
        return decoded.cast<String, Object?>();
      }
      if (decoded is Map<String, Object?>) {
        return decoded;
      }
    } catch (_) {}
    return <String, Object?>{};
  }

  Map<String, Object?> get sessionContext {
    try {
      Object? decoded = jsonDecode(sessionContextJson);
      if (decoded is Map<String, dynamic>) {
        return decoded.cast<String, Object?>();
      }
      if (decoded is Map<String, Object?>) {
        return decoded;
      }
    } catch (_) {}
    return <String, Object?>{};
  }

  String get normalizedInitialGreeting => initialGreeting.trim();

  bool get hasInitialGreeting => normalizedInitialGreeting.isNotEmpty;
}
