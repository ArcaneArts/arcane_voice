import 'package:artifact/artifact.dart';
import 'package:models/src/realtime/realtime_message_types.dart';
import 'package:models/src/realtime/realtime_turn_detection_config.dart';

export 'package:models/src/realtime/realtime_message_types.dart';

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
  static const String toolStarted = "tool.started";
  static const String toolCompleted = "tool.completed";

  const RealtimeMessageType._();
}

@artifact
class RealtimeSessionStartRequest implements RealtimeClientMessage {
  @override
  final String type;
  final String provider;
  final String model;
  final String voice;
  final String instructions;
  final int inputSampleRate;
  final int outputSampleRate;
  final RealtimeTurnDetectionConfig turnDetection;

  const RealtimeSessionStartRequest({
    this.type = RealtimeMessageType.sessionStart,
    required this.provider,
    required this.model,
    required this.voice,
    required this.instructions,
    this.inputSampleRate = 24000,
    this.outputSampleRate = 24000,
    this.turnDetection = const RealtimeTurnDetectionConfig(),
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
class RealtimeToolStartedEvent implements RealtimeServerMessage {
  @override
  final String type;
  final String name;

  const RealtimeToolStartedEvent({
    this.type = RealtimeMessageType.toolStarted,
    required this.name,
  });
}

@artifact
class RealtimeToolCompletedEvent implements RealtimeServerMessage {
  @override
  final String type;
  final String name;

  const RealtimeToolCompletedEvent({
    this.type = RealtimeMessageType.toolCompleted,
    required this.name,
  });
}
