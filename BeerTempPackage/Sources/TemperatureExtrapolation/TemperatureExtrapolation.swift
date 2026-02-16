import Foundation

public struct ExtrapolationPoint: Equatable, Sendable {
  public let date: Date
  public let value: Double

  public init(date: Date, value: Double) {
    self.date = date
    self.value = value
  }
}

/// Result of fitting `y(t) = C * (1 - e^(-k*t))` to data.
public struct CurveFit: Equatable, Sendable {
  public let k: Double
  public let c: Double

  public init(k: Double, c: Double) {
    self.k = k
    self.c = c
  }

  /// Evaluate the fitted curve at time `t` (relative to t0).
  public func evaluate(at t: Double) -> Double {
    c * (1 - exp(-k * t))
  }
}

public struct TemperatureExtrapolation: Equatable, Sendable {
  public let points: [ExtrapolationPoint]
  public let estimatedSecondsRemaining: TimeInterval?

  public init(points: [ExtrapolationPoint], estimatedSecondsRemaining: TimeInterval?) {
    self.points = points
    self.estimatedSecondsRemaining = estimatedSecondsRemaining
  }

  /// Filter `pastValues` to only include the last `fitWindow` seconds.
  /// Returns `nil` if fewer than 3 points remain.
  public static func filterRecentValues(
    _ pastValues: [(date: Date, value: Double)],
    fitWindow: TimeInterval
  ) -> [(date: Date, value: Double)]? {
    guard pastValues.count >= 3 else { return nil }
    let cutoff = pastValues[pastValues.count - 1].date.addingTimeInterval(-fitWindow)
    let recent = pastValues.filter { $0.date >= cutoff }
    guard recent.count >= 3 else { return nil }
    return recent
  }

  /// Compute the numerical gradient (dy/dt) between two consecutive points.
  public static func gradient(
    _ a: (date: Date, value: Double),
    _ b: (date: Date, value: Double)
  ) -> Double {
    let dt = b.date.timeIntervalSince(a.date)
    guard dt > 0 else { return 0 }
    return (b.value - a.value) / dt
  }

  /// Starting from the latest point, walk backwards and include points
  /// as long as their gradient is consistent with the current trend.
  /// A point "extends the set" if its gradient has the same sign as the
  /// most recent segment, within a noise tolerance (°C/s).
  /// Returns `nil` if fewer than 3 consistent points are found.
  public static func filterByTrend(
    _ values: [(date: Date, value: Double)],
    noiseTolerance: Double = 0.02
  ) -> [(date: Date, value: Double)]? {
    guard values.count >= 3 else { return nil }

    let n = values.count
    // Determine trend direction from the last segment
    let lastGrad = gradient(values[n - 2], values[n - 1])
    let rising = lastGrad >= 0

    // Walk backwards from the end, collecting consistent points
    // Start with the last two points (they define the trend)
    var startIndex = n - 2
    for i in stride(from: n - 3, through: 0, by: -1) {
      let g = gradient(values[i], values[i + 1])
      // Check if this segment is consistent with the trend
      if rising {
        // For a rising trend, gradient should be non-negative (allow noise)
        if g < -noiseTolerance { break }
      } else {
        // For a falling trend, gradient should be non-positive (allow noise)
        if g > noiseTolerance { break }
      }
      startIndex = i
    }

    let result = Array(values[startIndex...])
    guard result.count >= 3 else { return nil }
    return result
  }

  /// Convert absolute `(date, value)` pairs to relative `(t, y)` arrays,
  /// where `t` is seconds since the first point and `y` is the value offset
  /// from the first point's value.
  /// Returns `(tValues, yValues, t0Date, t0Value)`.
  public static func relativize(
    _ values: [(date: Date, value: Double)]
  ) -> (tValues: [Double], yValues: [Double], t0Date: Date, t0Value: Double) {
    let t0Date = values[0].date
    let t0Value = values[0].value
    var tValues: [Double] = []
    var yValues: [Double] = []
    for pv in values {
      tValues.append(pv.date.timeIntervalSince(t0Date))
      yValues.append(pv.value - t0Value)
    }
    return (tValues, yValues, t0Date, t0Value)
  }

  /// Fit `y(t) = C * (1 - e^(-k*t))` via grid search over k (log-spaced)
  /// with analytic least-squares solve for C at each k.
  /// Returns `nil` if no valid fit is found.
  public static func fitCurve(
    tValues: [Double],
    yValues: [Double],
    kCount: Int = 100,
    logKMin: Double = -6.0,
    logKMax: Double = -1.0
  ) -> CurveFit? {
    var bestK = 0.0
    var bestC = 0.0
    var bestResidual = Double.infinity

    for i in 0..<kCount {
      let logK = logKMin + (logKMax - logKMin) * Double(i) / Double(kCount - 1)
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
    return CurveFit(k: bestK, c: bestC)
  }

  /// Generate extrapolation points starting from `tLast` for the next
  /// `window` seconds, using the fitted curve anchored at `(t0Date, t0Value)`.
  public static func generatePoints(
    fit: CurveFit,
    t0Date: Date,
    t0Value: Double,
    tLast: Double,
    window: TimeInterval,
    count: Int = 50
  ) -> [ExtrapolationPoint] {
    var points: [ExtrapolationPoint] = []
    for i in 0...count {
      let t = tLast + window * Double(i) / Double(count)
      let temp = t0Value + fit.evaluate(at: t)
      let date = t0Date.addingTimeInterval(t)
      points.append(ExtrapolationPoint(date: date, value: temp))
    }
    return points
  }

  /// Compute the ETA (seconds from `tLast`) for the fitted curve to reach
  /// `targetValue`. Returns `nil` if the target is unreachable.
  public static func estimateETA(
    fit: CurveFit,
    t0Value: Double,
    targetValue: Double,
    tLast: Double
  ) -> TimeInterval? {
    let ratio = (targetValue - t0Value) / fit.c
    guard ratio > 0, ratio < 1 else { return nil }
    let tHit = -log(1 - ratio) / fit.k
    guard tHit > tLast else { return nil }
    return tHit - tLast
  }

  /// Full pipeline: filter → trend → relativize → fit → extrapolate → ETA.
  public static func compute(
    pastValues: [(date: Date, value: Double)],
    targetValue: Double? = nil,
    fitWindow: TimeInterval = 30,
    extrapolationWindow: TimeInterval = 120
  ) -> TemperatureExtrapolation? {
    guard let windowed = filterRecentValues(pastValues, fitWindow: fitWindow) else {
      return nil
    }

    guard let recent = filterByTrend(windowed) else {
      return nil
    }

    let (tValues, yValues, t0Date, t0Value) = relativize(recent)

    guard let fit = fitCurve(tValues: tValues, yValues: yValues) else {
      return nil
    }

    let tLast = tValues[tValues.count - 1]

    let points = generatePoints(
      fit: fit,
      t0Date: t0Date,
      t0Value: t0Value,
      tLast: tLast,
      window: extrapolationWindow
    )

    let eta: TimeInterval? = if let targetValue {
      estimateETA(fit: fit, t0Value: t0Value, targetValue: targetValue, tLast: tLast)
    } else {
      nil
    }

    return TemperatureExtrapolation(points: points, estimatedSecondsRemaining: eta)
  }
}
