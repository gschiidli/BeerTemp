import ActivityKit
import Foundation

public struct BeerTempLiveActivityAttributes: ActivityAttributes {
  public var sensorName: String

  public init(sensorName: String) {
    self.sensorName = sensorName
  }

  public struct ContentState: Codable, Hashable, Sendable {
    public var currentTemperature: Double
    public var targetValue: Double?
    public var targetTolerance: Double
    public var trend: TrendDirection
    public var indicatorStatus: IndicatorStatus
    public var chartPoints: [ChartPoint]
    public var etaSeconds: Double?

    public init(
      currentTemperature: Double,
      targetValue: Double?,
      targetTolerance: Double,
      trend: TrendDirection,
      indicatorStatus: IndicatorStatus,
      chartPoints: [ChartPoint],
      etaSeconds: Double? = nil
    ) {
      self.currentTemperature = currentTemperature
      self.targetValue = targetValue
      self.targetTolerance = targetTolerance
      self.trend = trend
      self.indicatorStatus = indicatorStatus
      self.chartPoints = chartPoints
      self.etaSeconds = etaSeconds
    }
  }
}

public enum TrendDirection: String, Codable, Hashable, Sendable {
  case heating
  case cooling
  case stable
}

public enum IndicatorStatus: String, Codable, Hashable, Sendable {
  case onTarget
  case approaching
  case farAway
  case noTarget
}

public struct ChartPoint: Codable, Hashable, Sendable {
  public var timestamp: TimeInterval
  public var value: Double

  public init(timestamp: TimeInterval, value: Double) {
    self.timestamp = timestamp
    self.value = value
  }

  public var date: Date {
    Date(timeIntervalSinceReferenceDate: timestamp)
  }
}
