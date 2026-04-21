import 'package:arcane_voice_models/src/realtime/realtime_message_types.dart';
import 'package:arcane_voice_models/src/realtime/realtime_tool_definition.dart';
import 'package:arcane_voice_models/src/realtime/realtime_turn_detection_config.dart';
import 'package:artifact/artifact.dart';

export 'package:arcane_voice_models/src/realtime/realtime_message_types.dart';

class RealtimeMessageType {
  static const String connectionReady = "connection.ready";
  static const String sessionStart = "session.start";
  static const String sessionStarted = "session.started";
  static const String sessionState = "session.state";
  static const String sessionStop = "session.stop";
  static const String sessionStopped = "session.stopped";
  static const String sessionInterrupt = "session.interrupt";
  static const String textInput = "text.input";
  static const String ping = "ping";
  static const String pong = "pong";
  static const String error = "error";
  static const String inputSpeechStarted = "input.speech_started";
  static const String inputSpeechStopped = "input.speech_stopped";
  static const String transcriptUserDelta = "transcript.user.delta";
  static const String transcriptUserFinal = "transcript.user.final";
  static const String transcriptAssistantDelta = "transcript.assistant.delta";
  static const String transcriptAssistantFinal = "transcript.assistant.final";
  static const String transcriptAssistantDiscard =
      "transcript.assistant.discard";
  static const String assistantOutputCompleted = "assistant.output.completed";
  static const String toolStarted = "tool.started";
  static const String toolCompleted = "tool.completed";
  static const String toolCall = "tool.call";
  static const String toolResult = "tool.result";

  const RealtimeMessageType._();
}

class RealtimeToolExecutionTarget {
  static const String arcaneVoiceProxy = "server";
  static const String arcaneVoiceClient = "client";

  static String displayLabel(String executionTarget) =>
      switch (executionTarget) {
        arcaneVoiceProxy => "Arcane Voice proxy",
        arcaneVoiceClient => "Arcane Voice client",
        _ => executionTarget,
      };

  const RealtimeToolExecutionTarget._();
}

@artifact
class RealtimeSessionStartRequest implements RealtimeClientMessage {
  @override
  final String type;
  final String provider;
  final String model;
  final String voice;
  final String instructions;
  final String initialGreeting;
  final String sessionContextJson;
  final String providerOptionsJson;
  final int inputSampleRate;
  final int outputSampleRate;
  final RealtimeTurnDetectionConfig turnDetection;
  final List<RealtimeToolDefinition> clientTools;

  const RealtimeSessionStartRequest({
    this.type = RealtimeMessageType.sessionStart,
    required this.provider,
    required this.model,
    required this.voice,
    required this.instructions,
    this.initialGreeting = "",
    this.sessionContextJson = "{}",
    this.providerOptionsJson = "{}",
    this.inputSampleRate = 24000,
    this.outputSampleRate = 24000,
    this.turnDetection = const RealtimeTurnDetectionConfig(),
    required this.clientTools,
  });
}

@artifact
class RealtimeSessionStopRequest implements RealtimeClientMessage {
  @override
  final String type;

  const RealtimeSessionStopRequest({
    this.type = RealtimeMessageType.sessionStop,
  });
}

@artifact
class RealtimeSessionInterruptRequest implements RealtimeClientMessage {
  @override
  final String type;

  const RealtimeSessionInterruptRequest({
    this.type = RealtimeMessageType.sessionInterrupt,
  });
}

@artifact
class RealtimeTextInputRequest implements RealtimeClientMessage {
  @override
  final String type;
  final String text;

  const RealtimeTextInputRequest({
    this.type = RealtimeMessageType.textInput,
    required this.text,
  });
}

@artifact
class RealtimePingRequest implements RealtimeClientMessage {
  @override
  final String type;

  const RealtimePingRequest({this.type = RealtimeMessageType.ping});
}

@artifact
class RealtimeToolResultRequest implements RealtimeClientMessage {
  @override
  final String type;
  final String requestId;
  final String outputJson;
  final String? error;

  const RealtimeToolResultRequest({
    this.type = RealtimeMessageType.toolResult,
    required this.requestId,
    required this.outputJson,
    this.error,
  });
}

@artifact
class RealtimeConnectionReadyEvent implements RealtimeServerMessage {
  @override
  final String type;
  final List<String> providers;
  final String defaultModel;
  final String defaultVoice;

  const RealtimeConnectionReadyEvent({
    this.type = RealtimeMessageType.connectionReady,
    required this.providers,
    required this.defaultModel,
    required this.defaultVoice,
  });
}

@artifact
class RealtimeToolCallEvent implements RealtimeServerMessage {
  @override
  final String type;
  final String requestId;
  final String name;
  final String argumentsJson;

