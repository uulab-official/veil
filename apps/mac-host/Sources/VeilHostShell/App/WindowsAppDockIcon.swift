import AppKit

/// The icon a mirrored Windows app shows on the Mac: the app's own icon with a small Veil badge in the corner,
/// the way Parallels marks the Windows apps it runs. Used for the Dock and the app switcher while that app's
/// window is in front, and for its minimized window in the Dock.
@MainActor
enum WindowsAppDockIcon {
    static let canvasSize = NSSize(width: 512, height: 512)
    /// The badge covers the lower-right corner, large enough to read at Dock size without hiding the app.
    static let badgeFraction: CGFloat = 0.42

    private static var cache: [String: NSImage] = [:]

    /// Veil's own icon, read from the bundle rather than `NSApp.applicationIconImage`, which this type replaces.
    static let veilIcon: NSImage = {
        if let url = Bundle.main.url(forResource: "VeilAppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: url) {
            return icon
        }
        return NSImage(systemSymbolName: "macwindow.on.rectangle", accessibilityDescription: "Veil")
            ?? NSImage(size: canvasSize)
    }()

    /// Nil when Windows did not send an icon for the app; callers then keep Veil's icon.
    static func image(for identity: WindowsAppWindowIdentity) -> NSImage? {
        if let cached = cache[identity.appId] {
            return cached
        }
        guard let data = identity.iconData,
              let appIcon = NSImage(data: data) else {
            return nil
        }

        let image = compose(appIcon: appIcon, badge: veilIcon)
        image.accessibilityDescription = identity.appName
        cache[identity.appId] = image
        return image
    }

    static func compose(appIcon: NSImage, badge: NSImage) -> NSImage {
        NSImage(size: canvasSize, flipped: false) { rect in
            // Windows icons carry their own padding, so the app icon fills the canvas the way a Mac app icon
            // would, inset only enough to leave the badge some overlap room.
            let appRect = rect.insetBy(dx: rect.width * 0.06, dy: rect.height * 0.06)
            NSGraphicsContext.current?.imageInterpolation = .high
            appIcon.draw(in: appRect, from: .zero, operation: .sourceOver, fraction: 1)

            let side = rect.width * badgeFraction
            let badgeRect = NSRect(x: rect.maxX - side, y: rect.minY, width: side, height: side)
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowBlurRadius = side * 0.08
            shadow.shadowOffset = NSSize(width: 0, height: -side * 0.03)
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
            shadow.set()
            badge.draw(in: badgeRect, from: .zero, operation: .sourceOver, fraction: 1)
            NSGraphicsContext.restoreGraphicsState()
            return true
        }
    }

    /// Shows the frontmost Windows app in the Dock and the app switcher, or Veil when `identity` is nil.
    static func showInDock(_ identity: WindowsAppWindowIdentity?) {
        let image = identity.flatMap(image(for:)) ?? veilIcon
        guard NSApp.applicationIconImage !== image else {
            return
        }
        NSApp.applicationIconImage = image
    }
}
