import AppKit
import Foundation

/// Screenshots kept until Command-Shift-0. Paste (Command-V) inserts every image in capture order.
@MainActor
enum ShotPool {
    private(set) static var count = 0

    private static var filenames: [String] = []
    private static var publishedChangeCount = -1
    private static let folderName = "TextSnipper/ShotPool"
    private static let manifestName = "order.json"

    static func restore() {
        let folder = directory()
        let manifest = folder.appendingPathComponent(manifestName)
        guard let data = try? Data(contentsOf: manifest),
              let names = try? JSONDecoder().decode([String].self, from: data) else {
            filenames = []
            count = 0
            return
        }
        filenames = names.filter { FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path) }
        count = filenames.count
        if count > 0 {
            publish()
        }
    }

    @discardableResult
    static func add(_ image: CGImage) throws -> Int {
        let folder = directory()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = "\(String(format: "%04d", filenames.count + 1))-\(UUID().uuidString).png"
        let url = folder.appendingPathComponent(name)
        guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw ShotPoolError.encodeFailed
        }
        try png.write(to: url, options: .atomic)
        filenames.append(name)
        count = filenames.count
        try saveManifest()
        publish()
        return count
    }

    static func reset() {
        let folder = directory()
        if FileManager.default.fileExists(atPath: folder.path) {
            try? FileManager.default.removeItem(at: folder)
        }
        filenames = []
        count = 0
        let pasteboard = NSPasteboard.general
        if pasteboard.changeCount == publishedChangeCount {
            pasteboard.clearContents()
        }
        publishedChangeCount = -1
    }

    private static func publish() {
        let folder = directory()
        let urls = filenames.map { folder.appendingPathComponent($0) }
        let paths = urls.map(\.path)
        let writers: [ShotWriter] = urls.enumerated().compactMap { index, url in
            ShotWriter(url: url, allPaths: index == 0 ? paths : nil)
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard !writers.isEmpty else { return }
        pasteboard.writeObjects(writers)
        publishedChangeCount = pasteboard.changeCount
    }

    private static func saveManifest() throws {
        let data = try JSONEncoder().encode(filenames)
        try data.write(to: directory().appendingPathComponent(manifestName), options: .atomic)
    }

    private static func directory() -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(folderName, isDirectory: true)
    }
}

extension Notification.Name {
    static let textSnipperShotPoolChanged = Notification.Name("textSnipperShotPoolChanged")
}

private enum ShotPoolError: LocalizedError {
    case encodeFailed

    var errorDescription: String? {
        "The screenshot could not be saved."
    }
}

/// One pool image, offered as PNG, TIFF, and a file so Command-V pastes a picture.
private final class ShotWriter: NSObject, NSPasteboardWriting {
    private let url: URL
    private let allPaths: [String]?
    private static let filenamesType = NSPasteboard.PasteboardType("NSFilenamesPboardType")

    init?(url: URL, allPaths: [String]?) {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        self.url = url
        self.allPaths = allPaths
    }

    func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        var types: [NSPasteboard.PasteboardType] = [.png, .tiff, .fileURL]
        if allPaths != nil {
            types.append(Self.filenamesType)
        }
        return types
    }

    func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        switch type {
        case .png:
            return try? Data(contentsOf: url)
        case .tiff:
            return NSImage(contentsOf: url)?.tiffRepresentation
        case .fileURL:
            return url.absoluteString
        case Self.filenamesType:
            return allPaths
        default:
            return nil
        }
    }
}
