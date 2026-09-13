# NekoCraft

Lightweight SwiftUI iOS/iPadOS launcher shell for Minecraft Java Edition, targeting iOS 17 and later.

## Current launcher features

- Offline account named `Dev` by default, persisted locally on the device
- Minecraft Java `1.21.11` selected by default
- Official Mojang version manifest lookup
- On-demand download and caching of the version's library artifacts
- Libraries stored in Application Support instead of inside the IPA, keeping the app download small

## Build locally

Open `NekoCraft.xcodeproj` in Xcode and run the `NekoCraft` scheme. Tap `Prepare 1.21.11` to fetch the library metadata and jars when needed.

This project does not bundle Mojang game assets or a Java runtime. iOS cannot execute Java jars directly, so launching the full game still requires a compatible embedded Java runtime and rendering bridge. The app currently prepares the official library set without adding that large runtime to the IPA.

## GitHub Actions

The `Build IPA` workflow archives the app without signing and uploads `NekoCraft.ipa` as a workflow artifact. An Apple Developer signing setup is required before the IPA can be installed on a device.