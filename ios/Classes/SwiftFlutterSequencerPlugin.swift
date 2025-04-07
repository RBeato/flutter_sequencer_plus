import Flutter
import Foundation
import AudioToolbox
import CoreAudio
import AVFoundation

var plugin: SwiftFlutterSequencerPlugin!
var Dart_PostCObject_DL: Dart_PostCObjectType? = nil

enum PluginError: Error {
    case engineNotReady
}

public class SwiftFlutterSequencerPlugin: NSObject, FlutterPlugin {
    public var registrar: FlutterPluginRegistrar!
    public var engine: CocoaEngine?
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "flutter_sequencer", binaryMessenger: registrar.messenger())
        plugin = SwiftFlutterSequencerPlugin()
        plugin.registrar = registrar
        registrar.addMethodCallDelegate(plugin, channel: channel)
    }
    
    public override init() {
        super.init()

        plugin = self
    }
    
    deinit {
        plugin = nil
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getPlatformVersion":
            result("iOS " + UIDevice.current.systemVersion)
        case "setupAssetManager":
            // No-op on iOS
            result(nil)
        case "normalizeAssetDir":
            guard let args = call.arguments as? [String: Any],
                  let assetDir = args["assetDir"] as? String else {
                result(FlutterError(code: "INVALID_ARGUMENTS", message: "assetDir is required", details: nil))
                return
            }
            
            // On iOS, we don't need to normalize the asset directory
            result(assetDir)
        case "listAudioUnits":
            listAudioUnits { audioUnits in
                result(audioUnits)
            }
        case "setupEngine":
            setupEngine(sampleRateCallbackPort: 0)
            if let engine = plugin.engine {
                let sampleRate = Int(AVAudioEngine().outputNode.outputFormat(forBus: 0).sampleRate)
                result(sampleRate)
            } else {
                result(FlutterError(code: "ENGINE_ERROR", message: "Failed to set up engine", details: nil))
            }
        case "addTrackSf2":
            guard let args = call.arguments as? [String: Any],
                  let path = args["path"] as? String,
                  let isAsset = args["isAsset"] as? Bool else {
                result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid arguments", details: nil))
                return
            }
            
            let presetIndex = args["presetIndex"] as? Int ?? 0
            
            plugin.engine!.addTrackSf2(sf2Path: path, isAsset: isAsset, presetIndex: Int32(presetIndex)) { trackId in
                result(Int(trackId))
            }
        case "play":
            enginePlay()
            result(nil)
        case "pause":
            enginePause()
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
}

// Called from method channel
func normalizeAssetDir(registrar: FlutterPluginRegistrar, assetDir: String) -> String? {
    let key = registrar.lookupKey(forAsset: assetDir)
    let path = Bundle.main.path(forResource: key, ofType: nil)
    
    return path
}

// Called from method channel
func listAudioUnits(completion: @escaping ([String]) -> Void) {
    AudioUnitUtils.loadAudioUnits { loadedComponents in
        let ids = loadedComponents.map(AudioUnitUtils.getAudioUnitId)
        
        completion(ids)
    }
}

// Called from method channel
func setupEngine() -> Int {
    plugin.engine = CocoaEngine(sampleRateCallbackPort: 0, registrar: plugin.registrar)
    return Int(AVAudioEngine().outputNode.outputFormat(forBus: 0).sampleRate)
}

@_cdecl("setup_engine")
func setupEngine(sampleRateCallbackPort: Dart_Port) {
    plugin.engine = CocoaEngine(sampleRateCallbackPort: sampleRateCallbackPort, registrar: plugin.registrar)
}

@_cdecl("destroy_engine")
func destroyEngine() {
    plugin.engine = nil
}

@_cdecl("add_track_sfz")
func addTrackSfz(sfzPath: UnsafePointer<CChar>, tuningPath: UnsafePointer<CChar>, callbackPort: Dart_Port) {
    plugin.engine!.addTrackSfz(sfzPath: sfzPath, tuningPath: tuningPath) { trackIndex in
        callbackToDartInt32(callbackPort, trackIndex)
    }
}

