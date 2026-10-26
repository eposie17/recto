import Foundation

/// One user action: a stroke added, an eraser pass that took off strokes and highlights, and so on.
/// Undo undoes the last action, not the last stroke.
public struct Edit<Item: Sendable>: Sendable {
    public var added: [Item]
    public var removed: [Item]

    public init(added: [Item] = [], removed: [Item] = []) { self.added = added; self.removed = removed }

    public var inverted: Edit { Edit(added: removed, removed: added) }
    public var isEmpty: Bool { added.isEmpty && removed.isEmpty }
}

/// Undo and redo for one surface. Each paper and each notebook keeps its own.
public struct History<Item: Sendable>: Sendable {
    private var done: [Edit<Item>] = []
    private var undone: [Edit<Item>] = []
    public let limit: Int

    public init(limit: Int = 200) { self.limit = limit }

    public var canUndo: Bool { !done.isEmpty }
    public var canRedo: Bool { !undone.isEmpty }

    public mutating func record(_ edit: Edit<Item>) {
        guard !edit.isEmpty else { return }
        done.append(edit)
        if done.count > limit { done.removeFirst(done.count - limit) }
        undone.removeAll()
    }

    /// Returns the edit to apply to take the last action back.
    public mutating func undo() -> Edit<Item>? {
        guard let e = done.popLast() else { return nil }
        undone.append(e)
        return e.inverted
    }

    /// Returns the edit to apply to bring the last undone action back.
    public mutating func redo() -> Edit<Item>? {
        guard let e = undone.popLast() else { return nil }
        done.append(e)
        return e
    }
}

extension PaperMarks {
    public mutating func apply(_ edit: Edit<Mark>) {
        for m in edit.removed { remove(id: m.id) }
        for m in edit.added { insert(m) }
    }
}
