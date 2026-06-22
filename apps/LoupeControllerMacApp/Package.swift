// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LoupeControllerMacApp",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "LoupeControllerMacApp", targets: ["LoupeControllerMacApp"])
    ],
    dependencies: [
        .package(path: "../../loupe-controller-ios")
    ],
    targets: [
        .executableTarget(
            name: "LoupeControllerMacApp",
            dependencies: [
                .product(name: "LoupeController", package: "loupe-controller-ios")
            ],
            path: "Sources/LoupeControllerMacApp",
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-rpath",
                    "-Xlinker", "@executable_path/../Frameworks"
                ])
            ]
        )
    ]
)
