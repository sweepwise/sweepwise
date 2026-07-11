import Foundation

public struct UnknownDir: Equatable, Sendable {
    public var path: String
    public var sizeBytes: Int64
    public var modifiedAt: Date
}

public struct ScanResult: Sendable {
    public var candidates: [Candidate] = []
    public var skipped: [String] = []
    public var unknownDirs: [UnknownDir] = []
}

public struct ScanProgress: Sendable {
    public var currentPath: String
    public var candidatesFound: Int
}

public final class Scanner {
    private let engine: RuleEngine
    private let minSizeBytes: Int64
    private let llmMinSizeBytes: Int64

    public init(engine: RuleEngine, minSizeBytes: Int64, llmMinSizeBytes: Int64) {
        self.engine = engine
        self.minSizeBytes = minSizeBytes
        self.llmMinSizeBytes = llmMinSizeBytes
    }

    public func scan(roots: [String],
                     progress: ((ScanProgress) -> Void)? = nil,
                     onCandidate: ((Candidate) -> Void)? = nil,
                     isPaused: (() -> Bool)? = nil,
                     isCancelled: () -> Bool = { false }) -> ScanResult {
        var result = ScanResult()
        let fm = FileManager.default
        for root in roots {
            waitWhilePaused(isPaused, isCancelled: isCancelled)
            guard !isCancelled() else { break }
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: root, isDirectory: &isDir), isDir.boolValue else {
                result.skipped.append(root)
                continue
            }
            // Track which depth-1 children produced candidates, for unknown-dir detection.
            let children = (try? fm.contentsOfDirectory(atPath: root)) ?? []
            for child in children.sorted() {
                waitWhilePaused(isPaused, isCancelled: isCancelled)
                guard !isCancelled() else { break }
                let childPath = (root as NSString).appendingPathComponent(child)
                let before = result.candidates.count
                walk(childPath, into: &result, progress: progress,
                     onCandidate: onCandidate, isPaused: isPaused, isCancelled: isCancelled)
                let produced = result.candidates.count > before
                if !produced, isDirectory(childPath) {
                    let size = Self.directorySize(childPath)
                    if size >= llmMinSizeBytes {
                        result.unknownDirs.append(UnknownDir(
                            path: childPath, sizeBytes: size,
                            modifiedAt: modificationDate(childPath)))
                    }
                }
            }
        }
        return result
    }

    /// Blocks the (background) scan thread while paused; cancellation breaks the wait.
    private func waitWhilePaused(_ isPaused: (() -> Bool)?, isCancelled: () -> Bool) {
        guard let isPaused else { return }
        while isPaused() && !isCancelled() {
            Thread.sleep(forTimeInterval: 0.05)
        }
    }

    private func walk(_ path: String, into result: inout ScanResult,
                      progress: ((ScanProgress) -> Void)?,
                      onCandidate: ((Candidate) -> Void)?,
                      isPaused: (() -> Bool)?, isCancelled: () -> Bool) {
        waitWhilePaused(isPaused, isCancelled: isCancelled)
        guard !isCancelled() else { return }
        progress?(ScanProgress(currentPath: path, candidatesFound: result.candidates.count))
        let modified = modificationDate(path)
        if let classification = engine.classify(path: path, modifiedAt: modified) {
            let size = isDirectory(path) ? Self.directorySize(path) : fileSize(path)
            if size >= minSizeBytes {
                let candidate = Candidate(path: path, sizeBytes: size,
                                          modifiedAt: modified,
                                          classification: classification)
                result.candidates.append(candidate)
                onCandidate?(candidate)
            }
            return  // matched: do not descend
        }
        guard isDirectory(path) else { return }
        guard let children = try? FileManager.default.contentsOfDirectory(atPath: path) else {
            result.skipped.append(path)
            return
        }
        for child in children.sorted() {
            walk((path as NSString).appendingPathComponent(child), into: &result,
                 progress: progress, onCandidate: onCandidate,
                 isPaused: isPaused, isCancelled: isCancelled)
        }
    }

    public static func directorySize(_ path: String) -> Int64 {
        let url = URL(fileURLWithPath: path)
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileSizeKey],
            options: [], errorHandler: { _, _ in true }) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey])
            total += Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
        }
        return total
    }

    private func isDirectory(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    private func fileSize(_ path: String) -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64).flatMap { $0 } ?? 0
    }

    private func modificationDate(_ path: String) -> Date {
        (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date)
            .flatMap { $0 } ?? .distantPast
    }
}
