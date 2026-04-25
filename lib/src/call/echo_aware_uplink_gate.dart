import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

class EchoAwareUplinkDecision {
  final List<Uint8List> audioToSend;
  final bool suppressed;
  final int releasedBufferedChunkCount;
  final int playbackReferenceRms;

  const EchoAwareUplinkDecision({
    required this.audioToSend,
    required this.suppressed,
    required this.releasedBufferedChunkCount,
    required this.playbackReferenceRms,
  });
}

class EchoAwareUplinkGate {
  final int bufferWindowMs;
  final int playbackTailMs;
  final int candidateOpenMs;
  final int gateHoldMs;
  final int minPlaybackRms;
  final int minDominanceDeltaRms;
  final double dominanceRatio;

  final Queue<_BufferedMicrophoneChunk> _bufferedMicrophoneChunks =
      Queue<_BufferedMicrophoneChunk>();

  int _candidateStartedAtMs = -1;
  int _gateOpenUntilMs = -1;
  int _lastPlaybackAtMs = -1;
  int _lastPlaybackRms = 0;
  int _smoothedPlaybackRms = 0;
  bool _gateOpen = false;

  EchoAwareUplinkGate({
    this.bufferWindowMs = 260,
    this.playbackTailMs = 260,
    this.candidateOpenMs = 90,
    this.gateHoldMs = 520,
    this.minPlaybackRms = 160,
    this.minDominanceDeltaRms = 120,
    this.dominanceRatio = 1.35,
  });

  int get playbackReferenceRms =>
      math.max(_lastPlaybackRms, _smoothedPlaybackRms);

  void reset() {
    _bufferedMicrophoneChunks.clear();
    _candidateStartedAtMs = -1;
    _gateOpenUntilMs = -1;
    _lastPlaybackAtMs = -1;
    _lastPlaybackRms = 0;
    _smoothedPlaybackRms = 0;
    _gateOpen = false;
  }

  void notePlaybackChunk({required int rms, required int nowMs}) {
    if (_lastPlaybackAtMs >= 0 && nowMs - _lastPlaybackAtMs > playbackTailMs) {
      _smoothedPlaybackRms = rms;
    } else if (_smoothedPlaybackRms == 0) {
      _smoothedPlaybackRms = rms;
    } else {
      _smoothedPlaybackRms = ((_smoothedPlaybackRms * 3) + rms) ~/ 4;
    }
    _lastPlaybackAtMs = nowMs;
    _lastPlaybackRms = rms;
  }

  EchoAwareUplinkDecision handleMicrophoneChunk({
    required Uint8List audioBytes,
    required int microphoneRms,
    required int nowMs,
  }) {
    if (!_shouldGatePlayback(nowMs)) {
      return _releaseBufferedAndSend(audioBytes: audioBytes);
    }

    int referenceRms = playbackReferenceRms;
    bool dominant = _isDominantMicrophone(
      microphoneRms: microphoneRms,
      playbackRms: referenceRms,
    );

    if (_gateOpen) {
      if (dominant) {
        _gateOpenUntilMs = nowMs + gateHoldMs;
      } else if (nowMs > _gateOpenUntilMs) {
        _gateOpen = false;
      }
    }

    if (!_gateOpen && dominant) {
      if (_candidateStartedAtMs < 0) {
        _candidateStartedAtMs = nowMs;
      }
      if (nowMs - _candidateStartedAtMs >= candidateOpenMs) {
        _gateOpen = true;
        _gateOpenUntilMs = nowMs + gateHoldMs;
      }
    } else if (!dominant) {
      _candidateStartedAtMs = -1;
    }

    if (_gateOpen) {
      _candidateStartedAtMs = -1;
      return _releaseBufferedAndSend(
        audioBytes: audioBytes,
        playbackReferenceRmsOverride: referenceRms,
      );
    }

    _bufferMicrophoneChunk(audioBytes: audioBytes, nowMs: nowMs);
    return EchoAwareUplinkDecision(
      audioToSend: const <Uint8List>[],
      suppressed: true,
      releasedBufferedChunkCount: 0,
      playbackReferenceRms: referenceRms,
    );
  }

  EchoAwareUplinkDecision _releaseBufferedAndSend({
    required Uint8List audioBytes,
    int? playbackReferenceRmsOverride,
  }) {
    List<Uint8List> audioToSend = <Uint8List>[];
    while (_bufferedMicrophoneChunks.isNotEmpty) {
      _BufferedMicrophoneChunk bufferedChunk = _bufferedMicrophoneChunks
          .removeFirst();
      audioToSend.add(bufferedChunk.audioBytes);
    }
    int releasedBufferedChunkCount = audioToSend.length;
    audioToSend.add(audioBytes);
    _candidateStartedAtMs = -1;
    return EchoAwareUplinkDecision(
      audioToSend: audioToSend,
      suppressed: false,
      releasedBufferedChunkCount: releasedBufferedChunkCount,
      playbackReferenceRms:
          playbackReferenceRmsOverride ?? playbackReferenceRms,
    );
  }

  bool _shouldGatePlayback(int nowMs) {
    if (_lastPlaybackAtMs < 0) return false;
    if (nowMs - _lastPlaybackAtMs > playbackTailMs) {
      _gateOpen = false;
      _gateOpenUntilMs = -1;
      return false;
    }
    if (playbackReferenceRms < minPlaybackRms) {
      _gateOpen = false;
      _gateOpenUntilMs = -1;
      return false;
    }
    return true;
  }

  bool _isDominantMicrophone({
    required int microphoneRms,
    required int playbackRms,
  }) {
    if (playbackRms < minPlaybackRms) return true;
    if (microphoneRms <= playbackRms) return false;
    if (microphoneRms - playbackRms < minDominanceDeltaRms) return false;
    return microphoneRms >= (playbackRms * dominanceRatio);
  }

  void _bufferMicrophoneChunk({
    required Uint8List audioBytes,
    required int nowMs,
  }) {
    _bufferedMicrophoneChunks.add(
      _BufferedMicrophoneChunk(
        timestampMs: nowMs,
        audioBytes: Uint8List.fromList(audioBytes),
      ),
    );
    while (_bufferedMicrophoneChunks.isNotEmpty &&
        nowMs - _bufferedMicrophoneChunks.first.timestampMs > bufferWindowMs) {
      _bufferedMicrophoneChunks.removeFirst();
    }
  }
}

class _BufferedMicrophoneChunk {
  final int timestampMs;
  final Uint8List audioBytes;

  const _BufferedMicrophoneChunk({
    required this.timestampMs,
    required this.audioBytes,
  });
}
