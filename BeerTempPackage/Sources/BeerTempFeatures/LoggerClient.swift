import Dependencies
import DependenciesMacros
import Foundation

@DependencyClient
public struct LoggerClient: Sendable {
  public var startLogger: @Sendable (String) -> Void
  public var log: @Sendable (String, Double?) -> Void
  public var logFileURL: @Sendable (String) -> URL?
}

extension LoggerClient: TestDependencyKey {
  public static let testValue = LoggerClient()
  public static let previewValue = LoggerClient(
    startLogger: { _ in },
    log: { _, _ in },
    logFileURL: { _ in nil }
  )
}

extension DependencyValues {
  public var loggerClient: LoggerClient {
    get { self[LoggerClient.self] }
    set { self[LoggerClient.self] = newValue }
  }
}
