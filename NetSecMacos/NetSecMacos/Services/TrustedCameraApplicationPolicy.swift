import Foundation

struct CameraApplicationTrustContext {
    let displayName: String
    let isKnown: Bool
    let isTrusted: Bool
}

struct TrustedCameraApplicationPolicy {
    private static let trustedSourceKey = "camguard.trusted.camera.sources"

    private static let trustedNames: Set<String> = [
        "facetime",
        "google meet",
        "zoom",
        "zoom.us",
        "microsoft teams",
        "teams",
        "slack",
        "webex",
        "whatsapp",
        "whatsapp desktop",
        "whatsapp messenger",
        "photo booth",
        "quicktime player",
        "safari",
        "google chrome",
        "chrome",
        "firefox",
        "arc",
        "brave browser",
        "microsoft edge"
    ]

    private static let trustedDomains: Set<String> = [
        "meet.google.com",
        "zoom.us",
        "teams.microsoft.com",
        "web.whatsapp.com"
    ]

    static func context(for observedApplicationName: String?) -> CameraApplicationTrustContext {
        context(for: observedApplicationName, websiteDomain: nil)
    }

    static func context(
        for observedApplicationName: String?,
        websiteDomain: String?
    ) -> CameraApplicationTrustContext {
        let displayName = observedApplicationName?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let displayName, !displayName.isEmpty else {
            return CameraApplicationTrustContext(displayName: "Unknown Application", isKnown: false, isTrusted: false)
        }

        if let websiteDomain, !websiteDomain.isEmpty {
            let normalizedDomain = normalizedSource(websiteDomain)
            let display = displayName.lowercased().contains(normalizedDomain) ? displayName : "\(websiteDomain) in \(displayName)"
            let isTrusted = trustedDomains.contains(normalizedDomain) || userTrustedSources().contains(normalizedDomain)
            return CameraApplicationTrustContext(displayName: display, isKnown: true, isTrusted: isTrusted)
        }

        let normalized = displayName.lowercased()
        let isTrusted = trustedNames.contains(normalized) || userTrustedSources().contains(normalized)
        return CameraApplicationTrustContext(displayName: displayName, isKnown: true, isTrusted: isTrusted)
    }

    static func trustSource(named sourceName: String) {
        let normalized = normalizedSource(sourceName)
        guard !normalized.isEmpty else {
            return
        }
        var trusted = userTrustedSources()
        trusted.insert(normalized)
        UserDefaults.standard.set(Array(trusted), forKey: trustedSourceKey)
    }

    static func isUserTrustedSource(_ sourceName: String) -> Bool {
        userTrustedSources().contains(normalizedSource(sourceName))
    }

    private static func userTrustedSources() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: trustedSourceKey) ?? [])
    }

    private static func normalizedSource(_ sourceName: String) -> String {
        sourceName
            .lowercased()
            .replacingOccurrences(of: #"^https?://"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^www\."#, with: "", options: .regularExpression)
            .split(separator: "/")
            .first
            .map(String.init) ?? sourceName.lowercased()
    }
}
