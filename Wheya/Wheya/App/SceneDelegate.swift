//
//  SceneDelegate.swift
//  Wheya
//
//  Created by Yuliia Murakami on 8/2/25.
//

import UIKit
import CloudKit
import SwiftUI

// Handles CloudKit share-accept flows for both:
// - Live accept (app already in foreground): windowScene(_:userDidAcceptCloudKitShareWith:)
// - Cold-launch accept (app launched from a share URL): scene(_:willConnectTo:options:)
//
// After accepting, we delegate to CloudKitManager.shareAccepted(_:) which:
//   • checks iCloud account status
//   • accepts the share (if pending & not owner)
//   • fetches the root Meeting record
//   • posts .didAcceptSharedMeeting so SwiftUI can import and display
class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    // Helper to reuse the same CloudKitManager the app uses elsewhere.
    // Falls back to a fresh instance only if injection isn’t available.
    private func cloud() -> CloudKitManager {
        if let mgr = (UIApplication.shared.delegate as? AppDelegate)?.manager {
            return mgr
        }
        // Fallback: you could also decide to fatalError here during dev to catch wiring issues.
        return CloudKitManager()
    }
    
    // Called when the user accepts a CloudKit share while the app is already running.
    // Typical path: user taps the "Open" banner after previewing a CKShare in the system sheet.
    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {

        Task {
            do {
                // Use the shared manager so state (subscriptions, caches) is consistent app-wide.
                let model = cloud()
                try await model.shareAccepted(metadata) // Accept → fetch root → notify UI
            } catch {
                #if DEBUG
                print("❌ Failed to accept share: \(error)")
                #endif
            }
        }
    }

    // Called when creating/connecting a scene; on cold launch from a share URL,
    // `connectionOptions.cloudKitShareMetadata` is populated and we can accept immediately.
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let metadata = connectionOptions.cloudKitShareMetadata {
            Task {
                do {
                    let model = cloud()
                    try await model.shareAccepted(metadata) // Same path as live accept
                } catch {
                    #if DEBUG
                    print("❌ Failed to accept share on launch: \(error)")
                    #endif
                }
            }
        }
    }
}
