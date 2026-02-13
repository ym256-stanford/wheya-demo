//
//  LiveMeetingView.swift
//  Wheya
//
//  Created by Yuliia Murakami on 7/31/25.
//

import SwiftUI
import MapKit
import SwiftData
import UIKit

private typealias IdentifiablePlace = LiveMeetingViewModel.IdentifiablePlace

struct LiveMeetingView: View {
    // MARK: Data Shared With Me
    @Environment(CloudKitManager.self) private var cloudKitManager
    @Environment(Session.self) private var session
    @Environment(\.modelContext) private var cache
    @Environment(\.dismiss) private var dismiss
    @Environment(LocationSharingService.self) private var locSvc
    
    // MARK: Data In
    let meeting: CachedMeeting
    
    // MARK: Data Owned By Me
    @State private var viewModel: LiveMeetingViewModel
    @State private var showFullNote = false
    @State private var showingMessagesFull = false
    // Finish meeting
    @State private var showConfirm = false
    @State private var showCelebration = false

    @State private var shareURL: URL? = nil
    @State private var showInviteSheet = false
    @State private var isGeneratingShare = false // Creating a link to share
    
    // [Always-on design] Work in the background
    @State private var showAlways = false
    private let appStoreURL = URL(string: "https://apps.apple.com/app/wheya/id6752795883")!

    // Need this for the fast UI
    private struct InputSheet: Identifiable, Equatable {
        var id = UUID()
        var title: String
        var placeholder: String
    }
    
    // Message enter view
    @State private var inputSheet: InputSheet?
    @State private var inputText = ""
    
    init(meeting: CachedMeeting, modelContext: ModelContext, cloud: CloudKitManager) {
        self.meeting = meeting
        _viewModel = State(initialValue: LiveMeetingViewModel(cached: meeting, modelContext: modelContext, cloud: cloud))
    }
    
    private var isOwner: Bool { meeting.isOwner }
    
    // Only share if it actually exists on the server
    private var meetingForShare: Meeting? {
        guard meeting.globalID != nil else { return nil }
        return Meeting(
            recordID: meeting.ckRecordID,
            createdAt: meeting.createdAt,
            title: meeting.title,
            date: meeting.date,
            locationName: meeting.locationName,
            latitude: meeting.latitude,
            longitude: meeting.longitude,
            notes: meeting.notes,
            shareMinutes: meeting.shareMinutes
        )
    }
    
    // MARK: - Body
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: LiveMeetingConstants.vStackSpacing) {
                titleRow
                mapCard()
                infoSection
                actionButtons    // “I’m Here” / “Running Late” buttons
            }
            .padding(.horizontal)
            
            messagesSection     // Recent messages + “View more”
                .padding(.top, LiveMeetingConstants.messagesTPadding)
        }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $inputSheet) { sheet in
            MessageEnterView(
                title: sheet.title,
                text: $inputText,
                placeholder: sheet.placeholder,
                onSend: {
                    Task { @MainActor in
                        await viewModel.sendMessage(title: sheet.title, text: inputText)
                        inputText = ""
                        inputSheet = nil
                    }
                },
                onCancel: { inputSheet = nil }
            )
            .id(sheet.id) // forces a fresh view identity each time
        }
        // [Always-on design]
        .onChange(of: locSvc.authStatus, initial: false) { _, new in
            showAlways = (new != .authorizedAlways)
        }
        // [Always-on design]
        .task {
            if locSvc.authStatus != .authorizedAlways {
                showAlways = true
            }
        }
        // [Always-on design]
        .sheet(isPresented: $showAlways) {
            AlwaysLocationGateView()
                .interactiveDismissDisabled(true) // optional; if you want to force a decision
        }
