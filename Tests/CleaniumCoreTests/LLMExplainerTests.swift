import XCTest
@testable import CleaniumCore

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

    func testProviderArguments() {
        XCTAssertEqual(LLMProvider.claude.arguments(prompt: "hi"), ["-p", "hi"])
        XCTAssertEqual(LLMProvider.codex.arguments(prompt: "hi"),
                       ["exec", "--skip-git-repo-check", "hi"])
        XCTAssertEqual(LLMProvider.gemini.arguments(prompt: "hi"), ["-p", "hi"])
    }

    func testDetectInstalledFindsBinariesInSearchPath() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cleanium-bin-\(UUID().uuidString)")
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
