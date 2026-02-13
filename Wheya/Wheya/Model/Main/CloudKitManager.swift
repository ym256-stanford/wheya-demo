//
//  CloudKitManager.swift
//  Wheya
//
//  Created by Yuliia Murakami on 2025/08/20.
//

import Foundation
import Observation
import CloudKit
import UIKit

//  CloudKitManager is the single place that knows how to talk to CloudKit.
//  It encapsulates:
//    • Container/database accessors (private vs shared DB)
//    • CRUD for Meeting records in a custom zone
//    • Sharing lifecycle (create/migrate share, accept share, reload shared content)
//    • Subscriptions: shared DB (database changes), private zone (record-zone changes), and a
//      per-record query subscription for the owner's currently displayed meeting
//    • AttendeeStatus upsert/fetch helpers (images as CKAsset)
//  UI Bridge:
//    • Posts NotificationCenter events:
//        - .didAcceptSharedMeeting (after accepting a share)
//        - .didReloadSharedMeetings (after shared DB change or accept)
//        - .didReloadPrivateMeetings (after owner’s private zone change)
//  Threading:
//    • Methods that mutate UI-observed state dispatch back to MainActor where needed.
//    • Long-running CloudKit work is `async` and off the main thread.
//
//  Callers
//  -------
//  • AppDelegate: registers subscriptions and handles CK push → calls fetch methods
//  • SceneDelegate: accepts incoming shares → calls shareAccepted(_:)
//  • SwiftUI (HomeView/Sync): listens to notifications and imports records into SwiftData
//

// Determine whether the current user is the owner of a given CloudKit record
extension CKRecord {
    var isOwner: Bool {
        self.creatorUserRecordID?.recordName == CKCurrentUserDefaultName
    }
}

extension Notification.Name {
    static let didAcceptSharedMeeting = Notification.Name("didAcceptSharedMeeting")
    static let didReloadSharedMeetings = Notification.Name("didReloadSharedMeetings")
    static let didReloadPrivateMeetings = Notification.Name("didReloadPrivateMeetings")
}

// Global variables to use across all files
enum CloudManager {
    // Record types
    static let meetingRecordType = "Meeting"
    static var meetingsZoneName = "MeetingsZone"
    static let attendeeStatusRecordType = "AttendeeStatus"
    
    // Container / subscription identifiers
    static let containerIdentifier = "iCloud.com.wheya"
    static let privateDatabaseQuerySubscriptionId = "query-meeting-update"
    static let sharedCloudDatabaseSubscriptionId = "shared-database-changes"
    static let privateZoneSubscriptionId = "private-meetings-zone-changes"
    
    // Typed accessors
    static var container: CKContainer { CKContainer(identifier: containerIdentifier) }
    static var privateDB: CKDatabase { container.privateCloudDatabase }
    static var sharedDB: CKDatabase { container.sharedCloudDatabase }
}

@Observable
class CloudKitManager {
    // Core CloudKit handles
    private let container: CKContainer
    private let privateDB: CKDatabase
    private let sharedDB: CKDatabase
    
    init() {
        // Write which container manually, since default is "iCloud.Hiromichi.Wheya"
        self.container = CloudManager.container
        self.privateDB = CloudManager.privateDB
        self.sharedDB = CloudManager.sharedDB
    }
        
    // Sharing
    // Tracks the last known state of the shared database so you can fetch only the changes since the last sync
    var sharedDatabaseChangeToken: CKServerChangeToken?
    // Caches the current list of shared meetings (records) that have been received via CloudKit sharing
    var sharedWithMe: [CKRecord] = []
    // Stores a pagination cursor from a previous shared records query — so you can continue loading more data where you left off
    var sharedWithMeCursor: CKQueryOperation.Cursor?
    // Helps the app know which record the user is interacting with, so you can update or clear it if it’s changed or deleted on the server.
    var displayRecord: CKRecord?
    
    // Helper function to handle errors
    func handle(_ error: Error?, operation: CloudKitOperationType, alert: Bool = false) -> CKError? {
        return handleCloudKitError(error, operation: operation, alert: alert)
    }

    // Helper function to create/update meeting fields.
    func applyMeetingFields(_ meeting: Meeting, to record: CKRecord) {
        record[MeetingRecordKeys.createdAt.rawValue] = meeting.createdAt
        record[MeetingRecordKeys.title.rawValue] = meeting.title
        record[MeetingRecordKeys.date.rawValue] = meeting.date
        record[MeetingRecordKeys.locationName.rawValue] = meeting.locationName
        record[MeetingRecordKeys.latitude.rawValue] = meeting.latitude
        record[MeetingRecordKeys.longitude.rawValue] = meeting.longitude
        record[MeetingRecordKeys.notes.rawValue] = meeting.notes
        record[MeetingRecordKeys.shareMinutes.rawValue] = meeting.shareMinutes
    }

