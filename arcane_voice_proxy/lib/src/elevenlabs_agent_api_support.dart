import 'dart:convert';
import 'dart:io';

import 'package:arcane_voice_proxy/src/realtime_json_support.dart';
import 'package:arcane_voice_proxy/src/server_log.dart';
import 'package:arcane_voice_proxy/src/server_tool_support.dart';

class ElevenLabsAgentApiClient {
  final String apiKey;

  const ElevenLabsAgentApiClient({required this.apiKey});

  Future<Map<String, Object?>> fetchAgent(String agentId) => performJsonRequest(
    method: 'GET',
    uri: Uri.https('api.elevenlabs.io', '/v1/convai/agents/$agentId'),
  );

  Future<void> patchAgentConversationConfig({
    required String agentId,
    required Map<String, Object?> conversationConfig,
  }) async {
    await performJsonRequest(
      method: 'PATCH',
      uri: Uri.https('api.elevenlabs.io', '/v1/convai/agents/$agentId'),
      body: <String, Object?>{'conversation_config': conversationConfig},
    );
  }

  Future<Map<String, Map<String, Object?>>> fetchWorkspaceClientToolsByName()
      async {
    Map<String, Object?> response = await performJsonRequest(
      method: 'GET',
      uri: Uri.https('api.elevenlabs.io', '/v1/convai/tools'),
    );
    Object? rawTools = response['tools'];
    if (rawTools is! List) {
      return <String, Map<String, Object?>>{};
    }

    Map<String, Map<String, Object?>> toolsByName =
        <String, Map<String, Object?>>{};
    for (Object? rawTool in rawTools) {
      Map<String, Object?>? tool = _castObjectMap(rawTool);
      if (tool == null) {
        continue;
      }

      Map<String, Object?> toolConfig =
          _castObjectMap(tool['tool_config']) ?? <String, Object?>{};
      if (toolConfig['type']?.toString() != 'client') {
        continue;
      }
      String toolName = toolConfig['name']?.toString() ?? "";
      if (toolName.isEmpty) {
        continue;
      }
      toolsByName[toolName] = tool;
    }
    return toolsByName;
  }

  Future<String> createTool(Map<String, Object?> toolConfig) async {
    info("[elevenlabs] creating client tool ${toolConfig['name']}");
    Map<String, Object?> response = await performJsonRequest(
      method: 'POST',
      uri: Uri.https('api.elevenlabs.io', '/v1/convai/tools'),
      body: <String, Object?>{'tool_config': toolConfig},
    );
    return response['id']?.toString() ?? "";
  }

  Future<void> updateTool({
    required String toolId,
    required Map<String, Object?> toolConfig,
  }) async {
    if (toolId.isEmpty) {
      return;
    }
    info("[elevenlabs] updating client tool ${toolConfig['name']}");
    await performJsonRequest(
      method: 'PATCH',
      uri: Uri.https('api.elevenlabs.io', '/v1/convai/tools/$toolId'),
      body: <String, Object?>{'tool_config': toolConfig},
    );
  }

  Future<String> getSignedUrl(String agentId) async {
    Map<String, Object?> response = await performJsonRequest(
      method: 'GET',
      uri: Uri.https(
        'api.elevenlabs.io',
        '/v1/convai/conversation/get-signed-url',
        <String, String>{'agent_id': agentId},
      ),
    );
    String signedUrl = response['signed_url']?.toString() ?? "";
    if (signedUrl.isEmpty) {
      throw StateError('ElevenLabs signed URL response did not include a URL.');
    }
    return signedUrl;
  }

  Future<Map<String, Object?>> performJsonRequest({
    required String method,
    required Uri uri,
    Map<String, Object?>? body,
  }) async {
    HttpClient client = HttpClient();
    HttpClientRequest request = await client.openUrl(method, uri);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.headers.set('xi-api-key', apiKey);
    if (body != null) {
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      request.write(jsonEncode(body));
    }

    HttpClientResponse response = await request.close();
    String responseBody = await utf8.decoder.bind(response).join();
    client.close(force: true);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'ElevenLabs $method ${uri.path} failed (${response.statusCode}): $responseBody',
        uri: uri,
      );
    }
    if (responseBody.trim().isEmpty) {
      return <String, Object?>{};
    }
    return JsonCodecHelper.decodeObject(responseBody);
  }
}

class ElevenLabsAgentConfigurator {
  final ElevenLabsAgentApiClient apiClient;
  final ProxyToolRegistry toolRegistry;

  const ElevenLabsAgentConfigurator({
    required this.apiClient,
    required this.toolRegistry,
  });

  Future<void> ensureAgentConfigured(String agentId) async {
    Map<String, Object?> agent = await apiClient.fetchAgent(agentId);
    List<String> toolIds = await _ensureWorkspaceTools();
    Map<String, Object?> conversationConfig =
        _castObjectMap(agent['conversation_config']) ?? <String, Object?>{};
    Map<String, Object?> nextConversationConfig =
        buildElevenLabsConversationConfigUpdate(
          conversationConfig: conversationConfig,
          toolIds: toolIds,
        );
    if (_jsonEquals(conversationConfig, nextConversationConfig)) {
      return;
    }

    info('[elevenlabs] updating agent tool_ids/client_events');
    await apiClient.patchAgentConversationConfig(
      agentId: agentId,
      conversationConfig: nextConversationConfig,
    );
  }

