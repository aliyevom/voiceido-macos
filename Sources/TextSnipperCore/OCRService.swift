import CoreGraphics
import Foundation
import Vision

public struct TokenDispute: @unchecked Sendable {
    public let token: String
    public let reread: String
    public let image: CGImage

    public init(token: String, reread: String, image: CGImage) {
        self.token = token
        self.reread = reread
        self.image = image
    }
}

public struct CodeRecognition: Sendable {
    public var text: String
    public var disputes: [TokenDispute]

    public init(text: String, disputes: [TokenDispute]) {
        self.text = text
        self.disputes = disputes
    }
}

public enum OCRService {
    public static func recognize(_ image: CGImage, keepLineBreaks: Bool, codeCapture: Bool = false) throws -> String {
        try inspect(image, keepLineBreaks: keepLineBreaks, codeCapture: codeCapture).text
    }

    /// Recognizes text. The vision model, when enabled, reads symbols and lookalike letters.
    public static func inspect(_ image: CGImage, keepLineBreaks: Bool, codeCapture: Bool = false) throws -> CodeRecognition {
        let source = codeCapture ? scaledForCode(image) : image
        let preserveColumns = codeCapture && keepLineBreaks
        let pieces = try readPieces(source, codeCapture: codeCapture)
        let text = TextAssembly.assemble(pieces, keepLineBreaks: keepLineBreaks, preserveColumns: preserveColumns)
        return CodeRecognition(text: text, disputes: [])
    }

    private static func readPieces(_ image: CGImage, codeCapture: Bool) throws -> [TextPiece] {
        let preferred = Array(Locale.preferredLanguages.prefix(4))
        let request = makeRequest(languages: preferred, codeCapture: codeCapture)
        do {
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
            return pieces(from: request)
        } catch {
            let fallback = makeRequest(languages: ["en-US"], codeCapture: false)
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([fallback])
            return pieces(from: fallback)
        }
    }

    private static func makeRequest(languages: [String], codeCapture: Bool) -> VNRecognizeTextRequest {
        let request = VNRecognizeTextRequest()
        request.revision = VNRecognizeTextRequestRevision3
        request.recognitionLevel = .accurate
        // Language correction rewrites hashes and identifiers, so code capture leaves glyphs as read.
        request.usesLanguageCorrection = !codeCapture
        request.automaticallyDetectsLanguage = !codeCapture
        request.minimumTextHeight = 0
        if codeCapture {
            request.recognitionLanguages = ["en-US"]
        } else if !languages.isEmpty {
            request.recognitionLanguages = languages
        }
        return request
    }

    /// Enlarges a small capture so thin code glyphs are easier to tell apart.
    private static func scaledForCode(_ image: CGImage) -> CGImage {
        let minSide = min(image.width, image.height)
        guard minSide > 0, minSide < 1400 else { return image }
        let factor = min(2.0, 1400.0 / Double(minSide))
        guard factor > 1.05 else { return image }
        let width = max(1, Int((Double(image.width) * factor).rounded()))
        let height = max(1, Int((Double(image.height) * factor).rounded()))
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
            return image
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }

    private static func pieces(from request: VNRecognizeTextRequest) -> [TextPiece] {
        (request.results ?? []).compactMap { observation -> TextPiece? in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            return TextPiece(text: text, box: observation.boundingBox)
        }
    }

}
