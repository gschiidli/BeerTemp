import ActivityKit
import BeerTempLiveActivityShared
import SwiftUI
import WidgetKit

struct BeerTempLiveActivityWidget: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: BeerTempLiveActivityAttributes.self) { context in
      LockScreenLiveActivityView(context: context)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          ExpandedLeadingView(context: context)
        }
        DynamicIslandExpandedRegion(.trailing) {
          ExpandedTrailingView(context: context)
        }
        DynamicIslandExpandedRegion(.center) {
          ExpandedCenterView(context: context)
        }
        DynamicIslandExpandedRegion(.bottom) {}
      } compactLeading: {
        CompactLeadingView(context: context)
      } compactTrailing: {
        CompactTrailingView(context: context)
      } minimal: {
        MinimalView(context: context)
      }
    }
  }
}
