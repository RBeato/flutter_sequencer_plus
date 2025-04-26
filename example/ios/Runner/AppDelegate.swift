import Flutter
import UIKit
import flutter_sequencer

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Manual plugin registration in Swift
    let registry = self.registrar(forPlugin: "FlutterSequencerPlugin")
    SwiftFlutterSequencerPlugin.register(with: registry!)
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
