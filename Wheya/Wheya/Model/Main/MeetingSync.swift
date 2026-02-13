//
//  MeetingSync.swift
//  Wheya
//
//  Created by Yuliia Murakami on 9/10/25.
//

import Foundation
import SwiftData
import CloudKit
import Observation

@Observable
@MainActor
final class MeetingSync {
    private let cache: ModelContext
    private let cloud: CloudKitManager
    
    init(cache: ModelContext, cloud: CloudKitManager) {
        self.cache = cache
        self.cloud = cloud
    }
    
    // MARK: - User
    // Upsert a CachedUserProfile by appleUserID.
    // - If sourceIsCloud == true and isSelf == true, we DO NOT overwrite an existing local image.
    // - For everyone else, we overwrite if image changes (as before).
    @discardableResult
    func upsertUser(
        appleUserID: String,
        displayName: String?,
        imageData: Data?,
        cloudUpdatedAt: Date?,
        sourceIsCloud: Bool,
        isSelf: Bool = false
    ) -> CachedUserProfile {
        let fd = FetchDescriptor<CachedUserProfile>(
            predicate: #Predicate { $0.appleUserID == appleUserID }
        )
        
        let user = (try? cache.fetch(fd))?.first ?? {
            // For a brand-new row, stamp updatedAt from the source
            let initialTS = sourceIsCloud ? (cloudUpdatedAt ?? .distantPast) : Date()
            let u = CachedUserProfile(
                appleUserID: appleUserID,
                displayName: displayName ?? "",
                imageData: imageData,
                updatedAt: initialTS
            )
            cache.insert(u)
            return u
        }()
        
        let cloudTS = cloudUpdatedAt ?? .distantPast
        let localTS = user.updatedAt ?? .distantPast
        
        if sourceIsCloud {
            // Only accept cloud data if it is strictly newer than the cache
            if cloudTS > localTS {
                if let name = displayName { user.displayName = name }
                if let bytes = imageData { user.imageData = bytes } // skip nil from cloud
                user.updatedAt = cloudTS
            }
        } else {
            // Local edits always win and bump timestamp
            if let name = displayName { user.displayName = name }
            // allow nil to clear locally (user removed their photo)
            user.imageData = imageData
            user.updatedAt = Date()
        }
        
        return user
    }
    
    // Push the current user's latest profile (name/image) to *all* meetings they appear in.
    // - Only touches that single user's attendee row per meeting (no accidental overwrites of others).
    // - Picks the right DB (private/shared) using the meeting's zone owner via upsertAttendeeStatus().
    @MainActor
    func pushMyProfileToAllMeetings(
        currentUserID: String,
        displayName: String?,
        imageData: Data?
    ) async {
        do {
            // 1) Pull *all* cached meetings where we have a CloudKit record ID.
            let descriptor = FetchDescriptor<CachedMeeting>()
            let allMeetings = try cache.fetch(descriptor)
            let eligible = allMeetings.compactMap { m -> (CachedMeeting, CKRecord.ID)? in
                guard let rid = m.ckRecordID else { return nil }
                // We’ll only push if this user is in the attendee list
                guard let rows = m.attendees,
                      rows.contains(where: { $0.user?.appleUserID == currentUserID }) else { return nil }
                return (m, rid)
            }
            
            for (meeting, rid) in eligible {
                // Find THIS user's attendee row to carry the organizer flag
                let organizer = meeting.attendees?.first(where: { $0.user?.appleUserID == currentUserID })?.organizer ?? false
                do {
                    _ = try await cloud.upsertAttendeeStatus(
                        forMeetingRecordID: rid,
                        appleUserID: currentUserID,
                        displayName: (displayName?.isEmpty == false ? displayName : nil),
                        imageData: imageData,
                        organizer: organizer,
                        here: nil,
                        latitude: nil,
                        longitude: nil,
                        etaMinutes: nil,
                        deleted: nil
                    )
                } catch {
                    #if DEBUG
                    print("[ProfileSync] Failed pushing to meeting \(rid.recordName): \(error)")
                    #endif
                }
            }
        } catch {
            #if DEBUG
            print("[ProfileSync] Couldn’t enumerate cached meetings: \(error)")
            #endif
        }
    }
    
