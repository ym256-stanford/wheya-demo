//
//  HomeView.swift
//  MeetingUp
//
//  Created by Hiromichi Murakami on 5/23/25.
//

import SwiftUI
import SwiftData
import CloudKit

// Filter Picker
private enum DateFilter: String, CaseIterable, Identifiable {
    case all   = "All"
    case today = "Today"
    case three = "3 Days"
    case week  = "1 Week"
    var id: String { rawValue }
}

//  Uses ProfileViewModel (cache → CloudKit → cache).
//  Shows cached user avatar in toolbar and opens ProfileView on tap.
struct HomeView: View {
    // MARK: Data Shared With Me
    @Environment(Session.self) private var session
    @Environment(\.modelContext) private var cache
    @Environment(CloudKitManager.self) private var cloud
    
    // Instant Profile View
    @Query(sort: \CachedUserProfile.updatedAt, order: .reverse)
    private var cachedProfiles: [CachedUserProfile]

    // The one row for the currently signed-in user (if any)
    private var myProfileRow: CachedUserProfile? {
        guard let uid = session.appleUserID else { return nil }
        return cachedProfiles.first(where: { $0.appleUserID == uid })
    }
    
    private var currentUID: String {
        myProfileRow?.appleUserID ?? session.appleUserID ?? ""
    }
    
    // MARK: Data Owned By Me
    // Defer VM creation until we have cache
    //@State private var profileModel: ProfileViewModel?
    @State private var editingMeeting: CachedMeeting? = nil
    //@State private var showProfile = false
    @State private var showMeetingSheet: Bool = false
    //@State private var selected: CachedMeeting?
    
    @State private var selectedFilter: DateFilter = .all
    
    @Query(
        filter: #Predicate<CachedMeeting> { $0.isHidden == false },
        sort: \CachedMeeting.date, order: .forward
    )
    private var allMeetings: [CachedMeeting]
    
    // Reuse your date filter on any array
    private func applyDateFilter(_ items: [CachedMeeting]) -> [CachedMeeting] {
        let cal = Calendar.current
        let now = Date()
        let startOfDay = cal.startOfDay(for: now)
        
        func endDate(days: Int) -> Date {
            let target = cal.date(byAdding: .day, value: days - 1, to: startOfDay)!
            return cal.date(bySettingHour: 23, minute: 59, second: 59, of: target)!
        }
        
        switch selectedFilter {
        case .all:
            return items
        case .today:
            return items.filter { cal.isDateInToday($0.date) }
        case .three:
            let end = endDate(days: 3)
            return items.filter { $0.date >= startOfDay && $0.date <= end }
        case .week:
            let end = endDate(days: 7)
            return items.filter { $0.date >= startOfDay && $0.date <= end }
        }
    }
    
    private enum HomeUI {
        static let outerHPadding: CGFloat = 16   // Picker と同じに
    }
    
