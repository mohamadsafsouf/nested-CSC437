import AVFoundation
import Foundation

enum CameraPermissionState: String, Codable, Equatable {
    case authorized
    case denied
    case restricted
    case notDetermined
    case unknown

    init(status: AVAuthorizationStatus) {
        switch status {
        case .authorized:
            self = .authorized
        case .denied:
            self = .denied
        case .restricted:
            self = .restricted
        case .notDetermined:
            self = .notDetermined
        @unknown default:
            self = .unknown
        }
    }

    var title: String {
        switch self {
        case .authorized:
            return "Authorized"
        case .denied:
            return "Denied"
        case .restricted:
            return "Restricted"
        case .notDetermined:
            return "Not Requested"
        case .unknown:
            return "Unknown"
        }
    }

    var detail: String {
        switch self {
        case .authorized:
            return "CamGuard can run the in-app camera safety test."
        case .denied:
            return "Camera access is denied. You can still view saved activity and privacy details."
        case .restricted:
            return "Camera access is restricted by device policy or parental controls."
        case .notDetermined:
            return "Permission has not been requested. The app will ask only when you start the safety test."
        case .unknown:
            return "iOS returned an unknown permission state."
        }
    }

    var monitoringStatus: MonitoringStatus {
        switch self {
        case .authorized, .notDetermined:
            return .normal
        case .denied, .restricted, .unknown:
            return .suspicious
        }
    }
}

final class CameraPermissionService {
    func currentState() -> CameraPermissionState {
        CameraPermissionState(status: AVCaptureDevice.authorizationStatus(for: .video))
    }

    func requestAccess() async -> CameraPermissionState {
        _ = await AVCaptureDevice.requestAccess(for: .video)
        return currentState()
    }
}
