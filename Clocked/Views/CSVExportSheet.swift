import SwiftUI
import UIKit

// MARK: - CSV export sheet (mockup: exportCSV / copyCSV / downloadCSV)

struct CSVExportSheet: View {
    var text: String
    var subtitle: String

    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Export CSV")
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(Theme.label)
            Text(subtitle)
                .font(.system(size: 14))
                .foregroundStyle(Theme.secondary)
                .padding(.top, 4)
                .padding(.bottom, 10)

            ScrollView {
                Text(text)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.label)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(height: 150)
            .background(Theme.inset)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            HStack(spacing: 10) {
                BigButton(title: copied ? "Copied" : "Copy",
                          background: Theme.inset, foreground: Theme.label) {
                    UIPasteboard.general.string = text
                    copied = true
                }
                ShareLink(item: csvFileURL) {
                    Text("Download .csv")
                        .font(.system(size: 16, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Theme.green)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 12)

            Spacer(minLength: 0)
        }
        .padding(20)
        .background(Theme.card)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    /// mockup downloadCSV: share a real file named hours-export.csv
    private var csvFileURL: URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hours-export.csv")
        try? text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
