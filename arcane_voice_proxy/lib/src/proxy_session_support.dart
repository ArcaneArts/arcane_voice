import 'dart:async';

import 'package:arcane_voice_models/arcane_voice_models.dart';
import 'package:arcane_voice_proxy/src/realtime_provider_session_support.dart';
import 'package:arcane_voice_proxy/src/server_tool_support.dart';

class ArcaneVoiceProxyConnectionInfo {
  final String? remoteAddress;
  final String? requestPath;
  final Map<String, String> queryParameters;

  const ArcaneVoiceProxyConnectionInfo({
    this.remoteAddress,
    this.requestPath,
    this.queryParameters = const <String, String>{},
  });
}

class ArcaneVoiceProxySessionRequest {
  final String sessionId;
  final ArcaneVoiceProxyConnectionInfo connectionInfo;
  final RealtimeSessionStartRequest request;
  final DateTime receivedAt;

  const ArcaneVoiceProxySessionRequest({
    required this.sessionId,
    required this.connectionInfo,
    required this.request,
    required this.receivedAt,
  });
}

class ArcaneVoiceProxyResolvedSession {
  final String provider;
  final RealtimeSessionConfig config;
  final ArcaneVoiceProxyToolRegistry proxyTools;
  final Object? context;

  const ArcaneVoiceProxyResolvedSession({
    required this.provider,
    required this.config,
    required this.proxyTools,
    this.context,
  });

  factory ArcaneVoiceProxyResolvedSession.passthrough({
    required RealtimeSessionStartRequest request,
    required ArcaneVoiceProxyToolRegistry proxyTools,
    Object? context,
  }) => ArcaneVoiceProxyResolvedSession(
    provider: request.provider,
    config: RealtimeSessionConfig.fromRequest(request),
    proxyTools: proxyTools,
    context: context,
  );
}

typedef ArcaneVoiceProxySessionResolver =
    FutureOr<ArcaneVoiceProxyResolvedSession> Function(
      ArcaneVoiceProxySessionRequest request,
    );

class ArcaneVoiceProxyUsage {
  final String provider;
  final int? inputTextTokens;
  final int? outputTextTokens;
  final int? cachedTextTokens;
  final int? inputAudioTokens;
  final int? outputAudioTokens;
  final int? totalTokens;
  final int? inputAudioBytes;
  final int? outputAudioBytes;
  final Duration? sessionDuration;
  final Map<String, Object?> raw;

  const ArcaneVoiceProxyUsage({
    required this.provider,
    this.inputTextTokens,
    this.outputTextTokens,
    this.cachedTextTokens,
    this.inputAudioTokens,
    this.outputAudioTokens,
    this.totalTokens,
    this.inputAudioBytes,
    this.outputAudioBytes,
    this.sessionDuration,
    this.raw = const <String, Object?>{},
  });

  int? get totalTextTokens => _sumNullable(inputTextTokens, outputTextTokens);

  int? get totalAudioTokens =>
      _sumNullable(inputAudioTokens, outputAudioTokens);

  ArcaneVoiceProxyUsage merge(ArcaneVoiceProxyUsage other) {
    if (other.provider != provider) {
      throw ArgumentError.value(
        other.provider,
        'other.provider',
        'Cannot merge usage for a different provider.',
      );
    }

    return ArcaneVoiceProxyUsage(
      provider: provider,
      inputTextTokens: _sumNullable(inputTextTokens, other.inputTextTokens),
      outputTextTokens: _sumNullable(outputTextTokens, other.outputTextTokens),
      cachedTextTokens: _sumNullable(cachedTextTokens, other.cachedTextTokens),
      inputAudioTokens: _sumNullable(inputAudioTokens, other.inputAudioTokens),
      outputAudioTokens: _sumNullable(
        outputAudioTokens,
        other.outputAudioTokens,
      ),
      totalTokens: _sumNullable(totalTokens, other.totalTokens),
      inputAudioBytes: _sumNullable(inputAudioBytes, other.inputAudioBytes),
      outputAudioBytes: _sumNullable(outputAudioBytes, other.outputAudioBytes),
      sessionDuration: _maxDuration(sessionDuration, other.sessionDuration),
      raw: <String, Object?>{...raw, ...other.raw},
    );
  }

