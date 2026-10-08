import Foundation
import Darwin
import Metal

// Bounded host diagnostic; no scene rendering or game acceptance claim.
// The real CPU staging contract requires coherent host-visible (Shared) memory.
guard let device = MTLCreateSystemDefaultDevice() else {
    print("SCENE112_METAL_ALLOCATION_PROBE={\"device_available\":false}")
    exit(1)
}
let count = 262144
let privateSize = device.heapBufferSizeAndAlign(length: count, options: .storageModePrivate)
let sharedSize = device.heapBufferSizeAndAlign(length: count, options: .storageModeShared)
let shared = device.makeBuffer(length: count, options: .storageModeShared)
let values: [String: Any] = [
    "scope": "host Metal allocation diagnostic; no app/backend/gameplay acceptance",
    "device_available": true, "name": device.name,
    "has_unified_memory": device.hasUnifiedMemory,
    "max_buffer_length": device.maxBufferLength,
    "requested_bytes": count,
    "private_heap_size": privateSize.size, "private_heap_alignment": privateSize.align,
    "shared_heap_size": sharedSize.size, "shared_heap_alignment": sharedSize.align,
    "direct_shared_buffer_created": shared != nil,
    "direct_shared_buffer_length": shared?.length ?? 0,
]
let json = try JSONSerialization.data(withJSONObject: values, options: [.sortedKeys])
print("SCENE112_METAL_ALLOCATION_PROBE=" + String(data: json, encoding: .utf8)!)
