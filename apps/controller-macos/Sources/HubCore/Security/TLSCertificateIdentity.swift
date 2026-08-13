import CryptoKit
import Foundation
import Security

public enum TLSCertificateIdentityError: Error, CustomStringConvertible {
  case keyGeneration(OSStatus)
  case keyLookup(OSStatus)
  case publicKeyExport
  case certificateConstruction
  case certificateStorage(OSStatus)
  case identityLookup(OSStatus)
  case signature

  public var description: String {
    switch self {
    case .keyGeneration(let status): "Could not create the TLS key (\(status))"
    case .keyLookup(let status): "Could not read the TLS key (\(status))"
    case .publicKeyExport: "Could not export the TLS public key"
    case .certificateConstruction: "Could not construct the local TLS certificate"
    case .certificateStorage(let status): "Could not store the TLS certificate (\(status))"
    case .identityLookup(let status): "Could not resolve the TLS identity (\(status))"
    case .signature: "Could not sign the TLS certificate"
    }
  }
}

public final class TLSCertificateIdentity: @unchecked Sendable {
  public let identity: SecIdentity
  public let certificate: SecCertificate
  public let fingerprint: String
  public let label: String

  private init(identity: SecIdentity, certificate: SecCertificate, label: String) {
    self.identity = identity
    self.certificate = certificate
    self.label = label
    let digest = SHA256.hash(data: SecCertificateCopyData(certificate) as Data)
    fingerprint = digest.map { String(format: "%02X", $0) }.joined(separator: ":")
  }

  public static func loadOrCreate(
    label: String = "com.bilalalissa.ParentalControlController.stage02.tls"
  ) throws -> TLSCertificateIdentity {
    let privateKey = try loadOrCreateKey(label: label)
    let certificateURL = try certificateURL(label: label)
    if let storedData = try? Data(contentsOf: certificateURL) {
      guard let certificate = SecCertificateCreateWithData(nil, storedData as CFData) else {
        throw TLSCertificateIdentityError.certificateConstruction
      }
      try storeCertificate(certificate, label: label)
      return try resolve(certificate: certificate, label: label)
    }
    guard
      let publicKey = SecKeyCopyPublicKey(privateKey),
      let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, nil) as Data?
    else { throw TLSCertificateIdentityError.publicKeyExport }

    let certificateData = try SelfSignedCertificate.make(
      publicKey: publicKeyData, privateKey: privateKey)
    guard let certificate = SecCertificateCreateWithData(nil, certificateData as CFData) else {
      throw TLSCertificateIdentityError.certificateConstruction
    }
    try certificateData.write(to: certificateURL, options: .atomic)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o600], ofItemAtPath: certificateURL.path)
    try storeCertificate(certificate, label: label)
    return try resolve(certificate: certificate, label: label)
  }

  private static func storeCertificate(_ certificate: SecCertificate, label: String) throws {
    let status = SecItemAdd(
      [
        kSecClass: kSecClassCertificate,
        kSecValueRef: certificate,
        kSecAttrLabel: label,
      ] as CFDictionary,
      nil
    )
    guard status == errSecSuccess || status == errSecDuplicateItem else {
      throw TLSCertificateIdentityError.certificateStorage(status)
    }
  }

  public static func delete(label: String) {
    SecItemDelete(
      [kSecClass: kSecClassCertificate, kSecAttrLabel: label] as CFDictionary)
    SecItemDelete(
      [
        kSecClass: kSecClassKey,
        kSecAttrApplicationTag: Data(label.utf8),
        kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
      ] as CFDictionary)
    if let url = try? certificateURL(label: label) {
      try? FileManager.default.removeItem(at: url)
    }
  }

  private static func certificateURL(label: String) throws -> URL {
    let base = try FileManager.default.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    .appendingPathComponent("ParentalControlController", isDirectory: true)
    .appendingPathComponent("Certificates", isDirectory: true)
    try FileManager.default.createDirectory(
      at: base,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    let name = SHA256.hash(data: Data(label.utf8)).map { String(format: "%02x", $0) }.joined()
    return base.appendingPathComponent("\(name).der")
  }

  private static func loadOrCreateKey(label: String) throws -> SecKey {
    let query =
      [
        kSecClass: kSecClassKey,
        kSecAttrApplicationTag: Data(label.utf8),
        kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
        kSecReturnRef: true,
        kSecMatchLimit: kSecMatchLimitOne,
      ] as CFDictionary
    var result: CFTypeRef?
    let lookupStatus = SecItemCopyMatching(query, &result)
    if lookupStatus == errSecSuccess, let key = result as! SecKey? { return key }
    guard lookupStatus == errSecItemNotFound else {
      throw TLSCertificateIdentityError.keyLookup(lookupStatus)
    }

    var error: Unmanaged<CFError>?
    let attributes =
      [
        kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
        kSecAttrKeySizeInBits: 256,
        kSecPrivateKeyAttrs: [
          kSecAttrIsPermanent: true,
          kSecAttrApplicationTag: Data(label.utf8),
          kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ],
      ] as CFDictionary
    guard let key = SecKeyCreateRandomKey(attributes, &error) else {
      let status = (error?.takeRetainedValue() as Error?)?._code ?? Int(errSecInternalError)
      throw TLSCertificateIdentityError.keyGeneration(OSStatus(status))
    }
    return key
  }

  private static func resolve(certificate: SecCertificate, label: String) throws
    -> TLSCertificateIdentity
  {
    var identity: SecIdentity?
    let status = SecIdentityCreateWithCertificate(nil, certificate, &identity)
    guard status == errSecSuccess, let identity else {
      throw TLSCertificateIdentityError.identityLookup(status)
    }
    return TLSCertificateIdentity(identity: identity, certificate: certificate, label: label)
  }
}

