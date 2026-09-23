import ProjectDescription

private let version = "0.1.0"

private let baseSettings: SettingsDictionary = [
    "SWIFT_VERSION": "6.0",
    "SWIFT_STRICT_CONCURRENCY": "complete",
    // OSS: ad-hoc "Sign to Run Locally" so anyone can build without an Apple Developer team.
    "CODE_SIGN_IDENTITY": "-",
    "CODE_SIGN_STYLE": "Manual",
    "DEVELOPMENT_TEAM": "",
    "ENABLE_HARDENED_RUNTIME": "YES",
    "MARKETING_VERSION": .string(version),
    "CURRENT_PROJECT_VERSION": "1",
]

let project = Project(
    name: "Machiai",
    options: .options(
        automaticSchemesOptions: .disabled,
        defaultKnownRegions: ["en", "ja"],
        developmentRegion: "en"
    ),
    settings: .settings(base: baseSettings),
    targets: [
        .target(
            name: "Machiai",
            destinations: .macOS,
            product: .app,
            bundleId: "me.ohzono.Machiai",
            deploymentTargets: .macOS("15.0"),
            infoPlist: .extendingDefault(with: [
                "CFBundleName": "Machiai",
                "CFBundleDisplayName": "Machiai",
                "CFBundleShortVersionString": "$(MARKETING_VERSION)",
                "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
                "LSApplicationCategoryType": "public.app-category.education",
                "NSHumanReadableCopyright": "© 2026 Seigo Ohzono. MIT License.",
            ]),
            sources: ["App/Sources/**"],
            resources: [
                "App/Resources/**",
                // Shipped so binary users can run Contents/Resources/hooks/install.sh.
                .folderReference(path: "hooks"),
            ]
        ),
        .target(
            name: "MachiaiTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "me.ohzono.MachiaiTests",
            deploymentTargets: .macOS("15.0"),
            infoPlist: .default,
            sources: ["App/Tests/**"],
            dependencies: [.target(name: "Machiai")]
        ),
    ],
    schemes: [
        .scheme(
            name: "Machiai",
            shared: true,
            buildAction: .buildAction(targets: ["Machiai"]),
            testAction: .targets(["MachiaiTests"]),
            runAction: .runAction(executable: "Machiai")
        ),
    ]
)
