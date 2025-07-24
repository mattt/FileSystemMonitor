// swift-tools-version:6.0
import PackageDescription

let package = Package(
	name: "FileSystemMonitor",
	platforms: [
		.macOS(.v12)
	],
	products: [
		.library(name: "FileSystemMonitor", targets: ["FileSystemMonitor"])
	],
	dependencies: [
		.package(url: "https://github.com/apple/swift-log.git", from: "1.0.0")
	],
	targets: [
		.target(
			name: "FileSystemMonitor",
			dependencies: [
				.product(name: "Logging", package: "swift-log")
			],
			path: "Sources"
		),
		.testTarget(
			name: "FileSystemMonitorTests",
			dependencies: ["FileSystemMonitor"],
			path: "Tests"
		),
	]
)
