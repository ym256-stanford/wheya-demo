//
//  CardView.swift
//  MeetingUp
//
//  Created by Hiromichi Murakami on 5/23/25.
//

import SwiftUI
import UIKit

struct CardView: View {
    // MARK: Data In
    let meeting: CachedMeeting
    let currentUserID: String?
    
    private var attendees: [CachedAttendeeStatus] {
        // Avoid touching relationships for rows that are on their way out
        guard !meeting.isHidden else { return [] }
        return (meeting.attendees ?? []).filter { $0.user != nil }
    }
    
    private var currentUser: CachedAttendeeStatus? {
        if let id = currentUserID,
           let me = attendees.first(where: { $0.user?.appleUserID == id }) {
            return me
        }
        if let org = attendees.first(where: { $0.organizer }) { return org }
        return attendees.first
    }

    // 1) 表示安定用：必ずソートした配列を使う（同名対策で appleUserID もキーに）
    private var attendeesSorted: [CachedAttendeeStatus] {
        attendees.sorted {
            let a = ($0.user?.displayName ?? "", $0.user?.appleUserID ?? "")
            let b = ($1.user?.displayName ?? "", $1.user?.appleUserID ?? "")
            return a < b
        }
    }

    // 2) オーガナイザー（最優先）→ 未同期時の決定的フォールバック
    private var organizer: CachedAttendeeStatus? {
        // a) 本命：organizer == true（ミーティング単位のフラグ）
        if let org = attendeesSorted.first(where: { $0.organizer }) { return org } // :contentReference[oaicite:4]{index=4}
        // b) 共有行などでまだフラグが入ってない瞬間は「自分以外」を優先
        if let me = currentUserID {
            if let notMe = attendeesSorted.first(where: { $0.user?.appleUserID != me }) {
                return notMe
            }
        }
        // c) 最後の手段：先頭（※ソート済みなので“ランダム”にならない）
        return attendeesSorted.first
    }

    // 3) others は「主催者以外のみ」
    private var others: [CachedAttendeeStatus] {
        guard let org = organizer else { return Array(attendeesSorted.dropFirst()) }
        return attendeesSorted.filter { $0.id != org.id }
    }

    // MARK: Data Owned By Me
    @State private var isExpanded = false // 詳細表示のトグルフラグ
    
    // 追加：左カラムの固定幅（必要に応じて調整）
    private let leadingColumnWidth: CGFloat = 88

    // MARK: - Body
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                // 左カラム
                VStack(alignment: .center, spacing: 4) {
                    // Leading avatar + name
                    avatar(from: organizer?.user?.imageData, size: 50)

                    Text({
                        if meeting.isOwner,
                           let me = currentUserID,
                           let orgID = organizer?.user?.appleUserID,
                           me == orgID { return "Me (Organizer)" }
                        return organizer?.user?.displayName ?? ""
                    }())
                    .font(.subheadline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .multilineTextAlignment(.center)
                    .foregroundStyle((organizer?.deleted ?? false) ? .secondary : .primary)
                    
                    // 4) 「and X others」は others.count を使う
                    // （左カラム内）
                    if !others.isEmpty {
                        Button("and \(others.count) \(others.count == 1 ? "other" : "others")") {
                            isExpanded.toggle()
                        }
                        .font(.caption)
                        .foregroundColor(.blue)
                        .buttonStyle(.borderless)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    }
                    
                }
                .frame(width: leadingColumnWidth, alignment: .top) // ★ここだけで横位置が固定される
                    
                VStack(alignment: .leading, spacing: 4) {
                    Text(meeting.title)
                        .font(.headline)

                    Text(meeting.locationName)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text(meeting.date
                        .formatted(date: .abbreviated, time: .shortened))
                        .font(.subheadline)
                    
                    // ノートが空でない場合のみ表示
                    if !meeting.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "note.text")
                                .foregroundColor(.secondary)
                            Text(meeting.notes)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .lineLimit(isExpanded ? 3 : 1) // 畳む時1行／展開時最大3行
                        }
                        .padding(.top, 2)
                    }
                }
                Spacer()
            }
            
            // 詳細展開時の参加者一覧
            if isExpanded && !others.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(others) { attendee in
                        HStack(spacing: 8) {
                            avatar(from: attendee.user?.imageData, size: 24)
                            Text(attendee.user?.displayName ?? "")
                                .font(.subheadline)
                                .lineLimit(1)
                                .foregroundStyle(attendee.deleted ? .secondary : .primary)
                            
                            if attendee.deleted {
                                StatusTag(text: "Left Meeting", systemImage: "rectangle.portrait.and.arrow.right")
                            }
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Avatars
    @ViewBuilder
    private func avatar(from data: Data?, size: CGFloat) -> some View {
        if let data, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay(Circle().stroke(.white, lineWidth: 1))
                .shadow(radius: 1)
        } else {
            Circle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: size, height: size)
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.system(size: size * 0.5))
                        .foregroundColor(.white)
                )
        }
    }
    
    #if DEBUG
    private func statusText(for a: CachedAttendeeStatus) -> String {
        if a.deleted { return "Deleted" }          // or "Left meeting"
        if a.here { return "Here" }
        if let eta = a.etaMinutes { return "ETA \(eta)m" }
        return "Sharing"
    }
    #endif
    
    struct StatusTag: View {
        let text: String
        let systemImage: String?
        var body: some View {
            Label(text, systemImage: systemImage ?? "")
                .labelStyle(.titleAndIcon)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.thinMaterial, in: Capsule())
                .accessibilityElement(children: .combine)
        }
    }

}

