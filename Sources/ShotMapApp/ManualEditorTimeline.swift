import Foundation

/// One position drives the player, filmstrip, frame nudges and editable field.
/// Update the numeric value before publishing its text so the field's change
/// handler can distinguish a seek from a new user edit.
struct ManualEditorTimeline {
    private(set) var time = 0.0
    var editableText = "00:00:00.000"

    @discardableResult
    mutating func seek(to requestedTime: Double, duration: Double) -> Double {
        let upperBound = duration.isFinite ? max(0, duration) : 0
        time = requestedTime.isFinite ? min(max(0, requestedTime), upperBound) : 0
        editableText = TimestampFormatter.editableString(for: time)
        return time
    }
}

extension Task where Failure == Error {
    /// Detached decoding keeps media work off the main actor, but cancellation
    /// does not propagate to it automatically when its UI waiter is cancelled.
    func valuePropagatingCancellation() async throws -> Success {
        try await withTaskCancellationHandler {
            try Task<Never, Never>.checkCancellation()
            return try await value
        } onCancel: {
            cancel()
        }
    }
}
