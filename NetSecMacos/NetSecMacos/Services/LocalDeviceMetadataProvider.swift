import Foundation
import Darwin

final class LocalDeviceMetadataProvider {
    private let userDefaults: UserDefaults
    private let clientDeviceIdKey = "camguard.device.clientDeviceId"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func currentDevice() -> LocalDeviceMetadata {
        LocalDeviceMetadata(
            clientDeviceId: clientDeviceId(),
            displayName: Host.current().localizedName ?? "This Mac",
            deviceTypeKey: "macos",
            osName: "macOS",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            modelName: modelIdentifier()
        )
    }

    private func clientDeviceId() -> String {
        if let existing = userDefaults.string(forKey: clientDeviceIdKey), !existing.isEmpty {
            return existing
        }

        let created = UUID().uuidString
        userDefaults.set(created, forKey: clientDeviceIdKey)
        return created
    }

    private func modelIdentifier() -> String? {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else {
            return nil
        }

        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return String(cString: model)
    }
}
