// swift-tools-version: 5.9
import PackageDescription

// The native AppKit build remains build-cli.sh. This product deliberately uses
// the portable engine on every host so its code is also testable on macOS.
let package = Package(
    name: "HanX", platforms: [.macOS(.v13)],
    products: [.executable(name: "hanx", targets: ["HanXCLI"])],
    targets: [
        .target(name: "CMiniz", path: "Sources/CMiniz", exclude: ["LICENSE"], publicHeadersPath: "include",
                cSettings: [.define("MINIZ_NO_ARCHIVE_APIS"), .define("MINIZ_NO_STDIO"), .define("MINIZ_NO_ZLIB_COMPATIBLE_NAMES")]),
        .executableTarget(name: "HanXCLI", dependencies: ["CMiniz"], path: "Sources",
            exclude: ["App", "Bridge", "CMiniz"],
            sources: ["Core", "Formats", "Sheet", "Slides", "AgentCLI", "CLI", "Platform"],
            swiftSettings: [.define("HANX_CLI"), .define("HANX_PORTABLE")])
    ]
)
