import Foundation

/// Converts mach_absolute_time ticks to seconds given the timebase. Pure (testable);
/// the OS layer supplies the real timebase via mach_timebase_info.
public func machTicksToSeconds(_ ticks: UInt64, numer: UInt32, denom: UInt32) -> Double {
    let nanos = Double(ticks) * Double(numer) / Double(denom)
    return nanos / 1_000_000_000.0
}

/// Live monotonic clock in seconds, on the same timeline as ScreenCaptureKit
/// sample presentation timestamps (both derive from the mach host clock).
public func machNowSeconds() -> Double {
    var info = mach_timebase_info_data_t()
    mach_timebase_info(&info)
    return machTicksToSeconds(mach_absolute_time(), numer: info.numer, denom: info.denom)
}
