import BeerTempFeatures
import Charts
import ComposableArchitecture
import SwiftUI

struct TemperatureSensorDetailView: View {
  @Bindable var store: StoreOf<SensorDetail>
  @State private var scrollPosition: Date = Date().addingTimeInterval(-120)

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
            .annotation(position: .overlay, alignment: .trailing) {
              VStack(alignment: .trailing, spacing: 2) {
                Text("\(target.formatted(.number.precision(.fractionLength(0)))) ±\(tolerance.formatted(.number.precision(.fractionLength(0...1)))) °C")
                  .font(.callout)
                  .foregroundStyle(indicatorColor)
                if let eta = extrapolation?.estimatedSecondsRemaining {
                  Text("\(formattedDuration(eta)) (\(formattedTime(eta)))")
                    .font(.callout)
                    .foregroundStyle(indicatorColor.opacity(0.8))
                }
              }
              .padding(.horizontal, 6)
              .padding(.vertical, 3)
              .background(.background, in: RoundedRectangle(cornerRadius: 4))
            }
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
    .navigationTitle(store.name ?? "Unknown Sensor")
    .toolbar {
      Button {
        store.send(.toggleLiveActivityTapped)
      } label: {
        Image(
          systemName: store.isLiveActivityActive
            ? "wave.3.right.circle.fill" : "wave.3.right.circle")
      }
      Button {
        store.send(.setToleranceButtonTapped)
      } label: {
        Image(systemName: "plusminus")
      }
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
    .alert(
      "Set target tolerance",
      isPresented: $store.isToleranceAlertShown
    ) {
      TextField("Tolerance (°C)", text: $store.targetToleranceInput)
        .keyboardType(.decimalPad)
      Button("Set tolerance") {
        store.send(.setToleranceConfirmed)
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("Current: ±\(store.targetTolerance.formatted(.number.precision(.fractionLength(0...1)))) °C")
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

  private func formattedTime(_ secondsRemaining: TimeInterval) -> String {
    let arrival = Date().addingTimeInterval(secondsRemaining)
    return arrival.formatted(date: .omitted, time: .shortened)
  }

  private func formattedDuration(_ seconds: TimeInterval) -> String {
    let total = Int(seconds)
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let secs = total % 60
    if hours > 0 {
      return "~\(hours)h \(minutes)m \(secs)s"
    } else if minutes > 0 {
      return "~\(minutes)m \(secs)s"
    } else {
      return "~\(secs)s"
    }
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
