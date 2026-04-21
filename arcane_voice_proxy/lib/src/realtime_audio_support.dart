import 'dart:math' as math;
import 'dart:typed_data';

class BufferedAudioChunk {
  final Uint8List audioBytes;
  final int durationMs;

  const BufferedAudioChunk({
    required this.audioBytes,
    required this.durationMs,
  });
}

class Pcm16ChunkTiming {
  const Pcm16ChunkTiming._();

  static int chunkDurationMs({
    required Uint8List audioBytes,
    required int sampleRate,
  }) {
    if (sampleRate <= 0 || audioBytes.isEmpty) return 1;
    int sampleCount = audioBytes.length ~/ 2;
    if (sampleCount <= 0) return 1;
    return math.max(1, (sampleCount * 1000 / sampleRate).round());
  }
}

class Pcm16LevelMeter {
  const Pcm16LevelMeter._();

  static int computeRms(Uint8List audioBytes) {
    if (audioBytes.length < 2) return 0;

    ByteData byteData = ByteData.sublistView(audioBytes);
    int sampleCount = audioBytes.length ~/ 2;
    double sumSquares = 0;

    for (int i = 0; i < sampleCount; i++) {
      int sample = byteData.getInt16(i * 2, Endian.little);
      sumSquares += sample * sample;
    }

    return math.sqrt(sumSquares / sampleCount).round();
  }
}
