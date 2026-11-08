import XCTest
@testable import TextSnipperCore

final class ConfusableTextTests: XCTestCase {
    func testIsolatedTokenMatchesAConfusableCluster() {
        XCTAssertEqual(ConfusableText.isolatedToken(in: "\"O0Il1S5\""), "O0Il1S5")
        XCTAssertEqual(ConfusableText.isolatedToken(in: "l1I0O"), "l1I0O")
        XCTAssertNil(ConfusableText.isolatedToken(in: "58304C5D6DBC2206"))
        XCTAssertNil(ConfusableText.isolatedToken(in: "550e8400-e29b-41d4-a716-446655440000"))
    }

    func testEmbeddedTokenIsFoundInsideALine() {
        XCTAssertEqual(
            ConfusableText.embeddedTokens(in: "let salt = \"O0Il1S5\""),
            ["O0Il1S5"]
        )
    }

    func testOnlyConfusableSwapsCountAsTheSameToken() {
        XCTAssertTrue(ConfusableText.differsOnlyByConfusables("O0Il1S5", "00Il155"))
        XCTAssertFalse(ConfusableText.differsOnlyByConfusables("O0Il1S5", "hello!!"))
        XCTAssertFalse(ConfusableText.differsOnlyByConfusables("O0Il1S5", "O0Il1S5"))
    }

    func testReplacementStaysInsideTheToken() {
        let line = "let salt = \"00Il155\" and key = \"58304C5D6DBC2206\""
        XCTAssertEqual(
            ConfusableText.replaceToken("00Il155", or: "O0Il1S5", with: "O0Il1S5", in: line),
            "let salt = \"O0Il1S5\" and key = \"58304C5D6DBC2206\""
        )
    }
}
