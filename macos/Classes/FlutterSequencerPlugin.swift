import Cocoa
import FlutterMacOS

public class FlutterSequencerPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "flutter_sequencer", binaryMessenger: registrar.messenger)
    let instance = FlutterSequencerPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "setupAssetManager":
      // Asset manager setup is handled differently on macOS vs iOS
      // For now, just return success
      result(nil)
    case "normalizeAssetDir":
      if let args = call.arguments as? [String: Any],
         let assetDir = args["assetDir"] as? String {
        // On macOS, we need to handle asset paths differently
        // For now, just return the path as is
        result(assetDir)
      } else {
        result(FlutterError(code: "INVALID_ARGUMENTS",
                           message: "Missing required arguments",
                           details: nil))
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
