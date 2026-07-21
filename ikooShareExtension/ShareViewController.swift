import UIKit
import UniformTypeIdentifiers

/// Deliberately tiny: extract a URL and/or text from the share payload, drop
/// an IngestItem JSON file into the App Group inbox, flash a confirmation,
/// and exit. No networking, no database — the main app does the heavy
/// lifting on next open (keeps us far under extension memory limits).
final class ShareViewController: UIViewController {
    private var sharedURL: String?
    private var sharedText: String?
    private let group = DispatchGroup()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        collectAttachments()
        group.notify(queue: .main) { [weak self] in
            self?.persistAndFinish()
        }
    }

    private func collectAttachments() {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem])?
            .flatMap { $0.attachments ?? [] } ?? []

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.url.identifier) { [weak self] item, _ in
                    if let url = item as? URL {
                        self?.sharedURL = url.absoluteString
                    }
                    self?.group.leave()
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { [weak self] item, _ in
                    if let text = item as? String {
                        self?.sharedText = (self?.sharedText).map { $0 + "\n" + text } ?? text
                    }
                    self?.group.leave()
                }
            }
        }
    }

    private func persistAndFinish() {
        if sharedURL != nil || sharedText != nil {
            let item = IngestItem(url: sharedURL, sharedText: sharedText)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode(item) {
                let fileURL = AppGroup.inboxURL.appendingPathComponent("\(item.id.uuidString).json")
                try? data.write(to: fileURL, options: .atomic)
            }
            showToastAndComplete(success: true)
        } else {
            showToastAndComplete(success: false)
        }
    }

    private func showToastAndComplete(success: Bool) {
        let label = UILabel()
        label.text = success ? "Saved — open ikoo to pin it ✓" : "Nothing to save"
        label.font = .preferredFont(forTextStyle: .headline)
        label.textColor = .white
        label.textAlignment = .center
        label.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        label.layer.cornerRadius = 14
        label.clipsToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.widthAnchor.constraint(greaterThanOrEqualToConstant: 260),
            label.heightAnchor.constraint(equalToConstant: 48),
        ])

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }
}
