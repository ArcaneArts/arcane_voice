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
  final int inputSampleRate;
  final int outputSampleRate;
  final RealtimeTurnDetectionConfig turnDetection;

  const RealtimeSessionConfig({
    required this.model,
    required this.voice,
    required this.instructions,
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
    inputSampleRate: request.inputSampleRate,
    outputSampleRate: request.outputSampleRate,
    turnDetection: request.turnDetection,
  );

  RealtimeSessionConfig copyWith({
    String? model,
    String? voice,
    String? instructions,
    int? inputSampleRate,
    int? outputSampleRate,
    RealtimeTurnDetectionConfig? turnDetection,
  }) => RealtimeSessionConfig(
    model: model ?? this.model,
    voice: voice ?? this.voice,
    instructions: instructions ?? this.instructions,
    inputSampleRate: inputSampleRate ?? this.inputSampleRate,
    outputSampleRate: outputSampleRate ?? this.outputSampleRate,
    turnDetection: turnDetection ?? this.turnDetection,
  );
}
