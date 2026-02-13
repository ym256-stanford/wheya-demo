//
//  EditProfileView.swift
//  Wheya
//
//  Created by Yuliia Murakami on 7/5/25.
//

import SwiftUI
import PhotosUI
import CloudKit

struct EditPhotoView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var userProfile: UserProfile
    @State private var selectedImage: UIImage? = nil
    @State private var pickerItem: PhotosPickerItem? = nil

    var onSave: (URL?) async -> Void

    var body: some View {
        VStack(spacing: 20) {
            if let image = selectedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 250)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            } else if let existing = userProfile.image {
                AsyncImage(url: existing) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFit()
                    default: Image(systemName: "photo").resizable().scaledToFit()
                }}
                .frame(maxHeight: 250)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable().scaledToFit().frame(width: 120, height: 120)
                    .foregroundColor(.gray)
            }

            PhotosPicker("Choose Photo", selection: $pickerItem, matching: .images)
                .buttonStyle(.borderedProminent)

            Spacer()
        }
        .padding()
        .navigationTitle("Edit Photo")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task {
                        let url = await saveImageToTempCloudKitIfNeeded()
                        userProfile.image = url
                        await onSave(url)
                        dismiss()
                    }
                }
                .disabled(selectedImage == nil)
            }
        }
        .onChange(of: pickerItem) {
            Task {
                if let data = try? await pickerItem?.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data) {
                    selectedImage = resizeImage(uiImage)
                }
            }
        }
    }

    // Resize image and write to disk
    private func resizeImage(_ image: UIImage, max: CGFloat = 1024) -> UIImage {
        let size = image.size
        let ratio = size.width / size.height
        let newSize: CGSize = size.width > size.height
            ? CGSize(width: max, height: max / ratio)
            : CGSize(width: max * ratio, height: max)
        return UIGraphicsImageRenderer(size: newSize).image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    // Save image to temp file and return URL
    private func saveImageToTempCloudKitIfNeeded() async -> URL? {
        guard let img = selectedImage,
              let data = img.jpegData(compressionQuality: 0.8) else { return nil }

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".jpg")

        do {
            try data.write(to: fileURL)
            return fileURL
        } catch {
            print("Error writing image: \(error)")
            return nil
        }
    }
}
