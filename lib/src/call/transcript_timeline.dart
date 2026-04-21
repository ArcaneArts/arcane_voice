class TranscriptTimeline {
  List<TranscriptEntry> entries = <TranscriptEntry>[];

  void clear() => entries = <TranscriptEntry>[];

  bool hasPendingEntry(TranscriptSpeaker speaker) =>
      _findMostRecentPendingEntryIndex(speaker) != -1;

  void beginPendingEntry(TranscriptSpeaker speaker) {
    if (_findMostRecentPendingEntryIndex(speaker) != -1) return;

    int insertionIndex = _findInsertionIndexForNewEntry(speaker);
    entries = _insertEntry(
      index: insertionIndex,
      entry: TranscriptEntry(speaker: speaker, text: "", pending: true),
    );
  }

  void applyDelta({required TranscriptSpeaker speaker, required String text}) {
    if (text.isEmpty) return;

    int pendingIndex = _findMostRecentPendingEntryIndex(speaker);
    if (pendingIndex != -1) {
      TranscriptEntry pendingEntry = entries[pendingIndex];
      entries[pendingIndex] = pendingEntry.copyWith(
        text: "${pendingEntry.text}$text",
      );
      return;
    }

    int recentFinalIndex = _findMostRecentFinalEntryIndex(speaker);
    String recentFinalText = recentFinalIndex == -1
        ? ""
        : entries[recentFinalIndex].text;
    if (_isDuplicateTranscriptFragment(
      existingText: recentFinalText,
      incomingText: text,
    )) {
      return;
    }

    int insertionIndex = _findInsertionIndexForNewEntry(speaker);
    entries = _insertEntry(
      index: insertionIndex,
      entry: TranscriptEntry(speaker: speaker, text: text, pending: true),
    );
  }

  void applyFinal({required TranscriptSpeaker speaker, required String text}) {
    String resolvedText = text.trim();
    int pendingIndex = _findMostRecentPendingEntryIndex(speaker);
    int recentFinalIndex = _findMostRecentFinalEntryIndex(speaker);
    String recentFinalText = recentFinalIndex == -1
        ? ""
        : entries[recentFinalIndex].text;

    if (pendingIndex != -1) {
      TranscriptEntry pendingEntry = entries[pendingIndex];
      String candidateText = _resolveFinalizedText(
        pendingText: pendingEntry.text,
        finalizedText: resolvedText,
      );
      if (_isDuplicateTranscriptFragment(
        existingText: recentFinalText,
        incomingText: candidateText,
      )) {
        entries = _removeEntry(index: pendingIndex);
        return;
      }

      entries[pendingIndex] = pendingEntry.copyWith(
        text: candidateText,
        pending: false,
      );
      return;
    }

    if (resolvedText.isEmpty) return;
    if (_isDuplicateTranscriptFragment(
      existingText: recentFinalText,
      incomingText: resolvedText,
    )) {
      return;
    }

    int insertionIndex = _findInsertionIndexForNewEntry(speaker);
    entries = _insertEntry(
      index: insertionIndex,
      entry: TranscriptEntry(
        speaker: speaker,
        text: resolvedText,
        pending: false,
      ),
    );
  }

  void appendSystemEntry(String text) {
    int pendingAssistantIndex = _findMostRecentPendingEntryIndex(
      TranscriptSpeaker.assistant,
    );
    TranscriptEntry systemEntry = TranscriptEntry(
      speaker: TranscriptSpeaker.system,
      text: text,
      pending: false,
    );
    if (pendingAssistantIndex == -1) {
      entries = <TranscriptEntry>[...entries, systemEntry];
      return;
    }

    entries = _insertEntry(index: pendingAssistantIndex, entry: systemEntry);
  }

  void discardPendingTranscript(TranscriptSpeaker speaker) {
    int pendingIndex = _findMostRecentPendingEntryIndex(speaker);
    if (pendingIndex == -1) return;

    entries = _removeEntry(index: pendingIndex);
  }

  int _findMostRecentFinalEntryIndex(TranscriptSpeaker speaker) {
    for (int index = entries.length - 1; index >= 0; index--) {
      TranscriptEntry entry = entries[index];
      if (entry.speaker == speaker && !entry.pending) {
        return index;
      }
    }

    return -1;
  }

  int _findMostRecentPendingEntryIndex(TranscriptSpeaker speaker) {
    for (int index = entries.length - 1; index >= 0; index--) {
      TranscriptEntry entry = entries[index];
      if (entry.speaker == speaker && entry.pending) {
        return index;
      }
    }

    return -1;
  }

  int _findInsertionIndexForNewEntry(TranscriptSpeaker speaker) {
    if (speaker != TranscriptSpeaker.user) return entries.length;

    int pendingAssistantIndex = _findMostRecentPendingEntryIndex(
      TranscriptSpeaker.assistant,
    );
    if (pendingAssistantIndex != -1) return pendingAssistantIndex;

    return entries.length;
  }

  List<TranscriptEntry> _insertEntry({
    required int index,
    required TranscriptEntry entry,
  }) => <TranscriptEntry>[
    for (int i = 0; i < entries.length + 1; i++)
      if (i < index) entries[i] else if (i == index) entry else entries[i - 1],
  ];

  List<TranscriptEntry> _removeEntry({required int index}) => <TranscriptEntry>[
    for (int i = 0; i < entries.length; i++)
      if (i != index) entries[i],
  ];

  bool _isDuplicateTranscriptFragment({
    required String existingText,
    required String incomingText,
  }) {
    String normalizedExistingText = _normalizeTranscriptText(existingText);
    String normalizedIncomingText = _normalizeTranscriptText(incomingText);
    if (normalizedExistingText.isEmpty || normalizedIncomingText.isEmpty) {
      return false;
    }

    if (normalizedExistingText == normalizedIncomingText) {
      return true;
    }

    return normalizedExistingText.endsWith(normalizedIncomingText);
  }

  String _resolveFinalizedText({
    required String pendingText,
    required String finalizedText,
  }) {
    if (finalizedText.isEmpty) return pendingText;
    if (_isDuplicateTranscriptFragment(
      existingText: pendingText,
      incomingText: finalizedText,
    )) {
      return pendingText;
    }

    return finalizedText;
  }

  String _normalizeTranscriptText(String value) => value.trim().toLowerCase();
}

class TranscriptEntry {
  final TranscriptSpeaker speaker;
  final String text;
  final bool pending;

  const TranscriptEntry({
    required this.speaker,
    required this.text,
    required this.pending,
  });

  TranscriptEntry copyWith({String? text, bool? pending}) => TranscriptEntry(
    speaker: speaker,
    text: text ?? this.text,
    pending: pending ?? this.pending,
  );
}

enum TranscriptSpeaker { user, assistant, system }

extension TranscriptSpeakerPresentation on TranscriptSpeaker {
  String get label => switch (this) {
    TranscriptSpeaker.user => "You",
    TranscriptSpeaker.assistant => "Assistant",
    TranscriptSpeaker.system => "System",
  };
}
