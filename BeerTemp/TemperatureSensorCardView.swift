import SwiftUI

struct TemperatureSensorCardView: View {
    let sensor: BluetoothTemperatureSensor
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Sensor \(sensor.name ?? "Undefined")")
            Text("ID: \(sensor.id)")
                .font(.caption)
            Text("Connection state: \(connectionState)")
                .font(.caption)
            HStack {
                Spacer()
                if let value = sensor.valueInCelcius {
                    Text("\(value.formatted(.number.precision(.fractionLength(3)))) °C")
                } else {
                    Text("No value received yet")
                }
            }
        }
        .padding()
        .background(Color.secondary)
        .cornerRadius(3.0)
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
        case .failedConnection:
            "failedConnection"
        }
    }
}
