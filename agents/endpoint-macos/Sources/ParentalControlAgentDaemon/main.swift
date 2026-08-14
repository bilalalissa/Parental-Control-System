import EndpointCore
import Foundation
import HubCore

enum DaemonMain {
  static func run() throws {
    let arguments = Arguments(CommandLine.arguments)
    let root = arguments.root ?? ProtectedConfigurationStore.systemRoot
    let store = ProtectedConfigurationStore(root: root)
    let configuration = try store.load()
    let repository = EndpointStatusRepository(
      initial: DeviceSnapshotCollector.collect(deviceID: configuration.deviceID))
    let log = BoundedLog(directory: root.appendingPathComponent("Logs", isDirectory: true))
    let service = arguments.noXPC ? nil : EndpointXPCService(repository: repository)
    service?.resume()
    let agent = try EndpointAgent(
      store: store, repository: repository, log: log,
      keychain: KeychainStore(service: arguments.keychainService))
    log.write(event: "daemon.started", detail: "Visible parental control endpoint started")

    var attempts = 0
    func connect() {
      guard repository.status().connectionState != .online else { return }
      agent.stop()
      do { try agent.start() } catch {
        log.write(event: "connection.retry", detail: String(describing: error))
      }
      attempts += 1
    }
    connect()
    let retry = DispatchSource.makeTimerSource(
      queue: DispatchQueue(label: "parental-control.endpoint.retry"))
    retry.schedule(deadline: .now() + 2, repeating: 2)
    retry.setEventHandler {
      if repository.status().connectionState == .online {
        retry.schedule(deadline: .now() + 60, repeating: 60)
        attempts = 0
      } else if attempts < 3 {
        connect()
      } else {
        retry.schedule(deadline: .now() + 60, repeating: 60)
        attempts = 0
      }
    }
    retry.resume()

    signal(SIGTERM, SIG_IGN)
    signal(SIGINT, SIG_IGN)
    let semaphore = DispatchSemaphore(value: 0)
    let signals = [SIGTERM, SIGINT].map { number -> DispatchSourceSignal in
      let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
      source.setEventHandler { semaphore.signal() }
      source.resume()
      return source
    }
    if let seconds = arguments.runSeconds {
      DispatchQueue.global().asyncAfter(deadline: .now() + seconds) { semaphore.signal() }
    }
    semaphore.wait()
    _ = signals
    retry.cancel()
    agent.stop()
    service?.invalidate()
    log.write(event: "daemon.stopped", detail: "Normal shutdown")
  }
}

private struct Arguments {
  var root: URL?
  var noXPC = false
  var runSeconds: TimeInterval?
  var keychainService = "com.bilalalissa.ParentalControlAgent.device"
  init(_ values: [String]) {
    func value(_ flag: String) -> String? {
      guard let index = values.firstIndex(of: flag), index + 1 < values.count else { return nil }
      return values[index + 1]
    }
    if let path = value("--root") { root = URL(fileURLWithPath: path, isDirectory: true) }
    noXPC = values.contains("--no-xpc")
    runSeconds = value("--run-seconds").flatMap(Double.init)
    if let service = value("--keychain-service") { keychainService = String(service.prefix(200)) }
  }
}

do { try DaemonMain.run() } catch {
  FileHandle.standardError.write(Data("agent-daemon error: \(error)\n".utf8))
  exit(1)
}
