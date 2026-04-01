import XCTest
@testable import Tome

@MainActor
final class TranscriptStoreTests: XCTestCase {

    func testAppend() {
        let store = TranscriptStore()
        let utterance = Utterance(text: "Hello", speaker: .you)
        store.append(utterance)

        XCTAssertEqual(store.utterances.count, 1)
        XCTAssertEqual(store.utterances[0].text, "Hello")
        XCTAssertNotNil(store.lastUtteranceTimestamp)
    }

    func testAppendPreservesOrder() {
        let store = TranscriptStore()
        store.append(Utterance(text: "First", speaker: .you))
        store.append(Utterance(text: "Second", speaker: .them))
        store.append(Utterance(text: "Third", speaker: .you))

        XCTAssertEqual(store.utterances.map(\.text), ["First", "Second", "Third"])
    }

    func testClear() {
        let store = TranscriptStore()
        store.append(Utterance(text: "Hello", speaker: .you))
        store.clear()

        XCTAssertTrue(store.utterances.isEmpty)
        XCTAssertNil(store.lastUtteranceTimestamp)
    }

    func testClearOnEmpty() {
        let store = TranscriptStore()
        store.clear()
        XCTAssertTrue(store.utterances.isEmpty)
    }

    func testClearResetsVolatileText() {
        let store = TranscriptStore()
        store.volatileYouText = "typing..."
        store.volatileThemText = "speaking..."
        store.clear()

        XCTAssertEqual(store.volatileYouText, "")
        XCTAssertEqual(store.volatileThemText, "")
    }
}
