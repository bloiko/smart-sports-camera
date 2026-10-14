// swift-tools-version:6.0
// FolloCore: the live virtual camera (port of src/live_sim.py + src/live_cam.py + src/goals.py), no UI.
// follosim: macOS command-line tool to run the same camera on a recorded match and compare with Python.
import PackageDescription

let package = Package(
    name: "FolloCore",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "FolloCore", targets: ["FolloCore"]),
        .executable(name: "follosim", targets: ["follosim"]),
    ],
    targets: [
        .target(name: "FolloCore", swiftSettings: [.unsafeFlags(["-O"])]),   // піксельний код: без -O у Debug в 20–50× повільніший
        .executableTarget(name: "follosim", dependencies: ["FolloCore"]),
    ]
)
