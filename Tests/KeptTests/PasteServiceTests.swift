import AppKit
import Testing
@testable import Kept
import KeptCore

@MainActor
@Suite("Paste service")
struct PasteServiceTests {
    /// A paste service on a private pasteboard and a temporary history,
    /// with every system dependency faked.
    @MainActor
    private final class Harness {
        let directory: URL
        let suiteName: String
        let defaults: UserDefaults
        let pasteboard: NSPasteboard
        let store: HistoryStore
        let monitor: PasteboardMonitor
        let permission = FakePermission()
        let poster = RecordingPoster()
        let focus = FakeFocus()
        let hints = RecordingHints()
        var options = PasteOptions()
        private(set) var captured: [Int] = []
        private(set) lazy var service = makeService()

        init(texts: [String] = ["newest", "older"]) throws {
            let directory = try makeTemporaryDirectory()
            let suiteName = "app.kept.tests.\(UUID().uuidString)"
            let pasteboard = makePasteboard()
            self.directory = directory
            self.suiteName = suiteName
            self.pasteboard = pasteboard
            defaults = try #require(UserDefaults(suiteName: suiteName))
            store = try makeStore(in: directory, texts: texts)
            monitor = PasteboardMonitor(pasteboard: pasteboard, isPaused: { false })
            monitor.onChange = { [weak self] in self?.captured.append($0) }
        }

        /// A fresh service over the same defaults, as after a relaunch.
        func makeService() -> PasteService {
            PasteService(
                store: store,
                writer: PasteboardWriter(pasteboard: pasteboard),
                monitor: monitor,
                options: { [weak self] in self?.options ?? PasteOptions() },
                permission: permission,
                poster: poster,
                focus: focus,
                onboarding: PasteOnboarding(defaults: defaults),
                hints: hints
            )
        }

        func tearDown() {
            pasteboard.releaseGlobally()
            defaults.removePersistentDomain(forName: suiteName)
            removeTemporaryDirectory(directory)
        }

        /// Pastes `clip` the way the panel does: prepare, then complete.
        @discardableResult
        func paste(_ clip: Clip, _ request: PasteRequest = .paste(alternate: false)) throws -> PastePlan {
            let plan = try service.prepare(clip, for: request)
            service.complete(plan, anchor: CGRect(x: 10, y: 20, width: 720, height: 460))
            return plan
        }

        func clip(_ title: String) throws -> Clip {
            try #require((store.pinned + store.recent).first { $0.title == title })
        }
    }

    @Test("With permission: writes the clip, skips it in the monitor, moves it up and posts ⌘V once")
    func pastesWithPermission() throws {
        let harness = try Harness()
        defer { harness.tearDown() }

        try harness.paste(try harness.clip("older"))
        #expect(harness.pasteboard.string(forType: .string) == "older")
        // Kept never records its own write.
        #expect(harness.monitor.poll() == .ownWrite)
        #expect(harness.captured.isEmpty)
        #expect(harness.store.recent.map(\.title) == ["older", "newest"])
        #expect(harness.poster.posts == 1)
        #expect(harness.hints.shown.isEmpty)
        #expect(harness.permission.requests == 0)
    }

    @Test("Without permission: copies, asks macOS once, explains once, then only says press ⌘V")
    func firstTimeWithoutPermission() throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        harness.permission.canPostEvents = false

        let first = try harness.paste(try harness.clip("older"))
        #expect(first.requestsAccess)
        #expect(harness.pasteboard.string(forType: .string) == "older")
        #expect(harness.poster.posts == 0)
        #expect(harness.permission.requests == 1)
        #expect(harness.hints.shown.map(\.hint) == [.allowPasting])
        #expect(harness.hints.shown.first?.anchor == CGRect(x: 10, y: 20, width: 720, height: 460))

        try harness.paste(try harness.clip("newest"))
        #expect(harness.permission.requests == 1)
        #expect(harness.hints.shown.map(\.hint) == [.allowPasting, .pressCommandV])

        // Remembered across launches.
        let onboarding = PasteOnboarding(defaults: harness.defaults)
        #expect(onboarding.hasRequestedAccess)
        #expect(onboarding.hasShownPermissionHint)
        let relaunched = harness.makeService()
        let plan = try relaunched.prepare(try harness.clip("older"), for: .paste(alternate: false))
        #expect(plan == .copy(plainText: false, hint: .pressCommandV))

