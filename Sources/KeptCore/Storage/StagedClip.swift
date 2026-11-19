/// A draft whose blob files are written and reserved (`ClipStager`), ready
/// for `HistoryStore.record(_:at:)`.
///
/// Hand one that won't be recorded (capture paused, history cleared…), or
/// the part a failed staging wrote (`ClipStager.Failure.written`), to
/// `HistoryStore.discard(_:)`, which deletes its files at once. One that's
/// simply dropped releases its reservation when the last copy goes away,
/// and its files are swept at the next launch.
public struct StagedClip: Sendable {
    public let draft: ClipDraft
    /// The blob files written for the draft.
    let blobHashes: Set<String>
    let reservation: BlobReservations.Reservation
}
