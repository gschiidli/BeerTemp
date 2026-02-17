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
    case liveActivityFailed(sensorID: UUID)
    case liveActivityStarted(sensorID: UUID, activityID: String)
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
    case liveActivity(UUID)
  }

  @Dependency(\.bluetoothClient) var bluetoothClient
  @Dependency(\.date) var date
  @Dependency(\.liveActivityClient) var liveActivityClient
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
            var effects: [Effect<Action>] = [
              .run { _ in loggerClient.log(name, temp) },
            ]
            if let sensorState = state.sensors[id: sensor.id],
              sensorState.isLiveActivityActive,
              let activityID = sensorState.liveActivityID,
              shouldUpdateLiveActivity(lastUpdate: sensorState.lastLiveActivityUpdate)
            {
              state.sensors[id: sensor.id]?.lastLiveActivityUpdate = date.now
              let contentState = buildContentState(for: sensor.id, in: state)
              let liveActivityClient = liveActivityClient
              effects.append(.run { _ in
                await liveActivityClient.update(activityID, contentState)
              })
            }
            return .merge(effects)
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
          targetTolerance: sensor.targetTolerance,
          targetValueProgress: sensor.targetValueProgress,
          pastValues: sensor.pastValues,
          isLiveActivityActive: sensor.isLiveActivityActive
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
        var effects: [Effect<Action>] = [
          .run { _ in loggerClient.log(name, temperature) },
        ]
        if let sensor = state.sensors[id: sensorID],
          sensor.isLiveActivityActive,
          let activityID = sensor.liveActivityID,
          shouldUpdateLiveActivity(lastUpdate: sensor.lastLiveActivityUpdate)
        {
          state.sensors[id: sensorID]?.lastLiveActivityUpdate = date.now
          let contentState = buildContentState(for: sensorID, in: state)
          let liveActivityClient = liveActivityClient
          effects.append(.run { _ in
            await liveActivityClient.update(activityID, contentState)
          })
        }
        return .merge(effects)

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

      case let .liveActivityStarted(sensorID, activityID):
        // Ignore if activity was toggled off while start was in flight
        guard state.sensors[id: sensorID]?.isLiveActivityActive == true else {
          let liveActivityClient = liveActivityClient
          let finalState = buildContentState(for: sensorID, in: state)
          return .run { _ in
            await liveActivityClient.endAll(finalState)
          }
        }
        state.sensors[id: sensorID]?.liveActivityID = activityID
        state.sensors[id: sensorID]?.lastLiveActivityUpdate = date.now
        return .none

      case let .liveActivityFailed(sensorID):
        state.sensors[id: sensorID]?.isLiveActivityActive = false
        state.sensors[id: sensorID]?.liveActivityID = nil
        for id in state.path.ids {
          if state.path[id: id]?.sensorID == sensorID {
            state.path[id: id]?.isLiveActivityActive = false
          }
        }
        return .none

      case .sensors:
        return .none

      case let .path(.element(id: pathID, action: .toggleLiveActivityTapped)):
        guard let detail = state.path[id: pathID] else { return .none }
        let sensorID = detail.sensorID
        let isActive = state.sensors[id: sensorID]?.isLiveActivityActive ?? false

        if isActive {
          state.sensors[id: sensorID]?.isLiveActivityActive = false
          state.sensors[id: sensorID]?.liveActivityID = nil
          state.sensors[id: sensorID]?.lastLiveActivityUpdate = nil
          state.path[id: pathID]?.isLiveActivityActive = false
          let finalState = buildContentState(for: sensorID, in: state)
          let liveActivityClient = liveActivityClient
          return .run { _ in
            await liveActivityClient.endAll(finalState)
          }
          .cancellable(id: CancelID.liveActivity(sensorID), cancelInFlight: true)
        } else {
          let sensorName = detail.name ?? "Unknown Sensor"
          let contentState = buildContentState(for: sensorID, in: state)
          let liveActivityClient = liveActivityClient
          state.sensors[id: sensorID]?.isLiveActivityActive = true
          state.path[id: pathID]?.isLiveActivityActive = true
          return .run { send in
            do {
              // End any orphaned activities before starting a new one
              await liveActivityClient.endAll(contentState)
              let activityID = try await liveActivityClient.start(sensorName, contentState)
              await send(.liveActivityStarted(sensorID: sensorID, activityID: activityID))
            } catch {
              await send(.liveActivityFailed(sensorID: sensorID))
            }
          }
          .cancellable(id: CancelID.liveActivity(sensorID), cancelInFlight: true)
        }

      case .path(.element(_, action: .setTargetConfirmed)):
        return .none

      case let .path(.element(id: pathID, action: .setToleranceConfirmed)):
        if let detail = state.path[id: pathID] {
          state.sensors[id: detail.sensorID]?.targetTolerance = detail.targetTolerance
        }
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

  private func buildContentState(
    for sensorID: UUID,
    in state: State
  ) -> BeerTempLiveActivityAttributes.ContentState {
    let sensor = state.sensors[id: sensorID]
    let temp = sensor?.valueInCelcius ?? 0
    let pastValues = sensor?.pastValues ?? []
    let targetValue = sensor?.targetValue
    let targetTolerance = sensor?.targetTolerance ?? 1.0

    let trend: TrendDirection = {
      guard pastValues.count >= 2 else { return .stable }
      let recent = pastValues.suffix(5)
      guard let first = recent.first, let last = recent.last else { return .stable }
      let diff = last.value - first.value
      if abs(diff) < 0.05 { return .stable }
      return diff > 0 ? .heating : .cooling
    }()

    let extrapolation = TemperatureExtrapolation.compute(
      pastValues: pastValues.map { (date: $0.date, value: $0.value) },
      targetValue: targetValue
    )

    let indicatorStatus: IndicatorStatus = {
      guard let target = targetValue else { return .noTarget }
      let diff = abs(temp - target)
      if diff <= targetTolerance { return .onTarget }
      if extrapolation?.estimatedSecondsRemaining != nil { return .approaching }
      return .farAway
    }()

    let chartPoints = downsampleChartPoints(pastValues, maxCount: 60)

    return BeerTempLiveActivityAttributes.ContentState(
      currentTemperature: temp,
      targetValue: targetValue,
      targetTolerance: targetTolerance,
      trend: trend,
      indicatorStatus: indicatorStatus,
      chartPoints: chartPoints,
      etaSeconds: extrapolation?.estimatedSecondsRemaining
    )
  }

  private func downsampleChartPoints(
    _ values: [LogValue],
    maxCount: Int
  ) -> [ChartPoint] {
    guard values.count > maxCount else {
      return values.map {
        ChartPoint(timestamp: $0.date.timeIntervalSinceReferenceDate, value: $0.value)
      }
    }
    let step = Double(values.count) / Double(maxCount)
    var result: [ChartPoint] = []
    for i in 0..<maxCount {
      let index = min(Int(Double(i) * step), values.count - 1)
      let v = values[index]
      result.append(ChartPoint(timestamp: v.date.timeIntervalSinceReferenceDate, value: v.value))
    }
    if let last = values.last {
      result[result.count - 1] = ChartPoint(
        timestamp: last.date.timeIntervalSinceReferenceDate,
        value: last.value
      )
    }
    return result
  }

  private func shouldUpdateLiveActivity(lastUpdate: Date?) -> Bool {
    guard let lastUpdate else { return true }
    return date.now.timeIntervalSince(lastUpdate) >= 10
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
