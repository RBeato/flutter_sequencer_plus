import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class DebugConsole extends StatefulWidget {
  @override
  _DebugConsoleState createState() => _DebugConsoleState();
}

class _DebugConsoleState extends State<DebugConsole> {
  String _debugLog = '';
  bool _isLoading = false;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadDebugLog();
  }

  Future<void> _loadDebugLog() async {
    setState(() {
      _isLoading = true;
    });

    try {
      const methodChannel = MethodChannel('flutter_sequencer');
      final String log = await methodChannel.invokeMethod('getDebugLog');
      
      setState(() {
        _debugLog = log;
        _isLoading = false;
      });

      // Auto-scroll to bottom
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    } catch (e) {
      setState(() {
        _debugLog = 'Error loading debug log: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _clearDebugLog() async {
    try {
      const methodChannel = MethodChannel('flutter_sequencer');
      await methodChannel.invokeMethod('clearDebugLog');
      
      setState(() {
        _debugLog = 'Debug log cleared.';
      });
    } catch (e) {
      setState(() {
        _debugLog = 'Error clearing debug log: $e';
      });
    }
  }

  Future<void> _dumpAudioUnitStates() async {
    try {
      const methodChannel = MethodChannel('flutter_sequencer');
      await methodChannel.invokeMethod('dumpAudioUnitStates');
      
      // Reload log after dumping states
      await _loadDebugLog();
    } catch (e) {
      setState(() {
        _debugLog += '\nError dumping AudioUnit states: $e';
      });
    }
  }

  Color _getLogLineColor(String line) {
    if (line.contains('[CRITICAL]') || line.contains('🔴')) {
      return Colors.red.shade300;
    } else if (line.contains('[ERROR]') || line.contains('🔴')) {
      return Colors.red.shade200;
    } else if (line.contains('[WARNING]') || line.contains('🟡')) {
      return Colors.orange.shade200;
    } else if (line.contains('[INFO]') || line.contains('ℹ️')) {
      return Colors.blue.shade200;
    } else if (line.contains('[DEBUG]') || line.contains('🔍')) {
      return Colors.grey.shade300;
    }
    return Colors.grey.shade100;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Native Debug Console'),
        backgroundColor: Colors.black87,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _loadDebugLog,
            tooltip: 'Refresh Log',
          ),
          IconButton(
            icon: Icon(Icons.clear),
            onPressed: _clearDebugLog,
            tooltip: 'Clear Log',
          ),
          IconButton(
            icon: Icon(Icons.memory),
            onPressed: _dumpAudioUnitStates,
            tooltip: 'Dump AudioUnit States',
          ),
        ],
      ),
      backgroundColor: Colors.black,
      body: Column(
        children: [
          // Status bar
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.grey.shade800,
            child: Row(
              children: [
                Text(
                  'Native iOS Debug Log',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                Spacer(),
                if (_isLoading)
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                SizedBox(width: 8),
                Text(
                  'Lines: ${_debugLog.split('\n').length}',
                  style: TextStyle(
                    color: Colors.grey.shade300,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          
          // Log content
          Expanded(
            child: _isLoading
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text(
                          'Loading native debug log...',
                          style: TextStyle(color: Colors.white),
                        ),
                      ],
                    ),
                  )
                : Container(
                    margin: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade900,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade700),
                    ),
                    child: _debugLog.isEmpty
                        ? Center(
                            child: Text(
                              'No debug log available.\nTry performing some actions in the app.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.grey.shade400,
                                fontSize: 16,
                              ),
                            ),
                          )
                        : ListView.builder(
                            controller: _scrollController,
                            padding: EdgeInsets.all(12),
                            itemCount: _debugLog.split('\n').length,
                            itemBuilder: (context, index) {
                              final lines = _debugLog.split('\n');
                              final line = lines[index];
                              
                              if (line.trim().isEmpty) {
                                return SizedBox(height: 4);
                              }

                              return Container(
                                margin: EdgeInsets.only(bottom: 2),
                                padding: EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: _getLogLineColor(line).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: SelectableText(
                                  line,
                                  style: TextStyle(
                                    fontFamily: 'Courier',
                                    fontSize: 12,
                                    color: _getLogLineColor(line),
                                    height: 1.3,
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
          ),
          
          // Action buttons
          Container(
            padding: EdgeInsets.all(16),
            color: Colors.grey.shade800,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: _loadDebugLog,
                  icon: Icon(Icons.refresh, size: 18),
                  label: Text('Refresh'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade700,
                    foregroundColor: Colors.white,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _dumpAudioUnitStates,
                  icon: Icon(Icons.memory, size: 18),
                  label: Text('Dump States'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    foregroundColor: Colors.white,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _clearDebugLog,
                  icon: Icon(Icons.clear, size: 18),
                  label: Text('Clear'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade700,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
}