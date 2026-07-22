import SwiftUI

/// Block-level markdown renderer for Coach replies.
/// SwiftUI's Text(AttributedString(markdown:)) only renders *inline* attributes
/// (bold, italic, code, link). Block elements — headings, bullet lists,
/// blockquotes (`>`), the "Next:" call-to-action — need their own SwiftUI
/// views with proper spacing to read as a structured response. That's what
/// this view does.
struct StructuredMarkdownText: View {
    let text: String
    let isDark: Bool
    let accentColor: Color
    var bubbleColor: Color? = nil  // foreground override for user bubbles

    // Parsed blocks are cached in @State and recomputed only when `text` changes
    // (initial appear + each onChange). Previously this was a computed property
    // that re-ran the whole parser — block split + AttributedString(markdown:)
    // per block — on EVERY render, which during streaming meant an O(n²)
    // re-parse storm as deltas arrived. No visual change: the parse still runs
    // on every text mutation, just not on unrelated re-renders.
    //
    // AttributedString(markdown:) is also pre-rendered once inside parseBlocks
    // and stored directly in the Block enum cases, so renderBlock() never calls
    // inline() from body — eliminating the per-render markdown parsing cost on
    // completed bubbles during streaming.
    @State private var blocks: [Block] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                renderBlock(block)
            }
        }
        .onAppear { blocks = parseBlocks(text) }
        .onChange(of: text) { _, newValue in blocks = parseBlocks(newValue) }
    }

    // MARK: - Block model
    // Text-bearing cases carry a pre-rendered AttributedString so renderBlock()
    // never has to call AttributedString(markdown:) at body-evaluation time.
    private enum Block {
        case heading(AttributedString)
        case bullets([AttributedString])
        case numbered([AttributedString])
        case next(AttributedString)
        case paragraph(AttributedString)
        case codeBlock(String)
        case divider
        // [Block] recurses through Array's heap box, so this compiles without
        // `indirect` — the enum itself never needs to store a Block inline.
        case quote([Block])
    }

    /// Parse into blocks. We accept both real `\n\n` paragraph breaks and the
    /// LLM's frequent mistake of running sections together on a single line —
    /// classifying line-by-line gives us the right structure either way.
    ///
    /// `depth` counts how many `.quote` wrappers already contain this call
    /// (0 = top-level, not inside any quote). It's an implementation detail
    /// for the nesting clamp below — callers never need to pass it.
    private func parseBlocks(_ text: String, depth: Int = 0) -> [Block] {
        // Normalize CRLF, then split on \n. We rebuild paragraphs ourselves.
        var lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")

        // Full-wrap unwrap: the model sometimes imitates the prompt's example
        // literally and wraps an ENTIRE reply in '>'. If every non-empty line
        // is quoted, strip one level from every line and repeat until it's no
        // longer fully wrapped — the glass bubble already frames the reply,
        // so a fully-quoted reply should render exactly as an unquoted one
        // would. Partial quoting (only some lines) is left to the quote-run
        // branch in the loop below.
        while lines.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }),
              lines.allSatisfy({ line in
                  let trimmed = line.trimmingCharacters(in: .whitespaces)
                  return trimmed.isEmpty || trimmed.hasPrefix(">")
              }) {
            lines = lines.map { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return trimmed.isEmpty ? line : stripOneQuoteLevel(trimmed)
            }
        }

        var result: [Block] = []
        var pendingBullets: [String] = []
        var pendingNumbered: [String] = []
        var pendingParagraph: [String] = []
        var inCode = false
        var codeLines: [String] = []

        func flushParagraph() {
            if !pendingParagraph.isEmpty {
                let joined = pendingParagraph.joined(separator: " ").trimmingCharacters(in: .whitespaces)
                if !joined.isEmpty { result.append(.paragraph(inline(joined))) }
                pendingParagraph.removeAll()
            }
        }
        func flushBullets() {
            if !pendingBullets.isEmpty { result.append(.bullets(pendingBullets.map { inline($0) })); pendingBullets.removeAll() }
        }
        func flushNumbered() {
            if !pendingNumbered.isEmpty { result.append(.numbered(pendingNumbered.map { inline($0) })); pendingNumbered.removeAll() }
        }
        func flushAll() { flushParagraph(); flushBullets(); flushNumbered() }

        var i = 0
        while i < lines.count {
            let raw = lines[i]
            let line = raw.trimmingCharacters(in: .whitespaces)

            // Quote-run: '>'-prefixed line(s) — checked BEFORE the code-fence
            // check so a quoted fence marker (`> ```) is handled by the
            // recursive parse rather than toggling fence state at this level,
            // unless already inside a code fence.
            if !inCode && line.hasPrefix(">") {
                flushAll()
                var buffer: [String] = []
                let clamp = depth >= 3
                while i < lines.count {
                    let qLine = lines[i].trimmingCharacters(in: .whitespaces)
                    guard qLine.hasPrefix(">") else { break }
                    buffer.append(clamp ? stripAllQuoteLevels(qLine) : stripOneQuoteLevel(qLine))
                    i += 1
                }
                if clamp {
                    // Already at max nesting (3) — flatten instead of
                    // wrapping again so a run of '>' beyond depth 3 renders
                    // as plain content, not a 4th nested quote bar.
                    result.append(contentsOf: parseBlocks(buffer.joined(separator: "\n"), depth: depth))
                } else {
                    let inner = parseBlocks(buffer.joined(separator: "\n"), depth: depth + 1)
                    if !inner.isEmpty { result.append(.quote(inner)) }
                }
                continue
            }

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
                i += 1; continue
            }
            if inCode { codeLines.append(raw); i += 1; continue }

            if line.isEmpty { flushAll(); i += 1; continue }

            // Horizontal rule
            if line == "---" || line == "***" {
                flushAll(); result.append(.divider); i += 1; continue
            }

            // Heading: # / ## / ### (treat all alike — section header)
            if let headingText = stripHeading(line) {
                flushAll(); result.append(.heading(inline(headingText))); i += 1; continue
            }

            // Bullet: - or * (not **) or +
            if line.hasPrefix("- ") || line.hasPrefix("+ ") || (line.hasPrefix("* ") && !line.hasPrefix("**")) {
                flushParagraph(); flushNumbered()
                pendingBullets.append(String(line.dropFirst(2)))
                i += 1; continue
            }

            // Numbered: 1. / 2. ...
            if let dot = line.firstIndex(of: "."),
               line.distance(from: line.startIndex, to: dot) <= 2,
               Int(line[line.startIndex..<dot]) != nil {
                flushParagraph(); flushBullets()
                let body = String(line[line.index(after: dot)...]).trimmingCharacters(in: .whitespaces)
                pendingNumbered.append(body)
                i += 1; continue
            }

            // "Next: …" call-to-action treated as its own block.
            if let nextBody = matchNext(line) {
                flushAll(); result.append(.next(inline(nextBody))); i += 1; continue
            }

            // Regular paragraph line.
            flushBullets(); flushNumbered()
            pendingParagraph.append(line)
            i += 1
        }
        // Streaming mid-fence: if the text ended while still inside an
        // unterminated code fence, flush what's buffered so far instead of
        // dropping it silently until the closing fence arrives.
        if inCode && !codeLines.isEmpty {
            result.append(.codeBlock(codeLines.joined(separator: "\n")))
        }
        flushAll()
        return result
    }

    /// Strip exactly one quote level: a leading '>' plus at most one
    /// following space (`> text` → `text`, `>text` → `text`, bare `>` → "").
    private func stripOneQuoteLevel(_ trimmedLine: String) -> String {
        guard trimmedLine.hasPrefix(">") else { return trimmedLine }
        var rest = String(trimmedLine.dropFirst())
        if rest.hasPrefix(" ") { rest.removeFirst() }
        return rest
    }

    /// Strip every leading quote level (used only past the nesting clamp).
    private func stripAllQuoteLevels(_ trimmedLine: String) -> String {
        var s = trimmedLine
        while s.hasPrefix(">") { s = stripOneQuoteLevel(s) }
        return s
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
        case .heading(let attr):
            Text(attr)
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
                        Text(item)
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
                        Text(item)
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundColor(mutedFg)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

        case .next(let attr):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Next")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(accentColor)
                    .clipShape(Capsule())
                Text(attr)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(fg)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 2)

        case .paragraph(let attr):
            Text(attr)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundColor(fg)
                .fixedSize(horizontal: false, vertical: true)

        case .codeBlock(let s):
            // Root cause of the "again" horizontal-scroll wobble: code the
            // model fences (JSON, long IDs, table rows) frequently contains
            // runs with no whitespace to wrap at. A bare Text() can't shrink
            // below that run's width, so it reports an ideal width wider than
            // the bubble — which (unlike DashboardView's cards) had no cap,
            // so the oversized report propagated up into the vertical
            // ScrollView's content and re-enabled horizontal drag. A
            // horizontal ScrollView is the native fix: it always reports its
            // *proposed* size upward regardless of content width, so any
            // unwrappable line scrolls within the code block instead of
            // dragging the whole screen.
            ScrollView(.horizontal, showsIndicators: false) {
                Text(s)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(fg)
                    .padding(8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(isDark ? 0.06 : 0.04), in: RoundedRectangle(cornerRadius: 8))

        case .divider:
            Rectangle()
                .fill(fg.opacity(0.12))
                .frame(height: 0.5)

        case .quote(let inner):
            // AnyView is mandatory here — a recursive @ViewBuilder `some View`
            // call doesn't compile. The overlay (not an HStack rule + content)
            // avoids the greedy-Rectangle sizing problem an HStack would have.
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(inner.enumerated()), id: \.offset) { _, b in
                    AnyView(renderBlock(b))
                }
            }
            .padding(.leading, 11)
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(accentColor.opacity(0.45))
                    .frame(width: 3)
                    .padding(.vertical, 1)
            }
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
