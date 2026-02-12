import SwiftUI

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any] // The content to share

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
