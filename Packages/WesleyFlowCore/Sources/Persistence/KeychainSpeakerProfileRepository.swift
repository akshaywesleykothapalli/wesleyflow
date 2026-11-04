import Domain
import Foundation
import Security

public struct SpeakerKeychainError: Error, Equatable {
    public let status: OSStatus
}

/// Encrypted local login Keychain items. Compatible with locally signed macOS builds.
public actor KeychainSpeakerProfileRepository: SpeakerProfileRepository {
    private let service: String

    public init(service: String = "local.wesleyflow.WesleyFlow.speaker-profiles.v1") {
        self.service = service
    }

    private func query(id: UUID? = nil) -> [String: Any] {
        var attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        if let id { attributes[kSecAttrAccount as String] = id.uuidString }
        return attributes
    }

    public func saveProfile(_ profile: SpeakerProfile) async throws {
        let data = try JSONEncoder().encode(profile.validated())
        let attributes = query(id: profile.id)
        let update = [kSecValueData as String: data]
        var status = SecItemUpdate(attributes as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var item = attributes
            item[kSecValueData as String] = data
            status = SecItemAdd(item as CFDictionary, nil)
            if status == errSecDuplicateItem {
                status = SecItemUpdate(attributes as CFDictionary, update as CFDictionary)
            }
        }
        guard status == errSecSuccess else { throw SpeakerKeychainError(status: status) }
    }

    private func accounts() throws -> [String] {
        var attributes = query()
        attributes[kSecReturnAttributes as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitAll
        var result: CFTypeRef?
        let status = SecItemCopyMatching(attributes as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess else { throw SpeakerKeychainError(status: status) }
        let items: [[String: Any]]
        if let rows = result as? [[String: Any]] { items = rows }
        else if let row = result as? [String: Any] { items = [row] }
        else { throw SpeakerRecognitionError.invalidProfile }
        return items.compactMap { $0[kSecAttrAccount as String] as? String }
    }

    public func getProfiles() async throws -> [SpeakerProfile] {

        // Password data cannot be requested together with kSecMatchLimitAll.
        try accounts().compactMap(UUID.init(uuidString:)).compactMap(readProfile)
    }

    public func getProfile(id: UUID) async throws -> SpeakerProfile? { try readProfile(id) }

    private func readProfile(_ id: UUID) throws -> SpeakerProfile? {
        var attributes = query(id: id)
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(attributes as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw SpeakerKeychainError(status: status) }
        guard let data = result as? Data, data.count <= 131_072,
              let decoded = try? JSONDecoder().decode(SpeakerProfile.self, from: data),
              id == decoded.id else { return nil }
        return try? decoded.validated()
    }

    public func deleteProfile(id: UUID) async throws { try delete(account: id.uuidString) }

    public func deleteAllProfiles() async throws {
        for account in try accounts() { try delete(account: account) }
    }

    private func delete(account: String) throws {
        var attributes = query()
        attributes[kSecAttrAccount as String] = account
        let status = SecItemDelete(attributes as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SpeakerKeychainError(status: status)
        }
    }
}