    // MARK: - User
    // Check if user is loged in their iCloud
    func checkAccountStatus() async throws {
        let status = try await container.accountStatus()
        
        switch status {
        case .available:
            print("iCloud account is available.")
        case .noAccount:
            throw NSError(domain: "CloudKit", code: 1, userInfo: [NSLocalizedDescriptionKey: "No iCloud account found."])
        case .restricted:
            throw NSError(domain: "CloudKit", code: 2, userInfo: [NSLocalizedDescriptionKey: "iCloud access is restricted."])
        case .couldNotDetermine:
            throw NSError(domain: "CloudKit", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not determine iCloud account status."])
        case .temporarilyUnavailable:
            throw NSError(domain: "CloudKit", code: 4, userInfo: [NSLocalizedDescriptionKey: "iCloud access is temporarily unavailable."])
        @unknown default:
            throw NSError(domain: "CloudKit", code: 5, userInfo: [NSLocalizedDescriptionKey: "Unknown iCloud account status."])
        }
    }
    
    // MARK: - Meeting CRUD (private zone for owner)
    // Create a meeting record. All meetings are saved to custom shared zone.
    func createMeetingRecord(from meeting: Meeting) async throws -> CKRecord {
        let zone = try await CloudKitZoneManager.shared.getPrivateZone()
        let incoming = meeting.recordID
        let recordName = incoming?.recordName ?? UUID().uuidString
        let recordID   = CKRecord.ID(recordName: recordName, zoneID: zone.zoneID)
        let record = CKRecord(recordType: MeetingRecordKeys.type.rawValue, recordID: recordID)
        
        applyMeetingFields(meeting, to: record)

        return record
    }

    // Save meeting to CloudKit
    func addMeeting(_ meeting: Meeting) async throws -> Meeting {
        let record = try await createMeetingRecord(from: meeting)
        let savedRecord = try await privateDB.save(record)
        guard let savedMeeting = Meeting(record: savedRecord) else {
            throw NSError(domain: "InvalidMeeting", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create Meeting from CKRecord"])
        }
        return savedMeeting
    }

    // Update meeting
    func updateMeeting(editedMeeting: Meeting) async throws {
        guard let recordID = editedMeeting.recordID else {
            throw NSError(domain: "MissingRecordID", code: 0)
        }
        
        do {
            // The record is guaranteed to exist in the database, so it is safe to use "!"
            let record = try await privateDB.record(for: recordID)
            // Save all values manually to update
            applyMeetingFields(editedMeeting, to: record)
            
            _ = try await privateDB.save(record)
        } catch {
            _ = handle(error, operation: .modifyRecords, alert: true)
            // Throw an error to tell the user that meeting was not updated
            throw error
        }
    }
        
    // Delete meeting (only owner can delete the meeting because it is in it's private database, all participants can only "hide" it.
    // Falls back to cascade if children block deletion.
    @MainActor
    func deleteMeeting(recordID: CKRecord.ID) async throws -> Bool {
        // Ensure it exists
        _ = try? await privateDB.record(for: recordID)

        // Try direct delete (works if all children reference with .deleteSelf)
        if (try? await privateDB.deleteRecord(withID: recordID)) != nil {
            return true
        }
        #if DEBUG
        print("⚠️ [CK] Direct delete failed: will attempt cascade")
        #endif

        // 1) Fetch attendees in the zone (parent or meeting == recordID)
        let attendees = try await fetchAttendeeStatusRecords(for: recordID, useSharedDB: false)

        // 2) Delete child records first
        if attendees.isEmpty == false {
            let ids = attendees.map(\.recordID)
            let (_, deleteResults) = try await privateDB.modifyRecords(saving: [], deleting: ids)
            for (_, res) in deleteResults {
                if case .failure(_) = res {
                    #if DEBUG
                    //print("⚠️ Failed to delete child \(rid.recordName): \(err)")
                    #endif
                }
            }
        }

        // 3) Delete the meeting
        _ = try await privateDB.deleteRecord(withID: recordID)
        return true
    }

    
    // Fetch all private meetings (returns records you can map into SwiftData)
    func fetchAllPrivateMeetings() async throws -> [CKRecord] {
        do {
            let privateQuery = CKQuery(recordType: MeetingRecordKeys.type.rawValue, predicate: NSPredicate(value: true))
            privateQuery.sortDescriptors = [NSSortDescriptor(key: MeetingRecordKeys.date.rawValue, ascending: true)]
            
            let privateResult = try await privateDB.records(matching: privateQuery)
            let privateRecords = privateResult.matchResults.compactMap { try? $0.1.get() }
            return privateRecords
        } catch {
            _ = handle(error, operation: .fetchRecords, alert: false)
            throw NSError(domain: "MeetingError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to load private meetings: \(error.localizedDescription)"])
        }
    }
    
    // Fetch shared meetings (returns records you can map into SwiftData)
    func fetchAllSharedMeetings() async throws -> [CKRecord] {
        
        let sharedQuery = CKQuery(recordType: MeetingRecordKeys.type.rawValue, predicate: NSPredicate(value: true))
        sharedQuery.sortDescriptors = [NSSortDescriptor(key: MeetingRecordKeys.date.rawValue, ascending: true)]
        
        do {
            // Ask ZoneManager for the (cached or freshly discovered) shared zone
            let sharedZone = try await CloudKitZoneManager.shared.getSharedZone()
            // Skip if hasn't accepted any shared meetings yet.
            guard sharedZone != nil else {
                #if DEBUG
                print("⚠️ Skipping shared meeting fetch — no accepted shared zones")
                #endif
                return []
            }
            
            do {
                let sharedResult = try await sharedDB.records(
                    matching: sharedQuery,
                    inZoneWith: sharedZone?.zoneID,
                    desiredKeys: nil,
                    resultsLimit: CKQueryOperation.maximumResults
                )
                
                let sharedRecords = sharedResult.matchResults.compactMap {
                    do {
                        return try $0.1.get()
                    } catch {
                        #if DEBUG
                        print("[fetchAllSharedMeetings] Error retrieving shared record: \(error)")
                        #endif
                        return nil
                    }
                }
                return sharedRecords
            } catch let e as CKError where e.code == .zoneNotFound {
                #if DEBUG
                print("[fetchAllSharedMeetings] Shared zone not found on server. Clearing cache and returning empty. Error: \(e)")
                #endif
                CloudKitZoneManager.shared.invalidateSharedZoneCache()
                return []
            }
        } catch {
            #if DEBUG
            print("[fetchAllSharedMeetings] Failed to fetch shared meetings: \(error)")
            #endif
            _ = handle(error, operation: .fetchRecords, alert: false)
            throw NSError(domain: "MeetingError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to load shared meetings: \(error.localizedDescription)"])
        }
    }
}

