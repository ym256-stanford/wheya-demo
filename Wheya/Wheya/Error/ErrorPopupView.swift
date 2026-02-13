//
//  ErrorPopupView.swift
//  Wheya
//
//  Created by Yuliia Murakami on 9/16/25.
//

import SwiftUI

// MARK: - Public API

struct ErrorPopupAction: Identifiable {
    enum Role { case cancel, destructive, normal }
    let id = UUID()
    let title: String
    let role: Role
    let action: () -> Void

    static func cancel(_ title: String = "Close", _ action: @escaping () -> Void = {}) -> Self {
        .init(title: title, role: .cancel, action: action)
    }
    static func destructive(_ title: String, _ action: @escaping () -> Void) -> Self {
        .init(title: title, role: .destructive, action: action)
    }
    static func `default`(_ title: String, _ action: @escaping () -> Void) -> Self {
        .init(title: title, role: .normal, action: action)
    }
}

/// A custom alert-style popup that closely matches SwiftUI `.alert`.
struct ErrorPopupView: View {
    let title: String?
    let message: String
    /// Buttons are stacked vertically; place `.cancel` last for parity with Apple's default.
    let actions: [ErrorPopupAction]

    /// Dismiss is called when tapping outside OR when a cancel action is triggered.
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // Backdrop
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .transition(.opacity)
                .accessibilityHidden(true)

            // Alert Card
            VStack(spacing: 0) {
                // Content
                VStack(spacing: 8) {
                    if let title, !title.isEmpty {
                        Text(title)
                            .font(.headline.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .padding(.top, 18)
                            .padding(.horizontal, 16)
                    }

                    Text(message)
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider().opacity(0.35)

                // Buttons (stacked like the system alert on iPhone)
                VStack(spacing: 0) {
                    ForEach(actions) { action in
                        Button {
                            // run action first; if it's cancel-like, also dismiss
                            action.action()
                            if action.role == .cancel { onDismiss() }
                        } label: {
                            Text(action.title)
                                .font(action.role == .normal ? .body.weight(.semibold) : .body)
                                .foregroundStyle(foregroundStyle(for: action.role))
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .contentShape(Rectangle())

                        if action.id != actions.last?.id {
                            Divider().opacity(0.2)
                        }
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Color(.systemBackground))
            )
            .overlay(
                // Subtle border like the system alert
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(Color(.separator).opacity(0.25), lineWidth: 1)
            )
            .frame(maxWidth: 320)
            .shadow(color: .black.opacity(0.25), radius: 20, y: 6)
            .padding(.horizontal, 24)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
            .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
        }
        .onTapGesture {
            // Tap outside behaves like system: dismisses only if you have a cancel.
            if actions.contains(where: { $0.role == .cancel }) { onDismiss() }
        }
        .onAppear { impactLight() }
        .animation(.spring(response: reduceMotion ? 0.01 : 0.28, dampingFraction: 0.9), value: UUID())
    }

    private func foregroundStyle(for role: ErrorPopupAction.Role) -> Color {
        switch role {
        case .cancel: return Color.accentColor
        case .destructive: return Color.red
        case .normal: return Color.accentColor
        }
    }

    private func impactLight() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
}

// MARK: - Presenter Modifier (simple to use like .alert)

struct ErrorPopupPresenter<OverlayContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    let overlay: () -> OverlayContent

    func body(content: Content) -> some View {
        ZStack {
            content
            if isPresented {
                overlay()
                    .onDisappear { isPresented = false }
            }
        }
        .animation(.default, value: isPresented)
    }
}

extension View {
    /// Present an ErrorPopupView easily.
    func errorPopup(isPresented: Binding<Bool>,
                    title: String? = nil,
                    message: String,
                    actions: [ErrorPopupAction] = [.cancel()],
                    onDismiss: @escaping () -> Void = {}) -> some View {
        self.modifier(
            ErrorPopupPresenter(isPresented: isPresented) {
                ErrorPopupView(title: title, message: message, actions: actions) {
                    isPresented.wrappedValue = false
                    onDismiss()
                }
            }
        )
    }
}

// MARK: - Previews

#Preview("Generic Failure (1 button)") {
    ZStack {
        Color(.systemGroupedBackground).ignoresSafeArea()
        Text("Background")
    }
    .errorPopup(
        isPresented: .constant(true),
        title: "Sign-In Failed",
        message: "We couldn’t sign you in. Please try again.",
        actions: [
            .cancel("Close")
        ]
    )
}

#Preview("No iCloud (2 buttons)") {
    ZStack {
        Color(.systemGroupedBackground).ignoresSafeArea()
        Text("Background")
    }
    .errorPopup(
        isPresented: .constant(true),
        title: "iCloud Required",
        message: "You’re not signed in to iCloud on this device.",
        actions: [
            .default("Open iCloud Settings", {
                // open settings
            }),
            .cancel("Close")
        ]
    )
}
