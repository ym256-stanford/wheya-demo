//
//  CustomUIComponents.swift
//  MeetingUp
//
//  Created by Yuliia Murakami on 5/31/25.
//

import SwiftUI

// MARK: - Custom Components

// TextField - Insert user info
struct CustomTextField: View {
    var title: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    var autocapitalization: TextInputAutocapitalization = .never
    var isSecure: Bool = false

    var body: some View {
        Group {
            if isSecure {
                SecureField(title, text: $text)
                    .padding(DesignConstants.TextField.padding)
                    .font(DesignConstants.TextField.font)
            } else {
                TextField(title, text: $text)
                    .keyboardType(keyboardType)
                    .textInputAutocapitalization(autocapitalization)
                    .padding(DesignConstants.TextField.padding)
                    .font(DesignConstants.TextField.font)
            }
        }
        .frame(maxWidth: .infinity)
        .overlay(
            RoundedRectangle(cornerRadius: DesignConstants.TextField.cornerRadius)
                .stroke(DesignConstants.TextField.borderColor, lineWidth: DesignConstants.TextField.borderWidth)
        )
    }
}

// Button
struct CustomButton: View {
    var title: String
    var foregroundColor: Color? = DesignConstants.Button.foregroundColor
    var backgroundColor: Color? = DesignConstants.Button.backgroundColor
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(DesignConstants.Button.font)
                .foregroundColor(foregroundColor)
                .frame(maxWidth: .infinity, minHeight: DesignConstants.Button.height)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignConstants.Button.cornerRadius)
                        .stroke(DesignConstants.Button.borderColor, lineWidth: DesignConstants.Button.borderWidth)
                )
        }
        .background(backgroundColor)
        .buttonStyle(.plain)
    }
}

// Error Message
struct CustomErrorMessage: View {
    var message: String

    var body: some View {
        Text(message)
            .foregroundColor(DesignConstants.ErrorMessage.textColor)
            .font(DesignConstants.ErrorMessage.font)
            .multilineTextAlignment(.center)
            .padding(.horizontal, DesignConstants.ErrorMessage.padding)
    }
}

// Instruction Title
struct CustomInstruction: View {
    var text: String

    var body: some View {
        Text(text)
            .font(DesignConstants.Instruction.font)
            .foregroundColor(DesignConstants.Instruction.textColor)
            .multilineTextAlignment(.center)
    }
}

// Circle in Login page
enum CircleState: CaseIterable, Equatable {
    case waiting, cancel, green
    
    var imageName: String {
        switch self {
        case .waiting: return "waiting"
        case .cancel:  return "cancel"
        case .green:   return "green"
        }
    }
    
    // Returns a random CircleState that is not equal to `excluding`.
    static func random(excluding: CircleState?) -> CircleState {
        var choices = Self.allCases
        if let ex = excluding, let idx = choices.firstIndex(of: ex) {
            choices.remove(at: idx)
        }
        return choices.randomElement()!
    }
}

struct MapCircleButton: View {
    // `nil` means “neutral (empty)”; non‐nil is one of the 3 images.
    @Binding var state: CircleState?
    
    var body: some View {
        Button(action: toggleState) {
            if state == nil {
                // Initial “neutral” state
                Circle()
                    .fill(DesignConstants.MapImage.circleFillColor)
                    .frame(
                        width: DesignConstants.MapImage.circleButtonSize,
                        height: DesignConstants.MapImage.circleButtonSize
                    )
                    .overlay(Circle().stroke(Color.gray, lineWidth: 1))
            } else {
                // Show the current image (fill the circle)
                Image(state!.imageName)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(
                        width: DesignConstants.MapImage.circleButtonSize,
                        height: DesignConstants.MapImage.circleButtonSize
                    )
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.gray, lineWidth: 1))
            }
        }
    }
    
    private func toggleState() {
        state = CircleState.random(excluding: state)
    }
}

// MARK: - Design Constants

struct DesignConstants {
    struct General {
        static let cornerRadius: CGFloat = 16
        static let horizontalSpacing: CGFloat = 16
    }
    
    struct TextField {
        static let padding: CGFloat = 12
        static let cornerRadius: CGFloat = 6
        static let borderColor: Color = .black
        static let borderWidth: CGFloat = 1
        static let font: Font = .body
    }
    
    struct MessageInput {
        static let textEditorHeight: CGFloat = 70
        static let textEditorPadding: CGFloat = 8
        static let cornerRadius: CGFloat = 10
        static let textEditorBackground = Color.white.opacity(0.1)
        static let textEditorBorder = Color.gray.opacity(0.2)
        static let textEditorLineWidth: CGFloat = 1
    }
    
    struct Button {
        static let height: CGFloat = 47
        static let cornerRadius: CGFloat = 6
        static let borderColor: Color = .primary
        static let borderWidth: CGFloat = 2
        static let backgroundColor: Color = Color.gray.opacity(0.2)
        static let foregroundColor: Color = .primary
        static let font: Font = .system(size: 19, weight: .semibold)
    }
    
