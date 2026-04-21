import 'dart:convert';

import 'package:arcane_voice_models/arcane_voice_models.dart';

typedef ArcaneVoiceClientToolHandler =
    Future<Object?> Function(Map<String, Object?> arguments);

class ArcaneVoiceClientTool {
  final RealtimeToolDefinition definition;
  final ArcaneVoiceClientToolHandler execute;

  const ArcaneVoiceClientTool({
    required this.definition,
    required this.execute,
  });

  factory ArcaneVoiceClientTool.jsonSchema({
    required String name,
    required String description,
    required Map<String, Object?> parameters,
    required ArcaneVoiceClientToolHandler execute,
  }) => ArcaneVoiceClientTool(
    definition: RealtimeToolDefinition(
      name: name,
      description: description,
      parametersJson: jsonEncode(parameters),
    ),
    execute: execute,
  );
}

class ArcaneVoiceClientToolRegistry {
  final Map<String, ArcaneVoiceClientTool> _tools;

  ArcaneVoiceClientToolRegistry({
    List<ArcaneVoiceClientTool> tools = const <ArcaneVoiceClientTool>[],
  }) : _tools = <String, ArcaneVoiceClientTool>{
         for (ArcaneVoiceClientTool tool in tools) tool.definition.name: tool,
       };

  List<RealtimeToolDefinition> get definitions =>
      _tools.values.map((tool) => tool.definition).toList();

  Future<String> execute({
    required String name,
    required String argumentsJson,
  }) async {
    ArcaneVoiceClientTool? tool = _tools[name];
    if (tool == null) {
      throw StateError("Unknown client tool: $name");
    }

    Object? decodedArguments = argumentsJson.trim().isEmpty
        ? <String, Object?>{}
        : jsonDecode(argumentsJson);
    Map<String, Object?> arguments = decodedArguments is Map<String, dynamic>
        ? decodedArguments.cast<String, Object?>()
        : decodedArguments is Map<String, Object?>
        ? decodedArguments
        : <String, Object?>{};
    Object? result = await tool.execute(arguments);
    return jsonEncode(result);
  }
}
