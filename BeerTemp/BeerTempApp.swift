//
//  BeerTempApp.swift
//  BeerTemp
//
//  Created by Konstantin Braun on 06.08.24.
//

import SwiftUI

@main
struct BeerTempApp: App {
    var body: some Scene {
        WindowGroup {
            TemperatureSensorListView(sensorManager: BluetoothTemperatureSensorManager())
        }
    }
}
