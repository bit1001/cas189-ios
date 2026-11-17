// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "QHCore",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "QHCore", targets: ["QHCore"]),
        .executable(name: "qh", targets: ["QHCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
    ],
    targets: [
        .target(name: "QHCore", dependencies: [.product(name: "Crypto", package: "swift-crypto")]),
        .executableTarget(name: "QHCLI", dependencies: ["QHCore"]),
        .testTarget(name: "QHCoreTests", dependencies: ["QHCore"]),
    ]
)