    // MARK: - Meeting
    // Create draft in cache -> attach user -> CloudKit upsert -> cache update
    @discardableResult
    func createMeeting(
        title: String,
        date: Date,
        locationName: String,
        latitude: Double,
        longitude: Double,
        notes: String,
        shareMinutes: Int,
        appleUserID: String?,
        displayName: String?,
        imageData: Data?
    ) async -> CachedMeeting? {
        let draft = CachedMeeting.makeLocalDraft(
            title: title,
            date: date,
            locationName: locationName,
            latitude: latitude,
            longitude: longitude,
            notes: notes,
            isOwner: true,
            shareMinutes: shareMinutes
        )
        cache.insert(draft)
        attachUser(appleUserID: appleUserID,
                   displayName: displayName,
                   imageData: imageData,
                   to: draft,
                   organizer: true,
                   isSelf: true, // you’re attaching the signed-in user
                   sourceIsCloud: false // local action
        )
        try? cache.save()
        _ = await upsertMeetingFromCached(draft)
        return draft
    }
    
    // Upsert a meeting to CloudKit from a CachedMeeting row.
    // - Behavior: cache → CloudKit → cache
    // On success, marks the cached row clean and stores the CloudKit recordName.
    // On failure, leaves the cached row dirty for a future retry.
    @discardableResult
    func upsertMeetingFromCached(_ cached: CachedMeeting) async -> Meeting? {
        // Shared items never push to CloudKit
        if cached.isOwner == false {
            cached.isDirty = false
            try? cache.save()
            return nil
        }
        
        // Save current meeting to cache
        try? cache.save()
        
        // If we don't have a CK identity yet → CREATE
        if cached.ckRecordID == nil {
            let createCandidate = Meeting(
                recordID: nil,
                createdAt: cached.createdAt,
                title: cached.title,
                date: cached.date,
                locationName: cached.locationName,
                latitude: cached.latitude,
                longitude: cached.longitude,
                notes: cached.notes,
                shareMinutes: cached.shareMinutes
            )
            do {
                let created = try await cloud.addMeeting(createCandidate)
                if let rid = created.recordID { cached.updateIdentity(from: rid) }
                cached.title = created.title
                cached.createdAt = created.createdAt
                cached.isDirty = false
                try? cache.save()
        
                if let rid = created.recordID {
                    await cloud.pushAttendeesToCloud(for: cached, meetingRecordID: rid, currentUserID: nil) // owner path
                    
                    await cloud.pushMessagesToCloud(for: cached, meetingRecordID: rid, currentUserID: nil)
                }
                return created
            } catch {
                #if DEBUG
                print("[Sync] CREATE failed:", error.localizedDescription)
                #endif
                cached.isDirty = true; try? cache.save()
                return nil
            }
        }
        
        // Otherwise → UPDATE, and if unknown item/zone not found, fallback to CREATE
        let updateCandidate = Meeting(
            recordID: cached.ckRecordID,
            createdAt: cached.createdAt,
            title: cached.title,
            date: cached.date,
            locationName: cached.locationName,
            latitude: cached.latitude,
            longitude: cached.longitude,
            notes: cached.notes,
            shareMinutes: cached.shareMinutes
        )
        do {
            try await cloud.updateMeeting(editedMeeting: updateCandidate)
            cached.isDirty = false
            try? cache.save()
           
            if let rid = updateCandidate.recordID {
                await cloud.pushAttendeesToCloud(for: cached, meetingRecordID: rid, currentUserID: nil) // owner path
                await cloud.pushMessagesToCloud(for: cached, meetingRecordID: rid, currentUserID: nil)
            }
            return updateCandidate
        } catch let e as CKError where e.code == .unknownItem || e.code == .zoneNotFound {
            
            do {
                let created = try await cloud.addMeeting(updateCandidate) // CKM will re-home zone + assign ID
                if let rid = created.recordID { cached.updateIdentity(from: rid) }
                cached.title = created.title
                cached.createdAt = created.createdAt
                cached.isDirty = false
                try? cache.save()
                return created
            } catch {
                cached.isDirty = true; try? cache.save()
                return nil
            }
        } catch {
            #if DEBUG
            print("[Sync] UPDATE failed:", error.localizedDescription)
            #endif
            cached.isDirty = true; try? cache.save()
            return nil
        }
    }
    