// MARK: - Sharing lifecycle
extension CloudKitManager {
    func makeRecordForSharing(from meeting: Meeting) async throws -> CKRecord {
        // Build a new Meeting record in our private custom zone (for sharing/migration).
        let zone = try await CloudKitZoneManager.shared.getPrivateZone()
        let recordID = CKRecord.ID(recordName: UUID().uuidString, zoneID: zone.zoneID)
        let record = CKRecord(recordType: MeetingRecordKeys.type.rawValue, recordID: recordID)
        applyMeetingFields(meeting, to: record)
        return record
    }
    
    // Save the prepared record to privateDB (owner) before creating a CKShare.
    func createSharableMeetingRecord(from meeting: Meeting) async throws -> CKRecord {
        let record = try await makeRecordForSharing(from: meeting)
        let savedRecord = try await privateDB.save(record)
        return savedRecord
    }
    
    // If the meeting was in the default zone, the function migrates it.
    // If a share already exists, it returns it;
    // otherwise it creates a new .readWrite share.
    func getOrCreateShare(for meeting: Meeting) async throws -> CKShare {
        // Must have a server record first
        guard let rid = meeting.recordID else {
            let err = NSError(domain: "Share", code: 1000,
                              userInfo: [NSLocalizedDescriptionKey: "Meeting not uploaded yet"])
            #if DEBUG
            print("[Share] No CKRecord.ID on Meeting → \(err.localizedDescription)")
            #endif
            throw err
        }

        // Pick the correct DB for this record’s zone owner
        // Do it *before* fetching the record (owner→privateDB, participant→sharedDB) to avoid time lag
        let rootDB: CKDatabase = (rid.zoneID.ownerName == CKCurrentUserDefaultName)
            ? privateDB
            : sharedDB
        
        var record = try await rootDB.record(for: rid)
        
        // If I'm the owner and it somehow lives in the default zone, migrate before sharing
        if rootDB === privateDB,
           record.recordID.zoneID.zoneName == CKRecordZone.default().zoneID.zoneName
        {
            #if DEBUG
            print("⚠️ [Share] Root record is in default zone; migrating to custom zone before sharing…")
            #endif
            let meetingCopy = Meeting(record: record)!
            record = try await createSharableMeetingRecord(from: meetingCopy) // saves into custom zone
        }

        let isOwner = (record.creatorUserRecordID?.recordName == CKCurrentUserDefaultName)

        // If a share already exists, read it from the appropriate DB
        if let shareRef = record.share {
            let shareDB: CKDatabase = isOwner ? privateDB : sharedDB

            if let existing = try? await shareDB.record(for: shareRef.recordID) as? CKShare {
                // Ensure public RW on owner side
                if isOwner, existing.publicPermission != .readWrite {
                    existing.publicPermission = .readWrite
                    _ = try? await shareDB.modifyRecords(saving: [existing], deleting: [])
                }
                return existing
            }
        }

        // Only the owner can create/modify the share
        guard isOwner else {
            throw NSError(domain: "Share", code: 403,
                          userInfo: [NSLocalizedDescriptionKey: "Only the owner can manage sharing"])
        }

        // Create a new share (owner path)
        let share = CKShare(rootRecord: record)
        share[CKShare.SystemFieldKey.title] = "Shared Meeting: \(meeting.title)" as CKRecordValue
        share.publicPermission = .readWrite

        // Save both share + root (required by CloudKit)
        let (saved, _) = try await privateDB.modifyRecords(saving: [share, record], deleting: [])
        for (id, res) in saved where id == share.recordID {
            if case .success(let savedShare as CKShare) = res {
                return savedShare
            }
        }
        throw NSError(domain: "ShareCreation", code: -1,
                      userInfo: [NSLocalizedDescriptionKey: "Failed to save CKShare"])
    }

    // Update `displayRecord` (owner UI focus) and hook any UI side effects.
    func setDisplayRecordAndUpdateTitleContent(_ record: CKRecord) {
        self.displayRecord = record

        // If you have any UI-related updates to do, place them here.
        // For example, updating observable variables used by SwiftUI.
    }
    
    // Handle owner’s private zone changes → reload owner meetings and notify UI.
    func fetchChangesForPrivateZoneSubscription() async throws {
        //print("📡 fetchChangesForPrivateZoneSubscription")
        let privateRecords = try await fetchAllPrivateMeetings()

        // Tell the UI to re-import & refresh attendees for owner-view meetings
        await MainActor.run {
            NotificationCenter.default.post(
                name: .didReloadPrivateMeetings,
                object: nil,
                userInfo: ["records": privateRecords]
            )
        }
    }

