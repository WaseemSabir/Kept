import Testing
import KeptCore

@Test("Version is major.minor.patch")
func versionIsSemantic() {
    let parts = KeptVersion.current.split(separator: ".", omittingEmptySubsequences: false)
    #expect(parts.count == 3)
    #expect(parts.allSatisfy { Int($0) != nil })
}
