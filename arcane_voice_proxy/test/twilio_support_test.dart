import 'dart:convert';
import 'dart:typed_data';

import 'package:arcane_voice_proxy/arcane_voice_proxy.dart';
import 'package:test/test.dart';

void main() {
  test('TwiML connect stream escapes XML attributes', () {
    String twiml = TwilioTwiMl.connectStream(
      streamUrl: 'wss://voice.example.com/ws/twilio?bad=<no>',
      parameters: <String, String>{'From': '+15551230000', 'Name': 'A&B'},
    );

    expect(twiml, startsWith('<?xml version="1.0" encoding="UTF-8"?>'));
    expect(
      twiml,
      contains('url="wss://voice.example.com/ws/twilio?bad=&lt;no&gt;"'),
    );
    expect(twiml, contains('<Parameter name="Name" value="A&amp;B" />'));
  });

  test('Twilio start metadata becomes session context', () {
    ArcaneVoiceTwilioStreamMetadata metadata =
        ArcaneVoiceTwilioStreamMetadata.fromStartMessage(<String, Object?>{
          'event': 'start',
          'streamSid': 'MZ123',
          'start': <String, Object?>{
            'accountSid': 'AC123',
            'callSid': 'CA123',
            'customParameters': <String, Object?>{
              'From': '+15551230000',
              'To': '+15557654321',
            },
          },
        });

    ArcaneVoiceTwilioConfig config = const ArcaneVoiceTwilioConfig();
    RealtimeSessionStartRequest request = config.buildStartRequest(
      metadata: metadata,
    );
    Map<String, Object?> context =
        jsonDecode(request.sessionContextJson) as Map<String, Object?>;
    Map<String, Object?> twilio = context['twilio'] as Map<String, Object?>;

    expect(context['source'], 'twilio');
    expect(twilio['callSid'], 'CA123');
    expect(twilio['from'], '+15551230000');
    expect(twilio['to'], '+15557654321');

    ArcaneVoiceTwilioCallContext? callContext =
        ArcaneVoiceTwilioCallContext.maybeFromSessionContextJson(
          request.sessionContextJson,
        );
    expect(callContext, isNotNull);
    expect(callContext!.callerNumber, '+15551230000');
    expect(callContext.dialedNumber, '+15557654321');
    expect(callContext.customParameters['From'], '+15551230000');
  });

  test('Twilio call context is available from proxy session request', () {
    ArcaneVoiceTwilioCallContext context = const ArcaneVoiceTwilioCallContext(
      callSid: 'CA789',
      from: '+15551234567',
      to: '+15557654321',
      customParameters: <String, String>{'Direction': 'inbound'},
    );
    RealtimeSessionStartRequest startRequest = RealtimeSessionStartRequest(
      provider: RealtimeProviderCatalog.openAiId,
      model: RealtimeProviderCatalog.openAi.defaultModel,
      voice: RealtimeProviderCatalog.openAi.defaultVoice,
      instructions: '',
      sessionContextJson: jsonEncode(context.toSessionContext()),
      clientTools: const <RealtimeToolDefinition>[],
    );
    ArcaneVoiceProxySessionRequest sessionRequest =
        ArcaneVoiceProxySessionRequest(
          sessionId: 'session_123',
          connectionInfo: const ArcaneVoiceProxyConnectionInfo(),
          request: startRequest,
          receivedAt: DateTime(2026),
        );

    ArcaneVoiceTwilioCallContext? parsed =
        ArcaneVoiceTwilioCallContext.maybeFromSessionRequest(sessionRequest);

    expect(parsed, isNotNull);
    expect(parsed!.callSid, 'CA789');
    expect(parsed.callerNumber, '+15551234567');
    expect(parsed.dialedNumber, '+15557654321');
    expect(parsed.customParameters['Direction'], 'inbound');
  });

  test('mu-law input is decoded and resampled to provider PCM16', () {
    Uint8List silenceMulaw = Uint8List.fromList(List<int>.filled(160, 0xff));
    Uint8List pcm24k = TwilioAudioCodec.mulaw8kToPcm16(
      silenceMulaw,
      outputSampleRate: 24000,
    );

    expect(pcm24k.length, 960);
    expect(pcm24k.every((int value) => value == 0), isTrue);
  });

  test('provider PCM16 output is resampled and encoded for Twilio', () {
    Uint8List silencePcm24k = Uint8List(960);
    Uint8List mulaw8k = TwilioAudioCodec.pcm16ToMulaw8k(
      silencePcm24k,
      inputSampleRate: 24000,
    );

    expect(mulaw8k.length, 160);
    expect(mulaw8k.every((int value) => value == 0xff), isTrue);
  });
}
