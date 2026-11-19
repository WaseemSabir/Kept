import AppKit
import SwiftUI

/// The preview's text editor (⌘E): a plain-text `NSTextView` that takes
/// the keyboard as soon as it's on screen.
///
/// AppKit's text view rather than SwiftUI's `TextEditor`, so Kept decides
/// what typing does: no smart quotes or dashes, text replacements,
/// autocorrection or link detection (code and URLs must stay as typed),
/// plain text only, and undo. Spelling is checked for prose, not code.
struct ClipTextEditor: NSViewRepresentable {
    @Binding var text: String
    /// Set in SF Mono, as the preview sets code, links and colors.
    let isCode: Bool
    /// The editor lost the keyboard (a click in the search field, say).
    var onResign: @MainActor () -> Void = {}

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onResign: onResign)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let textView = EditorTextView(frame: .zero)
        let coordinator = context.coordinator
        textView.delegate = coordinator
        textView.onResign = { [weak coordinator] in coordinator?.onResign() }
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.isContinuousSpellCheckingEnabled = !isCode
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = NSSize(width: Theme.Layout.editorInset, height: Theme.Layout.editorInset)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.setAccessibilityLabel("Clip text")

        let attributes = Self.attributes(isCode: isCode)
        textView.typingAttributes = attributes
        textView.string = text
        textView.textStorage?.setAttributes(attributes, range: NSRange(location: 0, length: (text as NSString).length))
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.text = $text
        context.coordinator.onResign = onResign
        guard let textView = scrollView.documentView as? NSTextView,
              !textView.hasMarkedText(), textView.string != text
        else { return }
        textView.string = text
        textView.textStorage?.setAttributes(
            Self.attributes(isCode: isCode),
            range: NSRange(location: 0, length: (text as NSString).length)
        )
    }

    /// The preview's type: 13 pt SF Pro for prose, 12 pt SF Mono for code,
    /// with its line spacing, in the label color.
    private static func attributes(isCode: Bool) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = isCode ? 3 : 2
        return [
            .font: isCode ? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular) : NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph,
        ]
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var onResign: @MainActor () -> Void

        init(text: Binding<String>, onResign: @escaping @MainActor () -> Void) {
            self.text = text
            self.onResign = onResign
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}

/// Takes the keyboard once it's in a window, and says when it loses it.
private final class EditorTextView: NSTextView {
    var onResign: (@MainActor () -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        window.makeFirstResponder(self)
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned, window != nil {
            // Once AppKit has moved the keyboard on.
            Task { @MainActor [weak self] in self?.onResign?() }
        }
        return resigned
    }
}
