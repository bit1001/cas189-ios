// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CAS189",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(name: "CAS189Core", targets: ["CAS189Core"])
    ],
    dependencies: [
        // 跨平台 SHA1/MD5/HMAC（Apple 上是 CryptoKit 的替代，Linux 上也能用）
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0")
    ],
    targets: [
        .target(
            name: "CAS189Core",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto")
            ]
        ),
        .testTarget(
            name: "CAS189CoreTests",
            dependencies: ["CAS189Core"]
        )
    ]
)
