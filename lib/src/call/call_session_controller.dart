import 'dart:convert';
import 'dart:async';

import 'package:arcane_voice/src/call/audio_capture_service.dart';
import 'package:arcane_voice/src/call/audio_playback_service.dart';
import 'package:arcane_voice/src/call/client_tool.dart';
import 'package:arcane_voice/src/call/pcm16_level_meter.dart';
import 'package:arcane_voice/src/call/realtime_socket_client.dart';
import 'package:arcane_voice/src/call/transcript_timeline.dart';
import 'package:arcane_voice_models/arcane_voice_models.dart';
import 'package:fast_log/fast_log.dart';
import 'package:flutter/foundation.dart';

part 'call_session_controller_audio.dart';
part 'call_session_controller_socket.dart';

class CallSessionController extends ChangeNotifier {
  static const String defaultInstructions =
      "You are a helpful assistant in a realtime voice call. Keep replies short, warm, and natural. If you use tools, use only the tools provided for this call.";
  static const int audioLogInterval = 100;

  final RealtimeSocketClient socketClient;
  final AudioCaptureService captureService;
  final AudioPlaybackService playbackService;
  final TranscriptTimeline transcriptTimeline;
  final ClientToolRegistry clientToolRegistry;
  final Stopwatch debugClock = Stopwatch();

  StreamSubscription<RealtimeSocketEvent>? socketSubscription;
  Future<void> socketEventQueue = Future<void>.value();
  bool callActive = false;
  bool connecting = false;
  bool muted = false;
  bool disposed = false;
  int microphoneChunkCount = 0;
  int playbackChunkCount = 0;
  int peakMicrophoneRms = 0;
  int peakPlaybackRms = 0;
  int silentMicrophoneChunkCount = 0;
  bool microphoneSilenceReported = false;
  int userTurnCount = 0;
  int assistantTurnCount = 0;
  int activeAssistantTurn = 0;
  int userSpeechStartedAtMs = -1;
  int userSpeechStoppedAtMs = -1;
  int assistantTurnStartedAtMs = -1;
  int assistantFirstAudioAtMs = -1;
  int assistantAudioChunkCount = 0;
  int assistantTranscriptDeltaCount = 0;
  bool userSpeechActive = false;
  List<String> pendingSystemEntries = <String>[];
  String sessionState = "idle";
  String serverUrl;
  RealtimeProviderDefinition providerOption = RealtimeProviderCatalog.openAi;
  String model = RealtimeProviderCatalog.openAi.defaultModel;
  String voice = RealtimeProviderCatalog.openAi.defaultVoice;
  String providerOptionsJson = "{}";
  String lastError = "";
  RealtimeTurnDetectionConfig turnDetectionConfig =
      const RealtimeTurnDetectionConfig();

  CallSessionController({
    RealtimeSocketClient? socketClient,
    AudioCaptureService? captureService,
    AudioPlaybackService? playbackService,
    TranscriptTimeline? transcriptTimeline,
    ClientToolRegistry? clientToolRegistry,
    String? serverUrl,
  }) : socketClient = socketClient ?? RealtimeSocketClient(),
       captureService = captureService ?? AudioCaptureService(),
       playbackService = playbackService ?? AudioPlaybackService(),
       transcriptTimeline = transcriptTimeline ?? TranscriptTimeline(),
       clientToolRegistry = clientToolRegistry ?? ClientToolRegistry(),
       serverUrl = serverUrl ?? RealtimeServerUrl.defaultUrl;

  bool get canStart => !connecting && !callActive;

  bool get canStop => connecting || callActive;

  String get provider => providerOption.id;

  List<TranscriptEntry> get transcriptEntries => transcriptTimeline.entries;

  List<String> get availableVoices => providerOption.voices;

  String get elevenLabsAgentId {
    try {
      Object? decoded = jsonDecode(providerOptionsJson);
      if (decoded is Map<String, dynamic>) {
        return decoded["agentId"]?.toString() ?? "";
      }
      if (decoded is Map<String, Object?>) {
        return decoded["agentId"]?.toString() ?? "";
      }
    } catch (_) {}
    return "";
  }

  void onPrimaryActionPressed() {
    if (canStart) {
      unawaited(startCall());
      return;
    }

    if (canStop) {
      unawaited(stopCall());
    }
  }

  void onMutePressed() => muted ? unawaited(unmute()) : unawaited(mute());

