import AppKit
import Testing
@testable import Kept
import KeptCore

@MainActor
@Suite("Capture service")
struct CaptureServiceTests {
    @Test("Records a copy, and the same copy again as one clip")
    func recordsCopies() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let store = try HistoryStore(directory: directory)
        let service = CaptureService(pasteboard: pasteboard, store: store, settings: { CaptureSettings() })

        pasteboard.simulateCopy("Meeting notes for Thursday", markers: [.source])
        service.captureCurrentContents()
        await service.waitUntilIdle()
        #expect(store.recent.map(\.title) == ["Meeting notes for Thursday"])
        #expect(store.recent.first?.sourceBundleID == "com.apple.TextEdit")

        pasteboard.simulateCopy("Meeting notes for Thursday")
        service.captureCurrentContents()
        await service.waitUntilIdle()
        #expect(store.recent.count == 1)
        #expect(store.recent.first?.copyCount == 2)
    }

    @Test("Concealed copies never reach the history")
    func skipsConcealed() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let store = try HistoryStore(directory: directory)
        let service = CaptureService(pasteboard: pasteboard, store: store, settings: { CaptureSettings() })

        pasteboard.simulateCopy("hunter2", markers: [.concealed])
        service.captureCurrentContents()
        await service.waitUntilIdle()
        #expect(store.recent.isEmpty)
    }

    @Test("A TIFF screenshot is stored as PNG with its size")
    func storesTIFFAsPNG() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let store = try HistoryStore(directory: directory)
        let service = CaptureService(pasteboard: pasteboard, store: store, settings: { CaptureSettings() })

        pasteboard.clearContents()
        pasteboard.setData(try encodedImage(width: 30, height: 20, type: "public.tiff"), forType: .tiff)
        service.captureCurrentContents()
        await service.waitUntilIdle()

        let clip = try #require(store.recent.first)
        #expect(clip.kind == .image)
        #expect(clip.title == "Image 30 × 20")
        #expect(clip.metadata.imageType == .png)
        let types = try store.representations(for: clip.id).flatMap(\.types)
        #expect(types == [.png])
    }
}
