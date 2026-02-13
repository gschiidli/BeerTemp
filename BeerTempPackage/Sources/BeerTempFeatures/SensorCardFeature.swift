import ComposableArchitecture
import Foundation

@Reducer
public struct SensorCard {
  @ObservableState
  public struct State: Equatable, Identifiable {
    public let id: UUID
    public var name: String?
    public var valueInCelcius: Double?
    public var targetValue: Double?
    public var targetValueProgress: TargetValueProgress = .notInProgress
    public var pastValues: [LogValue] = []
    public var connectionState: ConnectionState = .disconnected
    public var logFileURL: URL?
    public var isShareSheetPresented = false

    public init(
      id: UUID,
      name: String?,
      advertisedTemperature: Double? = nil
    ) {
      self.id = id
      self.name = name
      self.valueInCelcius = advertisedTemperature
    }
  }

  public enum Action {
    case exportLogsTapped
    case shareSheetDismissed
  }

  @Dependency(\.loggerClient) var loggerClient

  public init() {}

  public var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .exportLogsTapped:
        let name = state.name ?? "Unknown"
        state.logFileURL = loggerClient.logFileURL(name)
        state.isShareSheetPresented = state.logFileURL != nil
        return .none

      case .shareSheetDismissed:
        state.isShareSheetPresented = false
        state.logFileURL = nil
        return .none
      }
    }
  }
}
