import Carbon
import Foundation

/// A keyboard layout's `uchr` data, asked with `UCKeyTranslate` what each
/// key types.
struct UnicodeKeyLayout: KeyTranslating {
    private static let maxLength = 4

    let layoutData: Data
    /// `LMGetKbdType()`: ANSI, ISO or JIS, which changes a few keys.
    let keyboardType: UInt32

    /// `nil` for input sources without Unicode layout data (some input
    /// methods).
    init?(source: TISInputSource, keyboardType: UInt32) {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        guard !data.isEmpty else { return nil }
        layoutData = data
        self.keyboardType = keyboardType
    }

    func characters(forKeyCode keyCode: UInt16, withCommand: Bool) -> String? {
        let keyboardType = keyboardType
        return layoutData.withUnsafeBytes { buffer -> String? in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
                return nil
            }
            // UCKeyTranslate takes the Carbon modifier bits shifted down a byte.
            let modifiers: UInt32 = withCommand ? UInt32((cmdKey >> 8) & 0xFF) : 0
            var deadKeyState: UInt32 = 0
            var length = 0
            var characters = [UniChar](repeating: 0, count: Self.maxLength)
            let status = UCKeyTranslate(
                layout,
                keyCode,
                UInt16(kUCKeyActionDisplay),
                modifiers,
                keyboardType,
                OptionBits(kUCKeyTranslateNoDeadKeysMask),
                &deadKeyState,
                Self.maxLength,
                &length,
                &characters
            )
            guard status == OSStatus(noErr), length > 0 else { return nil }
            return String(utf16CodeUnits: characters, count: length)
        }
    }
}
