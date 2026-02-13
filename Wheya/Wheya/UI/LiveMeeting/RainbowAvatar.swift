//
//  RainbowAvatar.swift
//  Wheya
//
//  Created by Yuliia Murakami on 9/12/25.
//

import SwiftUI
import UIKit

// MARK: - RainbowAvatar

/// A circular avatar view with an optional rotating rainbow gradient border.
/// - isHere: If true, the border animates continuously.
/// - imageName: Optional image name to display inside the circle.
/// - name: Fallback display name used to generate initials when no image is provided.
struct RainbowAvatar: View {
    // MARK: Input Properties

    /// Whether the attendee is marked "here" and should show the animated border.
    let isHere: Bool
    let imageData: Data?
    /// Person's full name, used to generate initials as a fallback.
    let name: String
    
    // MARK: Animation State

    /// Tracks the current rotation angle for the rainbow gradient.
    @State private var rainbowRotation: Angle = .zero

    init(isHere: Bool, imageName: String? = nil, name: String, imageData: Data? = nil) {
        self.isHere = isHere
        self.name = name
        self.imageData = imageData
    }
    
    // MARK: - Body
    var body: some View {
        ZStack {
            // If attendee is "here", draw a spinning rainbow border.
            if isHere {
                Circle()
                    .strokeBorder(
                        AngularGradient(
                            gradient: Gradient(colors: [
                                .red, .orange, .yellow, .green, .blue, .purple, .red
                            ]),
                            center: .center
                        ),
                        lineWidth: RainbowAvatarConstants.borderWidth
                    )
                    .rotationEffect(rainbowRotation)
                    .frame(
                        width: RainbowAvatarConstants.outerSize,
                        height: RainbowAvatarConstants.outerSize
                    )
                    .accessibilityHidden(true)
            }

            // Inner content: either image or initials on gray background.
            if let data = imageData, let ui = UIImage(data: data) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .frame(
                        width: RainbowAvatarConstants.innerSize,
                        height: RainbowAvatarConstants.innerSize
                    )
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color.gray)
                    .frame(
                        width: RainbowAvatarConstants.innerSize,
                        height: RainbowAvatarConstants.innerSize
                    )
                    .overlay(
                        Text(initials(from: name))
                            .font(.headline)
                            .foregroundColor(.white)
                    )
            }
        }
        .onAppear {
            // Start a continuous 360° rotation animation for the border when view appears.
            withAnimation(
                Animation.linear(duration: RainbowAvatarConstants.rotationDuration)
                    .repeatForever(autoreverses: false)
            ) {
                rainbowRotation = .degrees(360)
            }
        }
    }

    // MARK: - Helpers

    /// Extracts uppercase initials from a full name.
    private func initials(from fullName: String) -> String {
        fullName
            .components(separatedBy: " ")
            .compactMap { $0.first }
            .map(String.init)
            .joined()
            .uppercased()
    }
}

// MARK: - Constants

private enum RainbowAvatarConstants {
    /// Total size of the outer circle including the border.
    static let outerSize: CGFloat = 58
    /// Size of the inner avatar content (image or initials).
    static let innerSize: CGFloat = 50
    /// Width of the rainbow gradient border.
    static let borderWidth: CGFloat = 4
    /// Duration of one full rotation of the rainbow border animation.
    static let rotationDuration: Double = 5
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        RainbowAvatar(isHere: true, imageName: nil, name: "Alex Johnson")
        RainbowAvatar(isHere: false, imageName: nil, name: "Alex Johnson")
    }
}
