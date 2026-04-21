part of 'call_session_controller.dart';

extension CallSessionControllerAudioHandling on CallSessionController {
  void _handleMicrophoneAudio(Uint8List audioBytes) {
    if (muted) return;
    microphoneChunkCount++;
    int rms = Pcm16LevelMeter.computeRms(audioBytes);
    peakMicrophoneRms = peakMicrophoneRms > rms ? peakMicrophoneRms : rms;
    if (rms == 0) {
      silentMicrophoneChunkCount++;
    } else {
      silentMicrophoneChunkCount = 0;
      microphoneSilenceReported = false;
    }
    if (microphoneChunkCount <= 3 ||
        microphoneChunkCount % CallSessionController.audioLogInterval == 0) {
      info(
        "[client] sending microphone chunk #$microphoneChunkCount (${audioBytes.length} bytes, rms=$rms, peak=$peakMicrophoneRms)",
      );
    }
    if (!microphoneSilenceReported &&
        silentMicrophoneChunkCount >= CallSessionController.audioLogInterval) {
      microphoneSilenceReported = true;
      _appendSystemEntry(
        "Microphone stream is silent. Check the macOS input device and microphone permission for this app.",
      );
      warn("[client] microphone stream is all-zero PCM");
    }
    socketClient.sendAudio(audioBytes);
  }
}
