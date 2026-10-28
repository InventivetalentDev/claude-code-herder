import XCTest

@testable import ClaudeHerder

final class InlineMarkdownTests: XCTestCase {
    func testStripsMarkersAndMarksCode() {
        let rendered = InlineMarkdown.render("`cow` shared **Rust** cache")

        XCTAssertEqual(String(rendered.characters), "cow shared Rust cache")
        let code = rendered.runs.filter { $0.inlinePresentationIntent?.contains(.code) == true }
        XCTAssertEqual(code.map { String(rendered[$0.range].characters) }, ["cow"])
        XCTAssertNotNil(code.first?.backgroundColor)
    }

    func testPlainTextIsUnchanged() {
        let text = "Fix the bug in /map/* (urgent)\nthen ship"

        XCTAssertEqual(String(InlineMarkdown.render(text).characters), text)
    }
}