    // Delete meeting from cache.
    // - if `cached.isOwner == true` and the record is in your private DB → delete in CloudKit + remove locally
    // - otherwise → remove locally only
    @discardableResult
    func deleteCached(_ cached: CachedMeeting, currentUserID: String) async -> Bool {
        if cached.isOwner {
            // Owner: delete in CloudKit + remove locally
            do {
                if let rid = cached.ckRecordID {
                    _ = try await cloud.deleteMeeting(recordID: rid)
                }
            } catch {
                #if DEBUG
                print("[deleteCached] Cloud delete failed (will delete locally): \(error)")
                #endif
            }
            cache.delete(cached)
            do { try cache.save(); return true } catch {
                #if DEBUG
                print("Local delete save failed: \(error)")
                #endif
                return false
            }
        } else {
            // Participant: local-only hide (don’t do the server refetch)
            cached.isHidden = true
            // Flip my attendee row to here=true to stop sharing
            if let myRow = (cached.attendees ?? []).first(where: { $0.user?.appleUserID == currentUserID }) {
                myRow.markDeleted(at: Date())
            }
            try? cache.save()
            if let rid = cached.ckRecordID {
                // Then push just my attendee row with deleted=true
                _ = try? await cloud.upsertAttendeeStatus(
                    forMeetingRecordID: rid,
                    appleUserID: currentUserID,
                    displayName: nil,
                    imageData: nil,
                    organizer: false,
                    here: true,
                    latitude: 0,
                    longitude: 0,
                    etaMinutes: nil,
                    deleted: true
                )
            }
            do {
                try cache.save()
                return true
            } catch {
                #if DEBUG
                print("[Sync] Failed to save hidden flag: \(error)")
                #endif
                return false
            }
        }
    }
    
    // Remove (reconcile) local shared rows that no longer exist on the server.
    func removeMeetings(with fetched: [CKRecord], isOwner: Bool) {
        // Build a set of server-side globalIDs we want to KEEP
        let keep = Set(fetched.map { $0.globalID })
        
        // Fetch all private (isOwner == true) meetings from SwiftData or
        // Fetch all shared (isOwner == false) meetings from SwiftData
        let fd = FetchDescriptor<CachedMeeting>(
            predicate: #Predicate { $0.isOwner == isOwner }
        )
        
        do {
            let localShared = try cache.fetch(fd)
            
            for row in localShared {
                if let gid = row.globalID, keep.contains(gid) == false {
                    if isOwner {
                        cache.delete(row)            // owner can purge immediately
                    } else {
                        row.isHidden = true          // participant: hide to avoid tearing objects mid-render
                        // Optional: stop UI pokes immediately
                        row.attendees = [] ; row.messages = []
                    }

                }
            }
            
            try cache.save()
        } catch {
            #if DEBUG
            print("❌ [Sync] Reconcile failed: \(error)")
            #endif
        }
    }
    
    // Reconcile both private and shared meetings.
    @MainActor
    func removeMeetings(private privateRecords: [CKRecord], shared sharedRecords: [CKRecord]) {
        removeMeetings(with: privateRecords, isOwner: true)
        removeMeetings(with: sharedRecords,  isOwner: false)
    }
}

// MARK: - Shared meetings
extension MeetingSync {
    // Imports a single **shared** record into SwiftData.
    // - Important: This is a **cache-only** operation: it never writes back to CloudKit.
    //   We treat shared data as coming from the owner, so participants should not push edits upstream.
    // - Returns: The upserted `CachedMeeting` row.
    @discardableResult
    func importSharedMeeting(from record: CKRecord) -> CachedMeeting? {
        upsertCachedFromCloud(record: record, isOwner: false)
    }
    
    // Bulk-imports meetings (either private or shared) into SwiftData.
    // - Parameters:
    //   - records: Array of CloudKit records fetched from either the private DB or the shared DB.
    //   - isOwner: Pass `true` when importing from the private database (you created the meetings),
    //              and `false` when importing from the shared database (meetings owned by others).
    //
    // Notes:
    // - This method performs an **idempotent upsert** per record:
    //   it will insert if missing, or update the existing cached row if present.
    // - We defer `save()` until after the loop to minimize persistence overhead.
    func importMeetings(from records: [CKRecord], isOwner: Bool) {
        for record in records { _ = upsertCachedFromCloud(record: record, isOwner: isOwner) }
        try? cache.save()
    }
    
