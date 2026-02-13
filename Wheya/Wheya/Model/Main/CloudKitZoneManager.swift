//
//  CloudKitZoneManager.swift
//  Wheya
//
//  Created by Yuliia Murakami on 7/31/25.
//

import CloudKit

//  Single-responsibility helper that locates and caches the custom CloudKit zones used
//  by the app:
//
//   • Private zone (owner writes meetings here)
//   • Shared zone (CloudKit auto-creates when a share is accepted)
//
//  Why a separate manager?
//   - Centralizes the logic for “find or create” + caching
//   - Avoids repeating zone discovery in multiple places
//   - Provides an explicit place to invalidate caches on server-side changes
//
//  Threading
//  ---------
//  This class is intentionally simple. If you call its methods from many concurrent places,
//  you can make it an `actor` to serialize access, or add a small in-flight guard.
//
class CloudKitZoneManager {
    // Singleton is fine here since it only caches small objects (zone references).
    static let shared = CloudKitZoneManager()

    // Databases we care about
    private let privateDB = CloudManager.privateDB
    private let sharedDB = CloudManager.sharedDB
    
    // In-memory caches (nil until first resolved)
    private var privateZone: CKRecordZone?
    private var sharedZone: CKRecordZone?
    
    // App-wide zone naming
    static let zoneName = CloudManager.meetingsZoneName

    // Returns the app’s custom **private** zone, creating it if needed.
    //
    // Call sites:
    //  - Creating/saving meetings (owner path)
    //  - Creating private-zone subscriptions
    //
    // Behavior:
    //  - Uses an in-memory cache to avoid repeated network calls
    //  - On “zone already exists” errors, fetches and caches the existing zone
    func getPrivateZone() async throws -> CKRecordZone {
        // 1) Use cache if we’ve already resolved the zone this run.
        if let cachedZone = privateZone {
            return cachedZone
        }
        
        // 2) Attempt to create the zone (idempotent; it might already exist).
        let zone = CKRecordZone(zoneName: Self.zoneName)
        
        do {
            let savedZone = try await privateDB.save(zone)
            self.privateZone = savedZone
            return savedZone
        } catch {
            #if DEBUG
            print("[getPrivateZone] Failed to save zone: \(error.localizedDescription)")
            #endif
            throw error
        }
    }
    
    // Returns the **shared** zone from the shared database, if available.
    //
    // When do we have a shared zone?
    //  - After the user accepts at least one share, CloudKit creates (and exposes) a zone
    //    in `sharedCloudDatabase`. There can be more than one across different owners,
    //    but this app assumes a single relevant one for your Meeting record type/name.
    //
    // Behavior:
    //  - Uses an in-memory cache
    //  - Discovers zones by listing `allRecordZones()` and picking the named match first,
    //    else falls back to the first available zone (useful if the owner used a different name)
    //  - Returns `nil` if there are no shared zones yet (i.e., no accepted shares)
    func getSharedZone() async throws -> CKRecordZone? {
        if let cachedZone = sharedZone {
            return cachedZone
        }
        
        // With single-owner assumption, there will be at most one relevant shared zone.
        // `allRecordZones()` is fine here; if none exist yet, you likely haven't accepted a share.
        let allZones = try await sharedDB.allRecordZones()
        
        if let matched = allZones.first(where: { $0.zoneID.zoneName == Self.zoneName }) {
            sharedZone = matched
        } else if let fallback = allZones.first {
            sharedZone = fallback
        } else {
            #if DEBUG
            print("[getSharedZone] No shared zones available yet. Have you accepted a share?")
            #endif
        }
        return sharedZone
    }
    
    // Clears the **shared zone** cache so the next call to `getSharedZone()` re-discovers it.
    //
    // Call this when:
    //  - You observe `CKError.zoneNotFound` querying the shared DB
    //  - `fetchChangesForSharedDBSubscription` reports the shared zone was deleted/purged/reset
    func invalidateSharedZoneCache() {
        #if DEBUG
        if let z = sharedZone {
            print("[invalidateSharedZoneCache] Invalidating shared zone cache (\(z.zoneID.zoneName))")
        } else {
            print("[invalidateSharedZoneCache] Shared zone cache already empty")
        }
        #endif
        sharedZone = nil
    }
}

// CloudKitZoneManager+Delete.swift
import CloudKit

extension CloudKitZoneManager {
    // Delete the app's private zone if it exists. Safe to call even if missing.
    func deletePrivateZoneIfExists() async throws {
        let db = CloudManager.privateDB
        let zoneID = CKRecordZone.ID(
            zoneName: Self.zoneName,                // e.g. "MeetingsZone"
            ownerName: CKCurrentUserDefaultName
        )
        do {
            try await db.deleteRecordZone(withID: zoneID)
        } catch let ck as CKError where ck.code == .zoneNotFound {
            // Already gone — fine.
        }
    }
}


