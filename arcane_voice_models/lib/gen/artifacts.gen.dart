// GENERATED – do not modify by hand

// ignore_for_file: camel_case_types
// ignore_for_file: non_constant_identifier_names
// ignore_for_file: constant_identifier_names
// ignore_for_file: library_private_types_in_public_api
// ignore_for_file: unused_element
import "package:arcane_voice_models/src/realtime/realtime_protocol_messages.dart";import "package:arcane_voice_models/src/realtime/realtime_provider_definition.dart";import "package:arcane_voice_models/src/realtime/realtime_tool_definition.dart";import "package:arcane_voice_models/src/realtime/realtime_turn_detection_config.dart";import "package:artifact/artifact.dart";import "dart:core";
typedef _0=ArtifactCodecUtil;typedef _1=ArtifactDataUtil;typedef _2=ArtifactSecurityUtil;typedef _3=ArtifactReflection;typedef _4=ArtifactMirror;typedef _5=Map<String,dynamic>;typedef _6=List<String>;typedef _7=String;typedef _8=dynamic;typedef _9=int;typedef _a=ArtifactModelExporter;typedef _b=ArgumentError;typedef _c=Exception;typedef _d=RealtimeSessionStartRequest;typedef _e=RealtimeSessionStopRequest;typedef _f=RealtimeSessionInterruptRequest;typedef _g=RealtimeTextInputRequest;typedef _h=RealtimePingRequest;typedef _i=RealtimeToolResultRequest;typedef _j=RealtimeConnectionReadyEvent;typedef _k=RealtimeToolCallEvent;typedef _l=RealtimeSessionStartedEvent;typedef _m=RealtimeSessionStateEvent;typedef _n=RealtimeSessionStoppedEvent;typedef _o=RealtimePongEvent;typedef _p=RealtimeErrorEvent;typedef _q=RealtimeInputSpeechStartedEvent;typedef _r=RealtimeInputSpeechStoppedEvent;typedef _s=RealtimeTranscriptUserDeltaEvent;typedef _t=RealtimeTranscriptUserFinalEvent;typedef _u=RealtimeTranscriptAssistantDeltaEvent;typedef _v=RealtimeTranscriptAssistantFinalEvent;typedef _w=RealtimeTranscriptAssistantDiscardEvent;typedef _x=RealtimeToolStartedEvent;typedef _y=RealtimeToolCompletedEvent;typedef _z=RealtimeProviderDefinition;typedef _10=RealtimeToolDefinition;typedef _11=RealtimeTurnDetectionConfig;typedef _12=ArtifactModelImporter<RealtimeSessionStartRequest>;typedef _13=List;typedef _14=bool;typedef _15=List<RealtimeToolDefinition>;typedef _16=ArtifactModelImporter<RealtimeSessionStopRequest>;typedef _17=ArtifactModelImporter<RealtimeSessionInterruptRequest>;typedef _18=ArtifactModelImporter<RealtimeTextInputRequest>;typedef _19=ArtifactModelImporter<RealtimePingRequest>;typedef _1a=ArtifactModelImporter<RealtimeToolResultRequest>;typedef _1b=ArtifactModelImporter<RealtimeConnectionReadyEvent>;typedef _1c=ArtifactModelImporter<RealtimeToolCallEvent>;typedef _1d=ArtifactModelImporter<RealtimeSessionStartedEvent>;typedef _1e=ArtifactModelImporter<RealtimeSessionStateEvent>;typedef _1f=ArtifactModelImporter<RealtimeSessionStoppedEvent>;typedef _1g=ArtifactModelImporter<RealtimePongEvent>;typedef _1h=ArtifactModelImporter<RealtimeErrorEvent>;typedef _1i=ArtifactModelImporter<RealtimeInputSpeechStartedEvent>;typedef _1j=ArtifactModelImporter<RealtimeInputSpeechStoppedEvent>;typedef _1k=ArtifactModelImporter<RealtimeTranscriptUserDeltaEvent>;typedef _1l=ArtifactModelImporter<RealtimeTranscriptUserFinalEvent>;typedef _1m=ArtifactModelImporter<RealtimeTranscriptAssistantDeltaEvent>;typedef _1n=ArtifactModelImporter<RealtimeTranscriptAssistantFinalEvent>;typedef _1o=ArtifactModelImporter<RealtimeTranscriptAssistantDiscardEvent>;typedef _1p=ArtifactModelImporter<RealtimeToolStartedEvent>;typedef _1q=ArtifactModelImporter<RealtimeToolCompletedEvent>;typedef _1r=ArtifactModelImporter<RealtimeProviderDefinition>;typedef _1s=ArtifactModelImporter<RealtimeToolDefinition>;typedef _1t=ArtifactModelImporter<RealtimeTurnDetectionConfig>;typedef _1u=ArtifactAccessor;typedef _1v=List<dynamic>;
_b __x(_7 c,_7 f)=>_b('${_S[50]}$c.$f');
const _6 _S=['type','provider','model','voice','instructions','inputSampleRate','outputSampleRate','turnDetection','clientTools','RealtimeSessionStartRequest','text','RealtimeTextInputRequest','requestId','outputJson','error','RealtimeToolResultRequest','providers','defaultModel','defaultVoice','RealtimeConnectionReadyEvent','name','argumentsJson','RealtimeToolCallEvent','RealtimeSessionStartedEvent','state','RealtimeSessionStateEvent','message','code','RealtimeErrorEvent','RealtimeTranscriptUserDeltaEvent','RealtimeTranscriptUserFinalEvent','RealtimeTranscriptAssistantDeltaEvent','RealtimeTranscriptAssistantFinalEvent','callId','executionTarget','RealtimeToolStartedEvent','success','RealtimeToolCompletedEvent','label','voices','RealtimeProviderDefinition','description','parametersJson','RealtimeToolDefinition','speechThresholdRms','speechStartMs','speechEndSilenceMs','preSpeechMs','bargeInEnabled','arcane_voice_models','Missing required '];const _1v _V=[RealtimeMessageType.sessionStart,24000,RealtimeTurnDetectionConfig(),RealtimeMessageType.sessionStop,RealtimeMessageType.sessionInterrupt,RealtimeMessageType.textInput,RealtimeMessageType.ping,RealtimeMessageType.toolResult,RealtimeMessageType.connectionReady,RealtimeMessageType.toolCall,RealtimeMessageType.sessionStarted,RealtimeMessageType.sessionState,RealtimeMessageType.sessionStopped,RealtimeMessageType.pong,RealtimeMessageType.error,RealtimeMessageType.inputSpeechStarted,RealtimeMessageType.inputSpeechStopped,RealtimeMessageType.transcriptUserDelta,RealtimeMessageType.transcriptUserFinal,RealtimeMessageType.transcriptAssistantDelta,RealtimeMessageType.transcriptAssistantFinal,RealtimeMessageType.transcriptAssistantDiscard,RealtimeMessageType.toolStarted,RealtimeMessageType.toolCompleted,true];const _14 _T=true;const _14 _F=false;_9 _ = ((){if(!_1u.$i(_S[49])){_1u.$r(_S[49],_1u(isArtifact: $isArtifact,artifactMirror:{},constructArtifact:$constructArtifact,artifactToMap:$artifactToMap,artifactFromMap:$artifactFromMap));}return 0;})();