  const RealtimeToolCallEvent({
    this.type = RealtimeMessageType.toolCall,
    required this.requestId,
    required this.name,
    required this.argumentsJson,
  });
}

@artifact
class RealtimeSessionStartedEvent implements RealtimeServerMessage {
  @override
  final String type;
  final String provider;
  final String model;
  final String voice;
  final int inputSampleRate;
  final int outputSampleRate;

  const RealtimeSessionStartedEvent({
    this.type = RealtimeMessageType.sessionStarted,
    required this.provider,
    required this.model,
    required this.voice,
    required this.inputSampleRate,
    required this.outputSampleRate,
  });
}

@artifact
class RealtimeSessionStateEvent implements RealtimeServerMessage {
  @override
  final String type;
  final String state;
  final String? provider;

  const RealtimeSessionStateEvent({
    this.type = RealtimeMessageType.sessionState,
    required this.state,
    this.provider,
  });
}

@artifact
class RealtimeSessionStoppedEvent implements RealtimeServerMessage {
  @override
  final String type;

  const RealtimeSessionStoppedEvent({
    this.type = RealtimeMessageType.sessionStopped,
  });
}

@artifact
class RealtimePongEvent implements RealtimeServerMessage {
  @override
  final String type;

  const RealtimePongEvent({this.type = RealtimeMessageType.pong});
}

@artifact
class RealtimeErrorEvent implements RealtimeServerMessage {
  @override
  final String type;
  final String message;
  final String? code;

  const RealtimeErrorEvent({
    this.type = RealtimeMessageType.error,
    required this.message,
    this.code,
  });
}

@artifact
class RealtimeInputSpeechStartedEvent implements RealtimeServerMessage {
  @override
  final String type;

  const RealtimeInputSpeechStartedEvent({
    this.type = RealtimeMessageType.inputSpeechStarted,
  });
}

@artifact
class RealtimeInputSpeechStoppedEvent implements RealtimeServerMessage {
  @override
  final String type;

  const RealtimeInputSpeechStoppedEvent({
    this.type = RealtimeMessageType.inputSpeechStopped,
  });
}

@artifact
class RealtimeTranscriptUserDeltaEvent implements RealtimeServerMessage {
  @override
  final String type;
  final String text;

  const RealtimeTranscriptUserDeltaEvent({
    this.type = RealtimeMessageType.transcriptUserDelta,
    required this.text,
  });
}

@artifact
class RealtimeTranscriptUserFinalEvent implements RealtimeServerMessage {
  @override
  final String type;
  final String text;

  const RealtimeTranscriptUserFinalEvent({
    this.type = RealtimeMessageType.transcriptUserFinal,
    required this.text,
  });
}

@artifact
class RealtimeTranscriptAssistantDeltaEvent implements RealtimeServerMessage {
  @override
  final String type;
  final String text;

  const RealtimeTranscriptAssistantDeltaEvent({
    this.type = RealtimeMessageType.transcriptAssistantDelta,
    required this.text,
  });
}

@artifact
class RealtimeTranscriptAssistantFinalEvent implements RealtimeServerMessage {
  @override
  final String type;
  final String text;

  const RealtimeTranscriptAssistantFinalEvent({
    this.type = RealtimeMessageType.transcriptAssistantFinal,
    required this.text,
  });
}

@artifact
class RealtimeTranscriptAssistantDiscardEvent implements RealtimeServerMessage {
  @override
  final String type;

  const RealtimeTranscriptAssistantDiscardEvent({
    this.type = RealtimeMessageType.transcriptAssistantDiscard,
  });
}

@artifact
class RealtimeAssistantOutputCompletedEvent implements RealtimeServerMessage {
  @override
  final String type;
  final String reason;

  const RealtimeAssistantOutputCompletedEvent({
    this.type = RealtimeMessageType.assistantOutputCompleted,
    this.reason = "completed",
  });
}

@artifact
class RealtimeToolStartedEvent implements RealtimeServerMessage {
  @override
  final String type;
  final String callId;
  final String name;
  final String executionTarget;

  const RealtimeToolStartedEvent({
    this.type = RealtimeMessageType.toolStarted,
    required this.callId,
    required this.name,
    required this.executionTarget,
  });
}

@artifact
class RealtimeToolCompletedEvent implements RealtimeServerMessage {
  @override
  final String type;
  final String callId;
  final String name;
  final String executionTarget;
  final bool success;
  final String? error;

  const RealtimeToolCompletedEvent({
    this.type = RealtimeMessageType.toolCompleted,
    required this.callId,
    required this.name,
    required this.executionTarget,
    this.success = true,
    this.error,
  });
}
