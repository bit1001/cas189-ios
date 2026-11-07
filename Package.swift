// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CAS189",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(name: "CAS189Core", targets: ["CAS189Core"]),
        .executable(name: "cas189", targets: ["cas189"])
    ],
    dependencies: [
        // 跨平台 SHA1/MD5/HMAC（Apple 上是 CryptoKit 的替代，Linux 上也能用）
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
        .package(url: "https://github.com/attaswift/BigInt.git", from: "5.3.0"),
        // 读写 .cas.zip（解压秒传凭证），iOS / macOS / Linux 通用
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.19")
    ],
    targets: [
        .target(
            name: "CAS189Core",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "BigInt", package: "BigInt"),
                .product(name: "ZIPFoundation", package: "ZIPFoundation")
            ]
        ),
        .executableTarget(
            name: "cas189",
            dependencies: ["CAS189Core"]
        ),
        .testTarget(
            name: "CAS189CoreTests",
            dependencies: ["CAS189Core"]
        )
    ]
)
