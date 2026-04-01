import XCTest
@testable import Tome

final class TranscriptLoggerTests: XCTestCase {
    private var tmpDir: URL!
    private var logger: TranscriptLogger!

    override func setUp() {
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TomeTests-\(UUID().uuidString)")
        logger = TranscriptLogger()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    private func findTranscriptFile() throws -> URL {
        let files = try FileManager.default.contentsOfDirectory(
            at: tmpDir, includingPropertiesForKeys: nil
        )
        return try XCTUnwrap(
            files.first { $0.pathExtension == "md" && !$0.lastPathComponent.hasPrefix(".") }
        )
    }

    // MARK: - Session Creation

    func testStartSessionCreatesFile() async throws {
        try await logger.startSession(sourceApp: "TestApp", vaultPath: tmpDir.path)

        let file = try findTranscriptFile()
        XCTAssertEqual(file.pathExtension, "md")

        let content = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(content.hasPrefix("---\n"))
        XCTAssertTrue(content.contains("created:"))
        XCTAssertTrue(content.contains("time:"))
        XCTAssertTrue(content.contains("source_app: \"TestApp\""))
        XCTAssertTrue(content.contains("duration: \"00:00\""))
        XCTAssertTrue(content.contains("tags:"))
        XCTAssertTrue(content.contains("## Transcript"))
    }

    func testStartSessionCallCapture() async throws {
        try await logger.startSession(
            sourceApp: "Zoom", vaultPath: tmpDir.path, sessionType: .callCapture
        )
        let content = try String(contentsOf: try findTranscriptFile(), encoding: .utf8)
        XCTAssertTrue(content.contains("type: meeting"))
        XCTAssertTrue(content.contains("log/meeting"))
        XCTAssertTrue(content.contains("source/meeting"))

        let file = try findTranscriptFile()
        XCTAssertTrue(file.lastPathComponent.contains("Call Recording"))
    }

    func testStartSessionVoiceMemo() async throws {
        try await logger.startSession(
            sourceApp: "Tome", vaultPath: tmpDir.path, sessionType: .voiceMemo
        )
        let content = try String(contentsOf: try findTranscriptFile(), encoding: .utf8)
        XCTAssertTrue(content.contains("type: fleeting"))
        XCTAssertTrue(content.contains("log/voice"))
        XCTAssertTrue(content.contains("source/voice"))

        let file = try findTranscriptFile()
        XCTAssertTrue(file.lastPathComponent.contains("Voice Memo"))
    }

    // MARK: - Append

    func testAppendWritesUtterances() async throws {
        try await logger.startSession(sourceApp: "TestApp", vaultPath: tmpDir.path)
        let now = Date()
        await logger.append(speaker: "You", text: "Hello from me", timestamp: now)
        await logger.append(
            speaker: "Them", text: "Hello from them",
            timestamp: now.addingTimeInterval(5)
        )
        await logger.endSession()

        let content = try String(contentsOf: try findTranscriptFile(), encoding: .utf8)
        XCTAssertTrue(content.contains("**You**"))
        XCTAssertTrue(content.contains("Hello from me"))
        // labelForSpeaker converts "Them" → "Speaker 2"
        XCTAssertTrue(content.contains("**Speaker 2**"))
        XCTAssertTrue(content.contains("Hello from them"))
    }

    // MARK: - Diarization

    func testRewriteWithDiarization() async throws {
        let approxStart = Date()
        try await logger.startSession(sourceApp: "TestApp", vaultPath: tmpDir.path)
        await logger.endSession()

        // Inject "Them" entries into the file for diarization to process
        let file = try findTranscriptFile()
        var content = try String(contentsOf: file, encoding: .utf8)

        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "HH:mm:ss"
        let ts1 = timeFmt.string(from: approxStart.addingTimeInterval(5))
        let ts2 = timeFmt.string(from: approxStart.addingTimeInterval(15))

        content += "**Them** (\(ts1))\nFirst utterance\n\n"
        content += "**Them** (\(ts2))\nSecond utterance\n\n"
        try content.write(to: file, atomically: true, encoding: .utf8)

        await logger.rewriteWithDiarization(segments: [
            (speakerId: "spk_A", startTime: 0, endTime: 10),
            (speakerId: "spk_B", startTime: 10, endTime: 20),
        ])

        let result = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(result.contains("**Speaker 2**"))
        XCTAssertTrue(result.contains("**Speaker 3**"))
        XCTAssertFalse(result.contains("**Them**"))
        XCTAssertTrue(result.contains("First utterance"))
        XCTAssertTrue(result.contains("Second utterance"))
        XCTAssertTrue(result.contains("**Speakers:** 3"))
    }

    func testRewriteWithEmptySegments() async throws {
        try await logger.startSession(sourceApp: "TestApp", vaultPath: tmpDir.path)
        await logger.append(speaker: "You", text: "Hello", timestamp: Date())
        await logger.endSession()

        let file = try findTranscriptFile()
        let contentBefore = try String(contentsOf: file, encoding: .utf8)

        await logger.rewriteWithDiarization(segments: [])

        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        let contentAfter = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(contentAfter.contains("Hello"))
        // Empty segments → diarSpeakerMap is empty → allSpeakers = {"You"} → count = 1
        XCTAssertTrue(contentAfter.contains("**Speakers:** 1"))
    }

    func testRewriteWithNoSession() async {
        await logger.rewriteWithDiarization(segments: [
            (speakerId: "spk_A", startTime: 0, endTime: 10),
        ])
    }

    // MARK: - Finalize Frontmatter

    func testFinalizeFrontmatter() async throws {
        try await logger.startSession(sourceApp: "TestApp", vaultPath: tmpDir.path)
        await logger.append(speaker: "You", text: "Hello", timestamp: Date())
        await logger.append(speaker: "Them", text: "Reply", timestamp: Date())
        await logger.endSession()

        let result = await logger.finalizeFrontmatter()
        XCTAssertNotNil(result)

        let content = try String(contentsOf: result!, encoding: .utf8)
        XCTAssertTrue(content.contains("\"Speaker 2\""))
        XCTAssertTrue(content.contains("\"You\""))
        XCTAssertTrue(content.contains("**Speakers:** 2"))
        XCTAssertNotNil(
            content.range(of: #"duration: "\d{2}:\d{2}""#, options: .regularExpression)
        )
    }

    func testFinalizeFrontmatterRenamesFile() async throws {
        try await logger.startSession(sourceApp: "TestApp", vaultPath: tmpDir.path)
        await logger.updateContext("Important Meeting")
        await logger.endSession()

        let result = await logger.finalizeFrontmatter()
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.lastPathComponent.contains("Important Meeting"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result!.path))

        let files = try FileManager.default.contentsOfDirectory(
            at: tmpDir, includingPropertiesForKeys: nil
        )
        let mdFiles = files.filter {
            $0.pathExtension == "md" && !$0.lastPathComponent.hasPrefix(".")
        }
        XCTAssertEqual(mdFiles.count, 1)
    }

    func testFinalizeFrontmatterNoSession() async {
        let result = await logger.finalizeFrontmatter()
        XCTAssertNil(result)
    }

    // MARK: - End Session

    func testEndSessionTwice() async throws {
        try await logger.startSession(sourceApp: "TestApp", vaultPath: tmpDir.path)
        await logger.endSession()
        await logger.endSession()
    }

    // MARK: - Full Flow

    func testFullFlow() async throws {
        try await logger.startSession(
            sourceApp: "Zoom", vaultPath: tmpDir.path, sessionType: .callCapture
        )
        let now = Date()
        await logger.append(speaker: "You", text: "Hello everyone", timestamp: now)
        await logger.append(
            speaker: "Them", text: "Hi there",
            timestamp: now.addingTimeInterval(3)
        )
        await logger.updateContext("Weekly Standup")
        await logger.endSession()

        let finalPath = await logger.finalizeFrontmatter()
        XCTAssertNotNil(finalPath)

        let content = try String(contentsOf: finalPath!, encoding: .utf8)
        XCTAssertTrue(content.contains("source_app: \"Zoom\""))
        XCTAssertTrue(content.contains("type: meeting"))
        XCTAssertTrue(content.contains("Hello everyone"))
        XCTAssertTrue(content.contains("Hi there"))
        XCTAssertTrue(content.contains("Weekly Standup"))
        XCTAssertTrue(finalPath!.lastPathComponent.contains("Weekly Standup"))
    }
}
