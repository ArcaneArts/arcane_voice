import 'package:arcane_voice/arcane_voice.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test("delta and final collapse into one finalized entry", () {
    TranscriptTimeline timeline = TranscriptTimeline();

    timeline.applyDelta(speaker: TranscriptSpeaker.user, text: "Hey, ");
    timeline.applyDelta(
      speaker: TranscriptSpeaker.user,
      text: "how's it going?",
    );
    timeline.applyFinal(
      speaker: TranscriptSpeaker.user,
      text: "Hey, how's it going?",
    );

    expect(timeline.entries, hasLength(1));
    expect(timeline.entries.first.text, "Hey, how's it going?");
    expect(timeline.entries.first.pending, isFalse);
  });

  test("late duplicate final is ignored", () {
    TranscriptTimeline timeline = TranscriptTimeline();

    timeline.applyFinal(
      speaker: TranscriptSpeaker.assistant,
      text:
          "Hey there! I'm doing pretty well. Thanks for asking! How about you? Everything alright?",
    );
    timeline.applyFinal(speaker: TranscriptSpeaker.assistant, text: "alright?");

    expect(timeline.entries, hasLength(1));
    expect(
      timeline.entries.first.text,
      "Hey there! I'm doing pretty well. Thanks for asking! How about you? Everything alright?",
    );
  });

  test("out-of-order user final updates earlier pending user entry", () {
    TranscriptTimeline timeline = TranscriptTimeline();

    timeline.beginPendingEntry(TranscriptSpeaker.user);
    timeline.applyDelta(
      speaker: TranscriptSpeaker.assistant,
      text: "Hey there! I'm doing pretty well. ",
    );
    timeline.applyDelta(
      speaker: TranscriptSpeaker.user,
      text: "Hey, how's it going?",
    );
    timeline.applyFinal(
      speaker: TranscriptSpeaker.user,
      text: "Hey, how's it going?",
    );
    timeline.applyFinal(
      speaker: TranscriptSpeaker.assistant,
      text: "Hey there! I'm doing pretty well. How about you?",
    );

    expect(timeline.entries, hasLength(2));
    expect(timeline.entries[0].speaker, TranscriptSpeaker.user);
    expect(timeline.entries[0].text, "Hey, how's it going?");
    expect(timeline.entries[0].pending, isFalse);
    expect(timeline.entries[1].speaker, TranscriptSpeaker.assistant);
    expect(
      timeline.entries[1].text,
      "Hey there! I'm doing pretty well. How about you?",
    );
    expect(timeline.entries[1].pending, isFalse);
  });

  test("late assistant suffix delta after final is ignored", () {
    TranscriptTimeline timeline = TranscriptTimeline();

    timeline.beginPendingEntry(TranscriptSpeaker.user);
    timeline.applyDelta(
      speaker: TranscriptSpeaker.assistant,
      text: "Hey there! I'm doing pretty well, thanks for asking. ",
    );
    timeline.applyDelta(
      speaker: TranscriptSpeaker.user,
      text: "Hey, how's it going?",
    );
    timeline.applyFinal(
      speaker: TranscriptSpeaker.user,
      text: "Hey, how's it going?",
    );
    timeline.applyFinal(
      speaker: TranscriptSpeaker.assistant,
      text:
          "Hey there! I'm doing pretty well, thanks for asking. How about you? What's going on?",
    );
    timeline.applyDelta(speaker: TranscriptSpeaker.assistant, text: "on?");

    expect(timeline.entries, hasLength(2));
    expect(timeline.entries[0].speaker, TranscriptSpeaker.user);
    expect(timeline.entries[0].text, "Hey, how's it going?");
    expect(timeline.entries[1].speaker, TranscriptSpeaker.assistant);
    expect(
      timeline.entries[1].text,
      "Hey there! I'm doing pretty well, thanks for asking. How about you? What's going on?",
    );
    expect(timeline.entries[1].pending, isFalse);
  });

  test("assistant suffix final preserves longer pending transcript", () {
    TranscriptTimeline timeline = TranscriptTimeline();

    timeline.applyDelta(
      speaker: TranscriptSpeaker.assistant,
      text: "Hey there! What's going on?",
    );
    timeline.applyFinal(speaker: TranscriptSpeaker.assistant, text: "on?");

    expect(timeline.entries, hasLength(1));
    expect(timeline.entries.first.speaker, TranscriptSpeaker.assistant);
    expect(timeline.entries.first.text, "Hey there! What's going on?");
    expect(timeline.entries.first.pending, isFalse);
  });

  test("discard removes pending assistant entry", () {
    TranscriptTimeline timeline = TranscriptTimeline();

    timeline.applyDelta(
      speaker: TranscriptSpeaker.assistant,
      text: "Actually whisper, ",
    );
    timeline.discardPendingTranscript(TranscriptSpeaker.assistant);

    expect(timeline.entries, isEmpty);
  });

  test("system entry inserts before pending assistant entry", () {
    TranscriptTimeline timeline = TranscriptTimeline();

    timeline.applyFinal(
      speaker: TranscriptSpeaker.user,
      text: "What's the secret code?",
    );
    timeline.applyDelta(
      speaker: TranscriptSpeaker.assistant,
      text: "The secret code is yolo42.",
    );
    timeline.appendSystemEntry("Running client tool secretCode...");

    expect(timeline.entries, hasLength(3));
    expect(timeline.entries[0].speaker, TranscriptSpeaker.user);
    expect(timeline.entries[1].speaker, TranscriptSpeaker.system);
    expect(timeline.entries[1].text, "Running client tool secretCode...");
    expect(timeline.entries[2].speaker, TranscriptSpeaker.assistant);
    expect(timeline.entries[2].pending, isTrue);
  });
}
