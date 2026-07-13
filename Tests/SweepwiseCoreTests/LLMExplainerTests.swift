import XCTest
@testable import SweepwiseCore

final class LLMExplainerTests: XCTestCase {
    let goodJSON = """
    {"category": "appLeftover", "risk": "userData",
     "context": "Voice recordings from the workwithme app.",
     "restore_note": "No restore possible; recordings are user-generated.",
     "suggested_rule": {"pattern": "~/Library/Application Support/workwithme/voice",
                        "kind": "exactPath"}}
    """

    func testParsePlainJSON() {
        let e = LLMExplainer.parse(goodJSON)
        XCTAssertEqual(e?.category, .appLeftover)
        XCTAssertEqual(e?.risk, .userData)
        XCTAssertEqual(e?.suggestedRule?.kind, .exactPath)
    }

    func testParseFencedJSON() {
        let fenced = "Here you go:\n```json\n\(goodJSON)\n```\nDone."
        XCTAssertNotNil(LLMExplainer.parse(fenced))
    }

    func testParseGarbageReturnsNil() {
        XCTAssertNil(LLMExplainer.parse("I cannot help with that."))
        XCTAssertNil(LLMExplainer.parse(""))
    }

    func testParseUnknownEnumReturnsNil() {
        let bad = goodJSON.replacingOccurrences(of: "appLeftover", with: "mystery")
        XCTAssertNil(LLMExplainer.parse(bad))
    }

    func testPromptContainsPathSizeAndSchema() {
        let p = LLMExplainer.prompt(path: "/x/y", sizeBytes: 1_500_000_000)
        XCTAssertTrue(p.contains("/x/y"))
        XCTAssertTrue(p.contains("1.5 GB") || p.contains("1,5 GB"))
        XCTAssertTrue(p.contains("suggested_rule"))
        XCTAssertTrue(p.contains("exactPath"))
    }

    func testExtractClaudeEnvelopeWithUsage() throws {
        let inner = goodJSON.replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
        let envelope = """
        {"type": "result", "result": "\(inner)",
         "usage": {"input_tokens": 100, "cache_creation_input_tokens": 20,
                   "cache_read_input_tokens": 30, "output_tokens": 40},
         "total_cost_usd": 0.01}
        """
        let reply = try XCTUnwrap(LLMExplainer.extract(envelope, provider: .claude))
        XCTAssertEqual(reply.explanation.category, .appLeftover)
        XCTAssertEqual(reply.usage?.inputTokens, 120)      // fresh input + cache creation
        XCTAssertEqual(reply.usage?.cacheReadTokens, 30)   // served from prompt cache
        XCTAssertEqual(reply.usage?.outputTokens, 40)
    }

    func testExtractFallsBackToRawParseWithoutEnvelope() throws {
        // Non-envelope output (other providers, or claude behaving unexpectedly)
        // still parses; usage is simply unknown.
        let reply = try XCTUnwrap(LLMExplainer.extract(goodJSON, provider: .claude))
        XCTAssertEqual(reply.explanation.category, .appLeftover)
        XCTAssertNil(reply.usage)
        let gemini = try XCTUnwrap(LLMExplainer.extract(goodJSON, provider: .gemini))
        XCTAssertNil(gemini.usage)
    }

    func testBatchPromptListsAllFoldersAndArraySchema() {
        let p = LLMExplainer.promptBatch(dirs: [("/a/one", 1_000_000), ("/b/two", 2_000_000)])
        XCTAssertTrue(p.contains("/a/one"))
        XCTAssertTrue(p.contains("/b/two"))
        XCTAssertTrue(p.contains("JSON array"))
        XCTAssertTrue(p.contains("\"path\""))
    }

    func testParseBatchMapsByPathAndSkipsBadItems() throws {
        let batch = """
        Here you go:
        ```json
        [{"path": "/a/one", "category": "cache", "risk": "safe",
          "context": "c1", "restore_note": "r1"},
         {"path": "/b/two", "category": "NOT_A_CATEGORY", "risk": "safe",
          "context": "c2", "restore_note": "r2"},
         {"path": "/c/three", "category": "llmModel", "risk": "redownload",
          "context": "c3", "restore_note": "r3",
          "suggested_rule": {"pattern": "/c/three", "kind": "exactPath"}}]
        ```
        """
        let map = try XCTUnwrap(LLMExplainer.parseBatch(batch))
        XCTAssertEqual(map.count, 2, "malformed item must be skipped, not sink the batch")
        XCTAssertEqual(map["/a/one"]?.category, .cache)
        XCTAssertEqual(map["/c/three"]?.suggestedRule?.kind, .exactPath)
    }

    func testExtractBatchReadsClaudeEnvelopeUsage() throws {
        let inner = #"[{\"path\": \"/a/one\", \"category\": \"cache\", \"risk\": \"safe\", \"context\": \"c\", \"restore_note\": \"r\"}]"#
        let envelope = """
        {"type": "result", "result": "\(inner)",
         "usage": {"input_tokens": 10, "cache_read_input_tokens": 5, "output_tokens": 7}}
        """
        let reply = try XCTUnwrap(LLMExplainer.extractBatch(envelope, provider: .claude))
        XCTAssertEqual(reply.explanations["/a/one"]?.category, .cache)
        XCTAssertEqual(reply.usage?.inputTokens, 10)
        XCTAssertEqual(reply.usage?.cacheReadTokens, 5)
        XCTAssertEqual(reply.usage?.outputTokens, 7)
    }

