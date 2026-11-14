import Dispatch

/// Converts a SwiftyChain timeout to a dispatch deadline without overflowing.
package enum SecretServiceDeadline {
    /// The timeout in nanoseconds, clamped to zero for negative values, or `nil` when it
    /// is too long to represent, meaning no deadline.
    package static func nanoseconds(in timeout: Duration) -> Int? {
        guard timeout > .zero else { return 0 }
        let (seconds, attoseconds) = timeout.components
        let (wholeSeconds, multiplyOverflow) = seconds.multipliedReportingOverflow(by: 1_000_000_000)
        let (total, addOverflow) = wholeSeconds.addingReportingOverflow(attoseconds / 1_000_000_000)
        guard !multiplyOverflow, !addOverflow else { return nil }
        return Int(exactly: total)
    }

    package static func dispatchTime(after timeout: Duration) -> DispatchTime {
        guard let nanoseconds = nanoseconds(in: timeout) else {
            return .distantFuture
        }
        return .now() + .nanoseconds(nanoseconds)
    }
}
