import Foundation

extension Data {
    var floatValue: Float? {
        guard count > 3 else {
            return nil
        }
        
        return Float(bitPattern: UInt32(littleEndian: self.withUnsafeBytes { $0.load(as: UInt32.self) }))
    }
    
    var uInt32Value: UInt32? {
        guard count > 3 else {
            return nil
        }
        return UInt32(littleEndian: self.withUnsafeBytes { $0.load(as: UInt32.self) })
    }
}
