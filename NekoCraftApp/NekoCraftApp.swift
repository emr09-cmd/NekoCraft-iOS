import SwiftUI

@main
struct NekoCraftApp: App {
    var body: some Scene {
        WindowGroup {
            LauncherView()
        }
    }
}

struct LauncherView: View {
    @StateObject private var model = LauncherViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    NekoCraftMetalView()
                        .frame(height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Minecraft Java launcher")
                            .font(.largeTitle.bold())
                        Text("A small, on-demand setup for iPhone and iPad.")
                            .foregroundStyle(.secondary)
                    }
                    launcherCard(title: "Offline account", systemImage: "person.crop.circle") {
                        HStack {
                            TextField("Username", text: $model.username)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            Text("OFFLINE")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(.orange.opacity(0.14), in: Capsule())
                        }
                        Text("Stored only on this device. No Microsoft login is used.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    launcherCard(title: "Game version", systemImage: "shippingbox") {
                        HStack {
                            Text("Minecraft Java")
                            Spacer()
                            Text(model.version)
                                .font(.headline.monospaced())
                        }
                        HStack(spacing: 8) {
                            Circle()
                                .fill(model.isPrepared ? .green : .secondary)
                                .frame(width: 8, height: 8)
                            Text(model.isGameReady ? "Ready to launch" : model.isPrepared ? "Libraries ready" : "Not downloaded")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    launcherCard(title: "Storage", systemImage: "internaldrive") {
                        HStack {
                            Text("Downloaded libraries")
                            Spacer()
                            Text(model.libraryCount == 0 ? "None" : "\(model.libraryCount) files")
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Text("Minecraft client")
                            Spacer()
                            Text(model.clientReady ? "Ready" : "Not downloaded")
                                .foregroundStyle(model.clientReady ? .green : .secondary)
                        }
                        Text("Libraries are fetched on demand and kept out of the app bundle.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        Task { await model.prepareOrLaunch() }
                    } label: {
                        HStack {
                            if model.isPreparing {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: model.isGameReady ? "play.fill" : model.isPrepared ? "arrow.right.circle.fill" : "arrow.down.circle.fill")
                            }
                            Text(model.isPreparing ? "Preparing 1.21.11..." : model.isPrepared ? "Launch 1.21.11" : "Prepare 1.21.11")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isPreparing || model.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if let message = model.message {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    launcherCard(title: "Launch console", systemImage: "terminal") {
                        ScrollView {
                            Text(model.logs.joined(separator: "\n"))
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .frame(maxHeight: 180)
                        Button("Clear console") {
                            model.clearLogs()
                        }
                        .font(.caption)
                    }
                }
                .padding(20)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("NekoCraft")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func launcherCard<Content: View>(title: String, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
    }
}

@MainActor
final class LauncherViewModel: ObservableObject {
    @Published var username: String {
        didSet { UserDefaults.standard.set(username, forKey: Self.usernameKey) }
    }
    @Published private(set) var isPreparing = false
    @Published private(set) var isPrepared = false
    @Published private(set) var isGameReady = false
    @Published private(set) var clientReady = false
    @Published private(set) var libraryCount = 0
    @Published private(set) var message: String?
    @Published private(set) var logs: [String]
    @Published private(set) var isLaunching = false

    let version = "1.21.11"
    private static let usernameKey = "offlineUsername"
    private let libraryStore = LibraryStore()
    private let clientStore = ClientStore()
    private var assetIndex = ""
    private var javaRuntime: OpaquePointer?

    init() {
        username = UserDefaults.standard.string(forKey: Self.usernameKey) ?? "Dev"
        libraryCount = libraryStore.fileCount()
        clientReady = clientStore.exists(version: version)
        logs = UserDefaults.standard.stringArray(forKey: "launchLogs") ?? ["NekoCraft console ready"]
    }

    func prepareOrLaunch() async {
        log("Button pressed")
        if isPrepared {
            log("Runtime already prepared; launching")
            launchGame()
            return
        }

        await prepareVersion()
    }

    private func prepareVersion() async {
        isPreparing = true
        log("Fetching Mojang 1.21.11 manifest")
        message = nil
        defer { isPreparing = false }

        do {
            let manifest = try await MojangManifestClient().versionManifest(for: version)
            let downloaded = try await libraryStore.download(manifest.libraries)
            log("Downloaded \(downloaded) library files")
            try await clientStore.download(manifest.downloads.client, version: version)
            log("Minecraft client downloaded")
            assetIndex = manifest.assetIndex.id
            let assetCount = try await AssetStore().download(manifest.assetIndex)
            log("Downloaded \(assetCount) asset objects")
            libraryCount = downloaded
            clientReady = true
            isPrepared = true
            isGameReady = false
            message = "Downloaded \(downloaded) Java libraries, the client, and \(assetCount) assets. Press Launch 1.21.11."
        } catch {
            log("Prepare failed: \(error.localizedDescription)")
            message = error.localizedDescription
        }
    }

    private func launchGame() {
        guard clientReady else {
            log("Launch blocked: client jar missing")
            message = "The Minecraft client is not downloaded yet. Press Prepare 1.21.11 first."
            return
        }
        if isLaunching {
            log("Launch blocked: launch already in progress")
            message = "Minecraft launch is already in progress."
            return
        }
        guard let runtimeHome = Bundle.main.url(forResource: "JavaRuntime", withExtension: nil) else {
            log("Launch failed: JavaRuntime folder missing")
            message = "Java runtime is missing from this app build."
            return
        }
        let clientPath = clientStore.path(version: version)
        let bundledLibraries = Bundle.main.url(forResource: "JavaRuntime", withExtension: nil)?.appendingPathComponent("libs", isDirectory: true)
        let classPath = libraryStore.classPath(clientPath: clientPath, additionalDirectory: bundledLibraries)
        javaRuntime = runtimeHome.path.withCString { NekoCraftJavaRuntimeCreate($0) }
        guard let javaRuntime else {
            log("Launch failed: native runtime handle unavailable")
            message = "Java runtime could not be created."
            return
        }
        let gameDirectory = clientStore.gameDirectory.path
        let assetsDirectory = clientStore.assetsDirectory.path
        isLaunching = true
        log("Starting Java 21 and Minecraft on background thread")
        let launchUsername = username
        let launchVersion = version
        let launchGameDirectory = gameDirectory
        let launchAssetsDirectory = assetsDirectory
        let launchAssetIndex = assetIndex
        Task.detached(priority: .userInitiated) { [weak self] in
            let result = classPath.withCString { classPathPointer in
                launchUsername.withCString { usernamePointer in
                    launchVersion.withCString { versionPointer in
                        launchGameDirectory.withCString { gameDirectoryPointer in
                            launchAssetsDirectory.withCString { assetsDirectoryPointer in
                                launchAssetIndex.withCString { assetIndexPointer in
                                    NekoCraftJavaRuntimeLaunchMinecraft(javaRuntime, classPathPointer, usernamePointer, versionPointer, gameDirectoryPointer, assetsDirectoryPointer, assetIndexPointer)
                                }
                            }
                        }
                    }
                }
            }
            let detail = result == 0 ? nil : (NekoCraftJavaRuntimeLastError(javaRuntime).map { String(cString: $0) } ?? "unknown error")
            await MainActor.run {
                guard let self else { return }
                self.isLaunching = false
                if result == 0 {
                    self.log("Java 21 VM started and Minecraft Main.main returned")
                    self.message = "Minecraft launch returned. Check the console for Java output."
                } else {
                    self.log("Java VM failed: code \(result), \(detail ?? "unknown error")")
                    self.message = "Minecraft launch failed (code \(result)): \(detail ?? "unknown error")"
                }
            }
        }
    }

    func clearLogs() {
        logs = ["Console cleared"]
        persistLogs()
    }

    private func log(_ entry: String) {
        let formatter = ISO8601DateFormatter()
        logs.append("[\(formatter.string(from: Date()))] \(entry)")
        if logs.count > 100 {
            logs.removeFirst(logs.count - 100)
        }
        persistLogs()
    }

    private func persistLogs() {
        UserDefaults.standard.set(logs, forKey: "launchLogs")
    }
}

private final class AssetStore {
    private let fileManager = FileManager.default

    private var directory: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("NekoCraft/Assets/objects", isDirectory: true)
    }

    func download(_ index: AssetIndex) async throws -> Int {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let (data, response) = try await URLSession.shared.data(from: index.url)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw LauncherError.networkFailure
        }
        let assetIndex = try JSONDecoder().decode(AssetIndexData.self, from: data)
        var downloaded = 0
        for asset in assetIndex.objects.values {
            let prefix = String(asset.hash.prefix(2))
            let destination = directory.appendingPathComponent("\(prefix)/\(asset.hash)")
            if fileManager.fileExists(atPath: destination.path) {
                downloaded += 1
                continue
            }
            try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard let url = URL(string: "https://resources.download.minecraft.net/\(prefix)/\(asset.hash)") else {
                throw LauncherError.networkFailure
            }
            let (temporaryURL, assetResponse) = try await URLSession.shared.download(from: url)
            guard let assetHTTP = assetResponse as? HTTPURLResponse, 200..<300 ~= assetHTTP.statusCode else {
                throw LauncherError.networkFailure
            }
            try fileManager.moveItem(at: temporaryURL, to: destination)
            downloaded += 1
        }
        return downloaded
    }
}

private struct MojangManifestClient {
    private let manifestURL = URL(string: "https://piston-meta.mojang.com/mc/game/version_manifest_v2.json")!

    func versionManifest(for version: String) async throws -> VersionManifest {
        let (data, response) = try await URLSession.shared.data(from: manifestURL)
        try validate(response)
        let index = try JSONDecoder().decode(VersionIndex.self, from: data)
        guard let versionURL = index.versions.first(where: { $0.id == version })?.url else {
            throw LauncherError.versionUnavailable(version)
        }
        let (versionData, versionResponse) = try await URLSession.shared.data(from: versionURL)
        try validate(versionResponse)
        return try JSONDecoder().decode(VersionManifest.self, from: versionData)
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw LauncherError.networkFailure
        }
    }
}

private final class LibraryStore {
    private let fileManager = FileManager.default

    private var directory: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("NekoCraft/Libraries", isDirectory: true)
    }

    func fileCount() -> Int {
        (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).count) ?? 0
    }

    func classPath(clientPath: URL, additionalDirectory: URL? = nil) -> String {
        let files = (fileManager.enumerator(at: directory, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? [])
            .filter { $0.pathExtension == "jar" }
        let bundledFiles = additionalDirectory.flatMap {
            (fileManager.enumerator(at: $0, includingPropertiesForKeys: nil)?.allObjects as? [URL])
        }?.filter { $0.pathExtension == "jar" } ?? []
        return ([clientPath] + files + bundledFiles).map(\.path).joined(separator: ":")
    }

    func download(_ libraries: [Library]) async throws -> Int {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        for library in libraries {
            guard let artifact = library.downloads?.artifact,
                  let url = URL(string: artifact.url) else { continue }
            let destination = directory.appendingPathComponent(artifact.path)
            if fileManager.fileExists(atPath: destination.path) { continue }
            try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            let (temporaryURL, response) = try await URLSession.shared.download(from: url)
            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
                throw LauncherError.networkFailure
            }
            try fileManager.moveItem(at: temporaryURL, to: destination)
        }
        return fileCount()
    }
}

private final class ClientStore {
    private let fileManager = FileManager.default

