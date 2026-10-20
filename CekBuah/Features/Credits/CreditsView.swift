import SwiftUI

/// Shows Credits.md (datasets, authors, links, licenses, changes).
struct CreditsView: View {
    private let lines: [String] = {
        guard let url = Bundle.main.url(forResource: "Credits", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return ["Credits.md tidak ditemukan."]
        }
        return text.components(separatedBy: .newlines)
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    row(for: line)
                }
            }
            .padding(Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Tentang & Sumber Data")
    }

    /// Minimal Markdown: headings, bullets, and inline links/bold via AttributedString.
    @ViewBuilder
    private func row(for line: String) -> some View {
        if line.hasPrefix("## ") {
            Text(inline(String(line.dropFirst(3)))).font(.title3.bold()).padding(.top, Spacing.m)
                .accessibilityAddTraits(.isHeader)
        } else if line.hasPrefix("# ") {
            Text(inline(String(line.dropFirst(2)))).font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
        } else if line.hasPrefix("- ") {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                Text("•").accessibilityHidden(true)
                Text(inline(String(line.dropFirst(2))))
            }
        } else if !line.trimmingCharacters(in: .whitespaces).isEmpty {
            Text(inline(line))
        }
    }

    private func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }
}

#Preview {
    NavigationStack { CreditsView() }
}
