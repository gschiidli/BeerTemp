// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "BeerTempPackage",
  platforms: [
    .iOS(.v17),
    .macOS(.v14),
  ],
  products: [
    .library(name: "BeerTempFeatures", targets: ["BeerTempFeatures"]),
    .library(name: "BeerTempLiveActivityShared", targets: ["BeerTempLiveActivityShared"]),
    .library(name: "TemperatureExtrapolation", targets: ["TemperatureExtrapolation"]),
  ],
  dependencies: [
    .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.17.0"),
  ],
  targets: [
    .target(
      name: "TemperatureExtrapolation"
    ),
    .target(
      name: "BeerTempLiveActivityShared"
    ),
    .target(
      name: "BeerTempFeatures",
      dependencies: [
        "TemperatureExtrapolation",
        "BeerTempLiveActivityShared",
        .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
      ]
    ),
  ]
)
