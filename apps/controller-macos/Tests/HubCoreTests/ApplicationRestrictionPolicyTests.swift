import Foundation
import Testing

@testable import HubCore

@Suite("application-use restriction policy")
struct ApplicationRestrictionPolicyTests {
  private func rule(_ bundle: String = "com.example.LearningGame") throws
    -> ApplicationRestrictionRule
  {
    try ApplicationRestrictionRule(
      bundleIdentifier: bundle, signingIdentifier: bundle, teamIdentifier: "TEAM123456",
      applicationName: "Learning Game")
  }

  @Test("rules require an exact signed non-system identity")
  func identityValidation() throws {
    #expect(throws: ApplicationRestrictionPolicyError.self) {
      try ApplicationRestrictionRule(
        bundleIdentifier: "com.apple.Safari", signingIdentifier: "com.apple.Safari",
        teamIdentifier: "APPLE", applicationName: "Safari")
    }
    #expect(throws: ApplicationRestrictionPolicyError.self) {
      try ApplicationRestrictionRule(
        bundleIdentifier: "com.example.Game", signingIdentifier: "com.example.Other",
        teamIdentifier: "TEAM123456", applicationName: "Game")
    }
    #expect(throws: ApplicationRestrictionPolicyError.self) {
      try ApplicationRestrictionRule(
        bundleIdentifier: "com.example.Game", signingIdentifier: "com.example.Game",
        teamIdentifier: "", applicationName: "Game")
    }
    #expect(try rule().bundleIdentifier == "com.example.LearningGame")
  }

  @Test("policy is bounded, versioned, and rejects duplicates")
  func bounds() throws {
    let valid = try ApplicationRestrictionPolicy(version: 1, rules: [rule()])
    #expect(valid.rules.count == 1)
    #expect(throws: ApplicationRestrictionPolicyError.self) {
      try ApplicationRestrictionPolicy(version: 2, rules: [rule(), rule()])
    }
    #expect(throws: ApplicationRestrictionPolicyError.self) {
      try ApplicationRestrictionPolicy(
        version: 3,
        rules: (0...ApplicationRestrictionPolicy.maximumRules).map {
          try rule("com.example.App\($0)")
        })
    }
  }

  @Test("aggregate configuration preserves the bounded local IPC response")
  func aggregateBudget() throws {
    let largeName = String(repeating: "A", count: 120)
    let rules = try (0..<ApplicationRestrictionPolicy.maximumRules).map { index in
      try ApplicationRestrictionRule(
        bundleIdentifier: "com.example.App\(index)",
        signingIdentifier: "com.example.App\(index)", teamIdentifier: "TEAM123456",
        applicationName: largeName)
    }
    let policy = try ApplicationRestrictionPolicy(version: 1, rules: rules)
    let first = ActivityConfiguration(deviceID: "one", restrictionPolicy: policy)
    #expect(throws: ApplicationRestrictionPolicyError.self) {
      try ApplicationRestrictionPolicy.validateStatusBudget(
        [
          first,
          ActivityConfiguration(deviceID: "two", restrictionPolicy: policy),
          ActivityConfiguration(deviceID: "three", restrictionPolicy: policy),
          ActivityConfiguration(deviceID: "four", restrictionPolicy: policy),
        ])
    }
  }

  @Test("activity identities and policy survive database migration")
  func persistence() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let path = root.appendingPathComponent("hub.sqlite").path
    let policy = try ApplicationRestrictionPolicy(version: 9, rules: [rule()])
    do {
      let database = try HubDatabase(path: path)
      try database.saveActivity(
        [
          HubAppActivity(
            deviceID: "child", bundleIdentifier: "com.example.LearningGame",
            applicationName: "Learning Game", signingIdentifier: "com.example.LearningGame",
            teamIdentifier: "TEAM123456", isForeground: true)
        ], for: "child")
      try database.saveActivityConfiguration(
        ActivityConfiguration(
          deviceID: "child", enabled: true, retentionDays: 3,
          restrictionPolicy: policy))
    }
    let database = try HubDatabase(path: path)
    #expect(try database.activityConfigurations().first?.restrictionPolicy == policy)
    let activity = try #require(database.activity().first)
    #expect(activity.signingIdentifier == "com.example.LearningGame")
    #expect(activity.teamIdentifier == "TEAM123456")
  }
}
