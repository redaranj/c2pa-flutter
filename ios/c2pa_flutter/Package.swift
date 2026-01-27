// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "c2pa_flutter",
    platforms: [
        .iOS(.v16),
        .macOS(.v14)
    ],
    products: [
        .library(name: "c2pa-flutter", targets: ["c2pa_flutter"])
    ],
    dependencies: [
        .package(url: "https://github.com/contentauth/c2pa-ios.git", from: "0.0.8")
    ],
    targets: [
        .target(
            name: "c2pa_flutter",
            dependencies: [
                .product(name: "C2PA", package: "c2pa-ios")
            ],
            resources: [
                .process("PrivacyInfo.xcprivacy")
            ]
        )
    ]
)
