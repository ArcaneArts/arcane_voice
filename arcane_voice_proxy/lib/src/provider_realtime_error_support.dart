import 'dart:convert';

import 'package:arcane_voice_proxy/src/provider_runtime_support.dart';
import 'package:arcane_voice_proxy/src/server_log.dart';

Future<void> emitProviderErrorFromEvent({
  required ProviderSessionRuntime runtime,
  required String providerLabel,
  required Map<String, Object?> event,
  required String defaultMessage,
  String errorField = 'error',
}) async {
  warning("[$providerLabel] provider error event: ${jsonEncode(event)}");
  Map<String, Object?>? structuredError = _castObjectMap(event[errorField]);
  if (structuredError != null) {
    await runtime.emitError(
      message: structuredError['message']?.toString() ?? defaultMessage,
      code: structuredError['code']?.toString(),
    );
    return;
  }

  await runtime.emitError(
    message: event['message']?.toString() ?? defaultMessage,
    code: event['code']?.toString(),
  );
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
