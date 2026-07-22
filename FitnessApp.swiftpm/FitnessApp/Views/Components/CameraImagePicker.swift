import SwiftUI
import UIKit

/// Wraps UIImagePickerController for the device camera. Used when the user
/// picks "Take Photo" from the composer's image action sheet. Library picking
/// continues to use PhotosPicker so we get the iOS 18+ system UI there.
struct CameraImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        // Fall back to the photo library if the simulator (or device w/o camera)
        // doesn't have a camera. Real devices will hit .camera.
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        #if DEBUG
        // Cross-path correlation with the FoodCameraView audit trail — if a
        // wedged mediaserverd also blocks this system picker, the timeline
        // shows both paths stalling together rather than looking unrelated.
        DebugCameraAudit.log("chatPicker.present", ["sourceType": picker.sourceType == .camera ? "camera" : "photoLibrary"])
        #endif
        return picker
    }

    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        var parent: CameraImagePicker
        init(_ parent: CameraImagePicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let ui = info[.originalImage] as? UIImage {
                parent.image = ui
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
