import BeerTempFeatures
import ConcurrencyExtras
@preconcurrency import CoreBluetooth
import Dependencies
import Foundation

extension BluetoothClient: @retroactive DependencyKey {
  public static let liveValue: BluetoothClient = {
    let live = BluetoothClientLive()
    return BluetoothClient(
      startScanning: { try await live.startScanning() },
      stopScanning: { await live.stopScanning() },
      discoveredSensors: { live.discoveredSensors() },
      connect: { id in try await live.connect(id) },
      disconnect: { id in await live.disconnect(id) },
      temperatureUpdates: { id in live.temperatureUpdates(id) },
      targetValueProgressUpdates: { id in live.targetValueProgressUpdates(id) },
      setTargetValue: { id, value in try await live.setTargetValue(id, value) },
      readTargetValue: { id in try await live.readTargetValue(id) }
    )
  }()
}

private nonisolated(unsafe) let serviceUUID = CBUUID(
  string: "4fafc201-1fb5-459e-8fcc-c5c9c331914b")
private nonisolated(unsafe) let valueCharacteristicUUID = CBUUID(
  string: "beb5483e-36e1-4688-b7f5-ea07361b26a8")
private nonisolated(unsafe) let targetValueCharacteristicUUID = CBUUID(
  string: "44e7fcba-4db0-4c41-b0a8-a34fc66afd74")
private nonisolated(unsafe) let targetValueProgressCharacteristicUUID = CBUUID(
  string: "6d913149-d0fc-4d85-9dd5-615248f2bee0")

private struct LockedState: @unchecked Sendable {
  var peripherals: [UUID: CBPeripheral] = [:]
  var peripheralDelegates: [UUID: PeripheralDelegate] = [:]
  var connectionContinuations: [UUID: UnsafeContinuation<Void, any Error>] = [:]
  var characteristicContinuations: [CBUUID: [UUID: UnsafeContinuation<Data?, any Error>]] = [:]
  var temperatureStreamContinuations: [UUID: AsyncStream<Double?>.Continuation] = [:]
  var progressStreamContinuations: [UUID: AsyncStream<TargetValueProgress>.Continuation] = [:]
  var discoveryStreamContinuation: AsyncStream<DiscoveredSensor>.Continuation?
  var serviceDiscoveryContinuations: [UUID: UnsafeContinuation<Void, any Error>] = [:]
  var characteristicDiscoveryContinuations: [UUID: UnsafeContinuation<Void, any Error>] = [:]
  var poweredOnContinuation: UnsafeContinuation<Void, any Error>?
}

private final class BluetoothClientLive: @unchecked Sendable {
  private let centralManagerDelegate: CentralManagerDelegate
  private let centralManager: CBCentralManager
  private let state = LockIsolated(LockedState())

  init() {
    centralManagerDelegate = CentralManagerDelegate()
    centralManager = CBCentralManager(
      delegate: centralManagerDelegate,
      queue: .global(qos: .userInitiated)
    )
    startDelegateEventLoop()
  }

  private func startDelegateEventLoop() {
    Task { [weak self] in
      guard let self else { return }
      for await event in centralManagerDelegate.delegateEventStream {
        switch event {
        case .didUpdateState:
          self.handleDidUpdateState()
        case let .didDiscover(peripheral, advertisementData, _):
          self.handleDidDiscover(peripheral: peripheral, advertisementData: advertisementData)
        case let .didConnect(peripheral):
          self.handleDidConnect(peripheral: peripheral)
        case let .didFailToConnect(peripheral, error):
          self.handleDidFailToConnect(peripheral: peripheral, error: error)
        case let .didDisconnectPeripheral(peripheral, error):
          self.handleDidDisconnect(peripheral: peripheral, error: error)
        }
      }
    }
  }

