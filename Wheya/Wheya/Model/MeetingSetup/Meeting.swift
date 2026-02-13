//
//  Meeting.swift
//  Wheya
//
//  Created by Yuliia Murakami on 7/8/25.
//

import Foundation
import CloudKit

// CloudKit record keys for the `Meeting` type.
// Keep these raw values exactly in sync with your CloudKit schema.
enum MeetingRecordKeys: String{
    case type = "Meeting"
    case createdAt
    case title
    case date
    case locationName
    case latitude
    case longitude
    case notes
    case shareMinutes
}

struct Meeting: Hashable {
    var recordID: CKRecord.ID? // Unique key for storing in CLoudKit database
    var createdAt: Date
    var title: String
    var date: Date
    var locationName: String
    var latitude: Double
    var longitude: Double
    var notes: String
    var shareMinutes: Int // LocationSharingOption
}

// Custom initializer to fetch the meetings from CloudKit database
extension Meeting {
    init?(record: CKRecord) {
        guard
            let createdAt = record[MeetingRecordKeys.createdAt.rawValue] as? Date,
            let title = record[MeetingRecordKeys.title.rawValue] as? String,
            let date = record[MeetingRecordKeys.date.rawValue] as? Date,
            let locationName = record[MeetingRecordKeys.locationName.rawValue] as? String,
            let latitude = record[MeetingRecordKeys.latitude.rawValue] as? Double,
            let longitude = record[MeetingRecordKeys.longitude.rawValue] as? Double,
            let notes = record[MeetingRecordKeys.notes.rawValue] as? String,
            let share = record[MeetingRecordKeys.shareMinutes.rawValue] as? Int
        else {
            print("Failed to initialize Meeting from record: \(record)")
            return nil
        }
        self.init(
            recordID: record.recordID,
            createdAt: createdAt,
            title: title,
            date: date,
            locationName: locationName,
            latitude: latitude,
            longitude:longitude,
            notes: notes,
            shareMinutes: share
        )
    }
}

