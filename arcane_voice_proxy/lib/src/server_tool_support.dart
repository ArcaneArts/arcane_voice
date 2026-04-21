import 'dart:convert';

import 'package:arcane_voice_models/arcane_voice_models.dart';
import 'package:arcane_voice_proxy/src/realtime_json_support.dart';

typedef ClientToolInvoker =
    Future<String> Function({
      required String requestId,
      required String name,
      required String rawArguments,
    });

typedef ServerToolHandler =
    Future<Object?> Function(Map<String, Object?> arguments);

class ProxyToolRegistry {
  final ServerToolRegistry serverTools;
  final Map<String, RealtimeToolDefinition> clientTools;
  final ClientToolInvoker? clientToolInvoker;

  ProxyToolRegistry({
    ServerToolRegistry? serverTools,
    List<RealtimeToolDefinition> clientTools = const <RealtimeToolDefinition>[],
    this.clientToolInvoker,
  }) : serverTools = serverTools ?? ServerToolRegistry.empty(),
       clientTools = <String, RealtimeToolDefinition>{
         for (RealtimeToolDefinition tool in clientTools) tool.name: tool,
       };

  ProxyToolRegistry bindClientTools({
    required List<RealtimeToolDefinition> clientTools,
    required ClientToolInvoker clientToolInvoker,
  }) => ProxyToolRegistry(
    serverTools: serverTools,
    clientTools: clientTools,
    clientToolInvoker: clientToolInvoker,
  );

  bool get hasTools => serverTools.hasTools || clientTools.isNotEmpty;

  List<Map<String, Object?>> get openAiTools => <Map<String, Object?>>[
    ...serverTools.openAiTools,
    for (RealtimeToolDefinition tool in clientTools.values)
      <String, Object?>{
        "type": "function",
        "name": tool.name,
        "description": tool.description,
        "parameters": _decodeParameters(tool.parametersJson),
      },
  ];

  List<Map<String, Object?>> get geminiTools => <Map<String, Object?>>[
    <String, Object?>{
      "functionDeclarations": <Map<String, Object?>>[
        ...serverTools.geminiFunctionDeclarations,
        for (RealtimeToolDefinition tool in clientTools.values)
          <String, Object?>{
            "name": tool.name,
            "description": tool.description,
            "parameters": _decodeParameters(
              tool.parametersJson,
            ).geminiSchemaSubset,
          },
      ],
    },
  ];

  String executionTarget(String name) => switch (_toolLocation(name)) {
    _ToolLocation.server => RealtimeToolExecutionTarget.server,
    _ToolLocation.client => RealtimeToolExecutionTarget.client,
    _ => RealtimeToolExecutionTarget.server,
  };

  Future<ToolExecutionResult> executeJsonString({
    required String callId,
    required String name,
    required String rawArguments,
  }) async {
    _ToolLocation location = _toolLocation(name);
    return switch (location) {
      _ToolLocation.server => _executeServerTool(
        callId: callId,
        name: name,
        rawArguments: rawArguments,
      ),
      _ToolLocation.client => _executeClientTool(
        callId: callId,
        name: name,
        rawArguments: rawArguments,
      ),
      _ => ToolExecutionResult.error(
        callId: callId,
        name: name,
        executionTarget: RealtimeToolExecutionTarget.server,
        error: "Unknown tool: $name",
      ),
    };
  }

  Future<ToolExecutionResult> executeObject({
    required String callId,
    required String name,
    required Map<String, Object?> arguments,
  }) => executeJsonString(
    callId: callId,
    name: name,
    rawArguments: jsonEncode(arguments),
  );

  Map<String, Object?> _decodeParameters(String parametersJson) {
    Object? decoded = jsonDecode(parametersJson);
    if (decoded is Map<String, dynamic>) {
      return decoded.cast<String, Object?>();
    }

    if (decoded is Map<String, Object?>) {
      return decoded;
    }

    return <String, Object?>{
      "type": "object",
      "properties": <String, Object?>{},
      "required": <String>[],
    };
  }

  Future<ToolExecutionResult> _executeServerTool({
    required String callId,
    required String name,
    required String rawArguments,
  }) async {
    try {
      Object? decodedArguments = rawArguments.trim().isEmpty
          ? <String, Object?>{}
          : jsonDecode(rawArguments);
      Map<String, Object?> arguments = decodedArguments is Map<String, dynamic>
          ? decodedArguments.cast<String, Object?>()
          : decodedArguments is Map<String, Object?>
          ? decodedArguments
          : <String, Object?>{};
      Object? result = await serverTools.executeValue(
        name: name,
        arguments: arguments,
      );
      return ToolExecutionResult.fromValue(
        callId: callId,
        name: name,
        executionTarget: RealtimeToolExecutionTarget.server,
        value: result,
      );
    } catch (error) {
      return ToolExecutionResult.error(
        callId: callId,
        name: name,
        executionTarget: RealtimeToolExecutionTarget.server,
        error: error.toString(),
      );
    }
  }

