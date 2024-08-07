import Foundation

extension Data {
    var floatValue: Float {
        Float(bitPattern: UInt32(littleEndian: self.withUnsafeBytes { $0.load(as: UInt32.self) }))
    }
}