    // Handle shared DB database-level changes → reload shared records, keep `displayRecord` fresh,
    // and re-add the query subscription for the owner’s currently focused meeting.
    func fetchChangesForSharedDBSubscription() async throws {
        var more = true
        var modifiedZoneIds: [CKRecordZone.ID] = []
        var deletions: [CKDatabase.DatabaseChange.Deletion] = []

        while more {
            let (modifications, _deletions, changeToken, moreComing) = try await self.sharedDB.databaseChanges(since: self.sharedDatabaseChangeToken)
            modifiedZoneIds.append(contentsOf: modifications.map(\.zoneID))
            deletions.append(contentsOf: _deletions)
            more = moreComing
            self.sharedDatabaseChangeToken = changeToken
        }
                
        modifiedZoneIds = modifiedZoneIds.filter { zoneID in
            !deletions.map(\.zoneID).contains(zoneID)
        }
        
        let zone = try await CloudKitZoneManager.shared.getSharedZone()
        // Only handle our known shared zone
        if let deletion = deletions.first(where: { $0.zoneID == zone?.zoneID }) {
            switch deletion.reason {
            case .deleted, .purged:
                CloudKitZoneManager.shared.invalidateSharedZoneCache()
                
                await MainActor.run {
                    self.sharedWithMe = []
                    if let displayRecord, !displayRecord.isOwner {
                        self.displayRecord = nil
                    }
                    // For UI change
                    NotificationCenter.default.post(
                        name: .didReloadSharedMeetings,
                        object: nil,
                        userInfo: ["records": []]
                    )
                }
                return

            case .encryptedDataReset:
                let (saved, _) = try await self.sharedDB.modifyRecords(saving: self.sharedWithMe, deleting: [])
                var savedRecords: [CKRecord] = []
                for (_, result) in saved {
                    switch result {
                    case .success(let record): savedRecords.append(record)
                    case .failure(let error): print("Failed to save: \(error)")
                        _ = handle(error, operation: .modifyRecords)
                    }
                }
                self.sharedWithMe = savedRecords
                return

            @unknown default:
                #if DEBUG
                print("Unknown deletion reason.")
                #endif
                return
            }
        }

        guard let zone, modifiedZoneIds.contains(zone.zoneID) else {
            #if DEBUG
            print("No relevant zone changes.")
            #endif
            return
        }
        self.sharedWithMeCursor = nil
        await self.loadSharedWithMeRecords()

        if let displayRecord, let newRecord = self.sharedWithMe.first(where: { $0.recordID == displayRecord.recordID }) {
            self.setDisplayRecordAndUpdateTitleContent(newRecord)
        }
        try await self.addQuerySubscription()
    }
    
    // Accepts a CKShare from SceneDelegate (live or cold launch), fetches the root Meeting,
    // reloads the full shared set, and notifies the UI.
    func shareAccepted(_ shareMetadata: CKShare.Metadata) async throws {
        try await self.checkAccountStatus()
        
        // 1. Only accept if not already accepted
        // checking the participantStatus of the provided metadata. If the status is pending, accept participation in the share.
        // trying to accept the share as an owner will throw an error
        if shareMetadata.participantRole != .owner && shareMetadata.participantStatus == .pending {
            _ = try await container.accept(shareMetadata)
        } else {
            #if DEBUG
            print("[shareAccepted] Share already accepted or owned.")
            #endif
        }
        
        // 2. Get root record ID
        // shareMetadata.rootRecord is only present if the share metadata was returned from a CKFetchShareMetadataOperation with shouldFetchRootRecord set to YES
        guard let rootRecordId = shareMetadata.hierarchicalRootRecordID else {
            throw NSError(domain: "Share", code: 404, userInfo: [NSLocalizedDescriptionKey: "Root record not found in share metadata"])
        }
        
        // 3. Use correct database based on participant role
        // root record shows up in sharedCloudDatabase for participant and privateDatabase for owner
        let database = shareMetadata.participantRole == .owner ? privateDB : sharedDB
        
        // 4. Fetch the root record
        let rootRecord = try await database.record(for: rootRecordId)
        
        // 5. Convert it to your model (e.g., Meeting)
        if Meeting(record: rootRecord) != nil {
            await MainActor.run {
                self.sharedWithMe.append(rootRecord)
            }
        } else {
            #if DEBUG
            print("[shareAccepted] Could not convert CKRecord to Meeting")
            #endif
        }
        
        await self.loadSharedWithMeRecords()
        
        await MainActor.run {
            NotificationCenter.default.post(
                name: .didAcceptSharedMeeting,
                object: nil,
                userInfo: ["record": rootRecord]
            )
        }
    }
    
    // Save a *database* subscription in the shared DB so participants receive pushes
    // for any changes under zones they have access to.
    func addSharedDatabaseSubscription() async throws {

        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true // silent push

        let sharedSubscription = CKDatabaseSubscription(subscriptionID: CloudManager.sharedCloudDatabaseSubscriptionId)
        sharedSubscription.notificationInfo = notificationInfo

        do {
            _ = try await sharedDB.save(sharedSubscription)
        } catch {
            #if DEBUG
            print("[addSharedDatabaseSubscription] Failed to save shared DB subscription: \(error)")
            #endif
            throw error
        }
    }
    
