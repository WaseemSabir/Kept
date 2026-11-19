import Foundation
import Testing
@testable import Kept
import KeptCore

@Suite("Clip accessibility")
struct ClipAccessibilityTests {
    private func clip(
        _ kind: ClipKind,
        _ title: String,
        pinned: Bool = false,
        metadata: ClipMetadata = ClipMetadata()
    ) -> Clip {
        Clip(
            kind: kind, title: title, searchText: title, contentHash: title,
            sourceBundleID: "com.apple.Safari", firstCopiedAt: .at(0), lastCopiedAt: .at(0),
            pinOrder: pinned ? 0 : nil, byteSize: 10, metadata: metadata
        )
    }

    @Test("Says the kind in words, which the list only draws")
    func kinds() {
        #expect(ClipAccessibility.kind(of: clip(.text, "Hello")) == "Text")
        #expect(ClipAccessibility.kind(of: clip(.text, "func a()", metadata: ClipMetadata(looksLikeCode: true))) == "Code")
        #expect(ClipAccessibility.kind(of: clip(.richText, "Hello")) == "Formatted text")
        #expect(ClipAccessibility.kind(of: clip(.link, "https://example.com")) == "Link")
        #expect(ClipAccessibility.kind(of: clip(.image, "Image 1440 × 900")) == "Image")
        #expect(ClipAccessibility.kind(of: clip(.file, "a.pdf")) == "File")
        #expect(ClipAccessibility.kind(of: clip(.file, "a.pdf, b.pdf", metadata: ClipMetadata(fileCount: 2))) == "2 files")
        #expect(ClipAccessibility.kind(of: clip(.color, "#FF6A00")) == "Color")
    }

    @Test("A row reads kind, text, age, source and pin")
    func label() {
        let link = clip(.link, "https://github.com/kept", pinned: true)
        #expect(
            ClipAccessibility.label(for: link, appName: "Safari", now: .at(9 * 60))
                == "Link, https://github.com/kept, 9 minutes ago, from Safari, pinned"
        )
        let image = clip(.image, "Image 1440 × 900")
        #expect(ClipAccessibility.label(for: image, appName: nil, now: .at(30)) == "Image, 1440 × 900, Just now")
    }

    @Test("The announcement adds the clip's place in the list")
    func announcement() {
        let text = clip(.text, "Meeting notes")
        #expect(
            ClipAccessibility.announcement(for: text, position: 4, of: 15, appName: "Notes", now: .at(120))
                == "Text, Meeting notes, 2 minutes ago, from Notes. 4 of 15."
        )
    }

    @Test("Long titles are cut to a sentence")
    func longTitles() {
        let long = clip(.text, String(repeating: "word ", count: 100))
        let title = ClipAccessibility.spokenTitle(of: long)
        #expect(title.count == ClipAccessibility.maxSpokenTitleCharacters + 1)
        #expect(title.hasSuffix("…"))
    }
}
