import CoreGraphics
import Foundation

public struct TextPiece: Equatable {
    public let text: String
    public let box: CGRect

    public init(text: String, box: CGRect) {
        self.text = text
        self.box = box
    }
}

public enum TextAssembly {
    /// Reads Vision boxes (origin at the bottom-left, y upward) from top to bottom.
    /// Words that overlap vertically stay on one line, left to right.
    public static func assemble(
        _ pieces: [TextPiece],
        keepLineBreaks: Bool,
        preserveColumns: Bool = false
    ) -> String {
        let cleaned = pieces.filter {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !cleaned.isEmpty else { return "" }

        let columns = columnGroups(cleaned)
        if columns.count > 1 {
            let parts = columns.map {
                assembleFlow($0, keepLineBreaks: true, preserveColumns: preserveColumns)
            }
            return keepLineBreaks ? parts.joined(separator: "\n\n") : parts.joined(separator: " ")
        }
        return assembleFlow(cleaned, keepLineBreaks: keepLineBreaks, preserveColumns: preserveColumns)
    }

    private static func assembleFlow(
        _ cleaned: [TextPiece],
        keepLineBreaks: Bool,
        preserveColumns: Bool
    ) -> String {
        let sorted = cleaned.sorted { lhs, rhs in
            if abs(lhs.box.midY - rhs.box.midY) > 0.000_1 {
                return lhs.box.midY > rhs.box.midY
            }
            return lhs.box.minX < rhs.box.minX
        }

        var lines: [[TextPiece]] = []
        for piece in sorted {
            if let index = lines.firstIndex(where: { line in
                line.contains { verticallyOverlaps($0.box, piece.box) }
            }) {
                lines[index].append(piece)
            } else {
                lines.append([piece])
            }
        }

        let rendered: [String]
        if preserveColumns && keepLineBreaks {
            let rows = lines.compactMap { line -> (text: String, box: CGRect)? in
                let ordered = line.sorted { $0.box.minX < $1.box.minX }
                let text = ordered
                    .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .joined(separator: " ")
                guard !text.isEmpty, let minX = ordered.map(\.box.minX).min(),
                      let maxX = ordered.map(\.box.maxX).max() else {
                    return nil
                }
                let box = CGRect(x: minX, y: ordered[0].box.minY, width: max(maxX - minX, 0.000_1), height: ordered[0].box.height)
                return (text, box)
            }
            rendered = indented(rows)
        } else {
            rendered = lines.map { line -> String in
                line.sorted { $0.box.minX < $1.box.minX }
                    .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .joined(separator: " ")
            }.filter { !$0.isEmpty }
        }

        if keepLineBreaks {
            return rendered.joined(separator: "\n")
        }
        return rendered.joined(separator: " ")
    }

    /// Splits a side-by-side page so the left block is read fully, then the right block.
    /// A wide gap between two words on one line is not treated as columns.
    private static func columnGroups(_ pieces: [TextPiece]) -> [[TextPiece]] {
        guard pieces.count >= 4 else { return [pieces] }
        let minX = pieces.map(\.box.minX).min() ?? 0
        let maxX = pieces.map(\.box.maxX).max() ?? 0
        let span = maxX - minX
        guard span > 0.25 else { return [pieces] }

        let binCount = 48
        var occupied = Array(repeating: 0, count: binCount)
        for piece in pieces {
            let start = binIndex(piece.box.minX, origin: minX, span: span, bins: binCount)
            let end = max(start, binIndex(piece.box.maxX, origin: minX, span: span, bins: binCount) - 1)
            if start <= end {
                for index in start...min(end, binCount - 1) {
                    occupied[index] += 1
                }
            }
        }

        var bestStart = 0
        var bestLength = 0
        var runStart: Int?
        for index in 0...binCount {
            let empty = index < binCount && occupied[index] == 0
            if empty {
                if runStart == nil { runStart = index }
            } else if let start = runStart {
                let length = index - start
                if length > bestLength, start > 2, index < binCount - 2 {
                    bestStart = start
                    bestLength = length
                }
                runStart = nil
            }
        }
        guard bestLength >= 4 else { return [pieces] }

        let gutterMin = minX + CGFloat(bestStart) / CGFloat(binCount) * span
        let gutterMax = minX + CGFloat(bestStart + bestLength) / CGFloat(binCount) * span
        let left = pieces.filter { $0.box.midX < gutterMin }
        let right = pieces.filter { $0.box.midX > gutterMax }
        let spansGutter = pieces.contains { $0.box.midX >= gutterMin && $0.box.midX <= gutterMax }
        guard !spansGutter, left.count >= 2, right.count >= 2 else { return [pieces] }
        guard rowCount(left) >= 2, rowCount(right) >= 2 else { return [pieces] }
        return [left, right]
    }

    private static func binIndex(_ value: CGFloat, origin: CGFloat, span: CGFloat, bins: Int) -> Int {
        let scaled = (value - origin) / span * CGFloat(bins)
        return min(max(Int(scaled.rounded(.down)), 0), bins)
    }

    private static func rowCount(_ pieces: [TextPiece]) -> Int {
        var rows: [CGFloat] = []
        for piece in pieces {
            if !rows.contains(where: { abs($0 - piece.box.midY) < 0.02 }) {
                rows.append(piece.box.midY)
            }
        }
        return rows.count
    }

    /// Restores leading spaces from how far each line sits to the right of the leftmost line.
    private static func indented(_ rows: [(text: String, box: CGRect)]) -> [String] {
        guard let left = rows.map(\.box.minX).min() else { return rows.map(\.text) }
        let widths = rows.compactMap { row -> CGFloat? in
            guard row.text.count >= 4, row.box.width > 0 else { return nil }
            return row.box.width / CGFloat(row.text.count)
        }
        guard let charWidth = median(widths), charWidth > 0.000_01 else {
            return rows.map(\.text)
        }
        return rows.map { row in
            let columns = Int(((row.box.minX - left) / charWidth).rounded())
            let clamped = min(max(columns, 0), 48)
            guard clamped > 0 else { return row.text }
            return String(repeating: " ", count: clamped) + row.text
        }
    }

    private static func median(_ values: [CGFloat]) -> CGFloat? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    private static func verticallyOverlaps(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        let overlap = min(lhs.maxY, rhs.maxY) - max(lhs.minY, rhs.minY)
        let basis = min(lhs.height, rhs.height)
        if basis <= 0.000_1 {
            return abs(lhs.midY - rhs.midY) < 0.01
        }
        return overlap > basis * 0.35
    }
}
