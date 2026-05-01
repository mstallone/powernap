// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PowerNAP",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "powernap", targets: ["PowerNAPCLI"]),
        .executable(name: "powernapd", targets: ["PowerNAPDaemonBin"]),
        .executable(name: "powernap-hook", targets: ["PowerNAPHookBin"]),
        .executable(name: "powernap-watchdog", targets: ["PowerNAPWatchdogBin"]),
        .library(name: "PowerNAPCore", targets: ["PowerNAPCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.3")
    ],
    targets: [
        .target(
            name: "PowerNAPCore",
            dependencies: [
                .product(name: "Logging", package: "swift-log")
            ],
            path: "Sources/PowerNAPCore",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .target(
            name: "PowerNAPPlatform",
            dependencies: [
                "PowerNAPCore",
                .product(name: "Logging", package: "swift-log")
            ],
            path: "Sources/PowerNAPPlatform",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreFoundation"),
                .linkedFramework("Foundation"),
                .linkedFramework("Security"),
                .linkedFramework("CoreWLAN"),
                .linkedFramework("SystemConfiguration"),
                .linkedFramework("Network")
            ]
        ),
        .executableTarget(
            name: "PowerNAPCLI",
            dependencies: [
                "PowerNAPCore",
                "PowerNAPPlatform",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Logging", package: "swift-log")
            ],
            path: "Sources/PowerNAPCLI"
        ),
        .executableTarget(
            name: "PowerNAPDaemonBin",
            dependencies: [
                "PowerNAPCore",
                "PowerNAPPlatform",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Logging", package: "swift-log")
            ],
            path: "Sources/PowerNAPDaemon"
        ),
        .executableTarget(
            name: "PowerNAPHookBin",
            dependencies: [
                "PowerNAPCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/PowerNAPHook"
        ),
        .executableTarget(
            name: "PowerNAPWatchdogBin",
            dependencies: [
                "PowerNAPCore",
                "PowerNAPPlatform",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Logging", package: "swift-log")
            ],
            path: "Sources/PowerNAPWatchdog"
        ),
        .testTarget(
            name: "PowerNAPCoreTests",
            dependencies: ["PowerNAPCore"],
            path: "Tests/PowerNAPCoreTests"
        ),
        .testTarget(
            name: "PowerNAPPlatformTests",
            dependencies: ["PowerNAPCore", "PowerNAPPlatform"],
            path: "Tests/PowerNAPPlatformTests"
        ),
        .testTarget(
            name: "PowerNAPIntegrationTests",
            dependencies: [
                "PowerNAPCore",
                "PowerNAPPlatform"
            ],
            path: "Tests/PowerNAPIntegrationTests"
        )
    ]
)
