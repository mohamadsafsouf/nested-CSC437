import Foundation
import UIKit

final class LocalDeviceMetadataProvider {
    private let userDefaults: UserDefaults
    private let clientDeviceIdKey = "camguard.ios.device.clientDeviceId"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func currentDevice() -> LocalDeviceMetadata {
        let device = UIDevice.current
        return LocalDeviceMetadata(
            clientDeviceId: clientDeviceId(),
            displayName: device.name.isEmpty ? "This iPhone" : device.name,
            deviceTypeKey: device.userInterfaceIdiom == .pad ? "ipad" : "ios",
            osName: device.systemName,
            osVersion: device.systemVersion,
            modelName: device.model
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
}
