import BeerTempFeatures
import ComposableArchitecture
import SwiftUI

@main
struct BeerTempApp: App {
  let store: StoreOf<AppFeature> = {
    #if targetEnvironment(simulator)
      Store(initialState: AppFeature.State()) {
        AppFeature()
      } withDependencies: {
        $0.bluetoothClient = .simulator
      }
    #else
      Store(initialState: AppFeature.State()) {
        AppFeature()
      }
    #endif
  }()

  var body: some Scene {
    WindowGroup {
      TemperatureSensorListView(
        store: store.scope(state: \.sensorList, action: \.sensorList)
      )
    }
  }
}