extension $RealtimeSessionStartRequest on _d{
  _d get _H=>this;
  _a get to=>_a(toMap);
  _5 toMap(){_;return<_7,_8>{_S[0]:_0.ea(type),_S[1]:_0.ea(provider),_S[2]:_0.ea(model),_S[3]:_0.ea(voice),_S[4]:_0.ea(instructions),_S[5]:_0.ea(inputSampleRate),_S[6]:_0.ea(outputSampleRate),_S[7]:turnDetection.toMap(),_S[8]:clientTools.$m((e)=> e.toMap()).$l,}.$nn;}
  static _12 get from=>_12(fromMap);
  static _d fromMap(_5 r){_;_5 m=r.$nn;return _d(type: m.$c(_S[0]) ?  _0.da(m[_S[0]], _7) as _7 : _V[0],provider: m.$c(_S[1])? _0.da(m[_S[1]], _7) as _7:throw __x(_S[9],_S[1]),model: m.$c(_S[2])? _0.da(m[_S[2]], _7) as _7:throw __x(_S[9],_S[2]),voice: m.$c(_S[3])? _0.da(m[_S[3]], _7) as _7:throw __x(_S[9],_S[3]),instructions: m.$c(_S[4])? _0.da(m[_S[4]], _7) as _7:throw __x(_S[9],_S[4]),inputSampleRate: m.$c(_S[5]) ?  _0.da(m[_S[5]], _9) as _9 : _V[1],outputSampleRate: m.$c(_S[6]) ?  _0.da(m[_S[6]], _9) as _9 : _V[1],turnDetection: m.$c(_S[7]) ?  _1.a<_11>(m[_S[7]],(m)=>$RealtimeTurnDetectionConfig.fromMap(m))! : _V[2],clientTools: m.$c(_S[8])? (m[_S[8]] as _13).$m((e)=> _1.a<_10>(e,(m)=>$RealtimeToolDefinition.fromMap(m))!).$l:throw __x(_S[9],_S[8]),);}
  _d copyWith({_7? type,_14 resetType=_F,_7? provider,_7? model,_7? voice,_7? instructions,_9? inputSampleRate,_14 resetInputSampleRate=_F,_9? deltaInputSampleRate,_9? outputSampleRate,_14 resetOutputSampleRate=_F,_9? deltaOutputSampleRate,_11? turnDetection,_14 resetTurnDetection=_F,_15? clientTools,_15? appendClientTools,_15? removeClientTools,})=>_d(type: resetType?_V[0]:(type??_H.type),provider: provider??_H.provider,model: model??_H.model,voice: voice??_H.voice,instructions: instructions??_H.instructions,inputSampleRate: deltaInputSampleRate!=null?(inputSampleRate??_H.inputSampleRate)+deltaInputSampleRate:resetInputSampleRate?_V[1]:(inputSampleRate??_H.inputSampleRate),outputSampleRate: deltaOutputSampleRate!=null?(outputSampleRate??_H.outputSampleRate)+deltaOutputSampleRate:resetOutputSampleRate?_V[1]:(outputSampleRate??_H.outputSampleRate),turnDetection: resetTurnDetection?_V[2]:(turnDetection??_H.turnDetection),clientTools: (clientTools??_H.clientTools).$u(appendClientTools,removeClientTools),);
  static _d get newInstance=>_d(provider: '',model: '',voice: '',instructions: '',clientTools: [],);
}
extension $RealtimeSessionStopRequest on _e{
  _e get _H=>this;
  _a get to=>_a(toMap);
  _5 toMap(){_;return<_7,_8>{_S[0]:_0.ea(type),}.$nn;}
  static _16 get from=>_16(fromMap);
  static _e fromMap(_5 r){_;_5 m=r.$nn;return _e(type: m.$c(_S[0]) ?  _0.da(m[_S[0]], _7) as _7 : _V[3],);}
  _e copyWith({_7? type,_14 resetType=_F,})=>_e(type: resetType?_V[3]:(type??_H.type),);
  static _e get newInstance=>_e();
}
extension $RealtimeSessionInterruptRequest on _f{
  _f get _H=>this;
  _a get to=>_a(toMap);
  _5 toMap(){_;return<_7,_8>{_S[0]:_0.ea(type),}.$nn;}
  static _17 get from=>_17(fromMap);
  static _f fromMap(_5 r){_;_5 m=r.$nn;return _f(type: m.$c(_S[0]) ?  _0.da(m[_S[0]], _7) as _7 : _V[4],);}
  _f copyWith({_7? type,_14 resetType=_F,})=>_f(type: resetType?_V[4]:(type??_H.type),);
  static _f get newInstance=>_f();
}
extension $RealtimeTextInputRequest on _g{
  _g get _H=>this;
  _a get to=>_a(toMap);
  _5 toMap(){_;return<_7,_8>{_S[0]:_0.ea(type),_S[10]:_0.ea(text),}.$nn;}
  static _18 get from=>_18(fromMap);
  static _g fromMap(_5 r){_;_5 m=r.$nn;return _g(type: m.$c(_S[0]) ?  _0.da(m[_S[0]], _7) as _7 : _V[5],text: m.$c(_S[10])? _0.da(m[_S[10]], _7) as _7:throw __x(_S[11],_S[10]),);}
  _g copyWith({_7? type,_14 resetType=_F,_7? text,})=>_g(type: resetType?_V[5]:(type??_H.type),text: text??_H.text,);
  static _g get newInstance=>_g(text: '',);
}
extension $RealtimePingRequest on _h{
  _h get _H=>this;
  _a get to=>_a(toMap);
  _5 toMap(){_;return<_7,_8>{_S[0]:_0.ea(type),}.$nn;}
  static _19 get from=>_19(fromMap);
  static _h fromMap(_5 r){_;_5 m=r.$nn;return _h(type: m.$c(_S[0]) ?  _0.da(m[_S[0]], _7) as _7 : _V[6],);}
  _h copyWith({_7? type,_14 resetType=_F,})=>_h(type: resetType?_V[6]:(type??_H.type),);
  static _h get newInstance=>_h();
}
extension $RealtimeToolResultRequest on _i{
  _i get _H=>this;
  _a get to=>_a(toMap);
  _5 toMap(){_;return<_7,_8>{_S[0]:_0.ea(type),_S[12]:_0.ea(requestId),_S[13]:_0.ea(outputJson),_S[14]:_0.ea(error),}.$nn;}
  static _1a get from=>_1a(fromMap);
  static _i fromMap(_5 r){_;_5 m=r.$nn;return _i(type: m.$c(_S[0]) ?  _0.da(m[_S[0]], _7) as _7 : _V[7],requestId: m.$c(_S[12])? _0.da(m[_S[12]], _7) as _7:throw __x(_S[15],_S[12]),outputJson: m.$c(_S[13])? _0.da(m[_S[13]], _7) as _7:throw __x(_S[15],_S[13]),error: m.$c(_S[14]) ?  _0.da(m[_S[14]], _7) as _7? : null,);}
  _i copyWith({_7? type,_14 resetType=_F,_7? requestId,_7? outputJson,_7? error,_14 deleteError=_F,})=>_i(type: resetType?_V[7]:(type??_H.type),requestId: requestId??_H.requestId,outputJson: outputJson??_H.outputJson,error: deleteError?null:(error??_H.error),);
  static _i get newInstance=>_i(requestId: '',outputJson: '',);
}
extension $RealtimeConnectionReadyEvent on _j{
  _j get _H=>this;
  _a get to=>_a(toMap);
  _5 toMap(){_;return<_7,_8>{_S[0]:_0.ea(type),_S[16]:providers.$m((e)=> _0.ea(e)).$l,_S[17]:_0.ea(defaultModel),_S[18]:_0.ea(defaultVoice),}.$nn;}
  static _1b get from=>_1b(fromMap);
  static _j fromMap(_5 r){_;_5 m=r.$nn;return _j(type: m.$c(_S[0]) ?  _0.da(m[_S[0]], _7) as _7 : _V[8],providers: m.$c(_S[16])? (m[_S[16]] as _13).$m((e)=> _0.da(e, _7) as _7).$l:throw __x(_S[19],_S[16]),defaultModel: m.$c(_S[17])? _0.da(m[_S[17]], _7) as _7:throw __x(_S[19],_S[17]),defaultVoice: m.$c(_S[18])? _0.da(m[_S[18]], _7) as _7:throw __x(_S[19],_S[18]),);}
  _j copyWith({_7? type,_14 resetType=_F,_6? providers,_6? appendProviders,_6? removeProviders,_7? defaultModel,_7? defaultVoice,})=>_j(type: resetType?_V[8]:(type??_H.type),providers: (providers??_H.providers).$u(appendProviders,removeProviders),defaultModel: defaultModel??_H.defaultModel,defaultVoice: defaultVoice??_H.defaultVoice,);
  static _j get newInstance=>_j(providers: [],defaultModel: '',defaultVoice: '',);
}
extension $RealtimeToolCallEvent on _k{
  _k get _H=>this;
  _a get to=>_a(toMap);
  _5 toMap(){_;return<_7,_8>{_S[0]:_0.ea(type),_S[12]:_0.ea(requestId),_S[20]:_0.ea(name),_S[21]:_0.ea(argumentsJson),}.$nn;}
  static _1c get from=>_1c(fromMap);
  static _k fromMap(_5 r){_;_5 m=r.$nn;return _k(type: m.$c(_S[0]) ?  _0.da(m[_S[0]], _7) as _7 : _V[9],requestId: m.$c(_S[12])? _0.da(m[_S[12]], _7) as _7:throw __x(_S[22],_S[12]),name: m.$c(_S[20])? _0.da(m[_S[20]], _7) as _7:throw __x(_S[22],_S[20]),argumentsJson: m.$c(_S[21])? _0.da(m[_S[21]], _7) as _7:throw __x(_S[22],_S[21]),);}
  _k copyWith({_7? type,_14 resetType=_F,_7? requestId,_7? name,_7? argumentsJson,})=>_k(type: resetType?_V[9]:(type??_H.type),requestId: requestId??_H.requestId,name: name??_H.name,argumentsJson: argumentsJson??_H.argumentsJson,);
  static _k get newInstance=>_k(requestId: '',name: '',argumentsJson: '',);
}
extension $RealtimeSessionStartedEvent on _l{
  _l get _H=>this;
  _a get to=>_a(toMap);
  _5 toMap(){_;return<_7,_8>{_S[0]:_0.ea(type),_S[1]:_0.ea(provider),_S[2]:_0.ea(model),_S[3]:_0.ea(voice),_S[5]:_0.ea(inputSampleRate),_S[6]:_0.ea(outputSampleRate),}.$nn;}
  static _1d get from=>_1d(fromMap);
  static _l fromMap(_5 r){_;_5 m=r.$nn;return _l(type: m.$c(_S[0]) ?  _0.da(m[_S[0]], _7) as _7 : _V[10],provider: m.$c(_S[1])? _0.da(m[_S[1]], _7) as _7:throw __x(_S[23],_S[1]),model: m.$c(_S[2])? _0.da(m[_S[2]], _7) as _7:throw __x(_S[23],_S[2]),voice: m.$c(_S[3])? _0.da(m[_S[3]], _7) as _7:throw __x(_S[23],_S[3]),inputSampleRate: m.$c(_S[5])? _0.da(m[_S[5]], _9) as _9:throw __x(_S[23],_S[5]),outputSampleRate: m.$c(_S[6])? _0.da(m[_S[6]], _9) as _9:throw __x(_S[23],_S[6]),);}
  _l copyWith({_7? type,_14 resetType=_F,_7? provider,_7? model,_7? voice,_9? inputSampleRate,_9? deltaInputSampleRate,_9? outputSampleRate,_9? deltaOutputSampleRate,})=>_l(type: resetType?_V[10]:(type??_H.type),provider: provider??_H.provider,model: model??_H.model,voice: voice??_H.voice,inputSampleRate: deltaInputSampleRate!=null?(inputSampleRate??_H.inputSampleRate)+deltaInputSampleRate:inputSampleRate??_H.inputSampleRate,outputSampleRate: deltaOutputSampleRate!=null?(outputSampleRate??_H.outputSampleRate)+deltaOutputSampleRate:outputSampleRate??_H.outputSampleRate,);
  static _l get newInstance=>_l(provider: '',model: '',voice: '',inputSampleRate: 0,outputSampleRate: 0,);
}
extension $RealtimeSessionStateEvent on _m{
  _m get _H=>this;
  _a get to=>_a(toMap);
  _5 toMap(){_;return<_7,_8>{_S[0]:_0.ea(type),_S[24]:_0.ea(state),_S[1]:_0.ea(provider),}.$nn;}
  static _1e get from=>_1e(fromMap);
  static _m fromMap(_5 r){_;_5 m=r.$nn;return _m(type: m.$c(_S[0]) ?  _0.da(m[_S[0]], _7) as _7 : _V[11],state: m.$c(_S[24])? _0.da(m[_S[24]], _7) as _7:throw __x(_S[25],_S[24]),provider: m.$c(_S[1]) ?  _0.da(m[_S[1]], _7) as _7? : null,);}
  _m copyWith({_7? type,_14 resetType=_F,_7? state,_7? provider,_14 deleteProvider=_F,})=>_m(type: resetType?_V[11]:(type??_H.type),state: state??_H.state,provider: deleteProvider?null:(provider??_H.provider),);
  static _m get newInstance=>_m(state: '',);
}
extension $RealtimeSessionStoppedEvent on _n{
  _n get _H=>this;
  _a get to=>_a(toMap);
  _5 toMap(){_;return<_7,_8>{_S[0]:_0.ea(type),}.$nn;}
  static _1f get from=>_1f(fromMap);
  static _n fromMap(_5 r){_;_5 m=r.$nn;return _n(type: m.$c(_S[0]) ?  _0.da(m[_S[0]], _7) as _7 : _V[12],);}
  _n copyWith({_7? type,_14 resetType=_F,})=>_n(type: resetType?_V[12]:(type??_H.type),);
  static _n get newInstance=>_n();
}
extension $RealtimePongEvent on _o{
  _o get _H=>this;
  _a get to=>_a(toMap);
  _5 toMap(){_;return<_7,_8>{_S[0]:_0.ea(type),}.$nn;}
  static _1g get from=>_1g(fromMap);
  static _o fromMap(_5 r){_;_5 m=r.$nn;return _o(type: m.$c(_S[0]) ?  _0.da(m[_S[0]], _7) as _7 : _V[13],);}
  _o copyWith({_7? type,_14 resetType=_F,})=>_o(type: resetType?_V[13]:(type??_H.type),);
  static _o get newInstance=>_o();
}
extension $RealtimeErrorEvent on _p{
  _p get _H=>this;
  _a get to=>_a(toMap);
  _5 toMap(){_;return<_7,_8>{_S[0]:_0.ea(type),_S[26]:_0.ea(message),_S[27]:_0.ea(code),}.$nn;}
  static _1h get from=>_1h(fromMap);
  static _p fromMap(_5 r){_;_5 m=r.$nn;return _p(type: m.$c(_S[0]) ?  _0.da(m[_S[0]], _7) as _7 : _V[14],message: m.$c(_S[26])? _0.da(m[_S[26]], _7) as _7:throw __x(_S[28],_S[26]),code: m.$c(_S[27]) ?  _0.da(m[_S[27]], _7) as _7? : null,);}
  _p copyWith({_7? type,_14 resetType=_F,_7? message,_7? code,_14 deleteCode=_F,})=>_p(type: resetType?_V[14]:(type??_H.type),message: message??_H.message,code: deleteCode?null:(code??_H.code),);
  static _p get newInstance=>_p(message: '',);
}
extension $RealtimeInputSpeechStartedEvent on _q{
  _q get _H=>this;
  _a get to=>_a(toMap);
  _5 toMap(){_;return<_7,_8>{_S[0]:_0.ea(type),}.$nn;}
  static _1i get from=>_1i(fromMap);
  static _q fromMap(_5 r){_;_5 m=r.$nn;return _q(type: m.$c(_S[0]) ?  _0.da(m[_S[0]], _7) as _7 : _V[15],);}
  _q copyWith({_7? type,_14 resetType=_F,})=>_q(type: resetType?_V[15]:(type??_H.type),);
  static _q get newInstance=>_q();
}
extension $RealtimeInputSpeechStoppedEvent on _r{
  _r get _H=>this;
  _a get to=>_a(toMap);
  _5 toMap(){_;return<_7,_8>{_S[0]:_0.ea(type),}.$nn;}
  static _1j get from=>_1j(fromMap);
  static _r fromMap(_5 r){_;_5 m=r.$nn;return _r(type: m.$c(_S[0]) ?  _0.da(m[_S[0]], _7) as _7 : _V[16],);}
  _r copyWith({_7? type,_14 resetType=_F,})=>_r(type: resetType?_V[16]:(type??_H.type),);
  static _r get newInstance=>_r();
}
extension $RealtimeTranscriptUserDeltaEvent on _s{
  _s get _H=>this;
  _a get to=>_a(toMap);
  _5 toMap(){_;return<_7,_8>{_S[0]:_0.ea(type),_S[10]:_0.ea(text),}.$nn;}
  static _1k get from=>_1k(fromMap);
  static _s fromMap(_5 r){_;_5 m=r.$nn;return _s(type: m.$c(_S[0]) ?  _0.da(m[_S[0]], _7) as _7 : _V[17],text: m.$c(_S[10])? _0.da(m[_S[10]], _7) as _7:throw __x(_S[29],_S[10]),);}
  _s copyWith({_7? type,_14 resetType=_F,_7? text,})=>_s(type: resetType?_V[17]:(type??_H.type),text: text??_H.text,);
  static _s get newInstance=>_s(text: '',);
}
extension $RealtimeTranscriptUserFinalEvent on _t{
  _t get _H=>this;
  _a get to=>_a(toMap);
  _5 toMap(){_;return<_7,_8>{_S[0]:_0.ea(type),_S[10]:_0.ea(text),}.$nn;}
  static _1l get from=>_1l(fromMap);
  static _t fromMap(_5 r){_;_5 m=r.$nn;return _t(type: m.$c(_S[0]) ?  _0.da(m[_S[0]], _7) as _7 : _V[18],text: m.$c(_S[10])? _0.da(m[_S[10]], _7) as _7:throw __x(_S[30],_S[10]),);}
  _t copyWith({_7? type,_14 resetType=_F,_7? text,})=>_t(type: resetType?_V[18]:(type??_H.type),text: text??_H.text,);
  static _t get newInstance=>_t(text: '',);
}
extension $RealtimeTranscriptAssistantDeltaEvent on _u{
  _u get _H=>this;
  _a get to=>_a(toMap);
  _5 toMap(){_;return<_7,_8>{_S[0]:_0.ea(type),_S[10]:_0.ea(text),}.$nn;}
  static _1m get from=>_1m(fromMap);
  static _u fromMap(_5 r){_;_5 m=r.$nn;return _u(type: m.$c(_S[0]) ?  _0.da(m[_S[0]], _7) as _7 : _V[19],text: m.$c(_S[10])? _0.da(m[_S[10]], _7) as _7:throw __x(_S[31],_S[10]),);}
  _u copyWith({_7? type,_14 resetType=_F,_7? text,})=>_u(type: resetType?_V[19]:(type??_H.type),text: text??_H.text,);
  static _u get newInstance=>_u(text: '',);
}
extension $RealtimeTranscriptAssistantFinalEvent on _v{
  _v get _H=>this;
  _a get to=>_a(toMap);
  _5 toMap(){_;return<_7,_8>{_S[0]:_0.ea(type),_S[10]:_0.ea(text),}.$nn;}
  static _1n get from=>_1n(fromMap);
  static _v fromMap(_5 r){_;_5 m=r.$nn;return _v(type: m.$c(_S[0]) ?  _0.da(m[_S[0]], _7) as _7 : _V[20],text: m.$c(_S[10])? _0.da(m[_S[10]], _7) as _7:throw __x(_S[32],_S[10]),);}
  _v copyWith({_7? type,_14 resetType=_F,_7? text,})=>_v(type: resetType?_V[20]:(type??_H.type),text: text??_H.text,);
  static _v get newInstance=>_v(text: '',);
}
extension $RealtimeTranscriptAssistantDiscardEvent on _w{
  _w get _H=>this;
  _a get to=>_a(toMap);
  _5 toMap(){_;return<_7,_8>{_S[0]:_0.ea(type),}.$nn;}
  static _1o get from=>_1o(fromMap);
  static _w fromMap(_5 r){_;_5 m=r.$nn;return _w(type: m.$c(_S[0]) ?  _0.da(m[_S[0]], _7) as _7 : _V[21],);}
  _w copyWith({_7? type,_14 resetType=_F,})=>_w(type: resetType?_V[21]:(type??_H.type),);
  static _w get newInstance=>_w();
}
extension $RealtimeToolStartedEvent on _x{
  _x get _H=>this;
  _a get to=>_a(toMap);
  _5 toMap(){_;return<_7,_8>{_S[0]:_0.ea(type),_S[33]:_0.ea(callId),_S[20]:_0.ea(name),_S[34]:_0.ea(executionTarget),}.$nn;}
  static _1p get from=>_1p(fromMap);
  static _x fromMap(_5 r){_;_5 m=r.$nn;return _x(type: m.$c(_S[0]) ?  _0.da(m[_S[0]], _7) as _7 : _V[22],callId: m.$c(_S[33])? _0.da(m[_S[33]], _7) as _7:throw __x(_S[35],_S[33]),name: m.$c(_S[20])? _0.da(m[_S[20]], _7) as _7:throw __x(_S[35],_S[20]),executionTarget: m.$c(_S[34])? _0.da(m[_S[34]], _7) as _7:throw __x(_S[35],_S[34]),);}
  _x copyWith({_7? type,_14 resetType=_F,_7? callId,_7? name,_7? executionTarget,})=>_x(type: resetType?_V[22]:(type??_H.type),callId: callId??_H.callId,name: name??_H.name,executionTarget: executionTarget??_H.executionTarget,);
  static _x get newInstance=>_x(callId: '',name: '',executionTarget: '',);
}
extension $RealtimeToolCompletedEvent on _y{
  _y get _H=>this;
  _a get to=>_a(toMap);
  _5 toMap(){_;return<_7,_8>{_S[0]:_0.ea(type),_S[33]:_0.ea(callId),_S[20]:_0.ea(name),_S[34]:_0.ea(executionTarget),_S[36]:_0.ea(success),_S[14]:_0.ea(error),}.$nn;}
  static _1q get from=>_1q(fromMap);
  static _y fromMap(_5 r){_;_5 m=r.$nn;return _y(type: m.$c(_S[0]) ?  _0.da(m[_S[0]], _7) as _7 : _V[23],callId: m.$c(_S[33])? _0.da(m[_S[33]], _7) as _7:throw __x(_S[37],_S[33]),name: m.$c(_S[20])? _0.da(m[_S[20]], _7) as _7:throw __x(_S[37],_S[20]),executionTarget: m.$c(_S[34])? _0.da(m[_S[34]], _7) as _7:throw __x(_S[37],_S[34]),success: m.$c(_S[36]) ?  _0.da(m[_S[36]], _14) as _14 : _V[24],error: m.$c(_S[14]) ?  _0.da(m[_S[14]], _7) as _7? : null,);}
  _y copyWith({_7? type,_14 resetType=_F,_7? callId,_7? name,_7? executionTarget,_14? success,_14 resetSuccess=_F,_7? error,_14 deleteError=_F,})=>_y(type: resetType?_V[23]:(type??_H.type),callId: callId??_H.callId,name: name??_H.name,executionTarget: executionTarget??_H.executionTarget,success: resetSuccess?_V[24]:(success??_H.success),error: deleteError?null:(error??_H.error),);
  static _y get newInstance=>_y(callId: '',name: '',executionTarget: '',);
}
extension $RealtimeProviderDefinition on _z{
  _z get _H=>this;
  _a get to=>_a(toMap);
  _5 toMap(){_;return<_7,_8>{'id':_0.ea(id),_S[38]:_0.ea(label),_S[17]:_0.ea(defaultModel),_S[18]:_0.ea(defaultVoice),_S[39]:voices.$m((e)=> _0.ea(e)).$l,}.$nn;}
  static _1r get from=>_1r(fromMap);
  static _z fromMap(_5 r){_;_5 m=r.$nn;return _z(id: m.$c('id')? _0.da(m['id'], _7) as _7:throw __x(_S[40],'id'),label: m.$c(_S[38])? _0.da(m[_S[38]], _7) as _7:throw __x(_S[40],_S[38]),defaultModel: m.$c(_S[17])? _0.da(m[_S[17]], _7) as _7:throw __x(_S[40],_S[17]),defaultVoice: m.$c(_S[18])? _0.da(m[_S[18]], _7) as _7:throw __x(_S[40],_S[18]),voices: m.$c(_S[39])? (m[_S[39]] as _13).$m((e)=> _0.da(e, _7) as _7).$l:throw __x(_S[40],_S[39]),);}
  _z copyWith({_7? id,_7? label,_7? defaultModel,_7? defaultVoice,_6? voices,_6? appendVoices,_6? removeVoices,})=>_z(id: id??_H.id,label: label??_H.label,defaultModel: defaultModel??_H.defaultModel,defaultVoice: defaultVoice??_H.defaultVoice,voices: (voices??_H.voices).$u(appendVoices,removeVoices),);
  static _z get newInstance=>_z(id: '',label: '',defaultModel: '',defaultVoice: '',voices: [],);
}
extension $RealtimeToolDefinition on _10{
  _10 get _H=>this;
  _a get to=>_a(toMap);
  _5 toMap(){_;return<_7,_8>{_S[20]:_0.ea(name),_S[41]:_0.ea(description),_S[42]:_0.ea(parametersJson),}.$nn;}
  static _1s get from=>_1s(fromMap);
  static _10 fromMap(_5 r){_;_5 m=r.$nn;return _10(name: m.$c(_S[20])? _0.da(m[_S[20]], _7) as _7:throw __x(_S[43],_S[20]),description: m.$c(_S[41])? _0.da(m[_S[41]], _7) as _7:throw __x(_S[43],_S[41]),parametersJson: m.$c(_S[42])? _0.da(m[_S[42]], _7) as _7:throw __x(_S[43],_S[42]),);}
  _10 copyWith({_7? name,_7? description,_7? parametersJson,})=>_10(name: name??_H.name,description: description??_H.description,parametersJson: parametersJson??_H.parametersJson,);
  static _10 get newInstance=>_10(name: '',description: '',parametersJson: '',);
}
extension $RealtimeTurnDetectionConfig on _11{
  _11 get _H=>this;
  _a get to=>_a(toMap);
  _5 toMap(){_;return<_7,_8>{_S[44]:_0.ea(speechThresholdRms),_S[45]:_0.ea(speechStartMs),_S[46]:_0.ea(speechEndSilenceMs),_S[47]:_0.ea(preSpeechMs),_S[48]:_0.ea(bargeInEnabled),}.$nn;}
  static _1t get from=>_1t(fromMap);
  static _11 fromMap(_5 r){_;_5 m=r.$nn;return _11(speechThresholdRms: m.$c(_S[44]) ?  _0.da(m[_S[44]], _9) as _9 : 100,speechStartMs: m.$c(_S[45]) ?  _0.da(m[_S[45]], _9) as _9 : 200,speechEndSilenceMs: m.$c(_S[46]) ?  _0.da(m[_S[46]], _9) as _9 : 900,preSpeechMs: m.$c(_S[47]) ?  _0.da(m[_S[47]], _9) as _9 : 300,bargeInEnabled: m.$c(_S[48]) ?  _0.da(m[_S[48]], _14) as _14 : _V[24],);}
  _11 copyWith({_9? speechThresholdRms,_14 resetSpeechThresholdRms=_F,_9? deltaSpeechThresholdRms,_9? speechStartMs,_14 resetSpeechStartMs=_F,_9? deltaSpeechStartMs,_9? speechEndSilenceMs,_14 resetSpeechEndSilenceMs=_F,_9? deltaSpeechEndSilenceMs,_9? preSpeechMs,_14 resetPreSpeechMs=_F,_9? deltaPreSpeechMs,_14? bargeInEnabled,_14 resetBargeInEnabled=_F,})=>_11(speechThresholdRms: deltaSpeechThresholdRms!=null?(speechThresholdRms??_H.speechThresholdRms)+deltaSpeechThresholdRms:resetSpeechThresholdRms?100:(speechThresholdRms??_H.speechThresholdRms),speechStartMs: deltaSpeechStartMs!=null?(speechStartMs??_H.speechStartMs)+deltaSpeechStartMs:resetSpeechStartMs?200:(speechStartMs??_H.speechStartMs),speechEndSilenceMs: deltaSpeechEndSilenceMs!=null?(speechEndSilenceMs??_H.speechEndSilenceMs)+deltaSpeechEndSilenceMs:resetSpeechEndSilenceMs?900:(speechEndSilenceMs??_H.speechEndSilenceMs),preSpeechMs: deltaPreSpeechMs!=null?(preSpeechMs??_H.preSpeechMs)+deltaPreSpeechMs:resetPreSpeechMs?300:(preSpeechMs??_H.preSpeechMs),bargeInEnabled: resetBargeInEnabled?_V[24]:(bargeInEnabled??_H.bargeInEnabled),);
  static _11 get newInstance=>_11();
}