@_cdecl("add_track_sfz_string")
func addTrackSfzString(sampleRoot: UnsafePointer<CChar>, sfzString: UnsafePointer<CChar>, tuningString: UnsafePointer<CChar>, callbackPort: Dart_Port) {
    plugin.engine!.addTrackSfzString(sampleRoot: sampleRoot, sfzString: sfzString, tuningString: tuningString) { trackIndex in
        callbackToDartInt32(callbackPort, trackIndex)
    }
}

@_cdecl("add_track_sf2")
func addTrackSf2(path: UnsafePointer<CChar>, isAsset: Bool, presetIndex: Int32, callbackPort: Dart_Port) {
    plugin.engine!.addTrackSf2(sf2Path: String(cString: path), isAsset: isAsset, presetIndex: presetIndex) { trackIndex in
        callbackToDartInt32(callbackPort, trackIndex)
    }
}

// Called from method channel
func addTrackAudioUnit(_ audioUnitId: String, completion: @escaping (track_index_t) -> Void) {
    plugin.engine!.addTrackAudioUnit(audioUnitId: audioUnitId, completion: completion)
}

@_cdecl("remove_track")
func removeTrack(trackIndex: track_index_t) {
    let _ = plugin.engine!.removeTrack(trackIndex: trackIndex)
}

@_cdecl("reset_track")
func resetTrack(trackIndex: track_index_t) {
    SchedulerResetTrack(plugin.engine!.scheduler, trackIndex)
}

@_cdecl("get_position")
func getPosition() -> position_frame_t {
    return SchedulerGetPosition(plugin.engine!.scheduler)
}

@_cdecl("get_track_volume")
func getTrackVolume(trackIndex: track_index_t) -> Float32 {
    return SchedulerGetTrackVolume(plugin.engine!.scheduler, trackIndex)
}

@_cdecl("get_last_render_time_us")
func getLastRenderTimeUs() -> UInt64 {
    return SchedulerGetLastRenderTimeUs(plugin.engine!.scheduler)
}

@_cdecl("get_buffer_available_count")
func getBufferAvailableCount(trackIndex: track_index_t) -> UInt32 {
    return SchedulerGetBufferAvailableCount(plugin.engine!.scheduler, trackIndex)
}

@_cdecl("handle_events_now")
func handleEventsNow(trackIndex: track_index_t, eventData: UnsafePointer<UInt8>, eventsCount: UInt32) {
    let events = UnsafeMutablePointer<SchedulerEvent>.allocate(capacity: Int(eventsCount))
    
    rawEventDataToEvents(eventData, eventsCount, events)
    
    SchedulerHandleEventsNow(plugin.engine!.scheduler, trackIndex, UnsafePointer(events), eventsCount)
    
    events.deallocate()
}

@_cdecl("schedule_events")
func scheduleEvents(trackIndex: track_index_t, eventData: UnsafePointer<UInt8>, eventsCount: UInt32) -> UInt32 {
    let events = UnsafeMutablePointer<SchedulerEvent>.allocate(capacity: Int(eventsCount))
    
    rawEventDataToEvents(eventData, eventsCount, events)
    
    let result = SchedulerAddEvents(plugin.engine!.scheduler, trackIndex, UnsafePointer(events), eventsCount)
    
    events.deallocate()
    
    return result
}

@_cdecl("clear_events")
func clearEvents(trackIndex: track_index_t, fromFrame: position_frame_t) {
    SchedulerClearEvents(plugin.engine!.scheduler, trackIndex, fromFrame)
}

@_cdecl("engine_play")
func enginePlay() {
    plugin.engine!.play()
}

@_cdecl("engine_pause")
func enginePause() {
    plugin.engine!.pause()
}

// Defining external C functions to avoid duplicate symbols
@_cdecl("RegisterDart_PostCObject")
func RegisterDart_PostCObject(_dartPostCObject: Dart_PostCObjectType) {
    Dart_PostCObject_DL = _dartPostCObject
}
