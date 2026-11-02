import Domain
import Darwin

/// Free (already including speculative) + inactive page proxy; reclaim is not guaranteed.
/// Does not add compressed/swap capacity.
public struct SystemInferenceMemory: InferenceMemorySource {
    public init() {}
    public func sample() throws -> InferenceMemorySample {
        var stats = vm_statistics64(); var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let host = mach_host_self(); defer { mach_port_deallocate(mach_task_self_, host) }
        let status = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(host, HOST_VM_INFO64, $0, &count) }
        }
        var pressure: Int32 = 0; var length = MemoryLayout<Int32>.size
        guard status == KERN_SUCCESS, sysctlbyname("kern.memorystatus_vm_pressure_level", &pressure, &length, nil, 0) == 0 else { throw InferenceFailure.memoryAdmissionDenied }
        var swap = xsw_usage(); var swapLength = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &swap, &swapLength, nil, 0) == 0 else { throw InferenceFailure.memoryAdmissionDenied }
        let pageSize = getpagesize()
        guard pageSize > 0 else { throw InferenceFailure.memoryAdmissionDenied }
        let bytes = try Self.availableBytes(freePagesIncludingSpeculative: UInt64(stats.free_count),
                                            inactivePages: UInt64(stats.inactive_count), pageSize: UInt64(pageSize))
        return .init(conservativeAvailableBytes: bytes, pressureLevel: Self.pressureLevel(pressure), swapUsedBytes: swap.xsu_used)
    }
    // This sysctl returns converted dispatch flags, not XNU's internal enum.
    static func pressureLevel(_ raw:Int32) -> InferenceMemoryPressure {
        switch raw {
        case 1: .normal
        case 2: .warning
        case 4: .critical
        default: .unknown
        }
    }
    /// Mach free_count already includes speculative_count. Keep this arithmetic independently testable.
    static func availableBytes(freePagesIncludingSpeculative: UInt64, inactivePages: UInt64, pageSize: UInt64) throws -> UInt64 {
        guard pageSize > 0 else { throw InferenceFailure.memoryAdmissionDenied }
        let (pages, additionOverflow) = freePagesIncludingSpeculative.addingReportingOverflow(inactivePages)
        guard !additionOverflow else { throw InferenceFailure.memoryAdmissionDenied }
        let (bytes, multiplicationOverflow) = pages.multipliedReportingOverflow(by: pageSize)
        guard !multiplicationOverflow else { throw InferenceFailure.memoryAdmissionDenied }
        return bytes
    }
}
