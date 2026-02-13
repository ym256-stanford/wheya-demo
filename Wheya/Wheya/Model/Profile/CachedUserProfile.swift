//
//  CachedUserProfile.swift
//  Wheya
//
//  Created by Yuliia Murakami on 9/10/25.
//

import Foundation
import SwiftData

// SwiftData cache for fast/offline UI.
// Treat CloudKit as the source of truth; this is just a mirror.
@Model
final class CachedUserProfile {
    @Relationship var attendances: [CachedAttendeeStatus]? = []
    
    var appleUserID: String = ""
    var displayName: String = ""
    var imageData: Data? = nil // store the raw image
    // When we last refreshed this cache from CloudKit
    var updatedAt: Date? = nil
    
    init(
        appleUserID: String = "",
        displayName: String = "",
        imageData: Data? = nil,
        // Use distantPast so the very first read looks "stale" until you upsert.
        updatedAt: Date = .distantPast
    ) {
        self.appleUserID = appleUserID
        self.displayName = displayName
        self.imageData = imageData
        self.updatedAt = updatedAt
    }
}

