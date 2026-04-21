import 'dart:convert';

import 'package:arcane_voice_models/gen/artifacts.gen.dart';
import 'package:arcane_voice_models/src/realtime/realtime_protocol_messages.dart';

class RealtimeProtocolCodec {
  const RealtimeProtocolCodec._();

  static String encodeClientJson(RealtimeClientMessage message) =>
      switch (message) {
        RealtimeSessionStartRequest value => value.to.json,
        RealtimeSessionStopRequest value => value.to.json,
        RealtimeSessionInterruptRequest value => value.to.json,
        RealtimeTextInputRequest value => value.to.json,
        RealtimePingRequest value => value.to.json,
        RealtimeToolResultRequest value => value.to.json,
        _ => throw const FormatException(
          "Unsupported realtime client message.",
        ),
      };

  static String encodeServerJson(RealtimeServerMessage message) =>
      switch (message) {
        RealtimeConnectionReadyEvent value => value.to.json,
        RealtimeSessionStartedEvent value => value.to.json,
        RealtimeSessionStateEvent value => value.to.json,
        RealtimeSessionStoppedEvent value => value.to.json,
        RealtimePongEvent value => value.to.json,
        RealtimeErrorEvent value => value.to.json,
        RealtimeInputSpeechStartedEvent value => value.to.json,
        RealtimeInputSpeechStoppedEvent value => value.to.json,
        RealtimeTranscriptUserDeltaEvent value => value.to.json,
        RealtimeTranscriptUserFinalEvent value => value.to.json,
        RealtimeTranscriptAssistantDeltaEvent value => value.to.json,
        RealtimeTranscriptAssistantFinalEvent value => value.to.json,
        RealtimeTranscriptAssistantDiscardEvent value => value.to.json,
        RealtimeAssistantOutputCompletedEvent value => value.to.json,
        RealtimeToolStartedEvent value => value.to.json,
        RealtimeToolCompletedEvent value => value.to.json,
        RealtimeToolCallEvent value => value.to.json,
        _ => throw const FormatException(
          "Unsupported realtime server message.",
        ),
      };

  static RealtimeClientMessage decodeClientJson(String source) =>
      decodeClientMap(_decodeObject(source));

  static RealtimeClientMessage decodeClientMap(Map<String, Object?> map) {
    String type = map["type"]?.toString() ?? "";
    return switch (type) {
      RealtimeMessageType.sessionStart => $RealtimeSessionStartRequest.fromMap(
        map,
      ),
      RealtimeMessageType.sessionStop => $RealtimeSessionStopRequest.fromMap(
        map,
      ),
      RealtimeMessageType.sessionInterrupt =>
        $RealtimeSessionInterruptRequest.fromMap(map),
      RealtimeMessageType.textInput => $RealtimeTextInputRequest.fromMap(map),
      RealtimeMessageType.ping => $RealtimePingRequest.fromMap(map),
      RealtimeMessageType.toolResult => $RealtimeToolResultRequest.fromMap(map),
      _ => throw FormatException("Unsupported realtime client message: $type"),
    };
  }

  static RealtimeServerMessage decodeServerJson(String source) =>
      decodeServerMap(_decodeObject(source));

  static RealtimeServerMessage decodeServerMap(Map<String, Object?> map) {
    String type = map["type"]?.toString() ?? "";
    return switch (type) {
      RealtimeMessageType.connectionReady =>
        $RealtimeConnectionReadyEvent.fromMap(map),
      RealtimeMessageType.sessionStarted =>
        $RealtimeSessionStartedEvent.fromMap(map),
      RealtimeMessageType.sessionState => $RealtimeSessionStateEvent.fromMap(
        map,
      ),
      RealtimeMessageType.sessionStopped =>
        $RealtimeSessionStoppedEvent.fromMap(map),
      RealtimeMessageType.pong => $RealtimePongEvent.fromMap(map),
      RealtimeMessageType.error => $RealtimeErrorEvent.fromMap(map),
      RealtimeMessageType.inputSpeechStarted =>
        $RealtimeInputSpeechStartedEvent.fromMap(map),
      RealtimeMessageType.inputSpeechStopped =>
        $RealtimeInputSpeechStoppedEvent.fromMap(map),
      RealtimeMessageType.transcriptUserDelta =>
        $RealtimeTranscriptUserDeltaEvent.fromMap(map),
      RealtimeMessageType.transcriptUserFinal =>
        $RealtimeTranscriptUserFinalEvent.fromMap(map),
      RealtimeMessageType.transcriptAssistantDelta =>
        $RealtimeTranscriptAssistantDeltaEvent.fromMap(map),
      RealtimeMessageType.transcriptAssistantFinal =>
        $RealtimeTranscriptAssistantFinalEvent.fromMap(map),
      RealtimeMessageType.transcriptAssistantDiscard =>
        $RealtimeTranscriptAssistantDiscardEvent.fromMap(map),
      RealtimeMessageType.assistantOutputCompleted =>
        $RealtimeAssistantOutputCompletedEvent.fromMap(map),
      RealtimeMessageType.toolStarted => $RealtimeToolStartedEvent.fromMap(map),
      RealtimeMessageType.toolCompleted => $RealtimeToolCompletedEvent.fromMap(
        map,
      ),
      RealtimeMessageType.toolCall => $RealtimeToolCallEvent.fromMap(map),
      _ => throw FormatException("Unsupported realtime server message: $type"),
    };
  }

  static Map<String, Object?> _decodeObject(String source) {
    Object? decoded = jsonDecode(source);
    if (decoded is Map<String, dynamic>) {
      return decoded.cast<String, Object?>();
    }

    if (decoded is Map<String, Object?>) {
      return decoded;
    }

    throw const FormatException("Expected a JSON object.");
  }
}
