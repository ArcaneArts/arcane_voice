import 'dart:convert';

class JsonCodecHelper {
  const JsonCodecHelper._();

  static Map<String, Object?> decodeObject(String source) {
    Object? decoded = jsonDecode(source);
    if (decoded is Map<String, dynamic>) {
      return decoded.cast<String, Object?>();
    }

    if (decoded is Map<String, Object?>) {
      return decoded;
    }

    throw const FormatException("Expected a JSON object.");
  }
}

extension ObjectMapCompaction on Map<String, Object?> {
  Map<String, Object?> get withoutNullValues => <String, Object?>{
    for (MapEntry<String, Object?> entry in entries)
      if (entry.value != null) entry.key: entry.value,
  };
}

extension GeminiSchemaSubset on Map<String, Object?> {
  Map<String, Object?> get geminiSchemaSubset => _sanitizeObjectMap(this);

  Map<String, Object?> _sanitizeObjectMap(Map<String, Object?> source) =>
      <String, Object?>{
        for (MapEntry<String, Object?> entry in source.entries)
          if (!_isUnsupportedGeminiKey(entry.key))
            entry.key: _sanitizeSchemaValue(entry.value),
      };

  Object? _sanitizeSchemaValue(Object? value) => switch (value) {
    Map<String, dynamic> mapValue => _sanitizeObjectMap(
      mapValue.cast<String, Object?>(),
    ),
    List<dynamic> listValue => <Object?>[
      for (Object? item in listValue) _sanitizeSchemaValue(item),
    ],
    _ => value,
  };

  bool _isUnsupportedGeminiKey(String key) => switch (key) {
    "additionalProperties" => true,
    _ => false,
  };
}
