//
//  AttendeeStatus.swift
//  Wheya
//
//  Created by Hiromichi Murakami on 7/25/25.
//

import Foundation
import CloudKit

// CloudKit record keys for the AttendeeStatus model.
// - Note: `rawValue` strings must match the fields you store in CloudKit.
enum AttendeeStatusRecordKeys: String {
    case type = "AttendeeStatus" // CKRecord.recordType
    case appleUserID
    case meeting
    case organizer
    case here
    case latitude
    case longitude
    case etaMinutes
    case deleted
    case hereUpdatedAt
    case deletedUpdatedAt
}

// A lightweight model that mirrors a CloudKit `AttendeeStatus` record.
// You can create it in memory, initialize it from a `CKRecord`, or convert it back to `CKRecord` for saving.
class AttendeeStatus: Identifiable {
    // Stable CloudKit record identifier (record name + zone).
    var recordID: CKRecord.ID

    // Properties
    var appleUserID: String
    var meetingRef: CKRecord.Reference // Reference to the related meeting
    var organizer: Bool
    var here: Bool? = nil // Specify if participant reached the meeting point
    var latitude: Double
    var longitude: Double
    // ETA (minutes)
    var etaMinutes: Int? // Need user's current location and meeting's latitute and longtitute to calculate
    var deleted: Bool? = nil
    var hereUpdatedAt: Date? = nil
    var deletedUpdatedAt: Date? = nil

    // MARK: - Initializers

    // Create a new attendee row in memory (for new records you plan to save to CloudKit).
    // - Parameters:
    //   - meetingRef: CK reference to the related meeting record (often the parent).
    //   - organizer: Whether this user is the organizer.
    //   - recordID: Optional explicit record ID; defaults to a new random record name.
    init(
      appleUserID: String,
      meetingRef: CKRecord.Reference,
      organizer: Bool = false,
      here: Bool? = nil,
      latitude: Double = 0,
      longitude: Double = 0,
      etaMinutes: Int? = nil,
      deleted: Bool? = nil,
      hereUpdatedAt: Date? = nil,
      deletedUpdatedAt: Date? = nil,
      recordID: CKRecord.ID = CKRecord.ID(recordName: UUID().uuidString)
    ) {
        self.recordID    = recordID
        self.appleUserID = appleUserID
        self.meetingRef  = meetingRef
        self.organizer   = organizer
        self.here        = here
        self.latitude    = latitude
        self.longitude   = longitude
        self.etaMinutes  = etaMinutes
        self.deleted     = deleted
        self.hereUpdatedAt = hereUpdatedAt
        self.deletedUpdatedAt = deletedUpdatedAt
    }

    // Initialize from an existing CloudKit record.
    // Returns `nil` if required fields are missing or of the wrong type.
    // - Parameter record: A `CKRecord` with type `AttendeeStatus`.
    init?(from record: CKRecord) {
        guard
            let uid = record[AttendeeStatusRecordKeys.appleUserID.rawValue] as? String,
            let meetingRef = record[AttendeeStatusRecordKeys.meeting.rawValue] as? CKRecord.Reference
        else {
            return nil
        }
        
        // Booleans may come back as NSNumber
        let organizerBool =
            (record[AttendeeStatusRecordKeys.organizer.rawValue] as? NSNumber)?.boolValue ??
            (record[AttendeeStatusRecordKeys.organizer.rawValue] as? Bool) ?? false

        // Optional flags: keys may be absent when false
        let hereOpt: Bool? = {
            if let n = record[AttendeeStatusRecordKeys.here.rawValue] as? NSNumber { return n.boolValue }
            return record[AttendeeStatusRecordKeys.here.rawValue] as? Bool
        }()

        let deletedOpt: Bool? = {
            if let n = record[AttendeeStatusRecordKeys.deleted.rawValue] as? NSNumber { return n.boolValue }
            return record[AttendeeStatusRecordKeys.deleted.rawValue] as? Bool
        }()

        // Numbers may be NSNumber; fall back to 0 when missing
        let lat = record[AttendeeStatusRecordKeys.latitude.rawValue] as? Double ?? 0
        let lon = record[AttendeeStatusRecordKeys.longitude.rawValue] as? Double ?? 0
        let eta: Int? = (record[AttendeeStatusRecordKeys.etaMinutes.rawValue] as? NSNumber)?.intValue
            ?? (record[AttendeeStatusRecordKeys.etaMinutes.rawValue] as? Int)

        // Field-level timestamps (optional)
        let hereTS = record[AttendeeStatusRecordKeys.hereUpdatedAt.rawValue] as? Date
        let deletedTS = record[AttendeeStatusRecordKeys.deletedUpdatedAt.rawValue] as? Date
        
        self.recordID = record.recordID
        self.appleUserID = uid
        self.meetingRef = meetingRef
        self.organizer = organizerBool
        self.here = hereOpt
        self.latitude = lat
        self.longitude = lon
        self.etaMinutes = eta
        self.deleted = deletedOpt
        self.hereUpdatedAt = hereTS
        self.deletedUpdatedAt = deletedTS
    }

    // Convert this model back into a `CKRecord` suitable for saving to CloudKit.
    // - Important: This does NOT set `parent`. If you want the attendee row to travel with the Meeting share
    //   and be cascade-deleted, also set:
    //     `record.parent = CKRecord.Reference(recordID: meetingRef.recordID, action: .none)`
    //   and keep `meeting` as a separate field with `.deleteSelf` action for queries/cascade.
    func toRecord() -> CKRecord {
        let record = CKRecord(recordType: AttendeeStatusRecordKeys.type.rawValue, recordID: recordID)
        record[AttendeeStatusRecordKeys.appleUserID.rawValue] = appleUserID as CKRecordValue
        record[AttendeeStatusRecordKeys.meeting.rawValue] = meetingRef
        record[AttendeeStatusRecordKeys.organizer.rawValue] = organizer as CKRecordValue
        // Only write 'here' when true (never write false)
        if here == true {
            record[AttendeeStatusRecordKeys.here.rawValue] = true as CKRecordValue
            record[AttendeeStatusRecordKeys.hereUpdatedAt.rawValue] =
            (hereUpdatedAt ?? Date()) as CKRecordValue
        }
        record[AttendeeStatusRecordKeys.latitude.rawValue] = latitude as CKRecordValue
        record[AttendeeStatusRecordKeys.longitude.rawValue] = longitude as CKRecordValue
        if let eta = etaMinutes {
            record[AttendeeStatusRecordKeys.etaMinutes.rawValue] = eta as CKRecordValue
        } else {
            record[AttendeeStatusRecordKeys.etaMinutes.rawValue] = nil
        }
        // Only write 'deleted' when true (never write false)
        if deleted == true {
            record[AttendeeStatusRecordKeys.deleted.rawValue] = true as CKRecordValue
            record[AttendeeStatusRecordKeys.deletedUpdatedAt.rawValue] =
            (deletedUpdatedAt ?? Date()) as CKRecordValue
        }
        return record
    }
}