    private var directory: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("NekoCraft/Versions", isDirectory: true)
    }

    var gameDirectory: URL {
        directory.deletingLastPathComponent().appendingPathComponent("Game", isDirectory: true)
    }

    var assetsDirectory: URL {
        directory.deletingLastPathComponent().appendingPathComponent("Assets", isDirectory: true)
    }

    func path(version: String) -> URL {
        clientURL(version: version)
    }

    func exists(version: String) -> Bool {
        fileManager.fileExists(atPath: clientURL(version: version).path)
    }

    func download(_ artifact: ClientArtifact, version: String) async throws {
        guard let url = URL(string: artifact.url) else {
            throw LauncherError.networkFailure
        }
        let destination = clientURL(version: version)
        if fileManager.fileExists(atPath: destination.path) { return }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let (temporaryURL, response) = try await URLSession.shared.download(from: url)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw LauncherError.networkFailure
        }
        try fileManager.moveItem(at: temporaryURL, to: destination)
    }

    private func clientURL(version: String) -> URL {
        directory.appendingPathComponent("Minecraft-\(version).jar")
    }
}

private struct VersionIndex: Decodable {
    let versions: [VersionReference]
}

private struct VersionReference: Decodable {
    let id: String
    let url: URL
}

private struct VersionManifest: Decodable {
    let libraries: [Library]
    let downloads: VersionDownloads
    let assetIndex: AssetIndex
}

