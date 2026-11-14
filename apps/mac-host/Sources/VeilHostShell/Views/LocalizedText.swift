import SwiftUI

extension Text {
    /// Shows a string computed at runtime through the app's Localizable.strings, the way a string
    /// literal in `Text("...")` already is. Strings without a translation show unchanged.
    init(localized key: String) {
        self.init(LocalizedStringKey(key))
    }
}
