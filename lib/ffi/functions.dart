import 'dart:ffi';
import 'dart:isolate';
import 'package:ffi/ffi.dart';

// FFI function type definitions for flutter_sequencer
typedef SetupEngineNative = Void Function(Int64 sampleRateCallbackPort);
typedef SetupEngineFunction = void Function(int sampleRateCallbackPort);

typedef DestroyEngineNative = Void Function();
typedef DestroyEngineFunction = void Function();

typedef AddTrackSf2Native = Void Function(Pointer<Utf8> path, Bool isAsset, Int32 presetIndex, Int64 callbackPort);
typedef AddTrackSf2Function = void Function(Pointer<Utf8> path, bool isAsset, int presetIndex, int callbackPort);

typedef AddTrackSfzNative = Void Function(Pointer<Utf8> sfzPath, Pointer<Utf8> tuningPath, Int64 callbackPort);
typedef AddTrackSfzFunction = void Function(Pointer<Utf8> sfzPath, Pointer<Utf8> tuningPath, int callbackPort);

typedef AddTrackSfzStringNative = Void Function(Pointer<Utf8> sampleRoot, Pointer<Utf8> sfzString, Pointer<Utf8> tuningString, Int64 callbackPort);
typedef AddTrackSfzStringFunction = void Function(Pointer<Utf8> sampleRoot, Pointer<Utf8> sfzString, Pointer<Utf8> tuningString, int callbackPort);

typedef RemoveTrackNative = Void Function(Uint32 trackIndex);
typedef RemoveTrackFunction = void Function(int trackIndex);

typedef ResetTrackNative = Void Function(Uint32 trackIndex);
typedef ResetTrackFunction = void Function(int trackIndex);

typedef GetPositionNative = Uint32 Function();
typedef GetPositionFunction = int Function();

typedef GetTrackVolumeNative = Float Function(Uint32 trackIndex);
typedef GetTrackVolumeFunction = double Function(int trackIndex);

typedef GetLastRenderTimeUsNative = Uint64 Function();
typedef GetLastRenderTimeUsFunction = int Function();

typedef GetBufferAvailableCountNative = Uint32 Function(Uint32 trackIndex);
typedef GetBufferAvailableCountFunction = int Function(int trackIndex);

typedef HandleEventsNowNative = Void Function(Uint32 trackIndex, Pointer<Uint8> eventData, Uint32 eventsCount);
typedef HandleEventsNowFunction = void Function(int trackIndex, Pointer<Uint8> eventData, int eventsCount);

typedef ScheduleEventsNative = Uint32 Function(Uint32 trackIndex, Pointer<Uint8> eventData, Uint32 eventsCount);
typedef ScheduleEventsFunction = int Function(int trackIndex, Pointer<Uint8> eventData, int eventsCount);

typedef ClearEventsNative = Void Function(Uint32 trackIndex, Uint32 fromFrame);
typedef ClearEventsFunction = void Function(int trackIndex, int fromFrame);

typedef EnginePlayNative = Void Function();
typedef EnginePlayFunction = void Function();

typedef EnginePauseNative = Void Function();
typedef EnginePauseFunction = void Function();