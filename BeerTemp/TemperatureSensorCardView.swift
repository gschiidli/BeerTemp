import BeerTempFeatures
import Charts
import ComposableArchitecture
import SwiftUI

struct TemperatureSensorCardView: View {
  let store: StoreOf<SensorCard>

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text(store.name ?? "Unknown Sensor")
          .font(.headline)
        Spacer()
        Circle()
          .fill(indicatorColor)
          .frame(width: 12, height: 12)
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
            y: .value("Temperature in °C", logValue.value)
          )
          .interpolationMethod(.catmullRom)
        }
        if let target = store.targetValue {
          RectangleMark(
            yStart: .value("Lower", target - 1),
            yEnd: .value("Upper", target + 1)
          )
          .foregroundStyle(indicatorColor.opacity(0.15))
          RuleMark(y: .value("Target", target))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
            .foregroundStyle(indicatorColor)
        }
      }
      .chartXAxis(.hidden)
      .chartYScale(domain: chartYDomain)
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

  private var chartYDomain: ClosedRange<Double> {
    let values = store.pastValues.map(\.value)
    var lo = values.min() ?? 0
    var hi = values.max() ?? 100
    if let target = store.targetValue {
      lo = min(lo, target - 1)
      hi = max(hi, target + 1)
    }
    let padding = max((hi - lo) * 0.1, 0.5)
    return (lo - padding)...(hi + padding)
  }

  private var indicatorColor: Color {
    switch store.targetValueProgress {
    case .onTheWay:
      Color.orange
    case .onPoint:
      Color.green
    case .passedThePoint:
      Color.red
    case .notInProgress:
      Color.secondary
    }
  }
}
