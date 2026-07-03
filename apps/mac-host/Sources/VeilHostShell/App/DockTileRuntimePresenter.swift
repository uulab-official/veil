import AppKit
import VeilHostCore

@MainActor
enum DockTileRuntimePresenter {
    static func update(_ dockIntegration: WindowsAppRuntimeDockIntegrationStatus) {
        guard dockIntegration.isEnabled else {
            NSApp.dockTile.badgeLabel = nil
            NSApp.dockTile.display()
            return
        }

        NSApp.dockTile.badgeLabel = dockIntegration.badgeLabel
        NSApp.dockTile.display()
    }
}
