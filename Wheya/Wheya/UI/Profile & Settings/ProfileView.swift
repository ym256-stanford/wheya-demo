//
//  ProfileView.swift
//  Wheya
//
//  Created by Hiromichi Murakami on 6/4/25.
//

import SwiftUI
import SwiftData
import PhotosUI
import UIKit

// Use AppUserProfile (imageData: Data?), PhotosPicker (async),
// and ProfileViewModel (cache → CloudKit → cache).
struct ProfileView: View {
    // MARK: Data Shared With Me
    @Environment(\.dismiss) private var dismiss
    @Environment(Session.self) private var session
    @Environment(\.modelContext) private var modelContext
    @Environment(CloudKitManager.self) private var cloud
    
    // MARK: Data Owned By Me
    @State private var model: ProfileViewModel? = nil
    @State private var draftName: String = ""
    
    // Photo picking
    @State private var selectedSource: PhotoSourceType?  // Camera or library
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var selectedPreview: UIImage? // Preview picture
    @State private var showCameraPicker = false
    @State private var showPhotoLibrary = false
    @State private var showPhotoOptions = false
    @State private var showSignOutConfirmation = false
    
    // Error popup state
    @State private var showPopup = false
    @State private var popupTitle: String? = nil
    @State private var popupMessage: String = ""
    @State private var popupActions: [ErrorPopupAction] = [.cancel()]
        
    // Delete account
    @State private var showDeleteConfirm = false
    
    @State private var showInviteSheet = false

    init() {}
    
    // MARK: - Body
    var body: some View {
        let profile = model?.userProfile

        return VStack(spacing: 24) {
            if let profile {
                profilePictureSection(userProfile: profile)
                profileInfoSection(userProfile: profile)
            } else {
                ProgressView("Profile not found.")
            }
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            navigationToolbar
        }
        .confirmationDialog(
            "Delete Account",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete Account", role: .destructive) {
                Task { await model?.deleteAccount() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will remove your account data from this device and iCloud. This action can’t be undone.")
        }
        .task {
            if model == nil {
                model = ProfileViewModel(
                    session: session,
                    modelContext: modelContext,
                    container: CloudManager.container,
                    cloud: cloud
                )
                await model?.loadUserProfile()
            }
        }
        .confirmationDialog(
            "Edit profile picture",
            isPresented: $showPhotoOptions,
            titleVisibility: .visible
        ) {
            PhotoPickerConfirmation(
                selectedSource: $selectedSource,
                allowDelete: model?.userProfile?.imageData != nil,
                onDelete: {
                    Task {
                        await model?.setProfileImage(.remove)
                        selectedPreview = nil
                    }
                }
            )
        }
        .onChange(of: selectedSource) {
            switch selectedSource {
            case .camera: showCameraPicker = true
            case .photoLibrary: showPhotoLibrary = true
            case .none: break
            }
            selectedSource = nil
        }
        .onChange(of: photoPickerItem) {
            handlePhotoPickerItemChange(photoPickerItem)
        }
        // ───── Error handling ─────
        .onChange(of: model?.errorKind) { _, newKind in
            guard let kind = newKind,
                  let content = AppErrorUI.content(for: kind) else {
                // nil content => cases you want silent (e.g., network/service hiccups)
                return
            }
            popupTitle = content.title
            popupMessage = content.message
            popupActions = content.actions
            showPopup = true
            // allow same error to trigger again later
            model?.errorKind = nil
        }
        .errorPopup(
            isPresented: $showPopup,
            title: popupTitle,
            message: popupMessage,
            actions: popupActions,
            onDismiss: { showPopup = false }
        )
        .alert("Sign Out", isPresented: $showSignOutConfirmation) {
            signOutAlertActions
        } message: {
            Text("Are you sure you want to sign out?")
        }
        .safeAreaInset(edge: .bottom) {
            deleteFooter { showDeleteConfirm = true }
        }
    }
    
    private func profilePictureSection(userProfile: AppUserProfile) -> some View {
        ProfilePictureView(
            imageData: userProfile.imageData,
            selectedImage: selectedPreview,
            displayName: userProfile.displayName,
            onCameraTap: { showPhotoOptions = true },
            variant: .large
        )
        .padding(.top)
        .sheet(isPresented: $showCameraPicker) {
            ImagePickerView(
                selectedImage: $selectedPreview,
                sourceType: .camera,
                allowsEditing: true,
                onImagePicked: updateProfileImage
            )
        }
        .photosPicker(
            isPresented: $showPhotoLibrary,
            selection: $photoPickerItem,
            matching: .images
        )
    }
    
    private func profileInfoSection(userProfile: AppUserProfile) -> some View {
        List {
            Section("Profile Info") {
                let nameBinding = Binding<String>(
                    get: { model?.userProfile?.displayName ?? "" },
                    set: { newValue in
                        model?.userProfile?.displayName = newValue
                    }
                )
                NavigationLink {
                    EditNameView(name: nameBinding) { newName in
                        model?.userProfile?.displayName = newName
                        Task { await model?.saveDisplayName(newName) }
                    }
                } label: {
                    HStack {
                        Text("Name").bold()
                        Spacer()
                        Text(model?.userProfile?.displayName ?? "Anonymous")
                            .foregroundColor(.primary)
                    }
                }
            }
            Section {
                invitationLink(userProfile)
            }
            Section {
                signOutButton
            }
            .listRowBackground(Color.clear)
        }
    }
    
    private let inviteURLString = "https://apps.apple.com/app/wheya/id6752795883"

    private func invitationLink(_ profile: AppUserProfile) -> some View {
        let inviteText = "\(profile.displayName) is using Wheya to plan meetups and share location and ETA in real time.\nGet the app: \(inviteURLString)"

        return Button {
            showInviteSheet = true
        } label: {
            HStack {
                Image(systemName: "person.2.fill")
                Text("Invite a Friend")
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
            }
        }
        .sheet(isPresented: $showInviteSheet) {
            // ← ここだけ変更
            let source = ShareTextWithPreviewItemSource(
                text: inviteText,
                previewTitle: inviteText,
                previewImage: UIImage(named: "AppIcon") // Assets の画像名
            )
            ShareSheet(items: [source])
        }
    }
    
    private var signOutButton: some View {
        Button(action: { showSignOutConfirmation = true }) {
            Text("Sign Out")
                .font(DesignConstants.Button.font)
                .fontWeight(.bold)
                .foregroundColor(Color.blue.opacity(0.9))
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
    
    @ViewBuilder
    private var signOutAlertActions: some View {
        Button("Sign Out", role: .destructive) {
            model?.signOut()
        }
        Button("Cancel", role: .cancel) { }
    }
    
    @ViewBuilder
    private func deleteFooter(title: String = "Delete account",
                              action: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            Divider().opacity(0.15)
            Button(title, role: .none, action: action)
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 10)
        }
        .background(.clear)
    }

    
    @ToolbarContentBuilder
    private var navigationToolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Text("Profile")
                .font(.headline)
                .fontWeight(.bold)
        }
    }
    
    private func handlePhotoPickerItemChange(_ item: PhotosPickerItem?) {
        guard let item = item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let uiImage = UIImage(data: data) {
                await MainActor.run {
                    updateProfileImage(uiImage)
                }
            }
        }
    }
    
    private func updateProfileImage(_ image: UIImage) {
        // Show the new image immediately for instant feedback
        selectedPreview = image
        Task {
            await model?.setProfileImage(.uiImage(image))
        }
    }
}

