import SwiftUI

/// Block-level markdown renderer for Coach replies.
/// SwiftUI's Text(AttributedString(markdown:)) only renders *inline* attributes
/// (bold, italic, code, link). Block elements — headings, bullet lists, the
/// "Next:" call-to-action — need their own SwiftUI views with proper spacing
/// to read as a structured response. That's what this view does.
struct StructuredMarkdownText: View {
    let text: String
    let isDark: Bool
    let accentColor: Color
    var bubbleColor: Color? = nil  // foreground override for user bubbles

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                renderBlock(block)
            }
        }
    }

    // MARK: - Block model
    private enum Block {
        case heading(String)
        case bullets([String])
        case numbered([String])
        case next(String)
        case paragraph(String)
        case codeBlock(String)
        case divider
    }

    /// Parse into blocks. We accept both real `\n\n` paragraph breaks and the
    /// LLM's frequent mistake of running sections together on a single line —
    /// classifying line-by-line gives us the right structure either way.
    private var blocks: [Block] {
        // Normalize CRLF, then split on \n. We rebuild paragraphs ourselves.
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")

        var result: [Block] = []
        var pendingBullets: [String] = []
        var pendingNumbered: [String] = []
        var pendingParagraph: [String] = []
        var inCode = false
        var codeLines: [String] = []

        func flushParagraph() {
            if !pendingParagraph.isEmpty {
                let joined = pendingParagraph.joined(separator: " ").trimmingCharacters(in: .whitespaces)
                if !joined.isEmpty { result.append(.paragraph(joined)) }
                pendingParagraph.removeAll()
            }
        }
        func flushBullets() {
            if !pendingBullets.isEmpty { result.append(.bullets(pendingBullets)); pendingBullets.removeAll() }
        }
        func flushNumbered() {
            if !pendingNumbered.isEmpty { result.append(.numbered(pendingNumbered)); pendingNumbered.removeAll() }
        }
        func flushAll() { flushParagraph(); flushBullets(); flushNumbered() }

        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)

            // Fenced code block ``` ... ```
            if line.hasPrefix("```") {
                if inCode {
                    result.append(.codeBlock(codeLines.joined(separator: "\n")))
                    codeLines.removeAll()
                    inCode = false
                } else {
                    flushAll()
                    inCode = true
                }
                continue
            }
            if inCode { codeLines.append(raw); continue }

            if line.isEmpty { flushAll(); continue }

            // Horizontal rule
            if line == "---" || line == "***" {
                flushAll(); result.append(.divider); continue
            }

            // Heading: # / ## / ### (treat all alike — section header)
            if let headingText = stripHeading(line) {
                flushAll(); result.append(.heading(headingText)); continue
            }

            // Bullet: - or * (not **)
            if line.hasPrefix("- ") || (line.hasPrefix("* ") && !line.hasPrefix("**")) {
                flushParagraph(); flushNumbered()
                pendingBullets.append(String(line.dropFirst(2)))
                continue
            }

            // Numbered: 1. / 2. ...
            if let dot = line.firstIndex(of: "."),
               line.distance(from: line.startIndex, to: dot) <= 2,
               Int(line[line.startIndex..<dot]) != nil {
                flushParagraph(); flushBullets()
                let body = String(line[line.index(after: dot)...]).trimmingCharacters(in: .whitespaces)
                pendingNumbered.append(body)
                continue
            }

            // "Next: …" call-to-action treated as its own block.
            if let nextBody = matchNext(line) {
                flushAll(); result.append(.next(nextBody)); continue
            }

            // Regular paragraph line.
            flushBullets(); flushNumbered()
            pendingParagraph.append(line)
        }
        flushAll()
        return result
    }

    private func stripHeading(_ line: String) -> String? {
        // Match 1-6 leading # then a space, or with bold variant: ### **Title**
        var s = line
        var hashes = 0
        while s.hasPrefix("#") && hashes < 6 {
            s.removeFirst(); hashes += 1
        }
        guard hashes > 0, s.hasPrefix(" ") else { return nil }
        var body = s.trimmingCharacters(in: .whitespaces)
        // Strip surrounding ** if present (`### **Why**`)
        if body.hasPrefix("**") && body.hasSuffix("**") && body.count >= 4 {
            body = String(body.dropFirst(2).dropLast(2))
        }
        return body
    }

    private func matchNext(_ line: String) -> String? {
        let lower = line.lowercased()
        // Plain "Next: ..." or "**Next:** ..."
        if lower.hasPrefix("next:") {
            return String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
        }
        if lower.hasPrefix("**next:**") {
            return String(line.dropFirst(9)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    // MARK: - Rendering
    private var fg: Color { bubbleColor ?? (isDark ? .white : .black) }
    private var mutedFg: Color { bubbleColor?.opacity(0.85) ?? (isDark ? .white.opacity(0.85) : .black.opacity(0.85)) }

    @ViewBuilder
    private func renderBlock(_ block: Block) -> some View {
        switch block {
        case .heading(let s):
            Text(inline(s))
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(accentColor)
                .textCase(.uppercase)
                .tracking(0.5)
                .padding(.top, 2)

        case .bullets(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle().fill(accentColor)
                            .frame(width: 5, height: 5)
                            .padding(.top, 6)
                        Text(inline(item))
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundColor(mutedFg)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

        case .numbered(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(i + 1).")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(accentColor)
                        Text(inline(item))
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundColor(mutedFg)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

        case .next(let s):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Next")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(accentColor)
                    .clipShape(Capsule())
                Text(inline(s))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(fg)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 2)

        case .paragraph(let s):
            Text(inline(s))
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundColor(fg)
                .fixedSize(horizontal: false, vertical: true)

        case .codeBlock(let s):
            Text(s)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(fg)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(isDark ? 0.06 : 0.04), in: RoundedRectangle(cornerRadius: 8))

        case .divider:
            Rectangle()
                .fill(fg.opacity(0.12))
                .frame(height: 0.5)
        }
    }

    /// Inline markdown (bold/italic/code/link) within a block.
    private func inline(_ s: String) -> AttributedString {
        let opts = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: true,
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        return (try? AttributedString(markdown: s, options: opts)) ?? AttributedString(s)
    }
}
