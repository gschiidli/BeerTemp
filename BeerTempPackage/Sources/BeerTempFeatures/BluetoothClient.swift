import Dependencies
import DependenciesMacros
import Foundation

@DependencyClient
public struct BluetoothClient: Sendable {
  public var startScanning: @Sendable () async throws -> Void
  public var stopScanning: @Sendable () async -> Void
  public var discoveredSensors: @Sendable () -> AsyncStream<DiscoveredSensor> = { .finished }
  public var connect: @Sendable (UUID) async throws -> Void
  public var disconnect: @Sendable (UUID) async -> Void
  public var temperatureUpdates: @Sendable (UUID) -> AsyncStream<Double?> = { _ in .finished }
  public var targetValueProgressUpdates: @Sendable (UUID) -> AsyncStream<TargetValueProgress> = {
    _ in .finished
  }
  public var setTargetValue: @Sendable (UUID, Double?) async throws -> Double?
  public var readTargetValue: @Sendable (UUID) async throws -> Double?
}

extension BluetoothClient: TestDependencyKey {
  public static let testValue = BluetoothClient()
  public static let previewValue = BluetoothClient(
    startScanning: {},
    stopScanning: {},
    discoveredSensors: { .finished },
    connect: { _ in },
    disconnect: { _ in },
    temperatureUpdates: { _ in .finished },
    targetValueProgressUpdates: { _ in .finished },
    setTargetValue: { _, _ in nil },
    readTargetValue: { _ in nil }
  )
}

extension DependencyValues {
  public var bluetoothClient: BluetoothClient {
    get { self[BluetoothClient.self] }
    set { self[BluetoothClient.self] = newValue }
  }
}
