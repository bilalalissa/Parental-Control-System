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
      EndpointSecureLockVerifier.parse(
        statusText: "screenLock delay is 0 seconds", terminationStatus: 0) == .ready)
    #expect(
      EndpointSecureLockVerifier.parse(
        statusText: "screenLock delay is 0.0 seconds", terminationStatus: 0) == .ready)
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

  @Test("readiness is refreshed on a bounded interval and after clock rollback")
  func readinessRefreshGate() {
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    #expect(EndpointSecureLockVerifier.shouldRefresh(lastCheckedAt: nil, now: now))
    #expect(
      !EndpointSecureLockVerifier.shouldRefresh(
        lastCheckedAt: now.addingTimeInterval(-59), now: now))
    #expect(
      EndpointSecureLockVerifier.shouldRefresh(
        lastCheckedAt: now.addingTimeInterval(-60), now: now))
    #expect(
      EndpointSecureLockVerifier.shouldRefresh(
        lastCheckedAt: now.addingTimeInterval(1), now: now))
  }

  @Test("a stalled readiness command is terminated within the bounded timeout")
  func readinessCommandTimeout() {
    let started = Date()
    let result = EndpointSecureLockVerifier.execute(
      executable: "/bin/sleep", arguments: ["2"], timeout: 0.05)
    #expect(result == nil)
    #expect(Date().timeIntervalSince(started) < 1)
  }

  @Test("session reports preserve readiness and confirmed lock evidence")
  func statusPropagation() {
    let repository = EndpointStatusRepository(
      initial: DeviceSnapshotCollector.collect(deviceID: "secure-lock-test"))
    let confirmedAt = Date(timeIntervalSince1970: 1_788_800_000)
    _ = repository.applySession(
      SessionUpdate(
        state: .locked, consoleUser: "child", secureLockReadiness: .ready,
        secureLockConfirmation: .confirmed, secureLockConfirmedAt: confirmedAt),
      verifiedConsoleUser: "admin-child", verifiedAccountType: .administrator)
    let status = repository.status()
    #expect(status.sessionState == .locked)
    #expect(status.consoleUser == "admin-child")
    #expect(status.consoleAccountType == .administrator)
    #expect(status.helperHealthy)
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
