//
//  ProfileViewModel.swift
//  Wheya
//
//  Created by Hiromichi Murakami on 7/4/25.
//

import Foundation
import CloudKit
import Observation
import SwiftData
import UIKit

// App-facing profile used by views
struct AppUserProfile: Equatable, Sendable {
    let appleUserID: String
    var displayName: String
    var imageData: Data?
}

private typealias UPKey = UserProfile.UserProfileKey

@Observable
@MainActor
class ProfileViewModel {
    var userProfile: AppUserProfile?
    var isLoading = false
    var errorMessage: String?
    var errorKind: AppErrorKind? = nil

    private let session: Session
    private let modelContext: ModelContext
    private let container: CKContainer
    private let cloud: CloudKitManager
    private let meetingSync: MeetingSync

    // MARK: — Init
    init(session: Session, modelContext: ModelContext, container: CKContainer = CloudManager.container, cloud: CloudKitManager) {
        self.session = session
        self.modelContext = modelContext
        self.container = container
        self.cloud = cloud
        self.meetingSync = MeetingSync(cache: modelContext, cloud: cloud)
    }

    // Save display name (cloud → cache)
    func saveDisplayName(_ newName: String) async {
        guard let uid = session.appleUserID, !uid.isEmpty else { return }
        
        do {
            let db = container.privateCloudDatabase
            let rid = CKRecord.ID(recordName: uid)
            let record = try await db.record(for: rid)
            record[UPKey.displayName] = newName as CKRecordValue
            record[UPKey.updatedAt] = Date() as CKRecordValue
            let _ = try await db.save(record)
            // Update cache and published profile
            try upsertCacheUser(appleUserID: uid, displayName: newName, imageData: userProfile?.imageData, updatedAt: Date())
            self.userProfile?.displayName = newName
            await meetingSync.pushMyProfileToAllMeetings(
                currentUserID: uid,
                displayName: newName,
                imageData: userProfile?.imageData
            )
        } catch {
            // non-fatal
            #if DEBUG
            errorMessage = "Failed to save name: \(error.localizedDescription)"
            #endif
        }
    }