//        .errorPopup(
//            isPresented: .init(
//                get: { viewModel.errorKind != nil },
//                set: { if !$0 { viewModel.errorKind = nil } }
//            ),
//            title: AppErrorUI.content(for: viewModel.errorKind ?? .generic)?.title,
//            message: AppErrorUI.content(for: viewModel.errorKind ?? .generic)?.message ?? "",
//            actions: AppErrorUI.content(for: viewModel.errorKind ?? .generic)?.actions ?? [.cancel("Close")]
//        )
        .errorPopup(
            isPresented: .init(
                get: {
                    guard let kind = viewModel.errorKind else { return false }
                    // Only show if NOT a CloudKit error AND the mapping wants UI.
                    return !isCloudKitError(kind) && (AppErrorUI.content(for: kind) != nil)
                },
                set: { if !$0 { viewModel.errorKind = nil } }
            ),
            title: {
                guard let kind = viewModel.errorKind,
                      let c = AppErrorUI.content(for: kind)
                else { return nil }
                return c.title
            }(),
            message: {
                guard let kind = viewModel.errorKind,
                      let c = AppErrorUI.content(for: kind)
                else { return "" }
                return c.message
            }(),
            actions: {
                guard let kind = viewModel.errorKind,
                      let c = AppErrorUI.content(for: kind)
                else { return [.cancel("Close")] }
                return c.actions
            }()
        )
        // Hide when not owner.
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if isOwner {
                    Button(role: .destructive) { showConfirm = true } label: {
                        Label("Finish", systemImage: "hands.sparkles")
                    }
                    shareAsTextButton     // 追加：LINE/SMS向けに確実に文面 + AppStoreリンクを出す
                }
            }
        }
        .confirmationDialog("End and delete this meeting for all attendees?",
                            isPresented: $showConfirm,
                            titleVisibility: .visible) {
            Button("End Sharing", role: .destructive) {
                showCelebration = true
                
                Task { @MainActor in
                    // Run the minimum animation time in parallel (no captures → Sendable-safe)
                    async let minShow: Void = Task.sleep(nanoseconds: 1_600_000_000)
                    
                    // Do the actual delete on the MainActor (safe for ModelContext & CachedMeeting)
                    let sync = MeetingSync(cache: cache, cloud: cloudKitManager)
                    let ok = await sync.deleteCached(meeting, currentUserID: session.appleUserID ?? "")
                    
                    // Sleep may throw on cancellation; we don't care → `try?`
                    _ = try? await minShow
                    
                    showCelebration = false
                    if ok {
                        if let rid = meeting.ckRecordID {
                            await ShareReminder.cancel(meetingRecordName: rid.recordName)
                        }
                        LocationSharingService.shared.clearActiveMeeting()
                        dismiss()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .task {
            // Start VM (inject env user id) — safe even if mapCard() is commented out
            viewModel.currentUserID = session.appleUserID
            viewModel.start()
            
            // [Always-on design] wire LocationSharingService environment
            LocationSharingService.shared.configureEnvironment(
                modelContext: cache,
                cloud: cloudKitManager,
                currentUserID: session.appleUserID
            )
            
            //  Ensure a server record and preload the share link early
            if isOwner {
                await ensureShareURL()
            }
            // This is the crucial line: tells the service which meeting to target.
            LocationSharingService.shared.setActiveMeeting(cached: meeting)
            
            // Notifications
            if let rid = meeting.ckRecordID {
                await ShareReminder.schedule(
                    meetingRecordName: rid.recordName,
                    meetingTitle: meeting.title,
                    meetingDate: meeting.date,
                    shareMinutes: meeting.shareMinutes
                )
            }
            
            // [Always-on design] show the gate if not Always
            showAlways = (locSvc.authStatus != .authorizedAlways)
            
            // Preload share
            guard isOwner, let m = meetingForShare, shareURL == nil else { return }
            do {
                let ck = try await cloudKitManager.getOrCreateShare(for: m)
                self.shareURL = ck.url
            } catch {
                print("❌ Failed to pre-load share:", error.localizedDescription)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .didReloadPrivateMeetings)) { _ in
            Task { @MainActor in
                await importDeltasForThisMeeting(reason: "private-zone reload")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .didReloadSharedMeetings)) { _ in
            Task { @MainActor in
                await importDeltasForThisMeeting(reason: "shared-zone reload")
            }
        }
        .onDisappear { viewModel.stop() }
        .overlay {
            if showCelebration {
                FireworksOverlay(isVisible: $showCelebration)
                    .transition(.opacity)
            }
        }
    }
    
    // 招待者名（自分）をできるだけ取る。取れなければ "A friend"
    private func inviterName() -> String {
        if let myID = session.appleUserID,
           let name = (meeting.attendees ?? [])
                .first(where: { $0.user?.appleUserID == myID })?
            .user?.displayName
                .trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            return name
        }
        return "A friend"
    }
    
    private func invitePlainText() -> String {
        let df = DateFormatter()
        df.locale = .autoupdatingCurrent
        df.timeZone = .autoupdatingCurrent
        df.dateStyle = .medium
        df.timeStyle = .short

        let start = meeting.date.addingTimeInterval(-TimeInterval(meeting.shareMinutes) * 60)
        let inviter = inviterName()

        // 重要：URLも含めて「文字列1個」にする（URL型を別アイテムで渡さない）
        return """
        \(inviter) has invited you to join a live meeting on Wheya!
        
        \(meeting.title)
        
        • When: \(df.string(from: meeting.date))
        • Where: \(meeting.locationName)

        Location sharing starts \(meeting.shareMinutes) min before (\(df.string(from: start))).
        
        By joining, your location will be visible to all attendees when sharing begins — and you’ll see theirs too.

        Accept invite to join when sharing starts: \(shareURL?.absoluteString ?? "")
        
        Download the app: \(appStoreURL.absoluteString)
        """
    }

    private var shareAsTextButton: some View {
        Button {
            Task {
                // URL未作成ならここで作成
                if shareURL == nil, let m = meetingForShare {
                    let ck = try? await cloudKitManager.getOrCreateShare(for: m)
                    self.shareURL = ck?.url
                }
                showInviteSheet = true
            }
        } label: {
            Image(systemName: "square.and.arrow.up")   // 好きなアイコンでOK
        }
        .sheet(isPresented: $showInviteSheet) {
            // ← ここだけ変更
            let source = ShareTextWithPreviewItemSource(
                text: invitePlainText(),
                previewTitle: invitePlainText(),
                previewImage: UIImage(named: "AppIcon") // Assets の画像名
            )
            ShareSheet(items: [source])
        }
        //.disabled(meetingForShare == nil)
        //.disabled(!isOwner)
        .disabled(!isOwner || isGeneratingShare)
    }
    
    // MARK: Sections
    private var titleRow: some View {
        Text(meeting.title)
            .font(.title2)
            .bold()
            .padding(.top, LiveMeetingConstants.titleTopPadding)
    }
    
    @ViewBuilder
    private func mapCard() -> some View {
        let cameraBinding = Binding<MapCameraPosition>(
            get: { .region(viewModel.region) },
            set: { new in if let r = new.region { viewModel.region = r } }
        )
        
        Map(position: cameraBinding, interactionModes: .all) {
            ForEach(viewModel.places) { place in
                Annotation("", coordinate: place.coordinate) {
                    markerView(for: place)
                }
            }
        }
        .frame(height: LiveMeetingConstants.mapHeight)
        .cornerRadius(LiveMeetingConstants.mapCornerRadius)
        .overlay(alignment: .bottom) {
            if !viewModel.isShareGateOpen {
                let start = meeting.date.addingTimeInterval(-TimeInterval(meeting.shareMinutes) * 60)
                LinearGradient(colors: [.clear, .black.opacity(0.5)],
                               startPoint: .top, endPoint: .bottom)
                .frame(height: 120)
                .clipShape(RoundedRectangle(cornerRadius: LiveMeetingConstants.mapCornerRadius))
                
                HStack(spacing: 10) {
                    Image(systemName: "clock.badge.exclamationmark").font(.headline)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Location sharing hasn’t started yet").font(.headline)
                        Text("Starts at \(Self.startFormatter.string(from: start))")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(12)
                .background(.thinMaterial, in: Capsule())
                .padding(.bottom, 16)
            }
        }
    }
    
    private struct NoteWidthKey: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
    }
    
    private struct WidthReader: View {
        @Binding var width: CGFloat
        var body: some View {
            GeometryReader { proxy in
                Color.clear
                    .preference(key: NoteWidthKey.self, value: proxy.size.width)
            }
            .onPreferenceChange(NoteWidthKey.self) { width = $0 }
        }
    }
    
    @State private var noteTextWidth: CGFloat = 0
    private let noteInnerPadding: CGFloat = 12  // ← Text を囲む .padding(12)
    
    private var noteHasTwoOrMoreLines: Bool {
        let note = meeting.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !note.isEmpty, noteTextWidth > 0 else { return false }
        
        // ★ テキスト実効幅（内側の 12pt × 2 を引く）
        let textWidth = max(noteTextWidth - noteInnerPadding * 2, 0)
        
        // SwiftUIの .font(.callout) と一致させる
        let font = UIFont.preferredFont(forTextStyle: .callout)
        
        // 指定幅での自然高さを取得
        let rect = (note as NSString).boundingRect(
            with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        )
        
        // ★ 小数誤差に強い行数判定：floor(高さ / 行高 + ほんの少し) >= 2
        let lines = Int(floor((rect.height / font.lineHeight) + 0.01))
        return lines >= 2
    }
    
    private var infoSection: some View {
        VStack(alignment: .leading, spacing: LiveMeetingConstants.infoSpacing) {
            TimelineView(.everyMinute) { timeline in
                let now = timeline.date
                Text("Meeting \(RelativeDateTimeFormatter().localizedString(for: meeting.date, relativeTo: now))")
                    .font(.title3).bold()
                    .monospacedDigit()
            }
            
            HStack {
                Image(systemName: "mappin.and.ellipse")
                    .foregroundColor(.blue)
                Text(meeting.locationName)
                    .font(.callout)
            }
            
            HStack {
                Image(systemName: "calendar")
                    .foregroundColor(.blue)
                Text(meeting.formattedDateTime)
                    .font(.callout)
            }
            
            let note = meeting.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            if !note.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(note)
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .lineLimit(showFullNote ? nil : 1)
                        .fixedSize(horizontal: false, vertical: true)   // ← 縦にきちんと伸びる
                        .id(showFullNote)                                // ← 再レイアウトを強制
                    
                    // ★ここを「2行以上のときだけ」に変更
                    if noteHasTwoOrMoreLines {
                        Button(showFullNote ? "Show less" : "Show more") {
                            withAnimation(.easeInOut(duration: 0.2)) { showFullNote.toggle() }
                        }
                        .font(.caption)
                        .foregroundColor(.blue)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: showFullNote)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 12))
                // ★この行を追加：実際の“note コンテナの幅”を取得
                .background(WidthReader(width: $noteTextWidth))
            }
        }
    }
    
    @ViewBuilder
    private func markerView(for place: IdentifiablePlace) -> some View {
        if place.isMeetingLocation {
            Image("custom_pin")
                .resizable()
                .frame(width: LiveMeetingConstants.pinSize,
                       height: LiveMeetingConstants.pinSize)
                .offset(y: LiveMeetingConstants.pinOffsetY)
        } else {
            attendeePinView(place: place)
        }
    }
    
    private func attendeePinView(place: IdentifiablePlace) -> some View {
        VStack(spacing: LiveMeetingConstants.etaSpacing) {
            // CHANGED: try to show avatar first; fall back to initials
            if let data = place.imageData, let ui = UIImage(data: data) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .frame(width: LiveMeetingConstants.attendeeSize,
                           height: LiveMeetingConstants.attendeeSize)
                    .clipShape(Circle())
                    .overlay(
                        Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: 2)
                    )
                    .shadow(radius: 1)
            } else {
                Circle()
                    .fill(Color.gray)
                    .frame(width: LiveMeetingConstants.attendeeSize,
                           height: LiveMeetingConstants.attendeeSize)
                    .overlay(
                        Text(initials(from: place.name ?? ""))
                            .font(.headline)
                            .foregroundColor(.white)
                    )
            }
            
            if let eta = place.etaMinutes {
                Text("\(eta) min")
                    .font(.headline)
                    .padding(LiveMeetingConstants.etaPadding)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(LiveMeetingConstants.etaCornerRadius)
            }
        }
    }
    
    // Buttons for “I’m Here” and “Running Late” that open the message sheet.
    private var actionButtons: some View {
        HStack(spacing: LiveMeetingConstants.buttonSpacing) {
            Button {
                inputSheet = .init(title: "I'm Here", placeholder: "I'm here!")
                inputText = inputSheet?.placeholder ?? ""
            } label: {
                Text("I'm Here")
                    .frame(maxWidth: .infinity)
                    .padding(LiveMeetingConstants.buttonPadding)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(LiveMeetingConstants.buttonCornerRadius)
            }
            
            Button {
                inputSheet = .init(
                    title: "Running Late",
                    placeholder: "Sorry, running late. I'll be there in few minutes!"
                )
                inputText = inputSheet?.placeholder ?? ""
            } label: {
                Text("Running Late")
                    .frame(maxWidth: .infinity)
                    .padding(LiveMeetingConstants.buttonPadding)
                    .foregroundColor(.primary)
                    .cornerRadius(LiveMeetingConstants.buttonCornerRadius)
                    .overlay(RoundedRectangle(cornerRadius: LiveMeetingConstants.buttonCornerRadius)
                        .stroke(Color.gray.opacity( LiveMeetingConstants.grayOpacity),
                                lineWidth: LiveMeetingConstants.buttonStrokeWidth))
            }
        }
        .font(.system(size: LiveMeetingConstants.buttonFontSize, weight: .semibold))
        .padding(.bottom, LiveMeetingConstants.buttonBottomPadding)
    }
    
    private func initials(from name: String) -> String {
        name.split(separator: " ").compactMap(\.first).map(String.init).joined().uppercased()
    }
    
    // Start time formatter
    private static let startFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = .autoupdatingCurrent
        f.timeZone = .autoupdatingCurrent
        f.doesRelativeDateFormatting = true
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()
    
    private var hasNote: Bool {
        !meeting.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    // Shows the two most recent messages and a “View more” button if needed.
    private var messagesSection: some View {
        let sorted = (meeting.messages ?? []).sorted { $0.timestamp > $1.timestamp }
        // ★追加：プレビュー件数を note の有無で切り替え
        let previewCount = hasNote ? 1 : 2
        // ★変更：ボタン表示条件は「全件数 > プレビュー件数」
        let showViewMore = sorted.count > previewCount
        return ScrollView {
            VStack(alignment: .leading, spacing: LiveMeetingConstants.messageRowSpacing) {
                ForEach(Array(sorted.prefix(previewCount)), id: \.persistentModelID) { msg in
                    let person = (meeting.attendees ?? [])
                        .first(where: { $0.user?.appleUserID == msg.senderAppleUserID })
                    let isHere = (meeting.attendees ?? [])
                        .first(where: { $0.user?.appleUserID == msg.senderAppleUserID })?
                        .here ?? false
                    let photo = person?.user?.imageData ?? nil
                    
                    // If you don’t have bundled avatars, pass nil for imageName
                    MessageRowView(
                        message: msg,
                        isHere: isHere,
                        imageData: photo
                    )
                }
                if showViewMore {
                    viewMoreButton
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { showingMessagesFull = true }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Recent messages")
            .accessibilityHint("Tap to view full conversation")
        }
        .padding(.horizontal, LiveMeetingConstants.messagesHPadding)
        .sheet(isPresented: $showingMessagesFull) {
            MessagesFullView(meeting: meeting)
        }
    }
    
    // Button to show full message list.
    private var viewMoreButton: some View {
        Button {
            showingMessagesFull = true
        } label: {
            Text("View more messages")
                .font(.callout)
                .foregroundColor(.blue)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, LiveMeetingConstants.viewMoreTop)
        .accessibilityLabel("View more messages")
        .accessibilityHint("Opens full message history")
    }
    
    @MainActor
    private func importDeltasForThisMeeting(reason: String) async {
        guard let rid = meeting.ckRecordID else { return }
        let sync = MeetingSync(cache: cache, cloud: cloudKitManager)
        
        // Pull latest attendees & messages for THIS meeting only
        await sync.importAttendeesFromCloud(
            for: meeting,
            meetingRecordID: rid,
            isOwner: meeting.isOwner,
            currentUserID: session.appleUserID
        )
        await sync.importMessagesFromCloud(
            for: meeting,
            meetingRecordID: rid,
            isOwner: meeting.isOwner
        )
        
        // Rebuild local projections (map pins, rainbow avatars, etc.)
        viewModel.rebuildPlacesFromCache()
    }
    
    @MainActor
    private func ensureShareURL() async {
        // Already have a URL? Done.
        if shareURL != nil { return }

        isGeneratingShare = true
        defer { isGeneratingShare = false }

        // 1) Make sure this meeting exists on the server (assigns ckRecordID/globalID)
        if meeting.ckRecordID == nil {
            let sync = MeetingSync(cache: cache, cloud: cloudKitManager)
            _ = await sync.upsertMeetingFromCached(meeting) // uploads & updates identity on success
        }

        // 2) Now create/fetch the CKShare using that identity
        guard let rid = meeting.ckRecordID else { return }
        let m = Meeting(
            recordID: rid,
            createdAt: meeting.createdAt,
            title: meeting.title,
            date: meeting.date,
            locationName: meeting.locationName,
            latitude: meeting.latitude,
            longitude: meeting.longitude,
            notes: meeting.notes,
            shareMinutes: meeting.shareMinutes
        )
        do {
            let ck = try await cloudKitManager.getOrCreateShare(for: m)
            self.shareURL = ck.url
        } catch {
            #if DEBUG
            print("❌ ensureShareURL failed:", error.localizedDescription)
            #endif
        }
    }
    
    private func isCloudKitError(_ kind: AppErrorKind) -> Bool {
        switch kind {
        // CloudKit / iCloud availability & service
        case .noICloud, .genericCloud, .networkOffline, .rateLimited(_), .quotaExceeded,
             // Data / records / assets that are CloudKit-driven in this app
             .recordNotFound, .imageEncodingFailed, .imageTooLarge:
            return true
        default:
            return false
        }
    }
}
