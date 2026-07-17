import SwiftUI

/// Reusable scrollable viewer for a legal document (Privacy Policy, Terms of
/// Service). Presented as a sheet from anywhere the app links to policy text
/// (currently LoginView). Rendering is intentionally plain — a selectable
/// `Text` block — since `LegalTexts` supplies readable plain-text/light-markdown
/// strings, not real Markdown that needs a parser.
public struct LegalDocumentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("theme_mode") private var themeMode = "dark"

    let title: String
    let text: String

    private var isDark: Bool { themeMode == "dark" }

    public init(title: String, text: String) {
        self.title = title
        self.text = text
    }

    public var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                Text(text)
                    .font(.system(size: 14))
                    .foregroundColor(isDark ? .white.opacity(0.85) : .black.opacity(0.85))
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            }
            .background(AdaptiveBackground())
            .scrollContentBackground(.hidden)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}
