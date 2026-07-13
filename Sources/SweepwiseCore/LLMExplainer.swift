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

    /// The CLI's official install/setup page, linked from Settings → AI.
    public var setupURL: URL {
        switch self {
        case .claude: return URL(string: "https://github.com/anthropics/claude-code")!
        case .codex: return URL(string: "https://github.com/openai/codex")!
        case .gemini: return URL(string: "https://github.com/google-gemini/gemini-cli")!
        }
    }

    /// One-line install hint shown next to the setup link.
    public var installHint: String {
        switch self {
        case .claude: return "curl -fsSL https://claude.ai/install.sh | bash — needs Claude Pro or Max"
        case .codex: return "npm install -g @openai/codex — needs ChatGPT Plus or Pro"
        case .gemini: return "npm install -g @google/gemini-cli"
        }
    }

    /// Folder names are untrusted input embedded in the prompt, and these CLIs are
    /// agentic — invoke each with tool use locked down so injected text in a path
    /// cannot trigger actions. Gemini's non-interactive default already requires
    /// approval for tool actions, which cannot be granted in -p mode.
    public func arguments(prompt: String) -> [String] {
        switch self {
        case .claude: return ["-p", prompt, "--output-format", "json", "--disallowedTools",
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

public struct LLMUsage: Equatable, Sendable {
    /// Fresh prompt-side tokens (regular input + cache creation).
    public var inputTokens: Int
    /// Prompt-side tokens served from Anthropic's prompt cache (~10% of the
    /// price of fresh input). The CLI manages cache breakpoints automatically.
    public var cacheReadTokens: Int
    public var outputTokens: Int
    public var totalTokens: Int { inputTokens + cacheReadTokens + outputTokens }
}

public struct LLMReply: Equatable, Sendable {
    public var explanation: LLMExplanation
    /// nil when the provider's output format does not report token usage.
    public var usage: LLMUsage?
}

public struct LLMBatchReply: Equatable, Sendable {
    /// Explanations keyed by the folder path echoed back by the model.
    public var explanations: [String: LLMExplanation]
    public var usage: LLMUsage?
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

    public static func promptBatch(dirs: [(path: String, sizeBytes: Int64)]) -> String {
        let lines = dirs.enumerated().map { i, dir in
            let size = ByteCountFormatter.string(fromByteCount: dir.sizeBytes, countStyle: .file)
            return "\(i + 1). \(dir.path) (\(size))"
        }.joined(separator: "\n")
        return """
        You are a macOS disk-cleanup expert. Classify EACH of these folders for deletion candidacy.
        Folders:
        \(lines)
        Reply with ONLY a JSON array, no prose — exactly one object per folder, in this shape:
        [{"path": "the folder path exactly as listed above",
          "category": one of ["cache","devArtifact","llmModel","appLeftover","trash","download","unknown"],
          "risk": one of ["safe","rebuildable","redownload","userData","unknown"],
          "context": "one sentence: what this folder is",
          "restore_note": "one sentence: how to restore it if deleted",
          "suggested_rule": {"pattern": "glob or exact path matching this kind of folder",
                             "kind": "exactPath" or "glob"}}]
        """
    }

    private struct BatchItem: Decodable {
        let path: String
        let category: Category
        let risk: Risk
        let context: String
        let restoreNote: String
        let suggestedRule: SuggestedRule?

        enum CodingKeys: String, CodingKey {
            case path, category, risk, context
            case restoreNote = "restore_note"
            case suggestedRule = "suggested_rule"
        }
    }

    /// One malformed array element must not sink the whole batch.
    private struct LossyBatchItem: Decodable {
        let item: BatchItem?
        init(from decoder: Decoder) {
            item = try? BatchItem(from: decoder)
        }
    }

    /// Extracts the first [...last] JSON array, tolerating markdown fences and
    /// prose, and maps well-formed elements by path (malformed ones are dropped).
    public static func parseBatch(_ output: String) -> [String: LLMExplanation]? {
        guard let start = output.firstIndex(of: "["),
              let end = output.lastIndex(of: "]"), start < end,
              let data = String(output[start...end]).data(using: .utf8),
              let items = try? JSONDecoder().decode([LossyBatchItem].self, from: data)
        else { return nil }
        let pairs = items.compactMap(\.item).map { item in
            (item.path, LLMExplanation(category: item.category, risk: item.risk,
                                       context: item.context, restoreNote: item.restoreNote,
                                       suggestedRule: item.suggestedRule))
        }
        guard !pairs.isEmpty else { return nil }
        return Dictionary(pairs, uniquingKeysWith: { first, _ in first })
    }

    public static func extractBatch(_ output: String, provider: LLMProvider) -> LLMBatchReply? {
        if provider == .claude,
           let data = output.data(using: .utf8),
           let envelope = try? JSONDecoder().decode(ClaudeEnvelope.self, from: data) {
            guard let explanations = parseBatch(envelope.result) else { return nil }
            return LLMBatchReply(explanations: explanations, usage: envelope.tokenUsage)
        }
        guard let explanations = parseBatch(output) else { return nil }
        return LLMBatchReply(explanations: explanations, usage: nil)
    }

    /// Extracts the first {...last} JSON object, tolerating markdown fences and prose.
    public static func parse(_ output: String) -> LLMExplanation? {
        guard let start = output.firstIndex(of: "{"),
              let end = output.lastIndex(of: "}"), start < end else { return nil }
        let json = String(output[start...end])
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(LLMExplanation.self, from: data)
    }

    /// claude --output-format json wraps the reply in an envelope carrying token usage.
    private struct ClaudeEnvelope: Decodable {
        struct Usage: Decodable {
            let input_tokens: Int?
            let cache_creation_input_tokens: Int?
            let cache_read_input_tokens: Int?
            let output_tokens: Int?
        }
        let result: String
        let usage: Usage?

        var tokenUsage: LLMUsage? {
            usage.map {
                LLMUsage(inputTokens: ($0.input_tokens ?? 0)
                            + ($0.cache_creation_input_tokens ?? 0),
                         cacheReadTokens: $0.cache_read_input_tokens ?? 0,
                         outputTokens: $0.output_tokens ?? 0)
            }
        }
    }

    /// Turns raw CLI stdout into an explanation plus token usage where the
    /// provider reports it (claude's JSON envelope). Falls back to plain parsing
    /// for other providers or unexpected output shapes.
    public static func extract(_ output: String, provider: LLMProvider) -> LLMReply? {
        if provider == .claude,
           let data = output.data(using: .utf8),
           let envelope = try? JSONDecoder().decode(ClaudeEnvelope.self, from: data) {
            guard let explanation = parse(envelope.result) else { return nil }
            return LLMReply(explanation: explanation, usage: envelope.tokenUsage)
        }
        guard let explanation = parse(output) else { return nil }
        return LLMReply(explanation: explanation, usage: nil)
    }

    /// One folder per CLI call. Each invocation carries the CLI's full fixed
    /// overhead (system prompt, tool definitions — tens of thousands of input
    /// tokens for claude), so prefer `explainBatch` for multiple folders.
    public func explain(path: String, sizeBytes: Int64) -> LLMReply? {
        guard let output = run(prompt: Self.prompt(path: path, sizeBytes: sizeBytes))
        else { return nil }
        return Self.extract(output, provider: provider)
    }

    /// Classifies many folders in a single CLI call, paying the per-invocation
    /// overhead once. Returns explanations keyed by path.
    public func explainBatch(dirs: [(path: String, sizeBytes: Int64)]) -> LLMBatchReply? {
        guard !dirs.isEmpty,
              let output = run(prompt: Self.promptBatch(dirs: dirs)) else { return nil }
        return Self.extractBatch(output, provider: provider)
    }

    private func run(prompt: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = provider.arguments(prompt: prompt)
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
            // SIGTERM first; a CLI that traps it gets SIGKILL after a short grace
            // period so a stuck provider can't outlive this call.
            process.terminate()
            let grace = Date(timeIntervalSinceNow: 2)
            while process.isRunning && Date() < grace {
                Thread.sleep(forTimeInterval: 0.1)
            }
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        drainDone.wait()
        return String(data: stdoutData, encoding: .utf8)
    }
}
