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

struct LogValue: Identifiable {
    let value: Double
    let date: Date

    var id: Date {
        date
    }
}

@MainActor
@Observable
class BluetoothTemperatureSensor {
    static let serviceUUID = CBUUID(
        string: "4fafc201-1fb5-459e-8fcc-c5c9c331914b")
    static let valueCharacteristicUUID = CBUUID(
        string: "beb5483e-36e1-4688-b7f5-ea07361b26a8")
    static let targetValueCharacteristicUUID = CBUUID(
        string: "44e7fcba-4db0-4c41-b0a8-a34fc66afd74")
    static let targetValueProgressCharacteristicUUID = CBUUID(
        string: "6d913149-d0fc-4d85-9dd5-615248f2bee0")

    enum ConnectionState {
        case disconnected
        case connecting
        case connected
        case failedConnection(error: Error?)
    }

    let peripheral: CBPeripheral
    private weak var manager: BluetoothTemperatureSensorManager?

    var state: ConnectionState = .disconnected

    var pastValues = [LogValue]() {
        didSet {
            let now = Date()
            if let oldestValue = pastValues.first,
                oldestValue.date.distance(to: now) > 30 * 60
            {
                pastValues = pastValues.filter {
                    $0.date.distance(to: now) < 30 * 60
                }
            }
        }
    }

    var valueInCelcius: Double? {
        didSet {
            logger.log(valueInCelcius)
        }
    }

    private var setTargetDebounceTask: Task<Void, Error>?

    var targetValue: Double?
    var targetValueProgress: TargetValueProgress = .notInProgress

    var scenePhase: ScenePhase = .background

    var targetValueString: String {
        targetValue?.formatted(.number.precision(.fractionLength(3))) ?? ""
    }

    var name: String? {
        peripheral.name
    }

    let logger: CsvLogger

    var logFile: URL?

    var hasLogFileToExport: Bool {
        get {
            logFile != nil
        }
        set {
            if newValue == false {
                logFile = nil
            }
        }
    }

    init(peripheral: CBPeripheral, manager: BluetoothTemperatureSensorManager) {
        let peripheralDelegate = PeripheralDelegate()
        peripheral.delegate = peripheralDelegate

        logger = CsvLogger(fileName: "\(peripheral.name ?? "Unknown").csv")

        self.peripheral = peripheral
        self.manager = manager

        subscirbeToDelegateEvents(peripheralDelegate: peripheralDelegate)

        UNUserNotificationCenter.current().requestAuthorization(options: [
            .alert, .badge, .sound,
        ]) { success, error in
            if success {
                print("All set!")
            } else if let error {
                print(error.localizedDescription)
            }
        }
    }

    private func subscirbeToDelegateEvents(
        peripheralDelegate: PeripheralDelegate
    ) {
        Task { @MainActor [weak self] in
            for await event in peripheralDelegate.delegateEventStream {
                guard let self else {
                    return
                }

                switch event {
                case .didDiscoverServices(let error):
                    didDiscoverServices(error: error)
                case .didDiscoverCharacteristicsFor(let service, let error):
                    didDiscoverCharacteristicsFor(
                        service: service, error: error)
                case .didUpdateValueFor(let characteristic, let error):
                    didUpdateValueFor(
                        characteristic: characteristic, error: error)
                case .didWriteValueFor(let characteristic, let error):
                    didWriteValueFor(
                        characteristic: characteristic, error: error)
                }
            }
        }
    }
    
    func setTargetValue(to newValue: String) async throws {
        let newTargetValue = try Double(newValue, format: .number)
        
        guard targetValue != newTargetValue else {
            return
        }
        
        targetValue = newTargetValue
        
        try await setTargetValue(to: targetValue)
    }

