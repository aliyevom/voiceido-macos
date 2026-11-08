import CoreGraphics
import CoreText
import Foundation
import TextSnipperCore

func expect(_ condition: Bool, _ message: String) {
    guard condition else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let primary = CaptureGeometry.displaySourceRect(
    globalRect: CGRect(x: 100, y: 810, width: 200, height: 40),
    screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900)
)
expect(primary == CGRect(x: 100, y: 50, width: 200, height: 40), "primary display source rect \(String(describing: primary))")

let lower = CaptureGeometry.displaySourceRect(
    globalRect: CGRect(x: 1540, y: 100, width: 100, height: 50),
    screenFrame: CGRect(x: 1440, y: -200, width: 1000, height: 800)
)
expect(lower == CGRect(x: 100, y: 450, width: 100, height: 50), "secondary display source rect \(String(describing: lower))")

let clipped = CaptureGeometry.displaySourceRect(
    globalRect: CGRect(x: -10, y: 10, width: 30, height: 20),
    screenFrame: CGRect(x: 0, y: 0, width: 100, height: 100)
)
expect(clipped == CGRect(x: 0, y: 70, width: 20, height: 20), "clipped source rect \(String(describing: clipped))")

expect(
    CaptureGeometry.displaySourceRect(
        globalRect: CGRect(x: 200, y: 200, width: 10, height: 10),
        screenFrame: CGRect(x: 0, y: 0, width: 100, height: 100)
    ) == nil,
    "off-screen selection should be nil"
)

let sameLine = TextAssembly.assemble([
    TextPiece(text: "world", box: CGRect(x: 0.5, y: 0.6, width: 0.2, height: 0.1)),
    TextPiece(text: "Hello", box: CGRect(x: 0.1, y: 0.61, width: 0.2, height: 0.1)),
], keepLineBreaks: true)
expect(sameLine == "Hello world", "same line got \(sameLine)")

let lines = TextAssembly.assemble([
    TextPiece(text: "world", box: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.08)),
    TextPiece(text: "there", box: CGRect(x: 0.45, y: 0.7, width: 0.2, height: 0.08)),
    TextPiece(text: "Hello", box: CGRect(x: 0.1, y: 0.7, width: 0.2, height: 0.08)),
], keepLineBreaks: true)
expect(lines == "Hello there\nworld", "line breaks got \(lines)")

let paragraph = TextAssembly.assemble([
    TextPiece(text: "Hello", box: CGRect(x: 0.1, y: 0.7, width: 0.2, height: 0.08)),
    TextPiece(text: "world", box: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.08)),
], keepLineBreaks: false)
expect(paragraph == "Hello world", "paragraph got \(paragraph)")

expect(
    TextAssembly.assemble([
        TextPiece(text: "   ", box: CGRect(x: 0, y: 0, width: 0.1, height: 0.1)),
    ], keepLineBreaks: true).isEmpty,
    "blank pieces should be dropped"
)

do {
    let image = try render("Hello World")
    let text = try OCRService.recognize(image, keepLineBreaks: true)
    expect(text.localizedCaseInsensitiveContains("hello"), "OCR missed hello in \(text)")
    expect(text.localizedCaseInsensitiveContains("world"), "OCR missed world in \(text)")
} catch {
    fputs("FAIL: OCR threw \(error)\n", stderr)
    exit(1)
}

print("ok")

func render(_ text: String) throws -> CGImage {
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
        throw RenderError.noContext
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
    guard let image = context.makeImage() else { throw RenderError.noImage }
    return image
}

enum RenderError: Error {
    case noContext
    case noImage
}
