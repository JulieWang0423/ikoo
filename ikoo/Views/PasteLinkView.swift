import SwiftUI
import UIKit

/// Paste any link — a TikTok/RedNote post, or a travel article, blog, or
/// newsletter (where a lot of people actually plan) — and run it through the
/// same extraction + confirm flow as a shared post.
struct PasteLinkView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var url: String = ""
    @State private var ingest: IngestItem?

    private var trimmed: String { url.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var looksValid: Bool {
        trimmed.contains(".") && (trimmed.hasPrefix("http") || trimmed.contains("www.") || trimmed.contains(".com") || trimmed.contains(".co"))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://…", text: $url, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .lineLimit(1...4)
                    if let clip = UIPasteboard.general.string, clip != url, clip.contains(".") {
                        Button {
                            url = clip
                        } label: {
                            Label("Paste from clipboard", systemImage: "doc.on.clipboard")
                        }
                    }
                }
                .listRowBackground(Theme.surface)

                Section {
                    Text("Works with TikTok and RedNote links, and travel articles, blog posts, or newsletters. ikoo reads the page and pulls out every place it names.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .listRowBackground(Theme.surface)
            }
            .ikooScreenBackground()
            .navigationTitle("Paste a link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Find places") {
                        ingest = IngestItem(url: trimmed, sharedText: nil)
                    }
                    .disabled(!looksValid)
                }
            }
            .sheet(item: $ingest) { item in
                ConfirmPinView(item: item) {
                    ingest = nil
                    dismiss()
                }
            }
        }
        .tint(Theme.accent)
    }
}
