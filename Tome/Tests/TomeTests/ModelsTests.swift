import XCTest
@testable import Tome

final class ModelsTests: XCTestCase {

    // MARK: - Speaker

    func testSpeakerCodableYou() throws {
        let data = try JSONEncoder().encode(Speaker.you)
        XCTAssertEqual(String(data: data, encoding: .utf8), "\"you\"")

        let decoded = try JSONDecoder().decode(Speaker.self, from: data)
        XCTAssertEqual(decoded, .you)
    }

    func testSpeakerCodableThem() throws {
        let data = try JSONEncoder().encode(Speaker.them)
        XCTAssertEqual(String(data: data, encoding: .utf8), "\"them\"")

        let decoded = try JSONDecoder().decode(Speaker.self, from: data)
        XCTAssertEqual(decoded, .them)
    }

    func testSpeakerDecodeInvalidValue() {
        let json = Data("\"unknown\"".utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(Speaker.self, from: json))
    }

    // MARK: - Utterance

    func testUtteranceCodableRoundTrip() throws {
        let date = Date(timeIntervalSince1970: 1_000_000)
        let original = Utterance(text: "Hello world", speaker: .you, timestamp: date)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Utterance.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.text, original.text)
        XCTAssertEqual(decoded.speaker, original.speaker)
        XCTAssertEqual(
            decoded.timestamp.timeIntervalSince1970,
            original.timestamp.timeIntervalSince1970,
            accuracy: 1
        )
    }

    func testUtteranceDecodeIncompleteJSON() {
        let json = Data("""
        {"id":"12345678-1234-1234-1234-123456789012","speaker":"you","timestamp":"2024-01-01T00:00:00Z"}
        """.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        XCTAssertThrowsError(try decoder.decode(Utterance.self, from: json))
    }

    func testUtteranceEmptyText() throws {
        let utterance = Utterance(text: "", speaker: .them)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(utterance)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Utterance.self, from: data)
        XCTAssertEqual(decoded.text, "")
    }

    // MARK: - SessionRecord

    func testSessionRecordCodableISO8601() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let original = SessionRecord(speaker: .them, text: "Test text", timestamp: date)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(SessionRecord.self, from: data)

        XCTAssertEqual(decoded.speaker, original.speaker)
        XCTAssertEqual(decoded.text, original.text)
        XCTAssertEqual(
            decoded.timestamp.timeIntervalSince1970,
            original.timestamp.timeIntervalSince1970,
            accuracy: 1
        )
    }
}
