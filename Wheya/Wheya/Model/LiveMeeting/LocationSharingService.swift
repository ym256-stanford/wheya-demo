//
//  LocationSharingService.swift
//  Wheya
//
//  Created by Yuliia Murakami on 9/19/25.
//

import Foundation
import CoreLocation
import MapKit
import SwiftData
import CloudKit
import UIKit
import Observation

@MainActor
@Observable
final class LocationSharingService: NSObject {
    static let shared = LocationSharingService()

    // Public state
    private(set) var authStatus: CLAuthorizationStatus = .notDetermined

    // Core Location
    private let manager = CLLocationManager()

    // Environment needed to push without UI
    struct Env {
        let modelContext: ModelContext
        let cloud: CloudKitManager
        let currentUserID: String
    }
    private var env: Env?

    // Active meeting we should share for (even with no screen)
    struct ActiveMeeting {
        let recordID: CKRecord.ID
        let title: String
        let venue: CLLocationCoordinate2D
        let start: Date
        let shareLeadMinutes: Int
    }
    private var active: ActiveMeeting?

    // Throttle
    private var lastUploadAt: Date?
    private var lastUploadCoord: CLLocationCoordinate2D?

    private override init() {
        super.init()
        manager.delegate = self
        manager.activityType = .otherNavigation
    }

    // MARK: - Wiring

    func configureEnvironment(modelContext: ModelContext, cloud: CloudKitManager, currentUserID: String?) {
        guard let currentUserID else { return }
        env = Env(modelContext: modelContext, cloud: cloud, currentUserID: currentUserID)
    }

    /// Minimal baseline tracking that keeps iOS able to wake us in the background.
    func startBaselineTracking() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            startCL(lowPower: true)
        default: break
        }
    }

    /// Require Always for your single-mode design.
    func ensureAlwaysAuthorization() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            manager.requestAlwaysAuthorization()
        case .authorizedAlways:
            // already good
            if manager.location == nil { startCL(lowPower: true) }
        default: break
        }
    }

    /// Called from AppDelegate when app is launched with `.location`.
    func resumeAfterLocationRelaunch() {
        ensureAlwaysAuthorization()
        startBaselineTracking()
        // If share window is already open, bump power right away:
        if isShareWindowOpen {
            bumpPower(high: true)
        }
    }

    /// Set/replace the meeting we should share in background.
    func setActiveMeeting(cached: CachedMeeting) {
        guard let rid = cached.ckRecordID else { return } // must exist on server
        active = ActiveMeeting(
            recordID: rid,
            title: cached.title,
            venue: CLLocationCoordinate2D(latitude: cached.latitude, longitude: cached.longitude),
            start: cached.date,
            shareLeadMinutes: cached.shareMinutes
        )
        ensureAlwaysAuthorization()
        // If Always is granted, we’ll be able to share even with no UI.
        startBaselineTracking()
        if isShareWindowOpen { bumpPower(high: true) }
    }

    func clearActiveMeeting() {
        active = nil
        // drop back to low power but keep baseline running
        bumpPower(high: false)
    }

    // MARK: - Internals

    private var shareStartDate: Date? {
        guard let a = active else { return nil }
        return a.start.addingTimeInterval(-TimeInterval(a.shareLeadMinutes * 60))
    }
    private var isShareWindowOpen: Bool {
        guard let s = shareStartDate else { return false }
        return Date() >= s
    }

    private func startCL(lowPower: Bool) {
        // Always-on flags
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = lowPower
        manager.desiredAccuracy = lowPower ? kCLLocationAccuracyHundredMeters : kCLLocationAccuracyBest
        manager.showsBackgroundLocationIndicator = !lowPower
        manager.startUpdatingLocation()
        // Also add SLC so the OS can relaunch us if killed
        if CLLocationManager.significantLocationChangeMonitoringAvailable() {
            manager.startMonitoringSignificantLocationChanges()
        }
    }

    private func bumpPower(high: Bool) {
        guard manager.authorizationStatus == .authorizedAlways ||
              manager.authorizationStatus == .authorizedWhenInUse else { return }
        if manager.delegate == nil { manager.delegate = self }
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = !high
        manager.desiredAccuracy = high ? kCLLocationAccuracyBest : kCLLocationAccuracyHundredMeters
        manager.showsBackgroundLocationIndicator = high
        if manager.location == nil { manager.requestLocation() }
    }

    /// Pushes the user’s coordinate to CloudKit for the active meeting (throttled).
    private func pushIfNeeded(coord: CLLocationCoordinate2D) {
        guard isShareWindowOpen,
              let env,
              let active,
              !env.currentUserID.isEmpty else { return }

        let now = Date()
        if let last = lastUploadAt, now.timeIntervalSince(last) < 10,
           let prev = lastUploadCoord {
            let d = CLLocation(latitude: prev.latitude, longitude: prev.longitude)
                .distance(from: CLLocation(latitude: coord.latitude, longitude: coord.longitude))
            if d < 15 { return } // throttle
        }

        // Local cache touch is optional here; background path focuses on CloudKit
        Task.detached { [env, active] in
            do {
                _ = try await env.cloud.upsertAttendeeStatus(
                    forMeetingRecordID: active.recordID,
                    appleUserID: env.currentUserID,
                    displayName: nil,
                    imageData: nil,
                    organizer: nil,
                    here: nil,
                    latitude: coord.latitude,
                    longitude: coord.longitude,
                    etaMinutes: nil,
                    deleted: nil
                )
            } catch {
                #if DEBUG
                print("[LocationSharingService] push failed:", error.localizedDescription)
                #endif
            }
        }

        lastUploadAt = now
        lastUploadCoord = coord
    }
}

// MARK: - CLLocationManagerDelegate
extension LocationSharingService: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didChangeAuthorization status: CLAuthorizationStatus) {
        Task { @MainActor in
            self.authStatus = status
            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                self.startCL(lowPower: !self.isShareWindowOpen)
            default: break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        guard let c = locations.last?.coordinate else { return }
        Task { @MainActor in
            // Upgrade power automatically when the window opens while we’re backgrounded
            if self.isShareWindowOpen { self.bumpPower(high: true) }
            self.pushIfNeeded(coord: c)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        #if DEBUG
        print("[LocationSharingService] CL error:", error.localizedDescription)
        #endif
    }
}

