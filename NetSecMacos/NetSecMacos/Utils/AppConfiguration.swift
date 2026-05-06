import Foundation

enum AppConfiguration {
    static var backendBaseURL: URL {
        if let override = UserDefaults.standard.string(forKey: "camguard.backend.baseURL"),
           let url = URL(string: override) {
            return url
        }

        return URL(string: "http://127.0.0.1:8000/api/v1")!
    }
}
