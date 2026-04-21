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

extension ElevenLabsSchemaSubset on Map<String, Object?> {
  Map<String, Object?> get elevenLabsSchemaSubset =>
      _sanitizeSchemaNode(
        this,
        path: const <String>[],
        inheritedDescription: null,
      ) ??
      <String, Object?>{"type": "object", "properties": <String, Object?>{}};

  Map<String, Object?>? _sanitizeSchemaNode(
    Map<String, Object?> source, {
    required List<String> path,
    required String? inheritedDescription,
  }) {
    String type = source["type"]?.toString() ?? "";
    return switch (type) {
      "object" => _sanitizeObjectSchema(
        source,
        path: path,
        inheritedDescription: inheritedDescription,
      ),
      "array" => _sanitizeArraySchema(
        source,
        path: path,
        inheritedDescription: inheritedDescription,
      ),
      "string" || "number" || "integer" || "boolean" => _sanitizeLiteralSchema(
        source,
        path: path,
        inheritedDescription: inheritedDescription,
      ),
      _ when source.containsKey("properties") => _sanitizeObjectSchema(
        source,
        path: path,
        inheritedDescription: inheritedDescription,
      ),
      _ => null,
    };
  }

  Map<String, Object?> _sanitizeObjectSchema(
    Map<String, Object?> source, {
    required List<String> path,
    required String? inheritedDescription,
  }) {
    Map<String, Object?> out = <String, Object?>{"type": "object"};
    String? description = _readDescription(source) ?? inheritedDescription;
    if (description != null && description.isNotEmpty) {
      out["description"] = description;
    }

    List<String> required = _readStringList(source["required"]);
    if (required.isNotEmpty) {
      out["required"] = required;
    }

    Map<String, Object?> properties = _readObjectMap(source["properties"]);
    if (properties.isNotEmpty) {
      out["properties"] = <String, Object?>{
        for (MapEntry<String, Object?> entry in properties.entries)
          if (_castObjectMap(entry.value)
              case Map<String, Object?> propertySchema)
            entry.key:
                (_sanitizeSchemaNode(
                  propertySchema,
                  path: <String>[...path, entry.key],
                  inheritedDescription: null,
                ) ??
                _fallbackLiteralSchema(path: <String>[...path, entry.key])),
      };
    } else {
      out["properties"] = <String, Object?>{};
    }

    Map<String, Object?> requiredConstraints = _readObjectMap(
      source["required_constraints"],
    );
    if (requiredConstraints.isNotEmpty) {
      out["required_constraints"] = requiredConstraints;
    }
    return out;
  }

  Map<String, Object?> _sanitizeArraySchema(
    Map<String, Object?> source, {
    required List<String> path,
    required String? inheritedDescription,
  }) {
    String description =
        _readDescription(source) ??
        inheritedDescription ??
        _defaultDescription(path, isArray: true);
    Map<String, Object?> out = <String, Object?>{
      "type": "array",
      "description": description,
    };

    Map<String, Object?> items = _readObjectMap(source["items"]);
    if (items.isNotEmpty) {
      out["items"] =
          _sanitizeSchemaNode(
            items,
            path: <String>[...path, "item"],
            inheritedDescription: _defaultItemDescription(path),
          ) ??
          _fallbackLiteralSchema(path: <String>[...path, "item"]);
    }
    return out;
  }

  Map<String, Object?> _sanitizeLiteralSchema(
    Map<String, Object?> source, {
    required List<String> path,
    required String? inheritedDescription,
  }) {
    Map<String, Object?> out = <String, Object?>{
      "type": source["type"]?.toString() ?? "string",
    };

    List<String> enumValues = _readStringList(source["enum"]);
    if (enumValues.isNotEmpty) {
      out["enum"] = enumValues;
    }

    Object? constantValue = source["constant_value"];
    String? dynamicVariable = source["dynamic_variable"]?.toString();
    bool? isSystemProvided = source["is_system_provided"] as bool?;
    String? description =
        _readDescription(source) ??
        inheritedDescription ??
        _defaultDescription(path);

    if (constantValue != null) {
      out["constant_value"] = constantValue;
    } else if (dynamicVariable != null && dynamicVariable.isNotEmpty) {
      out["dynamic_variable"] = dynamicVariable;
    } else if (isSystemProvided == true) {
      out["is_system_provided"] = true;
    } else {
      out["description"] = description;
    }

    return out;
  }

  Map<String, Object?> _fallbackLiteralSchema({required List<String> path}) =>
      <String, Object?>{
        "type": "string",
        "description": _defaultDescription(path),
      };

  Map<String, Object?> _readObjectMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value.cast<String, Object?>();
    }
    if (value is Map<String, Object?>) {
      return value;
    }
    return <String, Object?>{};
  }

  Map<String, Object?>? _castObjectMap(Object? value) {
    if (value is Map) {
      return value.cast<String, Object?>();
    }
    return null;
  }

  List<String> _readStringList(Object? value) => switch (value) {
    List<dynamic> listValue => <String>[
      for (Object? item in listValue)
        if (item != null && item.toString().isNotEmpty) item.toString(),
    ],
    _ => <String>[],
  };

  String? _readDescription(Map<String, Object?> source) {
    String? description = source["description"]?.toString();
    if (description == null || description.trim().isEmpty) {
      return null;
    }
    return description.trim();
  }

  String _defaultItemDescription(List<String> path) {
    if (path.isEmpty) {
      return "A single item value.";
    }
    return "A single ${path.last} value.";
  }

  String _defaultDescription(List<String> path, {bool isArray = false}) {
    if (path.isEmpty) {
      return isArray ? "A list of values." : "A value.";
    }
    String label = path.where((segment) => segment != "item").join(" ");
    if (label.isEmpty) {
      return isArray ? "A list of values." : "A value.";
    }
    return isArray ? "A list of $label values." : "A value for $label.";
  }
}
