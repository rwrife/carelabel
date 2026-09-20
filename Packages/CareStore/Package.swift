// swift-tools-version: 6.1

import PackageDescription

// Issue #4: the persistence layer.
//
// CareStore is the GRDB/SQLite data layer: versioned schema, Garment +
// WashLog persistence, repository protocols (with in-memory fakes in
// CareStoreTestSupport), a container-relative photo store, and migration
// tests against a committed v1 fixture database.
//
// Domain value types (CareProfile et al.) live in the sibling CareKit
// package; CareStore only serializes them.
let package = Package(
    name: "CareStore",
    platforms: [
        .iOS("26.0"),
        .macOS(.v15),
    ],
    products: [
        .library(name: "CareStore", targets: ["CareStore"]),
        .library(name: "CareStoreTestSupport", targets: ["CareStoreTestSupport"]),
    ],
    dependencies: [
        .package(path: "../CareKit"),
        // Exact pin in the spirit of toolchain.json: CI must never resolve a
        // different GRDB than was verified. 7.10+ officially supports Linux,
        // so the unit tests run both on the macOS CI runner and in the Linux
        // Docker verification loop.
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.11.1"),
    ],
    targets: [
        .target(
            name: "CareStore",
            dependencies: [
                .product(name: "CareKit", package: "CareKit"),
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .target(
            name: "CareStoreTestSupport",
            dependencies: [
                "CareStore",
                .product(name: "CareKit", package: "CareKit"),
            ]
        ),
        // Regenerates Tests/CareStoreTests/Fixtures/v1.sqlite through
        // Scripts/make_fixture_db.py (v1 is frozen; see that script).
        .executableTarget(
            name: "fixture-seed",
            dependencies: [
                "CareStore",
                .product(name: "CareKit", package: "CareKit"),
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Tools/fixture-seed"
        ),
        .testTarget(
            name: "CareStoreTests",
            dependencies: [
                "CareStore",
                "CareStoreTestSupport",
                .product(name: "CareKit", package: "CareKit"),
            ]
        ),
    ]
)
