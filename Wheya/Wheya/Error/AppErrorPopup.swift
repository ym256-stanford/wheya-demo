//
//  AppErrorPopup.swift
//  Wheya
//
//  Created by Yuliia Murakami on 9/16/25.
//

import SwiftUI
import UIKit

/// What ErrorPopupView needs.
struct ErrorPopupContent {
    let title: String?
    let message: String
    let actions: [ErrorPopupAction]
}

enum AppErrorUI {
    /// Map an AppErrorKind to UI content for ErrorPopupView.
    /// Returns nil for cases where you don't want to show any popup.
    static func content(for kind: AppErrorKind) -> ErrorPopupContent? {
        switch kind {
        // No UI
        case .appleCanceled:
            return nil
        
        // Storage problems
        case .dataStoreInitFailed:
            return .init(
                title: "Storage Unavailable",
                message: """
                        We couldn’t open the local database, so the app can’t start.
                        This can happen if the device is low on storage, a migration failed,
                        or iCloud is restricted on this device.
                        """,
                actions: [
                    // Leave Retry to the app (so it can call your init function)
                    .default("Open Settings", { openSettings() }),
                    .cancel("Close")
                ]
            )
        
        // Sign-in problems
        case .appleUnknown, .authRevoked:
            return .init(
                title: "Sign-In Failed",
                message: (kind == .authRevoked)
                    ? "Your sign-in was revoked. Please sign in again."
                    : "We couldn’t sign you in. Please try again.",
                actions: [.cancel("Close")]
            )

        // iCloud account missing
        case .noICloud:
            return .init(
                title: "iCloud Required",
                message: "You’re not signed in to iCloud on this device.",
                actions: [
                    .default("Open iCloud Settings", { openSettings() }),
                    .cancel("Close")
                ]
            )

        // Transient network/service hiccups — you said “no UI” for these
        case .networkOffline,
             .rateLimited(_):
            return nil

        // iCloud quota
        case .quotaExceeded:
            return .init(
                title: "iCloud Storage Full",
                message: "Free up space in iCloud to continue.",
                actions: [.cancel("Close")]
            )

        // Data / assets / generic
        case .recordNotFound,
             .imageEncodingFailed,
             .imageTooLarge,
             .genericCloud,
             .generic:
            return .init(
                title: "Something Went Wrong",
                message: "We couldn’t complete that. Please try again.",
                actions: [.cancel("Close")]
            )
        }
    }

    static func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

