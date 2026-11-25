// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KartaCarPlay",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "KartaCarPlay",
            targets: ["KartaCarPlay"]
        )
    ],
    dependencies: [
        // Uncomment or resolve in the iOS host Xcode workspace to link MapLibre Native iOS:
        // .package(url: "https://github.com/maplibre/maplibre-gl-native-distribution.git", from: "6.8.0")
    ],
    targets: [
        .target(
            name: "KartaCarPlay",
            dependencies: [
                // .product(name: "MapLibre", package: "maplibre-gl-native-distribution")
            ],
            path: "Sources/KartaCarPlay",
            linkerSettings: [
                .linkedFramework("CarPlay", .when(platforms: [.iOS])),
                .linkedFramework("MapKit", .when(platforms: [.iOS])),
                .linkedFramework("AVFoundation", .when(platforms: [.iOS])),
                .linkedFramework("Speech", .when(platforms: [.iOS]))
            ]
        )
    ]
)
