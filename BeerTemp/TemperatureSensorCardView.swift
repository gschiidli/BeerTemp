import Charts
import SwiftUI

struct TemperatureSensorCardView: View {
    @Bindable var sensor: BluetoothTemperatureSensor

    @Environment(\.scenePhase) var scenePhase

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Sensor \(sensor.name ?? "Undefined")")
            Text("ID: \(sensor.id)")
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
        .swipeActions {
            Button {
                sensor.exportLogsTapped()
            } label: {
                Text("Export Logs")
            }
        }
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
