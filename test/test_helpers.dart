import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_sequencer/global_state.dart';
import 'mocks/mock_native_bridge.dart';

void setupTestEnvironment() {
  // Initialize global state with mock native bridge
  final globalState = GlobalState();
  globalState.initializeForTesting(MockNativeBridge());
}

// Extension to reset global state for testing
extension GlobalStateTestExtension on GlobalState {
  void reset() {
    _instance = null;
    _isEngineReady = false;
    _onEngineReadyCallbacks = [];
    _sequences.clear();
  }
  
  void initializeForTesting(NativeBridge bridge) {
    _nativeBridge = bridge;
    _isEngineReady = true;
    _onEngineReadyCallbacks.forEach((callback) => callback());
    _onEngineReadyCallbacks.clear();
  }
}
