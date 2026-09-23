// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Sonar",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .target(
            name: "SonarCore",
            path: "work/SonarCore",
            linkerSettings: [
                .linkedFramework("Accelerate"),
            ]
        ),
        .executableTarget(
            name: "Sonar",
            dependencies: ["SonarCore"],
            path: ".",
            exclude: [
                "work/SonarCore",
                "Tests",
                "script",
                "docs",
                "AGENTS.md",
                "LICENSE",
                "README.md",
                "assets/gesture-sensing.gif",
            ],
            sources: ["work/Sonar"],
            resources: [
                .copy("assets/zoom"),
                .copy("assets/gallery"),
                .copy("assets/paper/SoundWave.pdf"),
                .copy("assets/sonar.png"),
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Accelerate"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("PDFKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("ApplicationServices"),
                // Embed the shared Info.plist so Xcode builds report the version
                // and include the microphone usage description.
                .unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT",
                              "-Xlinker", "__info_plist", "-Xlinker", "script/Info.plist"]),
            ]
        ),
        .testTarget(
            name: "SonarTests",
            dependencies: ["SonarCore"],
            path: "Tests/SonarTests"
        )
    ]
)
