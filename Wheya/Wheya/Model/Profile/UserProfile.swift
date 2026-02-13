//
//  UserProfile.swift
//  Wheya
//
//  Created by Yuliia Murakami on 6/30/25.
//

import Foundation
import CloudKit

// CloudKit-facing model (IO). Not persisted by SwiftData.
struct UserProfile {
    // Global variables
    static let recordType = "UserProfile"
    enum UserProfileKey {
        static let appleUserID = "appleUserID"
        static let displayName = "displayName"
        static let image = "image"
        static let updatedAt = "updatedAt"
        static let hasCustomPhoto = "hasCustomPhoto"
    }

    // The CK record ID (recordName is the Apple user ID)
    let recordID: CKRecord.ID
    // Apple Sign In unique ID
    var appleUserID: String
    var displayName: String
    var image: URL?
    var updatedAt: Date

    // Initialize from a CloudKit CKRecord
    init(record: CKRecord) {
        self.recordID = record.recordID
        self.appleUserID = record[UserProfileKey.appleUserID] as? String ?? ""
        self.displayName = record[UserProfileKey.displayName]   as? String ?? ""
        // 画像が CKAsset として保存されていれば URL を取り出す
        if let asset = record[UserProfileKey.image] as? CKAsset {
            self.image = asset.fileURL // local temp file from CK
        } else {
            self.image = nil
        }
        self.updatedAt = (record[UserProfileKey.updatedAt] as? Date) ?? (record.modificationDate ?? .distantPast) //
    }

    // Initializer for a new user (uses default zone)
    init(
        displayName: String,
        appleUserID: String,
        updatedAt: Date = Date(),
        image: URL? = nil
    ) {
        self.recordID = CKRecord.ID(recordName: appleUserID) // default zone
        self.appleUserID = appleUserID
        self.displayName = displayName
        self.image = image
        self.updatedAt = updatedAt
    }

    // Convert to a CKRecord for saving
    func toRecord() -> CKRecord {
        let record = CKRecord(recordType: Self.recordType, recordID: recordID)
        record[UserProfileKey.appleUserID] = appleUserID as CKRecordValue
        record[UserProfileKey.displayName] = displayName as CKRecordValue
        // 画像があれば CKAsset として保存
        if let imageURL = image {
            record[UserProfileKey.image] = CKAsset(fileURL: imageURL)
        }
        record[UserProfileKey.updatedAt] = updatedAt as CKRecordValue
        return record
    }
}
