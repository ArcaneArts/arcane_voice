class MonotonicTranscriptBuffer {
  String value = "";
  bool finalized = false;

  void startTurn() {
    value = "";
    finalized = false;
  }

  String? applySnapshot(String nextValue) {
    if (finalized || nextValue.isEmpty || nextValue == value) {
      return null;
    }

    String delta = nextValue.startsWith(value)
        ? nextValue.substring(value.length)
        : nextValue;
    value = nextValue;
    return delta;
  }

  String? finalizeText() {
    finalized = true;
    if (value.isEmpty) {
      value = "";
      return null;
    }

    String resolvedValue = value;
    value = "";
    return resolvedValue;
  }

  void discard() {
    value = "";
    finalized = true;
  }

  bool get hasValue => value.isNotEmpty;

  int get length => value.length;
}
