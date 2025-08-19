/// Error types that can occur when loading instruments
enum InstrumentErrorType {
  fileNotFound,
  invalidFormat,
  assetNotFound,
  presetIndexInvalid,
  memoryAllocationFailed,
  audioEngineError,
  timeout,
  unknown,
}

/// Detailed error information for instrument loading failures
class InstrumentError {
  final InstrumentErrorType type;
  final String message;
  final String? filePath;
  final int? presetIndex;
  final String? technicalDetails;
  
  const InstrumentError({
    required this.type,
    required this.message,
    this.filePath,
    this.presetIndex,
    this.technicalDetails,
  });
  
  @override
  String toString() {
    final buffer = StringBuffer();
    buffer.write('InstrumentError: ${type.name} - $message');
    
    if (filePath != null) {
      buffer.write('\n  File: $filePath');
    }
    
    if (presetIndex != null) {
      buffer.write('\n  Preset Index: $presetIndex');
    }
    
    if (technicalDetails != null) {
      buffer.write('\n  Technical Details: $technicalDetails');
    }
    
    return buffer.toString();
  }
  
  /// Create error for file not found
  static InstrumentError fileNotFound(String filePath) {
    return InstrumentError(
      type: InstrumentErrorType.fileNotFound,
      message: 'Instrument file not found',
      filePath: filePath,
    );
  }
  
  /// Create error for invalid file format
  static InstrumentError invalidFormat(String filePath, String technicalDetails) {
    return InstrumentError(
      type: InstrumentErrorType.invalidFormat,
      message: 'Invalid or corrupted instrument file format',
      filePath: filePath,
      technicalDetails: technicalDetails,
    );
  }
  
  /// Create error for asset not found
  static InstrumentError assetNotFound(String assetPath) {
    return InstrumentError(
      type: InstrumentErrorType.assetNotFound,
      message: 'Asset not found in bundle',
      filePath: assetPath,
      technicalDetails: 'Ensure the file is listed in pubspec.yaml under assets',
    );
  }
  
  /// Create error for invalid preset index
  static InstrumentError presetIndexInvalid(String filePath, int invalidIndex, int maxIndex) {
    return InstrumentError(
      type: InstrumentErrorType.presetIndexInvalid,
      message: 'Preset index out of range',
      filePath: filePath,
      presetIndex: invalidIndex,
      technicalDetails: 'Valid range: 0-$maxIndex',
    );
  }
  
  /// Create error for timeout
  static InstrumentError timeout(String filePath) {
    return InstrumentError(
      type: InstrumentErrorType.timeout,
      message: 'Timeout loading instrument file',
      filePath: filePath,
      technicalDetails: 'File may be too large or corrupted',
    );
  }
}

/// Result wrapper for instrument loading operations
class InstrumentLoadResult<T> {
  final T? data;
  final InstrumentError? error;
  
  const InstrumentLoadResult._({this.data, this.error});
  
  /// Create successful result
  InstrumentLoadResult.success(T data) : this._(data: data);
  
  /// Create error result
  InstrumentLoadResult.error(InstrumentError error) : this._(error: error);
  
  /// Check if operation was successful
  bool get isSuccess => data != null && error == null;
  
  /// Check if operation failed
  bool get isError => error != null;
  
  /// Get data or throw if error
  T get dataOrThrow {
    if (error != null) {
      throw Exception(error.toString());
    }
    return data!;
  }
}

/// Result of creating multiple tracks with error information
class TracksCreationResult {
  final List<dynamic> tracks; // Will be List<Track> but avoiding circular import
  final List<InstrumentError> errors;
  
  const TracksCreationResult({
    required this.tracks,
    required this.errors,
  });
  
  /// Check if all tracks were created successfully
  bool get allSuccessful => errors.isEmpty;
  
  /// Check if any tracks failed to create
  bool get hasErrors => errors.isNotEmpty;
  
  /// Get summary of results
  String get summary {
    final successCount = tracks.length;
    final errorCount = errors.length;
    return 'Created $successCount tracks successfully, $errorCount failed';
  }
}