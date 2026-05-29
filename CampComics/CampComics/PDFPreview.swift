import SwiftUI
import QuickLook
import UIKit

/// Thin SwiftUI wrapper that presents the generated PDF in a `QLPreviewController`
/// wrapped in a `UINavigationController`. The nav bar carries an explicit
/// `action` button that fires a `UIActivityViewController` (Files, Acrobat,
/// AirDrop, Mail, AirPrint) so the operator doesn't have to hunt for
/// QuickLook's built-in share affordance.
struct PDFPreview: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UINavigationController {
        let preview = QLPreviewController()
        preview.dataSource = context.coordinator
        preview.navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .action,
            target: context.coordinator,
            action: #selector(Coordinator.share(_:))
        )
        let nav = UINavigationController(rootViewController: preview)
        context.coordinator.preview = preview
        return nav
    }

    func updateUIViewController(_ controller: UINavigationController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        weak var preview: QLPreviewController?
        init(url: URL) { self.url = url }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController,
                               previewItemAt index: Int) -> QLPreviewItem {
            url as QLPreviewItem
        }

        @objc func share(_ sender: UIBarButtonItem) {
            guard let preview else { return }
            let activity = UIActivityViewController(activityItems: [url],
                                                    applicationActivities: nil)
            activity.popoverPresentationController?.barButtonItem = sender
            preview.present(activity, animated: true)
        }
    }
}

/// Wrapper so `URL` can drive `.sheet(item:)`.
struct PreviewItem: Identifiable {
    let id = UUID()
    let url: URL
}
