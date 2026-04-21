import 'package:arcane_voice_proxy/src/provider_transcript_support.dart';
import 'package:test/test.dart';

void main() {
  test('monotonic transcript buffer returns only appended deltas', () {
    MonotonicTranscriptBuffer buffer = MonotonicTranscriptBuffer();

    buffer.startTurn();
    String? firstDelta = buffer.applySnapshot('Hello');
    String? secondDelta = buffer.applySnapshot('Hello there');
    String? duplicateDelta = buffer.applySnapshot('Hello there');

    expect(firstDelta, 'Hello');
    expect(secondDelta, ' there');
    expect(duplicateDelta, isNull);
  });

  test('monotonic transcript buffer finalizes and clears state', () {
    MonotonicTranscriptBuffer buffer = MonotonicTranscriptBuffer();

    buffer.startTurn();
    buffer.applySnapshot('Hello there');
    String? finalized = buffer.finalizeText();
    String? ignored = buffer.applySnapshot('Hello there again');

    expect(finalized, 'Hello there');
    expect(ignored, isNull);
    expect(buffer.hasValue, isFalse);
  });

  test('monotonic transcript buffer discard clears pending text', () {
    MonotonicTranscriptBuffer buffer = MonotonicTranscriptBuffer();

    buffer.startTurn();
    buffer.applySnapshot('Partial response');
    buffer.discard();
    String? finalized = buffer.finalizeText();

    expect(finalized, isNull);
    expect(buffer.hasValue, isFalse);
  });
}
