import ComposableArchitecture

@Reducer
public struct AppFeature {
  @ObservableState
  public struct State: Equatable {
    public var sensorList = SensorList.State()

    public init() {}
  }

  public enum Action {
    case sensorList(SensorList.Action)
  }

  public init() {}

  public var body: some ReducerOf<Self> {
    Scope(state: \.sensorList, action: \.sensorList) {
      SensorList()
    }
  }
}