    // Inserts or updates a single cached meeting row from a CloudKit record.
    //
    // Flow:
    // 1) Convert the CloudKit `CKRecord` into your value-type `Meeting` model.
    // 2) Find an existing `CachedMeeting` by its **globalID** (stable across zones/devices).
    //    - We use `globalID` (string) instead of raw `recordID` for two reasons:
    //      a) Shared vs private zones produce different recordID scopes/names.
    //      b) String predicates compile cleanly in SwiftData and are portable.
    // 3) Create the row if it doesn't exist (insert), otherwise update it (update).
    // 4) Copy fields from `Meeting` to `CachedMeeting`, and mark `isDirty = false`
    //    because the source of truth is CloudKit (not a local, unsynced edit).
    // 5) Store Cloud identity info via `updateIdentity(from:)` so future operations
    //    (e.g., deletes, owner-specific actions) know how to address the record.
    //
    // - Parameters:
    //   - record: The CloudKit record representing a meeting.
    //   - isOwner: Whether this device/user is the **owner** of the meeting.
    // - Returns: The upserted `CachedMeeting` (or `nil` if the record couldn't be parsed).
    @discardableResult
    private func upsertCachedFromCloud(record: CKRecord, isOwner: Bool) -> CachedMeeting? {
        // Map CKRecord → your Meeting value type
        guard let meeting = Meeting(record: record) else { return nil }
        
        let gid = record.globalID
        
        // Always match by globalID (string) because it is unique
        let fd = FetchDescriptor<CachedMeeting>(predicate: #Predicate { $0.globalID == gid })
        let existing = (try? cache.fetch(fd))?.first
        
        let row = existing ?? {
            let cachedMeeting = CachedMeeting()
            cache.insert(cachedMeeting)
            return cachedMeeting
        }()
        
        // Fill/update fields
        row.title = meeting.title
        row.createdAt = meeting.createdAt
        row.date = meeting.date
        row.locationName = meeting.locationName
        row.latitude = meeting.latitude
        row.longitude = meeting.longitude
        row.notes = meeting.notes
        row.isOwner = isOwner
        row.shareMinutes = meeting.shareMinutes
        row.isDirty = false
        
        // Persist Cloud identity & globalID (owner::zone::name)
        row.updateIdentity(from: record.recordID)
        
        // If we just inserted, save now so other import paths can “see” it
        if existing == nil {
            try? cache.save()
        }
        
        return row
    }
}

// MARK: - Attendees
extension MeetingSync {
    // Ensure a single attendee row exists for (meeting, user). Optionally mark organizer.
    func ensureAttendee(meeting: CachedMeeting, user: CachedUserProfile, organizer: Bool) {
        // meeting.attendees is optional (CloudKit mirroring), defaulted to []
        if let existing = (meeting.attendees ?? []).first(where: { $0.user?.appleUserID == user.appleUserID }) {
            if organizer && existing.organizer == false { existing.organizer = true }
            return
        }
        
        let status = CachedAttendeeStatus()
        status.meeting = meeting
        status.user = user
        status.organizer = organizer
        cache.insert(status)
    }
    
    // Attach a user to a meeting (as organizer or guest) and save once.
    // Safe to call when user info hasn't loaded yet — it just no-ops if `appleUserID` is nil/empty.
    func attachUser(
        appleUserID: String?,
        displayName: String?,
        imageData: Data?,
        to meeting: CachedMeeting,
        organizer: Bool,
        isSelf: Bool = false,
        sourceIsCloud: Bool = false
    ) {
        // Require an ID to create/link a profile
        guard let id = appleUserID, !id.isEmpty else { return }

        // Upsert the profile in the same ModelContext
        let user = upsertUser(
            appleUserID: id,
            displayName: displayName,
            imageData: imageData,
            cloudUpdatedAt: nil,
            sourceIsCloud: sourceIsCloud, // tell upsert where this came from
            isSelf: isSelf // and whether this is the signed-in user)
        )
        // Ensure a single attendee row for (meeting, user); "upgrade" to organizer if asked
        ensureAttendee(meeting: meeting, user: user, organizer: organizer)
        
        try? cache.save()
    }
    