  func startScanning() async throws {
    switch centralManager.state {
    case .poweredOn:
      centralManager.scanForPeripherals(withServices: [serviceUUID])
    case .unknown, .resetting:
      try await withUnsafeThrowingContinuation { (continuation: UnsafeContinuation<Void, any Error>) in
        state.withValue { $0.poweredOnContinuation = continuation }
      }
      centralManager.scanForPeripherals(withServices: [serviceUUID])
    case .unsupported, .unauthorized, .poweredOff:
      throw BluetoothError.invalidState
    @unknown default:
      throw BluetoothError.invalidState
    }
  }

  func stopScanning() async {
    centralManager.stopScan()
  }

  func discoveredSensors() -> AsyncStream<DiscoveredSensor> {
    AsyncStream { continuation in
      state.withValue { $0.discoveryStreamContinuation = continuation }
      continuation.onTermination = { [weak self] _ in
        self?.state.withValue { $0.discoveryStreamContinuation = nil }
      }
    }
  }

  func connect(_ id: UUID) async throws {
    let peripheral = state.withValue { state -> CBPeripheral? in
      state.peripherals[id]
    }
    guard let peripheral else { throw BluetoothError.peripheralNotFound }

    try await withUnsafeThrowingContinuation { (continuation: UnsafeContinuation<Void, any Error>) in
      state.withValue { $0.connectionContinuations[id] = continuation }
      centralManager.connect(peripheral)
    }

    try await discoverServicesAndCharacteristics(id: id)
    startTemperatureNotifications(id: id)

    if let targetData = try? await readCharacteristic(id: id, uuid: targetValueCharacteristicUUID) {
      if targetData.floatValue != nil {
        startProgressNotifications(id: id)
      }
    }
  }

  func disconnect(_ id: UUID) async {
    let peripheral = state.withValue { $0.peripherals[id] }
    guard let peripheral else { return }
    centralManager.cancelPeripheralConnection(peripheral)
  }

  func temperatureUpdates(_ id: UUID) -> AsyncStream<Double?> {
    AsyncStream { continuation in
      state.withValue { $0.temperatureStreamContinuations[id] = continuation }
      continuation.onTermination = { [weak self] _ in
        self?.state.withValue { $0.temperatureStreamContinuations[id] = nil }
      }
    }
  }

  func targetValueProgressUpdates(_ id: UUID) -> AsyncStream<TargetValueProgress> {
    AsyncStream { continuation in
      state.withValue { $0.progressStreamContinuations[id] = continuation }
      continuation.onTermination = { [weak self] _ in
        self?.state.withValue { $0.progressStreamContinuations[id] = nil }
      }
    }
  }

  func setTargetValue(_ id: UUID, _ value: Double?) async throws -> Double? {
    let data: Data
    if let value {
      let bytes = withUnsafeBytes(of: Float(value).bitPattern.littleEndian) { Array($0) }
      data = Data(bytes)
    } else {
      data = Data()
    }

    try await writeCharacteristic(id: id, uuid: targetValueCharacteristicUUID, data: data)

    let readBack = try await readCharacteristic(id: id, uuid: targetValueCharacteristicUUID)
    let confirmed = readBack?.floatValue.map(Double.init)

    if confirmed != nil {
      startProgressNotifications(id: id)
    }

    return confirmed
  }

  func readTargetValue(_ id: UUID) async throws -> Double? {
    let data = try await readCharacteristic(id: id, uuid: targetValueCharacteristicUUID)
    return data?.floatValue.map(Double.init)
  }

  // MARK: - Internal helpers

  private func handleDidDiscover(
    peripheral: CBPeripheral, advertisementData: [String: Any]
  ) {
    let id = peripheral.identifier
    let continuation = state.withValue { state -> AsyncStream<DiscoveredSensor>.Continuation? in
      let isNew = state.peripherals[id] == nil
      state.peripherals[id] = peripheral
      if isNew {
        let delegate = PeripheralDelegate()
        peripheral.delegate = delegate
        state.peripheralDelegates[id] = delegate
        startPeripheralDelegateLoop(id: id, delegate: delegate)
      }
      return state.discoveryStreamContinuation
    }

    var temperature: Double?
    if let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
      let stringValue = String(data: manufacturerData, encoding: .utf8),
      let temp = Double(stringValue)
    {
      temperature = temp
    }

    let sensor = DiscoveredSensor(
      id: id,
      name: peripheral.name,
      advertisedTemperature: temperature
    )
    continuation?.yield(sensor)
  }

