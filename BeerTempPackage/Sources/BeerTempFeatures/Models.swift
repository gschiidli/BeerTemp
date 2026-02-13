import Foundation
import SwiftUI

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

public struct ExtrapolationPoint: Equatable, Sendable {
  public let date: Date
  public let value: Double
}

public struct TemperatureExtrapolation: Equatable, Sendable {
  public let points: [ExtrapolationPoint]
  public let estimatedSecondsRemaining: TimeInterval?

  /// Fits `T(t) = T_0 + C * (1 - e^(-k*t))` purely to the last
  /// `fitWindow` seconds of measured data, then always extrapolates
  /// `extrapolationWindow` seconds into the future.
  public static func compute(
    pastValues: [LogValue],
    targetValue: Double? = nil,
    fitWindow: TimeInterval = 10,
    extrapolationWindow: TimeInterval = 120
  ) -> TemperatureExtrapolation? {
    guard pastValues.count >= 3 else { return nil }

    // Use only the last `fitWindow` seconds of data for fitting
    let cutoff = pastValues[pastValues.count - 1].date.addingTimeInterval(-fitWindow)
    let recent = pastValues.filter { $0.date >= cutoff }
    guard recent.count >= 3 else { return nil }

    let t0Date = recent[0].date
    let t0Value = recent[0].value

    // Compute relative times and values
    var tValues: [Double] = []
    var yValues: [Double] = []
    for pv in recent {
      tValues.append(pv.date.timeIntervalSince(t0Date))
      yValues.append(pv.value - t0Value)
    }

    // Grid search over k (log-spaced), analytic solve for C
    // Model: y(t) = C * (1 - e^(-k*t))
    let numK = 100
    let logKMin = -6.0
    let logKMax = -1.0
    var bestK = 0.0
    var bestC = 0.0
    var bestResidual = Double.infinity

    for i in 0..<numK {
      let logK = logKMin + (logKMax - logKMin) * Double(i) / Double(numK - 1)
      let k = pow(10, logK)

      var sumYF = 0.0
      var sumFF = 0.0
      for j in 0..<tValues.count {
        let f = 1 - exp(-k * tValues[j])
        sumYF += yValues[j] * f
        sumFF += f * f
      }
      guard sumFF > 0 else { continue }
      let c = sumYF / sumFF

      var residual = 0.0
      for j in 0..<tValues.count {
        let f = 1 - exp(-k * tValues[j])
        let diff = yValues[j] - c * f
        residual += diff * diff
      }

      if residual < bestResidual {
        bestResidual = residual
        bestK = k
        bestC = c
      }
    }

    guard bestK > 0, abs(bestC) > 0.01 else { return nil }

    let tLast = tValues[tValues.count - 1]

    // Always generate extrapolation points for the next `extrapolationWindow`
    let numPoints = 50
    var points: [ExtrapolationPoint] = []
    for i in 0...numPoints {
      let t = tLast + extrapolationWindow * Double(i) / Double(numPoints)
      let temp = t0Value + bestC * (1 - exp(-bestK * t))
      let date = t0Date.addingTimeInterval(t)
      points.append(ExtrapolationPoint(date: date, value: temp))
    }

    // Compute ETA: when does the fitted curve cross targetValue?
    var eta: TimeInterval? = nil
    if let targetValue {
      let ratio = (targetValue - t0Value) / bestC
      if ratio > 0, ratio < 1 {
        let tHit = -log(1 - ratio) / bestK
        if tHit > tLast {
          eta = tHit - tLast
        }
      }
    }

    return TemperatureExtrapolation(
      points: points,
      estimatedSecondsRemaining: eta
    )
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
