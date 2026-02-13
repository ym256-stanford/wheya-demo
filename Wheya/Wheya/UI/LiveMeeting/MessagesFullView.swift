//
//  MessagesFullView.swift
//  Wheya
//
//  Created by Yuliia Murakami on 9/12/25.
//

import SwiftUI

/// Shows the full list of chat messages for a meeting in a scrollable view.
struct MessagesFullView: View {
    // MARK: Data In
    /// The meeting model providing title, date, location, attendees, and messages.
    let meeting: CachedMeeting
    
    // MARK: Environment

    /// Allows this view to dismiss its presentation.
    @Environment(\.dismiss) private var dismiss
    
    // MARK: Body

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(sortedMessages, id: \.persistentModelID) { msg in
                        let person = (meeting.attendees ?? [])
                            .first(where: { $0.user?.appleUserID == msg.senderAppleUserID })
                        
                        let isHere = person?.here ?? false
                        let photo  = person?.user?.imageData   // same path as map/card views
                        
                        MessageRowView(
                            message: msg,
                            isHere: isHere,
                            imageData: photo
                        )
                        .listRowSeparator(.hidden)
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Messages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    // MARK: Computed

    /// Sorted messages by timestamp in descending order.
    private var sortedMessages: [CachedMessage] {
        (meeting.messages ?? []).sorted { $0.timestamp > $1.timestamp }
    }
}

// MARK: - Constants

private enum MessagesFullConstants {
    /// Spacing for the root VStack.
    static let rootSpacing: CGFloat = 0
    /// Padding around the header title.
    static let headerPadding: CGFloat = 16
    /// Vertical padding for the message list container.
    static let listVerticalPadding: CGFloat = 16
    /// Spacing between message rows in the list.
    static let messageVStackSpacing: CGFloat = 16
}
