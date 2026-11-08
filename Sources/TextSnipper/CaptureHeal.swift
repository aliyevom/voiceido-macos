import AppKit
import Foundation
import os

/// Sends the capture to a fast vision model and returns a tighter transcription.
/// A missing key or a bad reply leaves the local text in place.
enum CaptureHeal {
    private static let endpoint = URL(string: "https://fal.run/fal-ai/any-llm/vision")!
    /// Flash reads letters and symbols more reliably than Flash-Lite, and stays on the latency path.
    private static let pageModel = "google/gemini-2.5-flash"
    private static let logger = Logger(subsystem: "local.aliyevom.TextSnipper", category: "heal")
    private static let systemPrompt = """
    Transcribe the screenshot for a text or code assessment. Output only the visible characters. \
    Copy English letters, digits, and symbols exactly as drawn, including O and 0, I and l and 1, S and 5, \
    quotes, brackets, slashes, percent signs, pipes, dashes, and operators such as -> and =>. \
    Keep line breaks and indentation spaces. Read the left column from top to bottom, then the next column. \
    Join a URL that wraps on screen into one line. Do not translate, fix spelling, add markdown, or describe the image.
    """

    /// Starts from the image alone so it can run while local OCR is still reading.
    static func transcribe(image: CGImage) async -> String? {
        guard let jpeg = jpegData(from: image, quality: 0.9) else { return nil }
        return await complete(
            model: pageModel,
            system: systemPrompt,
            prompt: "Transcribe every visible character.",
            jpeg: jpeg,
            maxTokens: 4096
        )
    }

    static func repair(draft: String, image: CGImage) async -> String? {
        guard let output = await transcribe(image: image) else { return nil }
        guard let accepted = accept(output, draft: draft) else {
            logger.error("Auto-heal discarded the reply")
            return nil
        }
        return accepted
    }

    private static func complete(model: String, system: String, prompt: String, jpeg: Data, maxTokens: Int) async -> String? {
        guard let key = FalKey.load() else {
            logger.error("Auto-heal skipped: no fal key")
            return nil
        }
        let body: [String: Any] = [
            "model": model,
            "priority": "latency",
            "temperature": 0,
            "max_tokens": maxTokens,
            "reasoning": false,
            "system_prompt": system,
            "prompt": prompt,
            "image_urls": ["data:image/jpeg;base64,\(jpeg.base64EncodedString())"],
        ]
        guard let payload = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        var request = URLRequest(url: endpoint, timeoutInterval: 12)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Key \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = payload
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else {
                logger.error("Auto-heal failed: HTTP \(status)")
                return nil
            }
            let decoded = try JSONDecoder().decode(FalVisionResponse.self, from: data)
            guard decoded.error == nil, let output = decoded.output else { return nil }
            NotificationCenter.default.post(name: .textSnipperSpentFalCredit, object: nil)
            return output
        } catch {
            logger.error("Auto-heal failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Rejects commentary and replies that barely resemble the capture.
    static func accept(_ output: String, draft: String) -> String? {
        let text = stripFences(output)
        if text.isEmpty || text == "SKIP" { return nil }
        let lowered = text.lowercased()
        if lowered.hasPrefix("here is") || lowered.hasPrefix("the text") || lowered.hasPrefix("sure,") {
            return nil
        }
        let ratio = Double(text.count) / Double(max(draft.count, 1))
        guard ratio >= 0.4, ratio <= 3 else { return nil }
        return text
    }

    private static func stripFences(_ output: String) -> String {
        var lines = output.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        if lines.first?.hasPrefix("```") == true {
            lines.removeFirst()
        }
        if lines.last?.trimmingCharacters(in: .whitespaces) == "```" {
            lines.removeLast()
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func jpegData(from image: CGImage, quality: CGFloat) -> Data? {
        let longest = max(image.width, image.height, 1)
        let scale = min(1, 1920.0 / Double(longest))
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))
        let rendered: CGImage
        if scale < 0.999 {
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
                return nil
            }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            guard let scaled = context.makeImage() else { return nil }
            rendered = scaled
        } else {
            rendered = image
        }
        let rep = NSBitmapImageRep(cgImage: rendered)
        return rep.representation(using: .jpeg, properties: [.compressionFactor: quality])
    }
}

private struct FalVisionResponse: Decodable {
    var output: String?
    var error: String?
}

enum FalKey {
    static func load() -> String? {
        read("fal.key")
    }

    /// A billing or read-only key can live beside the inference key.
    static func loadBilling() -> String? {
        read("fal-billing.key") ?? read("fal.key")
    }

    private static func read(_ name: String) -> String? {
        let url = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TextSnipper/\(name)")
        guard let data = try? Data(contentsOf: url),
              let key = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              key.contains(":") else {
            return nil
        }
        return key
    }
}

extension Notification.Name {
    static let textSnipperSpentFalCredit = Notification.Name("textSnipperSpentFalCredit")
}
