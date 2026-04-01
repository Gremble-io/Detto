import XCTest
@testable import Tome

final class SessionStoreTests: XCTestCase {
    private var store: SessionStore!
    private var filesBefore: Set<URL> = []

    override func setUp() async throws {
        store = SessionStore()
        let dir = await store.sessionsDirectoryURL
        let files = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
        )) ?? []
        filesBefore = Set(files)
    }

    override func tearDown() async throws {
        await store.endSession()
        let dir = await store.sessionsDirectoryURL
        let files = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
        )) ?? []
        for file in Set(files).subtracting(filesBefore) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private func findNewFile() async throws -> URL {
        let dir = await store.sessionsDirectoryURL
        let files = try FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
        )
        return try XCTUnwrap(Set(files).subtracting(filesBefore).first)
    }

    // MARK: - Happy Path

    func testStartSessionCreatesFile() async throws {
        await store.startSession()

        let file = try await findNewFile()
        XCTAssertEqual(file.pathExtension, "jsonl")
        XCTAssertTrue(file.lastPathComponent.hasPrefix("session_"))
    }

    func testAppendRecordWritesJSONL() async throws {
        await store.startSession()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        await store.appendRecord(SessionRecord(speaker: .you, text: "Hello", timestamp: date))
        await store.appendRecord(SessionRecord(speaker: .them, text: "Hi", timestamp: date))
        await store.appendRecord(SessionRecord(speaker: .you, text: "Bye", timestamp: date))
        await store.endSession()

        let file = try await findNewFile()
        let content = try String(contentsOf: file, encoding: .utf8)
        let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }
        XCTAssertEqual(lines.count, 3)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        for line in lines {
            let record = try decoder.decode(SessionRecord.self, from: Data(line.utf8))
            XCTAssertFalse(record.text.isEmpty)
        }
    }

    // MARK: - Negative / Boundary

    func testAppendWithoutStartSession() async {
        await store.appendRecord(
            SessionRecord(speaker: .you, text: "Test", timestamp: Date())
        )
    }

    func testEndSessionTwice() async {
        await store.startSession()
        await store.endSession()
        await store.endSession()
    }

    func testAppendAfterEndSession() async {
        await store.startSession()
        await store.endSession()
        await store.appendRecord(
            SessionRecord(speaker: .you, text: "Test", timestamp: Date())
        )
    }
}