    func setTargetValue(to newValue: Double?) async throws {
        refreshTargetValueProgressSubscription(for: newValue)

        if let newValue {
            let bytes = withUnsafeBytes(
                of: Float(newValue).bitPattern.littleEndian
            ) { Array($0) }
            try await write(Data(bytes), to: Self.targetValueCharacteristicUUID)
        } else {
            try await write(Data(), to: Self.targetValueCharacteristicUUID)
        }

        let targetValueData = try await read(
            from: Self.targetValueCharacteristicUUID)

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

            for try await targetValueProgressData
                in try subscribeToNotifications(
                    from: Self.targetValueProgressCharacteristicUUID)
            {
                switch targetValueProgressData?.first.flatMap(
                    TargetValueProgress.init)
                {
                case .none:
                    targetValueProgress = .notInProgress
                case .some(let targetValueProgress):
                    switch scenePhase {
                    case .background:
                        sendLocalNotification(
                            oldTargetValueProgress: self.targetValueProgress,
                            newTargetValueProgress: targetValueProgress)
                    case .inactive, .active:
                        break
                    @unknown default:
                        break
                    }
                    self.targetValueProgress = targetValueProgress
                }
            }
        }
    }

    func didFindPeripheralAgain(with advertisementData: [String: Any]) {
        if let manufacturerData = advertisementData[
            CBAdvertisementDataManufacturerDataKey] as? Data,
            let stringValue = String(data: manufacturerData, encoding: .utf8),
            let newValueInCelcius = Double(stringValue),
           newValueInCelcius != valueInCelcius
        {
            self.valueInCelcius = newValueInCelcius
            pastValues.append(
                LogValue(value: newValueInCelcius, date: Date()))
        }
    }

    private func sendLocalNotification(
        oldTargetValueProgress: TargetValueProgress,
        newTargetValueProgress: TargetValueProgress
    ) {
        switch (oldTargetValueProgress, newTargetValueProgress) {
        case (.onTheWay, .onPoint), (.onPoint, .passedThePoint),
            (.passedThePoint, .onPoint):
            break
        case (_, _):
            return
        }

        let content = UNMutableNotificationContent()

        switch newTargetValueProgress {
        case .notInProgress, .onTheWay:
            return
        case .onPoint:
            content.title = "Target Value Reached"
        case .passedThePoint:
            content.title = "Target Value Passed"
        }
        if let targetValue {
            switch newTargetValueProgress {
            case .notInProgress, .onTheWay:
                return
            case .onPoint:
                content.subtitle =
                    "The target value of \(targetValue) was reached"
            case .passedThePoint:
                content.subtitle =
                    "The target value of \(targetValue) was passed"
            }
        } else {
            switch newTargetValueProgress {
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
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: 0.01, repeats: false)

        // choose a random identifier
        let request = UNNotificationRequest(
            identifier: UUID().uuidString, content: content, trigger: trigger)

        // add our notification request
        UNUserNotificationCenter.current().add(request)
    }
    
    func connect() async throws {
        try await manager?.connect(to: self)
    }
    
    func disconnect() {
        manager?.disconnect(from: self)
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
        if let service = peripheral.services?.first(where: {
            $0.uuid == Self.serviceUUID
        }) {
            self.peripheral.discoverCharacteristics(
                [
                    Self.valueCharacteristicUUID,
                    Self.targetValueCharacteristicUUID,
                    Self.targetValueProgressCharacteristicUUID,
                ],
                for: service
            )
        }
    }

    private func didDiscoverCharacteristicsFor(
        service: CBService, error: Error?
    ) {
        if service.uuid == BluetoothTemperatureSensor.serviceUUID {
            if service.characteristics?.contains(where: {
                $0.uuid == Self.valueCharacteristicUUID
            }) == true {
                Task { @MainActor [weak self] in
                    guard
                        let stream = try self?.subscribeToNotifications(
                            from: Self.valueCharacteristicUUID)
                    else {
                        return
                    }

                    for try await valueData in stream {
                        let valueInCelcius = valueData?.floatValue.map(
                            Double.init)
                        self?.valueInCelcius = valueInCelcius
                        if let valueInCelcius {
                            self?.pastValues.append(
                                LogValue(value: valueInCelcius, date: Date()))
                        }
                    }
                }
            }

            if service.characteristics?.contains(where: {
                $0.uuid == Self.targetValueCharacteristicUUID
            }) == true {
                Task { @MainActor [weak self] in
                    guard let self else {
                        return
                    }

                    let targetValueData = try await read(
                        from: Self.targetValueCharacteristicUUID)
                    targetValue = (targetValueData?.floatValue).map(Double.init)

                    refreshTargetValueProgressSubscription(for: targetValue)
                }
            }
        }
    }

    private func didUpdateValueFor(
        characteristic: CBCharacteristic, error: Error?
    ) {
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

    private func didWriteValueFor(
        characteristic: CBCharacteristic, error: Error?
    ) {
        if let error {
            continuations[characteristic]?.resume(throwing: error)
        } else {
            continuations[characteristic]?.resume(
                returning: characteristic.value)
        }
        continuations[characteristic] = nil
    }

    private var continuations:
        [CBCharacteristic: UnsafeContinuation<Data?, Error>] = [:]

    func write(_ value: Data, to uuid: CBUUID) async throws {
        let shouldDisconnect: Bool
        
        switch state {
        case .disconnected, .connecting, .failedConnection:
            try await connect()
            shouldDisconnect = true
        case .connected:
            shouldDisconnect = false
        }
        
        defer {
            if shouldDisconnect {
                disconnect()
            }
        }
        
        guard
            let characteristic = peripheral.services?.compactMap(
                \.characteristics
            ).flatMap({ $0 }).first(where: { $0.uuid == uuid })
        else {
            throw BluetoothTemperatureSensorError.characteristicNotFound
        }

        guard continuations[characteristic] == nil else {
            throw BluetoothTemperatureSensorError.characteristicInUse
        }

        _ = try await withUnsafeThrowingContinuation {
            (continuation: UnsafeContinuation<Data?, Error>) in
            Task { @MainActor in
                continuations[characteristic] = continuation
                peripheral.writeValue(
                    value, for: characteristic, type: .withResponse)
            }
        }
    }

    func read(from uuid: CBUUID) async throws -> Data? {
        guard
            let characteristic = peripheral.services?.compactMap(
                \.characteristics
            ).flatMap({ $0 }).first(where: { $0.uuid == uuid })
        else {
            throw BluetoothTemperatureSensorError.characteristicNotFound
        }

        guard continuations[characteristic] == nil else {
            throw BluetoothTemperatureSensorError.characteristicInUse
        }

        return try await withUnsafeThrowingContinuation {
            (continuation: UnsafeContinuation<Data?, Error>) in
            Task { @MainActor in
                continuations[characteristic] = continuation
                peripheral.readValue(for: characteristic)
            }
        }
    }

    private var streamContinuations:
        [CBCharacteristic: AsyncThrowingStream<Data?, Error>.Continuation] = [:]

    func subscribeToNotifications(from uuid: CBUUID) throws
        -> AsyncThrowingStream<Data?, Error>
    {
        guard
            let characteristic = peripheral.services?.compactMap(
                \.characteristics
            ).flatMap({ $0 }).first(where: { $0.uuid == uuid })
        else {
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

    func exportLogsTapped() {
        logFile = logger.logFileURL
    }
}

extension BluetoothTemperatureSensor: Identifiable {
    var id: UUID {
        peripheral.identifier
    }
}

extension BluetoothTemperatureSensor: Hashable {
    static func == (
        lhs: BluetoothTemperatureSensor, rhs: BluetoothTemperatureSensor
    ) -> Bool {
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
