import CoreBluetooth
import Foundation
import Observation
import SwiftUI
import UserNotifications

enum BluetoothTemperatureSensorError: Error {
    case characteristicNotFound
    case characteristicInUse
}

enum TargetValueProgress: UInt8 {
    case notInProgress
    case onTheWay
    case onPoint
    case passedThePoint
}

@MainActor
@Observable
class BluetoothTemperatureSensor {
    static let serviceUUID = CBUUID(string: "4fafc201-1fb5-459e-8fcc-c5c9c331914b")
    static let valueCharacteristicUUID = CBUUID(string: "beb5483e-36e1-4688-b7f5-ea07361b26a8")
    static let autoUpdateCharacteristicUUID = CBUUID(string: "f751d216-4044-461f-a4e6-548314d60679")
    static let targetValueCharacteristicUUID = CBUUID(string: "44e7fcba-4db0-4c41-b0a8-a34fc66afd74")
    static let targetValueProgressCharacteristicUUID = CBUUID(string: "6d913149-d0fc-4d85-9dd5-615248f2bee0")
    
    enum ConnectionState {
        case disconnected
        case connecting
        case connected
        case failedConnection(error: Error?)
    }
    
    private let peripheral: CBPeripheral
    
    var state: ConnectionState = .disconnected
    var valueInCelcius: Double?
    var autoUpdateInterval: UInt32?
    private var setTargetDebounceTask: Task<Void, Error>?
    var targetValue: Double? {
        didSet {
            guard targetValue != oldValue else {
                return
            }
            setTargetDebounceTask?.cancel()
            setTargetDebounceTask = Task {
                try await Task.sleep(for: .milliseconds(500))
                try await setTargetValue(to: targetValue)
            }
        }
    }
    var targetValueProgress: TargetValueProgress = .notInProgress
    var scenePhase: ScenePhase = .background
    
    var targetValueString: String {
        get {
            targetValue?.formatted(.number.precision(.fractionLength(3))) ?? ""
        }
        set {
            if let newTargetValue = try? Double(newValue, format: .number) {
                targetValue = newTargetValue
            } else if newValue == "" {
                targetValue = nil
            }
        }
    }
    
    var name: String? {
        peripheral.name
    }
    
    init(peripheral: CBPeripheral) {
        let peripheralDelegate = PeripheralDelegate()
        peripheral.delegate = peripheralDelegate
        self.peripheral = peripheral
        
        subscirbeToDelegateEvents(peripheralDelegate: peripheralDelegate)
        
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { success, error in
            if success {
                print("All set!")
            } else if let error {
                print(error.localizedDescription)
            }
        }
    }
    
    private func subscirbeToDelegateEvents(peripheralDelegate: PeripheralDelegate) {
        Task { @MainActor [weak self] in
            for await event in peripheralDelegate.delegateEventStream {
                guard let self else {
                    return
                }
                
                switch event {
                case .didDiscoverServices(error: let error):
                    didDiscoverServices(error: error)
                case .didDiscoverCharacteristicsFor(service: let service, error: let error):
                    didDiscoverCharacteristicsFor(service: service, error: error)
                case .didUpdateValueFor(characteristic: let characteristic, error: let error):
                    didUpdateValueFor(characteristic: characteristic, error: error)
                case .didWriteValueFor(characteristic: let characteristic, error: let error):
                    didWriteValueFor(characteristic: characteristic, error: error)
                }
            }
        }
    }
    
    func setAutoUpdateInterval(to newValue: UInt32) async throws {
        let bytes = withUnsafeBytes(of: newValue) { Array($0) }
        
        try await write(newValue == 0 ? Data() : Data(bytes), to: Self.autoUpdateCharacteristicUUID)
        let autoUpdateIntervalData = try await read(from: Self.autoUpdateCharacteristicUUID)
        
        autoUpdateInterval = autoUpdateIntervalData?.uInt32Value
    }
    
