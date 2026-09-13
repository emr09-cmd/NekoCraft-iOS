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
                            Text(model.isPrepared ? "Libraries ready" : "Not downloaded")
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
                        Text("Libraries are fetched on demand and kept out of the app bundle.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        Task { await model.prepareVersion() }
                    } label: {
                        HStack {
                            if model.isPreparing {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: model.isPrepared ? "arrow.clockwise" : "arrow.down.circle.fill")
                            }
                            Text(model.isPreparing ? "Preparing 1.21.11..." : model.isPrepared ? "Refresh libraries" : "Prepare 1.21.11")
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
    @Published private(set) var libraryCount = 0
    @Published private(set) var message: String?

    let version = "1.21.11"
    private static let usernameKey = "offlineUsername"
    private let libraryStore = LibraryStore()
    private var javaRuntime: OpaquePointer?

    init() {
        username = UserDefaults.standard.string(forKey: Self.usernameKey) ?? "Dev"
        libraryCount = libraryStore.fileCount()
    }

    func prepareVersion() async {
        isPreparing = true
        message = nil
        defer { isPreparing = false }

        do {
            let manifest = try await MojangManifestClient().versionManifest(for: version)
            let downloaded = try await libraryStore.download(manifest.libraries)
            libraryCount = downloaded
            isPrepared = true
            message = try startJavaRuntime(downloadedLibraries: downloaded)
        } catch {
            message = error.localizedDescription
        }
    }

    private func startJavaRuntime(downloadedLibraries: Int) throws -> String {
        guard let runtimeHome = Bundle.main.url(forResource: "JavaRuntime", withExtension: nil) else {
            throw LauncherError.runtimeNotBundled
        }

        javaRuntime = NekoCraftJavaRuntimeCreate(runtimeHome.path)
        guard let javaRuntime else {
            throw LauncherError.runtimeUnavailable
        }

        let result = NekoCraftJavaRuntimeStart(javaRuntime, 0, nil)
        guard result == 0 else {
            throw LauncherError.runtimeStartFailed(result)
        }

        return "Downloaded \(downloadedLibraries) Java libraries. Java 21 runtime started."
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

private struct VersionIndex: Decodable {
    let versions: [VersionReference]
}

private struct VersionReference: Decodable {
    let id: String
    let url: URL
}

private struct VersionManifest: Decodable {
    let libraries: [Library]
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