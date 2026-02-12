import Charts
import SwiftUI

struct TemperatureSensorDetailView: View {
    @Bindable var sensor: BluetoothTemperatureSensor
    
    @State var targetValue = "65"
    @State var isTargetValueAlertShown = false

    @FocusState var textFieldFocusState

    @Environment(\.scenePhase) var scenePhase

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Sensor \(sensor.name ?? "Undefined")")
            Text("ID: \(sensor.id)")
                .font(.caption)
            Text("Connection state: \(sensor.state)")
                .font(.caption)
            HStack {
                Spacer()
                if let value = sensor.valueInCelcius {
                    Text(
                        "\(value.formatted(.number.precision(.fractionLength(3)))) °C"
                    )
                } else {
                    Text("No value received yet")
                }
            }
            Button("Set new target value") {
                targetValue = sensor.targetValueString
                isTargetValueAlertShown = true
            }
            Chart(sensor.pastValues) {
                LineMark(
                    x: .value("Month", $0.date),
                    y: .value("Temperature in °C", $0.value)
                )
            }
        }
        .onChange(of: scenePhase) { _, newValue in
            sensor.scenePhase = newValue
        }
        .padding()
        .background(backgroundColor)
        .cornerRadius(3.0)
        .sheet(isPresented: $sensor.hasLogFileToExport) {
            if let logFile = sensor.logFile {
                ShareSheet(items: [logFile])
            }
        }
        .alert(
            "Set target value",
            isPresented: $isTargetValueAlertShown
        ) {
            TextField("Target value", text: $targetValue)
                .focused($textFieldFocusState)
                .keyboardType(.decimalPad)
            Button("Set new target value") {
                Task {
                    try await sensor.setTargetValue(to: targetValue)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {}
    }

    @MainActor
    private var backgroundColor: Color {
        switch sensor.targetValueProgress {
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

    @MainActor
    private var connectionState: String {
        switch sensor.state {
        case .disconnected:
            "disconnected"
        case .connecting:
            "connecting"
        case .connected:
            "connected"
        case let .failedConnection(error):
            if let error {
                "failedConnection \(error)"
            } else {
                "failedConnection"
            }
        }
    }
}
