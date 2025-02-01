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
        List {
            if sensorManager.sensorArray.isEmpty {
                VStack(alignment: .center) {
                    Image(systemName: "thermometer.medium.slash")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 100, height: 100)
                        .padding(.top, 100)
                        .padding(.bottom, 16)
                    Text("No temperature sensors discovered")
                        .font(.headline)
                    Text("Pull down to search.")
                        .multilineTextAlignment(.center)
                        .font(.subheadline)
                }
                .frame(maxWidth: .infinity)
                .listRowSeparator(.hidden)
            } else {
                ForEach(sensorManager.sensorArray) { sensor in
                    TemperatureSensorCardView(sensor: sensor)
                        .listRowSeparator(.hidden)
                }
            }
        }
        .listStyle(.plain)
        .refreshable {
            do {
                try await sensorManager.scannForSensors()
            } catch {

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
    NavigationView {
        TemperatureSensorListView(
            sensorManager: BluetoothTemperatureSensorManager())
    }
}
