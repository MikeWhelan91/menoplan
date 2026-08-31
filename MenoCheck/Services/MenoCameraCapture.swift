import SwiftUI
import UIKit

/// Native camera capture (shutter + built-in Retake/Use Photo confirmation) — deliberately
/// not a custom AVCaptureSession/guide-overlay. The AI endpoint reads a normal resized
/// photo rather than a precisely template-aligned crop, so a guided capture UI buys
/// nothing here; `UIImagePickerController` gets the same practical result for a fraction
/// of the code.
struct MenoCameraCapture: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    var sourceType: UIImagePickerController.SourceType = .camera
    var onCapture: (UIImage) -> Void

    /// The simulator has no camera hardware — `.photoLibrary` is the only way to exercise
    /// this flow end-to-end there, which is also a reasonable real fallback on-device.
    static var isCameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: MenoCameraCapture
        init(_ parent: MenoCameraCapture) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onCapture(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
