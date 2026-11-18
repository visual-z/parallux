import Foundation
import ParalluxKit
import Security

/// Aggregation-server psks in the login Keychain (never in UserDefaults).
struct KeychainSecretStore: SecretStore {
    static let aggregationService = (Bundle.main.bundleIdentifier ?? "io.github.visual-z.parallux") + ".aggregation-server"
    static let remoteService = (Bundle.main.bundleIdentifier ?? "io.github.visual-z.parallux") + ".remote-control"
    let service: String

    init(service: String = KeychainSecretStore.aggregationService) {
        self.service = service
    }

    struct Failure: LocalizedError {
        let status: OSStatus
        var errorDescription: String? { "钥匙串写入失败（\(status)）" }
    }

    private func query(_ id: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: id.uuidString]
    }

    func secret(for id: UUID) -> String? {
        var q = query(id)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func setSecret(_ secret: String, for id: UUID) throws {
        SecItemDelete(query(id) as CFDictionary)
        var q = query(id)
        q[kSecValueData as String] = Data(secret.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(q as CFDictionary, nil)
        guard status == errSecSuccess else { throw Failure(status: status) }
    }

    func removeSecret(for id: UUID) {
        SecItemDelete(query(id) as CFDictionary)
    }
}
