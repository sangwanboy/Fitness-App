// swift-tools-version: 5.8
import PackageDescription
import AppleProductTypes

let package = Package(
    name: "FitnessApp",
    platforms: [
        .iOS("26.0")
    ],
    products: [
        .iOSApplication(
            name: "FitnessApp",
            targets: ["FitnessApp"],
            bundleIdentifier: "com.tushar.fitnessapp",
            displayVersion: "1.0",
            bundleVersion: "1",
            appIcon: .asset("AppIcon"),
            accentColor: .presetColor(.orange),
            supportedDeviceFamilies: [
                .phone
            ],
            supportedInterfaceOrientations: [
                .portrait
            ],
            capabilities: [],
            additionalInfoPlistContentFilePath: "AppInfo.plist"
        )
    ],
    targets: [
        .executableTarget(
            name: "FitnessApp",
            path: "FitnessApp"
        )
    ]
)