  private func handleDidConnect(peripheral: CBPeripheral) {
    let id = peripheral.identifier
    let continuation = state.withValue { $0.connectionContinuations.removeValue(forKey: id) }
    continuation?.resume(returning: ())
  }

  private func handleDidFailToConnect(peripheral: CBPeripheral, error: (any Error)?) {
    let id = peripheral.identifier
    let continuation = state.withValue { $0.connectionContinuations.removeValue(forKey: id) }
    continuation?.resume(throwing: error ?? BluetoothError.connectionFailed)
  }

  private func handleDidUpdateState() {
    let continuation = state.withValue { $0.poweredOnContinuation }
    switch centralManager.state {
    case .poweredOn:
      state.withValue { $0.poweredOnContinuation = nil }
      continuation?.resume(returning: ())
    case .unsupported, .unauthorized, .poweredOff:
      state.withValue { $0.poweredOnContinuation = nil }
      continuation?.resume(throwing: BluetoothError.invalidState)
    default:
      break
    }
  }

  private func handleDidDisconnect(peripheral: CBPeripheral, error: (any Error)?) {
    let id = peripheral.identifier
    state.withValue { state in
      state.temperatureStreamContinuations[id]?.finish()
      state.temperatureStreamContinuations[id] = nil
      state.progressStreamContinuations[id]?.finish()
      state.progressStreamContinuations[id] = nil
    }
  }

  private func startPeripheralDelegateLoop(id: UUID, delegate: PeripheralDelegate) {
    Task { [weak self] in
      for await event in delegate.delegateEventStream {
        guard let self else { return }
        switch event {
        case let .didDiscoverServices(error):
          self.handleDidDiscoverServices(id: id, error: error)
        case let .didDiscoverCharacteristicsFor(service, error):
          self.handleDidDiscoverCharacteristics(id: id, service: service, error: error)
        case let .didUpdateValueFor(characteristic, error):
          self.handleDidUpdateValue(id: id, characteristic: characteristic, error: error)
        case let .didWriteValueFor(characteristic, error):
          self.handleDidWriteValue(id: id, characteristic: characteristic, error: error)
        }
      }
    }
  }

  private func discoverServicesAndCharacteristics(id: UUID) async throws {
    let peripheral = state.withValue { $0.peripherals[id] }
    guard let peripheral else { throw BluetoothError.peripheralNotFound }

    try await withUnsafeThrowingContinuation { (continuation: UnsafeContinuation<Void, any Error>) in
      state.withValue { $0.serviceDiscoveryContinuations[id] = continuation }
      peripheral.discoverServices([serviceUUID])
    }

    try await withUnsafeThrowingContinuation { (continuation: UnsafeContinuation<Void, any Error>) in
      state.withValue { $0.characteristicDiscoveryContinuations[id] = continuation }
      if let service = peripheral.services?.first(where: { $0.uuid == serviceUUID }) {
        peripheral.discoverCharacteristics(
          [
            valueCharacteristicUUID,
            targetValueCharacteristicUUID,
            targetValueProgressCharacteristicUUID,
          ],
          for: service
        )
      }
    }
  }

  private func handleDidDiscoverServices(id: UUID, error: (any Error)?) {
    let continuation = state.withValue { $0.serviceDiscoveryContinuations.removeValue(forKey: id) }
    if let error {
      continuation?.resume(throwing: error)
    } else {
      continuation?.resume(returning: ())
    }
  }

  private func handleDidDiscoverCharacteristics(
    id: UUID, service: CBService, error: (any Error)?
  ) {
    let continuation = state.withValue {
      $0.characteristicDiscoveryContinuations.removeValue(forKey: id)
    }
    if let error {
      continuation?.resume(throwing: error)
    } else {
      continuation?.resume(returning: ())
    }
  }

