// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "AniimoAtlas",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "AniimoAtlas", targets: ["AniimoAtlas"])],
    dependencies: [
        .package(url: "https://github.com/warrenm/GLTFKit2.git", exact: "0.5.15"),
        .package(url: "https://github.com/warrenm/DracoSwift.git", exact: "1.5.7"),
        .package(url: "https://github.com/facebook/zstd.git", exact: "1.5.7")
    ],
    targets: [
        .target(
            name: "AniimoDraco",
            dependencies: [
                .product(name: "GLTFKit2", package: "GLTFKit2"),
                .product(name: "DracoSwift", package: "DracoSwift")
            ],
            path: "Sources/AniimoDraco",
            publicHeadersPath: "include",
            cxxSettings: [.headerSearchPath("include")]
        ),
        .executableTarget(
            name: "AniimoAtlas",
            dependencies: [
                "AniimoDraco",
                .product(name: "GLTFKit2", package: "GLTFKit2"),
                .product(name: "libzstd", package: "zstd")
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "AniimoAtlasTests", dependencies: ["AniimoAtlas"])
    ]
)
