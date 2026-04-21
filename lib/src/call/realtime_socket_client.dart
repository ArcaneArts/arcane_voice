import 'dart:async';
import 'dart:typed_data';

import 'package:arcane_voice_models/arcane_voice_models.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class RealtimeSocketClient {
  final StreamController<RealtimeSocketEvent> events;

  WebSocketChannel? channel;
  StreamSubscription<dynamic>? subscription;

  RealtimeSocketClient()
    : events = StreamController<RealtimeSocketEvent>.broadcast();

  Stream<RealtimeSocketEvent> get stream => events.stream;

  Future<void> connect({required Uri uri}) async {
    await close();

    WebSocketChannel createdChannel = WebSocketChannel.connect(uri);
    channel = createdChannel;
    subscription = createdChannel.stream.listen(
      _handleChannelData,
      onDone: _handleChannelDone,
      onError: _handleChannelError,
      cancelOnError: true,
    );
  }

  void sendMessage(RealtimeClientMessage payload) =>
      channel?.sink.add(RealtimeProtocolCodec.encodeClientJson(payload));

  void sendAudio(Uint8List audioBytes) => channel?.sink.add(audioBytes);

  Future<void> close() async {
    StreamSubscription<dynamic>? currentSubscription = subscription;
    WebSocketChannel? currentChannel = channel;
    subscription = null;
    channel = null;
    await currentSubscription?.cancel();
    await currentChannel?.sink.close();
  }

  Future<void> dispose() async {
    await close();
    await events.close();
  }

  void _handleChannelData(dynamic data) {
    if (data is String) {
      try {
        RealtimeServerMessage payload = RealtimeProtocolCodec.decodeServerJson(
          data,
        );
        events.add(RealtimeJsonEvent(payload: payload));
      } catch (error) {
        events.add(RealtimeSocketErrorEvent(message: error.toString()));
      }
      return;
    }

    if (data is Uint8List) {
      events.add(RealtimeAudioEvent(audioBytes: data));
      return;
    }

    if (data is List<int>) {
      events.add(RealtimeAudioEvent(audioBytes: Uint8List.fromList(data)));
    }
  }

  void _handleChannelDone() {
    events.add(const RealtimeConnectionClosedEvent());
  }

  void _handleChannelError(Object error) {
    events.add(RealtimeSocketErrorEvent(message: error.toString()));
  }
}

sealed class RealtimeSocketEvent {
  const RealtimeSocketEvent();
}

class RealtimeJsonEvent extends RealtimeSocketEvent {
  final RealtimeServerMessage payload;

  const RealtimeJsonEvent({required this.payload});
}

class RealtimeAudioEvent extends RealtimeSocketEvent {
  final Uint8List audioBytes;

  const RealtimeAudioEvent({required this.audioBytes});
}

class RealtimeSocketErrorEvent extends RealtimeSocketEvent {
  final String message;

  const RealtimeSocketErrorEvent({required this.message});
}

class RealtimeConnectionClosedEvent extends RealtimeSocketEvent {
  const RealtimeConnectionClosedEvent();
}
