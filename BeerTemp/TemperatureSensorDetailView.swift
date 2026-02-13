import BeerTempFeatures
import Charts
import ComposableArchitecture
import SwiftUI

struct TemperatureSensorDetailView: View {
  @Bindable var store: StoreOf<SensorDetail>

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        if let value = store.valueInCelcius {
          Text(
            "\(value.formatted(.number.precision(.fractionLength(3)))) °C"
          )
          .font(.title2.monospacedDigit())
        } else {
          Text("No value received yet")
            .foregroundStyle(.secondary)
        }
        Spacer()
        if store.targetValue != nil {
          Circle()
            .fill(indicatorColor)
            .frame(width: 12, height: 12)
        }
      }
      Chart {
        ForEach(store.pastValues) { logValue in
          LineMark(
            x: .value("Time", logValue.date),
            y: .value("Temperature in °C", logValue.value)
          )
          .interpolationMethod(.monotone)
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
    .navigationTitle(store.name ?? "Unknown Sensor")
    .toolbar {
      Button {
        store.send(.setTargetButtonTapped)
      } label: {
        Image(systemName: "target")
      }
    }
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
    .alert(
      "Set target value",
      isPresented: $store.isTargetValueAlertShown
    ) {
      TextField("Target value", text: $store.targetValueInput)
        .keyboardType(.decimalPad)
      Button("Set new target value") {
        store.send(.setTargetConfirmed)
      }
      Button("Cancel", role: .cancel) {}
    } message: {}
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
    guard let target = store.targetValue, let temp = store.valueInCelcius else {
      return .secondary
    }
    let diff = abs(temp - target)
    if diff <= 1 {
      return .green
    } else {
      return .orange
    }
  }
}