    // Create (or replace) a *query* subscription tied to the owner’s `displayRecord`.
    // - Fires on update & deletion of that one record in the private zone.
    func addQuerySubscription() async throws {
        guard let displayRecord, displayRecord.isOwner else {
            #if DEBUG
            print("[addQuerySubscription] No displayRecord or not owner.")
            #endif
            return
        }
    
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true

        let predicate = NSPredicate(format: "recordID == %@", displayRecord.recordID)

        let querySubscription = CKQuerySubscription(
            recordType: displayRecord.recordType,
            predicate: predicate,
            subscriptionID: CloudManager.privateDatabaseQuerySubscriptionId,
            options: [.firesOnRecordUpdate, .firesOnRecordDeletion]
        )

        querySubscription.notificationInfo = notificationInfo
        querySubscription.zoneID = displayRecord.recordID.zoneID

        do {
            let _ = try await privateDB.save(querySubscription)
        } catch {
            #if DEBUG
            print("[addQuerySubscription] Failed to save query subscription: \(error)")
            #endif
            _ = handle(error, operation: .modifySubscriptions, alert: false)
            throw error
        }
    }
    
    // Remove the per-record query subscription (e.g., when navigating away).
    func removeQuerySubscriptions() async throws {
        do {
            try await privateDB.deleteSubscription(withID: CloudManager.privateDatabaseQuerySubscriptionId)
        } catch {
            #if DEBUG
            print("[removeQuerySubscriptions] Failed to remove query subscription: \(error)")
            #endif
            _ = handle(error, operation: .deleteSubscriptions, alert: false)
            throw error
        }
    }
    
    // Handle the owner’s per-record query push (update/deletion on the focused record).
    func fetchChangesForQuerySubscription(_ notification: CKQueryNotification) async throws {
        
        guard let displayRecord,
              displayRecord.isOwner,
              notification.recordID?.recordName == displayRecord.recordID.recordName else {
            return
        }
        
        if notification.queryNotificationReason == .recordDeleted {
            self.displayRecord = nil
            return
        }
        
        let updatedRecord = try await privateDB.record(for: displayRecord.recordID)
        if Meeting(record: updatedRecord) != nil {
        }
        self.setDisplayRecordAndUpdateTitleContent(updatedRecord)
    }
    
    // Reloads the entire set of shared meetings into `sharedWithMe` and notifies the UI.
    @MainActor
    func loadSharedWithMeRecords() async {
        do {
            let records = try await fetchAllSharedMeetings()
            self.sharedWithMe = records
            // Broadcast so UI (HomeView) can import into SwiftData
            NotificationCenter.default.post(
                name: .didReloadSharedMeetings,
                object: nil,
                userInfo: ["records": records]
            )
        } catch {
            #if DEBUG
            print(" [CK] loadSharedWithMeRecords failed: \(error)")
            #endif
        }
    }
}

// MARK: - AttendeeStatus
extension CloudKitManager {
    struct AttendeeKeys {
        static let type = CloudManager.attendeeStatusRecordType // "AttendeeStatus"
        static let appleUserID = "appleUserID"
        static let displayName = "displayName"
        static let imageData = "imageData"
        static let imageAsset = "imageAsset"
        static let organizer = "organizer"
        static let meeting = "meeting"
        static let updatedAt = "updatedAt"
        static let here = "here"
        static let latitude = "latitude"
        static let longitude = "longitude"
        static let etaMinutes = "etaMinutes"
        static let deleted = "deleted"
        static let hereUpdatedAt = "hereUpdatedAt"
        static let deletedUpdatedAt = "deletedUpdatedAt"
    }
    
    // Saves the given AttendeeStatus record to the correct database (private if you own the zone; shared otherwise).
    @discardableResult
    func saveAttendeeStatusRecord(
        _ attendeeRecord: CKRecord,
        meetingRecordID: CKRecord.ID
    ) async throws -> CKRecord {
        // If the zone owner is "me", write to privateDB; otherwise it's a shared zone → sharedDB.
        let targetDB: CKDatabase = (meetingRecordID.zoneID.ownerName == CKCurrentUserDefaultName)
            ? privateDB
            : sharedDB
        return try await targetDB.save(attendeeRecord)
    }
    