  static int? _sumNullable(int? a, int? b) {
    if (a == null && b == null) {
      return null;
    }
    return (a ?? 0) + (b ?? 0);
  }

  static Duration? _maxDuration(Duration? a, Duration? b) {
    if (a == null) {
      return b;
    }
    if (b == null) {
      return a;
    }
    return a >= b ? a : b;
  }
}

class ArcaneVoiceProxySessionStartedEvent {
  final String sessionId;
  final DateTime startedAt;
  final ArcaneVoiceProxyConnectionInfo connectionInfo;
  final RealtimeSessionStartRequest request;
  final String provider;
  final RealtimeSessionConfig config;
  final Object? context;

  const ArcaneVoiceProxySessionStartedEvent({
    required this.sessionId,
    required this.startedAt,
    required this.connectionInfo,
    required this.request,
    required this.provider,
    required this.config,
    this.context,
  });
}

class ArcaneVoiceProxyUsageEvent {
  final String sessionId;
  final DateTime observedAt;
  final ArcaneVoiceProxyConnectionInfo connectionInfo;
  final String provider;
  final ArcaneVoiceProxyUsage usage;
  final Object? context;

  const ArcaneVoiceProxyUsageEvent({
    required this.sessionId,
    required this.observedAt,
    required this.connectionInfo,
    required this.provider,
    required this.usage,
    this.context,
  });
}

class ArcaneVoiceProxyToolExecutionEvent {
  final String sessionId;
  final DateTime startedAt;
  final DateTime completedAt;
  final ArcaneVoiceProxyConnectionInfo connectionInfo;
  final String provider;
  final String name;
  final String executionTarget;
  final String rawArguments;
  final ToolExecutionResult result;
  final Object? context;

  const ArcaneVoiceProxyToolExecutionEvent({
    required this.sessionId,
    required this.startedAt,
    required this.completedAt,
    required this.connectionInfo,
    required this.provider,
    required this.name,
    required this.executionTarget,
    required this.rawArguments,
    required this.result,
    this.context,
  });

  Duration get duration => completedAt.difference(startedAt);
}

class ArcaneVoiceProxySessionStoppedEvent {
  final String sessionId;
  final DateTime startedAt;
  final DateTime stoppedAt;
  final ArcaneVoiceProxyConnectionInfo connectionInfo;
  final String provider;
  final String model;
  final String voice;
  final String reason;
  final ArcaneVoiceProxyUsage? usage;
  final int proxyToolCalls;
  final int clientToolCalls;
  final String? error;
  final Object? context;

  const ArcaneVoiceProxySessionStoppedEvent({
    required this.sessionId,
    required this.startedAt,
    required this.stoppedAt,
    required this.connectionInfo,
    required this.provider,
    required this.model,
    required this.voice,
    required this.reason,
    this.usage,
    this.proxyToolCalls = 0,
    this.clientToolCalls = 0,
    this.error,
    this.context,
  });

  Duration get duration => stoppedAt.difference(startedAt);
}

class ArcaneVoiceProxyLifecycleCallbacks {
  final FutureOr<void> Function(ArcaneVoiceProxySessionStartedEvent event)?
  onSessionStarted;
  final FutureOr<void> Function(ArcaneVoiceProxyUsageEvent event)? onUsage;
  final FutureOr<void> Function(ArcaneVoiceProxyToolExecutionEvent event)?
  onToolExecuted;
  final FutureOr<void> Function(ArcaneVoiceProxySessionStoppedEvent event)?
  onSessionStopped;

  const ArcaneVoiceProxyLifecycleCallbacks({
    this.onSessionStarted,
    this.onUsage,
    this.onToolExecuted,
    this.onSessionStopped,
  });
}