  void onProviderChanged(RealtimeProviderDefinition provider) {
    if (connecting || callActive || providerOption == provider) return;

    providerOption = provider;
    model = provider.defaultModel;
    voice = provider.defaultVoice;
    info("[client] provider changed to ${provider.id}");
    _safeNotifyListeners();
  }

  void onVoiceChanged(String selectedVoice) {
    if (connecting || callActive || voice == selectedVoice) return;
    if (!availableVoices.contains(selectedVoice)) return;

    voice = selectedVoice;
    info("[client] voice changed to $selectedVoice");
    _safeNotifyListeners();
  }

  void onProviderOptionsJsonChanged(String nextValue) {
    if (connecting || callActive || providerOptionsJson == nextValue) return;

    providerOptionsJson = nextValue;
    info("[client] provider options updated");
    _safeNotifyListeners();
  }

  void onElevenLabsAgentIdChanged(String agentId) {
    String trimmedAgentId = agentId.trim();
    String nextProviderOptionsJson = trimmedAgentId.isEmpty
        ? "{}"
        : jsonEncode(<String, Object?>{"agentId": trimmedAgentId});
    onProviderOptionsJsonChanged(nextProviderOptionsJson);
  }

  Future<void> startCall() async {
    if (!canStart) return;

    info("[client] starting call to $serverUrl");
    _prepareForConnection();

    await socketSubscription?.cancel();
    socketSubscription = socketClient.stream.listen(
      _handleSocketEvent,
      onDone: _handleSocketDone,
      onError: _handleSocketError,
      cancelOnError: false,
    );

    try {
      await socketClient.connect(uri: Uri.parse(serverUrl));
      info("[client] websocket connected");
      socketClient.sendMessage(
        RealtimeSessionStartRequest(
          provider: providerOption.id,
          model: model,
          voice: voice,
          instructions: defaultInstructions,
          providerOptionsJson: providerOptionsJson,
          inputSampleRate: 24000,
          outputSampleRate: 24000,
          turnDetection: turnDetectionConfig,
          clientTools: clientToolRegistry.definitions,
        ),
      );
    } catch (error) {
      await _fail(error.toString());
    }
  }

  Future<void> stopCall() async {
    if (!connecting && !callActive && sessionState == "idle") return;

    info("[client] stopping call");
    _setInactiveState(state: "idle");
    _safeNotifyListeners();

    await captureService.stop();
    await playbackService.reset();
    socketClient.sendMessage(const RealtimeSessionStopRequest());
    await _closeSocket();
  }

  Future<void> mute() async {
    if (!callActive || muted) return;
    info("[client] muting microphone");
    muted = true;
    await captureService.pause();
    _safeNotifyListeners();
  }

  Future<void> unmute() async {
    if (!callActive || !muted) return;
    info("[client] unmuting microphone");
    muted = false;
    await captureService.resume();
    _safeNotifyListeners();
  }

  @override
  void dispose() {
    disposed = true;
    unawaited(captureService.dispose());
    unawaited(playbackService.dispose());
    unawaited(socketClient.dispose());
    unawaited(socketSubscription?.cancel());
    super.dispose();
  }

  void _prepareForConnection() {
    lastError = "";
    connecting = true;
    callActive = false;
    sessionState = "connecting";
    transcriptTimeline.clear();
    pendingSystemEntries = <String>[];
    socketEventQueue = Future<void>.value();
    debugClock
      ..reset()
      ..start();
    _resetTurnDebugState();
    info(
      "[client] turn debug provider=${providerOption.id} model=$model voice=$voice "
      "threshold=${turnDetectionConfig.speechThresholdRms} startMs=${turnDetectionConfig.speechStartMs} "
      "endSilenceMs=${turnDetectionConfig.speechEndSilenceMs} preSpeechMs=${turnDetectionConfig.preSpeechMs} "
      "bargeIn=${turnDetectionConfig.bargeInEnabled}",
    );
    _safeNotifyListeners();
  }

  void _resetAudioTracking() {
    microphoneChunkCount = 0;
    playbackChunkCount = 0;
    peakMicrophoneRms = 0;
    peakPlaybackRms = 0;
    silentMicrophoneChunkCount = 0;
    microphoneSilenceReported = false;
  }

