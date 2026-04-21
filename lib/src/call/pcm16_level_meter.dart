import 'dart:math' as math;
import 'dart:typed_data';

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
