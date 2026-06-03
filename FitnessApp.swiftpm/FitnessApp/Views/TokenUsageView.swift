import SwiftUI

/// Settings → AI token usage. Lifetime Gemini token totals (input / output /
/// thinking) summed from each response's built-in `usageMetadata`, broken down
/// by feature, with a reset.
public struct TokenUsageView: View {
    @ObservedObject private var meter = TokenMeter.shared
    @Environment(\.dismiss) private var dismiss

    @AppStorage("theme_mode") private var themeMode = "dark"
    @AppStorage("accent_color") private var accentColorHex = "#30D158"
    @State private var showResetConfirm = false

    private var isDark: Bool { themeMode == "dark" }
    private var accent: Color { ThemeHelper.color(from: accentColorHex) }
    private var secondary: Color { isDark ? .white.opacity(0.55) : .black.opacity(0.55) }

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 18) {
                    totalCard
                    breakdownCard
                    sourceCard
                    footerNote
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollContentBackground(.hidden)
            .background(AdaptiveBackground())
            .navigationTitle("AI Token Usage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) { showResetConfirm = true } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .disabled(meter.total == 0)
                }
            }
            .alert("Reset token counter?", isPresented: $showResetConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) { withAnimation { meter.reset() } }
            } message: {
                Text("Clears the on-device lifetime token totals. This does not affect your Google Cloud billing.")
            }
        }
    }

    // MARK: - Total card

    private var totalCard: some View {
        VStack(spacing: 6) {
            Text(meter.total.formatted())
                .font(.system(size: 46, weight: .bold, design: .rounded))
                .foregroundStyle(
                    LinearGradient(colors: [accent, .purple],
                                   startPoint: .leading, endPoint: .trailing)
                )
                .contentTransition(.numericText())
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text("TOTAL TOKENS")
                .font(.system(size: 12, weight: .bold))
                .tracking(0.8)
                .foregroundColor(secondary)
            Text(subtitleLine)
                .font(.system(size: 13))
                .foregroundColor(secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 24))
    }

    private var subtitleLine: String {
        guard meter.total > 0, let since = meter.since else {
            return "No API calls yet"
        }
        let f = DateFormatter(); f.dateFormat = "MMM d, yyyy"
        let callLabel = meter.calls == 1 ? "1 call" : "\(meter.calls.formatted()) calls"
        return "\(callLabel) · since \(f.string(from: since))"
    }

    // MARK: - Input / output / thinking breakdown

    private var breakdownCard: some View {
        VStack(spacing: 0) {
            meterRow(icon: "arrow.up.circle.fill", color: .blue,
                     title: "Input", subtitle: "Prompt tokens sent", value: meter.prompt)
            divider
            meterRow(icon: "arrow.down.circle.fill", color: .green,
                     title: "Output", subtitle: "Visible model replies", value: meter.output)
            divider
            meterRow(icon: "brain", color: .purple,
                     title: "Thinking", subtitle: "gemini-3.5-flash reasoning", value: meter.thoughts)
        }
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
    }

    private func meterRow(icon: String, color: Color, title: String, subtitle: String, value: Int) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(color.opacity(0.18))
                    .frame(width: 30, height: 30)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(color)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(isDark ? .white : .black)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(secondary)
            }
            Spacer()
            Text(value.formatted())
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(isDark ? .white : .black)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var divider: some View {
        Rectangle()
            .fill(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
            .frame(height: 0.5)
            .padding(.leading, 56)
    }

    // MARK: - By-feature breakdown

    private var activeSources: [TokenSource] {
        TokenSource.allCases.filter { meter.tokens(for: $0) > 0 }
    }

    private var sourceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("BY FEATURE")
                .font(.system(size: 12, weight: .bold))
                .tracking(0.8)
                .foregroundColor(secondary)

            if activeSources.isEmpty {
                Text("No usage recorded yet. Chat with Astra, open a prediction's “Why?”, or scan a meal to start counting.")
                    .font(.system(size: 13))
                    .foregroundColor(secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(activeSources, id: \.self) { src in
                    sourceRow(src)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
    }

    private func sourceRow(_ src: TokenSource) -> some View {
        let tokens = meter.tokens(for: src)
        let calls = meter.callCount(for: src)
        let fraction = meter.total > 0 ? Double(tokens) / Double(meter.total) : 0
        return VStack(spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: src.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(src.tint)
                    .frame(width: 20)
                Text(src.displayName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isDark ? .white : .black)
                Spacer()
                Text("\(TokenFormat.compact(tokens)) · \(calls == 1 ? "1 call" : "\(calls) calls")")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
                    Capsule()
                        .fill(src.tint.opacity(0.85))
                        .frame(width: max(4, geo.size.width * fraction))
                }
            }
            .frame(height: 6)
        }
    }

    // MARK: - Footer

    private var footerNote: some View {
        Text("Counts every Gemini API call the app makes — coach chat, predictions, “Why?” explanations, and food photo scans — summed from each response's built-in usage report. Stored on-device only.")
            .font(.system(size: 12))
            .foregroundColor(secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 8)
            .padding(.top, 2)
    }
}
