import 'dart:async';
import 'dart:io';

import 'package:http/http.dart';
import 'package:arcane_voice_models/arcane_voice_models.dart';
import 'package:test/test.dart';

void main() {
  late String port;
  late String host;
  late Process p;

  setUp(() async {
    ServerSocket probe = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    port = probe.port.toString();
    host = 'http://127.0.0.1:$port';
    await probe.close();

    p = await Process.start(
      'dart',
      ['run', 'bin/server.dart'],
      environment: {'PORT': port},
    );

    StreamIterator<String> stdoutIterator = StreamIterator<String>(
      p.stdout.transform(SystemEncoding().decoder),
    );
    bool hasOutput = await stdoutIterator.moveNext();
    expect(hasOutput, isTrue);
    await stdoutIterator.cancel();
  });

  tearDown(() => p.kill());

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

  test('Twilio voice webhook returns connect stream TwiML', () async {
    Response response = await get(
      Uri.parse(
        '$host/twilio/voice?CallSid=CA123&AccountSid=AC123&From=%2B15551230000&To=%2B15557654321',
      ),
    );

    expect(response.statusCode, 200);
    expect(response.headers['content-type'], contains('text/xml'));
    expect(response.body, contains('<Response><Connect><Stream'));
    expect(response.body, contains('url="ws://127.0.0.1:$port/ws/twilio"'));
    expect(
      response.body,
      contains('<Parameter name="From" value="+15551230000" />'),
    );
    expect(
      response.body,
      contains('<Parameter name="To" value="+15557654321" />'),
    );
  });

  test('Twilio voice webhook accepts form encoded POST', () async {
    Response response = await post(
      Uri.parse('$host/twilio/voice'),
      headers: <String, String>{
        'content-type': 'application/x-www-form-urlencoded',
      },
      body: <String, String>{
        'CallSid': 'CA456',
        'From': '+15550001111',
        'To': '+15550002222',
      },
    );

    expect(response.statusCode, 200);
    expect(
      response.body,
      contains('<Parameter name="CallSid" value="CA456" />'),
    );
    expect(
      response.body,
      contains('<Parameter name="From" value="+15550001111" />'),
    );
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
