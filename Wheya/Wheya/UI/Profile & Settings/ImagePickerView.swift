//
//  ImagePickerView.swift
//  MeetingUp
//
//  Created by Yuliia Murakami on 6/9/25.

import SwiftUI
import UIKit

// A SwiftUI view that wraps the UIKit `UIImagePickerController`.
// This allows to present a native interface for selecting images from the photo library or taking a new photo with the camera.
struct ImagePickerView: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    // The source for the image picker (e.g., .camera or .photoLibrary).
    let sourceType: UIImagePickerController.SourceType
    var allowsEditing: Bool = false
    let onImagePicked: (UIImage) -> Void

    // Creates and configures the initial `UIImagePickerController` instance.
    // This method is called once when SwiftUI first creates the view.
    func makeUIViewController(context: Context) -> UIImagePickerController {
        // First, check if the requested source type (like the camera) is available on the device.
        guard UIImagePickerController.isSourceTypeAvailable(sourceType) else {
            // If the source is not available (e.g., trying to use the camera on a simulator),
            // log an error and return an empty picker.
            print("ImagePickerView Error: Source type \(sourceType.rawValue) is not available.")
            return UIImagePickerController()
        }
        
        let picker = UIImagePickerController()
        picker.sourceType = self.sourceType
        picker.allowsEditing = self.allowsEditing
        // Set the delegate, which handles user actions like picking an image or canceling.
        // The `context.coordinator` is the bridge between UIKit's delegate pattern and SwiftUI.
        picker.delegate = context.coordinator
        return picker
    }

    // Updates the `UIImagePickerController` if the SwiftUI view's state changes.
    // In this case, no updates are needed, so the function is empty.
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {
        // no-op
    }

    // Creates the `Coordinator` instance that acts as the delegate for the `UIImagePickerController`.
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // The Coordinator class acts as a bridge between the UIKit `UIImagePickerController` and the SwiftUI `ImagePickerView`.
    // It handles delegate callbacks from the picker.
    class Coordinator: NSObject,
                       UINavigationControllerDelegate,
                       UIImagePickerControllerDelegate {
        // A reference back to the parent `ImagePickerView` struct.
        let parent: ImagePickerView

        init(_ parent: ImagePickerView) {
            self.parent = parent
        }

        // This delegate method is called when the user has finished picking an image or video.
        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]
        ) {
            // The `info` dictionary contains the selected media.
            // We prioritize the `.editedImage` if it exists, otherwise we fall back to the `.originalImage`.
            let image = info[.editedImage] as? UIImage ?? info[.originalImage] as? UIImage
            
            
            if let uiImage = image {
                parent.selectedImage = uiImage
                // call the completion handler closure.
                parent.onImagePicked(uiImage)
            }

            picker.dismiss(animated: true)
        }

        // This delegate method is called when the user taps the "Cancel" button.
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}