private enum SelfSignedCertificate {
  static func make(publicKey: Data, privateKey: SecKey, now: Date = Date()) throws -> Data {
    let signatureAlgorithm = DER.sequence(DER.oid([1, 2, 840, 10045, 4, 3, 2]))
    let commonName = DER.sequence(
      DER.set(
        DER.sequence(
          DER.oid([2, 5, 4, 3]) + DER.utf8("Parental Control Local Hub")
        )))
    let subjectPublicKeyInfo = DER.sequence(
      DER.sequence(
        DER.oid([1, 2, 840, 10045, 2, 1]) + DER.oid([1, 2, 840, 10045, 3, 1, 7])
      ) + DER.bitString(publicKey)
    )
    var serial = Data(count: 16)
    let randomStatus = serial.withUnsafeMutableBytes {
      SecRandomCopyBytes(kSecRandomDefault, $0.count, $0.baseAddress!)
    }
    guard randomStatus == errSecSuccess else {
      throw TLSCertificateIdentityError.certificateConstruction
    }
    let tbs = DER.sequence(
      DER.explicit(tag: 0, DER.integer(Data([2])))
        + DER.integer(serial)
        + signatureAlgorithm
        + commonName
        + DER.sequence(
          DER.utcTime(now.addingTimeInterval(-86_400))
            + DER.utcTime(now.addingTimeInterval(86_400 * 3650)))
        + commonName
        + subjectPublicKeyInfo
    )
    var error: Unmanaged<CFError>?
    guard
      let signature = SecKeyCreateSignature(
        privateKey, .ecdsaSignatureMessageX962SHA256, tbs as CFData, &error) as Data?
    else { throw TLSCertificateIdentityError.signature }
    return DER.sequence(tbs + signatureAlgorithm + DER.bitString(signature))
  }
}

private enum DER {
  static func sequence(_ content: Data) -> Data { tagged(0x30, content) }
  static func set(_ content: Data) -> Data { tagged(0x31, content) }
  static func utf8(_ value: String) -> Data { tagged(0x0C, Data(value.utf8)) }

  static func explicit(tag: UInt8, _ content: Data) -> Data {
    tagged(0xA0 | tag, content)
  }

  static func integer(_ input: Data) -> Data {
    var content = input.drop { $0 == 0 }
    if content.isEmpty { content = Data([0]) }
    var data = Data(content)
    if let first = data.first, first & 0x80 != 0 { data.insert(0, at: 0) }
    return tagged(0x02, data)
  }

  static func bitString(_ content: Data) -> Data {
    tagged(0x03, Data([0]) + content)
  }

  static func utcTime(_ date: Date) -> Data {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyMMddHHmmss'Z'"
    return tagged(0x17, Data(formatter.string(from: date).utf8))
  }

  static func oid(_ components: [UInt]) -> Data {
    precondition(components.count >= 2)
    var bytes = [UInt8(components[0] * 40 + components[1])]
    for component in components.dropFirst(2) {
      var encoded = [UInt8(component & 0x7F)]
      var remainder = component >> 7
      while remainder > 0 {
        encoded.insert(UInt8(remainder & 0x7F) | 0x80, at: 0)
        remainder >>= 7
      }
      bytes.append(contentsOf: encoded)
    }
    return tagged(0x06, Data(bytes))
  }

  static func tagged(_ tag: UInt8, _ content: Data) -> Data {
    Data([tag]) + length(content.count) + content
  }

  static func length(_ value: Int) -> Data {
    if value < 128 { return Data([UInt8(value)]) }
    var remainder = value
    var bytes: [UInt8] = []
    while remainder > 0 {
      bytes.insert(UInt8(remainder & 0xFF), at: 0)
      remainder >>= 8
    }
    return Data([0x80 | UInt8(bytes.count)] + bytes)
  }
}
