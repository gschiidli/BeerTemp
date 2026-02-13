import BeerTempFeatures
import ComposableArchitecture
import SwiftUI

struct TemperatureSensorListView: View {
  @Bindable var store: StoreOf<SensorList>

  @Environment(\.scenePhase) var scenePhase

  var body: some View {
    NavigationStack(path: $store.scope(state: \.path, action: \.path)) {
      List {
        if store.sensors.isEmpty {
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
          ForEach(
            store.scope(state: \.sensors, action: \.sensors),
            id: \.state.id
          ) { cardStore in
            TemperatureSensorCardView(store: cardStore)
              .onTapGesture {
                store.send(.sensorTapped(id: cardStore.state.id))
              }
              .listRowSeparator(.hidden)
          }
        }
      }
      .listStyle(.plain)
      .refreshable {
        store.send(.pullToRefreshTriggered)
      }
      .navigationTitle("Discovered devices")
    } destination: { detailStore in
      TemperatureSensorDetailView(store: detailStore)
    }
    .task {
      store.send(.onAppear)
    }
    .onChange(of: scenePhase) { _, newValue in
      store.send(.scenePhaseChanged(newValue))
    }
  }
}
