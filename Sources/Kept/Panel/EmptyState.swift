/// What the panel says when there's nothing to list, and what to do about it.
struct EmptyState: Equatable, Sendable {
    let title: String
    let hint: String?
    /// Whether the message takes the whole panel (nothing to preview, ever)
    /// rather than the list column.
    let spansPanel: Bool
}
