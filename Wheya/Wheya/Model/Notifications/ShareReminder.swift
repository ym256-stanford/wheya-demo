//
//  ShareReminder.swift
//  Wheya
//
//  Created by Yuliia Murakami on 9/19/25.
//

import UserNotifications

enum ShareReminder {
    static func id(for recordName: String) -> String { "share-start-\(recordName)" }

    /// Schedules a single local notification for the share start time.
    /// Returns true if scheduled (permission granted + future time).
    @discardableResult
    static func schedule(meetingRecordName: String,
                         meetingTitle: String,
                         meetingDate: Date,
                         shareMinutes: Int) async -> Bool
    {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        guard granted else { return false }

        // Compute share start = meetingDate - shareMinutes
        let shareStart = meetingDate.addingTimeInterval(-TimeInterval(shareMinutes * 60))

        // If it's already in the past (or too close), skip or nudge soon.
        let fireDate = max(shareStart, Date().addingTimeInterval(3))

        // Ensure we don't duplicate
        center.removePendingNotificationRequests(withIdentifiers: [id(for: meetingRecordName)])

        // Build content
        let content = UNMutableNotificationContent()
        content.title = "Sharing has started"
        content.body = "Live sharing for “\(meetingTitle)” is starting now. Open Wheya app to shart sharing your location directly on in background."
        content.sound = .default
        // Deep-link payload so a tap takes them straight into the meeting
        content.userInfo = ["meetingRecordName": meetingRecordName]

        // Use calendar trigger to respect user’s locale/timezone
        let comps = Calendar.autoupdatingCurrent.dateComponents([.year,.month,.day,.hour,.minute,.second], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)

        let request = UNNotificationRequest(identifier: id(for: meetingRecordName),
                                            content: content,
                                            trigger: trigger)
        do {
            try await center.add(request)
            return true
        } catch {
            #if DEBUG
            print("Failed to schedule share reminder:", error.localizedDescription)
            #endif
            return false
        }
    }

    /// Call when the meeting is deleted/finished or user leaves.
    static func cancel(meetingRecordName: String) async {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [id(for: meetingRecordName)])
    }
}

