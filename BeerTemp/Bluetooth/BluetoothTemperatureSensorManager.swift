import CoreBluetooth
import Foundation
import Observation

enum BluetoothTemperatureSensorManagerError: Error {
    case invalidState(state: CBManagerState)
}

@MainActor
@Observable
class BluetoothTemperatureSensorManager {
    var sensors: Set<BluetoothTemperatureSensor> = []
    
    var sensorArray: Array<BluetoothTemperatureSensor> {
        .init(sensors)
    }
    
    private var continuations:
        [CBPeripheral: UnsafeContinuation<Void, Error>] = [:]
    
    private let centralManager: CBCentralManager
    
    init() {
        let centralManagerDelegate = CentralManagerDelegate()
        self.centralManager = CBCentralManager(delegate: centralManagerDelegate, queue: .global(qos: .userInitiated))
//                                               , options: [CBCentralManagerOptionRestoreIdentifierKey: "bluetoothTemperatureSensorManagerRestoreIdentifier"])
        
        subscirbeToDelegateEvents(centralManager: centralManager, centralManagerDelegate: centralManagerDelegate)
    }
    
    private func subscirbeToDelegateEvents(centralManager: CBCentralManager, centralManagerDelegate: CentralManagerDelegate) {
        Task { @MainActor [weak self] in
            for await event in centralManagerDelegate.delegateEventStream {
                guard let self else {
                    return
                }
                
                switch event {
                case .didUpdateState:
                    didUpdateState(for: centralManager)
                case let .didDiscover(peripheral, advertisementData, _):
                    didDiscover(peripheral: peripheral, advertisementData: advertisementData, on: centralManager)
                case let .didConnect(peripheral):
                    didConnect(to: peripheral, on: centralManager)
                case let .didFailToConnect(peripheral, error):
                    didFailToConnect(to: peripheral, with: error, on: centralManager)
                case let .didDisconnectPeripheral(peripheral, error):
                    didDisconnect(from: peripheral, with: error, on: centralManager)
                }
            }
        }
    }
    
    private func didUpdateState(for centralManager: CBCentralManager) {
        switch centralManager.state {
        case .unknown, .resetting, .unsupported, .unauthorized, .poweredOff:
            return
        case .poweredOn:
            return
        @unknown default:
            return
        }
    }
    
    func scannForSensors() async throws {
        switch centralManager.state {
        case .unknown, .resetting, .unsupported, .unauthorized, .poweredOff:
            throw BluetoothTemperatureSensorManagerError.invalidState(state: centralManager.state)
        case .poweredOn:
            centralManager.scanForPeripherals(withServices: [BluetoothTemperatureSensor.serviceUUID])
//            , options: [CBCentralManagerScanOptionAllowDuplicatesKey: NSNumber(booleanLiteral: true)])
        @unknown default:
            throw BluetoothTemperatureSensorManagerError.invalidState(state: centralManager.state)
        }
    }
    
    private func didDiscover(peripheral: CBPeripheral, advertisementData:[String : Any], on centralManager: CBCentralManager) {
        if let foundSensor = sensors.first(where: { $0.id == peripheral.identifier }) {
            foundSensor.didFindPeripheralAgain(with: advertisementData)
        } else {
            let sensor = BluetoothTemperatureSensor(peripheral: peripheral, manager: self)
            sensors.insert(sensor)
        }
    }
    
    private func didConnect(to peripheral: CBPeripheral, on centralManager: CBCentralManager) {
        continuations[peripheral]?.resume(returning: ())
        
        guard let sensor = sensors.first(where: { $0.id == peripheral.identifier }) else {
            return
        }
        
        sensor.didConnect()
    }
    
    private func didFailToConnect(to peripheral: CBPeripheral, with error: Error?, on centralManager: CBCentralManager) {
        if let error {
            continuations[peripheral]?.resume(throwing: error)
        }
        
        guard let sensor = sensors.first(where: { $0.id == peripheral.identifier }) else {
            return
        }
        
        sensor.didFailToConnect(with: error)
    }
    
    private func didDisconnect(from peripheral: CBPeripheral, with error: Error?, on centralManager: CBCentralManager) {
        guard let sensor = sensors.first(where: { $0.id == peripheral.identifier }) else {
            return
        }
        
        sensor.didDisconnect(with: error)
    }
    
    func connect(to sensor: BluetoothTemperatureSensor) async throws {
        try await withUnsafeThrowingContinuation { (continuation: UnsafeContinuation<Void, Error>) in
            continuations[sensor.peripheral] = continuation
            centralManager.connect(sensor.peripheral)
        }
    }
    
    func disconnect(from sensor: BluetoothTemperatureSensor) {
        centralManager.cancelPeripheralConnection(sensor.peripheral)
    }
}