private struct VersionDownloads: Decodable {
    let client: ClientArtifact
}

private struct ClientArtifact: Decodable {
    let url: String
}

private struct AssetIndex: Decodable {
    let id: String
    let url: URL
}

private struct AssetIndexData: Decodable {
    let objects: [String: AssetObject]
}

private struct AssetObject: Decodable {
    let hash: String
}

private struct Library: Decodable {
    let downloads: Downloads?
}

private struct Downloads: Decodable {
    let artifact: Artifact?
}

private struct Artifact: Decodable {
    let path: String
    let url: String
}

private enum LauncherError: LocalizedError {
    case networkFailure
    case runtimeNotBundled
    case runtimeUnavailable
    case runtimeStartFailed(Int32)
    case versionUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .networkFailure:
            return "The Mojang download service did not respond. Check your connection and try again."
        case .runtimeNotBundled:
            return "Java 21 is not bundled in this build. Run the iOS runtime packaging step before launching."
        case .runtimeUnavailable:
            return "The bundled Java 21 runtime could not be opened."
        case .runtimeStartFailed(let code):
            return "Java 21 failed to start (code \(code)). JIT or runtime signing may be unavailable."
        case .versionUnavailable(let version):
            return "Minecraft \(version) is not currently listed by Mojang."
        }
    }
}