import BeerTempFeatures
import Charts
import ComposableArchitecture
import SwiftUI

struct TemperatureSensorCardView: View {
  let store: StoreOf<SensorCard>
  @State private var scrollPosition: Date = Date().addingTimeInterval(-120)

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text(store.name ?? "Unknown Sensor")
          .font(.headline)
        Spacer()
        if store.targetValue != nil {
          Circle()
            .fill(indicatorColor)
            .frame(width: 12, height: 12)
        }
      }
      HStack {
        Spacer()
        if let value = store.valueInCelcius {
          Text(
            "\(value.formatted(.number.precision(.fractionLength(3)))) °C"
          )
        } else {
          Text("No value received yet")
        }
      }
      Chart {
        ForEach(store.pastValues) { logValue in
          LineMark(
            x: .value("Time", logValue.date),
            y: .value("Temperature in °C", logValue.value),
            series: .value("Series", "Measured")
          )
          .interpolationMethod(.monotone)
        }
        if let extrapolation {
          ForEach(Array(extrapolation.points.enumerated()), id: \.offset) { _, point in
            LineMark(
              x: .value("Time", point.date),
              y: .value("Temperature in °C", point.value),
              series: .value("Series", "Extrapolation")
            )
            .interpolationMethod(.monotone)
            .foregroundStyle(.gray.opacity(0.3))
            .lineStyle(StrokeStyle(lineWidth: 1.5))
          }
        }
        if let target = store.targetValue {
          let tolerance = store.targetTolerance
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
      .chartXScale(domain: chartXDomain)
      .chartScrollableAxes(.horizontal)
      .chartXVisibleDomain(length: 240)
      .chartScrollPosition(x: $scrollPosition)
      .chartYScale(domain: chartYDomain)
      .onChange(of: store.pastValues.last?.date) { _, newDate in
        scrollPosition = (newDate ?? Date()).addingTimeInterval(-120)
      }
    }
    .padding()
    .background(Color(.secondarySystemBackground))
    .clipShape(RoundedRectangle(cornerRadius: 16))
    .sheet(isPresented: Binding(
      get: { store.isShareSheetPresented },
      set: { newValue in
        if !newValue { store.send(.shareSheetDismissed) }
      }
    )) {
      if let logFile = store.logFileURL {
        ShareSheet(items: [logFile])
      }
    }
    .swipeActions {
      Button {
        store.send(.exportLogsTapped)
      } label: {
        Text("Export Logs")
      }
    }
  }

  private var extrapolation: TemperatureExtrapolation? {
    TemperatureExtrapolation.compute(
      pastValues: store.pastValues.map { (date: $0.date, value: $0.value) },
      targetValue: store.targetValue
    )
  }


  private var chartXDomain: ClosedRange<Date> {
    let now = store.pastValues.last?.date ?? Date()
    let dataStart = store.pastValues.first?.date ?? now
    let extEnd = extrapolation?.points.last?.date ?? now
    let lo = min(dataStart, now.addingTimeInterval(-120))
    let hi = max(extEnd, now.addingTimeInterval(120))
    return lo...hi
  }

  private var chartYDomain: ClosedRange<Double> {
    var values = store.pastValues.map(\.value)
    if let ext = extrapolation {
      values.append(contentsOf: ext.points.map(\.value))
    }
    var lo = values.min() ?? 0
    var hi = values.max() ?? 100
    if let target = store.targetValue {
      let tolerance = store.targetTolerance
      lo = min(lo, target - tolerance)
      hi = max(hi, target + tolerance)
    }
    let padding = max((hi - lo) * 0.1, 0.5)
    return (lo - padding)...(hi + padding)
  }

  private var indicatorColor: Color {
    guard let target = store.targetValue, let temp = store.valueInCelcius else {
      return .secondary
    }
    let diff = abs(temp - target)
    if diff <= store.targetTolerance {
      return .green
    } else if extrapolation?.estimatedSecondsRemaining != nil {
      return .orange
    } else {
      return .red
    }
  }
}
