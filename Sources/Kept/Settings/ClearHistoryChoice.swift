/// What clearing the history from Settings removes.
enum ClearHistoryChoice: Equatable, Sendable {
    /// Unpinned clips; pins stay.
    case unpinned
    /// Every clip, pins too.
    case everything
}
