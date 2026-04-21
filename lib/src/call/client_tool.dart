import 'dart:convert';

import 'package:arcane_voice_models/arcane_voice_models.dart';

typedef ClientToolHandler =
    Future<Object?> Function(Map<String, Object?> arguments);

class ClientTool {
  final RealtimeToolDefinition definition;
  final ClientToolHandler execute;

  const ClientTool({required this.definition, required this.execute});

  factory ClientTool.jsonSchema({
    required String name,
    required String description,
    required Map<String, Object?> parameters,
    required ClientToolHandler execute,
  }) => ClientTool(
    definition: RealtimeToolDefinition(
      name: name,
      description: description,
      parametersJson: jsonEncode(parameters),
    ),
    execute: execute,
  );
}

class ClientToolRegistry {
  final Map<String, ClientTool> _tools;

  ClientToolRegistry({List<ClientTool> tools = const <ClientTool>[]})
    : _tools = <String, ClientTool>{
        for (ClientTool tool in tools) tool.definition.name: tool,
      };

  List<RealtimeToolDefinition> get definitions =>
      _tools.values.map((tool) => tool.definition).toList();

  Future<String> execute({
    required String name,
    required String argumentsJson,
  }) async {
    ClientTool? tool = _tools[name];
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