    // Upsert (create-or-replace) an AttendeeStatus row for a meeting.
    // - Important: The recordName includes the meeting's recordName to avoid collisions
    //              across different meetings for the same user.
    // - Data placement: We write to `privateDB` if the meeting zone is owned by me,
    //                   otherwise to `sharedDB` so the owner sees the change.
    func upsertAttendeeStatus(
        forMeetingRecordID meetingRID: CKRecord.ID,
        appleUserID: String,
        displayName: String?,
        imageData: Data?,
        organizer: Bool? = nil,
        here: Bool? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        etaMinutes: Int? = nil,
        deleted: Bool? = nil
    ) async throws -> CKRecord {
        let zoneID = meetingRID.zoneID
        let db: CKDatabase = (zoneID.ownerName == CKCurrentUserDefaultName) ? privateDB : sharedDB
        // Include meeting recordName to avoid collisions across meetings
        let rid = CKRecord.ID(recordName: "att-\(meetingRID.recordName)-\(appleUserID)", zoneID: zoneID)
        
        // 1) Fetch if exists, else create
        let rec: CKRecord
        do {
            rec = try await db.record(for: rid) // edit existing
        } catch let err as CKError where err.code == .unknownItem {
            // Create new
            let r = CKRecord(recordType: AttendeeKeys.type, recordID: rid)
            r.parent = CKRecord.Reference(recordID: meetingRID, action: .none)
            r[AttendeeKeys.meeting] = CKRecord.Reference(recordID: meetingRID, action: .deleteSelf)
            rec = r
        }
        
        if rec.parent == nil {
            rec.parent = CKRecord.Reference(recordID: meetingRID, action: .none)
        }
        if rec[AttendeeKeys.meeting] == nil {
            rec[AttendeeKeys.meeting] = CKRecord.Reference(recordID: meetingRID, action: .deleteSelf)
        }
        
        // 2) Apply fields
        rec[AttendeeKeys.appleUserID] = appleUserID as CKRecordValue
        if let displayName { rec[AttendeeKeys.displayName] = displayName as CKRecordValue }

        if let organizer {
            rec[AttendeeKeys.organizer] = organizer as CKRecordValue
        }
        if let data = imageData, let asset = makeImageAsset(from: data) {
            rec[AttendeeKeys.imageAsset] = asset
        } else {
            rec[AttendeeKeys.imageAsset] = nil
        }
        
        if let here {
            rec[AttendeeKeys.here] = here as CKRecordValue
            if here {
                rec[AttendeeKeys.hereUpdatedAt] = Date() as CKRecordValue
            }
        }
        
        if let latitude { rec[AttendeeKeys.latitude] = latitude as CKRecordValue }
        if let longitude { rec[AttendeeKeys.longitude] = longitude as CKRecordValue }
        if let etaMinutes {
            rec[AttendeeKeys.etaMinutes] = etaMinutes as CKRecordValue
        } else {
            rec[AttendeeKeys.etaMinutes] = nil
        }
        
        if let deleted {
            rec[AttendeeKeys.deleted] = deleted as CKRecordValue
            if deleted {
                rec[AttendeeKeys.deletedUpdatedAt] = Date() as CKRecordValue
                // Force here=true alongside delete to stop sharing on all devices
                rec[AttendeeKeys.here] = true as CKRecordValue
                rec[AttendeeKeys.hereUpdatedAt] = Date() as CKRecordValue
                // Safety: clear travel fields on the record too
                rec[AttendeeKeys.latitude] = 0 as CKRecordValue
                rec[AttendeeKeys.longitude] = 0 as CKRecordValue
                rec[AttendeeKeys.etaMinutes] = nil
            }
        }
        rec[AttendeeKeys.updatedAt] = Date() as CKRecordValue
        
        // 3) Save, handle conflict once by merging with server
        do {
            let saved = try await db.save(rec)
            return saved
        } catch let err as CKError where err.code == .serverRecordChanged {
            #if DEBUG
            print("[CKM] Conflict; fetching server copy and retrying…")
            #endif
            let server = try await db.record(for: rid)
            
            if server.parent == nil {
                    server.parent = CKRecord.Reference(recordID: meetingRID, action: .none)
                }
            if server[AttendeeKeys.meeting] == nil {
                server[AttendeeKeys.meeting] = CKRecord.Reference(recordID: meetingRID, action: .deleteSelf)
            }
            if let displayName { server[AttendeeKeys.displayName] = displayName as CKRecordValue }

            if let organizer {
                server[AttendeeKeys.organizer] = organizer as CKRecordValue
            }
            if let data = imageData, let asset = makeImageAsset(from: data) {
                server[AttendeeKeys.imageAsset] = asset
            }
            
            if let here {
                server[AttendeeKeys.here] = here as CKRecordValue
                if here {
                    server[AttendeeKeys.hereUpdatedAt] = Date() as CKRecordValue
                }
            }
            if let latitude  { server[AttendeeKeys.latitude] = latitude as CKRecordValue }
            if let longitude { server[AttendeeKeys.longitude] = longitude as CKRecordValue }
            if let etaMinutes {
                server[AttendeeKeys.etaMinutes] = etaMinutes as CKRecordValue
            } else {
                server[AttendeeKeys.etaMinutes] = nil
            }
    
            if let deleted {
                server[AttendeeKeys.deleted] = deleted as CKRecordValue
                if deleted {
                    server[AttendeeKeys.deletedUpdatedAt] = Date() as CKRecordValue
                    // Force here=true alongside delete
                    server[AttendeeKeys.here] = true as CKRecordValue
                    server[AttendeeKeys.hereUpdatedAt] = Date() as CKRecordValue
                    // Safety: clear travel fields
                    server[AttendeeKeys.latitude] = 0 as CKRecordValue
                    server[AttendeeKeys.longitude] = 0 as CKRecordValue
                    server[AttendeeKeys.etaMinutes] = nil
                }
            }

            server[AttendeeKeys.updatedAt] = Date() as CKRecordValue
            let saved = try await db.save(server)
            return saved
        }
    }
    
