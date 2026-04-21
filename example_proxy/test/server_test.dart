import 'dart:async';
import 'dart:io';

import 'package:arcane_voice_models/arcane_voice_models.dart';
import 'package:http/http.dart';
import 'package:test/test.dart';

void main() {
  late String port;
  late String host;
  late Process process;

  setUp(() async {
    ServerSocket probe = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    port = probe.port.toString();
    host = 'http://127.0.0.1:$port';
    await probe.close();

    process = await Process.start(
      'dart',
      ['run', 'bin/server.dart'],
      environment: <String, String>{'PORT': port},
    );

    StreamIterator<String> stdoutIterator = StreamIterator<String>(
      process.stdout.transform(SystemEncoding().decoder),
    );
    bool hasOutput = await stdoutIterator.moveNext();
    expect(hasOutput, isTrue);
    await stdoutIterator.cancel();
  });

  tearDown(() => process.kill());

  test('Root', () async {
    Response response = await get(Uri.parse('$host/'));
    expect(response.statusCode, 200);
    expect(response.body, contains('arcana-realtime-proxy'));
  });

  test('Health', () async {
    Response response = await get(Uri.parse('$host/health'));
    expect(response.statusCode, 200);
    expect(response.body, contains('"status":"ok"'));
  });

  test('404', () async {
    Response response = await get(Uri.parse('$host/foobar'));
    expect(response.statusCode, 404);
  });

  test('Realtime websocket accepts typed control messages', () async {
    WebSocket socket = await WebSocket.connect(
      'ws://127.0.0.1:$port/ws/realtime',
    );
    StreamIterator<dynamic> iterator = StreamIterator<dynamic>(socket);
    bool hasFirstMessage = await iterator.moveNext();
    RealtimeServerMessage firstMessage = RealtimeProtocolCodec.decodeServerJson(
      iterator.current as String,
    );

    expect(hasFirstMessage, isTrue);
    expect(firstMessage, isA<RealtimeConnectionReadyEvent>());

    socket.add(
      RealtimeProtocolCodec.encodeClientJson(const RealtimePingRequest()),
    );
    bool hasSecondMessage = await iterator.moveNext();
    RealtimeServerMessage secondMessage =
        RealtimeProtocolCodec.decodeServerJson(iterator.current as String);

    expect(hasSecondMessage, isTrue);
    expect(secondMessage, isA<RealtimePongEvent>());
    await iterator.cancel();
    await socket.close();
  });
}
