//
//  CachedMeeting.swift
//  Wheya
//
//  Created by Yuliia Murakami on 9/10/25.
//

import Foundation
import SwiftData
import CloudKit

// SwiftData cache model for a single Meeting.
// This is the local source used by SwiftUI; CloudKit round-trips are handled by MeetingSync/CloudKitManager.
//
// Identity strategy:
// - We store CloudKit identity (recordName/zoneName/ownerName) so we can address the record on the server.
// - We also compute a stable, **globally unique** `globalID` string (owner::zone::recordName)
//   to reliably match the same meeting across private vs shared DBs and across devices.
// - `globalID` is what we query with in SwiftData (simple String predicates, no CK types).
@Model
final class CachedMeeting {
    // All attendee rows for this meeting (owner or shared).
    // - deleteRule: `.cascade` means deleting a meeting deletes its attendee rows locally.
    @Relationship(deleteRule: .cascade) var attendees: [CachedAttendeeStatus]? = []
    
    @Relationship(deleteRule: .cascade) var messages: [CachedMessage]? = []
    
    // Unique primary key across private + shared DBs; needed to find rows quickly
    var globalID: String? = nil
    
    // Cloud identity (needed for shared records)
    var recordName: String? = nil // CKRecord.ID.recordName
    var zoneName: String? = nil // CKRecordZone.ID.zoneName
    var ownerName: String? = nil // CKRecordZone.ID.ownerName
    
    // Meeting fields
    var title: String = ""
    var createdAt: Date = Date()
    var date: Date = Date()
    var locationName: String = ""
    var latitude: Double = 0
    var longitude: Double = 0
    var notes: String = ""
    var isOwner: Bool = false // true if the meeting is orginized by you
    var shareMinutes: Int = 10
    
    // Offline/failed writes
    var isDirty: Bool = false
    var isHidden: Bool = false // local-only hide for participants
    
    init(
        title: String = "",
        createdAt: Date = Date(),
        date: Date = Date(),
        locationName: String = "",
        latitude: Double = 0,
        longitude: Double = 0,
        notes: String = "",
        isOwner: Bool = false,
        shareMinutes: Int = 10,
        isDirty: Bool = false,
        isHidden: Bool = false
    ) {
        self.title = title
        self.createdAt = createdAt
        self.date = date
        self.locationName = locationName
        self.latitude = latitude
        self.longitude = longitude
        self.notes = notes
        self.isOwner = isOwner
        self.shareMinutes = shareMinutes
        self.isDirty = isDirty
        self.isHidden = isHidden
    }
}

// Build a globally unique key from a CKRecord.ID that’s safe to store/query in SwiftData.
// We prefer a string because it’s portable and easy to predicate on.
extension CKRecord.ID {
    var globalID: String { "\(zoneID.ownerName)::\(zoneID.zoneName)::\(recordName)" }
}

extension CKRecord {
    var globalID: String { recordID.globalID }
}

extension CachedMeeting {
    // Create a local “draft” row (owner path) that will later be pushed to CloudKit.
    // - Sets `isDirty = true` so sync can find and upload it.
    static func makeLocalDraft(title: String, date: Date, locationName: String, latitude: Double, longitude: Double, notes: String, isOwner: Bool, shareMinutes: Int) -> CachedMeeting {
        CachedMeeting(
            title: title,
            createdAt: Date(),
            date: date,
            locationName: locationName,
            latitude: latitude,
            longitude: longitude,
            notes: notes,
            isOwner: isOwner,
            shareMinutes: shareMinutes,
            isDirty: true
        )
    }
    
    // Reconstruct a `CKRecord.ID` from the stored identity fields, if available.
    // - Used when performing owner actions (update/delete) against CloudKit.
    var ckRecordID: CKRecord.ID? {
        guard let name = recordName, let zone = zoneName, let owner = ownerName else { return nil }
        return CKRecord.ID(recordName: name, zoneID: .init(zoneName: zone, ownerName: owner))
    }

    // Update local Cloud identity after a successful CloudKit create or when importing from Cloud.
    // - Also refreshes the `globalID` to keep the cache in sync with server truth.
    func updateIdentity(from rid: CKRecord.ID) {
        recordName = rid.recordName
        zoneName   = rid.zoneID.zoneName
        ownerName  = rid.zoneID.ownerName
        globalID   = rid.globalID
    }
}

extension CachedMeeting {
    var formattedDateTime: String {
        // cache the formatter so we don't recreate it every render
        struct Holder {
            static let df: DateFormatter = {
                let df = DateFormatter()
                df.locale = .autoupdatingCurrent
                df.timeZone = .autoupdatingCurrent
                df.dateStyle = .medium
                df.timeStyle = .short
                return df
            }()
        }
        return Holder.df.string(from: date)
    }
}
