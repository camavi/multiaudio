// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Multiaudio",
    platforms: [.iOS(.v14)],
    products: [
        .library(
            name: "Multiaudio",
            targets: ["MultiAudioPlugin"])
    ],
    dependencies: [
        .package(url: "https://github.com/ionic-team/capacitor-swift-pm.git", from: "7.0.0")
    ],
    targets: [
        .target(
            name: "MultiAudioPlugin",
            dependencies: [
                .product(name: "Capacitor", package: "capacitor-swift-pm"),
                .product(name: "Cordova", package: "capacitor-swift-pm")
            ],
            path: "ios/Sources/MultiAudioPlugin"),
        .testTarget(
            name: "MultiAudioPluginTests",
            dependencies: ["MultiAudioPlugin"],
            path: "ios/Tests/MultiAudioPluginTests")
    ]
)