        // Once granted, pasting just works.
        harness.permission.canPostEvents = true
        try harness.paste(try harness.clip("newest"))
        #expect(harness.poster.posts == 1)
        #expect(harness.hints.shown.count == 2)
        #expect(harness.monitor.poll() == .ownWrite)
    }

    @Test("Copy only (⌘⏎) and paste directly off never post, ask or hint")
    func copyOnly() throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        harness.permission.canPostEvents = false

        try harness.paste(try harness.clip("older"), .copyOnly)
        harness.options.pasteDirectly = false
        try harness.paste(try harness.clip("newest"))
        #expect(harness.pasteboard.string(forType: .string) == "newest")
        #expect(harness.poster.posts == 0)
        #expect(harness.permission.requests == 0)
        #expect(harness.hints.shown.isEmpty)
    }

    @Test("Kept frontmost or secure input: copy and say press ⌘V")
    func focusProblems() throws {
        let harness = try Harness()
        defer { harness.tearDown() }

        harness.focus.isKeptFrontmost = true
        try harness.paste(try harness.clip("older"))
        harness.focus.isKeptFrontmost = false
        harness.focus.isSecureInputEnabled = true
        try harness.paste(try harness.clip("newest"))
        #expect(harness.poster.posts == 0)
        #expect(harness.permission.requests == 0)
        #expect(harness.hints.shown.map(\.hint) == [.pressCommandV, .pressCommandV])
    }

    @Test("⌥⏎ writes plain text; always paste plain text swaps it")
    func formats() throws {
        let harness = try Harness(texts: [])
        defer { harness.tearDown() }
        let rtf = #"{\rtf1\ansi Hello, \b world\b0}"#
        let snapshot = PasteboardSnapshot(
            items: [PasteboardItem([ClipRepresentation(.rtf, string: rtf), ClipRepresentation(.string, string: "Hello, world")])],
            sourceBundleID: "com.apple.TextEdit"
        )
        let draft = try #require(ClipBuilder().build(from: snapshot))
        let clip = try harness.store.record(draft)

        try harness.paste(clip, .paste(alternate: true))
        #expect(harness.pasteboard.data(forType: .rtf) == nil)
        #expect(harness.pasteboard.string(forType: .string) == "Hello, world")

        try harness.paste(clip, .paste(alternate: false))
        #expect(harness.pasteboard.data(forType: .rtf) != nil)

        harness.options.alwaysPastePlainText = true
        try harness.paste(clip, .paste(alternate: false))
        #expect(harness.pasteboard.data(forType: .rtf) == nil)
        try harness.paste(clip, .paste(alternate: true))
        #expect(harness.pasteboard.data(forType: .rtf) != nil)
    }

    // MARK: Paste clipboard as plain text

    @Test("The plain-text shortcut records a pending copy, rewrites it as plain text and pastes")
    func clipboardAsPlainText() throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        let copied = harness.pasteboard.simulateRichCopy("Hello, world", markers: [.concealed])

        let plan = try #require(harness.service.pasteClipboardAsPlainText())
        #expect(plan == .paste(plainText: true))
        // The copy was seen before it was replaced.
        #expect(harness.captured == [copied])
        #expect(harness.pasteboard.data(forType: .rtf) == nil)
        #expect(harness.pasteboard.string(forType: .string) == "Hello, world")
        // Still marked secret for other clipboard managers, and Kept's own.
        let types = Set((harness.pasteboard.types ?? []).map(\.rawValue))
        #expect(types.contains(PasteboardType.concealed.rawValue))
        #expect(types.contains(PasteboardType.keptOwn.rawValue))
        #expect(harness.pasteboard.string(forType: NSPasteboard.PasteboardType(PasteboardType.source.rawValue)) == "com.apple.TextEdit")
        #expect(harness.monitor.poll() == .ownWrite)
        #expect(harness.poster.posts == 1)
    }

    @Test("The plain-text shortcut follows the same permission rules")
    func clipboardAsPlainTextWithoutPermission() throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        harness.permission.canPostEvents = false
        harness.pasteboard.simulateRichCopy("Hello, world")

        let plan = try #require(harness.service.pasteClipboardAsPlainText())
        #expect(plan == .copy(plainText: true, hint: .allowPasting, requestsAccess: true))
        #expect(harness.pasteboard.string(forType: .string) == "Hello, world")
        #expect(harness.poster.posts == 0)
        #expect(harness.hints.shown.count == 1)
        #expect(harness.hints.shown.first?.anchor == nil)
    }

    @Test("The plain-text shortcut leaves a clipboard without text alone")
    func clipboardWithoutText() throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        harness.pasteboard.clearContents()
        harness.pasteboard.setData(Data([0x89, 0x50, 0x4E, 0x47]), forType: .png)
        let changeCount = harness.pasteboard.changeCount

        #expect(harness.service.pasteClipboardAsPlainText() == nil)
        #expect(harness.pasteboard.changeCount == changeCount)
        #expect(harness.poster.posts == 0)
        #expect(harness.hints.shown.isEmpty)
    }
}

// MARK: Fakes

@MainActor
private final class FakePermission: PermissionChecking {
    var canPostEvents = true
    private(set) var requests = 0
    private(set) var settingsOpened = 0

    func requestAccess() { requests += 1 }
    func openSettings() { settingsOpened += 1 }
}

@MainActor
private final class RecordingPoster: KeystrokePosting {
    private(set) var posts = 0

    func postPasteShortcut() { posts += 1 }
}

@MainActor
private final class FakeFocus: KeyboardFocusChecking {
    var isKeptFrontmost = false
    var isSecureInputEnabled = false
}

@MainActor
private final class RecordingHints: PasteHintPresenting {
    struct Shown {
        let hint: PastePlan.Hint
        let anchor: CGRect?
    }

    private(set) var shown: [Shown] = []

    func show(_ hint: PastePlan.Hint, anchor: CGRect?) {
        shown.append(Shown(hint: hint, anchor: anchor))
    }
}

private extension NSPasteboard {
    /// Another app's rich-text copy (RTF and its plain text) from TextEdit,
    /// with optional marker types. Returns the new change count.
    @discardableResult
    func simulateRichCopy(_ string: String, markers: [KeptCore.PasteboardType] = []) -> Int {
        clearContents()
        let item = NSPasteboardItem()
        item.setData(Data(#"{\rtf1\ansi Hello, \b world\b0}"#.utf8), forType: .rtf)
        item.setString(string, forType: .string)
        item.setString("com.apple.TextEdit", forType: NSPasteboard.PasteboardType(KeptCore.PasteboardType.source.rawValue))
        for marker in markers {
            item.setString("1", forType: NSPasteboard.PasteboardType(marker.rawValue))
        }
        writeObjects([item])
        return changeCount
    }
}