bool $isArtifact(dynamic v)=>v==null?false : v is! Type ?$isArtifact(v.runtimeType):v == _d ||v == _e ||v == _f ||v == _g ||v == _h ||v == _i ||v == _j ||v == _k ||v == _l ||v == _m ||v == _n ||v == _o ||v == _p ||v == _q ||v == _r ||v == _s ||v == _t ||v == _u ||v == _v ||v == _w ||v == _x ||v == _y ||v == _z ||v == _10 ||v == _11 ;
T $constructArtifact<T>() => T==_d ?$RealtimeSessionStartRequest.newInstance as T :T==_e ?$RealtimeSessionStopRequest.newInstance as T :T==_f ?$RealtimeSessionInterruptRequest.newInstance as T :T==_g ?$RealtimeTextInputRequest.newInstance as T :T==_h ?$RealtimePingRequest.newInstance as T :T==_i ?$RealtimeToolResultRequest.newInstance as T :T==_j ?$RealtimeConnectionReadyEvent.newInstance as T :T==_k ?$RealtimeToolCallEvent.newInstance as T :T==_l ?$RealtimeSessionStartedEvent.newInstance as T :T==_m ?$RealtimeSessionStateEvent.newInstance as T :T==_n ?$RealtimeSessionStoppedEvent.newInstance as T :T==_o ?$RealtimePongEvent.newInstance as T :T==_p ?$RealtimeErrorEvent.newInstance as T :T==_q ?$RealtimeInputSpeechStartedEvent.newInstance as T :T==_r ?$RealtimeInputSpeechStoppedEvent.newInstance as T :T==_s ?$RealtimeTranscriptUserDeltaEvent.newInstance as T :T==_t ?$RealtimeTranscriptUserFinalEvent.newInstance as T :T==_u ?$RealtimeTranscriptAssistantDeltaEvent.newInstance as T :T==_v ?$RealtimeTranscriptAssistantFinalEvent.newInstance as T :T==_w ?$RealtimeTranscriptAssistantDiscardEvent.newInstance as T :T==_x ?$RealtimeToolStartedEvent.newInstance as T :T==_y ?$RealtimeToolCompletedEvent.newInstance as T :T==_z ?$RealtimeProviderDefinition.newInstance as T :T==_10 ?$RealtimeToolDefinition.newInstance as T :T==_11 ?$RealtimeTurnDetectionConfig.newInstance as T : throw _c();
_5 $artifactToMap(Object o)=>o is _d ?o.toMap():o is _e ?o.toMap():o is _f ?o.toMap():o is _g ?o.toMap():o is _h ?o.toMap():o is _i ?o.toMap():o is _j ?o.toMap():o is _k ?o.toMap():o is _l ?o.toMap():o is _m ?o.toMap():o is _n ?o.toMap():o is _o ?o.toMap():o is _p ?o.toMap():o is _q ?o.toMap():o is _r ?o.toMap():o is _s ?o.toMap():o is _t ?o.toMap():o is _u ?o.toMap():o is _v ?o.toMap():o is _w ?o.toMap():o is _x ?o.toMap():o is _y ?o.toMap():o is _z ?o.toMap():o is _10 ?o.toMap():o is _11 ?o.toMap():throw _c();
T $artifactFromMap<T>(_5 m)=>T==_d ?$RealtimeSessionStartRequest.fromMap(m) as T:T==_e ?$RealtimeSessionStopRequest.fromMap(m) as T:T==_f ?$RealtimeSessionInterruptRequest.fromMap(m) as T:T==_g ?$RealtimeTextInputRequest.fromMap(m) as T:T==_h ?$RealtimePingRequest.fromMap(m) as T:T==_i ?$RealtimeToolResultRequest.fromMap(m) as T:T==_j ?$RealtimeConnectionReadyEvent.fromMap(m) as T:T==_k ?$RealtimeToolCallEvent.fromMap(m) as T:T==_l ?$RealtimeSessionStartedEvent.fromMap(m) as T:T==_m ?$RealtimeSessionStateEvent.fromMap(m) as T:T==_n ?$RealtimeSessionStoppedEvent.fromMap(m) as T:T==_o ?$RealtimePongEvent.fromMap(m) as T:T==_p ?$RealtimeErrorEvent.fromMap(m) as T:T==_q ?$RealtimeInputSpeechStartedEvent.fromMap(m) as T:T==_r ?$RealtimeInputSpeechStoppedEvent.fromMap(m) as T:T==_s ?$RealtimeTranscriptUserDeltaEvent.fromMap(m) as T:T==_t ?$RealtimeTranscriptUserFinalEvent.fromMap(m) as T:T==_u ?$RealtimeTranscriptAssistantDeltaEvent.fromMap(m) as T:T==_v ?$RealtimeTranscriptAssistantFinalEvent.fromMap(m) as T:T==_w ?$RealtimeTranscriptAssistantDiscardEvent.fromMap(m) as T:T==_x ?$RealtimeToolStartedEvent.fromMap(m) as T:T==_y ?$RealtimeToolCompletedEvent.fromMap(m) as T:T==_z ?$RealtimeProviderDefinition.fromMap(m) as T:T==_10 ?$RealtimeToolDefinition.fromMap(m) as T:T==_11 ?$RealtimeTurnDetectionConfig.fromMap(m) as T:throw _c();
