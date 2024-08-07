import SwiftUI

struct TemperatureSensorCardView: View {
    let sensor: BluetoothTemperatureSensor
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Sensor \(sensor.id)")
                .font(.title)
            Text("Connection state: \(connectionState)")
                .font(.caption)
            HStack {
                Spacer()
                if let value = sensor.valueInCelcius {
                    Text("Value: \(value)")
                } else {
                    Text("No value received yet")
                }
            }
        }
        .padding()
        .background(Color.secondary)
        .cornerRadius(3.0)
    }
    
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
