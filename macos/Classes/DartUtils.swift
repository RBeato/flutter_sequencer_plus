import Foundation

func scan<
  S : Sequence, U
>(_ seq: S, _ initial: U, _ combine: (U, S.Iterator.Element) -> U) -> [U] {
  var result: [U] = []
  result.reserveCapacity(seq.underestimatedCount)
  var runningResult = initial
  for element in seq {
    runningResult = combine(runningResult, element)
    result.append(runningResult)
  }
  return result
}

func withArrayOfCStrings<R>(
  _ args: [String],
  _ body: ([UnsafeMutablePointer<CChar>?]) -> R
) -> R {
  let argsCounts = Array(args.map { $0.utf8.count + 1 })
  let argsOffsets = [ 0 ] + scan(argsCounts, 0, +)
  let argsBufferSize = argsOffsets.last!

  var argsBuffer: [UInt8] = []
  argsBuffer.reserveCapacity(argsBufferSize)
  for arg in args {
    argsBuffer.append(contentsOf: arg.utf8)
    argsBuffer.append(0)
  }

  return argsBuffer.withUnsafeMutableBufferPointer {
    (argsBuffer) in
    let ptr = UnsafeMutableRawPointer(argsBuffer.baseAddress!).bindMemory(
      to: CChar.self, capacity: argsBuffer.count)
    var cStrings: [UnsafeMutablePointer<CChar>?] = argsOffsets.map { ptr + $0 }
    cStrings[cStrings.count - 1] = nil
    return body(cStrings)
  }
}

// Dart_Port needs to be defined for macOS
public typealias Dart_Port = Int64

// Define the necessary C functions that will be implemented in another file
@_silgen_name("callbackToDartInt32")
public func callbackToDartInt32(_ callbackPort: Dart_Port, _ value: Int32) -> Void

@_silgen_name("callbackToDartStrArray")
public func callbackToDartStrArray(_ callbackPort: Dart_Port, _ count: Int32, _ values: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> Void

public func swiftCallbackToDartStrArray(callbackPort: Dart_Port, values: [String]) -> Void {
    withArrayOfCStrings(values) { (cStrings: [UnsafeMutablePointer<CChar>?]) in
        var cStrings2 = cStrings
        
        callbackToDartStrArray(
           callbackPort,
           Int32(values.count),
           &cStrings2
        )
    }
}

// Function for raw event data conversion
public func rawEventDataToEvents(_ eventData: UnsafePointer<UInt8>, _ eventsCount: UInt32, _ events: UnsafeMutablePointer<SchedulerEvent>) {
    // This will be implemented once we have the SchedulerEvent structure defined
    // For now, it's a stub
}
