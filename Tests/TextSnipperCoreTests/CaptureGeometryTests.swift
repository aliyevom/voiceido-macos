import CoreGraphics
import XCTest
@testable import TextSnipperCore

final class CaptureGeometryTests: XCTestCase {
    func testPrimaryDisplaySelectionNearTheTop() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let selection = CGRect(x: 100, y: 810, width: 200, height: 40)
        let source = CaptureGeometry.displaySourceRect(globalRect: selection, screenFrame: screen)
        XCTAssertEqual(source, CGRect(x: 100, y: 50, width: 200, height: 40))
    }

    func testSelectionOnADisplayBelowThePrimary() {
        let screen = CGRect(x: 1440, y: -200, width: 1000, height: 800)
        let selection = CGRect(x: 1540, y: 100, width: 100, height: 50)
        let source = CaptureGeometry.displaySourceRect(globalRect: selection, screenFrame: screen)
        XCTAssertEqual(source, CGRect(x: 100, y: 450, width: 100, height: 50))
    }

    func testSelectionIsClippedToTheScreen() {
        let screen = CGRect(x: 0, y: 0, width: 100, height: 100)
        let selection = CGRect(x: -10, y: 10, width: 30, height: 20)
        let source = CaptureGeometry.displaySourceRect(globalRect: selection, screenFrame: screen)
        XCTAssertEqual(source, CGRect(x: 0, y: 70, width: 20, height: 20))
    }

    func testSelectionOnAnotherScreenReturnsNil() {
        let screen = CGRect(x: 0, y: 0, width: 100, height: 100)
        let selection = CGRect(x: 200, y: 200, width: 10, height: 10)
        XCTAssertNil(CaptureGeometry.displaySourceRect(globalRect: selection, screenFrame: screen))
    }
}
