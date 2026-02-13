//
//  LiveMeetingViewModel.swift
//  Wheya
//
//  Created by Hiromichi Murakami on 7/28/25.
//

import Foundation
import MapKit
import CoreLocation
import Observation
import SwiftData
import CloudKit

@MainActor
@Observable
final class LiveMeetingViewModel: NSObject, CLLocationManagerDelegate {

    struct IdentifiablePlace: Identifiable {
        var id: String
        var coordinate: CLLocationCoordinate2D
        var name: String?
        var isMeetingLocation: Bool
        var etaMinutes: Int?
        var imageData: Data? = nil
    }

    private struct Const {
        static let etaCooldownSec: TimeInterval = 45
        static let cachePollSec: TimeInterval = 4
    }
    
    @ObservationIgnored private var consecutivePushFailures = 0  // reduce spam
    
    // MARK: Data In
    private let cached: CachedMeeting
    private let meeting: Meeting
    private let modelContext: ModelContext
    private let cloud: CloudKitManager

    // User info
    var currentUserID: String? { didSet { rebuildPlacesFromCache() } }
    
    // Live user info
    private var userLocation: CLLocationCoordinate2D?
    private var userETA: Int?
    
    // Timers
    private var etaTimer: Timer?
    private var cachePollTimer: Timer?
    private var gateOpenTimer: Timer?
    
    // Map state
    var region: MKCoordinateRegion
    var places: [IdentifiablePlace] = []
    var isShareGateOpen = false

    // Location
    private let locationManager = CLLocationManager()
    private var lastRegion: MKCoordinateRegion?
    private var lastETATime: Date?
    // Background behavior: only when the live-share window is open
    private var wantsBackgroundTracking: Bool { isShareGateOpen }
    private var lastUploadAt: Date?
    private var lastUploadCoord: CLLocationCoordinate2D?
    // Don't update loction after "I'm Here"
    private var suppressSelfLocation = false
    
    // Error
    var errorKind: AppErrorKind?
    
