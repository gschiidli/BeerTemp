import Foundation
import SwiftUI

@_exported import BeerTempLiveActivityShared
@_exported import TemperatureExtrapolation

public enum ConnectionState: Equatable, Sendable {
  case disconnected
  case connecting
  case connected
  case failedConnection(errorDescription: String?)
}

public enum TargetValueProgress: UInt8, Equatable, Sendable {
  case notInProgress
  case onTheWay
  case onPoint
  case passedThePoint
}

public struct LogValue: Equatable, Identifiable, Sendable {
  public let id: UUID
  public let value: Double
  public let date: Date

  public init(id: UUID, value: Double, date: Date) {
    self.id = id
    self.value = value
    self.date = date
  }
}

public struct DiscoveredSensor: Equatable, Identifiable, Sendable {
  public let id: UUID
  public let name: String?
  public let advertisedTemperature: Double?

  public init(id: UUID, name: String?, advertisedTemperature: Double?) {
    self.id = id
    self.name = name
    self.advertisedTemperature = advertisedTemperature
  }
}
