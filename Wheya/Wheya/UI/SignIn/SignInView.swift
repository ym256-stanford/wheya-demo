//
//  SignInView.swift
//  Wheya
//
//  Created by Yuliia Murakami on 6/30/25.
//

import SwiftUI
import AuthenticationServices

struct SignInView: View {
    @Environment(Session.self) private var session
    @Environment(\.colorScheme) private var colorScheme
    @State private var model: SignInViewModel
    
    // Error handling
    @State private var showPopup = false
    @State private var popupTitle: String? = nil
    @State private var popupMessage: String = ""
    @State private var popupActions: [ErrorPopupAction] = [.cancel()]
    
    init(session: Session) {
        _model = State(initialValue: SignInViewModel(session: session))
    }

    var body: some View {
        VStack(spacing: 40) {
            Text("Wheya")
                .font(.largeTitle)
                .bold()
            
            MapImageView()
                .padding(.bottom)
            
            if model.isLoading {
                ProgressView("Signing in…")
            } else if session.appleUserID == nil {
                SignInWithAppleButton(
                    .signIn,
                    
                    onRequest: {
                        $0.requestedScopes = [.fullName]

                        // Clear any stale error so a previous popup can't resurface
                        model.errorKind = nil
                        model.errorMessage = nil
                    },
                    onCompletion: model.handleAppleSignIn)
                .id(colorScheme) // forces style refresh on scheme change
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 50)
                .disabled(model.isLoading) // #1 Debounce: prevent re-taps in-flight
                .allowsHitTesting(!model.isLoading) // extra safety against double taps
            } else {
                // We have a stored Apple ID: verify state and proceed
                ProgressView("Logging you in…")
                    .task { await model.recheckAuthorization() }
            }
        }
        .padding()
        .onChange(of: model.errorKind) { _, newKind in
            guard let kind = newKind,
                  let content = AppErrorUI.content(for: kind)
            else { return }     // nil means "don't show anything" (e.g., network hiccup)
            
            popupTitle = content.title
            popupMessage = content.message
            popupActions = content.actions
            showPopup = true
            
            // reset so the same error can trigger again later if needed
            model.errorKind = nil
        }
        .errorPopup(
            isPresented: $showPopup,
            title: popupTitle,
            message: popupMessage,
            actions: popupActions,
            onDismiss: { showPopup = false }
        )
    }
}

