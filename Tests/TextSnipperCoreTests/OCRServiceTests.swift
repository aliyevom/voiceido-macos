import CoreGraphics
import CoreText
import Foundation
import XCTest
@testable import TextSnipperCore

final class OCRServiceTests: XCTestCase {
    func testRecognizesClearText() throws {
        let image = try render("Hello World")
        let text = try OCRService.recognize(image, keepLineBreaks: true)
        XCTAssertTrue(
            text.localizedCaseInsensitiveContains("hello"),
            "Expected Hello in \(text)"
        )
        XCTAssertTrue(
            text.localizedCaseInsensitiveContains("world"),
            "Expected World in \(text)"
        )
    }

    private func render(_ text: String) throws -> CGImage {
        let width = 1000
        let height = 220
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            XCTFail("Could not create an image context")
            throw OCRTestError.noContext
        }

        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, 72, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1),
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        context.textPosition = CGPoint(x: 40, y: 70)
        CTLineDraw(line, context)

        guard let image = context.makeImage() else {
            XCTFail("Could not create a CGImage")
            throw OCRTestError.noImage
        }
        return image
    }
}

private enum OCRTestError: Error {
    case noContext
    case noImage
}
