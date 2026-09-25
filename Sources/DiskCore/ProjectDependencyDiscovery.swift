import Darwin
import Foundation

/// A directory-only companion to the cache scan. Paths are leads for a focused
/// scan, never measured bytes or cleanup candidates.
public struct ProjectDependencyDiscovery: Sendable {
    private static let projectHiddenFolders: Set<String> = [".worktrees"]
    public let paths: [String]
    public let directoriesVisited: Int
    public let skippedDirectories: Int
    public let complete: Bool

    public static func discover(
        home: URL,
        excludedFolders: [String] = [],
        promptAvoidanceFolders: [String] = [],
        directoryLimit: Int = 150_000,
        timeLimit: TimeInterval = 45,
        progress: (@Sendable (Self) -> Void)? = nil
    ) async throws -> Self {
        let worker = Task.detached(priority: .utility) {
            try walk(home: home, exclusions: FolderExclusions(paths: excludedFolders),
                     promptAvoidance: FolderExclusions(paths: promptAvoidanceFolders, resolveAliases: false),
                     directoryLimit: directoryLimit, timeLimit: timeLimit, progress: progress)
        }
        return try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    }

    private static func walk(home: URL, exclusions: FolderExclusions, promptAvoidance: FolderExclusions,
                             directoryLimit: Int, timeLimit: TimeInterval,
                             progress: (@Sendable (Self) -> Void)?) throws -> Self {
        let homePath = home.standardizedFileURL.path
        guard !exclusions.contains(homePath), !promptAvoidance.contains(homePath) else {
            return Self(paths: [], directoriesVisited: 0, skippedDirectories: 1, complete: false)
        }
        let started = Date()
        var pending = [homePath]
        var found: [String] = []
        var visited = 0
        var skipped = 0
        var complete = true
        var lastProgress = started
        while let path = pending.popLast() {
            try Task.checkCancellation()
            if visited >= directoryLimit || Date().timeIntervalSince(started) >= timeLimit {
                complete = false
                break
            }
            visited += 1
            guard let directory = opendir(path) else { skipped += 1; continue }
            defer { closedir(directory) }
            var entries = 0
            var children: [String] = []
            while let entry = readdir(directory) {
                entries += 1
                if entries & 255 == 0 { try Task.checkCancellation() }
                let name = withUnsafePointer(to: &entry.pointee.d_name) {
                    $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
                }
                guard (!name.hasPrefix(".") || projectHiddenFolders.contains(name)),
                      !(path == homePath && name == "Library") else { continue }
                let child = path + "/" + name
                guard !exclusions.contains(child) else { skipped += 1; continue }
                guard !promptAvoidance.contains(child) else { skipped += 1; continue }
                let kind = entry.pointee.d_type
                if kind != DT_DIR {
                    guard kind == DT_UNKNOWN, (try? lstatDirectory(at: child)) == true else { continue }
                }
                if name == "node_modules" { found.append(child); continue }
                children.append(child)
            }
            children.sort { left, right in
                if path == homePath {
                    let rank = ["Desktop": 0, "Documents": 1, "Downloads": 2]
                    let leftRank = rank[(left as NSString).lastPathComponent] ?? 3
                    let rightRank = rank[(right as NSString).lastPathComponent] ?? 3
                    if leftRank != rightRank { return leftRank > rightRank }
                }
                return left > right
            }
            pending.append(contentsOf: children)
            if let progress, Date().timeIntervalSince(lastProgress) >= 5 {
                progress(Self(paths: found.sorted(), directoriesVisited: visited,
                              skippedDirectories: skipped, complete: false))
                lastProgress = Date()
            }
        }
        return Self(paths: found.sorted(), directoriesVisited: visited, skippedDirectories: skipped, complete: complete)
    }

    private static func lstatDirectory(at path: String) throws -> Bool {
        var info = stat()
        guard lstat(path, &info) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        return (info.st_mode & S_IFMT) == S_IFDIR
    }
}
