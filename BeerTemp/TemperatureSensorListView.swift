//
//  ContentView.swift
//  BeerTemp
//
//  Created by Konstantin Braun on 06.08.24.
//

import SwiftUI

struct DataUpdate {
    let temp: Double
}

struct TemperatureSensorListView: View {
    let sensorManager: BluetoothTemperatureSensorManager
    
    var body: some View {
        Group {
            ScrollView(.vertical) {
                if sensorManager.sensorArray.isEmpty {
                    Text("No temperature sensors discovered")
                } else {
                    VStack {
                        ForEach(sensorManager.sensorArray) {sensor in
                            TemperatureSensorCardView(sensor: sensor)
                                .padding(.horizontal)
                        }
                    }
                }
            }
            .refreshable {
                do {
                    try await sensorManager.scannForSensors()
                } catch {
                    
                }
            }
        }
        .task {
            do {
                try await sensorManager.scannForSensors()
            } catch {
                
            }
        }
        .navigationTitle("Discovered devices")
    }
}

#Preview {
    TemperatureSensorListView(sensorManager: BluetoothTemperatureSensorManager())
}
