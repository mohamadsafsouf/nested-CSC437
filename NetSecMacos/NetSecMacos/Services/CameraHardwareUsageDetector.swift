import CoreMediaIO
import Foundation
import os

struct CameraHardwareUsageSnapshot: Equatable {
    let isRunning: Bool
    let runningDeviceNames: [String]
}

final class CameraHardwareUsageDetector {
    private let logger = Logger(subsystem: "CamGuardMac", category: "CameraHardware")

    func snapshot() -> CameraHardwareUsageSnapshot {
        let devices = cameraDeviceIDs()
        var runningNames: [String] = []

        for deviceID in devices where isDeviceRunningSomewhere(deviceID) {
            runningNames.append(deviceName(for: deviceID) ?? "Camera")
        }

        return CameraHardwareUsageSnapshot(isRunning: !runningNames.isEmpty, runningDeviceNames: runningNames)
    }

    private func cameraDeviceIDs() -> [CMIOObjectID] {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        var dataSize: UInt32 = 0
        let sizeStatus = CMIOObjectGetPropertyDataSize(
            CMIOObjectID(kCMIOObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize
        )
        guard sizeStatus == noErr, dataSize > 0 else {
            logger.warning("Unable to read CoreMediaIO device list: \(sizeStatus, privacy: .public)")
            return []
        }

        let count = Int(dataSize) / MemoryLayout<CMIOObjectID>.size
        var devices = [CMIOObjectID](repeating: 0, count: count)
        var dataUsed: UInt32 = 0
        let dataStatus = devices.withUnsafeMutableBufferPointer { buffer in
            CMIOObjectGetPropertyData(
                CMIOObjectID(kCMIOObjectSystemObject),
                &address,
                0,
                nil,
                dataSize,
                &dataUsed,
                buffer.baseAddress
            )
        }
        guard dataStatus == noErr else {
            logger.warning("Unable to read CoreMediaIO devices: \(dataStatus, privacy: .public)")
            return []
        }

        return devices
    }

    private func isDeviceRunningSomewhere(_ deviceID: CMIOObjectID) -> Bool {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        guard CMIOObjectHasProperty(deviceID, &address) else {
            return false
        }

        var isRunning: UInt32 = 0
        let dataSize = UInt32(MemoryLayout<UInt32>.size)
        var dataUsed: UInt32 = 0
        let status = CMIOObjectGetPropertyData(deviceID, &address, 0, nil, dataSize, &dataUsed, &isRunning)
        if status != noErr {
            logger.warning("Unable to read camera running state: \(status, privacy: .public)")
        }
        return status == noErr && isRunning != 0
    }

    private func deviceName(for deviceID: CMIOObjectID) -> String? {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOObjectPropertyName),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        guard CMIOObjectHasProperty(deviceID, &address) else {
            return nil
        }

        var name: CFString?
        let dataSize = UInt32(MemoryLayout<CFString?>.size)
        var dataUsed: UInt32 = 0
        let status = withUnsafeMutablePointer(to: &name) { pointer in
            CMIOObjectGetPropertyData(deviceID, &address, 0, nil, dataSize, &dataUsed, pointer)
        }
        guard status == noErr else {
            return nil
        }
        return name as String?
    }
}
