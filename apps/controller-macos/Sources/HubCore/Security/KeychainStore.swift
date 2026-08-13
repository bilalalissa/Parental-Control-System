import Foundation
import Security

public enum KeychainStoreError: Error, CustomStringConvertible {
  case unexpectedStatus(OSStatus)

  public var description: String {
    switch self {
    case .unexpectedStatus(let status):
      let message = SecCopyErrorMessageString(status, nil) as String? ?? "status \(status)"
      return "Keychain operation failed: \(message)"
    }
  }
}

public struct KeychainStore: Sendable {
  public let service: String

  public init(service: String = "com.bilalalissa.ParentalControlController.stage02") {
    self.service = service
  }

  public func data(account: String) throws -> Data? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecMatchLimit as String: kSecMatchLimitOne,
      kSecReturnData as String: true,
    ]
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = result as? Data else {
      throw KeychainStoreError.unexpectedStatus(status)
    }
    return data
  }

  public func set(_ data: Data, account: String) throws {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
    let update: [String: Any] = [kSecValueData as String: data]
    let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
    if status == errSecItemNotFound {
      var insert = query
      insert[kSecValueData as String] = data
      insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      let insertStatus = SecItemAdd(insert as CFDictionary, nil)
      guard insertStatus == errSecSuccess else {
        throw KeychainStoreError.unexpectedStatus(insertStatus)
      }
    } else if status != errSecSuccess {
      throw KeychainStoreError.unexpectedStatus(status)
    }
  }

  public func loadOrCreateRandom(account: String, byteCount: Int = 32) throws -> Data {
    if let existing = try data(account: account) { return existing }
    var bytes = [UInt8](repeating: 0, count: byteCount)
    let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    guard status == errSecSuccess else { throw KeychainStoreError.unexpectedStatus(status) }
    let data = Data(bytes)
    try set(data, account: account)
    return data
  }
}
