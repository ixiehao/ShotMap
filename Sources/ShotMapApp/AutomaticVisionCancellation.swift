import Foundation
import Vision

/// Vision's synchronous `perform` does not inherit Swift task cancellation.
/// Only request registration crosses executors; inference stays on its caller.
final class AutomaticVisionCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var active: [UUID: [VNRequest]] = [:]

    func cancel() {
        lock.lock()
        guard !cancelled else { lock.unlock(); return }
        cancelled = true
        let requests = active.values.flatMap { $0 }
        lock.unlock()
        // Never call framework code under our registration lock.
        requests.forEach { $0.cancel() }
    }

    func perform(_ requests: [VNRequest], using handler: VNImageRequestHandler) throws {
        try performRecoveringComputeFailure(requests, configureCPU: VisionComputeSupport.configureCPU) {
            try handler.perform(requests)
        }
    }

    /// Keep Vision's hardware choice on the normal path. A VM or unavailable
    /// accelerator may fail to create its inference context; retry once using
    /// supported CPU stages, without treating a failed analysis as evidence.
    func performRecoveringComputeFailure(
        _ requests: [VNRequest], configureCPU: ([VNRequest]) -> Bool,
        operation: () throws -> Void
    ) throws {
        try withActiveRequests(requests) {
            do {
                try operation()
            } catch {
                try checkCancellation()
                let failure = error as NSError
                var retryCodes = [VNErrorCode.internalError.rawValue, VNErrorCode.operationFailed.rawValue]
                if #available(macOS 14, *) { retryCodes.append(VNErrorCode.unsupportedComputeDevice.rawValue) }
                guard failure.domain == VNErrorDomain,
                      retryCodes.contains(failure.code),
                      configureCPU(requests) else { throw error }
                try checkCancellation()
                try operation()
            }
        }
    }

    /// Registration also handles cancellation immediately before `perform`.
    /// A completed or cancelled group is removed even when Vision throws.
    func withActiveRequests<T>(_ requests: [VNRequest], operation: () throws -> T) throws -> T {
        try Task.checkCancellation()
        let token = UUID()
        lock.lock()
        guard !cancelled else { lock.unlock(); throw CancellationError() }
        active[token] = requests
        lock.unlock()
        defer {
            lock.lock()
            active.removeValue(forKey: token)
            lock.unlock()
        }
        do {
            let result = try operation()
            try checkCancellation()
            return result
        } catch {
            try checkCancellation()
            throw error
        }
    }

    private func checkCancellation() throws {
        lock.lock()
        let wasCancelled = cancelled
        lock.unlock()
        if wasCancelled { throw CancellationError() }
        try Task.checkCancellation()
    }
}
