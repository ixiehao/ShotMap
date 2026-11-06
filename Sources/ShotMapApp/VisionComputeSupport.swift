import CoreML
import Vision

/// Capability-based compatibility, separate from request lifetime and scoring.
/// Keep Vision's default device selection on both processor families. Never
/// assume that every M-series request has an ANE path, or that Intel needs CPU
/// inference. Future SDK changes belong here behind availability checks.
enum VisionComputeSupport {
    static func configureCPU(_ requests: [VNRequest]) -> Bool {
        guard !requests.isEmpty else { return false }
        if #available(macOS 14, *) {
            // Validate the whole group before changing any assignment. Some
            // newer Neural Engine requests intentionally have no CPU variant.
            var assignments: [(VNRequest, VNComputeStage, MLComputeDevice)] = []
            for request in requests {
                guard let stages = try? request.supportedComputeStageDevices, !stages.isEmpty else { return false }
                for (stage, devices) in stages {
                    guard let cpu = devices.first(where: { if case .cpu = $0 { return true }; return false }) else { return false }
                    assignments.append((request, stage, cpu))
                }
            }
            for (request, stage, cpu) in assignments { request.setComputeDevice(cpu, for: stage) }
        } else {
            requests.forEach { $0.usesCPUOnly = true }
        }
        return true
    }
}
