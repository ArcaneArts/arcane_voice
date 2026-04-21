part of 'call_session_controller.dart';

extension CallSessionControllerSocketHandling on CallSessionController {
  void _handleSocketEvent(RealtimeSocketEvent event) {
    Future<void> currentQueue = socketEventQueue;
    socketEventQueue = _processQueuedSocketEvent(
      currentQueue: currentQueue,
      event: event,
    );
  }

  void _handleSocketDone() {
    unawaited(_handleRemoteClose());
  }

  void _handleSocketError(Object error) {
    unawaited(_fail(error.toString()));
  }

  Future<void> _processQueuedSocketEvent({
    required Future<void> currentQueue,
    required RealtimeSocketEvent event,
  }) async {
    try {
      await currentQueue;
    } catch (_) {}

    await _processSocketEvent(event);
  }

  Future<void> _processSocketEvent(RealtimeSocketEvent event) async {
    if (event is RealtimeAudioEvent) {
      await _processAudioEvent(event);
      return;
    }

    if (event is RealtimeSocketErrorEvent) {
      await _fail(event.message);
      return;
    }

    if (event is RealtimeConnectionClosedEvent) {
      await _handleRemoteClose();
      return;
    }

    if (event is RealtimeJsonEvent) {
      await _handleJsonEvent(event.payload);
    }
  }

  Future<void> _processAudioEvent(RealtimeAudioEvent event) async {
    _ensureAssistantTurnStarted(trigger: "audio");
    playbackChunkCount++;
    assistantAudioChunkCount++;
    int rms = Pcm16LevelMeter.computeRms(event.audioBytes);
    peakPlaybackRms = peakPlaybackRms > rms ? peakPlaybackRms : rms;
    if (assistantFirstAudioAtMs < 0) {
      assistantFirstAudioAtMs = _debugNowMs();
      int latencyMs = assistantTurnStartedAtMs < 0
          ? -1
          : assistantFirstAudioAtMs - assistantTurnStartedAtMs;
      info(
        "[client] assistant turn #$activeAssistantTurn first audio at ${assistantFirstAudioAtMs}ms "
        "latency=${latencyMs < 0 ? 'n/a' : '${latencyMs}ms'}",
      );
    }
    if (playbackChunkCount <= 5 ||
        playbackChunkCount % CallSessionController.audioLogInterval == 0) {
      info(
        "[client] received playback chunk #$playbackChunkCount (${event.audioBytes.length} bytes, rms=$rms, peak=$peakPlaybackRms)",
      );
    }
    await playbackService.addAudio(event.audioBytes);
  }

  Future<void> _handleJsonEvent(RealtimeServerMessage payload) async {
    info("[client] json event ${payload.type}");

    if (payload is RealtimeSessionStartedEvent) {
      await _handleSessionStarted(payload);
      return;
    }

    if (payload is RealtimeSessionStateEvent) {
      if (sessionState != payload.state) {
        info(
          "[client] state ${sessionState.isEmpty ? 'unknown' : sessionState} -> ${payload.state} at ${_debugNowMs()}ms",
        );
      }
      sessionState = payload.state;
      _safeNotifyListeners();
      return;
    }

    if (payload is RealtimeInputSpeechStartedEvent) {
      await _handleSpeechStarted();
      return;
    }

    if (payload is RealtimeInputSpeechStoppedEvent) {
      if (!userSpeechActive) {
        info("[client] duplicate speech stopped ignored at ${_debugNowMs()}ms");
        return;
      }
      userSpeechActive = false;
      int stoppedAtMs = _debugNowMs();
      int durationMs = userSpeechStartedAtMs < 0
          ? -1
          : stoppedAtMs - userSpeechStartedAtMs;
      userSpeechStoppedAtMs = stoppedAtMs;
      info(
        "[client] user turn #$userTurnCount speech stopped at ${stoppedAtMs}ms "
        "duration=${durationMs < 0 ? 'n/a' : '${durationMs}ms'}",
      );
      sessionState = "thinking";
      _safeNotifyListeners();
      return;
    }

    if (payload is RealtimeTranscriptUserDeltaEvent) {
      transcriptTimeline.applyDelta(
        speaker: TranscriptSpeaker.user,
        text: payload.text,
      );
      _safeNotifyListeners();
      return;
    }

    if (payload is RealtimeTranscriptUserFinalEvent) {
      transcriptTimeline.applyFinal(
        speaker: TranscriptSpeaker.user,
        text: payload.text,
      );
      info(
        "[client] user turn #$userTurnCount transcript final length=${payload.text.length}",
      );
      _flushPendingSystemEntries();
      _safeNotifyListeners();
      return;
    }

    if (payload is RealtimeTranscriptAssistantDeltaEvent) {
      _ensureAssistantTurnStarted(trigger: "transcript");
      assistantTranscriptDeltaCount++;
      transcriptTimeline.applyDelta(
        speaker: TranscriptSpeaker.assistant,
        text: payload.text,
      );
      _safeNotifyListeners();
      return;
    }

    if (payload is RealtimeTranscriptAssistantFinalEvent) {
      _ensureAssistantTurnStarted(trigger: "transcript.final");
      transcriptTimeline.applyFinal(
        speaker: TranscriptSpeaker.assistant,
        text: payload.text,
      );
      _safeNotifyListeners();
      return;
    }

    if (payload is RealtimeTranscriptAssistantDiscardEvent) {
      transcriptTimeline.discardPendingTranscript(TranscriptSpeaker.assistant);
      _finishAssistantTurn(reason: "discard");
      _safeNotifyListeners();
      return;
    }

    if (payload is RealtimeAssistantOutputCompletedEvent) {
      String? transcript;
      for (
        int index = transcriptTimeline.entries.length - 1;
        index >= 0;
        index--
      ) {
        TranscriptEntry entry = transcriptTimeline.entries[index];
        if (entry.speaker == TranscriptSpeaker.assistant) {
          transcript = entry.text;
          break;
        }
      }
      _finishAssistantTurn(reason: payload.reason, transcript: transcript);
      _safeNotifyListeners();
      return;
    }

    if (payload is RealtimeToolStartedEvent) {
      _appendOrQueueSystemEntry(
        "Running ${payload.executionTarget} tool ${payload.name}...",
      );
      return;
    }

    if (payload is RealtimeToolCompletedEvent) {
      String status = payload.success ? "Finished" : "Failed";
      String suffix = payload.error == null ? "." : ": ${payload.error}";
      _appendOrQueueSystemEntry(
        "$status ${payload.executionTarget} tool ${payload.name}$suffix",
      );
      return;
    }

    if (payload is RealtimeToolCallEvent) {
      await _handleClientToolCall(payload);
      return;
    }

    if (payload is RealtimeErrorEvent) {
      await _fail(payload.message);
      return;
    }

    if (payload is RealtimeSessionStoppedEvent) {
      await _handleRemoteClose();
    }
  }