    // MARK: - Body
    var body: some View {
        NavigationStack {
//            let isLoading = profileModel?.isLoading ?? false
//            let profile = profileModel?.userProfile
//            let error = profileModel?.errorMessage
            //let profile = myProfileRow
            
            VStack(spacing: 16) {
                newMeetingButton
                
                Picker("Date Filter", selection: $selectedFilter) {
                    ForEach(DateFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter as DateFilter)
                    }
                }
                .pickerStyle(.segmented)
                .padding([.horizontal, .top])
                                
                List {
                    let items = applyDateFilter(allMeetings)
                    ForEach(items) { meeting in
                        NavigationLink {
                            LiveMeetingView(meeting: meeting, modelContext: cache, cloud: cloud) // reads CloudKitManager & Session from @Environment
                        } label: {
                            CardView(
                                meeting: meeting,
                                // 共有行でも常に “自分の AppleUserID” を渡す（フォールバック安定化のため）
                                //currentUserID: profileModel?.userProfile?.appleUserID
                                currentUserID: currentUID
                            )
                        }
                        .listRowSeparator(.hidden)                 // 純正線は消す
                        .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: HomeUI.outerHPadding))
                        
                        // owner can edit; shared cannot
                        .swipeActions(edge: .leading) {
                            if meeting.isOwner {
                                Button("Edit", systemImage: "pencil") { editingMeeting = meeting }
                                    .tint(.blue)
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) { deleteMeeting(meeting) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .contextMenu {
                            if meeting.isOwner {
                                Button("Edit", systemImage: "pencil") { editingMeeting = meeting }
                            }
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                deleteMeeting(meeting)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("Upcoming Meetings")
            .toolbar {
                // Avatar in the top-right.
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        ProfileView() // inherits Session & ModelContext from environment
                    } label: {
//                        ProfilePictureView(
//                            imageData: profileModel?.userProfile?.imageData,
//                            displayName: profileModel?.userProfile?.displayName,
//                            size: 32
//                        ) // cache-first bytes
                        ProfilePictureView(
                            imageData: myProfileRow?.imageData,
                            displayName: myProfileRow?.displayName,
                            size: 32
                        )
                    }
                    //.disabled(isLoading && profile == nil)
                }
            }
            // Create a meeting
            .sheet(isPresented: $showMeetingSheet) {
                MeetingSetupView(
                    meeting: nil,
//                    userName: profile?.displayName ?? "Anonymous",
//                    userImageData: profile?.imageData,
//                    userRecordID: profile?.appleUserID
                    userName: myProfileRow?.displayName ?? "Anonymous",
                    userImageData: myProfileRow?.imageData,
                    userRecordID: myProfileRow?.appleUserID
                ) { title, date, locationName, latitude, longitude, notes, shareMinutes in
                    Task {
                        let sync = MeetingSync(cache: cache, cloud: cloud)
                        if let created = await sync.createMeeting(
                            title: title,
                            date: date,
                            locationName: locationName,
                            latitude: latitude,
                            longitude: longitude,
                            notes: notes,
                            shareMinutes: shareMinutes,
//                            appleUserID: profile?.appleUserID,
//                            displayName: profile?.displayName,
//                            imageData: profile?.imageData
                            appleUserID: myProfileRow?.appleUserID,
                            displayName: myProfileRow?.displayName,
                            imageData: myProfileRow?.imageData
                        ), let rid = created.ckRecordID {
                            await ShareReminder.schedule(
                                meetingRecordName: rid.recordName,
                                meetingTitle: created.title,
                                meetingDate: created.date,
                                shareMinutes: created.shareMinutes
                            )
                        }
                    }
                }
            }
            // Edit a meeting
            .sheet(isPresented: Binding(
                get: { editingMeeting != nil },
                set: { if !$0 { editingMeeting = nil } }
            )) {
                if let editedMeeting = editingMeeting {
                    MeetingSetupView(
                        meeting: editedMeeting,
//                        userName: profile?.displayName ?? "Anonymous",
//                        userImageData: profile?.imageData,
//                        userRecordID: profile?.appleUserID
                        userName: myProfileRow?.displayName ?? "Anonymous",
                        userImageData: myProfileRow?.imageData,
                        userRecordID: myProfileRow?.appleUserID
                    ) { newTitle, newDate, newLoc, newLat, newLon, newNotes, newShareMin in
                        editedMeeting.title = newTitle
                        editedMeeting.date  = newDate
                        editedMeeting.locationName = newLoc
                        editedMeeting.latitude = newLat
                        editedMeeting.longitude = newLon
                        editedMeeting.notes = newNotes
                        editedMeeting.shareMinutes = newShareMin
                        try? cache.save()
                        Task {
                            let sync = MeetingSync(cache: cache, cloud: cloud)
                            _ = await sync.upsertMeetingFromCached(editedMeeting)
                        }
                    }
                }
            }
            .task(id: session.appleUserID) {
                if myProfileRow == nil, let uid = session.appleUserID {
                    let placeholder = CachedUserProfile(
                        appleUserID: uid,
                        displayName: "Anonymous",
                        imageData: nil,
                        updatedAt: .distantPast   // never beats real data
                    )
                    cache.insert(placeholder)
                    try? cache.save()
                }

                // Create VM when we know who the user is and we have cache
                guard let _ = session.appleUserID else { return }
                // Load UserProfile
//                if profileModel == nil {
//                    profileModel = ProfileViewModel(session: session, modelContext: cache, container: CloudManager.container, cloud: cloud)
//                }
//                await profileModel?.loadUserProfile()   // cache → cloud → cache
                
                // Load meetings
                do {
                    let privateMeetings = try await cloud.fetchAllPrivateMeetings()
                    let sharedMeetings = try await cloud.fetchAllSharedMeetings()
                    let sync = MeetingSync(cache: cache, cloud: cloud)
                    sync.importMeetings(from: privateMeetings, isOwner: true)
                    sync.importMeetings(from: sharedMeetings, isOwner: false)
                    
                    // Reconcile deletions (remove private or shared rows that disappeared on the server)
                    sync.removeMeetings(private: privateMeetings, shared: sharedMeetings)
                    
                    //await sync.fetchAndImportAttendees(for: privateMeetings, isOwner: true, currentUserID: profileModel?.userProfile?.appleUserID)
                    await sync.fetchAndImportAttendees(for: privateMeetings, isOwner: true, currentUserID: currentUID)
                    //await sync.fetchAndImportAttendees(for: sharedMeetings,  isOwner: false, currentUserID: profileModel?.userProfile?.appleUserID)
                    await sync.fetchAndImportAttendees(for: sharedMeetings,  isOwner: false, currentUserID: currentUID)
                    await sync.fetchAndImportMessages(for: privateMeetings, isOwner: true)
                    await sync.fetchAndImportMessages(for: sharedMeetings,  isOwner: false)
                    
                    sync.purgeDuplicateLocalMeetings()
                } catch {
                    #if DEBUG
                    print("[Home] fetching meetings failed: \(error)")
                    #endif
                }
            }
            // 1) SINGLE record: fired right after a user accepts a share
            .onReceive(NotificationCenter.default.publisher(for: .didAcceptSharedMeeting).receive(on: RunLoop.main)) { note in
                guard let record = note.userInfo?["record"] as? CKRecord else { return }
                
                let sync = MeetingSync(cache: cache, cloud: cloud)
                
                // Import the shared meeting into SwiftData (cache-only, isOwner = false)
                if let cached = sync.importSharedMeeting(from: record) {
                    
                    // If we have the local profile, attach this device's user + sync attendees
                    //if let profile = profileModel?.userProfile {
                    if let profile = myProfileRow {
                        // Ensure *this device’s user* exists as an attendee locally
                        sync.attachUser(
                            appleUserID: profile.appleUserID,
                            displayName: profile.displayName,
                            imageData: profile.imageData,
                            to: cached,
                            organizer: false
                        )
                        
                        // Push *only me* to the shared attendee list (participant path)
                        Task {
                            await cloud.pushAttendeesToCloud(
                                for: cached,
                                meetingRecordID: record.recordID,
                                //currentUserID: profile.appleUserID
                                currentUserID: currentUID
                            )
//                            await cloud.pushMessagesToCloud(for: cached, meetingRecordID: record.recordID, currentUserID: profile.appleUserID)
                            await cloud.pushMessagesToCloud(for: cached, meetingRecordID: record.recordID, currentUserID: currentUID)
                        }
                        
                        // Pull attendees from shared DB so organizer shows up locally
                        Task {
                            await sync.importAttendeesFromCloud(
                                for: cached,
                                meetingRecordID: record.recordID,
                                isOwner: false,
                                //currentUserID: profile.appleUserID
                                currentUserID: currentUID
                            )
                        }
                    }
                }
            }
            
            // 2) MULTIPLE records: fired when the shared zone changes and we refetched all shared meetings
            .onReceive(NotificationCenter.default.publisher(for: .didReloadSharedMeetings).receive(on: RunLoop.main)) { note in
                guard let records = note.userInfo?["records"] as? [CKRecord] else { return }
            
                let sync = MeetingSync(cache: cache, cloud: cloud)
                
                // Import all refreshed shared meetings into SwiftData
                sync.importMeetings(from: records, isOwner: false)
                
                // Reconcile deletions (remove shared rows that disappeared on the server)
                sync.removeMeetings(with: records, isOwner: false)
            }
            // Owner: private zone changed -> refresh attendees for *private* meetings
            .onReceive(NotificationCenter.default.publisher(for: .didReloadPrivateMeetings)) { note in
                guard let records = note.userInfo?["records"] as? [CKRecord] else { return }
                Task { @MainActor in
                    let sync = MeetingSync(cache: cache, cloud: cloud)
//                    await sync.fetchAndImportAttendees(for: records, isOwner: true, currentUserID: profileModel?.userProfile?.appleUserID)
                    await sync.fetchAndImportAttendees(for: records, isOwner: true, currentUserID: currentUID)
                    await sync.fetchAndImportMessages(for: records, isOwner: true)
                }
            }
            // Participant: shared DB changed -> refresh attendees for *shared* meetings
            .onReceive(NotificationCenter.default.publisher(for: .didReloadSharedMeetings)) { note in
                guard let records = note.userInfo?["records"] as? [CKRecord] else { return }
                Task { @MainActor in
                    let sync = MeetingSync(cache: cache, cloud: cloud)
//                    await sync.fetchAndImportAttendees(for: records, isOwner: false, currentUserID: profileModel?.userProfile?.appleUserID)
                    await sync.fetchAndImportAttendees(for: records, isOwner: false, currentUserID: currentUID)
                    await sync.fetchAndImportMessages(for: records, isOwner: false)
                }
            }
        }
    }
    
    private var newMeetingButton: some View {
        Button("New Meeting", systemImage: "plus.circle.fill") {
            showMeetingSheet = true
        }
        .font(.system(size: 24, weight: .semibold))
        .padding(.top)
    }
    
    // Delete meeting from Cache
    private func deleteMeeting(_ meeting: CachedMeeting) {
        Task {
            let sync = MeetingSync(cache: cache, cloud: cloud)
            //_ = await sync.deleteCached(meeting, currentUserID: profileModel?.userProfile?.appleUserID ?? "")
            _ = await sync.deleteCached(meeting, currentUserID: currentUID)
        }
    }
}