  Future<ToolExecutionResult> _executeClientTool({
    required String callId,
    required String name,
    required String rawArguments,
  }) async {
    ClientToolInvoker? invoker = clientToolInvoker;
    if (invoker == null) {
      return ToolExecutionResult.error(
        callId: callId,
        name: name,
        executionTarget: RealtimeToolExecutionTarget.client,
        error: "Client tool invoker is not available.",
      );
    }

    try {
      String outputJson = await invoker(
        requestId: callId,
        name: name,
        rawArguments: rawArguments,
      );
      return ToolExecutionResult.fromJsonString(
        callId: callId,
        name: name,
        executionTarget: RealtimeToolExecutionTarget.client,
        outputJson: outputJson,
      );
    } catch (error) {
      return ToolExecutionResult.error(
        callId: callId,
        name: name,
        executionTarget: RealtimeToolExecutionTarget.client,
        error: error.toString(),
      );
    }
  }

  _ToolLocation _toolLocation(String name) => switch (name) {
    _ when serverTools.hasTool(name) => _ToolLocation.server,
    _ when clientTools.containsKey(name) => _ToolLocation.client,
    _ => _ToolLocation.unknown,
  };
}

class ServerToolRegistry {
  final Map<String, ServerTool> tools;

  ServerToolRegistry({List<ServerTool> tools = const <ServerTool>[]})
    : tools = <String, ServerTool>{
        for (ServerTool tool in tools) tool.name: tool,
      };

  factory ServerToolRegistry.empty() => ServerToolRegistry();

  bool get hasTools => tools.isNotEmpty;

  bool hasTool(String name) => tools.containsKey(name);

  List<Map<String, Object?>> get openAiTools =>
      tools.values.map((tool) => tool.openAiDefinition).toList();

  List<Map<String, Object?>> get geminiFunctionDeclarations =>
      tools.values.map((tool) => tool.geminiDefinition.geminiSchemaSubset).toList();

  Future<Object?> executeValue({
    required String name,
    required Map<String, Object?> arguments,
  }) async {
    ServerTool? tool = tools[name];
    if (tool == null) {
      throw StateError("Unknown tool: $name");
    }

    return tool.execute(arguments);
  }
}

abstract class ServerTool {
  RealtimeToolDefinition get definition;
  Future<Object?> execute(Map<String, Object?> arguments);

  String get name => definition.name;

  String get description => definition.description;

  String get parametersJson => definition.parametersJson;

  Map<String, Object?> get parameters => _decodeParameters(parametersJson);

  Map<String, Object?> get openAiDefinition => <String, Object?>{
    "type": "function",
    "name": name,
    "description": description,
    "parameters": parameters,
  };

  Map<String, Object?> get geminiDefinition => <String, Object?>{
    "name": name,
    "description": description,
    "parameters": parameters,
  };

  Map<String, Object?> _decodeParameters(String source) {
    Object? decoded = jsonDecode(source);
    if (decoded is Map<String, dynamic>) {
      return decoded.cast<String, Object?>();
    }

    if (decoded is Map<String, Object?>) {
      return decoded;
    }

    return <String, Object?>{
      "type": "object",
      "properties": <String, Object?>{},
      "required": <String>[],
    };
  }
}

class CallbackServerTool extends ServerTool {
  @override
  final RealtimeToolDefinition definition;
  final ServerToolHandler onExecute;

  CallbackServerTool({
    required this.definition,
    required this.onExecute,
  });

  factory CallbackServerTool.jsonSchema({
    required String name,
    required String description,
    required Map<String, Object?> parameters,
    required ServerToolHandler onExecute,
  }) => CallbackServerTool(
    definition: RealtimeToolDefinition(
      name: name,
      description: description,
      parametersJson: jsonEncode(parameters),
    ),
    onExecute: onExecute,
  );

  @override
  Future<Object?> execute(Map<String, Object?> arguments) => onExecute(arguments);
}

class ToolExecutionResult {
  final String callId;
  final String name;
  final String executionTarget;
  final bool success;
  final String outputJson;
  final Map<String, Object?> outputObject;
  final String? error;

  const ToolExecutionResult({
    required this.callId,
    required this.name,
    required this.executionTarget,
    required this.success,
    required this.outputJson,
    required this.outputObject,
    this.error,
  });

  factory ToolExecutionResult.fromValue({
    required String callId,
    required String name,
    required String executionTarget,
    required Object? value,
  }) {
    String outputJson = jsonEncode(value);
    return ToolExecutionResult(
      callId: callId,
      name: name,
      executionTarget: executionTarget,
      success: true,
      outputJson: outputJson,
      outputObject: _normalizeOutputObject(value),
    );
  }

  factory ToolExecutionResult.fromJsonString({
    required String callId,
    required String name,
    required String executionTarget,
    required String outputJson,
  }) {
    Object? value = outputJson.trim().isEmpty ? null : jsonDecode(outputJson);
    return ToolExecutionResult(
      callId: callId,
      name: name,
      executionTarget: executionTarget,
      success: true,
      outputJson: outputJson,
      outputObject: _normalizeOutputObject(value),
    );
  }

  factory ToolExecutionResult.error({
    required String callId,
    required String name,
    required String executionTarget,
    required String error,
  }) => ToolExecutionResult(
    callId: callId,
    name: name,
    executionTarget: executionTarget,
    success: false,
    outputJson: jsonEncode(<String, Object?>{"error": error}),
    outputObject: <String, Object?>{"error": error},
    error: error,
  );

  static Map<String, Object?> _normalizeOutputObject(Object? value) {
    if (value is Map<String, dynamic>) {
      return value.cast<String, Object?>();
    }

    if (value is Map<String, Object?>) {
      return value;
    }

    return <String, Object?>{"result": value};
  }
}

enum _ToolLocation { server, client, unknown }
