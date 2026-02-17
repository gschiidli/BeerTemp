import ComposableArchitecture
import Foundation

@Reducer
public struct SensorDetail {
  @ObservableState
  public struct State: Equatable {
    public var sensorID: UUID
    public var name: String?
    public var valueInCelcius: Double?
    public var targetValue: Double?
    public var targetTolerance: Double = 1.0
    public var targetValueProgress: TargetValueProgress = .notInProgress
    public var pastValues: [LogValue] = []
    public var connectionState: ConnectionState = .disconnected
    public var targetValueInput: String = "65"
    public var isTargetValueAlertShown = false
    public var targetToleranceInput: String = "1"
    public var isToleranceAlertShown = false
    public var isLiveActivityActive = false
    public var logFileURL: URL?
    public var isShareSheetPresented = false

    public var targetValueString: String {
      targetValue?.formatted(.number.precision(.fractionLength(3))) ?? ""
    }

    public init(
      sensorID: UUID,
      name: String?,
      valueInCelcius: Double? = nil,
      targetValue: Double? = nil,
      targetTolerance: Double = 1.0,
      targetValueProgress: TargetValueProgress = .notInProgress,
      pastValues: [LogValue] = [],
      connectionState: ConnectionState = .disconnected,
      isLiveActivityActive: Bool = false
    ) {
      self.sensorID = sensorID
      self.name = name
      self.valueInCelcius = valueInCelcius
      self.targetValue = targetValue
      self.targetTolerance = targetTolerance
      self.targetValueProgress = targetValueProgress
      self.pastValues = pastValues
      self.connectionState = connectionState
      self.isLiveActivityActive = isLiveActivityActive
    }
  }

  public enum Action: BindableAction {
    case binding(BindingAction<State>)
    case exportLogsTapped
    case setTargetButtonTapped
    case setTargetConfirmed
    case setTargetResponse(Result<Double?, any Error>)
    case setToleranceButtonTapped
    case setToleranceConfirmed
    case shareSheetDismissed
    case toggleLiveActivityTapped
  }

  @Dependency(\.bluetoothClient) var bluetoothClient
  @Dependency(\.loggerClient) var loggerClient

  public init() {}

  public var body: some ReducerOf<Self> {
    BindingReducer()
    Reduce { state, action in
      switch action {
      case .binding:
        return .none

      case .exportLogsTapped:
        let name = state.name ?? "Unknown"
        state.logFileURL = loggerClient.logFileURL(name)
        state.isShareSheetPresented = state.logFileURL != nil
        return .none

      case .setTargetButtonTapped:
        state.targetValueInput = state.targetValueString
        state.isTargetValueAlertShown = true
        return .none

      case .setTargetConfirmed:
        state.isTargetValueAlertShown = false
        state.connectionState = .connecting
        let sensorID = state.sensorID
        let input = state.targetValueInput
        let bluetoothClient = bluetoothClient
        return .run { send in
          try await bluetoothClient.connect(sensorID)
          let newValue = try Double(input, format: .number)
          let confirmed = try await bluetoothClient.setTargetValue(sensorID, newValue)
          await bluetoothClient.disconnect(sensorID)
          await send(.setTargetResponse(.success(confirmed)))
        } catch: { error, send in
          await bluetoothClient.disconnect(sensorID)
          await send(.setTargetResponse(.failure(error)))
        }

      case let .setTargetResponse(.success(confirmed)):
        state.targetValue = confirmed
        state.connectionState = .disconnected
        return .none

      case let .setTargetResponse(.failure(error)):
        state.connectionState = .failedConnection(
          errorDescription: error.localizedDescription)
        return .none

      case .setToleranceButtonTapped:
        state.targetToleranceInput = state.targetTolerance
          .formatted(.number.precision(.fractionLength(0...1)))
        state.isToleranceAlertShown = true
        return .none

      case .setToleranceConfirmed:
        state.isToleranceAlertShown = false
        if let value = try? Double(state.targetToleranceInput, format: .number), value > 0 {
          state.targetTolerance = value
        }
        return .none

      case .shareSheetDismissed:
        state.isShareSheetPresented = false
        state.logFileURL = nil
        return .none

      case .toggleLiveActivityTapped:
        return .none
      }
    }
  }
}
