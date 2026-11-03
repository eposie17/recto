import Foundation
import CoreGraphics

public enum TouchKind: Sendable { case pencil, finger }

public enum TouchDecision: Equatable, Sendable { case ink, scroll, ignore }

/// Who gets a one-finger or Pencil touch.
public enum InputRules {
    /// Finger strokes that start this close to the screen's outer edges are ignored in write mode,
    /// because that is where the phone is held.
    public static let gripEdge: CGFloat = 20

    public static func decide(kind: TouchKind, start: CGPoint, writeMode: Bool,
                              environment env: WindowEnvironment) -> TouchDecision {
        // A Pencil always inks, from its very first stroke, on the paper and the notes.
        if kind == .pencil { return .ink }
        guard writeMode else { return .scroll }
        let s = env.screen
        // Only the screen's real edges count. The fold is screen like any other and takes ink.
        let nearEdge = start.x - s.minX < gripEdge || s.maxX - start.x < gripEdge
            || start.y - s.minY < gripEdge || s.maxY - start.y < gripEdge
        return nearEdge ? .ignore : .ink
    }
}