    // Pushes attendee rows for a meeting from the local cache up to CloudKit.
    // - Owner devices push **all** local attendees for the meeting.
    // - Participant devices push **only themselves** (the row matching `currentUserID`).
    // - The actual DB selection (private/shared) happens inside `upsertAttendeeStatus`
    //   based on the **zone owner** of `meetingRecordID`.
    func pushAttendeesToCloud(
        for cached: CachedMeeting,
        meetingRecordID rid: CKRecord.ID,
        currentUserID: String?
    ) async {
        // Load local rows from SwiftData
        let rows = cached.attendees ?? []
        guard !rows.isEmpty else {
            return
        }
        
        // Decide WHICH rows to push (owner vs participant)
        let rowsToPush: [CachedAttendeeStatus]
        if cached.isOwner {
            // Owner can push everyone they’ve attached
            rowsToPush = rows
        } else if let me = currentUserID {
            // Participant pushes only themselves
            rowsToPush = rows.filter { $0.user?.appleUserID == me }
        } else {
            return
        }

        // Upsert each selected attendee
        for status in rowsToPush {
            guard let user = status.user, !user.appleUserID.isEmpty else {
                continue
            }
            do {
                _ = try await upsertAttendeeStatus(
                    forMeetingRecordID: rid,
                    appleUserID: user.appleUserID,
                    displayName: user.displayName.isEmpty ? nil : user.displayName,
                    imageData: user.imageData,
                    organizer: status.organizer,
                    here: status.here ? true : nil,
                    latitude: status.latitude,
                    longitude: status.longitude,
                    etaMinutes: status.etaMinutes,
                    deleted: nil
                )
            } catch {
                #if DEBUG
                print("[Sync] Attendee upsert failed for \(user.appleUserID): \(error)")
                #endif
            }
        }
    }
    
    // Compress an image to a temp JPEG and wrap as CKAsset, because it is more compact to share
    private func makeImageAsset(from data: Data) -> CKAsset? {
        guard let ui = UIImage(data: data) else { return nil }
        // downscale for cards; reduce payloads
        let max: CGFloat = 512
        let size = ui.size
        let ar = size.width / size.height
        let newSize = size.width > size.height
            ? CGSize(width: max, height: max / ar)
            : CGSize(width: max * ar, height: max)
        let img = UIGraphicsImageRenderer(size: newSize).image { _ in ui.draw(in: CGRect(origin: .zero, size: newSize)) }
        guard let jpeg = img.jpegData(compressionQuality: 0.75) else { return nil }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("jpg")
        do { try jpeg.write(to: url, options: [.atomic]) } catch { return nil }
        return CKAsset(fileURL: url)
    }
    
    // Fetches `AttendeeStatus` rows for a meeting within that meeting’s zone.
    //
    // Who calls me & why:
    // - Owner path: `MeetingSync.importAttendeesFromCloud(..., isOwner: true)` → reads from `privateDB`
    // - Participant path: `MeetingSync.importAttendeesFromCloud(..., isOwner: false)` → reads from `sharedDB`
    // - Delete cascade: `CloudKitManager.deleteMeeting(recordID:)` → loads children before deleting.
    //
    // Query strategy:
    // - Primary: query by **system parent** (fast, robust for shares)
    //
    // Notes:
    // - We sort **locally** (stable) since server sort on system fields can be restricted.
    // - We request all keys (`desiredKeys: nil`) so legacy inline images (`imageData`) are available, too.
    //
    // - Parameters:
    //   - meetingRecordID: The `CKRecord.ID` of the Meeting whose attendees we want.
    //   - useSharedDB: `false` → owner device reads `privateDB`; `true` → participant devices read `sharedDB`.
    // Fetches `AttendeeStatus` rows for a meeting within that meeting’s zone.
    func fetchAttendeeStatusRecords(
        for meetingRecordID: CKRecord.ID,
        useSharedDB: Bool
    ) async throws -> [CKRecord] {
        let db = useSharedDB ? sharedDB : privateDB

        // Primary: by system parent
        let parentRef = CKRecord.Reference(recordID: meetingRecordID, action: .none)
        let parentQ   = CKQuery(recordType: AttendeeKeys.type,
                                predicate: NSPredicate(format: "%K == %@", CKRecord.SystemFieldKey.parent, parentRef))

        let parentRes = try await db.records(
            matching: parentQ,
            inZoneWith: meetingRecordID.zoneID,
            desiredKeys: nil,
            resultsLimit: CKQueryOperation.maximumResults
        )
        var records = parentRes.matchResults.compactMap { try? $0.1.get() }

        // Fallback: legacy rows that only have `meeting` set
        if records.isEmpty {
            let meetingRef = CKRecord.Reference(recordID: meetingRecordID, action: .deleteSelf)
            let legacyQ = CKQuery(recordType: AttendeeKeys.type,
                                  predicate: NSPredicate(format: "%K == %@", AttendeeKeys.meeting, meetingRef))
            let legacyRes = try await db.records(
                matching: legacyQ,
                inZoneWith: meetingRecordID.zoneID,
                desiredKeys: nil,
                resultsLimit: CKQueryOperation.maximumResults
            )
            records = legacyRes.matchResults.compactMap { try? $0.1.get() }
        }

        // Local stable sort
        records.sort { a,b in
            let an = (a[AttendeeKeys.displayName] as? String)?.lowercased()
            let bn = (b[AttendeeKeys.displayName] as? String)?.lowercased()
            if let an, let bn, an != bn { return an < bn }
            let au = (a[AttendeeKeys.appleUserID] as? String) ?? ""
            let bu = (b[AttendeeKeys.appleUserID] as? String) ?? ""
            if au != bu { return au < bu }
            return a.recordID.recordName < b.recordID.recordName
        }
        return records
    }


