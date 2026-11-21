import Foundation
import Security

enum KeychainError: LocalizedError {
    case unexpectedStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            return "钥匙串操作失败（\(status)）。"
        }
    }
}

/// 智谱 API Key 存在 macOS 钥匙串，相当于 Windows 版的 DPAPI 文件。
final class ZhipuApiKeyStore {
    private let service = "JT Copilot"
    private let account = "zhipu-api-key"
    private let environmentKey = "ZHIPU_API_KEY"

    func apiKey() -> String? {
        if let environment = ProcessInfo.processInfo.environment[environmentKey],
           !environment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return environment.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var hasApiKey: Bool {
        apiKey() != nil
    }

    func saveApiKey(_ apiKey: String) throws {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw NSError(domain: "JTCopilot", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "API Key 不能为空。"
            ])
        }

        let data = Data(trimmed.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func deleteApiKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