  private func handleDidUpdateValue(
    id: UUID, characteristic: CBCharacteristic, error: (any Error)?
  ) {
    let charUUID = characteristic.uuid

    let readContinuation = state.withValue {
      $0.characteristicContinuations[charUUID]?.removeValue(forKey: id)
    }

    if let readContinuation {
      if let error {
        readContinuation.resume(throwing: error)
      } else {
        readContinuation.resume(returning: characteristic.value)
      }
      return
    }

    if charUUID == valueCharacteristicUUID {
      let continuation = state.withValue { $0.temperatureStreamContinuations[id] }
      let temp = characteristic.value?.floatValue.map(Double.init)
      continuation?.yield(temp)
    } else if charUUID == targetValueProgressCharacteristicUUID {
      let continuation = state.withValue { $0.progressStreamContinuations[id] }
      let progress =
        characteristic.value?.first.flatMap(TargetValueProgress.init) ?? .notInProgress
      continuation?.yield(progress)
    }
  }

  private func handleDidWriteValue(
    id: UUID, characteristic: CBCharacteristic, error: (any Error)?
  ) {
    let charUUID = characteristic.uuid
    let continuation = state.withValue {
      $0.characteristicContinuations[charUUID]?.removeValue(forKey: id)
    }
    if let error {
      continuation?.resume(throwing: error)
    } else {
      continuation?.resume(returning: characteristic.value)
    }
  }

  private func startTemperatureNotifications(id: UUID) {
    let peripheral = state.withValue { $0.peripherals[id] }
    guard let peripheral else { return }
    if let characteristic = findCharacteristic(peripheral: peripheral, uuid: valueCharacteristicUUID)
    {
      peripheral.setNotifyValue(true, for: characteristic)
    }
  }

  private func startProgressNotifications(id: UUID) {
    let peripheral = state.withValue { $0.peripherals[id] }
    guard let peripheral else { return }
    if let characteristic = findCharacteristic(
      peripheral: peripheral, uuid: targetValueProgressCharacteristicUUID)
    {
      peripheral.setNotifyValue(true, for: characteristic)
    }
  }

  private func readCharacteristic(id: UUID, uuid: CBUUID) async throws -> Data? {
    let peripheral = state.withValue { $0.peripherals[id] }
    guard let peripheral else { throw BluetoothError.peripheralNotFound }

    guard let characteristic = findCharacteristic(peripheral: peripheral, uuid: uuid) else {
      throw BluetoothError.characteristicNotFound
    }

    return try await withUnsafeThrowingContinuation {
      (continuation: UnsafeContinuation<Data?, any Error>) in
      state.withValue { state in
        if state.characteristicContinuations[uuid] == nil {
          state.characteristicContinuations[uuid] = [:]
        }
        state.characteristicContinuations[uuid]?[id] = continuation
      }
      peripheral.readValue(for: characteristic)
    }
  }

  private func writeCharacteristic(id: UUID, uuid: CBUUID, data: Data) async throws {
    let peripheral = state.withValue { $0.peripherals[id] }
    guard let peripheral else { throw BluetoothError.peripheralNotFound }

    guard let characteristic = findCharacteristic(peripheral: peripheral, uuid: uuid) else {
      throw BluetoothError.characteristicNotFound
    }

    _ = try await withUnsafeThrowingContinuation {
      (continuation: UnsafeContinuation<Data?, any Error>) in
      state.withValue { state in
        if state.characteristicContinuations[uuid] == nil {
          state.characteristicContinuations[uuid] = [:]
        }
        state.characteristicContinuations[uuid]?[id] = continuation
      }
      peripheral.writeValue(data, for: characteristic, type: .withResponse)
    }
  }

  private func findCharacteristic(peripheral: CBPeripheral, uuid: CBUUID) -> CBCharacteristic? {
    peripheral.services?
      .compactMap(\.characteristics)
      .flatMap { $0 }
      .first { $0.uuid == uuid }
  }
}

enum BluetoothError: Error {
  case characteristicNotFound
  case connectionFailed
  case invalidState
  case peripheralNotFound
}
