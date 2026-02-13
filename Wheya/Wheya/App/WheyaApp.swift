//
//  WheyaApp.swift
//  Wheya
//
//  Created by Hiromichi Murakami on 2025/06/28.
//

import SwiftUI
import SwiftData
import os.log

@main
struct WheyaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    @State private var session = Session()
    let cloud = CloudKitManager()
    
    // Local storage
    static var startupErrorKind: AppErrorKind?
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            CachedUserProfile.self,
            CachedMeeting.self,
            CachedAttendeeStatus.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
#if DEBUG
            fatalError("Could not create ModelContainer: \(error)")
#else
            os_log("ModelContainer init failed: %{public}@", type: .fault, String(describing: error))
            // Flag the error so UI can present the popup
            WheyaApp.startupErrorKind = .dataStoreInitFailed
            // Return an in-memory container so the app can show the popup.
            let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return try! ModelContainer(for: schema, configurations: [fallback])
#endif
        }
    }()
    
    init() {
        appDelegate.manager = cloud // This is needed for sharing
    }
    
    var body: some Scene {
        WindowGroup {
            RootSwitcher()
                .environment(session)
                .environment(cloud)
                .environment(LocationSharingService.shared)
                .errorPopup(
                    isPresented: .init(
                        get: { WheyaApp.startupErrorKind != nil },
                        set: { if !$0 { WheyaApp.startupErrorKind = nil } }
                    ),
                    title: AppErrorUI.content(for: .dataStoreInitFailed)?.title,
                    message: AppErrorUI.content(for: .dataStoreInitFailed)?.message ?? "",
                    actions: AppErrorUI.content(for: .dataStoreInitFailed)?.actions ?? [.cancel("Close")]
                )
        }
        .modelContainer(sharedModelContainer)
    }
}
