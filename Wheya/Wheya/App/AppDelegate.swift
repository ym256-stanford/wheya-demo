//
//  AppDelegate.swift
//  Wheya
//
//  Created by Yuliia Murakami on 8/2/25.
//

import UIKit
import CloudKit

// UIKit delegate that wires up:
// - SceneDelegate for CloudKit share acceptance
// - Remote notification registration
// - Handling CloudKit push notifications that reflect:
//    • shared DB changes (others’ meetings)
//    • query subscription changes (owner’s selected meeting)
//    • private zone changes (anything in your zone, e.g. AttendeeStatus)
class AppDelegate: NSObject, UIApplicationDelegate {
    // Injected from App so this is non-nil at launch.
    // Holds all CloudKit logic & subscriptions.
    var manager: CloudKitManager!
    
    // Ensures we use SceneDelegate so share-accept flows work on iOS.
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }

    // Handles remote CloudKit notifications while the app is **active**.
    // We intentionally skip background handling for now to avoid doing work while not in foreground.
    @MainActor
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        
        // Skip if not active — we only want real-time updates while using the app
        if application.applicationState != .active {
            return .newData // fetch changes to my view in background
            //return .noData
        }
        
        guard let notification = CKNotification(fromRemoteNotificationDictionary: userInfo) else {
            return .noData
        }
        
        // Handle shared database changes (meetings owned by others)
        if notification.notificationType == .database,
           notification.subscriptionID == CloudManager.sharedCloudDatabaseSubscriptionId {
            Task {
                do {
                    try await manager.fetchChangesForSharedDBSubscription()
                } catch {
#if DEBUG
                    print("[AppDelegate] Error fetching shared DB changes: \(error)")
#endif
                }
            }
        }
        
        // Handle query subscription changes
        if notification.notificationType == .query,
           notification.subscriptionID == CloudManager.privateDatabaseQuerySubscriptionId,
           let queryNotification = notification as? CKQueryNotification {
            Task {
                do {
                    try await manager.fetchChangesForQuerySubscription(queryNotification)
                } catch {
#if DEBUG
                    print("[AppDelegate] Error fetching query subscription changes: \(error)")
#endif
                }
            }
        }
        
        // Private zone changes (any record in your zone, e.g., AttendeeStatus image/name)
        if notification.notificationType == .recordZone,
           notification.subscriptionID == CloudManager.privateZoneSubscriptionId {
            Task {
                do {
                    try await manager.fetchChangesForPrivateZoneSubscription()
                } catch {
#if DEBUG
                    print("[AppDelegate] Error fetching private zone changes: \(error)")
#endif
                }
            }
            return .newData
        }
        
        return .newData
    }

    // Called when the app launches:
    // - Register for remote notifications
    // - Create/ensure CloudKit subscriptions:
    //     • shared database subscription (so we learn about shared-zone changes)
    //     • private zone subscription (so owner sees participant edits)
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        application.registerForRemoteNotifications()
        
        Task {
            do {
                try await manager.addSharedDatabaseSubscription()
                await manager.addPrivateZoneSubscription()
            } catch {
#if DEBUG
                print("[AppDelegate] Could not register shared DB subscription: \(error)")
#endif
            }
        }
        
        // [Always-on design] iOS can relaunch your app for location and your sharing logic wakes up automatically
        LocationSharingService.shared.startBaselineTracking()
        if launchOptions?[.location] != nil {
            LocationSharingService.shared.resumeAfterLocationRelaunch()
        }
        
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        #if DEBUG
        print("[AppDelegate] Failed to register for remote notifications: \(error)")
        #endif
    }
}
