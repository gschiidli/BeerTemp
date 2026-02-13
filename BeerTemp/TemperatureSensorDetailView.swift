import BeerTempFeatures
import Charts
import ComposableArchitecture
import SwiftUI

struct TemperatureSensorDetailView: View {
  @Bindable var store: StoreOf<SensorDetail>

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("Sensor \(store.name ?? "Undefined")")
      Text("ID: \(store.sensorID)")
        .font(.caption)
      Text("Connection state: \(connectionStateText)")
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
      Button("Set new target value") {
        store.send(.setTargetButtonTapped)
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

  private var connectionStateText: String {
    switch store.connectionState {
    case .disconnected:
      "disconnected"
    case .connecting:
      "connecting"
    case .connected:
      "connected"
    case let .failedConnection(errorDescription):
      if let errorDescription {
        "failedConnection \(errorDescription)"
      } else {
        "failedConnection"
      }
    }
  }
}