    // Import attendees for one meeting from CloudKit and mirror into SwiftData.
    // - Parameters:
    //   - cached: the local CachedMeeting row you already upserted
    //   - meetingRecordID: CKRecord.ID of the Meeting
    //   - isOwner: true = read from privateDB, false = read from sharedDB
    func importAttendeesFromCloud(
        for cached: CachedMeeting,
        meetingRecordID: CKRecord.ID,
        isOwner: Bool,
        currentUserID: String? = nil
    ) async {
        // Local helpers for robust CKRecord reads
        func boolOpt(_ rec: CKRecord, _ key: String) -> Bool? {
            if let n = rec[key] as? NSNumber { return n.boolValue }
            return rec[key] as? Bool
        }
        func dbl(_ rec: CKRecord, _ key: String) -> Double {
            if let n = rec[key] as? NSNumber { return n.doubleValue }
            return rec[key] as? Double ?? 0
        }
        func intOpt(_ rec: CKRecord, _ key: String) -> Int? {
            if let n = rec[key] as? NSNumber { return n.intValue }
            return rec[key] as? Int
        }

        do {
            let rows = try await cloud.fetchAttendeeStatusRecords(
                for: meetingRecordID,
                useSharedDB: !isOwner
            )

            var imported = 0

            for r in rows {
                // --- Required identity fields ---
                guard let uid = r[CloudKitManager.AttendeeKeys.appleUserID] as? String,
                      !uid.isEmpty
                else { continue }

                let displayName = r[CloudKitManager.AttendeeKeys.displayName] as? String

                // Organizer can be NSNumber or Bool
                let isOrganizer =
                    (r[CloudKitManager.AttendeeKeys.organizer] as? NSNumber)?.boolValue ??
                    (r[CloudKitManager.AttendeeKeys.organizer] as? Bool) ?? false

                // Flags as optionals (nil = key absent)
                let incomingHereOpt    = boolOpt(r, CloudKitManager.AttendeeKeys.here)
                let incomingDeletedOpt = boolOpt(r, CloudKitManager.AttendeeKeys.deleted)

                // Field-level timestamps
                let hereTS     = r[CloudKitManager.AttendeeKeys.hereUpdatedAt] as? Date
                let deletedTS  = r[CloudKitManager.AttendeeKeys.deletedUpdatedAt] as? Date

                // Record-level timestamp (fallback)
                let cloudTS =
                    (r[CloudKitManager.AttendeeKeys.updatedAt] as? Date) ??
                    (r.modificationDate ?? .distantPast)

                // Image: prefer asset; fall back to inline
                var imageBytes: Data? = nil
                if let asset = r[CloudKitManager.AttendeeKeys.imageAsset] as? CKAsset,
                   let url = asset.fileURL {
                    imageBytes = try? await withCheckedThrowingContinuation { cont in
                        DispatchQueue.global(qos: .userInitiated).async {
                            do { cont.resume(returning: try Data(contentsOf: url)) }
                            catch { cont.resume(throwing: error) }
                        }
                    }
                } else if let inline = r[CloudKitManager.AttendeeKeys.imageData] as? Data {
                    imageBytes = inline
                }

                // Loc/ETA
                let latitude  = dbl(r, CloudKitManager.AttendeeKeys.latitude)
                let longitude = dbl(r, CloudKitManager.AttendeeKeys.longitude)
                let eta       = intOpt(r, CloudKitManager.AttendeeKeys.etaMinutes)

                // Self flag (used only for user upsert semantics)
                let isSelf = (currentUserID != nil && currentUserID == uid)

                // --- Upsert user profile (name/photo) gated by LWW at profile level ---
                let user = upsertUser(
                    appleUserID: uid,
                    displayName: displayName,
                    imageData: imageBytes,
                    cloudUpdatedAt: cloudTS,
                    sourceIsCloud: true,
                    isSelf: isSelf
                )

                // --- Ensure attendee row exists & set organizer if needed ---
                ensureAttendee(meeting: cached, user: user, organizer: isOrganizer)

                // --- Apply flags using per-field timestamps (with true-wins for deleted) ---
                if let row = (cached.attendees ?? []).first(where: { $0.user?.appleUserID == uid }) {
                    row.organizer = isOrganizer

                    // HERE: apply only if incoming hereTS is newer than local hereUpdatedAt.
                    // Monotonic: once true, always true (ignore incoming false).
                    if let ts = hereTS, ts > (row.hereUpdatedAt ?? .distantPast) {
                        row.here = row.here || (incomingHereOpt ?? false)
                        row.hereUpdatedAt = ts
                    } else if hereTS == nil, incomingHereOpt == true {
                        // Seeding from record-level timestamp
                        if cloudTS > (row.hereUpdatedAt ?? .distantPast) {
                            row.here = true
                            row.hereUpdatedAt = cloudTS
                        }
                    }

                    // DELETED: true-wins. Use helper so it's sticky + stops sharing immediately.
                    if incomingDeletedOpt == true {
                        row.markDeleted(at: deletedTS ?? cloudTS)
                    }
                    
                    // Coordinates/ETA normalization
                    if row.here || row.deleted {
                        row.latitude = 0
                        row.longitude = 0
                        row.etaMinutes = nil
                    } else {
                        row.latitude  = latitude
                        row.longitude = longitude
                        row.etaMinutes = eta
                    }
                }

                imported += 1
            }

            try? cache.save()
        } catch {
            #if DEBUG
            print("[Sync] Attendee import failed:", error.localizedDescription)
            #endif
        }
    }



