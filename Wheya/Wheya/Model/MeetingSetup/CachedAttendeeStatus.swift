//
//  CachedAttendeeStatus.swift
//  Wheya
//
//  Created by Yuliia Murakami on 9/10/25.
//

import Foundation
import SwiftData

// SwiftData model that mirrors a single attendee’s status for a meeting.
// This is the local, cached representation used by SwiftUI (lists, views).
// Cloud syncing to/from `CKRecord(AttendeeStatus)` happens in MeetingSync/CloudKitManager.
//
// Identity:
// - There is exactly one row per (meeting, user) pair.
// - Organizer is a per-meeting flag; multiple attendees can be organizers if you allow it.
//
// Lifecycle:
// - Owner devices create/update these rows and may push them to CloudKit.
// - Participant devices import them from CloudKit and typically don’t edit others’ rows.
@Model
final class CachedAttendeeStatus {
    // Many-to-one relationship to the local user profile this attendee row represents.
    // Inverse is `CachedUserProfile.attendances`.
    // - Note: keep this optional so rows can exist while a user profile is being created/fetched.
    @Relationship(inverse: \CachedUserProfile.attendances)
    var user: CachedUserProfile? = nil // Relationship to UserProfile (attendee)
    // Many-to-one relationship to the meeting this attendee belongs to.
    // Inverse is `CachedMeeting.attendees`.
    // - Note: deleting a meeting should also delete its attendee rows first.
    @Relationship(inverse: \CachedMeeting.attendees) var meeting: CachedMeeting?
    var organizer: Bool = false  // True if the user is the organizer of the meeting
    var here: Bool = false
    var hereUpdatedAt: Date? = nil
    var latitude: Double = 0
    var longitude: Double = 0
    var etaMinutes: Int? = nil
    
    // ---- Sticky deleted (true-wins) ----
    private var deletedRaw: Bool = false
    var deleted: Bool {
        get { deletedRaw }
        set { if newValue { deletedRaw = true } } // ignore attempts to set false
    }

    private var deletedUpdatedAtRaw: Date? = nil
    var deletedUpdatedAt: Date? {
        get { deletedUpdatedAtRaw }
        set {
            guard let v = newValue else { return }                 // ignore nil
            if let old = deletedUpdatedAtRaw, v <= old { return }  // forward-only
            deletedUpdatedAtRaw = v
        }
    }
    
    // Cloud identity for this attendee record (stable across polls/devices)
    // Mirrors the meeting’s identity storage so we can build a durable fallback ID.
    var attendeeRecordName: String? = nil
    var attendeeZoneName: String? = nil
    var attendeeOwnerName: String? = nil
    var attendeeGlobalID: String? = nil // owner::zone::recordName

    var hasCKIdentity: Bool { attendeeGlobalID != nil }
    
    init(
        organizer: Bool = false
    ) {
        self.organizer = organizer
    }
}

import CloudKit

extension CachedAttendeeStatus {
    func updateIdentity(from rid: CKRecord.ID) {
        attendeeRecordName = rid.recordName
        attendeeZoneName   = rid.zoneID.zoneName
        attendeeOwnerName  = rid.zoneID.ownerName
        attendeeGlobalID   = rid.globalID   // uses your existing CKRecord.ID.globalID helper
    }
}

extension CachedAttendeeStatus {
    func markDeleted(at ts: Date = Date()) {
        if !deleted { deleted = true }
        if (deletedUpdatedAt ?? .distantPast) < ts { deletedUpdatedAt = ts }
        if here == false {
            here = true
            if (hereUpdatedAt ?? .distantPast) < ts { hereUpdatedAt = ts }
        }
        latitude = 0; longitude = 0; etaMinutes = nil
    }
}
