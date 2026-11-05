import SwiftUI
import RectoCore

/// Where the fold is, in the reader's own coordinates.
///
/// On the iPhone Duo this must come from the system's reserved-regions API (see the brief's
/// "Building notes"). That API is not wired yet: wire it in `systemFold` once it can be checked
/// against the Xcode 27.1 Duo simulator. Until then the Debug menu can pretend a fold, so every
/// layout can be tried in any simulator, and two pages still show whenever the window is wide.
enum FoldOverride: String, CaseIterable, Identifiable {
    case system = "From the system"
    case none = "No fold"
    case upright = "Fold down the middle (open flat, book)"
    case across = "Fold across (laptop, held tall)"
    var id: String { rawValue }
}

enum Fold {
    static let creaseWidth: CGFloat = 16

    static func fold(in size: CGSize, override: FoldOverride) -> CGRect? {
        switch override {
        case .system: return systemFold(in: size)
        case .none: return nil
        case .upright:
            return CGRect(x: size.width / 2 - creaseWidth / 2, y: 0, width: creaseWidth, height: size.height)
        case .across:
            return CGRect(x: 0, y: size.height / 2 - creaseWidth / 2, width: size.width, height: creaseWidth)
        }
    }

    /// TODO(week 1, on a Mac): read the fold from the system's reserved regions on iPhone Duo.
    static func systemFold(in size: CGSize) -> CGRect? { nil }
}
