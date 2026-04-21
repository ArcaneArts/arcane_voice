import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:arcane_voice_proxy/src/realtime_json_support.dart';
import 'package:arcane_voice_proxy/src/server_log.dart';

class ProviderJsonSocketConnection {
  final String providerLabel;

  WebSocket? socket;
  StreamSubscription<dynamic>? subscription;
  bool isClosed = false;

  ProviderJsonSocketConnection({required this.providerLabel});

  int? get closeCode => socket?.closeCode;

  String? get closeReason => socket?.closeReason;

  Future<void> connect({
    required String url,
    Map<String, Object>? headers,
    required FutureOr<void> Function(dynamic message) onMessage,
    required FutureOr<void> Function() onDone,
    required FutureOr<void> Function(Object error) onError,
  }) async {
    WebSocket nextSocket = await WebSocket.connect(url, headers: headers);
    nextSocket.pingInterval = const Duration(seconds: 20);
    socket = nextSocket;
    subscription = nextSocket.listen(
      (dynamic message) {
        Future.sync(() => onMessage(message));
      },
      onDone: () {
        Future.sync(onDone);
      },
      onError: (Object error) {
        Future.sync(() => onError(error));
      },
      cancelOnError: true,
    );
  }

  Future<void> close({required String closeMessage}) async {
    if (isClosed) return;
    isClosed = true;
    info("[$providerLabel] $closeMessage");
    StreamSubscription<dynamic>? currentSubscription = subscription;
    WebSocket? currentSocket = socket;
    subscription = null;
    socket = null;
    await currentSubscription?.cancel();
    await currentSocket?.close();
  }

  Future<void> sendJson(Map<String, Object?> payload) async {
    if (isClosed) return;
    WebSocket? currentSocket = socket;
    if (currentSocket == null) return;
    currentSocket.add(jsonEncode(payload));
  }
}

Map<String, Object?>? decodeProviderJsonMessage(dynamic message) {
  String source = switch (message) {
    String text => text,
    List<int> bytes => utf8.decode(bytes),
    _ => "",
  };
  if (source.isEmpty) {
    return null;
  }
  return JsonCodecHelper.decodeObject(source);
}
