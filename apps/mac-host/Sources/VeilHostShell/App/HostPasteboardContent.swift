import AppKit
import VeilHostCore

/// What a ⌘V in a mirrored Windows window should carry to the guest clipboard.
enum HostPasteboardContent: Equatable {
    case text(String)
    case image(png: Data)
    case files([URL])

    /// Reads the one representation that will be sent.
    ///
    /// The source app's own type order decides, because it lists its richest representation first: Finder
    /// puts file URLs before the names-as-text it also writes, and a browser's Copy Image puts the bitmap
    /// before the address. Taking text whenever it exists would paste "report.pdf" for a copied file.
    /// Returns nil when nothing on the pasteboard can be sent, so the shortcut falls through to a plain
    /// Ctrl+V of Windows' own clipboard.
    static func read(from pasteboard: NSPasteboard, includeFiles: Bool) -> HostPasteboardContent? {
        for type in pasteboard.types ?? [] {
            switch type {
            case .fileURL where includeFiles:
                let urls = pasteboard.readObjects(
                    forClasses: [NSURL.self],
                    options: [.urlReadingFileURLsOnly: true]
                ) as? [URL] ?? []
                if !urls.isEmpty {
                    return .files(urls)
                }
            case .string:
                if let text = pasteboard.string(forType: .string) {
                    return .text(text)
                }
            case .png:
                if let png = pasteboard.data(forType: .png) {
                    return .image(png: png)
                }
            case .tiff:
                if let tiff = pasteboard.data(forType: .tiff),
                   let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                    return .image(png: png)
                }
            default:
                continue
            }
        }

        return nil
    }

    /// Writes a verified guest image as both PNG and TIFF. Many Mac apps still read only TIFF, so a PNG-only
    /// pasteboard would paste nothing into them.
    static func writeImage(_ payload: ClipboardImagePayload, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        var types: [NSPasteboard.PasteboardType] = [.png]
        let tiff = NSBitmapImageRep(data: payload.png)?.tiffRepresentation
        if tiff != nil {
            types.append(.tiff)
        }
        pasteboard.declareTypes(types, owner: nil)
        pasteboard.setData(payload.png, forType: .png)
        if let tiff {
            pasteboard.setData(tiff, forType: .tiff)
        }
    }
}
