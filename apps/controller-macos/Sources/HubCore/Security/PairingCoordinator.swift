import Foundation

public enum PairingError: Error, Equatable, CustomStringConvertible {
  case unavailable
  case invalidCode
  case expired
  case consumed
  case rateLimited

  public var description: String {
    switch self {
    case .unavailable: "No pairing invitation is active"
    case .invalidCode: "The pairing code is invalid"
    case .expired: "The pairing invitation expired"
    case .consumed: "The pairing invitation was already used"
    case .rateLimited: "Too many pairing attempts"
    }
  }
}

public final class PairingCoordinator: @unchecked Sendable {
  public static let maximumAttempts = 5

  private struct Ticket {
    let code: String
    let expiresAt: Date
    var attempts: Int
    var consumed: Bool
  }

  private let lock = NSLock()
  private var ticket: Ticket?

  public init() {}

  public func create(
    host: String,
    port: UInt16,
    certificateFingerprint: String,
    controllerPublicKey: Data = Data(),
    now: Date = Date(),
    lifetime: TimeInterval = 300,
    code: String? = nil
  ) -> PairingInvitation {
    let generatedCode = code ?? String(format: "%06d", Int.random(in: 0...999_999))
    let expiresAt = now.addingTimeInterval(lifetime)
    lock.lock()
    ticket = Ticket(code: generatedCode, expiresAt: expiresAt, attempts: 0, consumed: false)
    lock.unlock()
    return PairingInvitation(
      code: generatedCode,
      expiresAt: expiresAt,
      host: host,
      port: port,
      certificateFingerprint: certificateFingerprint,
      controllerPublicKey: controllerPublicKey
    )
  }

  public func consume(code: String, now: Date = Date()) throws {
    lock.lock()
    defer { lock.unlock() }
    guard var current = ticket else { throw PairingError.unavailable }
    if current.consumed { throw PairingError.consumed }
    if current.expiresAt < now {
      ticket = nil
      throw PairingError.expired
    }
    if current.attempts >= Self.maximumAttempts { throw PairingError.rateLimited }
    guard constantTimeEqual(current.code, code) else {
      current.attempts += 1
      ticket = current
      throw current.attempts >= Self.maximumAttempts
        ? PairingError.rateLimited : PairingError.invalidCode
    }
    current.consumed = true
    ticket = current
  }

  private func constantTimeEqual(_ expected: String, _ supplied: String) -> Bool {
    let lhs = Array(expected.utf8)
    let rhs = Array(supplied.utf8)
    var difference = lhs.count ^ rhs.count
    for index in 0..<max(lhs.count, rhs.count) {
      difference |= Int((index < lhs.count ? lhs[index] : 0) ^ (index < rhs.count ? rhs[index] : 0))
    }
    return difference == 0
  }
}
