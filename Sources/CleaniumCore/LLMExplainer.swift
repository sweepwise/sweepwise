import Foundation

public enum LLMProvider: String, Codable, CaseIterable, Sendable {
    case claude, codex, gemini

    public var displayName: String {
        switch self {
        case .claude: return "Claude (Claude Pro/Max)"
        case .codex: return "Codex (ChatGPT Plus)"
        case .gemini: return "Gemini"
        }
    }

    /// Folder names are untrusted input embedded in the prompt, and these CLIs are
    /// agentic — invoke each with tool use locked down so injected text in a path
    /// cannot trigger actions. Gemini's non-interactive default already requires
    /// approval for tool actions, which cannot be granted in -p mode.
    public func arguments(prompt: String) -> [String] {
        switch self {
        case .claude: return ["-p", prompt, "--disallowedTools",
                              "Bash,Edit,Write,NotebookEdit,WebFetch,WebSearch,Task,Read,Glob,Grep"]
        case .codex: return ["exec", "--sandbox", "read-only", "--skip-git-repo-check", prompt]
        case .gemini: return ["-p", prompt]
        }
    }

    public static var defaultSearchPaths: [String] {
        let home = NSHomeDirectory()
        return ["/opt/homebrew/bin", "/usr/local/bin",
                home + "/.local/bin", home + "/bin", home + "/.bun/bin"]
    }

    /// Returns installed providers with their binary paths, in enum order.
    public static func detectInstalled(
        searchPaths: [String] = defaultSearchPaths) -> [(LLMProvider, String)] {
        let fm = FileManager.default
        return allCases.compactMap { provider in
            for dir in searchPaths {
                let candidate = dir + "/" + provider.rawValue
                if fm.isExecutableFile(atPath: candidate) { return (provider, candidate) }
            }
            return nil
        }
    }
}

public struct LLMExplanation: Codable, Equatable, Sendable {
    public var category: Category
    public var risk: Risk
    public var context: String
    public var restoreNote: String
    public var suggestedRule: SuggestedRule?

    enum CodingKeys: String, CodingKey {
        case category, risk, context
        case restoreNote = "restore_note"
        case suggestedRule = "suggested_rule"
    }
}

public final class LLMExplainer {
    public let provider: LLMProvider
    public let binaryPath: String
    public let timeout: TimeInterval

    public init(provider: LLMProvider, binaryPath: String, timeout: TimeInterval = 30) {
        self.provider = provider
        self.binaryPath = binaryPath
        self.timeout = timeout
    }

    public static func prompt(path: String, sizeBytes: Int64) -> String {
        let size = ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
        return """
        You are a macOS disk-cleanup expert. Classify this folder for deletion candidacy.
        Folder: \(path)
        Size: \(size)
        Reply with ONLY a JSON object, no prose, exactly this shape:
        {"category": one of ["cache","devArtifact","llmModel","appLeftover","trash","download","unknown"],
         "risk": one of ["safe","rebuildable","redownload","userData","unknown"],
         "context": "one sentence: what this folder is",
         "restore_note": "one sentence: how to restore it if deleted",
         "suggested_rule": {"pattern": "glob or exact path matching this kind of folder",
                            "kind": "exactPath" or "glob"}}
        """
    }

    /// Extracts the first {...last} JSON object, tolerating markdown fences and prose.
    public static func parse(_ output: String) -> LLMExplanation? {
        guard let start = output.firstIndex(of: "{"),
              let end = output.lastIndex(of: "}"), start < end else { return nil }
        let json = String(output[start...end])
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(LLMExplanation.self, from: data)
    }

    public func explain(path: String, sizeBytes: Int64) -> LLMExplanation? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = provider.arguments(prompt: Self.prompt(path: path, sizeBytes: sizeBytes))
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }

        // Drain stdout concurrently so the CLI never blocks on a full pipe buffer
        // while we're polling isRunning below.
        var stdoutData = Data()
        let drainDone = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            stdoutData = pipe.fileHandleForReading.readDataToEndOfFile()
            drainDone.signal()
        }

        let deadline = Date(timeIntervalSinceNow: timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        if process.isRunning {
            process.terminate()
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        drainDone.wait()
        return Self.parse(String(data: stdoutData, encoding: .utf8) ?? "")
    }
}