    // Load (cache → cloud → cache)
    func loadUserProfile() async {
        guard let uid = session.appleUserID, !uid.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        
        // Cache first (instant UI)
        do {
            let descriptor = FetchDescriptor<CachedUserProfile>(
                predicate: #Predicate { $0.appleUserID == uid }
            )
            if let user = try modelContext.fetch(descriptor).first {
                self.userProfile = AppUserProfile(
                    appleUserID: user.appleUserID,
                    displayName: user.displayName,
                    imageData: user.imageData
                )
            }
        } catch {
            // non-fatal
        }
        
        // PLACEHOLDER
        // If still nil, publish a placeholder so UI can render immediately
        if self.userProfile == nil {
            self.userProfile = AppUserProfile(
                appleUserID: uid,
                displayName: "Anonymous",
                imageData: nil
            )
            // Also insert a minimal cache row so subsequent launches are instant
            try? upsertCacheUser(appleUserID: uid, displayName: "Anonymous", imageData: nil, updatedAt: .distantPast)
        }
        
        // CloudKit fetch (source of truth) — will overwrite with fresh data when it arrives
        do {
            let db = container.privateCloudDatabase
            let rid = CKRecord.ID(recordName: uid)
            let record = try await db.record(for: rid)
            
            let cloudTS = (record[UPKey.updatedAt] as? Date) ?? (record.modificationDate ?? .distantPast)
            
            var name = (record[UPKey.displayName] as? String) ?? ""

            if name.isEmpty {
                // Prefer any locally edited name if present
                if let cached = try? modelContext.fetch(FetchDescriptor<CachedUserProfile>(
                    predicate: #Predicate { $0.appleUserID == uid }
                )).first, let localTS = cached.updatedAt, localTS > cloudTS, !cached.displayName.isEmpty {
                    name = cached.displayName
                } else {
                    name = "Anonymous"
                    record[UPKey.displayName] = name as CKRecordValue
                    record[UPKey.updatedAt]  = Date() as CKRecordValue
                    _ = try? await db.save(record)
                }
            }
            
            let hasCustom = (record[UPKey.hasCustomPhoto] as? NSNumber)?.boolValue ?? true
            var bytes: Data? = nil
            if hasCustom, let asset = record[UPKey.image] as? CKAsset, let url = asset.fileURL {
                bytes = try? await Task.detached { try Data(contentsOf: url) }.value
            } else {
                bytes = nil // treat placeholder as “no photo” locally → initials
            }
//            var bytes: Data? = nil
//            // Update in the background, not in the main thread
//            if let asset = record[UPKey.image] as? CKAsset, let fileURL = asset.fileURL {
//                let url = fileURL
//                bytes = try? await withCheckedThrowingContinuation { cont in
//                    DispatchQueue.global(qos: .userInitiated).async {
//                        do { cont.resume(returning: try Data(contentsOf: url)) }
//                        catch { cont.resume(throwing: error) }
//                    }
//                }
//            }
            
            // Compare timestamps before publishing/overwriting cache
            let fd = FetchDescriptor<CachedUserProfile>(predicate: #Predicate { $0.appleUserID == uid })
            let local = try? modelContext.fetch(fd).first
            let localTS = local?.updatedAt ?? .distantPast

            if cloudTS > localTS {
                // Cloud is fresher → publish and cache with cloudTS
                let freshProfile = AppUserProfile(appleUserID: uid, displayName: name, imageData: bytes)
                self.userProfile = freshProfile
                try upsertCacheUser(appleUserID: uid, displayName: name, imageData: bytes, updatedAt: cloudTS)
            } else {
                // Local is fresher → keep local UI/cache; do nothing
            }
        } catch {
            // non-fatal
            #if DEBUG
            self.errorMessage = "Failed to load profile: \(error.localizedDescription)"
            #endif
        }
    }
    
    // Upsert = Update and insert the value
    private func upsertCacheUser(appleUserID: String, displayName: String, imageData: Data?, updatedAt: Date? = nil) throws {
        let descriptor = FetchDescriptor<CachedUserProfile>(
            predicate: #Predicate { $0.appleUserID == appleUserID }
        )
        if let user = try modelContext.fetch(descriptor).first {
            user.displayName = displayName
            user.imageData = imageData
            //user.updatedAt = Date()
            if let ts = updatedAt { user.updatedAt = ts }
        } else {
            let new = CachedUserProfile(
                appleUserID: appleUserID,
                displayName: displayName,
                imageData: imageData,
                //updatedAt: Date()
                // If caller provided ts use it, else default to now for brand-new local rows
                updatedAt: updatedAt ?? Date()
            )
            modelContext.insert(new)
        }
        try modelContext.save()
    }
        
    func signOut() {
        session.signOut()
    }
    
    // MARK: Profile Image
    enum ProfileImageChange {
        case uiImage(UIImage) // user picked/took a photo
        case fileURL(URL) // if import from disk
        case remove // delete photo
    }
    
    // This function sets the profile image or erases it based on the change.
    func setProfileImage(_ change: ProfileImageChange) async {
        guard let uid = session.appleUserID, !uid.isEmpty else { return }
        if isLoading { return }
        isLoading = true
        defer { isLoading = false }
        
        var assetURL: URL?
        var bytesForCache: Data?
        var tempToDelete: URL?
        
        // Use this to mark whether the user truly has a custom (non-placeholder) photo
        let isCustomPhoto: Bool
        
        // Prepare local data/asset
        switch change {
        case .remove:
            // Generate a fallback avatar (keeps UI consistent and avoids nil asset surprises)
            let currentName: String = {
                if let name = userProfile?.displayName, !name.isEmpty { return name }
                // try cache if viewModel.userProfile is not loaded yet
                let d = FetchDescriptor<CachedUserProfile>(predicate: #Predicate { $0.appleUserID == uid })
                if let cached = try? modelContext.fetch(d).first, !cached.displayName.isEmpty {
                    return cached.displayName
                }
                return ""
            }()
            
            let avatar: UIImage = InitialsAvatar.fromName(currentName, size: 256)
            
            guard let data = avatar.jpegData(compressionQuality: 0.85) else {
                errorKind = .imageEncodingFailed
                return
            }
            
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).appendingPathExtension("jpg")
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                errorKind = .imageEncodingFailed
                return
            }
            assetURL = url
            //bytesForCache = data
            tempToDelete = url
            isCustomPhoto = false
            bytesForCache = nil
            
        case .fileURL(let url):
            assetURL = url
            isCustomPhoto = true
            // Read bytes off-main
            do {
                bytesForCache = try await Task.detached(priority: .userInitiated) {
                    try Data(contentsOf: url)
                }.value
            } catch {
                errorKind = .imageEncodingFailed
                return
            }
            
        case .uiImage(let image):
            let resized = resizeImage(image)
            do {
                // Compress + write to temp off-main
                let (data, url) = try await withCheckedThrowingContinuation { cont in
                    DispatchQueue.global(qos: .userInitiated).async {
                        do {
                            guard let data = resized.jpegData(compressionQuality: 0.8) else {
                                throw NSError(domain: "EncodeError", code: -1,
                                              userInfo: [NSLocalizedDescriptionKey: "Failed to compress image."])
                            }
                            let url = FileManager.default.temporaryDirectory
                                .appendingPathComponent(UUID().uuidString).appendingPathExtension("jpg")
                            try data.write(to: url, options: .atomic)
                            cont.resume(returning: (data, url))
                        } catch {
                            cont.resume(throwing: error)
                        }
                    }
                }
                bytesForCache = data
                assetURL = url
                tempToDelete = url
                isCustomPhoto = true
            } catch {
                errorKind = .imageEncodingFailed
                return
            }
        }
        
        // Cleanup temp file if we created one
        defer {
            if let tmp = tempToDelete {
                try? FileManager.default.removeItem(at: tmp)
            }
        }
        
        // --- OPTIMISTIC: publish to UI + cache BEFORE CloudKit ---
        let now = Date()
        var next = userProfile ?? AppUserProfile(
            appleUserID: uid,
            displayName: {
                if let n = userProfile?.displayName, !n.isEmpty { return n }
                let d = FetchDescriptor<CachedUserProfile>(predicate: #Predicate { $0.appleUserID == uid })
                if let cached = try? modelContext.fetch(d).first, !cached.displayName.isEmpty { return cached.displayName }
                return "Anonymous"
            }(),
            imageData: nil
        )
        next.imageData = bytesForCache              // nil for .remove → initials in UI
        self.userProfile = next
        try? upsertCacheUser(
            appleUserID: next.appleUserID,
            displayName: next.displayName,
            imageData: next.imageData,
            updatedAt: now                           // ensure we win against older reads
        )
        
        // CloudKit: fetch-or-create record, set asset, save, then update cache/UI
        let db = container.privateCloudDatabase
        do {
            let record = try await fetchOrCreateUserRecord(uid: uid, db: db)
            
            if let url = assetURL {
                record[UPKey.image] = CKAsset(fileURL: url)
            } else {
                record[UPKey.image] = nil
            }
            record[UPKey.updatedAt] = Date() as CKRecordValue
            record[UPKey.hasCustomPhoto] = isCustomPhoto as CKRecordValue
            _ = try await db.save(record)
            
            // Publish + cache
            var next = userProfile ?? AppUserProfile(appleUserID: uid,
                                                     displayName: {
                if let n = userProfile?.displayName, !n.isEmpty { return n }
                let d = FetchDescriptor<CachedUserProfile>(predicate: #Predicate { $0.appleUserID == uid })
                if let cached = try? modelContext.fetch(d).first, !cached.displayName.isEmpty { return cached.displayName }
                return ""
            }(),
                                                     imageData: nil)
            next.imageData = bytesForCache
            
            try upsertCacheUser(
                appleUserID: next.appleUserID,
                displayName: next.displayName,
                imageData: next.imageData,
                updatedAt: Date()
            )
            self.userProfile = next
            
            // Best-effort downstream propagation (non-fatal on failure)
            if let id = session.appleUserID, !id.isEmpty {
                await meetingSync.pushMyProfileToAllMeetings(
                    currentUserID: id,
                    displayName: next.displayName,
                    imageData: next.imageData
                )
            }
            
        } catch let ck as CKError {
            switch ck.code {
            case .notAuthenticated:
                // Mid-session iCloud sign-out
                session.signOut()
                errorKind = .noICloud
                
            case .networkUnavailable, .networkFailure,
                    .serviceUnavailable, .requestRateLimited, .zoneBusy:
                // Transient – you decided to suppress UI; emit a “silent” kind if you want telemetry
                errorKind = .networkOffline
                
            case .quotaExceeded:
                errorKind = .quotaExceeded
                
            default:
                errorKind = .genericCloud
            }
        } catch {
            errorKind = .generic
        }
    }
    
    private func fetchOrCreateUserRecord(uid: String, db: CKDatabase) async throws -> CKRecord {
        let rid = CKRecord.ID(recordName: uid)
        do {
            return try await db.record(for: rid)
        } catch let ck as CKError where ck.code == .unknownItem {
            let rec = CKRecord(recordType: UserProfile.recordType, recordID: rid)
            rec[UPKey.appleUserID] = uid as CKRecordValue
            rec[UPKey.updatedAt] = Date() as CKRecordValue
            return try await db.save(rec)
        }
    }

    private func resizeImage(_ image: UIImage, maxDimension: CGFloat = 1024) -> UIImage {
        let size = image.size
        let aspectRatio = size.width / size.height
        let newSize: CGSize
        if size.width > size.height {
            newSize = CGSize(width: maxDimension, height: maxDimension / aspectRatio)
        } else {
            newSize = CGSize(width: maxDimension * aspectRatio, height: maxDimension)
        }
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
    
    // MARK: Delete account
    @MainActor
    func deleteAccount() async {
        guard let uid = session.appleUserID, !uid.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }

        // 0) Best-effort: revoke Sign in with Apple via backend (silent on transient)
        await revokeSignInWithAppleIfPossible(userID: uid)

        // 1) Remove self from shared meetings (mark attendee row deleted)
        await removeSelfFromAllSharedMeetings(currentUserID: uid)

        // 2) Drop owned data by deleting your custom private zone
        do {
            try await CloudKitZoneManager.shared.deletePrivateZoneIfExists()
        } catch {
            // Per your policy: keep silent for CK transient/hard failures here.
            // (You're signing out locally regardless.)
        }

        // 3) Delete UserProfile record in the private DB default zone
        do {
            try await deleteUserProfileRecord(uid: uid)
        } catch {
            // Keep silent unless you want to surface a popup:
            // errorKind = .genericCloud
        }

        // 4) Clear local SwiftData cache (best effort)
        try? deleteAllLocalUserData(appleUserID: uid)

        // 5) Local sign-out/reset
        session.signOut()
        session.requiresProfileName = false
        userProfile = nil
    }
    
    // MARK: - Shared meetings: mark my attendee row as deleted

    private func removeSelfFromAllSharedMeetings(currentUserID uid: String) async {
        let fd = FetchDescriptor<CachedMeeting>(predicate: #Predicate { $0.isOwner == false })
        let shared = (try? modelContext.fetch(fd)) ?? []
        for row in shared {
            guard let rid = row.ckRecordID else { continue }
            _ = try? await cloud.upsertAttendeeStatus(
                forMeetingRecordID: rid,
                appleUserID: uid,
                displayName: nil,
                imageData: nil,
                organizer: false,
                here: nil,             // do not mutate presence
                latitude: nil,
                longitude: nil,
                etaMinutes: nil,
                deleted: true
            )
        }
    }
    
    // MARK: - Local cache purge

    private func deleteAllLocalUserData(appleUserID uid: String) throws {
        // Meetings
        for m in try modelContext.fetch(FetchDescriptor<CachedMeeting>()) {
            modelContext.delete(m)
        }
        // Attendee statuses
        for s in try modelContext.fetch(FetchDescriptor<CachedAttendeeStatus>()) {
            modelContext.delete(s)
        }
        // Messages
        for msg in try modelContext.fetch(FetchDescriptor<CachedMessage>()) {
            modelContext.delete(msg)
        }
        // Cached user profile
        let profFD = FetchDescriptor<CachedUserProfile>(
            predicate: #Predicate { $0.appleUserID == uid }
        )
        if let u = try modelContext.fetch(profFD).first {
            modelContext.delete(u)
        }
        try modelContext.save()
    }
    
    // MARK: - Sign in with Apple revocation (backend call; best-effort)

    private func revokeSignInWithAppleIfPossible(userID: String) async {
        // Call your backend to revoke the user's refresh_token with Apple.
        // (Backend constructs client_secret JWT and POSTs to https://appleid.apple.com/auth/revoke)
        do {
            try await AppBackend.shared.revokeSIWA(forAppleUserID: userID)
        } catch let urlErr as URLError {
            // Silent for offline/timeouts/etc.
            _ = urlErr
        } catch {
            // Silent; local deletion proceeds
        }
    }
    
    // MARK: - UserProfile record deletion (private DB, default zone)

    private func deleteUserProfileRecord(uid: String) async throws {
        let db = container.privateCloudDatabase
        let rid = CKRecord.ID(recordName: uid)
        do {
            _ = try await db.deleteRecord(withID: rid)
        } catch let ck as CKError where ck.code == .unknownItem {
            // Already gone — fine.
        }
    }
}
