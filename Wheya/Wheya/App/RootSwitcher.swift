//
//  RootSwitcher.swift
//  Wheya
//
//  Created by Yuliia Murakami on 9/10/25.
//

import Foundation
import SwiftUI

//  Simple router: shows SignInView until logged in, then HomeView.
struct RootSwitcher: View {
    @Environment(Session.self) private var session
    // [Always-on design]
    @Environment(\.modelContext) private var modelContext
    @Environment(CloudKitManager.self) private var cloud
    @Environment(LocationSharingService.self) private var sharingService
    
    // [Always-on design]
    var body: some View {
            Group {
                if !session.isLoggedIn {
                    SignInView(session: session)
                } else {
                    HomeView()
                }
            }
            // When the login state / user id changes, wire up the service once.
            .task(id: session.appleUserID) {
                guard let uid = session.appleUserID else { return }
                sharingService.configureEnvironment(
                    modelContext: modelContext,
                    cloud: cloud,
                    currentUserID: uid
                )
                sharingService.startBaselineTracking()
            }
        }
}
