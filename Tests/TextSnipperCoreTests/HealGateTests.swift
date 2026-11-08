import XCTest
@testable import TextSnipperCore

final class HealGateTests: XCTestCase {
    func testSentencesAndCodeBothAskForRepair() {
        XCTAssertTrue(HealGate.shouldConsult("Hello from the meeting notes today.", codeCapture: false))
        XCTAssertTrue(HealGate.shouldConsult("func score() -> Int { return 0 }", codeCapture: true))
    }

    func testShortTextSkipsTheNetwork() {
        XCTAssertFalse(HealGate.shouldConsult("ok", codeCapture: true))
    }

    func testTerminalAndCodeAskForRepair() {
        XCTAssertTrue(HealGate.shouldConsult("zsh: no such file or directory: ./build.sh", codeCapture: true))
        XCTAssertTrue(HealGate.shouldConsult("git clone https://example.com/textsniper.git", codeCapture: true))
    }

    func testCodeAsksEvenOutsideCodeMode() {
        XCTAssertTrue(HealGate.shouldConsult("zsh: no such file or directory: ./build.sh", codeCapture: false))
    }

    func testDamagedGlyphsAskEvenOutsideCodeMode() {
        XCTAssertTrue(HealGate.shouldConsult("aliyevom textsnipper *|", codeCapture: false))
        XCTAssertTrue(HealGate.shouldConsult("Executed 9 tests, with @ failures (0 unexpected)", codeCapture: false))
    }
}
