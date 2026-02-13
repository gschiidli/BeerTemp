import Foundation
import CoreBluetooth

final class CentralManagerDelegate: NSObject, @unchecked Sendable {
    enum DelegateEvents: @unchecked Sendable {
        case didUpdateState
        case didDiscover(peripheral: CBPeripheral, advertisementData: [String : Any], rssi: Double)
        case didConnect(peripheral: CBPeripheral)
        case didFailToConnect(peripheral: CBPeripheral, error: Error?)
        case didDisconnectPeripheral(peripheral: CBPeripheral, error: Error?)
    }
    
    let delegateEventStream: AsyncStream<DelegateEvents>
    private let delegateEventStreamContinuation: AsyncStream<DelegateEvents>.Continuation
    
    override init() {
        let streamAndContinuation = AsyncStream<DelegateEvents>.makeStream()
        
        self.delegateEventStream = streamAndContinuation.stream
        self.delegateEventStreamContinuation = streamAndContinuation.continuation
        
        super.init()
    }
    
    deinit {
        delegateEventStreamContinuation.finish()
    }
}

extension CentralManagerDelegate: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        delegateEventStreamContinuation.yield(.didUpdateState)
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        delegateEventStreamContinuation.yield(.didDiscover(peripheral: peripheral, advertisementData: advertisementData, rssi: RSSI.doubleValue))
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        delegateEventStreamContinuation.yield(.didConnect(peripheral: peripheral))
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        delegateEventStreamContinuation.yield(.didFailToConnect(peripheral: peripheral, error: error))
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        delegateEventStreamContinuation.yield(.didDisconnectPeripheral(peripheral: peripheral, error: error))
    }
}
