import 'package:arcane_voice_models/arcane_voice_models.dart';
import 'package:arcane_voice_proxy/src/provider_runtime_support.dart';
import 'package:arcane_voice_proxy/src/server_tool_support.dart';

class ProviderToolExecutionBridge {
  final ProviderSessionRuntime runtime;

  const ProviderToolExecutionBridge({required this.runtime});

  ToolExecutionInvocation createInvocation({
    required String callId,
    required String name,
  }) => ToolExecutionInvocation(runtime: runtime, callId: callId, name: name);
}

class ToolExecutionInvocation {
  final ProviderSessionRuntime runtime;
  final String callId;
  final String name;

  const ToolExecutionInvocation({
    required this.runtime,
    required this.callId,
    required this.name,
  });

  Future<ToolExecutionResult> executeJson({
    required String rawArguments,
  }) async {
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
    await _emitStarted();
    return runtime.toolRegistry.executeObject(
      callId: callId,
      name: name,
      arguments: arguments,
    );
  }

  Future<void> emitCompleted(ToolExecutionResult output) => runtime.onJsonEvent(
    RealtimeToolCompletedEvent(
      callId: callId,
      name: name,
      executionTarget: output.executionTarget,
      success: output.success,
      error: output.error,
    ),
  );

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
