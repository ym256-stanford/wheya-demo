//
//  MeetingSetupView.swift
//  Wheya
//
//  Created by Yuliia Murakami on 7/8/25.
//

import SwiftUI
import MapKit
import CloudKit

struct MeetingSetupView: View {
    // MARK: Data Shared With Me
    @Environment(\.dismiss) private var dismiss
    // If nil => "create" mode. If non-nil => "edit" mode.
    let meeting: CachedMeeting?
    
    // Save action provided by the caller (HomeView or a coordinator).
    // For "create": gets the new title. For "edit": gets the updated title.
    let onSave: (_ title: String, _ date: Date, _ locationName: String, _ latitude: Double, _ longitude: Double, _ notes: String, _ shareMinutes: Int) -> Void
    
    // MARK: Data Owned By Me
    @State private var editor: Meeting // (all edits go here)
    // Keep the original so Cancel can restore it
    // Local draft title so we don’t mutate SwiftData until Save.
    //    @State private var title: String = ""
    //    @State private var pickedDate: Date = Date()
    // Local UI states not stored in CloudKit
    @State private var locationSharingOption: LocationSharingOption = .preset(10)
    @State private var isShowingCustomPicker = false
    @State private var customMinutes = 5
    
    // MARK: Data In
    // User info for display
    var userName: String
    let userImageData: Data?
    var userRecordID: String?
    
    private var isLocationValid: Bool {
        let hasName = editor.locationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let hasCoords = !(editor.latitude == 0 && editor.longitude == 0)
        return hasName && hasCoords
    }
    
    init(
        meeting: CachedMeeting? = nil,
        userName: String,
        userImageData: Data?,
        userRecordID: String?,
        onSave: @escaping (_ title: String, _ date: Date, _ locationName: String, _ latitude: Double, _ longitude: Double, _ notes: String, _ shareMinutes: Int) -> Void
    ) {
        self.meeting = meeting
        self.userName = userName
        self.userImageData = userImageData
        self.userRecordID = userRecordID
        self.onSave = onSave
        // Note: we set _title in .onAppear to avoid @State init issues
        
        // Seed local editor from cache or defaults
        let seed = Meeting(
            recordID: meeting?.ckRecordID,
            createdAt: meeting?.createdAt ?? Date(),
            title: meeting?.title ?? "",
            date: meeting?.date ?? Date(),
            locationName: meeting?.locationName ?? "",
            latitude: meeting?.latitude ?? 0,
            longitude: meeting?.longitude ?? 0,
            notes: meeting?.notes ?? "",
            shareMinutes: meeting?.shareMinutes ?? 10
        )
        _editor = State(initialValue: seed)
    }
    
    // MARK: - Body
    var body: some View {
        NavigationStack {
            List {
                meetingInfoSection
                settingsSection
                organizerSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Meeting Setup")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let title = editor.title.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(title, editor.date, editor.locationName, editor.latitude, editor.longitude,
                               editor.notes,
                               editor.shareMinutes
                        )
                        dismiss()
                    }
                    .disabled(!isLocationValid)
                }
            }
        }
        .sheet(isPresented: $isShowingCustomPicker) {
            VStack(spacing: 16) {
                Text("Custom Location Sharing").font(.headline)
                Picker("Minutes", selection: $customMinutes) {
                    ForEach(1...60, id: \.self) { Text("\($0) min").tag($0) }
                }
                .pickerStyle(.wheel)
                .labelsHidden()
                Divider()
                HStack {
                    Button("Cancel") { isShowingCustomPicker = false }
                    Spacer()
                    Button("Save") {
                        locationSharingOption = .custom(customMinutes)
                        editor.shareMinutes = customMinutes
                        isShowingCustomPicker = false
                    }
                }.padding(.horizontal)
            }
            .padding()
        }
    }
    
    private var meetingInfoSection: some View {
        Section(header: Text("Meeting Info")) {
            // Title
            NavigationLink {
                EditTitleView(title: $editor.title, isNew: meeting == nil)
            } label: {
                HStack {
                    Text("Title").bold()
                    Spacer()
                    Text(editor.title.isEmpty ? "Add Title" : editor.title)
                        .foregroundColor(editor.title.isEmpty ? .secondary : .primary)
                }
            }
            
            // Date
            HStack {
                Text("Date").bold()
                Spacer()
                DatePicker("", selection: $editor.date, displayedComponents: .date)
                    .datePickerStyle(.compact)
            }
            
            // Time
            HStack {
                Text("Time").bold()
                Spacer()
                DatePicker("", selection: $editor.date, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.compact)
            }
            
            // Search by text (bind whole Meeting)
            NavigationLink {
                LocationSearchView(meeting: $editor, isNew: meeting == nil)
            } label: {
                HStack {
                    Text("Location").bold()
                    Spacer()
                    Text(editor.locationName.isEmpty ? "Add Location" : editor.locationName)
                        .foregroundColor(editor.locationName.isEmpty ? .secondary : .primary)
                        .lineLimit(1)
                }
            }
            
            // 地図でピン入力
            NavigationLink {
                LocationPickerView(
                    locationName: $editor.locationName,
                    coordinate: Binding(
                        get: { CLLocationCoordinate2D(latitude: editor.latitude, longitude: editor.longitude) },
                        set: { newCoord in
                            editor.latitude = newCoord.latitude
                            editor.longitude = newCoord.longitude
                        }
                    )
                )
            } label: {
                HStack {
                    Text("Location (Map)").bold()
                    Spacer()
                    Image(systemName: "map")
                }
            }
            
            // ノート入力
            NavigationLink {
                EditNotesView(title: $editor.notes, isNew: editor.notes.isEmpty)
            } label: {
                HStack {
                    Text("Notes").bold()
                    Spacer()
                    Text(editor.notes.isEmpty ? "Add Notes" : editor.notes)
                        .foregroundColor(editor.notes.isEmpty ? .secondary : .primary)
                }
            }
        }
    }
    
    private var settingsSection: some View {
        Section(
            header: Text("Location Sharing"),
            footer: Text("Stops sharing when the organizer ends the meeting")
                .font(.footnote)
                .foregroundColor(.secondary)
        ) {
            HStack {
                Text("Start Time").bold()
                Spacer()
                Menu {
                    ForEach(LocationSharingOption.presets) { option in
                        Button(option.displayText) {
                            locationSharingOption = option
                            editor.shareMinutes = option.minutes
                        }
                    }
                    Divider()
                    Button("Custom...") {
                        if case .custom(let m) = locationSharingOption { customMinutes = m }
                        else { customMinutes = 10 }
                        isShowingCustomPicker = true        // ← フラグを立てるだけ
                    }
                } label: {
                    Text(locationSharingOption.displayText)
                        .foregroundColor(.blue)
                }
            }
        }
    }

    
    private var organizerSection: some View {
        Section(
            header: Text("Organizer"),
            footer: Text("You can share the meeting once it’s set up")
                .font(.footnote)
                .foregroundColor(.secondary)
        ) {
            HStack(spacing: 12) {
                ProfilePictureView(imageData: userImageData, displayName: userName, size: 32)
                Text(userName).font(.body)
            }
        }
    }
}
