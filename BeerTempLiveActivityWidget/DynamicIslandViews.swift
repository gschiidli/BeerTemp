import ActivityKit
import BeerTempLiveActivityShared
import SwiftUI
import WidgetKit

// MARK: - Expanded Dynamic Island Views

struct ExpandedLeadingView: View {
  let context: ActivityViewContext<BeerTempLiveActivityAttributes>

  var body: some View {
    Text(
      context.state.currentTemperature.formatted(.number.precision(.fractionLength(1)))
    )
    .font(.title2.monospacedDigit())
    .foregroundStyle(colorForStatus(context.state.indicatorStatus))
    + Text(" °C")
      .font(.caption)
      .foregroundStyle(.secondary)
  }
}

struct ExpandedTrailingView: View {
  let context: ActivityViewContext<BeerTempLiveActivityAttributes>

  var body: some View {
    Image(systemName: trendArrowName)
      .font(.title3)
      .foregroundStyle(colorForStatus(context.state.indicatorStatus))
  }

  private var trendArrowName: String {
    switch context.state.trend {
    case .heating: "arrow.up.right"
    case .cooling: "arrow.down.right"
    case .stable: "arrow.right"
    }
  }
}

struct ExpandedCenterView: View {
  let context: ActivityViewContext<BeerTempLiveActivityAttributes>

  var body: some View {
    Text(context.attributes.sensorName)
      .font(.caption)
      .foregroundStyle(.secondary)
  }
}

// MARK: - Compact Dynamic Island Views

struct CompactLeadingView: View {
  let context: ActivityViewContext<BeerTempLiveActivityAttributes>

  var body: some View {
    Image(systemName: trendArrowName)
      .foregroundStyle(colorForStatus(context.state.indicatorStatus))
  }

  private var trendArrowName: String {
    switch context.state.trend {
    case .heating: "arrow.up.right"
    case .cooling: "arrow.down.right"
    case .stable: "arrow.right"
    }
  }
}

struct CompactTrailingView: View {
  let context: ActivityViewContext<BeerTempLiveActivityAttributes>

  var body: some View {
    Text(
      "\(context.state.currentTemperature.formatted(.number.precision(.fractionLength(1))))°"
    )
    .font(.caption.monospacedDigit())
    .foregroundStyle(colorForStatus(context.state.indicatorStatus))
  }
}

// MARK: - Minimal View

struct MinimalView: View {
  let context: ActivityViewContext<BeerTempLiveActivityAttributes>

  var body: some View {
    Text("\(Int(context.state.currentTemperature))°")
      .font(.caption2.monospacedDigit())
      .foregroundStyle(colorForStatus(context.state.indicatorStatus))
  }
}

// MARK: - Shared Color Helper

func colorForStatus(_ status: IndicatorStatus) -> Color {
  switch status {
  case .onTarget: .green
  case .approaching: .orange
  case .farAway: .red
  case .noTarget: .secondary
  }
}
