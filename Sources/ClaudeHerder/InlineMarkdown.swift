import SwiftUI

/// Titles and recaps are written by Claude and often contain inline markdown like `code`.
enum InlineMarkdown {
    static func render(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace)
        // Text that isn't valid markdown is still fine to show as-is.
        guard var rendered = try? AttributedString(markdown: text, options: options) else {
            return AttributedString(text)
        }
        for run in rendered.runs where run.inlinePresentationIntent?.contains(.code) == true {
            rendered[run.range].backgroundColor = Theme.codeBackground
        }
        return rendered
    }
}
