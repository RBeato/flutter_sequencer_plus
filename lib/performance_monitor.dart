import 'dart:async';
import 'dart:io';
import 'native_bridge.dart';

/// High-performance monitoring system for flutter_sequencer
class PerformanceMonitor {
  static final PerformanceMonitor _instance = PerformanceMonitor._internal();
  static PerformanceMonitor get instance => _instance;
  
  PerformanceMonitor._internal();
  
  // Performance metrics
  int _totalEventsProcessed = 0;
  int _totalBufferUnderruns = 0;
  int _totalLoopRestarts = 0;
  double _averageLatency = 0.0;
  Timer? _monitoringTimer;
  
  // Real-time statistics
  final List<double> _latencyHistory = [];
  final List<int> _eventCountHistory = [];
  static const int _historySize = 100;
  
  /// Start performance monitoring
  void startMonitoring() {
    if (_monitoringTimer != null) return;
    
    _monitoringTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      _updateMetrics();
    });
    
    print('[PerformanceMonitor] Started real-time monitoring');
  }
  
  /// Stop performance monitoring
  void stopMonitoring() {
    _monitoringTimer?.cancel();
    _monitoringTimer = null;
    print('[PerformanceMonitor] Stopped monitoring');
  }
  
  /// Record event processing
  void recordEventProcessed(int count, double latencyMs) {
    _totalEventsProcessed += count;
    
    // Update latency history
    _latencyHistory.add(latencyMs);
    if (_latencyHistory.length > _historySize) {
      _latencyHistory.removeAt(0);
    }
    
    // Update event count history
    _eventCountHistory.add(count);
    if (_eventCountHistory.length > _historySize) {
      _eventCountHistory.removeAt(0);
    }
    
    // Calculate rolling average
    if (_latencyHistory.isNotEmpty) {
      _averageLatency = _latencyHistory.reduce((a, b) => a + b) / _latencyHistory.length;
    }
  }
  
  /// Record buffer underrun
  void recordBufferUnderrun() {
    _totalBufferUnderruns++;
  }
  
  /// Record loop restart
  void recordLoopRestart() {
    _totalLoopRestarts++;
  }
  
  /// Get current performance statistics
  Map<String, dynamic> getStats() {
    final eventsPerSecond = _eventCountHistory.isNotEmpty 
        ? (_eventCountHistory.reduce((a, b) => a + b) / _eventCountHistory.length * 10)
        : 0.0;
        
    return {
      'totalEventsProcessed': _totalEventsProcessed,
      'totalBufferUnderruns': _totalBufferUnderruns,
      'totalLoopRestarts': _totalLoopRestarts,
      'averageLatencyMs': _averageLatency.toStringAsFixed(2),
      'eventsPerSecond': eventsPerSecond.toStringAsFixed(1),
      'platform': Platform.operatingSystem,
      'isOptimalPerformance': _averageLatency < 5.0 && _totalBufferUnderruns == 0,
    };
  }
  
  /// Get performance recommendations
  List<String> getRecommendations() {
    final recommendations = <String>[];
    
    if (_averageLatency > 10.0) {
      recommendations.add('High latency detected. Consider reducing buffer size.');
    }
    
    if (_totalBufferUnderruns > 0) {
      recommendations.add('Buffer underruns detected. Increase buffer size or optimize event processing.');
    }
    
    if (_totalLoopRestarts > 100) {
      recommendations.add('Frequent loop restarts. Check loop timing implementation.');
    }
    
    if (Platform.isAndroid && _averageLatency > 20.0) {
      recommendations.add('Android performance suboptimal. Enable performance mode in device settings.');
    }
    
    if (_eventCountHistory.isNotEmpty && 
        _eventCountHistory.reduce((a, b) => a + b) / _eventCountHistory.length > 1000) {
      recommendations.add('High event load. Consider event batching or reducing MIDI density.');
    }
    
    if (recommendations.isEmpty) {
      recommendations.add('Performance is optimal! No recommendations at this time.');
    }
    
    return recommendations;
  }
  
  /// Update metrics from native bridge
  void _updateMetrics() {
    // This would be called periodically to gather native performance data
    // For now, we track Dart-side metrics
  }
  
  /// Print performance report
  void printReport() {
    final stats = getStats();
    final recommendations = getRecommendations();
    
    print('\\n=== FLUTTER SEQUENCER PERFORMANCE REPORT ===');
    print('Total Events Processed: ${stats['totalEventsProcessed']}');
    print('Average Latency: ${stats['averageLatencyMs']} ms');
    print('Events/Second: ${stats['eventsPerSecond']}');
    print('Buffer Underruns: ${stats['totalBufferUnderruns']}');
    print('Loop Restarts: ${stats['totalLoopRestarts']}');
    print('Platform: ${stats['platform']}');
    print('Performance Status: ${stats['isOptimalPerformance'] ? 'OPTIMAL' : 'NEEDS OPTIMIZATION'}');
    
    print('\\nRECOMMENDATIONS:');
    for (int i = 0; i < recommendations.length; i++) {
      print('${i + 1}. ${recommendations[i]}');
    }
    print('===============================================\\n');
  }
  
  /// Reset all metrics
  void reset() {
    _totalEventsProcessed = 0;
    _totalBufferUnderruns = 0;
    _totalLoopRestarts = 0;
    _averageLatency = 0.0;
    _latencyHistory.clear();
    _eventCountHistory.clear();
    print('[PerformanceMonitor] Metrics reset');
  }
}

/// Easy access to performance monitoring
final performanceMonitor = PerformanceMonitor.instance;