    func setTargetValue(to newValue: Double?) async throws {
        refreshTargetValueProgressSubscription(for: newValue)
        
        if let newValue {
            let bytes = withUnsafeBytes(of: Float(newValue).bitPattern.littleEndian) { Array($0) }
            try await write(Data(bytes), to: Self.targetValueCharacteristicUUID)
        } else {
            try await write(Data(), to: Self.targetValueCharacteristicUUID)
        }
        
        let targetValueData = try await read(from: Self.targetValueCharacteristicUUID)
        
        targetValue = targetValueData?.floatValue.map(Double.init)
    }
    
    private var targetValueProgressSubscription: Task<Void, Error>?
    
    private func refreshTargetValueProgressSubscription(for newValue: Double?) {
        if newValue == nil {
            targetValueProgress = .notInProgress
            targetValueProgressSubscription?.cancel()
            targetValueProgressSubscription = nil
            return
        }
        
        guard targetValueProgressSubscription == nil else {
            return
        }
        
        targetValueProgressSubscription?.cancel()
        targetValueProgressSubscription = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            
            for try await targetValueProgressData in try subscribeToNotifications(from: Self.targetValueProgressCharacteristicUUID) {
                switch targetValueProgressData?.first.flatMap(TargetValueProgress.init) {
                case .none:
                    targetValueProgress = .notInProgress
                case .some(let targetValueProgress):
                    self.targetValueProgress = targetValueProgress
                    switch scenePhase {
                    case .background:
                        sendLocalNotification()
                    case .inactive, .active:
                        break
                    @unknown default:
                        break
                    }
                }
            }
        }
    }
    
    private func sendLocalNotification() {
        let content = UNMutableNotificationContent()
        
        switch targetValueProgress {
        case .notInProgress, .onTheWay:
            return
        case .onPoint:
            content.title = "Target Value Reached"
        case .passedThePoint:
            content.title = "Target Value Passed"
        }
        if let targetValue {
            switch targetValueProgress {
            case .notInProgress, .onTheWay:
                return
            case .onPoint:
                content.subtitle = "The target value of \(targetValue) was reached"
            case .passedThePoint:
                content.subtitle = "The target value of \(targetValue) was passed"
            }
        } else {
            switch targetValueProgress {
            case .notInProgress, .onTheWay:
                return
            case .onPoint:
                content.subtitle = "The target value was reached"
            case .passedThePoint:
                content.title = "The target value was reached passed"
            }
        }
        content.sound = UNNotificationSound.default

        // show this notification five seconds from now
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)

        // choose a random identifier
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)

        // add our notification request
        UNUserNotificationCenter.current().add(request)
    }
    
    func didConnect() {
        peripheral.discoverServices([Self.serviceUUID])
        state = .connected
    }
    
    func didFailToConnect(with error: Error?) {
        state = .failedConnection(error: error)
    }
    
    func didDisconnect(with error: Error?) {
        continuations.removeAll()
        streamContinuations.removeAll()
        state = .failedConnection(error: error)
    }
    
    private func didDiscoverServices(error: Error?) {
        if let service = peripheral.services?.first(where: { $0.uuid == Self.serviceUUID }) {
            self.peripheral.discoverCharacteristics(
                [
                    Self.valueCharacteristicUUID,
                    Self.autoUpdateCharacteristicUUID,
                    Self.targetValueCharacteristicUUID,
                    Self.targetValueProgressCharacteristicUUID
                ],
                for: service
            )
        }
    }
    
    private func didDiscoverCharacteristicsFor(service: CBService, error: Error?) {
        if service.uuid == BluetoothTemperatureSensor.serviceUUID {
            if service.characteristics?.contains(where: { $0.uuid == Self.valueCharacteristicUUID }) == true {
                Task { @MainActor [weak self] in
                    guard let stream = try self?.subscribeToNotifications(from: Self.valueCharacteristicUUID) else {
                        return
                    }
                    
                    for try await valueData in stream {
                        self?.valueInCelcius = valueData?.floatValue.map(Double.init)
                    }
                }
            }
            
            if service.characteristics?.contains(where: { $0.uuid == Self.autoUpdateCharacteristicUUID }) == true {
                Task { @MainActor [weak self] in
                    guard let self else {
                        return
                    }
                    
                    let autoUpdateIntervalData = try await read(from: Self.autoUpdateCharacteristicUUID)
                    
                    autoUpdateInterval = autoUpdateIntervalData?.uInt32Value
                }
            }
            
            if service.characteristics?.contains(where: { $0.uuid == Self.targetValueCharacteristicUUID }) == true {
                Task { @MainActor [weak self] in
                    guard let self else {
                        return
                    }
                    
                    let targetValueData = try await read(from: Self.targetValueCharacteristicUUID)
                    targetValue = (targetValueData?.floatValue).map(Double.init)
                    
                    refreshTargetValueProgressSubscription(for: targetValue)
                }
            }
        }
    }
    
    private func didUpdateValueFor(characteristic: CBCharacteristic, error: Error?) {
        if let streamContinuation = streamContinuations[characteristic] {
            if let error {
                streamContinuation.finish(throwing: error)
                streamContinuations[characteristic] = nil
            } else {
                streamContinuation.yield(characteristic.value)
            }
        }
        if let continuation = continuations[characteristic] {
            if let error {
                continuation.resume(throwing: error)
            } else {
                continuation.resume(returning: characteristic.value)
            }
            continuations[characteristic] = nil
        }
    }
    
    private func didWriteValueFor(characteristic: CBCharacteristic, error: Error?) {
        if let error {
            continuations[characteristic]?.resume(throwing: error)
        } else {
            continuations[characteristic]?.resume(returning: characteristic.value)
        }
        continuations[characteristic] = nil
    }
    
    private var continuations: [CBCharacteristic: UnsafeContinuation<Data?, Error>] = [:]
    
    func write(_ value: Data, to uuid: CBUUID) async throws {
        guard let characteristic = peripheral.services?.compactMap(\.characteristics).flatMap({$0}).first(where: { $0.uuid == uuid }) else {
            throw BluetoothTemperatureSensorError.characteristicNotFound
        }
        
        guard continuations[characteristic] == nil else {
            throw BluetoothTemperatureSensorError.characteristicInUse
        }
        
        _ = try await withUnsafeThrowingContinuation { (continuation: UnsafeContinuation<Data?, Error>) in
            Task { @MainActor in
                continuations[characteristic] = continuation
                peripheral.writeValue(value, for: characteristic, type: .withResponse)
            }
        }
    }
    
    func read(from uuid: CBUUID) async throws -> Data? {
        guard let characteristic = peripheral.services?.compactMap(\.characteristics).flatMap({$0}).first(where: { $0.uuid == uuid }) else {
            throw BluetoothTemperatureSensorError.characteristicNotFound
        }
        
        guard continuations[characteristic] == nil else {
            throw BluetoothTemperatureSensorError.characteristicInUse
        }
        
        return try await withUnsafeThrowingContinuation { (continuation: UnsafeContinuation<Data?, Error>) in
            Task { @MainActor in
                continuations[characteristic] = continuation
                peripheral.readValue(for: characteristic)
            }
        }
    }
    
    private var streamContinuations: [CBCharacteristic: AsyncThrowingStream<Data?, Error>.Continuation] = [:]
    
    func subscribeToNotifications(from uuid: CBUUID) throws -> AsyncThrowingStream<Data?, Error> {
        guard let characteristic = peripheral.services?.compactMap(\.characteristics).flatMap({$0}).first(where: { $0.uuid == uuid }) else {
            throw BluetoothTemperatureSensorError.characteristicNotFound
        }
        
        guard continuations[characteristic] == nil else {
            throw BluetoothTemperatureSensorError.characteristicInUse
        }
        
        return .init { continuation in
            Task { @MainActor in
                streamContinuations[characteristic] = continuation
                continuation.onTermination = { [peripheral] _ in
                    peripheral.setNotifyValue(false, for: characteristic)
                }
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }
}

extension BluetoothTemperatureSensor: Identifiable {
    var id: UUID {
        peripheral.identifier
    }
}

extension BluetoothTemperatureSensor: Hashable {
    static func == (lhs: BluetoothTemperatureSensor, rhs: BluetoothTemperatureSensor) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        id.hash(into: &hasher)
    }
}

extension Array where Element == UInt8 {
    func toHexString() -> String {
        var string = ""

        for val in self {
            string = string + String(format: "%02X", val)
        }

        return string
    }
}
