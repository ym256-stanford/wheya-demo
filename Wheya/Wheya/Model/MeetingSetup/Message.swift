//
//  Message.swift
//  Wheya
//
//  Created by Yuliia Murakami on 9/12/25.
//

import Foundation
import CloudKit

enum MessageRecordKeys: String {
    case type = "Message"
    case meeting
    case appleUserID
    case displayName
    case text
    case timestamp
    case updatedAt
}

struct ChatMessage: Hashable {
    var recordID: CKRecord.ID?
    var meetingRef: CKRecord.Reference
    var appleUserID: String
    var displayName: String?
    var text: String
    var timestamp: Date
    var updatedAt: Date
}

extension ChatMessage {
    init?(record: CKRecord) {
        guard
            let meetingRef = record[MessageRecordKeys.meeting.rawValue] as? CKRecord.Reference,
            let appleUserID = record[MessageRecordKeys.appleUserID.rawValue] as? String,
            let text = record[MessageRecordKeys.text.rawValue] as? String,
            let timestamp = record[MessageRecordKeys.timestamp.rawValue] as? Date
        else { return nil }
        self.init(
            recordID: record.recordID,
            meetingRef: meetingRef,
            appleUserID: appleUserID,
            displayName: record[MessageRecordKeys.displayName.rawValue] as? String,
            text: text,
            timestamp: timestamp,
            updatedAt: record[MessageRecordKeys.updatedAt.rawValue] as? Date ?? (record.modificationDate ?? Date())
        )
    }
}
