import Foundation
import Testing

@testable import ParentalControlController

@Suite("Local hub startup coordinator")
@MainActor
struct HubStartupCoordinatorTests {
  @Test("helper startup allows time for a human Keychain decision")
  func keychainAuthorizationGrace() {
    let graceMilliseconds =
      HubClient.helperStartupPollCount * HubClient.helperStartupPollMilliseconds
    #expect(graceMilliseconds >= 60_000)
    #expect(graceMilliseconds <= 120_000)
  }

  @Test("concurrent hub requests share one helper launch")
  func coalescesConcurrentStartup() async throws {
    let coordinator = HubStartupCoordinator()
    let counter = StartCounter()

    async let status: Void = coordinator.run {
      counter.value += 1
      try await Task.sleep(for: .milliseconds(100))
    }
    async let pairing: Void = coordinator.run {
      counter.value += 1
      try await Task.sleep(for: .milliseconds(100))
    }

    _ = try await (status, pairing)
    #expect(counter.value == 1)
  }

  @Test("a failed launch does not block a later retry")
  func retriesAfterFailure() async throws {
    let coordinator = HubStartupCoordinator()
    let counter = StartCounter()

    await #expect(throws: StartupFailure.self) {
      try await coordinator.run {
        counter.value += 1
        throw StartupFailure()
      }
    }
    try await coordinator.run { counter.value += 1 }

    #expect(counter.value == 2)
  }
}

@MainActor
private final class StartCounter {
  var value = 0
}

private struct StartupFailure: Error {}
