import ComposableArchitecture
import Foundation
import SwiftUI

@Reducer
public struct SensorList {
  @ObservableState
  public struct State: Equatable {
    public var sensors: IdentifiedArrayOf<SensorCard.State> = []
    public var path = StackState<SensorDetail.State>()
    public var isScanning = false
    public var scenePhase: ScenePhase = .active

    public init() {}
  }

  public enum Action {
    case onAppear
    case path(StackActionOf<SensorDetail>)
    case pullToRefreshTriggered
    case scanStarted
    case scenePhaseChanged(ScenePhase)
    case sensorDiscovered(DiscoveredSensor)
    case sensorTapped(id: UUID)
    case sensors(IdentifiedActionOf<SensorCard>)
    case targetProgressUpdated(sensorID: UUID, TargetValueProgress)
    case temperatureUpdated(sensorID: UUID, Double?)
  }

  enum CancelID: Hashable {
    case scanning
  }

  @Dependency(\.bluetoothClient) var bluetoothClient
  @Dependency(\.date) var date
  @Dependency(\.loggerClient) var loggerClient
  @Dependency(\.notificationClient) var notificationClient
  @Dependency(\.uuid) var uuid

  public init() {}

  public var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .onAppear:
        return startScanning()

      case .pullToRefreshTriggered:
        return startScanning()

      case .scanStarted:
        state.isScanning = true
        let bluetoothClient = bluetoothClient
        return .run { send in
          for await sensor in bluetoothClient.discoveredSensors() {
            await send(.sensorDiscovered(sensor))
          }
        }
        .cancellable(id: CancelID.scanning)

      case let .sensorDiscovered(sensor):
        if state.sensors[id: sensor.id] != nil {
          if let temp = sensor.advertisedTemperature,
            temp != state.sensors[id: sensor.id]?.valueInCelcius
          {
            state.sensors[id: sensor.id]?.valueInCelcius = temp
            let logValue = LogValue(id: uuid(), value: temp, date: date.now)
            state.sensors[id: sensor.id]?.pastValues.append(logValue)
            trimPastValues(&state.sensors[id: sensor.id]!.pastValues)

            for id in state.path.ids {
              if state.path[id: id]?.sensorID == sensor.id {
                state.path[id: id]?.valueInCelcius = temp
                let detailLogValue = LogValue(id: uuid(), value: temp, date: date.now)
                state.path[id: id]?.pastValues.append(detailLogValue)
                trimPastValues(&state.path[id: id]!.pastValues)
              }
            }

            let name = state.sensors[id: sensor.id]?.name ?? "Unknown"
            let loggerClient = loggerClient
            return .run { _ in
              loggerClient.log(name, temp)
            }
          }
        } else {
          let sensorState = SensorCard.State(
            id: sensor.id,
            name: sensor.name,
            advertisedTemperature: sensor.advertisedTemperature
          )
          state.sensors.append(sensorState)
          let name = sensor.name ?? "Unknown"
          let loggerClient = loggerClient
          let notificationClient = notificationClient
          return .merge(
            .run { _ in
              loggerClient.startLogger(name)
            },
            .run { _ in
              _ = try? await notificationClient.requestAuthorization()
            }
          )
        }
        return .none

      case let .sensorTapped(id):
        guard let sensor = state.sensors[id: id] else { return .none }
        // Prevent double-push if already on detail for this sensor
        guard !state.path.ids.contains(where: { state.path[id: $0]?.sensorID == id }) else {
          return .none
        }
        let detailState = SensorDetail.State(
          sensorID: id,
          name: sensor.name,
          valueInCelcius: sensor.valueInCelcius,
          targetValue: sensor.targetValue,
          targetValueProgress: sensor.targetValueProgress,
          pastValues: sensor.pastValues
        )
        state.path.append(detailState)
        return .none

      case let .temperatureUpdated(sensorID, temperature):
        state.sensors[id: sensorID]?.valueInCelcius = temperature
        if let temperature {
          let logValue = LogValue(id: uuid(), value: temperature, date: date.now)
          state.sensors[id: sensorID]?.pastValues.append(logValue)
          trimPastValues(&state.sensors[id: sensorID]!.pastValues)
        }

        for id in state.path.ids {
          if state.path[id: id]?.sensorID == sensorID {
            state.path[id: id]?.valueInCelcius = temperature
            if let temperature {
              let logValue = LogValue(id: uuid(), value: temperature, date: date.now)
              state.path[id: id]?.pastValues.append(logValue)
              trimPastValues(&state.path[id: id]!.pastValues)
            }
          }
        }

        let name = state.sensors[id: sensorID]?.name ?? "Unknown"
        let loggerClient = loggerClient
        return .run { _ in
          loggerClient.log(name, temperature)
        }

      case let .targetProgressUpdated(sensorID, progress):
        let oldProgress = state.sensors[id: sensorID]?.targetValueProgress ?? .notInProgress
        state.sensors[id: sensorID]?.targetValueProgress = progress

        for id in state.path.ids {
          if state.path[id: id]?.sensorID == sensorID {
            state.path[id: id]?.targetValueProgress = progress
          }
        }

        guard state.scenePhase == .background else { return .none }

        let targetValue = state.sensors[id: sensorID]?.targetValue
        return sendNotificationIfNeeded(
          oldProgress: oldProgress,
          newProgress: progress,
          targetValue: targetValue
        )

      case let .scenePhaseChanged(newPhase):
        state.scenePhase = newPhase
        return .none

      case .sensors:
        return .none

      case .path(.element(_, action: .setTargetConfirmed)):
        return .none

      case let .path(.element(id: pathID, action: .setTargetResponse(.success(confirmed)))):
        if let sensorID = state.path[id: pathID]?.sensorID {
          state.sensors[id: sensorID]?.targetValue = confirmed
        }
        return .none

      case .path:
        return .none
      }
    }
    .forEach(\.sensors, action: \.sensors) {
      SensorCard()
    }
    .forEach(\.path, action: \.path) {
      SensorDetail()
    }
  }

  private func startScanning() -> Effect<Action> {
    let bluetoothClient = bluetoothClient
    return .run { send in
      try await bluetoothClient.startScanning()
      await send(.scanStarted)
    } catch: { _, _ in }
  }

  private func trimPastValues(_ values: inout [LogValue]) {
    let now = date.now
    let cutoff: TimeInterval = 30 * 60
    if let oldest = values.first, oldest.date.distance(to: now) > cutoff {
      values = values.filter { $0.date.distance(to: now) < cutoff }
    }
  }

  private func sendNotificationIfNeeded(
    oldProgress: TargetValueProgress,
    newProgress: TargetValueProgress,
    targetValue: Double?
  ) -> Effect<Action> {
    switch (oldProgress, newProgress) {
    case (.onTheWay, .onPoint), (.onPoint, .passedThePoint), (.passedThePoint, .onPoint):
      break
    default:
      return .none
    }

    let title: String
    let subtitle: String

    switch newProgress {
    case .notInProgress, .onTheWay:
      return .none
    case .onPoint:
      title = "Target Value Reached"
      if let targetValue {
        subtitle = "The target value of \(targetValue) was reached"
      } else {
        subtitle = "The target value was reached"
      }
    case .passedThePoint:
      title = "Target Value Passed"
      if let targetValue {
        subtitle = "The target value of \(targetValue) was passed"
      } else {
        subtitle = "The target value was passed"
      }
    }

    let notificationClient = notificationClient
    return .run { _ in
      await notificationClient.send(title, subtitle)
    }
  }
}