    // Convenience for many meetings: matches by globalID and imports for each record.
    func fetchAndImportAttendees(
        for meetingRecords: [CKRecord],
        isOwner: Bool,
        currentUserID: String?
    ) async {
        for rec in meetingRecords {
            let gid = rec.globalID
            let fd  = FetchDescriptor<CachedMeeting>(predicate: #Predicate { $0.globalID == gid })
            guard let cached = try? cache.fetch(fd).first else {
                continue
            }
            await importAttendeesFromCloud(for: cached, meetingRecordID: rec.recordID, isOwner: isOwner, currentUserID: currentUserID)
        }
    }
}

// MARK: - Messages
extension MeetingSync {
    // Import messages for one meeting from CloudKit
    func importMessagesFromCloud(
        for cached: CachedMeeting,
        meetingRecordID rid: CKRecord.ID,
        isOwner: Bool
    ) async {
        do {
            let rows = try await cloud.fetchMessageRecords(for: rid, useSharedDB: !isOwner)
            
            var imported = 0
            for r in rows {
                let uid   = r[CloudKitManager.MessageKeys.appleUserID] as? String ?? ""
                let name  = r[CloudKitManager.MessageKeys.displayName] as? String ?? ""
                let text  = r[CloudKitManager.MessageKeys.text]        as? String ?? ""
                guard !text.isEmpty else { continue }
                let ts    = (r[CloudKitManager.MessageKeys.timestamp]  as? Date)
                ?? (r.creationDate ?? .distantPast)
                
                // Upsert by globalID so we don't duplicate across devices
                let gid = r.recordID.globalID
                let fd = FetchDescriptor<CachedMessage>(predicate: #Predicate<CachedMessage> {
                    $0.globalID == gid
                })
                let row = (try? cache.fetch(fd))?.first ?? {
                    let m = CachedMessage()
                    m.meeting = cached
                    cache.insert(m)
                    return m
                }()
                
                row.senderAppleUserID = uid
                row.senderDisplayName = name
                row.text = text
                row.timestamp = ts
                row.updateIdentity(from: r.recordID)
                row.isDirty = false
                imported += 1
            }
            
            try? cache.save()
        } catch {
            #if DEBUG
            print("[Sync] fetchMessageRecords failed:", error.localizedDescription)
            #endif
        }
    }
    
    func fetchAndImportMessages(
        for meetingRecords: [CKRecord],
        isOwner: Bool
    ) async {
        for rec in meetingRecords {
            let gid = rec.globalID
            let fd  = FetchDescriptor<CachedMeeting>(predicate: #Predicate { $0.globalID == gid })
            guard let cached = try? cache.fetch(fd).first else {
                continue
            }
            await importMessagesFromCloud(for: cached, meetingRecordID: rec.recordID, isOwner: isOwner)
        }
    }
}

// MARK: - Debug

extension MeetingSync {
    /// Removes extra local rows that share the same globalID. Keeps the richest row.
    func purgeDuplicateLocalMeetings() {
        do {
            let all = try cache.fetch(FetchDescriptor<CachedMeeting>())
            let byGID = Dictionary(grouping: all, by: { $0.globalID ?? "nil:\($0.id)" })
            for (_, group) in byGID {
                guard group.count > 1 else { continue }
                // Prefer one that has a CloudKit identity and organizer/attendees/messages
                let keep = group.max { lhs, rhs in
                    func score(_ m: CachedMeeting) -> Int {
                        var s = 0
                        if m.ckRecordID != nil { s += 4 }
                        if m.isOwner { s += 2 }
                        s += (m.attendees?.count ?? 0) > 0 ? 1 : 0
                        s += (m.messages?.count  ?? 0) > 0 ? 1 : 0
                        return s
                    }
                    return score(lhs) < score(rhs)
                }
                for row in group where row !== keep {
                    cache.delete(row)        // local only
                }
            }
            try cache.save()
        } catch {
            #if DEBUG
            print("[Deduper] Failed: \(error)")
            #endif
        }
    }
}
