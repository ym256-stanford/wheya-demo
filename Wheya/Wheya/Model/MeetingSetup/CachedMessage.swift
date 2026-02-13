//
//  CachedMessage.swift
//  Wheya
//
//  Created by Yuliia Murakami on 9/12/25.
//

import Foundation
import SwiftData
import CloudKit

// A model representing a message sent by an attendee within a meeting.

@Model
final class CachedMessage {
    @Relationship(inverse: \CachedMeeting.messages) var meeting: CachedMeeting?
    
    // Denormalized sender info (avoid requiring a CachedUserProfile inverse)
    var senderAppleUserID: String = ""
    var senderDisplayName: String = ""
    
    // Content
    var text: String = ""
    var timestamp: Date = Date()
    
    // Cloud identity (stable across zones/devices)
    var recordName: String? = nil
    var zoneName: String? = nil
    var ownerName: String? = nil
    var globalID: String? = nil  // owner::zone::recordName
    
    // Offline state
    var isDirty: Bool = false
    
    init(
        meeting: CachedMeeting? = nil,
        senderAppleUserID: String = "",
        senderDisplayName: String = "",
        text: String = "",
        timestamp: Date = Date(),
        recordName: String? = nil,
        zoneName: String? = nil,
        ownerName: String? = nil,
        globalID: String? = nil,
        isDirty: Bool = false
    ) {
        self.meeting = meeting
        self.senderAppleUserID = senderAppleUserID
        self.senderDisplayName = senderDisplayName
        self.text = text
        self.timestamp = timestamp
        self.recordName = recordName
        self.zoneName = zoneName
        self.ownerName = ownerName
        self.globalID = globalID
        self.isDirty = isDirty
    }
    
    var hasCKIdentity: Bool { globalID != nil }
    
    func updateIdentity(from rid: CKRecord.ID) {
        recordName = rid.recordName
        zoneName   = rid.zoneID.zoneName
        ownerName  = rid.zoneID.ownerName
        globalID   = rid.globalID
    }
}
