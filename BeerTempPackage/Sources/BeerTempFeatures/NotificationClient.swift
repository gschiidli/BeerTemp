import Dependencies
import DependenciesMacros
import Foundation

@DependencyClient
public struct NotificationClient: Sendable {
  public var requestAuthorization: @Sendable () async throws -> Bool
  public var send: @Sendable (_ title: String, _ subtitle: String) async -> Void
}

extension NotificationClient: TestDependencyKey {
  public static let testValue = NotificationClient()
  public static let previewValue = NotificationClient(
    requestAuthorization: { true },
    send: { _, _ in }
  )
}

extension DependencyValues {
  public var notificationClient: NotificationClient {
    get { self[NotificationClient.self] }
    set { self[NotificationClient.self] = newValue }
  }
}
