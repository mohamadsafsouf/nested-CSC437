import Foundation
import os
import Security

@MainActor
final class SessionPersistenceService {
    private let userDefaults: UserDefaults
    private let logger = Logger(subsystem: "CamGuardMac", category: "SessionPersistence")
    private let userKey = "camguard.session.user"
    private let lastSelectedTabKey = "camguard.session.lastSelectedTab"
    private let keychainService = "com.camguard.mac.session"
    private let keychainAccount = "supabaseAuthSession"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func loadUser() -> AppUser? {
        guard let data = userDefaults.data(forKey: userKey) else {
            return nil
        }

        do {
            return try JSONDecoder().decode(AppUser.self, from: data)
        } catch {
            logger.error("Failed to decode persisted user session: \(error.localizedDescription, privacy: .public)")
            userDefaults.removeObject(forKey: userKey)
            return nil
        }
    }

    func saveUser(_ user: AppUser) {
        do {
            let data = try JSONEncoder().encode(user)
            userDefaults.set(data, forKey: userKey)
        } catch {
            logger.error("Failed to persist user session: \(error.localizedDescription, privacy: .public)")
        }
    }

    func clearUser() {
        userDefaults.removeObject(forKey: userKey)
    }

    func loadSession() -> AuthSession? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status != errSecItemNotFound else {
            return nil
        }
        guard status == errSecSuccess, let data = item as? Data else {
            logger.error("Failed to load auth session from Keychain with status \(status, privacy: .public)")
            return nil
        }

        do {
            return try JSONDecoder().decode(AuthSession.self, from: data)
        } catch {
            logger.error("Failed to decode auth session from Keychain: \(error.localizedDescription, privacy: .public)")
            clearSession()
            return nil
        }
    }

    func saveSession(_ session: AuthSession) {
        do {
            let data = try JSONEncoder().encode(session)
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: keychainService,
                kSecAttrAccount as String: keychainAccount
            ]
            let attributes: [String: Any] = [
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            ]

            let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            if status == errSecItemNotFound {
                var addQuery = query
                addQuery.merge(attributes) { _, new in new }
                let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
                if addStatus != errSecSuccess {
                    logger.error("Failed to add auth session to Keychain with status \(addStatus, privacy: .public)")
                }
            } else if status != errSecSuccess {
                logger.error("Failed to update auth session in Keychain with status \(status, privacy: .public)")
            }
        } catch {
            logger.error("Failed to encode auth session for Keychain: \(error.localizedDescription, privacy: .public)")
        }
    }

    func clearSession() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            logger.error("Failed to clear auth session from Keychain with status \(status, privacy: .public)")
        }
    }

    func loadLastSelectedTab() -> AppTab {
        guard let rawValue = userDefaults.string(forKey: lastSelectedTabKey),
              let tab = AppTab(rawValue: rawValue) else {
            return .overview
        }

        return tab
    }

    func saveLastSelectedTab(_ tab: AppTab) {
        userDefaults.set(tab.rawValue, forKey: lastSelectedTabKey)
    }
}
