//
//  ProfilePictureView.swift
//  Wheya
//
//  Created by Yuliia Murakami on 9/1/25.
//

import SwiftUI

// This is a view for profile picture. Can be in large and small variants. Large is used in ProfileView to change the photo, otherwise small is used.
// This shows a newly picked UIImage if present; otherwise it renders your cached thumbnail bytes (imageData) from SwiftData; otherwise it falls back to initials.
// NOTE: Before wrote the code to download the image from CloudKit, but erased. If necessary find in the CloudKit version.
struct ProfilePictureView: View {
    enum Variant { case large, small }
    // Raw bytes from SwiftData cache.
    var imageData: Data? = nil
    // A newly selected image to be displayed immediately, overriding the URL.
    var selectedImage: UIImage?
    // The user's name, used to generate initials for the placeholder.
    var displayName: String?
    // An optional action to trigger when the camera icon is tapped. Only used in .large.
    var onCameraTap: (() -> Void)?
    
    var size: CGFloat = DesignConstants.ProfilePicture.size
    var variant: Variant = .small
    
    // Styling differences
    private var showCamera: Bool { onCameraTap != nil && variant == .large }
    private var borderWidth: CGFloat {
        variant == .large ? DesignConstants.ProfilePicture.borderWidth : 1
    }
    private var shadowRadius: CGFloat {
        variant == .large ? DesignConstants.ProfilePicture.shadowRadius : 0
    }
    
    // MARK: - Body
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // The actual circular image (or placeholder)
            Group {
                if let image = selectedImage {
                    // Prioritize showing the newly selected UIImage for instant feedback.
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else if let data = imageData, let ui = UIImage(data: data) {
                    // Prefer cached Data over URL to avoid extra disk/network I/O.
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFill()
                } else {
                    // Show the placeholder if no image is available.
                    placeholder
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(DesignConstants.ProfilePicture.borderColor,
                            lineWidth: DesignConstants.ProfilePicture.borderWidth)
            )
            .shadow(radius: shadowRadius)
            
            // The camera button, which appears only if an action is provided.
            if showCamera {
                if let onCameraTap = onCameraTap {
                    Button(action: onCameraTap) {
                        Image(systemName: "camera.fill")
                            .foregroundColor(.white)
                            .padding(DesignConstants.ProfilePicture.cameraPadding)
                            .background(Color.gray.opacity(DesignConstants.ProfilePicture.cameraOpacity))
                            .clipShape(Circle())
                            .shadow(radius: DesignConstants.ProfilePicture.cameraShadow)
                    }
                    .offset(x: DesignConstants.ProfilePicture.cameraOffset,
                            y: DesignConstants.ProfilePicture.cameraOffset)
                }
            }
        }
    }
    
    // Shows initials or a default icon.
    private var placeholder: some View {
        ZStack {
            if let name = displayName, !name.isEmpty {
                Text(initials(from: name))
                    .font(.system(size: size * 0.4, weight: .medium))
                    .foregroundColor(DesignConstants.ProfilePicture.defaultImageColor)
            } else {
                Image(systemName: DesignConstants.ProfilePicture.defaultImageName)
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(DesignConstants.ProfilePicture.defaultImageColor)
            }
        }
    }
    
    // Helper function to generate initials from a name string.
    private func initials(from name: String) -> String {
        return name
            .components(separatedBy: .whitespaces)
            .compactMap { $0.first }
            .map { String($0).uppercased() }
            .prefix(2)
            .joined()
    }
}

