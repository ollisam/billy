// swift-tools-version:5.10
import Foundation
import PackageDescription

// Invoicing isn't part of the open-source app. If Sources/Billy/Invoicing exists
// (it's git-ignored), it's compiled in and the invoice features switch on.
let invoicing = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("Sources/Billy/Invoicing").path
let hasInvoicing = FileManager.default.fileExists(atPath: invoicing)

let package = Package(
    name: "Billy",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Billy",
            path: "Sources/Billy",
            swiftSettings: hasInvoicing ? [.define("INVOICES")] : []
        )
    ]
)