    struct ErrorMessage {
        static let textColor: Color = .red
        static let font: Font = .footnote
        static let padding: CGFloat = 12
    }
    
    struct Instruction {
        static let font: Font = .system(size: 19, weight: .semibold)
        static let textColor: Color = .primary
    }
    
    struct ProfilePicture {
        static let size: CGFloat = 120
        static let borderWidth: CGFloat = 1
        static let borderColor: Color = .gray
        static let defaultImageName: String = "person.crop.circle.fill"
        static let defaultImageColor: Color = .gray
        static let shadowRadius: CGFloat = 0
        
        // Camera overlay
        static let cameraPadding: CGFloat = 8
        static let cameraOpacity: Double = 0.5
        static let cameraOffset: CGFloat = 5
        static let cameraShadow: CGFloat = 2
    }
    
    struct imageThumbnail {
        static let maxImages = 5
        static let spacing: CGFloat = 16
        static let textFieldCornerRadius: CGFloat = 8
        static let textFieldPaddingVertical: CGFloat = 8
        static let textFieldPaddingHorizontal: CGFloat = 12
        static let thumbnailSize: CGFloat = 60
        static let thumbnailCornerRadius: CGFloat = 8
        static let thumbnailPadding: CGFloat = 4
        static let scrollPadding: CGFloat = 4
        // Delete button
        static let overlayStrokeColor: Color = Color.gray.opacity(0.3)
        static let overlayLineWidth: CGFloat = 1
        static let deleteButtonBackground: Color = Color.black.opacity(0.6)
        static let deleteButtonOffset: CGSize = CGSize(width: 4, height: -4)
    }
    
    struct MapImage {
        static let imageHeight: CGFloat = 200
        static let imageCornerRadius: CGFloat = 12
        
        static let pulseLineWidth: CGFloat = 4
        static let pulseMinOpacity: Double = 0.0
        static let pulseMaxOpacity: Double = 0.6
        static let pulseAnimationDuration: Double = 1
        static let pulseRepeatCount: Int = 11
        
        static let pulseOffScale: CGFloat = 0
        static let pulseMinScale: CGFloat = 1.0
        static let pulseMaxScale: CGFloat = 1.2
        
        static let circleFillColor: Color = Color.white.opacity(0.7)
        static let circleButtonSize: CGFloat = 44
        static let circleStrokeWidth: CGFloat = 1
        static let circleOffset1 = CGSize(width: -60, height: -55)
        static let circleOffset2 = CGSize(width:  60, height:  45)
        
        static let pinSize = CGSize(width: 64, height: 64)
    }
}

/// LiveMeeting 画面で使う共通レイアウト値（意味のある数だけ集約）
enum LiveMeetingConstants {
    // 地図リージョン計算
    static let regionPadding: CGFloat = 1.5   // 表示範囲に持たせる余白倍率（>1で広め）
    static let minDelta: Double = 0.001       // ズームしすぎ防止の最小スパン

    // 画面全体
    static let vStackSpacing: CGFloat = 16    // セクション間の縦スペース
    static let titleTopPadding: CGFloat = 16  // タイトル上の余白

    // Map 表示
    static let mapHeight: CGFloat = 300       // 地図の高さ（pt）
    static let mapCornerRadius: CGFloat = 12  // 地図カードの角丸

    // 会場ピン（Meetingロケーション）
    static let pinSize: CGFloat = 70          // ピン画像サイズ（正方形）
    static let pinOffsetY: CGFloat = -20      // ピン先端を座標に合わせるオフセット

    // 参加者アバター
    static let attendeeSize: CGFloat = 64     // 参加者アイコンの直径
    static let attendeeStroke: CGFloat = 3    // アバター外枠の太さ
    static let placeholderSize: CGFloat = 50  // 画像なし時のプレースホルダー直径

    // ETA バッジ（到着予想到）
    static let etaSpacing: CGFloat = 1        // バッジ内の要素間隔
    static let etaPadding: CGFloat = 4        // バッジ内パディング
    static let etaCornerRadius: CGFloat = 8   // バッジ角丸

    // 情報セクション（住所・日時・メモなど）
    static let infoSpacing: CGFloat = 6       // 行間の縦スペース


    static let messagesHPadding: CGFloat = 8
    static let messagesTPadding: CGFloat = 8
    static let animationDuration: Double = 0.5
    static let infoFontSize: CGFloat = 16

    static let buttonSpacing: CGFloat = 12
    static let buttonPadding: CGFloat = 8
    static let buttonCornerRadius: CGFloat = 8
    static let buttonStrokeWidth: CGFloat = 1
    static let buttonFontSize: CGFloat = 18
    static let buttonBottomPadding: CGFloat = 8
    static let grayOpacity: Double = 0.5

    static let messageRowSpacing: CGFloat = 16
    static let viewMoreTop: CGFloat = 4
}