  Future<void> _handleSessionStarted(
    RealtimeSessionStartedEvent payload,
  ) async {
    int inputSampleRate = payload.inputSampleRate;
    int outputSampleRate = payload.outputSampleRate;
    info(
      "[client] session started input=$inputSampleRate output=$outputSampleRate provider=${payload.provider} model=${payload.model}",
    );

    await playbackService.ensureInitialized(sampleRate: outputSampleRate);
    await captureService.start(
      sampleRate: inputSampleRate,
      onAudio: _handleMicrophoneAudio,
    );

    connecting = false;
    callActive = true;
    muted = false;
    _resetAudioTracking();
    sessionState = "ready";
    _safeNotifyListeners();
  }

  Future<void> _handleSpeechStarted() async {
    if (userSpeechActive) {
      info("[client] duplicate speech started ignored at ${_debugNowMs()}ms");
      return;
    }
    userSpeechActive = true;
    userTurnCount++;
    userSpeechStartedAtMs = _debugNowMs();
    info(
      "[client] user turn #$userTurnCount speech started at ${userSpeechStartedAtMs}ms",
    );
    transcriptTimeline.beginPendingEntry(TranscriptSpeaker.user);
    if (playbackService.hasActivePlayback) {
      info(
        "[client] user turn #$userTurnCount barged in, resetting active playback",
      );
      await playbackService.reset();
      _finishAssistantTurn(reason: "barge-in");
    }
    sessionState = "listening";
    _safeNotifyListeners();
  }

  Future<void> _handleRemoteClose() async {
    info("[client] remote close at ${_debugNowMs()}ms");
    await captureService.stop();
    await playbackService.reset();
    await _closeSocket();
    _setInactiveState(state: lastError.isEmpty ? "idle" : sessionState);
    _flushPendingSystemEntries();
    _safeNotifyListeners();
  }

  Future<void> _closeSocket() async {
    StreamSubscription<RealtimeSocketEvent>? currentSubscription =
        socketSubscription;
    socketSubscription = null;
    await currentSubscription?.cancel();
    await socketClient.close();
  }

  Future<void> _fail(String message) async {
    warn("[client] call failed: $message");
    _finishAssistantTurn(reason: "error");
    lastError = message;
    _setInactiveState(state: "error");
    await captureService.stop();
    await playbackService.reset();
    await _closeSocket();
    _flushPendingSystemEntries();
    _appendSystemEntry(message);
    _safeNotifyListeners();
  }

  Future<void> _handleClientToolCall(RealtimeToolCallEvent payload) async {
    info(
      "[client] executing client tool ${payload.name} request=${payload.requestId}",
    );
    try {
      String outputJson = await clientToolRegistry.execute(
        name: payload.name,
        argumentsJson: payload.argumentsJson,
      );
      socketClient.sendMessage(
        RealtimeToolResultRequest(
          requestId: payload.requestId,
          outputJson: outputJson,
        ),
      );
    } catch (error) {
      socketClient.sendMessage(
        RealtimeToolResultRequest(
          requestId: payload.requestId,
          outputJson: "null",
          error: error.toString(),
        ),
      );
    }
  }
}
