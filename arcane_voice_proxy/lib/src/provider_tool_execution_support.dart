import 'dart:convert';

import 'package:arcane_voice_models/arcane_voice_models.dart';
import 'package:arcane_voice_proxy/src/provider_runtime_support.dart';
import 'package:arcane_voice_proxy/src/server_log.dart';
import 'package:arcane_voice_proxy/src/server_tool_support.dart';

class ProviderToolExecutionBridge {
  final ProviderSessionRuntime runtime;

  const ProviderToolExecutionBridge({required this.runtime});

  ToolExecutionInvocation createInvocation({
    required String callId,
    required String name,
  }) => ToolExecutionInvocation(runtime: runtime, callId: callId, name: name);

  Future<void> executeJsonToolCall({
    required String providerLabel,
    required String? callId,
    required String? name,
    required String rawArguments,
    required Future<void> Function(ToolExecutionResult output) onResult,
  }) async {
    String resolvedName = name?.trim() ?? "";
    String resolvedCallId = callId?.trim() ?? "";
    if (resolvedName.isEmpty || resolvedCallId.isEmpty) {
      return;
    }

    info("[$providerLabel] executing tool $resolvedName");
    ToolExecutionInvocation invocation = createInvocation(
      callId: resolvedCallId,
      name: resolvedName,
    );
    ToolExecutionResult output = await invocation.executeJson(
      rawArguments: rawArguments,
    );
    await onResult(output);
    await invocation.emitCompleted(output, rawArguments: rawArguments);
  }

  Future<void> executeObjectToolCall({
    required String providerLabel,
    required String? callId,
    required String? name,
    required Map<String, Object?> arguments,
    required Future<void> Function(ToolExecutionResult output) onResult,
  }) async {
    String resolvedName = name?.trim() ?? "";
    String resolvedCallId = callId?.trim() ?? "";
    if (resolvedName.isEmpty || resolvedCallId.isEmpty) {
      return;
    }

    info("[$providerLabel] executing tool $resolvedName");
    ToolExecutionInvocation invocation = createInvocation(
      callId: resolvedCallId,
      name: resolvedName,
    );
    ToolExecutionResult output = await invocation.executeObject(
      arguments: arguments,
    );
    await onResult(output);
    await invocation.emitCompleted(output, rawArguments: jsonEncode(arguments));
  }
}

class ToolExecutionInvocation {
  final ProviderSessionRuntime runtime;
  final String callId;
  final String name;
  DateTime? startedAt;

  ToolExecutionInvocation({
    required this.runtime,
    required this.callId,
    required this.name,
  });

  Future<ToolExecutionResult> executeJson({
    required String rawArguments,
  }) async {
    startedAt ??= DateTime.now();
    await _emitStarted();
    return runtime.toolRegistry.executeJsonString(
      callId: callId,
      name: name,
      rawArguments: rawArguments,
    );
  }

  Future<ToolExecutionResult> executeObject({
    required Map<String, Object?> arguments,
  }) async {
    startedAt ??= DateTime.now();
    await _emitStarted();
    return runtime.toolRegistry.executeObject(
      callId: callId,
      name: name,
      arguments: arguments,
    );
  }

  Future<void> emitCompleted(
    ToolExecutionResult output, {
    required String rawArguments,
  }) async {
    DateTime completedAt = DateTime.now();
    await runtime.onJsonEvent(
      RealtimeToolCompletedEvent(
        callId: callId,
        name: name,
        executionTarget: output.executionTarget,
        success: output.success,
        error: output.error,
      ),
    );
    await runtime.notifyToolExecuted(
      result: output,
      rawArguments: rawArguments,
      startedAt: startedAt ?? completedAt,
      completedAt: completedAt,
    );
  }

  Future<void> _emitStarted() async {
    String executionTarget = runtime.toolRegistry.executionTarget(name);
    await runtime.onJsonEvent(
      RealtimeToolStartedEvent(
        callId: callId,
        name: name,
        executionTarget: executionTarget,
      ),
    );
  }
}
