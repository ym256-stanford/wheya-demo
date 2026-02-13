//
//  PhotoPickerConfirmation.swift
//  MeetingUp
//
//  Created by Yuliia Murakami on 6/9/25.
//

import SwiftUI

struct PhotoPickerConfirmation: View {
    // MARK: Data Shared With Me
    @Binding var selectedSource: PhotoSourceType?
    
    // MARK: Data In
    var allowDelete: Bool = false
    var onDelete: (() -> Void)? = nil

    // MARK: - Body
    
    var body: some View {
        Group {
            Button {
                selectedSource = .camera
            } label: {
                Label("Take Photo", systemImage: "camera")
            }

            Button {
                selectedSource = .photoLibrary
            } label: {
                Label("Choose Photo", systemImage: "photo.on.rectangle")
            }

            if allowDelete, let onDelete = onDelete {
                Button(role: .destructive, action: onDelete) {
                    Label("Remove Photo", systemImage: "trash")
                }
            }

            Button("Cancel", role: .cancel) { }
        }
    }
}
