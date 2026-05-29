import SwiftUI
import QuickLook

/// Thin SwiftUI wrapper around `QLPreviewController` so the generated PDF can
/// be presented via `.sheet(item:)`. QuickLook gives AirDrop / email / Files /
/// AirPrint via its built-in share button, which covers the slice's
/// distribution requirements without a separate share-sheet code path.
struct PDFPreview: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let vc = QLPreviewController()
        vc.dataSource = context.coordinator
        return vc
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController,
                               previewItemAt index: Int) -> QLPreviewItem {
            url as QLPreviewItem
        }
    }
}

/// Wrapper so `URL` can drive `.sheet(item:)`.
struct PreviewItem: Identifiable {
    let id = UUID()
    let url: URL
}
