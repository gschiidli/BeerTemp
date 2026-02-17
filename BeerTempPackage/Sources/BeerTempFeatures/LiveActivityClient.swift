import BeerTempLiveActivityShared
import Dependencies
import DependenciesMacros
import Foundation

@DependencyClient
public struct LiveActivityClient: Sendable {
  public var start: @Sendable (
    _ sensorName: String,
    _ initialState: BeerTempLiveActivityAttributes.ContentState
  ) async throws -> String

  public var update: @Sendable (
    _ activityID: String,
    _ state: BeerTempLiveActivityAttributes.ContentState
  ) async -> Void

  public var end: @Sendable (
    _ activityID: String,
    _ finalState: BeerTempLiveActivityAttributes.ContentState
  ) async -> Void

  public var endAll: @Sendable (
    _ finalState: BeerTempLiveActivityAttributes.ContentState
  ) async -> Void

  public var isSupported: @Sendable () -> Bool = { false }
}

extension LiveActivityClient: TestDependencyKey {
  public static let testValue = LiveActivityClient()
  public static let previewValue = LiveActivityClient(
    start: { _, _ in "preview-id" },
    update: { _, _ in },
    end: { _, _ in },
    endAll: { _ in },
    isSupported: { true }
  )
}

extension DependencyValues {
  public var liveActivityClient: LiveActivityClient {
    get { self[LiveActivityClient.self] }
    set { self[LiveActivityClient.self] = newValue }
  }
}