    init(cached: CachedMeeting, modelContext: ModelContext, cloud: CloudKitManager) {
        self.cached = cached
        self.modelContext = modelContext
        self.cloud = cloud
        self.meeting = Meeting(
            recordID: cached.ckRecordID,
            createdAt: cached.createdAt,
            title: cached.title,
            date: cached.date,
            locationName: cached.locationName,
            latitude: cached.latitude,
            longitude: cached.longitude,
            notes: cached.notes,
            shareMinutes: cached.shareMinutes
        )
        self.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: cached.latitude, longitude: cached.longitude),
            span: MKCoordinateSpan(latitudeDelta: LiveMeetingConstants.minDelta, longitudeDelta: LiveMeetingConstants.minDelta)
        )
        super.init()
        locationManager.delegate = self
    }

    // Lifecycle
    func start() {
        dbg("START",
                "shareStart:", shareStartDate,
                "now>=", Date() >= shareStartDate,
                "gateOpen:", isShareGateOpen)
        openShareGateIfNeeded()
        if !isShareGateOpen { scheduleGateOpenTimer() }
        rebuildPlacesFromCache()
        startCachePollingIfNeeded()
    }

    func stop() {
        dbg("STOP: timers invalidated, stopping CL")
        etaTimer?.invalidate(); etaTimer = nil
        gateOpenTimer?.invalidate(); gateOpenTimer = nil
        cachePollTimer?.invalidate(); cachePollTimer = nil
        // [Always-on design] Don't disable background CL here.
        // leave locationManager running; uploads remain time-gated
        
        // Legacy: Turn off background behavior when leaving the screen
//        locationManager.allowsBackgroundLocationUpdates = false
//        locationManager.pausesLocationUpdatesAutomatically = true
//        locationManager.stopUpdatingLocation()
    }

    // Schedules a one-shot timer to auto-open the “live sharing” gate at `shareStartDate`.
    //
    // Behavior:
    // - If the share window is already open or `shareStartDate` is in the past, returns without scheduling.
    // - Otherwise invalidates any existing gate timer and schedules a new one to fire after
    //   `shareStartDate.timeIntervalSinceNow`.
    // - When the timer fires, hops to the main actor and:
    //     - sets `isShareGateOpen = true`
    //     - calls `configureLocation()` to begin location updates / ETA flow
    //     - calls `rebuildPlacesFromCache()` to update pins/region immediately
    //
    // Threading:
    // - The timer’s closure is `@Sendable`; mutations are wrapped in `Task { @MainActor … }`
    //   to satisfy Swift 6’s actor isolation rules.
    //
    // Lifecycle:
    // - Called from `start()` only when the gate is still closed.
    // - The timer is invalidated in `stop()` to avoid firing after the view disappears.
    private func scheduleGateOpenTimer() {
        guard !isShareGateOpen else { return }
        let remaining = shareStartDate.timeIntervalSinceNow
        guard remaining > 0 else { return }   // don’t schedule a 0s timer
        dbg("⏰ scheduleGateOpenTimer in", Int(remaining), "sec")
        gateOpenTimer?.invalidate()
        
        gateOpenTimer = Timer.scheduledTimer(withTimeInterval: remaining, repeats: false) { [weak self] _ in
            // This closure is @Sendable; do NOT touch main-actor state directly here.
            Task { @MainActor [weak self] in
                guard let self, !self.isShareGateOpen else { return }
                self.isShareGateOpen = true
                self.configureLocation()
                self.startCachePollingIfNeeded()
                self.rebuildPlacesFromCache()
            }
        }
    }
    
    // The time when can start sharing
    private var shareStartDate: Date {
        meeting.date.addingTimeInterval(-TimeInterval(meeting.shareMinutes) * 60)
    }
    
    private var canShareNow: Bool { Date() >= shareStartDate }

    // Opens or closes the “live location sharing” gate based on time.
    //
    // - If now >= (meeting.date - shareMinutes), sets `isShareGateOpen = true` and
    //   calls `configureLocation()` to begin location updates / ETA refreshes.
    // - Otherwise keeps the gate closed and limits the map to the meeting pin only
    //   (the UI shows a “Location sharing hasn’t started yet” banner).
    // - Called from `start()` when `LiveMeetingView` appears; also gates cache
    //   polling and ETA requests elsewhere.
    private func openShareGateIfNeeded() {
        // [Always-on design] Always start CL so the OS can wake us in background via CL
        configureLocation()
        
        // Legacy: only start sharing when can share now
        if canShareNow {
            dbg("Gate OPEN (now>=start). Configure location.")
            isShareGateOpen = true
            configureLocation()
        } else {
            dbg("Gate CLOSED (now<start). Meeting pin only.")
            isShareGateOpen = false
            rebuildPlacesFromCache()
            // keep running in low-power mode until time window opens
        }
    }
    
    // Rebuilds map pins (`places`) and camera (`region`) from cached and live state.
    // This is the single source of truth for what the map displays.
    //
    // Behavior:
    // - When the share gate is CLOSED:
    //     - Shows only the meeting pin and recenters around the venue.
    // - When the share gate is OPEN:
    ///     - Builds attendee pins:
    //         • Adds a “You” pin if `userLocation` is available (with `userETA` and `imageData`).
    //         • Adds other attendees from `cached.attendees`, skipping the current user and
    //           ignoring rows with (0,0) coordinates.
    //     - Updates `region` to fit the meeting + all attendee coordinates (with padding).
    //     - Sets `places` with the meeting pin first, followed by attendees.
    //
    // Called from:
    // - `start()` (initial render)
    // - the 4s polling timer in `startCachePollingIfNeeded()` (only while the gate is open)
    // - after location auth/updates via `configureLocation()` and location delegate callbacks
    // - after ETA calculation in `requestETA()`
    // - when the gate auto-opens in `scheduleGateOpenTimer()`
    // - when `currentUserID` changes (didSet)
    func rebuildPlacesFromCache() {
        guard isShareGateOpen else {
            dbg("rebuild: gate CLOSED → meeting-only pin")
            places = [IdentifiablePlace(
                id: "meeting",
                coordinate: meeting.coordinate,
                name: meeting.locationName,
                isMeetingLocation: true,
                etaMinutes: nil,
                imageData: nil
            )]
            updateRegionIfNeeded(meeting: meeting, attendeeCoords: [])
            return
        }
        
        // Gate is open
        dbg("rebuild: gate OPEN.",
            "selfUser:", currentUserID ?? "nil",
            "userLoc:", fmt(userLocation))
        var attendees: [IdentifiablePlace] = []
        let rows = cached.attendees ?? []
        
        dbg("rebuild: gate OPEN, cached.attendees:", rows.count,
                "selfUser:", currentUserID ?? "nil",
                "userLoc:", fmt(userLocation))
        
        // Add yourself
        if let u = userLocation, !suppressSelfLocation {
            let selfRow = rows.first(where: { $0.user?.appleUserID == currentUserID })
            if selfRow?.here == true {
                dbg("rebuild: skip 'You' pin since here==true")
            } else {
                attendees.append(IdentifiablePlace(
                    id: "you",
                    coordinate: u,
                    name: "You",
                    isMeetingLocation: false,
                    etaMinutes: userETA,
                    imageData: selfRow?.user?.imageData
                ))
            }
        }
        
        for row in rows {
            if let uid = currentUserID, uid == row.user?.appleUserID { continue }
            // Skip participants who already come
            if row.here == true { continue }
            
            let lat = row.latitude, lon = row.longitude
            if lat == 0 && lon == 0 { dbg(" - skip attendee (0,0):", row.user?.displayName ?? "unknown")
                continue }
            // Stable fallback ID (prevents pin flicker across polls)
            let rawID =
                row.user?.appleUserID
                ?? row.attendeeGlobalID  // owner::zone::recordName
                ?? row.attendeeRecordName // still stable within zone
                ?? "anonymous"
            
            attendees.append(IdentifiablePlace(
                    id: "attendee_\(rawID)",
                    coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                    name: row.user?.displayName,
                    isMeetingLocation: false,
                    etaMinutes: row.etaMinutes,
                    imageData: row.user?.imageData
                ))
            dbg(" + attendee:", row.user?.displayName ?? rawID,
                        "(", String(format: "%.5f, %.5f", lat, lon), "eta:", row.etaMinutes ?? -1, ")")
        }

        updateRegionIfNeeded(meeting: meeting, attendeeCoords: attendees.map(\.coordinate))
        places = [IdentifiablePlace(
            id: "meeting",
            coordinate: meeting.coordinate,
            name: meeting.locationName,
            isMeetingLocation: true,
            etaMinutes: nil,
            imageData: nil
        )] + attendees
    }
    
    private func startCachePollingIfNeeded() {
        cachePollTimer?.invalidate()
        guard isShareGateOpen else {
            return
        }
        cachePollTimer = Timer.scheduledTimer(withTimeInterval: Const.cachePollSec, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.rebuildPlacesFromCache() }
        }
    }


    // Updates the map camera (`region`) only when the computed region meaningfully changes.
    //
    // Flow:
    // - Builds a target region with `computeRegion(meeting:attendeeCoords:)`,
    //   which fits the meeting location plus attendee coordinates with padding
    //   and enforces a minimum span.
    // - Compares the new region to `lastRegion` and **debounces** tiny differences:
    //     - center latitude/longitude delta < 0.0001° (≈11 m latitude)
    //     - span latitude/longitude delta < 0.0005°
    //   If all deltas are below thresholds, returns early to prevent jitter and
    //   unnecessary view updates.
    // - When above thresholds, assigns `region = computed` and caches it in `lastRegion`.
    //
    // Called via `rebuildPlacesFromCache()`:
    // - on initial render (`start()`),
    // - when the share gate auto-opens,
    // - on each 4s poll while sharing,
    // - after location/ETA updates,
    // - and when `currentUserID` changes.
    private func updateRegionIfNeeded(meeting: Meeting, attendeeCoords: [CLLocationCoordinate2D]) {
        let computed = Self.computeRegion(meeting: meeting, attendeeCoords: attendeeCoords)
        if let last = lastRegion {
            let latDiff = abs(last.center.latitude - computed.center.latitude)
            let lonDiff = abs(last.center.longitude - computed.center.longitude)
            let spanLatDiff = abs(last.span.latitudeDelta - computed.span.latitudeDelta)
            let spanLonDiff = abs(last.span.longitudeDelta - computed.span.longitudeDelta)
            if latDiff < 0.0001 && lonDiff < 0.0001 && spanLatDiff < 0.0005 && spanLonDiff < 0.0005 {
                return
            }
        }
        region = computed
        lastRegion = computed
    }

    static func computeRegion(meeting: Meeting, attendeeCoords: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        var all = attendeeCoords
        all.append(meeting.coordinate)
        let lats = all.map(\.latitude)
        let lons = all.map(\.longitude)

        let minLat = lats.min() ?? meeting.latitude
        let maxLat = lats.max() ?? meeting.latitude
        let minLon = lons.min() ?? meeting.longitude
        let maxLon = lons.max() ?? meeting.longitude

        var span = MKCoordinateSpan(
            latitudeDelta: max(LiveMeetingConstants.minDelta, (maxLat - minLat) * LiveMeetingConstants.regionPadding),
            longitudeDelta: max(LiveMeetingConstants.minDelta, (maxLon - minLon) * LiveMeetingConstants.regionPadding)
        )
        if span.latitudeDelta.isNaN || span.longitudeDelta.isNaN {
            span = MKCoordinateSpan(latitudeDelta: LiveMeetingConstants.minDelta, longitudeDelta: LiveMeetingConstants.minDelta)
        }

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )

        return MKCoordinateRegion(center: center, span: span)
    }
    
    // Configures Core Location and primes the VM with a location ASAP.
    //
    // Behavior:
    // - Sets desired accuracy to `kCLLocationAccuracyBest`.
    // - If auth is `.notDetermined`, requests When-In-Use authorization.
    // - If authorized, starts continuous updates:
    //     - If a last known location exists, immediately:
    //         • sets `userLocation`
    //         • calls `rebuildPlacesFromCache()` to update pins/region
    //         • calls `scheduleETAUpdate()` to kick the ETA timer
    //     - Otherwise calls `requestLocation()` as a one-shot bootstrap.
    // - No action for denied/restricted states.
    //
    // Flow:
    // - Called when the share gate opens (from `openShareGateIfNeeded()` or the gate timer),
    //   and again from `locationManager(_:didChangeAuthorization:)` when auth becomes allowed.
    // - Subsequent updates are handled in `didUpdateLocations` (which also rebuilds and schedules ETA).
    private func configureLocation() {
        // 1) Power/behavior hints
        locationManager.activityType = .otherNavigation
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters // low power baseline

        switch locationManager.authorizationStatus {
        case .notDetermined:
            dbg("→ requestWhenInUseAuthorization")
            // First prompt: When-In-Use
            locationManager.requestWhenInUseAuthorization()
            return  // wait for `didChangeAuthorization` to re-enter here

        case .authorizedWhenInUse:
            // [Always-on design]
            // escalate to Always for your only mode
            locationManager.requestAlwaysAuthorization()
            return

        case .authorizedAlways:
            // [Always-on design] Always-on background capability
            locationManager.allowsBackgroundLocationUpdates = true
            // Low power before gate, high power during gate:
            locationManager.pausesLocationUpdatesAutomatically = !isShareGateOpen
            locationManager.desiredAccuracy = isShareGateOpen ? kCLLocationAccuracyBest
                                                              : kCLLocationAccuracyHundredMeters
            // Keep a continuous stream (foreground)…
            locationManager.startUpdatingLocation()
            // …and add SLC so iOS can wake/relaunch us in background
            if CLLocationManager.significantLocationChangeMonitoringAvailable() {
                locationManager.startMonitoringSignificantLocationChanges()
            }

            // 4) Bootstrap the UI immediately (don’t wait for the first callback)
            if let loc = locationManager.location?.coordinate {
                dbg("Bootstrap with lastKnown:", fmt(loc))
                userLocation = loc
                rebuildPlacesFromCache()
                scheduleETAUpdate()
            } else {
                dbg("No lastKnown → requestLocation()")
                locationManager.requestLocation() // one-shot to get an initial fix
            }

        default:
            dbg("Auth denied/restricted → no-op")
            // .denied / .restricted: nothing to do (consider surfacing a UI hint)
            break
        }
    }

    // These delegate requirements are nonisolated; forward to the main actor before mutating state.

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didChangeAuthorization status: CLAuthorizationStatus) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if status == .authorizedAlways || status == .authorizedWhenInUse {
                self.configureLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        guard let coord = locations.last?.coordinate else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            if self.suppressSelfLocation { return } // 🚫 after “here”, ignore
            self.userLocation = coord
            self.rebuildPlacesFromCache()
            self.scheduleETAUpdate()
            self.pushSelfLocationIfNeeded(reason: "location")
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didFailWithError error: Error) {
        // If you ever log to UI, hop to main actor; for print it’s fine either way.
        Task { @MainActor in
            dbg("Location error:", error.localizedDescription)
        }
    }

    private func scheduleETAUpdate() {
        guard isShareGateOpen, !suppressSelfLocation else { return }
        if let last = lastETATime, Date().timeIntervalSince(last) < Const.etaCooldownSec {
            dbg("ETA cooldown skip. Next in", Int(Const.etaCooldownSec - Date().timeIntervalSince(last)), "s")
            return }
        lastETATime = Date()
        dbg("ETA schedule after 2s")
        etaTimer?.invalidate()
        etaTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak self] _ in
            Task { @MainActor in await self?.requestETA() }
        }
    }

    private func requestETA() async {
        guard let u = userLocation else { dbg("ETA abort: userLocation=nil"); return }
        let src = MKMapItem(placemark: .init(coordinate: u))
        let dest = MKMapItem(placemark: .init(coordinate: meeting.coordinate))
        let req = MKDirections.Request()
        req.source = src
        req.destination = dest
        req.transportType = .automobile
        dbg("ETA request from", fmt(u), "→", fmt(meeting.coordinate))
        do {
            let resp = try await MKDirections(request: req).calculate()
            let sec = resp.routes.first?.expectedTravelTime ?? 0
            userETA = Int(ceil(sec / 60.0))
            dbg("ETA ok:", userETA ?? -1, "min")
            rebuildPlacesFromCache()
            pushSelfLocationIfNeeded(reason: "eta")
        } catch {
            print("ETA error:", error.localizedDescription)
        }
    }
    
    private func distanceMeters(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }

    private func pushSelfLocationIfNeeded(reason: String) {
        guard isShareGateOpen, !suppressSelfLocation,
              let me = currentUserID,
              let coord = userLocation,
              let rid = meeting.recordID else { return }

        // throttle: every ≥10s OR moved ≥15m
        let now = Date()
        if let last = lastUploadAt, now.timeIntervalSince(last) < 10,
           let prev = lastUploadCoord, distanceMeters(prev, coord) < 15 {
            return
        }
        
        if let meRow = (cached.attendees ?? []).first(where: { $0.user?.appleUserID == me }),
           meRow.deleted {
            dbg("Skip self-location push: I'm deleted")
            return
        }

        // 1) Update my local cached attendee row so UI shows immediately
        if let meRow = (cached.attendees ?? []).first(where: { $0.user?.appleUserID == me }) {
            meRow.latitude = coord.latitude
            meRow.longitude = coord.longitude
            meRow.etaMinutes = userETA
            try? modelContext.save()
        }

        // 2) Push to CloudKit so others see it
        let isOrganizer = (cached.attendees ?? [])
            .first(where: { $0.user?.appleUserID == me })?.organizer ?? false

        Task { [weak cloud] in
            guard let cloud else { return }
            do {
                _ = try await cloud.upsertAttendeeStatus(
                    forMeetingRecordID: rid,
                    appleUserID: me,
                    displayName: nil,
                    imageData: nil,
                    organizer: isOrganizer,
                    here: nil,
                    latitude: coord.latitude,
                    longitude: coord.longitude,
                    etaMinutes: self.userETA,
                    deleted: nil // ← don’t reset deleted during movement/ETA updates
                )
                await MainActor.run { consecutivePushFailures = 0 }
            } catch {
                dbg("⚠️ pushSelfLocationIfNeeded failed:", error.localizedDescription)
                await MainActor.run {
                    consecutivePushFailures += 1
                    // show a popup only if this keeps failing
                    if consecutivePushFailures >= 3 {
                        if let ck = error as? CKError {
                            errorKind = mapCKErrorToKind(ck)   // maps to your existing enum
                        } else {
                            errorKind = .generic
                        }
                    }
                }
            }
        }

        lastUploadAt = now
        lastUploadCoord = coord
    }
    
    // Sends a message for this meeting. If `title == "I'm Here"`,
    // we also mark the current user as here *after* the message is sent,
    // and we stop local location sharing (so "You" disappears).
    @MainActor
    func sendMessage(title: String, text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            dbg("sendMessage: empty → abort")
            return
        }
        guard let myID = currentUserID else {
            dbg("sendMessage: currentUserID=nil → abort")
            return
        }
        
        // Look up my display name from cache
        let myDisplayName = (cached.attendees ?? [])
            .first(where: { $0.user?.appleUserID == myID })?
            .user?.displayName
        
        dbg("sendMessage:", #""\#(trimmed)""#, "title:", title)
        
        // 1) Create + push the message via MeetingSync (no 'here' flag yet)
        // Local insert (instant UI)
        let msg = CachedMessage()
        msg.meeting           = cached
        msg.senderAppleUserID = myID
        msg.senderDisplayName = myDisplayName ?? ""
        msg.text              = trimmed
        msg.timestamp         = Date()
        msg.isDirty           = true
        modelContext.insert(msg)
        try? modelContext.save()
        dbg("sendMessage: local message inserted (dirty)")
        
        // Push message to CloudKit (if the meeting exists in CloudKit)
        if let rid = cached.ckRecordID {
            await cloud.pushMessagesToCloud(for: cached, meetingRecordID: rid, currentUserID: myID)
            dbg("sendMessage: pushed message to CloudKit rid=\(rid.recordName)")
        } else {
            dbg("sendMessage: no CKRecord yet; message will sync after meeting upload")
        }
        
        // 2) If this was "I'm Here", flip 'here', stop sharing, and push attendee
        if title == "I'm Here" {
            markImHereTapped()
        }
    }
    
    // Marks the current user as "here" for this meeting,
    // stops Core Location updates locally, clears coords/ETA in cache,
    // rebuilds the map, and pushes the attendee row to CloudKit with:
    //   here=true, latitude=0, longitude=0, eta=nil
    @MainActor
    func markImHereTapped() {

        guard let me = currentUserID else {
            dbg("[markImHereTapped] currentUserID=nil; aborting")
            return
        }

        // 1) Update local cached attendee row (instant UI)
        if let meRow = (cached.attendees ?? []).first(where: { $0.user?.appleUserID == me }) {
            meRow.here = true
            meRow.hereUpdatedAt = Date()
            meRow.etaMinutes = nil
            meRow.latitude = 0
            meRow.longitude = 0
            do {
                try modelContext.save();
            }
            catch {
                dbg("[markImHereTapped] Cache save failed:", error.localizedDescription)
            }
        } else {
            dbg("[markImHereTapped] No CachedAttendeeStatus row found for uid=\(me)")
        }

        // 2) Stop sharing my location locally (remove “You” pin)
        locationManager.stopUpdatingLocation()
        locationManager.allowsBackgroundLocationUpdates = false
        locationManager.pausesLocationUpdatesAutomatically = true
        userLocation = nil
        userETA = nil
        lastUploadAt = nil
        lastUploadCoord = nil
        // Don't update location
        suppressSelfLocation = true
        
        // Rebuild map now (others with here==true are already skipped; 'You' disappears since userLocation=nil)
        rebuildPlacesFromCache()

        // 3) Push attendee status to CloudKit (flip here, clear coords on server)
        guard let rid = meeting.recordID else {
            dbg("[markImHereTapped] Meeting has no CKRecord.ID yet; will be pushed after first upload.")
            return
        }
        let isOrganizer = (cached.attendees ?? []).first(where: { $0.user?.appleUserID == me })?.organizer ?? false

        Task { [weak cloud] in
            guard let cloud else { return }
            do {
                _ = try await cloud.upsertAttendeeStatus(
                    forMeetingRecordID: rid,
                    appleUserID: me,
                    displayName: nil,
                    imageData: nil,
                    organizer: isOrganizer,
                    here: true,
                    latitude: 0,        // explicitly clear on server
                    longitude: 0,
                    etaMinutes: nil,
                    deleted: nil
                )
            } catch {
                dbg("[markImHereTapped] Cloud push failed:", error.localizedDescription)
            }
        }
    }
    
    // Map CloudKit -> your AppErrorKind (no new cases)
    private func mapCKErrorToKind(_ ck: CKError) -> AppErrorKind {
        switch ck.code {
        case .notAuthenticated:
            return .noICloud
        case .quotaExceeded:
            return .quotaExceeded
        case .unknownItem, .zoneNotFound, .userDeletedZone:
            return .recordNotFound
        case .serviceUnavailable, .requestRateLimited:
            let retry = ck.userInfo[CKErrorRetryAfterKey] as? TimeInterval
            return .rateLimited(retry)        // AppErrorUI shows no popup by design
        case .networkUnavailable, .networkFailure:
            return .networkOffline            // AppErrorUI shows no popup by design
        default:
            return .genericCloud
        }
    }
}

private extension Meeting {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

// Toggle this to silence all logs quickly
private let DEBUG_LIVE_MEETING = false

private func dbg(_ items: Any..., fn: StaticString = #function) {
    guard DEBUG_LIVE_MEETING else { return }
    let prefix = "📍 LiveMeetingVM.\(fn)"
    print(prefix, items.map { String(describing: $0) }.joined(separator: " "))
}

private func fmt(_ c: CLLocationCoordinate2D?) -> String {
    guard let c else { return "nil" }
    return String(format: "%.5f, %.5f", c.latitude, c.longitude)
}



