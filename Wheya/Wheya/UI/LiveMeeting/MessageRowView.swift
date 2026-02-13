//
//  MessageRowView.swift
//  Wheya
//
//  Created by Yuliia Murakami on 9/12/25.
//

import SwiftUI

// MARK: - MessageRowView

/// A reusable row view showing an individual chat message:
/// includes the sender’s avatar (with optional rainbow border),
/// sender name, timestamp, message text, and any attached images.
struct MessageRowView: View {
    // MARK: Data In
    /// The message model containing sender info, text, timestamp, and optional image paths.
    let message: CachedMessage
    /// Whether the sender is marked "here" in this meeting
    let isHere: Bool
    let imageData: Data?
    
    // MARK: - Body
    var body: some View {
        HStack(alignment: .top, spacing: Constants.hStackSpacing) {
            // Avatar view with rainbow border if the sender is "here"
            RainbowAvatar(
                isHere: isHere,
                name: message.senderDisplayName,
                imageData: imageData
            )

            VStack(alignment: .leading, spacing: Constants.vStackSpacing) {
                // Sender name and timestamp row
                HStack {
                    Text(message.senderDisplayName.isEmpty ? "Anonymous" : message.senderDisplayName)
                        .font(.headline)
                    Spacer()
                    // Use SwiftUI’s built-in time style for the timestamp
                    Text(message.timestamp, style: .time)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                // The message body text
                Text(message.text)
                    .font(.body)
            }
        }
        // Horizontal padding around the entire row
        .padding(.horizontal, Constants.horizontalPadding)
    }
}

// MARK: - Constants

private enum Constants {
    /// Spacing between avatar and message content
    static let hStackSpacing: CGFloat = 12
    /// Spacing between lines in the message content VStack
    static let vStackSpacing: CGFloat = 4
    /// Horizontal padding for the entire row
    static let horizontalPadding: CGFloat = 16
    /// Spacing between images in the horizontal scroll
    static let scrollImageSpacing: CGFloat = 8
    /// Size (width & height) for each attached image thumbnail
    static let imageFrameSize: CGFloat = 120
    /// Corner radius for image thumbnails
    static let imageCornerRadius: CGFloat = 8
}

