import BeerTempFeatures
import ComposableArchitecture
import SwiftUI

@main
struct BeerTempApp: App {
  let store = Store(initialState: AppFeature.State()) {
    AppFeature()
  }

  var body: some Scene {
    WindowGroup {
      TemperatureSensorListView(
        store: store.scope(state: \.sensorList, action: \.sensorList)
      )
    }
  }
}
