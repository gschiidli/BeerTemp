import ActivityKit
import BeerTempFeatures
import BeerTempLiveActivityShared
import Dependencies
import Foundation

extension LiveActivityClient: @retroactive DependencyKey {
  public static let liveValue = LiveActivityClient(
    start: { sensorName, initialState in
      let attributes = BeerTempLiveActivityAttributes(sensorName: sensorName)
      let content = ActivityContent(state: initialState, staleDate: nil)
      let activity = try Activity.request(
        attributes: attributes,
        content: content,
        pushType: nil
      )
      return activity.id
    },
    update: { activityID, state in
      let activities = Activity<BeerTempLiveActivityAttributes>.activities
      guard let activity = activities.first(where: { $0.id == activityID }) else { return }
      let content = ActivityContent(state: state, staleDate: nil)
      await activity.update(content)
    },
    end: { activityID, finalState in
      let activities = Activity<BeerTempLiveActivityAttributes>.activities
      guard let activity = activities.first(where: { $0.id == activityID }) else { return }
      let content = ActivityContent(state: finalState, staleDate: nil)
      await activity.end(content, dismissalPolicy: .default)
    },
    endAll: { finalState in
      let activities = Activity<BeerTempLiveActivityAttributes>.activities
      let content = ActivityContent(state: finalState, staleDate: nil)
      for activity in activities {
        await activity.end(content, dismissalPolicy: .immediate)
      }
    },
    isSupported: {
      ActivityAuthorizationInfo().areActivitiesEnabled
    }
  )
}
