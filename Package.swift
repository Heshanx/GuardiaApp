// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GuardiaDomain",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [.library(name: "GuardiaDomain", targets: ["GuardiaDomain"])],
    targets: [
        .target(name: "GuardiaDomain", path: "Guardia/Domain"),
        .testTarget(name: "GuardiaDomainTests", dependencies: ["GuardiaDomain"], path: "Tests/GuardiaDomainTests")
    ]
)
