//
//  MapImageView.swift
//  MeetingUp
//
//  Created by Yuliia Murakami on 5/29/25.
//

import SwiftUI

// Show the image and animation in Login page
struct MapImageView: View {
    // MARK: Data Owned By Me
    @State private var circle1State: CircleState? = nil
    @State private var circle2State: CircleState? = nil
    @State private var pulseRing: Bool = false

    private var bothGreen: Bool {
        circle1State == .green && circle2State == .green
    }
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            // Background image + pulsing ring
            Image("LoginImage")
                .resizable()
                .scaledToFit()
                .cornerRadius(DesignConstants.MapImage.imageCornerRadius)
                .overlay(pulseOverlay)
                .onChange(of: bothGreen) {
                    if bothGreen {
                        pulseRing = false
                        withAnimation(pulseAnimation) {
                            pulseRing = true
                        }
                    } else {
                        withAnimation(.none) {
                            pulseRing = false
                        }
                    }
                }
                .frame(height: DesignConstants.MapImage.imageHeight)
                .padding(.bottom)
            
            // Two overlaid circle‐buttons
            MapCircleButton(state: $circle1State)
                .frame(width: DesignConstants.MapImage.circleButtonSize,
                       height: DesignConstants.MapImage.circleButtonSize)
                .offset(DesignConstants.MapImage.circleOffset1)
            
            MapCircleButton(state: $circle2State)
                .frame(width: DesignConstants.MapImage.circleButtonSize,
                       height: DesignConstants.MapImage.circleButtonSize)
                .offset(DesignConstants.MapImage.circleOffset2)
            
            // Center pin
            Image("custom_pin")
                .resizable()
                .frame(width: DesignConstants.MapImage.pinSize.width,
                       height: DesignConstants.MapImage.pinSize.height)
        }
    }
    
    // MARK: Subviews
    
    // The animation used for the pulsing ring.
    private var pulseAnimation: Animation {
        Animation.easeInOut(duration: DesignConstants.MapImage.pulseAnimationDuration)
            .repeatCount(DesignConstants.MapImage.pulseRepeatCount, autoreverses: true)
    }
    
    // Shape and color of pulsing ring.
    private var pulseOverlay: some View {
        Circle()
            .stroke(
                Color.blue.opacity(currentPulseOpacity),
                lineWidth: DesignConstants.MapImage.pulseLineWidth
            )
            .scaleEffect(currentPulseScale)
    }

    private var currentPulseOpacity: Double {
        bothGreen
            ? (pulseRing
                ? DesignConstants.MapImage.pulseMaxOpacity
                : DesignConstants.MapImage.pulseMinOpacity)
            : DesignConstants.MapImage.pulseMinOpacity
    }

    private var currentPulseScale: CGFloat {
        bothGreen
            ? (pulseRing
                ? DesignConstants.MapImage.pulseMaxScale
                : DesignConstants.MapImage.pulseMinScale)
            : DesignConstants.MapImage.pulseOffScale
    }
}

struct MapImageView_Previews: PreviewProvider {
    static var previews: some View {
        MapImageView()
    }
}