  void _resetTurnDebugState() {
    userTurnCount = 0;
    assistantTurnCount = 0;
    activeAssistantTurn = 0;
    userSpeechStartedAtMs = -1;
    userSpeechStoppedAtMs = -1;
    assistantTurnStartedAtMs = -1;
    assistantFirstAudioAtMs = -1;
    assistantAudioChunkCount = 0;
    assistantTranscriptDeltaCount = 0;
    userSpeechActive = false;
    pendingSystemEntries = <String>[];
  }

  int _debugNowMs() => debugClock.elapsedMilliseconds;

  void _ensureAssistantTurnStarted({required String trigger}) {
    bool flushedSystemEntries = _flushPendingSystemEntries();
    if (activeAssistantTurn != 0) {
      if (flushedSystemEntries) {
        _safeNotifyListeners();
      }
      return;
    }
    assistantTurnCount++;
    activeAssistantTurn = assistantTurnCount;
    assistantTurnStartedAtMs = _debugNowMs();
    assistantFirstAudioAtMs = -1;
    assistantAudioChunkCount = 0;
    assistantTranscriptDeltaCount = 0;
    int thinkLatencyMs = userSpeechStoppedAtMs < 0
        ? -1
        : assistantTurnStartedAtMs - userSpeechStoppedAtMs;
    info(
      "[client] assistant turn #$activeAssistantTurn started via $trigger at ${assistantTurnStartedAtMs}ms "
      "after user stop ${thinkLatencyMs < 0 ? 'n/a' : '${thinkLatencyMs}ms'}",
    );
    if (flushedSystemEntries) {
      _safeNotifyListeners();
    }
  }

  void _finishAssistantTurn({required String reason, String? transcript}) {
    if (activeAssistantTurn == 0) return;
    int finishedAtMs = _debugNowMs();
    int responseDurationMs = assistantTurnStartedAtMs < 0
        ? -1
        : finishedAtMs - assistantTurnStartedAtMs;
    int firstAudioLatencyMs =
        assistantFirstAudioAtMs < 0 || assistantTurnStartedAtMs < 0
        ? -1
        : assistantFirstAudioAtMs - assistantTurnStartedAtMs;
    int transcriptLength = transcript?.length ?? 0;
    info(
      "[client] assistant turn #$activeAssistantTurn finished via $reason at ${finishedAtMs}ms "
      "duration=${responseDurationMs < 0 ? 'n/a' : '${responseDurationMs}ms'} "
      "firstAudio=${firstAudioLatencyMs < 0 ? 'n/a' : '${firstAudioLatencyMs}ms'} "
      "audioChunks=$assistantAudioChunkCount transcriptDeltas=$assistantTranscriptDeltaCount transcriptLength=$transcriptLength",
    );
    activeAssistantTurn = 0;
    assistantTurnStartedAtMs = -1;
    assistantFirstAudioAtMs = -1;
    assistantAudioChunkCount = 0;
    assistantTranscriptDeltaCount = 0;
  }

  void _setInactiveState({required String state}) {
    connecting = false;
    callActive = false;
    muted = false;
    sessionState = state;
  }

  void _appendSystemEntry(String text) {
    info("[client] system note: $text");
    transcriptTimeline.appendSystemEntry(text);
    _safeNotifyListeners();
  }

  void _appendOrQueueSystemEntry(String text) {
    if (activeAssistantTurn != 0) {
      _appendSystemEntry(text);
      return;
    }

    if (transcriptTimeline.hasPendingEntry(TranscriptSpeaker.user)) {
      info("[client] system note queued until user transcript final: $text");
      pendingSystemEntries = <String>[...pendingSystemEntries, text];
      return;
    }

    _appendSystemEntry(text);
  }

  bool _flushPendingSystemEntries() {
    if (pendingSystemEntries.isEmpty) {
      return false;
    }

    List<String> bufferedEntries = pendingSystemEntries;
    pendingSystemEntries = <String>[];
    for (String text in bufferedEntries) {
      info("[client] system note: $text");
      transcriptTimeline.appendSystemEntry(text);
    }
    return true;
  }

  void _safeNotifyListeners() {
    if (disposed) return;
    notifyListeners();
  }
}

class RealtimeServerUrl {
  static const String configuredUrl = String.fromEnvironment(
    "REALTIME_SERVER_URL",
    defaultValue: "ws://127.0.0.1:8080/ws/realtime",
  );

  const RealtimeServerUrl._();

  static String get defaultUrl => configuredUrl;
}
