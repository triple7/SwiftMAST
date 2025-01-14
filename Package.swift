// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftMAST",
    platforms: [
        .iOS("14"),
        .macOS("11")
    ],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "SwiftMAST",
            targets: ["SwiftMAST"]),
    ],
    dependencies: [
        .package(url: "https://github.com/triple7/SwiftQValue", branch: "main"),
        .package(url: "https://github.com/brampf/fitscore.git", branch: "master"),
            .package(url: "https://github.com/brampf/fitskit.git", branch: "master"),
            .package(url: "https://github.com/apple/swift-numerics.git", branch: "main"),
            .package(url: "https://github.com/marmelroy/Zip.git", branch: "master")],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "SwiftMAST",
            dependencies: [
                .product(name: "SwiftQValue", package: "SwiftQValue"),
                .product(name: "FITSKit", package: "FITSKit"),
                           .product(name: "Numerics", package: "swift-numerics"),
                           .product(name: "Zip", package: "zip")]),
        .testTarget(
            name: "SwiftMASTTests",
            dependencies: ["SwiftMAST", .product(name: "FITSCore", package: "FITSCore")]),
    ]
)
