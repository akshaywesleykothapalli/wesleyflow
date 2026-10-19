import Domain
import Darwin

/// Conservative immediately free + inactive + speculative pages. Does not add compressed/swap capacity.
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
        let pages = UInt64(stats.free_count) + UInt64(stats.inactive_count) + UInt64(stats.speculative_count)
        return .init(conservativeAvailableBytes: pages * UInt64(getpagesize()), pressureNormal: pressure == 1, swapUsedBytes: swap.xsu_used)
    }
}