    func testTimeoutKillsProcessThatIgnoresSIGTERM() throws {
        // A CLI that traps SIGTERM must still die (SIGKILL escalation) so a
        // stuck provider can't outlive its explain() call.
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sweepwise-kill-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let script = dir.appendingPathComponent("stubborn")
        let pidFile = dir.appendingPathComponent("pid")
        try "#!/bin/sh\ntrap '' TERM\necho $$ > \"\(pidFile.path)\"\nsleep 60\n"
            .write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        let explainer = LLMExplainer(provider: .claude, binaryPath: script.path, timeout: 1)
        XCTAssertNil(explainer.explain(path: "/x", sizeBytes: 1))

        let pidString = try String(contentsOf: pidFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let pid = try XCTUnwrap(Int32(pidString))
        // The child trapped SIGTERM; SIGKILL escalation must still end it soon.
        var dead = false
        for _ in 0..<50 where !dead {
            dead = kill(pid, 0) != 0
            if !dead { Thread.sleep(forTimeInterval: 0.1) }
        }
        XCTAssertTrue(dead, "stubborn child (pid \(pid)) survived the timeout kill path")
    }

    func testEveryProviderHasASetupURL() {
        for provider in LLMProvider.allCases {
            let url = provider.setupURL
            XCTAssertEqual(url.scheme, "https", "\(provider) setup URL must be https")
            XCTAssertFalse(url.host?.isEmpty ?? true, "\(provider) setup URL needs a host")
        }
    }

    func testProviderArgumentsRestrictTools() {
        // Folder names are untrusted input embedded in the prompt; the CLIs are
        // agentic, so every provider must be invoked with tool use locked down.
        // claude additionally uses the JSON envelope so token usage is reported.
        XCTAssertEqual(LLMProvider.claude.arguments(prompt: "hi"),
                       ["-p", "hi", "--output-format", "json", "--disallowedTools",
                        "Bash,Edit,Write,NotebookEdit,WebFetch,WebSearch,Task,Read,Glob,Grep"])
        XCTAssertEqual(LLMProvider.codex.arguments(prompt: "hi"),
                       ["exec", "--sandbox", "read-only", "--skip-git-repo-check", "hi"])
        XCTAssertEqual(LLMProvider.gemini.arguments(prompt: "hi"), ["-p", "hi"])
    }

    func testExplainDrainsLargeStdoutWithoutDeadlock() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sweepwise-llm-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let script = dir.appendingPathComponent("fake-claude")

        // Filler exceeds the ~64KB pipe buffer; under the old (post-exit) read this
        // would deadlock the child on a full pipe and cause explain() to time out.
        let filler = String(repeating: "This folder likely contains build artifacts. ", count: 4000)
        let scriptContents = """
        #!/bin/sh
        printf '%s' '\(filler)'
        cat <<'JSON'
        \(goodJSON)
        JSON
        """
        try scriptContents.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        let explainer = LLMExplainer(provider: .claude, binaryPath: script.path, timeout: 10)
        let result = explainer.explain(path: "/tmp/whatever", sizeBytes: 1_000_000)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.explanation.category, .appLeftover)
    }

    // Fix 7: nominated rules must relate to the deleted path and not be trivially broad.
    func testSuggestedRuleValidExactPathPasses() {
        let origin = NSHomeDirectory() + "/Library/Application Support/foo/voice"
        let s = SuggestedRule(pattern: "~/Library/Application Support/foo/voice", kind: .exactPath)
        XCTAssertTrue(s.isValid(forOriginPath: origin))
    }

    func testSuggestedRuleExactPathMismatchFails() {
        let origin = NSHomeDirectory() + "/Library/Application Support/foo/voice"
        let s = SuggestedRule(pattern: "~/Library/Application Support/bar/other", kind: .exactPath)
        XCTAssertFalse(s.isValid(forOriginPath: origin))
    }

    func testSuggestedRuleGlobMatchingOriginPasses() {
        let origin = NSHomeDirectory() + "/Library/Caches/acme-widgets-9.9"
        let s = SuggestedRule(pattern: "~/Library/Caches/acme-widgets*", kind: .glob)
        XCTAssertTrue(s.isValid(forOriginPath: origin))
    }

    func testSuggestedRuleBareWildcardRejected() {
        let origin = NSHomeDirectory() + "/Library/Caches/anything"
        XCTAssertFalse(SuggestedRule(pattern: "*", kind: .glob).isValid(forOriginPath: origin))
        XCTAssertFalse(SuggestedRule(pattern: "**", kind: .glob).isValid(forOriginPath: origin))
        // Too broad: only one literal component even though it matches the origin.
        XCTAssertFalse(SuggestedRule(pattern: "~/Library/*", kind: .glob)
            .isValid(forOriginPath: origin))
    }

    func testDetectInstalledFindsBinariesInSearchPath() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sweepwise-bin-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let fake = dir.appendingPathComponent("claude")
        try "#!/bin/sh\n".write(to: fake, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fake.path)
        let found = LLMProvider.detectInstalled(searchPaths: [dir.path])
        XCTAssertEqual(found.map(\.0), [.claude])
        XCTAssertEqual(found.first?.1, fake.path)
    }
}
