import Foundation
import CoreBluetooth

class PeripheralDelegate: NSObject {
    enum DelegateEvents {
        case didDiscoverServices(error: Error?)
        case didDiscoverCharacteristicsFor(service: CBService, error: Error?)
        case didUpdateValueFor(characteristic: CBCharacteristic, error: Error?)
        case didWriteValueFor(characteristic: CBCharacteristic, error: Error?)
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

extension PeripheralDelegate: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        delegateEventStreamContinuation.yield(.didDiscoverServices(error: error))
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        delegateEventStreamContinuation.yield(.didDiscoverCharacteristicsFor(service: service, error: error))
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        delegateEventStreamContinuation.yield(.didUpdateValueFor(characteristic: characteristic, error: error))
    }
    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        delegateEventStreamContinuation.yield(.didWriteValueFor(characteristic: characteristic, error: error))
    }
}
