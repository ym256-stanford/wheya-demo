//
//  MessageEnterView.swift
//  Wheya
//
//  Created by Yuliia Murakami on 9/12/25.
//

import SwiftUI
import PhotosUI
import AVFoundation

struct MessageEnterView: View {
    // MARK: Data In
    let title: String
    @Binding var text: String
    let placeholder: String
    let onSend: () -> Void
    let onCancel: () -> Void
    
    // MARK: - Body
    var body: some View {
        ZStack {
            VStack(spacing: DesignConstants.imageThumbnail.spacing) {
                // Title
                Text(title)
                    .font(.title2)
                    .bold()
                    .accessibilityAddTraits(.isHeader)
                
                VStack(alignment: .leading, spacing: DesignConstants.imageThumbnail.spacing) {
                    // Input area
                    inputField()
                }
                Button("Send") { onSend() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(DesignConstants.imageThumbnail.spacing)
            .background(.ultraThinMaterial)
            .cornerRadius(DesignConstants.General.cornerRadius)
            .padding(.horizontal, DesignConstants.imageThumbnail.spacing)
        }
    }
    
    // MARK: - Subviews
    
    private func inputField() -> some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .frame(height: DesignConstants.MessageInput.textEditorHeight)
                .padding(DesignConstants.MessageInput.textEditorPadding)
                .background(
                    RoundedRectangle(cornerRadius: DesignConstants.MessageInput.cornerRadius)
                        .fill(DesignConstants.MessageInput.textEditorBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DesignConstants.MessageInput.cornerRadius)
                        .stroke(DesignConstants.MessageInput.textEditorBorder, lineWidth: DesignConstants.MessageInput.textEditorLineWidth)
                )
                .foregroundColor(.primary)
                .scrollContentBackground(.hidden)
        }
    }
}
