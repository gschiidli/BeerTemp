import ActivityKit
import BeerTempLiveActivityShared
import Charts
import SwiftUI
import WidgetKit

struct LockScreenLiveActivityView: View {
  let context: ActivityViewContext<BeerTempLiveActivityAttributes>

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(context.attributes.sensorName)
          .font(.headline)
        Spacer()
        Text(temperatureString)
          .font(.title2.monospacedDigit())
        if context.state.targetValue != nil {
          Circle()
            .fill(indicatorColor)
            .frame(width: 10, height: 10)
        }
      }

      Chart {
        ForEach(Array(context.state.chartPoints.enumerated()), id: \.offset) { _, point in
          LineMark(
            x: .value("Time", point.date),
            y: .value("Temp", point.value)
          )
          .interpolationMethod(.monotone)
        }
        if let target = context.state.targetValue {
          let tolerance = context.state.targetTolerance
          RectangleMark(
            yStart: .value("Lower", target - tolerance),
            yEnd: .value("Upper", target + tolerance)
          )
          .foregroundStyle(indicatorColor.opacity(0.15))
          RuleMark(y: .value("Target", target))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
            .foregroundStyle(indicatorColor)
        }
      }
      .chartXAxis(.hidden)
      .chartYScale(domain: chartYDomain)
      .frame(height: 80)
    }
    .padding()
  }

  private var temperatureString: String {
    "\(context.state.currentTemperature.formatted(.number.precision(.fractionLength(1)))) °C"
  }

  private var indicatorColor: Color {
    colorForStatus(context.state.indicatorStatus)
  }

  private var chartYDomain: ClosedRange<Double> {
    let values = context.state.chartPoints.map(\.value)
    var lo = values.min() ?? 0
    var hi = values.max() ?? 100
    if let target = context.state.targetValue {
      let tolerance = context.state.targetTolerance
      lo = min(lo, target - tolerance)
      hi = max(hi, target + tolerance)
    }
    let padding = max((hi - lo) * 0.1, 0.5)
    return (lo - padding)...(hi + padding)
  }
}
