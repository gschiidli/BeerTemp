import BeerTempFeatures
import Dependencies
import Foundation
import UserNotifications

extension NotificationClient: @retroactive DependencyKey {
  public static let liveValue = NotificationClient(
    requestAuthorization: {
      try await UNUserNotificationCenter.current().requestAuthorization(options: [
        .alert, .badge, .sound,
      ])
    },
    send: { title, subtitle in
      let content = UNMutableNotificationContent()
      content.title = title
      content.subtitle = subtitle
      content.sound = .default

      let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.01, repeats: false)
      let request = UNNotificationRequest(
        identifier: UUID().uuidString,
        content: content,
        trigger: trigger
      )

      try? await UNUserNotificationCenter.current().add(request)
    }
  )
}
