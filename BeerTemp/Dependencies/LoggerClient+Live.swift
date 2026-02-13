import BeerTempFeatures
import Dependencies
import Foundation

extension LoggerClient: @retroactive DependencyKey {
  public static let liveValue: LoggerClient = {
    let storage = LoggerStorage()
    return LoggerClient(
      startLogger: { name in
        storage.start(name: name)
      },
      log: { name, value in
        storage.log(name: name, value: value)
      },
      logFileURL: { name in
        storage.logFileURL(name: name)
      }
    )
  }()
}

private final class LoggerStorage: @unchecked Sendable {
  private var loggers: [String: CsvLogger] = [:]
  private let lock = NSLock()

  func start(name: String) {
    lock.lock()
    defer { lock.unlock() }
    if loggers[name] == nil {
      loggers[name] = CsvLogger(fileName: "\(name).csv")
    }
  }

  func log(name: String, value: Double?) {
    lock.lock()
    let logger = loggers[name]
    lock.unlock()
    logger?.log(value)
  }

  func logFileURL(name: String) -> URL? {
    lock.lock()
    let logger = loggers[name]
    lock.unlock()
    return logger?.logFileURL
  }
}
