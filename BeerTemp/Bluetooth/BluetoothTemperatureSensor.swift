import CoreBluetooth
import Foundation
import Observation

@MainActor
@Observable
class BluetoothTemperatureSensor {
    static let serviceUUID = CBUUID(string: "4fafc201-1fb5-459e-8fcc-c5c9c331914b")
    static let characteristicUUID = CBUUID(string: "beb5483e-36e1-4688-b7f5-ea07361b26a8")
    
    enum ConnectionState {
        case disconnected
        case connecting
        case connected
        case failedConnection(error: Error?)
    }
    
    private let peripheral: CBPeripheral
    
    var state: ConnectionState = .disconnected
    var valueInCelcius: Double?
    
    var name: String? {
        peripheral.name
    }
    
    init(peripheral: CBPeripheral) {
        let peripheralDelegate = PeripheralDelegate()
        peripheral.delegate = peripheralDelegate
        self.peripheral = peripheral
        
        subscirbeToDelegateEvents(peripheralDelegate: peripheralDelegate)
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
                }
            }
        }
    }
    
    func didConnect() {
        peripheral.discoverServices([Self.serviceUUID])
        state = .connected
    }
    
    func didFailToConnect(with error: Error?) {
        state = .failedConnection(error: error)
    }
    
    func didDisconnect(with error: Error?) {
        state = .failedConnection(error: error)
    }
    
    private func didDiscoverServices(error: Error?) {
        if let service = peripheral.services?.first(where: { $0.uuid == Self.serviceUUID }) {
            self.peripheral.discoverCharacteristics([Self.characteristicUUID], for: service)
        }
    }
    
    private func didDiscoverCharacteristicsFor(service: CBService, error: Error?) {
        if service.uuid == BluetoothTemperatureSensor.serviceUUID,
           let characteristic = service.characteristics?.first(where: { $0.uuid == Self.characteristicUUID }) {
            self.peripheral.setNotifyValue(true, for: characteristic)
        }
    }
    
    func didUpdateValueFor(characteristic: CBCharacteristic, error: Error?) {
        if characteristic.uuid == Self.characteristicUUID,
           let valueData = characteristic.value
        {
            valueInCelcius = Double(valueData.floatValue)
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
