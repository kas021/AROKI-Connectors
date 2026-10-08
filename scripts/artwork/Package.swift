// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "PublishArtwork", platforms: [.macOS(.v13)], dependencies: [
    .package(path: "../../../Vireo/VireoCore")
], targets: [.executableTarget(name: "PublishArtwork", dependencies: [.product(name: "VireoCore", package: "vireocore")])])
