import SwiftUI
import PhotosUI

/// Pick a screenshot (e.g. of a RedNote note), read the text on it with
/// on-device OCR, and run it through the same extraction + confirm flow as a
/// shared post. No photo-library permission needed — PhotosPicker is
/// out-of-process.
struct ScreenshotImportView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selection: PhotosPickerItem?
    @State private var reading = false
    @State private var failed: String?
    @State private var ingest: IngestItem?

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                Spacer()
                Image(systemName: "text.viewfinder")
                    .font(.system(size: 52))
                    .foregroundStyle(Theme.accent)
                Text("Read a screenshot")
                    .font(Theme.title(26))
                    .foregroundStyle(Theme.ink)
                Text("Pick a screenshot of a post — a RedNote note, a story, an article — and ikoo reads the text on it to find the places.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                if reading {
                    ProgressView("Reading the screenshot…")
                        .padding(.top, 8)
                } else if let failed {
                    Text(failed)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                Spacer()

                PhotosPicker(selection: $selection, matching: .images, photoLibrary: .shared()) {
                    Text("Choose a screenshot")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .foregroundStyle(.white)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .disabled(reading)
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("From a screenshot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .onChange(of: selection) { _, newValue in
                guard let newValue else { return }
                Task { await handlePick(newValue) }
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

    private func handlePick(_ item: PhotosPickerItem) async {
        reading = true
        failed = nil
        defer { reading = false }

        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            failed = "Couldn't open that image. Try another."
            return
        }
        let text = await OCRService.recognizeText(in: image)
        guard text.trimmingCharacters(in: .whitespacesAndNewlines).count > 3 else {
            failed = "No readable text found on that screenshot."
            return
        }
        var newItem = IngestItem(url: nil, sharedText: text)
        // Screenshots don't carry a link, so mark the source explicitly.
        if newItem.sourceApp == "other" { newItem.sourceApp = "screenshot" }
        ingest = newItem
    }
}
