import 'dart:typed_data';

import 'package:arcane_voice/src/call/echo_aware_uplink_gate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('passes microphone audio through when playback is not recent', () {
    EchoAwareUplinkGate gate = EchoAwareUplinkGate();

    EchoAwareUplinkDecision decision = gate.handleMicrophoneChunk(
      audioBytes: _chunk(1),
      microphoneRms: 420,
      nowMs: 100,
    );

    expect(decision.suppressed, isFalse);
    expect(_chunkIds(decision.audioToSend), <int>[1]);
  });

  test('suppresses microphone audio while playback dominates', () {
    EchoAwareUplinkGate gate = EchoAwareUplinkGate(
      candidateOpenMs: 80,
      playbackTailMs: 200,
      minPlaybackRms: 100,
      minDominanceDeltaRms: 80,
      dominanceRatio: 1.3,
    );

    gate.notePlaybackChunk(rms: 500, nowMs: 0);

    EchoAwareUplinkDecision decision = gate.handleMicrophoneChunk(
      audioBytes: _chunk(1),
      microphoneRms: 560,
      nowMs: 40,
    );

    expect(decision.suppressed, isTrue);
    expect(decision.audioToSend, isEmpty);
  });

  test(
    'releases buffered audio once user speech clearly dominates playback',
    () {
      EchoAwareUplinkGate gate = EchoAwareUplinkGate(
        candidateOpenMs: 80,
        playbackTailMs: 200,
        minPlaybackRms: 100,
        minDominanceDeltaRms: 80,
        dominanceRatio: 1.2,
      );

      gate.notePlaybackChunk(rms: 500, nowMs: 0);

      EchoAwareUplinkDecision firstDecision = gate.handleMicrophoneChunk(
        audioBytes: _chunk(1),
        microphoneRms: 760,
        nowMs: 40,
      );
      EchoAwareUplinkDecision secondDecision = gate.handleMicrophoneChunk(
        audioBytes: _chunk(2),
        microphoneRms: 780,
        nowMs: 140,
      );

      expect(firstDecision.suppressed, isTrue);
      expect(secondDecision.suppressed, isFalse);
      expect(secondDecision.releasedBufferedChunkCount, 1);
      expect(_chunkIds(secondDecision.audioToSend), <int>[1, 2]);
    },
  );

  test('flushes buffered chunks after playback reference goes stale', () {
    EchoAwareUplinkGate gate = EchoAwareUplinkGate(
      candidateOpenMs: 80,
      playbackTailMs: 120,
      minPlaybackRms: 100,
      minDominanceDeltaRms: 80,
      dominanceRatio: 1.2,
    );

    gate.notePlaybackChunk(rms: 500, nowMs: 0);

    EchoAwareUplinkDecision suppressedDecision = gate.handleMicrophoneChunk(
      audioBytes: _chunk(1),
      microphoneRms: 560,
      nowMs: 40,
    );
    EchoAwareUplinkDecision releasedDecision = gate.handleMicrophoneChunk(
      audioBytes: _chunk(2),
      microphoneRms: 560,
      nowMs: 220,
    );

    expect(suppressedDecision.suppressed, isTrue);
    expect(releasedDecision.suppressed, isFalse);
    expect(releasedDecision.releasedBufferedChunkCount, 1);
    expect(_chunkIds(releasedDecision.audioToSend), <int>[1, 2]);
  });
}

Uint8List _chunk(int id) => Uint8List.fromList(<int>[id, 0, 0, 0]);

List<int> _chunkIds(List<Uint8List> chunks) =>
    chunks.map((Uint8List chunk) => chunk.first).toList();