  Future<List<String>> _ensureWorkspaceTools() async {
    if (!toolRegistry.hasTools) {
      return <String>[];
    }

    List<Map<String, Object?>> desiredTools = toolRegistry.elevenLabsClientTools;
    Map<String, Map<String, Object?>> existingToolsByName =
        await apiClient.fetchWorkspaceClientToolsByName();
    List<String> resolvedToolIds = <String>[];

    for (Map<String, Object?> desiredTool in desiredTools) {
      String toolName = desiredTool['name']?.toString() ?? "";
      if (toolName.isEmpty) {
        continue;
      }

      Map<String, Object?>? existing = existingToolsByName[toolName];
      if (existing == null) {
        String createdToolId = await apiClient.createTool(desiredTool);
        resolvedToolIds = <String>[...resolvedToolIds, createdToolId];
        continue;
      }

      String toolId = existing['id']?.toString() ?? "";
      Map<String, Object?> existingToolConfig =
          _castObjectMap(existing['tool_config']) ?? <String, Object?>{};
      if (!_jsonEquals(existingToolConfig, desiredTool)) {
        await apiClient.updateTool(toolId: toolId, toolConfig: desiredTool);
      }
      if (toolId.isNotEmpty) {
        resolvedToolIds = <String>[...resolvedToolIds, toolId];
      }
    }

    return resolvedToolIds;
  }
}

Map<String, Object?> buildElevenLabsConversationConfigUpdate({
  required Map<String, Object?> conversationConfig,
  required List<String> toolIds,
}) {
  Map<String, Object?> nextConversationConfig = _cloneObjectMap(
    conversationConfig,
  );
  Map<String, Object?> nextConversation = _cloneObjectMap(
    _castObjectMap(nextConversationConfig['conversation']) ??
        <String, Object?>{},
  );
  List<String> clientEvents = _readStringList(nextConversation['client_events']);
  List<String> requiredClientEvents = <String>[
    'audio',
    'user_transcript',
    'agent_response',
    'agent_response_correction',
    'client_tool_call',
    'interruption',
  ];
  nextConversation['client_events'] = _mergeUniqueStrings(
    existing: clientEvents,
    additions: requiredClientEvents,
  );
  nextConversationConfig['conversation'] = nextConversation;

  if (toolIds.isNotEmpty) {
    Map<String, Object?> nextAgent = _cloneObjectMap(
      _castObjectMap(nextConversationConfig['agent']) ?? <String, Object?>{},
    );
    Map<String, Object?> nextPrompt = _cloneObjectMap(
      _castObjectMap(nextAgent['prompt']) ?? <String, Object?>{},
    );
    List<String> existingToolIds = _readStringList(nextPrompt['tool_ids']);
    nextPrompt['tool_ids'] = _mergeUniqueStrings(
      existing: existingToolIds,
      additions: toolIds,
    );
    nextAgent['prompt'] = nextPrompt;
    nextConversationConfig['agent'] = nextAgent;
  }

  return nextConversationConfig;
}

Object? formatElevenLabsToolResult(String outputJson) {
  Object? decoded = _decodeJsonValue(outputJson);
  if (decoded is Map<String, dynamic>) {
    return decoded.cast<String, Object?>();
  }
  if (decoded is String) {
    return decoded;
  }
  return jsonEncode(decoded);
}

int parseElevenLabsPcmSampleRate(
  String? format, {
  int defaultSampleRate = 16000,
}) {
  if (format == null || format.isEmpty) {
    return defaultSampleRate;
  }
  RegExp matchPattern = RegExp(r'_(\d+)$');
  RegExpMatch? match = matchPattern.firstMatch(format);
  if (match == null) {
    return defaultSampleRate;
  }
  return int.tryParse(match.group(1) ?? "") ?? defaultSampleRate;
}

Map<String, Object?> _cloneObjectMap(Map<String, Object?> source) =>
    <String, Object?>{
      for (MapEntry<String, Object?> entry in source.entries)
        entry.key: _cloneJsonValue(entry.value),
    };

Object? _cloneJsonValue(Object? value) {
  if (value is Map<String, dynamic>) {
    return _cloneObjectMap(value.cast<String, Object?>());
  }
  if (value is Map<String, Object?>) {
    return _cloneObjectMap(value);
  }
  if (value is List<dynamic>) {
    return <Object?>[
      for (Object? item in value) _cloneJsonValue(item),
    ];
  }
  return value;
}

Map<String, Object?>? _castObjectMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value.cast<String, Object?>();
  }
  if (value is Map<String, Object?>) {
    return value;
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

List<String> _mergeUniqueStrings({
  required List<String> existing,
  required List<String> additions,
}) {
  Set<String> values = <String>{...existing};
  for (String value in additions) {
    if (value.isNotEmpty) {
      values = <String>{...values, value};
    }
  }
  return values.toList();
}

Object? _decodeJsonValue(String source) {
  if (source.trim().isEmpty) {
    return null;
  }
  try {
    return jsonDecode(source);
  } catch (_) {
    return source;
  }
}

bool _jsonEquals(Object? left, Object? right) => jsonEncode(left) == jsonEncode(right);
