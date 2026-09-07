import Foundation
import Testing

@testable import EndpointCore

@Suite("secure lock readiness")
struct EndpointSecureLockTests {
  @Test("fixed sysadminctl output is classified fail closed")
  func readinessParser() {
    #expect(
      EndpointSecureLockVerifier.parse(
        statusText: "screenLock delay is immediate", terminationStatus: 0) == .ready)
    #expect(
      EndpointSecureLockVerifier.parse(
        statusText: "screenLock delay is 300 seconds", terminationStatus: 0) == .passwordDelayed)
    #expect(
      EndpointSecureLockVerifier.parse(statusText: "screenLock is off", terminationStatus: 0)
        == .passwordNotRequired)
    #expect(
      EndpointSecureLockVerifier.parse(statusText: "unexpected", terminationStatus: 0)
        == .verificationUnavailable)
    #expect(
      EndpointSecureLockVerifier.parse(
        statusText: "screenLock delay is immediate", terminationStatus: 1)
        == .verificationUnavailable)
  }

  @Test("session reports preserve readiness and confirmed lock evidence")
  func statusPropagation() {
    let repository = EndpointStatusRepository(
      initial: DeviceSnapshotCollector.collect(deviceID: "secure-lock-test"))
    let confirmedAt = Date(timeIntervalSince1970: 1_788_800_000)
    _ = repository.applySession(
      SessionUpdate(
        state: .locked, consoleUser: "child", secureLockReadiness: .ready,
        secureLockConfirmation: .confirmed, secureLockConfirmedAt: confirmedAt))
    let status = repository.status()
    #expect(status.sessionState == .locked)
    #expect(status.secureLockReadiness == .ready)
    #expect(status.secureLockConfirmation == .confirmed)
    #expect(status.secureLockConfirmedAt == confirmedAt)
  }

  @Test("older session payloads decode without inventing secure-lock evidence")
  func backwardsCompatibleDecode() throws {
    let data = Data(
      #"{"state":"active","consoleUser":"child","observedAt":0}"#.utf8)
    let update = try JSONDecoder.endpoint.decode(SessionUpdate.self, from: data)
    #expect(update.secureLockReadiness == nil)
    #expect(update.secureLockConfirmation == nil)
    #expect(update.secureLockConfirmedAt == nil)
  }
}