    //  Enable owner to see participant edits
    func addPrivateZoneSubscription() async {
        do {
            // Get the real zone the app uses
            let zone = try await CloudKitZoneManager.shared.getPrivateZone()
            let sub = CKRecordZoneSubscription(zoneID: zone.zoneID,
                                               subscriptionID: CloudManager.privateZoneSubscriptionId)
            
            let info = CKSubscription.NotificationInfo()
            info.shouldSendContentAvailable = true
            sub.notificationInfo = info
            
           // try await container.privateCloudDatabase.modifySubscriptions(saving: [sub], deleting: [])
            _ = try await container.privateCloudDatabase.save(sub)
        } catch {
            #if DEBUG
            print("[addPrivateZoneSubscription] Failed private zone subscription: \(error)")
            #endif
        }
    }
}

// MARK: - Messages
extension CloudKitManager {
    struct MessageKeys {
        static let type        = "Message"
        static let meeting     = "meeting"
        static let appleUserID = "appleUserID"
        static let displayName = "displayName"
        static let text        = "text"
        static let timestamp   = "timestamp"
        static let updatedAt   = "updatedAt"
    }

    // Deterministic recordName to avoid dupes: msg-<meeting>-<millis>-<uid>
    private func messageRecordID(
        meetingRID: CKRecord.ID,
        epochMillis: Int64,
        appleUserID: String
    ) -> CKRecord.ID {
        CKRecord.ID(recordName: "msg-\(meetingRID.recordName)-\(epochMillis)-\(appleUserID)", zoneID: meetingRID.zoneID)
    }

    @discardableResult
    func upsertMessage(
        forMeetingRecordID meetingRID: CKRecord.ID,
        appleUserID: String,
        displayName: String?,
        text: String,
        timestamp: Date
    ) async throws -> CKRecord {
        let db: CKDatabase = (meetingRID.zoneID.ownerName == CKCurrentUserDefaultName) ? privateDB : sharedDB
        let ms = Int64(timestamp.timeIntervalSince1970 * 1000)
        let rid = messageRecordID(meetingRID: meetingRID, epochMillis: ms, appleUserID: appleUserID)

        // Fetch-or-create with parent + deleteSelf pointer (like Attendee)
        let rec: CKRecord
        do {
            rec = try await db.record(for: rid)
        } catch let err as CKError where err.code == .unknownItem {
            let r = CKRecord(recordType: MessageKeys.type, recordID: rid)
            r.parent = CKRecord.Reference(recordID: meetingRID, action: .none)
            r[MessageKeys.meeting] = CKRecord.Reference(recordID: meetingRID, action: .deleteSelf)
            rec = r
        }

        rec[MessageKeys.appleUserID] = appleUserID as CKRecordValue
        if let displayName { rec[MessageKeys.displayName] = displayName as CKRecordValue }
        rec[MessageKeys.text] = text as CKRecordValue
        rec[MessageKeys.timestamp] = timestamp as CKRecordValue
        rec[MessageKeys.updatedAt] = Date() as CKRecordValue

        // Save with one conflict merge retry (same pattern as attendee upsert)
        do {
            return try await db.save(rec)
        } catch let e as CKError where e.code == .serverRecordChanged {
            let server = try await db.record(for: rid)
            server[MessageKeys.text] = text as CKRecordValue
            server[MessageKeys.updatedAt] = Date() as CKRecordValue
            return try await db.save(server)
        }
    }

    // Fetch by system parent (same strategy as Attendee fetch)
    func fetchMessageRecords(
        for meetingRecordID: CKRecord.ID,
        useSharedDB: Bool
    ) async throws -> [CKRecord] {
        let db = useSharedDB ? sharedDB : privateDB
        let parentRef = CKRecord.Reference(recordID: meetingRecordID, action: .none)
        let predicate = NSPredicate(format: "%K == %@", CKRecord.SystemFieldKey.parent, parentRef)
        let query = CKQuery(recordType: MessageKeys.type, predicate: predicate)

        let result = try await db.records(
            matching: query,
            inZoneWith: meetingRecordID.zoneID,
            desiredKeys: nil,
            resultsLimit: CKQueryOperation.maximumResults
        )

        var records = result.matchResults.compactMap { try? $0.1.get() }
        records.sort {
            let a = ($0[MessageKeys.timestamp] as? Date) ?? Date.distantPast
            let b = ($1[MessageKeys.timestamp] as? Date) ?? Date.distantPast
            if a != b { return a < b }
            return $0.recordID.recordName < $1.recordID.recordName
        }
        return records
    }

    // Owner pushes all dirty messages; participant pushes only their own
    func pushMessagesToCloud(
        for cached: CachedMeeting,
        meetingRecordID rid: CKRecord.ID,
        currentUserID: String?
    ) async {
        let rows = cached.messages ?? []
        guard !rows.isEmpty else { return }

        let toPush: [CachedMessage]
        if cached.isOwner {
            toPush = rows.filter { !$0.hasCKIdentity || $0.isDirty }
        } else if let me = currentUserID {
            toPush = rows.filter { ($0.senderAppleUserID == me) && (!$0.hasCKIdentity || $0.isDirty) }
        } else {
            return
        }

        for msg in toPush {
            do {
                let saved = try await upsertMessage(
                    forMeetingRecordID: rid,
                    appleUserID: msg.senderAppleUserID,
                    displayName: msg.senderDisplayName.isEmpty ? nil : msg.senderDisplayName,
                    text: msg.text,
                    timestamp: msg.timestamp
                )
                // stamp identity locally
                msg.updateIdentity(from: saved.recordID)
                msg.isDirty = false
            } catch {
                #if DEBUG
                print("⚠️ [Sync] Message upsert failed: \(error)")
                #endif
            }
        }
    }
}
