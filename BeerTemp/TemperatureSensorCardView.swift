import BeerTempFeatures
import Charts
import ComposableArchitecture
import SwiftUI

struct TemperatureSensorCardView: View {
  let store: StoreOf<SensorCard>

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("Sensor \(store.name ?? "Undefined")")
      Text("ID: \(store.id)")
        .font(.caption)
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
      Chart(store.pastValues) {
        LineMark(
          x: .value("Month", $0.date),
          y: .value("Temperature in °C", $0.value)
        )
      }
    }
    .padding()
    .background(backgroundColor)
    .cornerRadius(3.0)
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

  private var backgroundColor: Color {
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
